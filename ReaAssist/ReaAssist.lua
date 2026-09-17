-- ============================================================================
-- launcher_template.lua - the source of the standard entrypoint launcher
-- ============================================================================
--
-- gen_launchers.lua turns this file into Dev/Launcher/build/ReaAssist.lua by
-- replacing the three EMBED lines below with the whole of launcher_core.lua,
-- launcher_lock.lua and reaper_host.lua, byte for byte. Nothing else changes,
-- so the shipped launcher is this file plus three chunks that are each tested
-- on their own.
--
-- The shipped path is an action identity and can never move:
--
--   Scripts/mbriggs-reaper/ReaAssist/ReaAssist.lua
--
-- CFG.VERSION compatibility marker: required by pre-1.5 updater verification.
--
-- ReaPack owns it, the in-app updater leaves it alone once it is owned, and
-- everything else lives under paths ReaPack has never seen (Distribution
-- Unification Plan, sections 2 and 3, decisions 10a.1 and 10a.2).
--
-- The Screen Reader entrypoint does NOT embed any of this. Decision 10a.4 has
-- it set its mode flag and delegate here, so there is one engine on disk and a
-- ReaPack sync that commits the two files in either order still lands a
-- coherent pair.
-- ============================================================================

local LAUNCHER_MODE = "standard"
local BODY_MAIN     = "ReaAssist.lua"
local TITLE         = "ReaAssist"

-- Set by the Screen Reader launcher immediately before it delegates here, and
-- cleared as soon as it is read so the body never inherits it.
if rawget(_G, "ReaAssist_LAUNCHER_MODE") == "sr" then
  LAUNCHER_MODE = "sr"
  BODY_MAIN     = "ReaAssist_Screen_Reader_Mode.lua"
  TITLE         = "ReaAssist - Screen Reader Mode"
end
rawset(_G, "ReaAssist_LAUNCHER_MODE", nil)

-- Paths, relative to the REAPER resource folder. Decision 10a.1 puts the whole
-- body under App/ and decision 10a.2 puts everything durable the launcher owns
-- under Recovery/, which is outside everything Factory Reset and the Temp
-- sweep clear and is removed by the uninstaller.
local HOME_REL      = "Scripts/mbriggs-reaper/ReaAssist/"
local BODY_REL      = HOME_REL .. "App/"
local RECOVERY_REL  = HOME_REL .. "Recovery/"
local PARKED_REL    = RECOVERY_REL .. "Body/"
local CANDIDATE_REL = RECOVERY_REL .. "Candidate/"
local WORK_REL      = RECOVERY_REL .. "Work"
local JOURNAL_REL   = RECOVERY_REL .. "launcher_journal.json"
local LOCK_REL      = RECOVERY_REL .. "launcher.lock"
local MANIFEST_REL  = BODY_REL .. "manifest.json"
-- Written by the in-app uninstaller before its authoritative gate finishes and
-- removed only by a deliberate yes below. It sits at the package root because
-- that is the one directory the uninstall never removes: Recovery/, the
-- launchers and App/ all go, and a ReaPack-owned launcher outlives all of them.
--
-- Its FIRST LINE is the phase. This exact text means the removal finished; any
-- other first line, and a file that will not open at all, means one is still
-- running or was interrupted. The body writes the same line and nothing else
-- may be read as it.
local MARKER_REL    = HOME_REL .. "ReaAssist_uninstalled.txt"
local MARKER_DONE   = "ReaAssist-uninstall: done"

local UPDATE_BASE  =
  "https://raw.githubusercontent.com/michaelbriggsaudio/mbriggs-reaper/main"
  .. "/ReaAssist/App/"
local MANIFEST_URL = UPDATE_BASE .. "manifest.json"
local PAYLOAD_BASE = UPDATE_BASE

-- Used only when App/manifest.json is missing or unreadable, which is the cold
-- install. It is the initial critical set from decision 10a.3, and it is a
-- floor rather than the definition: once a manifest exists, the manifest wins.
local FALLBACK_CRITICAL = {
  "ReaAssist.lua",
  "Resources/UI.lua",
  "Resources/Context.lua",
  "Resources/Diag.lua",
  "Resources/Engine.lua",
  "Resources/I18N.lua",
  "Resources/CodeRuntime.lua",
  "Resources/Relaunch.lua",
  "Resources/System_Prompt.md",
  "Resources/Prompts.md",
  "Resources/API_Ref.md",
}

local resource = reaper.GetResourcePath()
local sep = package.config:sub(1, 1)

local function at(rel)
  return resource .. sep .. rel:gsub("/", sep)
end

-- ---------------------------------------------------------------------------
-- BEGIN embedded launcher_core.lua
-- ---------------------------------------------------------------------------
local core = (function()
-- ============================================================================
-- launcher_core.lua - the launcher bootstrap engine (Phase A prototype)
-- ============================================================================
--
-- Both ReaAssist entrypoints become thin permanent launchers owned by ReaPack
-- (Distribution Unification Plan, sections 2 and 3). This chunk is what they
-- embed. It has to run when the application body is absent, so it may use
-- nothing the body provides: no ReaImGui, no Resources/*.lua, no JSON module,
-- no logger, no localization. Native dialogs and OSARA speech are the whole
-- user interface it gets.
--
-- It ships inside two rarely-updated files and every change to it is a bigger
-- deal than a body release, so every line here is a liability. Anything the
-- body can do once it exists does not belong in this file.
--
-- Every host touch goes through the injected `host` table. That is what lets
-- the identical text run under the stubbed host in Dev/Launcher/test and under
-- real REAPER in Phase B, and it is why there is no `reaper.` anywhere below.
--
-- Contract (see README.md):
--   local core = <this chunk>
--   core.configure(opts)       -> true | nil, message
--   core.resolve_pending()     -> nil | true, outcome | nil, kind, detail
--   core.probe()               -> "present" | "incomplete" | "absent"
--   core.restore(progress_cb)  -> true, detail | nil, kind, detail
--
-- resolve_pending comes before probe on every launch, including the fast path
-- that skips restore entirely. probe only asks whether the critical files
-- exist and are nonempty, so a crash that landed those but not the rest would
-- otherwise leave an unresolved journal behind a body that looks whole.
--
-- The chunk returns a table and declares only locals, so Phase B can paste it
-- verbatim inside `local core = (function() ... end)()`.
-- ============================================================================

local M = {}
local P = {}
local C = nil

-- What each state sounds like. Kept short on purpose: OSARA speaks these in
-- full and a cold bootstrap emits most of them back to back.
local SAY = {
  recovering  = "Finishing an interrupted installation step.",
  recovered   = "Interrupted installation step resolved.",
  probing     = "Checking the ReaAssist installation.",
  parked_check= "Checking the local backup copy.",
  parked_ok   = "Local backup copy verified.",
  parked_bad  = "Local backup copy is incomplete. Downloading instead.",
  manifest    = "Contacting the ReaAssist server.",
  downloading = "Downloading ReaAssist files.",
  verifying   = "Verifying downloaded files.",
  applying    = "Installing files.",
  confirming  = "Confirming the installation.",
  done        = "ReaAssist is ready.",
  failed      = "ReaAssist could not finish installing.",
}

-- Terminal failure text. The two the reviewer called out have to stay
-- distinguishable by reading alone: "we never reached the server, your disk is
-- untouched" and "the server answered with content we refused to trust".
local FAIL = {
  offline = "ReaAssist could not reach its server, so the missing files "
    .. "could not be downloaded.\n\nNothing on this computer was changed. "
    .. "Check the internet connection and start ReaAssist again.",
  unavailable = "The ReaAssist server answered but did not have the files "
    .. "this version needs.\n\nNothing on this computer was changed. Please "
    .. "try again in a little while.",
  busy = "The ReaAssist server is busy and kept asking ReaAssist to come "
    .. "back later, so the missing files could not be downloaded yet."
    .. "\n\nNothing on this computer was changed. The files are there; the "
    .. "server just could not send them right now. Start ReaAssist again in a "
    .. "few minutes.",
  verify = "The ReaAssist server supplied installation information or files "
    .. "that could not be verified, so ReaAssist refused to install them."
    .. "\n\nNothing was applied. Please try again later, or reinstall from "
    .. "https://reaassist.app",
  disk = "ReaAssist could not write the files it needs.\n\nAnything it had "
    .. "already changed was put back. Check that the REAPER resource folder "
    .. "is writable, then start ReaAssist again.",
  journal = "ReaAssist found an unfinished installation it could not resolve "
    .. "on this launch.\n\nSome files may already have been updated, so "
    .. "ReaAssist did not start rather than run a half-updated copy. Nothing "
    .. "further was changed.\n\nClose any other copies of REAPER and start "
    .. "REAPER again. If this keeps happening, reinstall from "
    .. "https://reaassist.app, which replaces the whole application and "
    .. "clears the unfinished installation.",
  incomplete = "ReaAssist installed its files but they still did not pass "
    .. "the launch check.\n\nThe previous state was put back. Please "
    .. "reinstall from https://reaassist.app",
  config = "ReaAssist could not start its installer.",
}

-- Resolution outcomes that permit running the body. This is a safe-list, not a
-- list of failures, and deliberately so: twice in this engine's review history
-- a state was argued to be unreachable and was not, so an outcome nobody
-- thought about here has to fail closed rather than launch on a transaction
-- nobody classified.
local SAFE_OUTCOMES = {
  finished = true, forward = true, rollback = true,
  cleanup_deferred = true, rollback_deferred = true,
}

local HOST_SEAMS = {
  "message_box", "announce", "exec", "read_file", "write_file",
  "file_size", "present", "make_dir", "remove", "rename", "sleep", "os_name",
}

-- The canonical manifest, and the one name in this engine that means the same
-- thing at three roots: it is what a parked copy is read from, it is what the
-- server is asked for, and it is what the body is left holding at
-- <body root>/manifest.json when a restore finishes (decision 10a.1, plan
-- section 3b migration rule 2).
--
-- Installing it is the whole of the B2.1c amendment. Before it, a restore read
-- the fetched manifest out of the attempt that won, deleted it, and applied
-- only the entries inside it, and a manifest cannot list itself: the body's
-- updater refuses a self-entry, and a file whose bytes contain their own
-- sha256 is not a thing that can be generated. So a fresh website or skip-N
-- bootstrap finished with no canonical manifest at all, which leaves the
-- launcher pinned to its built-in fallback critical list for the life of the
-- install and leaves the body with no record of what it is or what it holds.
--
-- It is installed as an ordinary entry of the same transaction rather than
-- through a path of its own. Everything the journal is authoritative for then
-- covers it unchanged: three generations, verified before promoted, unchanged
-- files never touched, cleanup that stops at the first refusal, and safe-list
-- outcomes. The name is body-root-relative like every other entry, so nothing
-- downstream has to know this file is special.
local MANIFEST_NAME = "manifest.json"

-- ----------------------------------------------------------------------------
-- Paths
-- ----------------------------------------------------------------------------
-- Manifest names are forward-slash relative, matching manifest.json. Every
-- local path is built here so the separator conversion happens in one place.

function P.path(root, name)
  if C.sep ~= "/" then name = name:gsub("/", C.sep) end
  return root .. name
end

function P.parent(path)
  return path:match("^(.*)[\\/][^\\/]+$")
end

function P.ensure_parent(path)
  local parent = P.parent(path)
  if parent and parent ~= "" then C.host.make_dir(parent) end
end

function P.exists(path)
  -- An unreadable path still needs recovery and cleanup accounting.
  return C.host.present(path) ~= false
end

-- Filename allowlist, trimmed from Updater.is_safe_filename. Manifest names
-- reach a curl command line and a local path, so they are checked before they
-- are used, not after. Server content is never trusted to be well behaved.
--
-- The absence of the tilde from this list is load bearing several call sites
-- away: it is what keeps every name this engine reserves for its own working
-- files outside the namespace a validated name can spell. There are three of
-- them and they are spelled in exactly three places:
--
--   P.attempt_dest  <slot>~dl~<run token>~<attempt>  where a download lands
--   P.bak_path      <dest>~bak                       an original moved aside
--   P.staged_path   <dest>~new                       a cross-volume sibling
--
-- Widening this list to admit a tilde would hand a hostile or careless manifest
-- the path another entry's attempt is being written into, or the backup and the
-- staging sibling of another entry's destination. There is a row for each.
function P.safe_name(name)
  if type(name) ~= "string" or name == "" then return false end
  if not name:match("^[A-Za-z0-9_./ %-]+$") then return false end
  if name:match("^/") or name:match("^%a:") then return false end
  if name:find("\\", 1, true) then return false end
  for segment in (name .. "/"):gmatch("([^/]*)/") do
    if segment == "" or segment == "." or segment == ".." then return false end
    if segment:sub(1, 1) == "." then return false end
    if segment:sub(1, 1) == " " or segment:sub(-1) == " " then return false end
  end
  return true
end

-- Percent-encode a manifest name on its way into a URL, segment by segment.
-- safe_name has already refused everything except letters, digits, underscore,
-- dot, slash, space and hyphen, so the only character this has to encode today
-- is the space, and no shipped name has one. Encoding the whole complement of
-- the unreserved set anyway means a later widening of safe_name cannot quietly
-- start producing invalid URLs, which is the shape of defect this engine keeps
-- finding: a guard one call site away from the thing it was reasoned about.
-- The separators stay literal because they are path structure rather than data,
-- and safe_name has already refused every traversal they could express.
function P.url_path(name)
  return (name:gsub("[^A-Za-z0-9%-%._~/]", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

-- Two entries that land on one path are refused wherever they appear. The
-- second one would treat the first one's freshly made ~bak as a leftover from
-- an older transaction and delete it through the same landing logic, so the
-- backup would be gone while the file it protects is still being replaced.
-- Names are compared case-folded because the Windows filesystem is, and a file
-- list that needs two spellings of one path is wrong on every platform.
function P.claim_name(seen, name)
  local key = name:lower()
  if seen[key] then return false end
  seen[key] = true
  return true
end

-- ----------------------------------------------------------------------------
-- Announcements and progress
-- ----------------------------------------------------------------------------
-- Every state transition goes to OSARA and to progress_cb. Per-file progress
-- goes only to progress_cb: a Screen Reader user does not want each of forty
-- filenames read out, and the surrounding state already told them what is
-- happening.

function P.title()
  return (C.mode == "sr") and "ReaAssist - Screen Reader Mode" or "ReaAssist"
end

function P.emit(state, detail)
  local text = SAY[state] or state
  if state == "downloading" or state == "applying" then
    text = text .. " " .. tostring(detail or 0) .. " files."
  end
  local prefix = (C.mode == "sr")
    and "ReaAssist Screen Reader Mode: " or "ReaAssist: "
  pcall(C.host.announce, prefix .. text)
  if C.progress then
    pcall(C.progress, {
      state = state, detail = detail, mode = C.mode, text = text,
    })
  end
end

function P.progress_file(index, total, name)
  if not C.progress then return end
  pcall(C.progress, {
    state = "file", index = index, total = total, detail = name, mode = C.mode,
  })
end

function P.fail(kind, detail)
  P.emit("failed", detail)
  local text = FAIL[kind] or FAIL.disk
  if detail and detail ~= "" then
    text = text .. "\n\nDetail: " .. tostring(detail)
  end
  pcall(C.host.message_box, text, P.title())
  return nil, kind, detail
end

-- ----------------------------------------------------------------------------
-- JSON: decode only
-- ----------------------------------------------------------------------------
-- Enough of the format to read a manifest and a journal. The journal is
-- written by hand below, so there is no encoder here.

function P.json_decode(text)
  local pos = 1
  local value
  local function fail(msg) error(msg .. " at " .. pos, 0) end
  local function skip()
    while true do
      local c = text:sub(pos, pos)
      if c == " " or c == "\t" or c == "\r" or c == "\n" then
        pos = pos + 1
      else
        return
      end
    end
  end
  local function str()
    pos = pos + 1
    local out = {}
    while pos <= #text do
      local c = text:sub(pos, pos)
      if c == '"' then pos = pos + 1 return table.concat(out) end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        pos = pos + 2
        if e == "n" then out[#out + 1] = "\n"
        elseif e == "t" then out[#out + 1] = "\t"
        elseif e == "r" then out[#out + 1] = "\r"
        elseif e == "u" then
          local cp = tonumber(text:sub(pos, pos + 3), 16) or 63
          pos = pos + 4
          out[#out + 1] = (cp < 128) and string.char(cp) or "?"
        else out[#out + 1] = e end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    fail("unterminated string")
  end
  value = function()
    skip()
    local c = text:sub(pos, pos)
    if c == '"' then return str() end
    if c == "{" then
      pos = pos + 1
      local t = {}
      skip()
      if text:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        skip()
        if text:sub(pos, pos) ~= '"' then fail("expected a key") end
        local key = str()
        skip()
        if text:sub(pos, pos) ~= ":" then fail("expected a colon") end
        pos = pos + 1
        t[key] = value()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then fail("expected a comma") end
      end
    end
    if c == "[" then
      pos = pos + 1
      local t = {}
      skip()
      if text:sub(pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = value()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then fail("expected a comma") end
      end
    end
    if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
    if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
    if text:sub(pos, pos + 3) == "null" then pos = pos + 4 return false end
    local num = text:match("^%-?%d+%.?%d*", pos)
    if num and #num > 0 then pos = pos + #num return tonumber(num) end
    fail("unexpected character")
  end
  local ok, result = pcall(value)
  if not ok then return nil, tostring(result) end
  return result
end

function P.json_string(s)
  s = tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    :gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. s .. '"'
end

-- ----------------------------------------------------------------------------
-- Manifests
-- ----------------------------------------------------------------------------

-- The immutable payload reference. Optional today; work package C makes it
-- mandatory before release N.
--
-- The payload base points at a branch, and GitHub's raw CDN serves payloads
-- stale for minutes after a release push, so a cold bootstrap in that window
-- can read the new manifest and download the old bytes. Per-file verification
-- refuses them, which is safe, but what the user is told is that their
-- checksums did not match. A manifest that names the commit it was generated
-- from selects the payload that matches it, so even a manifest cached for a
-- month pairs with the payload it describes.
--
-- Validated to exactly what a git object name is and nothing else, because it
-- is interpolated into a URL: forty lowercase hex characters. Anything else,
-- including a JSON null (which this decoder reads as false rather than as
-- absent), takes the whole manifest down with it. There is no lenient path,
-- because a lenient path is one that interpolates somebody else's text into
-- the base every payload is fetched from.
function P.payload_ref(value)
  if type(value) ~= "string" then return nil end
  if #value ~= 40 or not value:match("^[0-9a-f]+$") then return nil end
  return value
end

-- Substitute the ref segment of a raw payload base. The shape is GitHub's and
-- it is fixed: https://host/<owner>/<repo>/<ref>/<path...>. A base with no ref
-- segment to replace returns nil and the caller fails closed, because a
-- manifest that named a commit and got the branch anyway is the exact pairing
-- this exists to prevent.
function P.base_at_ref(base, ref)
  local head, tail = base:match("^(https?://[^/]+/[^/]+/[^/]+/)[^/]+/(.*)$")
  if not head then return nil end
  return head .. ref .. "/" .. tail
end

function P.parse_manifest(text)
  local data = P.json_decode(text)
  if type(data) ~= "table" or type(data.files) ~= "table" then return nil end
  local ref = nil
  if data.payload_ref ~= nil then
    ref = P.payload_ref(data.payload_ref)
    if not ref then return nil end
  end
  local files, seen = {}, {}
  -- The manifest's own destination is claimed before any entry can ask for it.
  -- This transaction installs the manifest at that path itself, so an entry
  -- naming it would be a second claimant for one destination, which is the
  -- state claim_name exists to refuse: the second entry would treat the first
  -- one's fresh ~bak as a leftover and delete it. It is refused rather than
  -- reconciled because there is nothing to reconcile. A manifest cannot carry
  -- a truthful checksum of itself, so an entry with this name is either a
  -- mistake or an attempt to substitute different bytes for the ones this
  -- launcher just parsed and verified every payload against.
  P.claim_name(seen, MANIFEST_NAME)
  for _, entry in ipairs(data.files) do
    if type(entry) ~= "table" or type(entry.name) ~= "string"
        or type(entry.sha256) ~= "string" then
      return nil
    end
    if not P.safe_name(entry.name) then return nil end
    if not P.claim_name(seen, entry.name) then return nil end
    files[#files + 1] = { name = entry.name, sha256 = entry.sha256:lower() }
  end
  if #files == 0 then return nil end
  return files, tostring(data.version or "?"), ref
end

-- Returns the parsed file list, the version, the payload ref, and the EXACT
-- bytes that produced them. The bytes are the fourth return rather than a
-- second read, because the copy that gets installed has to be the copy that
-- was parsed: a re-read is a different moment and a re-serialisation is a
-- different file.
function P.read_manifest(path)
  local text = C.host.read_file(path)
  if not text or text == "" then return nil end
  local files, version, ref = P.parse_manifest(text)
  if not files then return nil end
  return files, version, ref, text
end

-- A manifest that does not carry every critical file is rejected before
-- anything is copied rather than after everything has been. This is stricter
-- than probe() strictly requires: a body that already holds one of those files
-- could pass the launch check without the manifest listing it. Refusing is
-- still the right direction, because the alternative is a body assembled from
-- a source that never claimed to be complete.
function P.covers_critical(files)
  local have = {}
  for _, f in ipairs(files) do have[f.name] = true end
  for _, name in ipairs(C.critical) do
    if not have[name] then return false end
  end
  return true
end

-- ----------------------------------------------------------------------------
-- Hashing and downloading
-- ----------------------------------------------------------------------------
-- Both shell out, exactly like the website installer does at this same
-- dependency level. host.exec returns REAPER's ExecProcess contract: the exit
-- code, a newline, then the captured output.

-- A name no other launcher run can produce. It reaches a file name, so it is
-- constrained to what this engine puts in one: an offered value that is not
-- letters, digits and hyphens is refused and a fresh one minted rather than
-- sanitised into something two runs could arrive at from different inputs.
-- os.time pins the second, math.random is seeded per process by Lua 5.4 itself,
-- and the address of a fresh table is unique inside this process and varies
-- between processes under address space layout randomisation.
function P.run_token(value)
  if type(value) == "string" and value:match("^[%w%-]+$") then return value end
  local addr = tostring({}):match("[x%x]+$") or "0"
  return string.format("%d-%d-%s", os.time(),
    math.random(1, 2147483647), addr)
end

function P.hash_file(path)
  local os_name = C.host.os_name() or ""
  local cmd
  if os_name:match("^Win") then
    cmd = 'certutil -hashfile "' .. path .. '" SHA256'
  elseif os_name:match("OSX") or os_name:match("macOS") then
    cmd = "/usr/bin/shasum -a 256 '" .. path:gsub("'", "'\\''") .. "'"
  else
    cmd = "sha256sum '" .. path:gsub("'", "'\\''") .. "'"
  end
  local out = C.host.exec(cmd, 30000)
  if not out then return nil end
  if tonumber(out:match("^(%-?%d+)")) ~= 0 then return nil end
  for token in out:gmatch("%x+") do
    if #token == 64 then return token:lower() end
  end
  return nil
end

-- Only the manifest is cache-busted. Payload files are verified against the
-- manifest hash, so a stale cached payload fails verification instead of
-- being installed; a stale cached manifest would be believed.
function P.bust(url)
  C.nonce = (C.nonce or 0) + 1
  local sep = url:find("?", 1, true) and "&" or "?"
  return url .. sep .. "cb=" .. tostring(os.time()) .. "-" .. tostring(C.nonce)
end

function P.download(url, dest)
  local os_name = C.host.os_name() or ""
  local is_mac = os_name:match("OSX") or os_name:match("macOS")
  -- macOS: REAPER-launched scripts do not reliably inherit PATH.
  local curl = is_mac and "/usr/bin/curl" or "curl"
  -- -f collapses every HTTP status of 400 or above into exit 22, which cannot
  -- tell a 404 from a 503. --write-out puts the real status into the captured
  -- output so the classification below can read it; the marker is there
  -- because curl's own error text shares that stream.
  local cmd = string.format(
    '%s -fsSL --connect-timeout 10 --max-time 120 '
    .. '-w "reaassist_http=%%{http_code};" -o "%s" "%s"',
    curl, dest, url)
  local out = C.host.exec(cmd, 180000)
  if not out then
    return nil, "offline", "curl could not be launched"
  end
  local code = tonumber(out:match("^(%-?%d+)"))
  if code == 0 then return true end
  local status = tonumber(out:match("reaassist_http=(%d+)")) or 0
  if status >= 400 then
    -- The server answered. 408, 429 and 5xx are it asking us to come back, so
    -- they ride the same bounded retry a transport failure gets. Every other
    -- 4xx is a definite answer and is refused now.
    if status == 408 or status == 429 or status >= 500 then
      return nil, "busy", "the server answered " .. status .. " for " .. url
    end
    return nil, "unavailable", "the server answered " .. status .. " for " .. url
  end
  if code == 22 then
    -- An HTTP error whose status did not come back. Treated as the definite
    -- answer it usually is rather than retried blind.
    return nil, "unavailable", "the server had no file at " .. url
  end
  return nil, "offline", "curl exit " .. tostring(code)
end

-- Bounded retries. "offline" is no answer at all and "busy" is the server
-- asking us to come back; both are worth asking again. A 404 and a checksum
-- mismatch are the server telling us something true, so asking three times
-- does not change it.
function P.retry(fn)
  local kind, detail
  for attempt = 1, C.retries do
    local ok
    ok, kind, detail = fn(attempt)
    if ok then return true end
    if kind ~= "offline" and kind ~= "busy" then break end
    if attempt < C.retries then C.host.sleep(C.backoff * attempt) end
  end
  -- "busy" keeps its own dialog to the end. A server that spent the whole
  -- budget saying come back later is a different sentence from a server that
  -- did not have the file, and telling the user the wrong one sends them
  -- looking for a problem that is not theirs.
  return nil, kind, detail
end

-- Where one download attempt is allowed to land, and nowhere else.
--
-- The engine stops waiting for a command it cannot see the end of, and that
-- command keeps running: host.exec returns nil when the done marker never
-- arrives, and the curl behind it goes on writing for as long as --max-time
-- allows. So the destination an attempt was given is a path that may still be
-- growing after the attempt is over, and nothing may ever read, hash or promote
-- it: not the next attempt of this run, and not the next launcher, whose
-- attempt numbers start again at one. The run token separates the launchers and
-- the attempt number separates the attempts, and neither is enough on its own.
--
-- The tilde is the third load-bearing part, and it is what makes this namespace
-- disjoint from every name a manifest or a journal can carry. safe_name permits
-- letters, digits, underscore, dot, slash, space and hyphen and nothing else, so
-- a name with a tilde in it is refused before it can reach P.path, and no
-- validated name can therefore produce the path an attempt was given. The suffix
-- used to be ".dl." plus the token and the attempt, every character of which
-- safe_name permits: a hostile or corrupt entry could spell one of these paths
-- and hand the engine a staging slot an abandoned curl was still writing to.
-- Structural disjointness rather than a token that is hard to guess.
function P.attempt_dest(slot, attempt)
  return slot .. "~dl~" .. C.run_token .. "~" .. tostring(attempt)
end

-- One download with the bounded retries above, each attempt into a destination
-- of its own. Returns the path the winning attempt wrote to, or nil plus the
-- failure the retries ended on.
function P.fetch(url_of, slot)
  local won
  local ok, kind, detail = P.retry(function(attempt)
    local dest = P.attempt_dest(slot, attempt)
    local got, k, d = P.download(url_of(attempt), dest)
    if got then
      won = dest
    else
      -- Best effort, and nothing rests on it: a command this launcher gave up
      -- on may hold the file open, and a path carrying this run's token and a
      -- spent attempt number is read by nobody whether it goes or not.
      C.host.remove(dest)
    end
    return got, k, d
  end)
  if not ok then return nil, kind, detail end
  return won
end

-- Move a finished download into the staging slot the rest of the engine names.
-- The slot has to exist under a name recovery can rebuild from the journal,
-- which an attempt destination cannot be, and it is never handed to a command,
-- so this rename is the only writer it ever has.
function P.stage_download(src, slot)
  C.host.remove(slot)  -- Windows os.rename refuses to clobber.
  if not C.host.rename(src, slot) then return false end
  return true
end

-- ----------------------------------------------------------------------------
-- The candidate directory
-- ----------------------------------------------------------------------------
-- Both restore paths land here first, so there is exactly one apply. The
-- parked copy is COPIED in (it has to survive the run); downloads are written
-- straight in. Nothing leaves this directory until every file in it has been
-- hashed against the manifest.

function P.clear_candidate(files)
  for _, f in ipairs(files) do
    C.host.remove(P.path(C.candidate_root, f.name))
  end
end

function P.fill_candidate(source_root, files)
  for _, f in ipairs(files) do
    local dest = P.path(C.candidate_root, f.name)
    P.ensure_parent(dest)
    C.host.remove(dest)
    local data = C.host.read_file(P.path(source_root, f.name))
    if not data then return nil, "missing file: " .. f.name end
    if not C.host.write_file(dest, data) then
      return nil, "could not stage " .. f.name
    end
  end
  return true
end

-- Stage the canonical manifest into the candidate as the last entry of the
-- transaction, from the bytes that were parsed rather than from a re-read or a
-- re-serialisation. Both sources arrive here the same way: the network path
-- holds the bytes the winning attempt returned, and the parked path holds the
-- bytes it read out of the parked copy.
--
-- **Why last.** The manifest is the completion marker for the body it
-- describes, so it is published only after every file it names has landed. A
-- crash between the two is not a state anybody has to survive by inspection:
-- the entry is in the journal, the staged copy is in the candidate, and
-- recovery rolls the transaction forward and lands it, or rolls it back and
-- puts the previous manifest back with the previous body. The ordering matters
-- for the case where the journal itself is unreadable and the launch is
-- refused: what is on disk then is a body with the manifest of the version
-- that was there before, or no manifest at all on a cold install, and never a
-- manifest that advertises files the body does not have. Landing it first
-- would invert exactly that: an interrupted install would leave a manifest
-- naming files nothing installed, which the body's own updater and the per-tick
-- sentinel both read as truth.
--
-- The checksum is derived here rather than carried in from outside, because
-- there is nowhere outside to carry it from. It is not a second opinion on the
-- manifest's authenticity: these bytes are the root of trust every payload was
-- just verified against, and hashing them adds no assumption that was not
-- already made when they were parsed. What it is for is everything downstream
-- that reads a journal entry's sha256: the unchanged-file skip, the
-- disambiguation of the backup window, and the promotion's hash immediately
-- before the rename. Those need a checksum of the bytes about to be published,
-- which is what this is.
function P.stage_manifest(files, text)
  local slot = P.path(C.candidate_root, MANIFEST_NAME)
  P.ensure_parent(slot)
  C.host.remove(slot)
  if type(text) ~= "string" or text == "" then
    return nil, "the manifest could not be staged"
  end
  if not C.host.write_file(slot, text) then
    return nil, "could not stage " .. MANIFEST_NAME
  end
  local sha = P.hash_file(slot)
  if not sha then return nil, "could not hash " .. MANIFEST_NAME end
  files[#files + 1] = { name = MANIFEST_NAME, sha256 = sha }
  return true
end

-- Returns nil when every file matches, or the first offending name. Hashing
-- happens here and only here, at the moment of use: a parked copy verified
-- last month proves nothing about the bytes on disk right now.
function P.verify_candidate(files)
  for _, f in ipairs(files) do
    if P.hash_file(P.path(C.candidate_root, f.name)) ~= f.sha256 then
      return f.name
    end
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- The journal
-- ----------------------------------------------------------------------------
-- A scaled-down sibling of the updater's journal: same write-then-act
-- discipline, three phases instead of the full set. Written before the first
-- live file moves and after every landing, so an interruption at any point
-- resolves in one direction only.
--
-- Replacement keeps three generations, because the naive write-remove-rename
-- destroys the only good copy for the length of the rename. That window is not
-- confined to the first write: every replacement removes the primary, so a
-- launch that tears a .tmp inside that window is left with no journal at all
-- while live files have already moved. Recovery then reports "nothing to do"
-- and the evidence of a half-applied body is gone.
--
-- Falling back to an older generation is safe because every journal write
-- happens before the act it describes, so an older journal can only
-- under-claim. What the files on disk can re-derive is narrower than it looks,
-- though: only per-file status, and only where the bytes on the two sides
-- differ. The journal stays authoritative for the direction of the
-- transaction, for whether a backup was ever made, and for files whose bytes
-- are identical on both sides, none of which a destination hash can answer.

function P.journal_text(j)
  local parts = {}
  for _, f in ipairs(j.files) do
    parts[#parts + 1] = string.format(
      '{"name":%s,"sha256":%s,"status":%s,"bak_existed":%s,"dest_existed":%s}',
      P.json_string(f.name), P.json_string(f.sha256), P.json_string(f.status),
      f.bak_existed and "true" or "false",
      f.dest_existed and "true" or "false")
  end
  return string.format(
    '{"schema":1,"phase":%s,"source":%s,"version":%s,"candidate":%s,'
    .. '"files":[%s]}',
    P.json_string(j.phase), P.json_string(j.source), P.json_string(j.version),
    P.json_string(j.candidate), table.concat(parts, ","))
end

function P.journal_write(j)
  local text = P.journal_text(j)
  local tmp, old = C.journal_path .. ".tmp", C.journal_path .. ".old"
  P.ensure_parent(tmp)
  -- A failed rotation can leave .tmp as the only readable recovery record.
  -- Preserve its exact bytes in .old before reusing the staging path. A failed
  -- copy leaves .tmp untouched; a failed subsequent write leaves .old intact.
  if P.exists(tmp) then
    local prior = C.host.read_file(tmp)
    if prior and P.journal_valid(P.json_decode(prior))
        and not P.journal_valid(P.json_decode(C.host.read_file(C.journal_path) or ""))
        and not P.journal_valid(P.json_decode(C.host.read_file(old) or "")) then
      if not C.host.write_file(old, prior) or C.host.read_file(old) ~= prior then
        return false
      end
    end
  end
  C.host.remove(tmp)
  if not C.host.write_file(tmp, text) then
    C.host.remove(tmp)
    return false
  end
  -- Read it back before it can become the generation recovery trusts. A write
  -- that returned success and left something unreadable is exactly the case
  -- the generations exist for, and finding it here costs one small read.
  if not P.journal_valid(P.json_decode(C.host.read_file(tmp) or "")) then
    C.host.remove(tmp)
    return false
  end
  if P.exists(C.journal_path) then
    -- Windows os.rename refuses to clobber, so a stale .old goes first. If it
    -- will not go, the rename fails and so does this write: proceeding would
    -- mean removing the primary with nowhere to put it. The rename's own
    -- result is the proof here, which is why the removal is not checked twice.
    if P.exists(old) then C.host.remove(old) end
    if not C.host.rename(C.journal_path, old) then return false end
  end
  if not C.host.rename(tmp, C.journal_path) then
    -- Both the .old and the complete .tmp are still on disk and journal_read
    -- reads either, so a failed swap costs nothing. Deleting one here is what
    -- would strand the transaction.
    return false
  end
  -- The displaced generation has to be proven gone, not asked to go. Nothing
  -- downstream rereads it deliberately, but journal_read will read it if the
  -- primary ever becomes unreadable, and by then it predates every backup
  -- claim made since it was current: the window closer would call a replaced
  -- file unchanged, and the rollback would then walk past both the
  -- replacement and its real ~bak and still report a clean undo. So a stale
  -- .old is a failed write, for the same reason the rotation above is.
  if P.exists(old) then
    C.host.remove(old)
    if P.exists(old) then return false end
  end
  return true
end

-- The journal drives file removal, renames and restores, so it is checked the
-- same way a server manifest is: every field for shape, every name through
-- safe_name, and the staging path constrained to the configured root. A
-- corrupt or hostile journal must not be able to reach outside them.
-- Returns the journal, or nil plus the reason it was refused.
function P.journal_valid(data)
  if type(data) ~= "table" or data.schema ~= 1 then
    return nil, "the installation journal is not in a format this launcher knows"
  end
  if data.phase ~= "applying" and data.phase ~= "committed"
      and data.phase ~= "rolling_back" and data.phase ~= "rolled_back" then
    return nil, "the installation journal names an unknown phase"
  end
  if type(data.source) ~= "string" or type(data.version) ~= "string"
      or type(data.candidate) ~= "string" then
    return nil, "the installation journal is missing its transaction fields"
  end
  -- Recovery reads from this path and deletes inside it. The prefix test is
  -- paired with the dot-dot test because a prefix alone can be walked back out
  -- of the root it just matched.
  if data.candidate:find("..", 1, true)
      or data.candidate:sub(1, #C.candidate_root) ~= C.candidate_root then
    return nil, "the installation journal points outside the staging folder"
  end
  if type(data.files) ~= "table" or #data.files == 0 then
    return nil, "the installation journal lists no files"
  end
  local seen = {}
  for _, f in ipairs(data.files) do
    if type(f) ~= "table" then
      return nil, "the installation journal has a malformed entry"
    end
    if not P.safe_name(f.name) then
      return nil, "the installation journal names a file the launcher will "
        .. "not touch"
    end
    if not P.claim_name(seen, f.name) then
      return nil, "the installation journal lists one file twice"
    end
    if type(f.sha256) ~= "string" or #f.sha256 ~= 64
        or not f.sha256:match("^%x+$") then
      return nil, "the installation journal has a malformed checksum"
    end
    if f.status ~= "pending" and f.status ~= "applied"
        and f.status ~= "unchanged" then
      return nil, "the installation journal has an unknown file status"
    end
    if type(f.bak_existed) ~= "boolean"
        or type(f.dest_existed) ~= "boolean" then
      return nil, "the installation journal has a malformed backup record"
    end
  end
  return data
end

-- Newest generation first: the primary, then the one it displaced, then the
-- one that was replacing it. Returns the journal, plain nil when not one of
-- the three exists, or nil plus a reason when at least one exists and none
-- validates. That last case fails closed and keeps every file: a journal
-- nobody can read is also a body nobody can vouch for, and deleting it would
-- throw away the only evidence that files had already moved.
function P.journal_read()
  local generations = {
    C.journal_path, C.journal_path .. ".old", C.journal_path .. ".tmp",
  }
  local any = false
  for _, path in ipairs(generations) do
    if P.exists(path) then
      any = true
      local data = P.journal_valid(P.json_decode(C.host.read_file(path) or ""))
      -- No promotion to the primary path. The next successful write rotates
      -- the generations anyway, and journal_delete clears all three, so
      -- moving files here would only add a step that can itself fail.
      if data then return data end
    end
  end
  if not any then return nil end
  return nil, "the installation journal could not be read"
end

-- Three answers, because a journal nobody could delete is still authoritative
-- on the next launch and the callers need to know which one survived:
--   "gone"     every generation is deleted and the transaction is closed
--   "primary"  only the current record survives, which still says the
--              transaction is over; the next launch reads it and retries
--   "stale"    an older generation would not go, so the current record is
--              KEPT and the caller must not permit a launch
--
-- Order and the early return are both load-bearing, and the reachable case is
-- worth spelling out because it is not obvious. A terminal write whose final
-- proof fails leaves the primary holding the terminal phase and .old holding
-- the pre-terminal one, both readable, and returns false; that launch refuses.
-- The launch after it reads the terminal primary and arrives here. Walking on
-- past a failed .old to delete a removable primary would leave the
-- pre-terminal generation as the only thing on disk, and the launch after THAT
-- would redo a rollback that had already finished, over whatever had been
-- installed in between. Deleting the authoritative record while a contradictory
-- one survives is the worst thing this function can do, so it stops instead.
function P.journal_delete()
  for _, path in ipairs({ C.journal_path .. ".tmp", C.journal_path .. ".old" }) do
    if P.exists(path) then
      C.host.remove(path)
      if P.exists(path) then return "stale" end
    end
  end
  if P.exists(C.journal_path) then
    C.host.remove(C.journal_path)
    if P.exists(C.journal_path) then return "primary" end
  end
  return "gone"
end

-- ----------------------------------------------------------------------------
-- Apply, rollback, recovery
-- ----------------------------------------------------------------------------

-- The two working names a transaction needs beside a live file, and the only
-- two places either one is spelled. Every construction site goes through here:
-- the apply, the rollback, the recovery walk and the cleanup, so the suffix
-- cannot fork between the code that creates one of these files and the code
-- that goes looking for it later.
--
-- Both carry the same tilde P.attempt_dest does, for the same reason and after
-- the same finding one class along. safe_name permits letters, digits,
-- underscore, dot, slash, space and hyphen, so ".bak" and ".new" were legal
-- manifest name fragments from end to end: a manifest listing both "X" and
-- "X.bak" got both files installed, and then commit's cleanup for entry X
-- deleted the one it had just landed for the second entry. What that can damage
-- is only ever files the manifest itself asked for, which is a smaller reach
-- than the attempt destinations had, and it is the same defect: a name this
-- engine reserves sitting inside the namespace it is reserved against. The
-- tilde puts it outside by construction, so nothing has to keep being true.
--
-- Neither path is ever recorded. The journal stores the destination name and
-- the flags, and both names are rebuilt from the destination wherever they are
-- needed, so there is no stored form to migrate when the spelling changes.
function P.bak_path(dest) return dest .. "~bak" end
function P.staged_path(dest) return dest .. "~new" end

-- A live file is only ever replaced by a rename inside its own directory.
-- When the candidate root sits on another volume the rename cannot cross it,
-- so the bytes are staged as a sibling, hashed there, and renamed in. Copying
-- the candidate straight over the destination would leave a window where the
-- live file is half written and the candidate is still present, which recovery
-- would read as an original worth backing up: the real backup would be
-- overwritten by the copy that replaced it.
function P.move(src, dest, sha256)
  -- Proven immediately before the rename, on this route and on the one below,
  -- so a rename into a live path can only ever publish bytes that were checked
  -- a statement ago. The candidate was hashed once already, when the whole of
  -- it was verified before anything live was touched, and that check is minutes
  -- and a whole transaction older than this one: it says the download was good,
  -- not that these are still the bytes about to be published.
  --
  -- What could write to `src` between the two is now nothing. Downloads land at
  -- attempt destinations (see P.attempt_dest), whose tilde no validated name can
  -- spell, the same tilde that keeps the two names beside a live file (see
  -- P.bak_path and P.staged_path) out of reach as well, and they reach this path
  -- only through a rename this instance performs, so no command any launcher
  -- started is writing here, whatever the manifest
  -- asked for. The one writer left is this instance itself, one mutation
  -- past a revoked fence, which is the cooperative residual README.md bounds.
  if sha256 and P.hash_file(src) ~= sha256 then return false end
  if C.host.rename(src, dest) then return true end
  local staged = P.staged_path(dest)
  C.host.remove(staged)
  local data = C.host.read_file(src)
  if not data then return false end
  if not C.host.write_file(staged, data) then
    C.host.remove(staged)
    return false
  end
  -- Verified before it is promoted, so the rename can only ever publish bytes
  -- that already match the manifest.
  if sha256 and P.hash_file(staged) ~= sha256 then
    C.host.remove(staged)
    return false
  end
  C.host.remove(dest)  -- Windows os.rename refuses to clobber.
  if not C.host.rename(staged, dest) then
    C.host.remove(staged)
    return false
  end
  C.host.remove(src)
  return true
end

-- Delete a backup and prove it is gone. host.remove's return value is
-- advisory across the three platforms, so the file's absence is what counts.
-- Leaving one behind has consequences past tidiness: rollback restores from
-- the journal's record, and a backup no journal records is a second claimant
-- for the destination it sits at.
function P.drop_backup(dest)
  local bak = P.bak_path(dest)
  if not P.exists(bak) then return true end
  C.host.remove(bak)
  return not P.exists(bak)
end

-- Move one staged file into the body. The ordinary apply and the roll-forward
-- both go through here so the backup rules cannot drift apart.
function P.land(j, f, source)
  local dest = P.path(C.body_root, f.name)
  P.ensure_parent(dest)
  -- An unchanged file is skipped before the backup transition is opened at
  -- all. Most of a real package is stable between versions, and for those
  -- files the destination already hashes to the target BEFORE anything moves,
  -- which makes "the move finished" and "the bytes were always the same"
  -- indistinguishable for the whole length of the transition. Nothing to back
  -- up, nothing to rename, nothing to move, so that ambiguous state never
  -- exists. It is recorded rather than re-derived, because a rollback that
  -- inferred "fresh add" here would delete a file the user came with.
  if f.status == "pending" and not f.bak_existed and P.exists(dest)
      and P.hash_file(dest) == f.sha256 then
    f.status = "unchanged"
    if not P.journal_write(j) then
      return nil, "the installation journal could not be updated"
    end
    return true
  end
  if f.bak_existed and not P.exists(P.bak_path(dest)) then
    -- A claimed backup that is not on disk. bak_existed is only ever recorded
    -- for a destination that existed AND differed from the target, so the
    -- destination holding the target bytes now can only mean the move
    -- finished. Anything else is the crash between the record and the rename:
    -- the destination still holds the ORIGINAL, and landing on it now would
    -- destroy it with no backup anywhere.
    if P.hash_file(dest) == f.sha256 then
      f.status = "applied"
      if not P.journal_write(j) then
        return nil, "the installation journal could not be updated"
      end
      return true
    end
    f.bak_existed = false
  end
  if not f.bak_existed then
    -- Any ~bak here predates this transaction: an earlier commit could not
    -- delete it. It goes before this destination changes, or a rollback would
    -- find two candidates for one file and could not tell which is current.
    if not P.drop_backup(dest) then
      return nil, "a leftover backup of " .. f.name .. " could not be removed"
    end
    if P.exists(dest) then
      -- Recorded BEFORE the rename that creates it. Rollback trusts this
      -- record over the file's presence, so the record must never lag disk.
      f.bak_existed = true
      if not P.journal_write(j) then
        return nil, "the installation journal could not be updated"
      end
      if not C.host.rename(dest, P.bak_path(dest)) then
        return nil, "could not move " .. f.name .. " aside"
      end
    end
  end
  if not P.move(source, dest, f.sha256) then
    return nil, "could not install " .. f.name
  end
  f.status = "applied"
  if not P.journal_write(j) then
    return nil, "the installation journal could not be updated"
  end
  return true
end

-- The launch check, run before any commit and by both paths. probe() only
-- proves the critical files exist and are not empty, which a truncated or
-- half-written file passes on its way to failing at dofile time. Compiling the
-- body main is the cheapest question that actually means "would this launch",
-- and it is asked while the backups are still on disk, because a moment later
-- they will not be. Compiling does not run the body.
function P.body_ok()
  if M.probe() ~= "present" then
    return nil, "the installed files did not pass the launch check"
  end
  local chunk, err = C.compile(M.body_main_path())
  if not chunk then
    return nil, "the installed body would not load (" .. tostring(err) .. ")"
  end
  return true
end

-- Undo whatever landed. The phase marker is written before the first
-- mutation, because recovery reads the phase to pick a direction and a crash
-- inside a rollback must never be read as an interrupted apply.
function P.rollback(j)
  if j.phase ~= "rolling_back" then
    j.phase = "rolling_back"
    if not P.journal_write(j) then return "deferred" end
  end
  local failures = 0
  for i = #j.files, 1, -1 do
    local f = j.files[i]
    local dest = P.path(C.body_root, f.name)
    local bak = P.bak_path(dest)
    C.host.remove(P.staged_path(dest))  -- inert staging; nothing restores from it
    if f.bak_existed and P.exists(bak) then
      -- Only a backup this journal claims may be put back. A ~bak the journal
      -- does not record belongs to an earlier transaction whose cleanup never
      -- finished, and restoring it would overwrite a good current file with
      -- older bytes. The record is written before the rename that creates the
      -- backup, so the CURRENT generation can never be behind what is on disk.
      -- A superseded generation can be, which is why one is never allowed to
      -- outlive the write that displaced it.
      C.host.remove(dest)
      if not C.host.rename(bak, dest) then failures = failures + 1 end
    elseif f.bak_existed then
      -- A claimed backup that is not on disk, which is the same pair of states
      -- land has to tell apart, and it is only decidable because bak_existed
      -- is never recorded for a destination that already matched the target.
      -- Old bytes mean the backup was never created and there is nothing to
      -- undo, which is also what a second pass of this walk sees after the
      -- first one put the file back. New bytes mean the original is gone and
      -- cannot be restored, so the file that replaced it is removed: a body
      -- that fails its launch check and gets reinstalled beats a silent
      -- mixture of two versions.
      if P.hash_file(dest) == f.sha256 then
        C.host.remove(dest)
        if P.exists(dest) then failures = failures + 1 end
      end
    elseif f.status == "applied" and not f.dest_existed then
      -- A fresh add, and the journal says so twice rather than a hash implying
      -- it: this transaction marked the file applied, and the destination was
      -- not there when the transaction started. This is the only branch that
      -- deletes, so it is the one that has to demand positive evidence. A file
      -- recorded as unchanged never reaches it, because its status is neither
      -- applied nor backed up.
      C.host.remove(dest)
      if P.exists(dest) then failures = failures + 1 end
    end
  end
  if failures > 0 then
    -- A transient lock must not cost the user their rollback. Keep the
    -- journal so the next launch retries this same idempotent walk.
    P.journal_write(j)
    return "incomplete"
  end
  -- The walk is finished. Record that BEFORE any cleanup is attempted, so a
  -- generation that survives the cleanup reads as a transaction with nothing
  -- left to undo. Deleting first and trusting it would leave a rolling_back
  -- journal authoritative on disk: the launcher would run the restored body,
  -- the updater or a reinstall could put new files in, and the next launch
  -- would walk the same rollback again and take them out.
  j.phase = "rolled_back"
  if not P.journal_write(j) then return "unjournaled" end
  return P.finish_rollback(j)
end

function P.finish_rollback(j)
  if not P.cleanup_files(j, false) then return P.defer_cleanup(j, "rollback_deferred") end
  local cleaned = P.journal_delete()
  if cleaned == "gone" then return "rollback" end
  if cleaned == "primary" then
    -- The undo is complete and durable, and only the terminal record is stuck.
    -- Safe to launch on: what survives is the generation that says the walk is
    -- finished, so it can never run again, and the next launch retries the
    -- deletion.
    return "rollback_deferred"
  end
  -- An older generation survived instead. It contradicts the terminal record
  -- and would be read the moment the terminal record stopped being readable,
  -- so this does not permit a launch.
  return "stale_generation"
end

function P.abort(j, kind, detail)
  local outcome = P.rollback(j)
  if outcome == "rollback" or outcome == "rollback_deferred" then
    return nil, kind, detail
  end
  return nil, "journal",
    detail .. "; the rollback could not be completed and recorded"
end

-- Finish an interrupted apply in the forward direction when every file that
-- has not landed yet is still in the candidate directory and still hashes.
-- Returns the outcome, or false to send the caller to the rollback.
function P.roll_forward(j)
  local candidate = j.candidate or C.candidate_root
  local function source_of(f) return P.path(candidate, f.name) end
  -- Close the rename-before-journal window: the entry says pending, its
  -- candidate copy is gone, and the destination already holds the new bytes.
  -- Two different histories produce that, and the destination cannot tell them
  -- apart: a move that finished, or a file whose bytes were identical all
  -- along and whose staging was swept by something else. Only the journal
  -- separates them. A transaction that never opened the backup transition on a
  -- destination that already existed never touched that file, and calling it
  -- "applied" would let the rollback below delete it.
  for _, f in ipairs(j.files) do
    if f.status == "pending" and not P.exists(source_of(f))
        and P.hash_file(P.path(C.body_root, f.name)) == f.sha256 then
      f.status = (f.dest_existed and not f.bak_existed) and "unchanged"
        or "applied"
    end
  end
  for _, f in ipairs(j.files) do
    if f.status == "pending" and P.hash_file(source_of(f)) ~= f.sha256 then
      return false
    end
  end
  for _, f in ipairs(j.files) do
    if f.status == "pending" and not P.land(j, f, source_of(f)) then
      return false
    end
  end
  -- Recovery did not watch the earlier steps happen, so before it commits it
  -- re-proves what the ordinary apply watched: every file in the journal
  -- hashes at its destination, and the body as a whole passes the same launch
  -- check apply gates its own commit on. Either failure rolls back rather than
  -- committing a body nobody verified. The ordinary apply does not repeat the
  -- per-file hashing because it staged and hashed those bytes itself minutes
  -- earlier and a rename does not change them.
  for _, f in ipairs(j.files) do
    if P.hash_file(P.path(C.body_root, f.name)) ~= f.sha256 then return false end
  end
  if not P.body_ok() then return false end
  local done = P.commit(j)
  -- "unjournaled" is passed up rather than rolled back. Everything landed and
  -- verified; the only thing missing is a journal write, and a rollback needs
  -- those too. The launch is refused instead, and the next one commits.
  return (done == "closed") and "forward" or done
end

-- Cleanup is journaled like every other step. Backups, sibling staging files
-- and candidate files must all be gone before the retry record is removed.
-- The next apply also refuses a destination whose backup it cannot clear.
-- The journal stays committed while cleanup is incomplete, and the next launch
-- retries the same idempotent walk.
--
-- Three outcomes, and the callers must keep them apart:
--   "closed"            the journal is gone and the transaction is over
--   "cleanup_deferred"  the committed phase is durable, cleanup remains
--   "unjournaled"       the committed phase never reached disk
-- The last one is fatal for the launch. What is on disk still says "applying",
-- so a body allowed to run could edit its own files through the updater while
-- a transaction that may still roll back is open, and that rollback would then
-- revert work that came after it.
function P.commit(j)
  if j.phase ~= "committed" then
    j.phase = "committed"
    if not P.journal_write(j) then return "unjournaled" end
  end
  if not P.cleanup_files(j, true) then return P.defer_cleanup(j, "cleanup_deferred") end
  local cleaned = P.journal_delete()
  -- Only named safe answers permit startup. An unknown answer must preserve
  -- the primary and refuse startup, as a surviving older generation would.
  if cleaned == "gone" then return "closed" end
  if cleaned == "primary" then return "cleanup_deferred" end
  return "stale_generation"
end

function P.defer_cleanup(j, outcome)
  -- The usual retry already has one authoritative terminal primary. Avoid
  -- rotating that record just because a temporary file is still locked.
  if not P.exists(C.journal_path .. ".tmp") and not P.exists(C.journal_path .. ".old") then
    local current = P.journal_valid(P.json_decode(C.host.read_file(C.journal_path) or ""))
    if current and P.journal_text(current) == P.journal_text(j) then return outcome end
  end
  -- Recovery may have read a fallback generation. Republish the terminal
  -- record and prove .tmp and .old are gone before permitting startup with
  -- cleanup pending. Otherwise a later read could repeat an old undo.
  if not P.journal_write(j) then return "stale_generation" end
  return outcome
end

-- Terminal rollback preserves any backup it did not consume during undo.
-- Commit removes its backups after the new body has passed verification.
function P.cleanup_files(j, include_backups)
  local stuck = 0
  for _, f in ipairs(j.files) do
    local dest = P.path(C.body_root, f.name)
    if include_backups and not P.drop_backup(dest) then stuck = stuck + 1 end
    -- Keep the durable retry list until every transaction file is gone.
    -- A successful remove return alone does not prove absence.
    for _, path in ipairs({ P.staged_path(dest),
        P.path(j.candidate or C.candidate_root, f.name) }) do
      C.host.remove(path)
      if P.exists(path) then stuck = stuck + 1 end
    end
  end
  return stuck == 0
end

function P.resolve(j)
  if j.phase == "rolled_back" then
    -- Terminal. The undo happened and was recorded before any cleanup was
    -- attempted, so there is nothing to walk again and walking it would be the
    -- dangerous move: anything installed since would be taken back out.
    local done = P.finish_rollback(j)
    return done == "rollback" and "finished" or done
  end
  if j.phase == "committed" then
    -- Everything landed and was verified before the phase flipped, so there is
    -- nothing left to re-check here; only the cleanup was cut short. commit
    -- skips its phase write when the phase is already committed, so this call
    -- returns one of closed, cleanup_deferred or stale_generation.
    local done = P.commit(j)
    return (done == "closed") and "finished" or done
  end
  if j.phase == "rolling_back" then return P.rollback(j) end
  local outcome = P.roll_forward(j)
  if outcome then return outcome end
  return P.rollback(j)
end

function P.apply(files, version, source)
  local j = {
    phase = "applying", source = source, version = version,
    candidate = C.candidate_root, files = {},
  }
  for _, f in ipairs(files) do
    j.files[#j.files + 1] = {
      name = f.name, sha256 = f.sha256, status = "pending", bak_existed = false,
      -- Recorded once, at the start, while it is still a fact rather than an
      -- inference. Everything downstream that has to tell "we added this" from
      -- "the user already had this" reads it instead of guessing from bytes.
      dest_existed = P.exists(P.path(C.body_root, f.name)),
    }
  end
  if not P.journal_write(j) then
    -- No journal means no crash recovery, so no live file is touched.
    P.journal_delete()
    return nil, "disk", "the installation journal could not be written"
  end
  for _, f in ipairs(j.files) do
    local ok, detail = P.land(j, f, P.path(C.candidate_root, f.name))
    if not ok then return P.abort(j, "disk", detail) end
  end
  -- Confirm before committing. The backups are still on disk at this point,
  -- so a body that does not pass its own launch check can still be undone.
  P.emit("confirming")
  local sound, why = P.body_ok()
  if not sound then return P.abort(j, "incomplete", why) end
  -- The commit result is load-bearing. A deferred cleanup still leaves a
  -- finished, committed install and the next launch retries the backups, but a
  -- committed phase that never reached disk leaves an APPLYING transaction
  -- open, and the body must not run on top of one of those.
  local done = P.commit(j)
  if done ~= "closed" and done ~= "cleanup_deferred" then
    return nil, "journal",
      "the installation could not be marked as finished (" .. done .. ")"
  end
  return true
end

-- ----------------------------------------------------------------------------
-- The two restore sources
-- ----------------------------------------------------------------------------

-- The parked copy carries the canonical manifest by construction: reading it is
-- the first thing this function does, and a parked copy without one is
-- discarded before anything is staged. So the manifest a parked restore
-- installs is not re-derived from anywhere. It is the parked copy's own
-- manifest, the same bytes this function just parsed and just checked the
-- parked body against. Phase B's parking step therefore has to copy
-- manifest.json into Recovery/Body/ alongside the files, which it already has
-- to do for this path to work at all.
function P.try_parked()
  P.emit("parked_check")
  local files, version, _, text =
    P.read_manifest(P.path(C.parked_root, MANIFEST_NAME))
  local why
  if not files then
    why = "the backup manifest could not be read"
  elseif not P.covers_critical(files) then
    why = "the backup copy does not list every file the launcher needs"
  else
    local ok, detail = P.fill_candidate(C.parked_root, files)
    if not ok then
      why = detail
    else
      local staged, sdetail = P.stage_manifest(files, text)
      if not staged then
        why = sdetail
      else
        local bad = P.verify_candidate(files)
        if bad then why = "checksum mismatch on " .. bad end
      end
    end
  end
  if why then
    -- One bad file discards the WHOLE parked copy. A partial adopt would
    -- produce a body no build ever tested, which is worse than a download.
    --
    -- Discard means the staged copy goes and the parked source stays. It is
    -- not deleted, because the thing that failed may be the hash tool rather
    -- than the bytes, and deleting on a false negative costs the user their
    -- only offline restore. It is not marked either: a durable "known bad"
    -- flag would have to be invalidated by whatever reparks the copy, which
    -- is Phase B's job and not visible from here. So a still-bad copy is
    -- recopied and rehashed on the next failed launch, which costs seconds on
    -- a launch that is already downloading a whole body.
    if files then P.clear_candidate(files) end
    P.emit("parked_bad", why)
    return nil
  end
  P.emit("parked_ok", version)
  return files, version
end

function P.try_network()
  if not C.manifest_url or not C.payload_base then
    return nil, nil, "offline", "no server is configured for this install"
  end
  P.emit("manifest")
  C.host.make_dir(C.candidate_root)
  -- Read straight from the attempt that won. The manifest never occupies a
  -- shared slot at all, because nothing but this function ever wants it.
  local got, kind, detail = P.fetch(function() return P.bust(C.manifest_url) end,
    P.path(C.candidate_root, MANIFEST_NAME))
  if not got then return nil, nil, kind, detail end
  local text = C.host.read_file(got)
  C.host.remove(got)
  local files, version, ref = P.parse_manifest(text or "")
  if not files then
    return nil, nil, "verify", "the server manifest could not be read"
  end
  if not P.covers_critical(files) then
    return nil, nil, "verify",
      "the server manifest does not list every file the launcher needs"
  end
  -- Where the payloads come from, which the manifest may pin to the commit it
  -- was generated from. Absent, the configured base stands and nothing about
  -- this changes.
  local base = C.payload_base
  if ref then
    base = P.base_at_ref(C.payload_base, ref)
    if not base then
      return nil, nil, "verify",
        "the server manifest names a payload version this launcher cannot use"
    end
  end
  P.emit("downloading", #files)
  -- Anything a previous attempt left here is discarded before the first
  -- byte arrives. Partial copies are never patched up and reused.
  P.clear_candidate(files)
  for i, f in ipairs(files) do
    local target = P.path(C.candidate_root, f.name)
    P.ensure_parent(target)
    local landed, k, d = P.fetch(
      function() return base .. P.url_path(f.name) end, target)
    if not landed then
      P.clear_candidate(files)
      return nil, nil, k, d
    end
    -- Into the slot only once the attempt is over and its command has exited.
    if not P.stage_download(landed, target) then
      C.host.remove(landed)
      P.clear_candidate(files)
      return nil, nil, "disk", "could not stage " .. f.name
    end
    P.progress_file(i, #files, f.name)
  end
  -- The manifest is written from the bytes this function parsed rather than
  -- promoted from the attempt it arrived in. That attempt destination may still
  -- be growing: the launcher stops waiting for a command it cannot see the end
  -- of, and the curl behind it goes on writing. Nothing ever reads, hashes or
  -- promotes one of those, and the manifest is no exception to a rule the rest
  -- of this engine keeps.
  local staged, sdetail = P.stage_manifest(files, text)
  if not staged then
    P.clear_candidate(files)
    return nil, nil, "disk", sdetail
  end
  P.emit("verifying", #files)
  -- Downloaded bytes are verified HERE, before anything is applied, and the
  -- emit above is not the verification. An earlier revision announced this
  -- step and then returned, so the only hash check on the network path was
  -- the one inside roll_forward, which runs solely during crash recovery: a
  -- corrupted or tampered payload downloaded and installed on every ordinary
  -- run. The parked path has always verified at the moment of use; this makes
  -- the two sources agree.
  local bad = P.verify_candidate(files)
  if bad then
    P.clear_candidate(files)
    return nil, nil, "verify", "checksum mismatch on " .. bad
  end
  return files, version
end

-- ----------------------------------------------------------------------------
-- Public contract
-- ----------------------------------------------------------------------------

-- Selection records use the same parser as installation journals. The caller
-- bounds the input and validates its own record schema.
function M.decode_json(text)
  if type(text)~="string" then return nil end
  return P.json_decode(text)
end

function M.configure(opts)
  if type(opts) ~= "table" then return nil, "an options table is required" end
  local host = opts.host
  if type(host) ~= "table" then return nil, "opts.host is required" end
  for _, name in ipairs(HOST_SEAMS) do
    if type(host[name]) ~= "function" then
      return nil, "opts.host." .. name .. " is required"
    end
  end
  if type(opts.body_root) ~= "string" or opts.body_root == "" then
    return nil, "opts.body_root is required"
  end
  if type(opts.journal_path) ~= "string" or opts.journal_path == "" then
    return nil, "opts.journal_path is required"
  end
  local sep = opts.sep or package.config:sub(1, 1)
  local function as_root(value)
    local last = value:sub(-1)
    if last ~= "/" and last ~= "\\" then value = value .. sep end
    return value
  end
  local body_main = opts.body_main or "ReaAssist_App.lua"
  local critical = opts.critical_files or { body_main }
  if #critical == 0 then
    return nil, "opts.critical_files must not be empty"
  end
  local payload_base = opts.payload_base_url
  if payload_base and payload_base:sub(-1) ~= "/" then
    payload_base = payload_base .. "/"
  end
  C = {
    sep          = sep,
    host         = host,
    mode         = (opts.mode == "sr") and "sr" or "standard",
    body_root    = as_root(opts.body_root),
    body_main    = body_main,
    critical     = critical,
    parked_root  = opts.parked_root and as_root(opts.parked_root) or nil,
    -- Sibling of the body root by default, so a rename into place stays on
    -- one volume and a leftover never sits inside the body being probed.
    candidate_root = as_root(opts.candidate_root
      or (opts.body_root:gsub("[\\/]+$", "") .. "_candidate")),
    journal_path = opts.journal_path,
    -- Names every destination a download of this run is allowed to land in, so
    -- a command one launcher abandoned can never be writing into a path
    -- another launcher reads. Taken from the host when it offers one, so the
    -- whole run carries a single identity and the exec wrapper's files and the
    -- download destinations name the same run; minted here when it does not,
    -- because this is a configure option rather than a seam and the engine may
    -- not stop working when a caller leaves it out.
    run_token    = P.run_token(opts.run_token),
    -- Optional compile seam, defaulted rather than required. loadfile is
    -- standard Lua and not a REAPER API, so compiling the body main here keeps
    -- the engine's no-body-dependency rule intact; the seam exists so the
    -- tests can inject a failure and Phase B can swap in a different check.
    compile      = (type(host.compile) == "function") and host.compile
                   or loadfile,
    manifest_url = opts.manifest_url,
    payload_base = payload_base,
    retries      = tonumber(opts.retries) or 3,
    backoff      = tonumber(opts.retry_backoff) or 2,
  }
  return true
end

function M.probe()
  if not C then return "absent" end
  local found, missing = 0, 0
  for _, name in ipairs(C.critical) do
    local size = C.host.file_size(P.path(C.body_root, name))
    if size and size > 0 then found = found + 1 else missing = missing + 1 end
  end
  if missing == 0 then return "present" end
  if found == 0 then return "absent" end
  return "incomplete"
end

function M.body_main_path()
  if not C then return nil end
  return P.path(C.body_root, C.body_main)
end

-- Resolve any journal an interrupted run left behind. This runs before
-- anything else looks at the body, including the launcher's own fast path,
-- because probe() cannot see the difference between a whole body and one whose
-- critical files landed while the rest of the transaction did not.
--
--   nil                -> there was no journal and nothing was done
--   true, outcome      -> a journal was resolved; the outcome is one of
--                         finished, forward, rollback, cleanup_deferred
--   nil, kind, detail   -> it could not be resolved; the dialog has been shown
--
-- The third case means the caller must not run the body. Something is part
-- applied and nobody can say what, so running it would be guessing.
function M.resolve_pending(progress_cb)
  if not C then return nil, "config", "configure() was not called" end
  if progress_cb then C.progress = progress_cb end
  local pending, why = P.journal_read()
  if not pending then
    if not why then return nil end
    -- Kept, not deleted. Deleting the evidence would let the next launch run
    -- a half-applied body as if nothing had happened.
    return P.fail("journal", why)
  end
  P.emit("recovering", pending.phase)
  local outcome = P.resolve(pending)
  P.emit("recovered", outcome)
  if not SAFE_OUTCOMES[outcome] then
    return P.fail("journal",
      "an interrupted installation could not be resolved (" .. outcome .. ")")
  end
  return true, outcome
end

function M.restore(progress_cb)
  if not C then return nil, "config", "configure() was not called" end
  C.progress = progress_cb
  -- The same entry the launcher calls before its fast path. Harmless twice:
  -- a resolved journal is gone, so the second call has nothing to find.
  local resolved, kind, detail = M.resolve_pending()
  if not resolved and kind then return nil, kind, detail end
  local state = M.probe()
  P.emit("probing", state)
  if state == "present" then
    P.emit("done", "present")
    return true, "present"
  end
  local files, version, source
  if C.parked_root then
    files, version = P.try_parked()
    if files then source = "parked" end
  end
  if not files then
    local kind, detail
    files, version, kind, detail = P.try_network()
    if not files then return P.fail(kind, detail) end
    source = "network"
  end
  P.emit("applying", #files)
  local ok, akind, adetail = P.apply(files, version, source)
  if not ok then return P.fail(akind, adetail) end
  P.emit("done", version)
  return true, "restored"
end

return M

end)()
-- ---------------------------------------------------------------------------
-- END embedded launcher_core.lua
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- BEGIN embedded launcher_lock.lua
-- ---------------------------------------------------------------------------
local lock = (function()
-- ============================================================================
-- launcher_lock.lua - the interprocess lock the launcher holds while it works
-- ============================================================================
--
-- Phase B, decision 10a.5 of Dev/Plans/Distribution Unification Plan.md, and
-- the gap launcher_core.lua's README calls its one correctness gap: the engine
-- is safe against a crash between any two steps and is not safe against two
-- REAPER instances sharing one resource path and bootstrapping at once.
--
-- Same rules as the engine. Every host touch goes through the injected `host`
-- table, so there is no `reaper.` anywhere in this file and the identical text
-- runs under the stubbed host in Dev/Launcher/test and under real REAPER. It
-- is embedded verbatim in both shipped launchers by gen_launchers.lua, so it
-- declares only locals and returns a table.
--
-- Contract:
--   local lock = <this chunk>
--   lock.configure(opts)      -> true | nil, message
--   lock.acquire(progress_cb) -> true, detail | nil, kind, detail
--   lock.beat()               -> refresh the heartbeat; cheap, safe any time
--   lock.release()            -> true | nil, detail
--   lock.held()               -> true when this instance owns it
--
-- Failure `kind` values: "busy" (someone else has it and the user cancelled or
-- the budget ran out), "disk" (the lock could not be written), "conflict" (a
-- stale break turned out to take a lock nobody evaluated), "identity", "config".
--
-- ----------------------------------------------------------------------------
-- The atomic acquire, per operating system
-- ----------------------------------------------------------------------------
-- Creating a lock file only counts if the creation FAILS when the file is
-- already there. Two things that look like they would do it do not:
--
--   * `io.open(path, "wx")`. Lua's own l_checkmode rejects any mode letter
--     outside L_MODEEXT, which is "b". The exclusive-create mode C11 added to
--     fopen never reaches the C library, so this is an "invalid mode" error
--     rather than a lock.
--   * `os.rename(tmp, lock)` on POSIX. rename(2) replaces the destination
--     silently, so both racers succeed and the second one wins.
--
-- So the primitive is per operating system, and each one is first class where
-- it is used rather than a portable compromise that is weak on both:
--
--   Windows ("file" style). MoveFile refuses to clobber, so `os.rename` of a
--   uniquely named staging file onto the lock path IS a test and set. Release
--   is `os.remove`, which works on files.
--
--   macOS and Linux ("dir" style). The lock is a DIRECTORY that always holds
--   an `owner` file. POSIX.1 requires rename to fail with ENOTEMPTY or EEXIST
--   when the destination is a non-empty directory, so renaming a staging
--   directory onto a held lock refuses for the same reason MoveFile does.
--   The owner file is written into the staging directory BEFORE the rename,
--   so the lock is never momentarily empty and never renameable-over. Release
--   removes the owner file and then the directory, both of which os.remove
--   does on POSIX.
--
-- Windows cannot use the directory form because its os.remove will not delete
-- a directory (MSVCRT's remove() is files only), and a release that has to
-- shell out is a release that can fail on the path where reliability matters
-- most.
--
-- ----------------------------------------------------------------------------
-- Deciding an owner is gone
-- ----------------------------------------------------------------------------
-- Proof of DEATH and proof of LIFE are different questions and the signals
-- answer them asymmetrically, which is the correction round 9 forced:
--
--   1. A process check, when the host can do one. The record carries the
--      owner's process id and the host answers pid_alive. A dead process
--      proves the owner is gone. A LIVE process proves only that it is not
--      gone, because the process id is REAPER's and every script inside that
--      REAPER shares it: a launcher instance that died inside a REAPER still
--      running answers "alive" here forever. So a live process is not allowed
--      to end the question, which is what it used to do.
--   2. The held file, on Windows only. The owner keeps `<lock>.held.<token>`
--      open for the whole critical section, and Windows will not delete a file
--      that is open without FILE_SHARE_DELETE. A prospective breaker asks the
--      filesystem to delete it: a refusal is positive proof of life, because
--      some process has that handle open right now, and a deletion is proof of
--      death, because the operating system closes handles when a process dies
--      however it dies. POSIX allows unlinking an open file, so this probe is
--      switched off there by `hold_blocks_remove` rather than being quietly
--      wrong. On Windows it is also the signal that survives a leaked handle
--      the wrong way round: an instance whose Lua state is gone but whose file
--      handle has not been collected yet still reads as alive, which is why it
--      cannot be the only thing standing between a dead script and its lock.
--   3. Silence. The owner rewrites a heartbeat file every couple of seconds
--      from the same defer pump that drives the engine, and a heartbeat that
--      has not moved for `stale_seconds` means the owner is gone or wedged.
--      This is the only signal that ages out a dead script sharing a live
--      REAPER's process id, so it decides whenever the two above cannot.
--
-- Breaking a silent owner that may still be alive is safe because BOTH sides
-- of it are handled, and the previous revision of this comment named only the
-- first, which is the finding Codex round 10 returned:
--
--   The breaker's side. The breaker acquires the lock before it touches
--   anything, and the first thing the engine does under the lock is resolve
--   the journal, so an interrupted transaction is rolled forward or back
--   rather than continued blind.
--
--   The broken owner's side. It is fenced. Every mutation it performs from
--   then on is refused, because resolving the journal says nothing about an
--   instance that is still parked in a defer pump with a write, a rename or a
--   process launch pending. See "The mutation fence" below.
--
-- The launcher pumps beat() from every defer frame, including every frame a
-- download is yielding through, so a healthy owner cannot fall silent for ten
-- minutes while it works.
--
-- Decision 10a.5 says a lock is stale when it is "older than 10 minutes or its
-- owning process is gone". The ten minutes is applied to the HEARTBEAT rather
-- than to the acquisition time: a cold bootstrap over a slow connection can
-- legitimately run past ten minutes (the engine allows curl 120 seconds per
-- file), and an age test against the acquisition time would break a lock whose
-- owner is downloading normally. Codex ruled the heartbeat anchor correct in
-- round 9 and Michael approved it as plan item 10a.8, so this is now the
-- decision rather than a deviation from it.
--
-- ----------------------------------------------------------------------------
-- Token-named sidecars
-- ----------------------------------------------------------------------------
-- The heartbeat and the held file carry the owner's token in their names. A
-- shared name for either one is a path a stale owner can write to or delete
-- after its lock has been broken and re-acquired, and both of those corrupt
-- the CURRENT owner's liveness evidence. With the token in the name the
-- question does not arise: an instance can only ever touch its own.
--
-- What the tokened names protect is the EVIDENCE and nothing else. They do not
-- stop a broken owner from writing to the body, moving a live file or starting
-- a process, which is what the fence below is for.
--
-- ----------------------------------------------------------------------------
-- The mutation fence
-- ----------------------------------------------------------------------------
-- An instance whose lock has been broken is not stopped by having lost it. Its
-- coroutine is parked in a defer pump somewhere inside a transaction, and when
-- the pump resumes it, the write or the rename it was about to perform lands
-- in the tree the NEW owner is working in. Two instances writing one body is
-- the exact state the lock exists to prevent, so the lock has to be the thing
-- that prevents it rather than a claim about who was told what.
--
-- So: may_mutate() reads the canonical lock record and answers yes only while
-- that record still names this instance's token. The host the engine is given
-- asks it immediately before every mutating seam call, and a refusal raises,
-- so the engine stops at the refused statement instead of handling a failure
-- and cleaning up after it. The answer is latched the first time it is no: an
-- instance that has been revoked once never mutates again, whatever the disk
-- says afterwards, because the only honest reading of a foreign record is that
-- somebody else is part way through work this instance cannot see.
--
-- It is a read per mutation rather than a read per frame, and that is the
-- whole point. A check that passed a frame ago says nothing about the
-- mutation happening now, and the record is one line under two hundred bytes.
-- Reads are not fenced: a probe or a journal read changes nothing, and making
-- them pay for a second read would tax the launch that is doing nothing wrong.
--
-- The residual, stated the way this project states them rather than argued
-- away: this is COOPERATIVE fencing, so between the check and the mutation the
-- operating system may suspend this process for longer than the whole
-- staleness budget, and the mutation then lands after the lock was broken. It
-- is bounded at one mutation, because the check before the next one refuses.
-- Closing it needs a filesystem that can fence a handle, which neither Lua nor
-- the REAPER API offers.
--
-- ----------------------------------------------------------------------------
-- Breaking a stale lock without stealing a live one
-- ----------------------------------------------------------------------------
-- Breaking is one rename to a destination nobody else will name:
-- `<lock>.dead.<my token>`. Renames are exclusive on their SOURCE on every
-- platform, so exactly one of any number of simultaneous breakers wins and the
-- rest get "it was not there".
--
-- The state to be careful about is the one where the owner released between
-- the read that judged the lock stale and the rename that took it, and a third
-- instance acquired in that gap. A new owner writes a new token, so the
-- breaker compares the token it took with the token it judged: equal means it
-- took exactly what it evaluated, and anything else means it took a lock it
-- never looked at. In that case it puts the lock back with one more rename and
-- stops this launch rather than continuing, because a token it has never
-- evaluated means another instance is live and doing work. "Anything else"
-- includes a record that will not read: it names nobody, so nothing can show it
-- is the record that was judged, and it is put back for the same reason a
-- foreign one is. Only a record that reads AND carries the judged token is
-- destroyed, and a put-back that fails leaves the record in the grave rather
-- than destroying it.
--
-- Breaking is NEVER treated as acquiring. A successful break is followed by
-- the ordinary atomic acquire, which is race free, so nothing here can end up
-- believing it owns a lock it took from somebody.
--
-- Releasing is fenced by the same protocol, and for the same reason. The
-- obvious release (delete the sidecars, then delete whatever is at the lock
-- path) destroys a shared path it has not looked at: between the moment this
-- owner was judged silent and the moment it gets around to releasing, a waiting
-- instance can break the lock and acquire it, and the delete then takes out the
-- NEW owner's lock and leaves two instances free to work at once. So release
-- renames the lock aside to a destination only this instance can name, reads
-- the record that came with it, and deletes only when the record is its own.
-- A record belonging to somebody else is put back untouched and the release
-- reports that ownership was lost, and if the put-back itself fails the record
-- is LEFT where it is rather than destroyed: it is a working instance's
-- ownership evidence, not debris, and this function deleting a record it has
-- not written is the exact defect the protocol exists to prevent. The rename is
-- exclusive on its source, so a release and a break that collide have exactly
-- one winner and the loser mutates nothing shared. A release whose fence has
-- already tripped skips all
-- of it: the answer the rename exists to obtain is already known, and taking a
-- record known to be somebody else's aside even for an instant is a mutation
-- of the current owner's lock in exchange for nothing.
--
-- The residual, stated plainly because the engine's standing rule is that an
-- argument for unreachability is a reason to write the test rather than skip
-- one: an owner whose heartbeat has been silent for the full stale budget can
-- still be alive, and if it releases and a third instance acquires inside the
-- microseconds between our read and our rename, we detect the swap and put the
-- lock back, and for that instant two instances believed they held it. Both
-- coincidences are required, the breaker performs no mutation in that window,
-- and the detection is tested.
-- ============================================================================

local M = {}
local P = {}
local C = nil

-- Short on purpose: OSARA speaks these in full while the user is waiting.
local SAY = {
  lock_wait  = "Another copy of REAPER is setting up ReaAssist. Waiting.",
  lock_stale = "Clearing a lock left behind by a copy of REAPER that stopped.",
  lock_ok    = "Ready to continue.",
  lock_busy  = "Another copy of REAPER is still setting up ReaAssist.",
  lock_lost  = "Another copy of REAPER took over the setup. "
    .. "This copy stopped without changing anything else.",
}

local WAIT_DIALOG =
  "Another copy of REAPER is setting up ReaAssist right now.\n\n"
  .. "ReaAssist waited %d seconds for it to finish. Choose Retry to keep "
  .. "waiting, or Cancel to close this copy and start it again later."

local CONFLICT_DIALOG =
  "ReaAssist could not take charge of its own setup because another copy of "
  .. "REAPER claimed it at the same moment.\n\nNothing on this computer was "
  .. "changed. Close the other copy of REAPER and start ReaAssist again."

local REVOKED_DIALOG =
  "Another copy of REAPER took charge of setting up ReaAssist while this copy "
  .. "was working, so this copy stopped straight away to keep your files "
  .. "safe.\n\nNothing further was changed here. Let the other copy finish, "
  .. "then start ReaAssist again."

local DISK_DIALOG =
  "ReaAssist could not write to its Recovery folder, so it could not make "
  .. "sure only one copy of REAPER sets it up at a time.\n\nNothing was "
  .. "changed. Check that the REAPER resource folder is writable, then start "
  .. "ReaAssist again."

local IDENTITY_DIALOG =
  "ReaAssist could not check which copy of REAPER is running.\n\n"
  .. "Restart REAPER and try again. If this keeps happening, contact support."

local SEAMS = {
  "message_box", "announce", "read_file", "write_file", "file_size", "present",
  "make_dir", "remove", "rename", "sleep", "os_name",
}

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

function P.title()
  return (C.mode == "sr") and "ReaAssist - Screen Reader Mode" or "ReaAssist"
end

function P.emit(state, detail)
  local text = SAY[state] or state
  if state == "lock_wait" and detail then
    text = text .. " " .. tostring(detail) .. " seconds."
  end
  local prefix = (C.mode == "sr")
    and "ReaAssist Screen Reader Mode: " or "ReaAssist: "
  pcall(C.host.announce, prefix .. text)
  if C.progress then
    pcall(C.progress, {
      state = state, detail = detail, mode = C.mode, text = text,
    })
  end
end

function P.exists(path)
  return C.host.present(path) ~= false
end

-- Whole seconds since the epoch. An optional host seam rather than a direct
-- os.time call, so the suite can drive staleness and the wait budget exactly
-- instead of taking whatever the machine took. The shipped host binds it to
-- os.time, and a host that does not offer it gets os.time here.
function P.now()
  if C and type(C.host.now) == "function" then return C.host.now() end
  return os.time()
end

-- A token no other instance can produce. os.time pins the second, math.random
-- is seeded per process by Lua 5.4 itself, and the address of a fresh table is
-- unique inside this process and varies between processes under address space
-- layout randomisation. Any one of the three could repeat; all three together
-- is what makes "the token I took is the token I judged" mean something.
function P.mint_token()
  local addr = tostring({}):match("[x%x]+$") or "0"
  return string.format("%d-%d-%s", P.now(),
    math.random(1, 2147483647), addr)
end

-- One line, tab separated, key=value. Not JSON: the engine's decoder is not
-- available to this chunk when it is embedded alongside rather than inside it,
-- and a lock record has four fields.
function P.encode(rec)
  return string.format("schema=1\ttoken=%s\tacquired=%d\tmode=%s\tpid=%s\tstart=%s\n",
    rec.token, rec.acquired, rec.mode, rec.pid or "-", rec.start or "-")
end

function P.decode(text)
  if type(text) ~= "string" then return nil end
  local token = text:match("token=([^\t\r\n]+)")
  local acquired = tonumber(text:match("acquired=(%d+)"))
  if not token or not acquired then return nil end
  if not token:match("^[%w%-]+$") then return nil end
  local start = text:match("\tstart=([^\t\r\n]+)")
  if start == "-" then start = nil end
  if start and (#start > 160 or start:find("[%c]")) then return nil end
  return {
    token = token,
    acquired = acquired,
    mode = text:match("mode=([^\t\r\n]+)") or "standard",
    pid = text:match("pid=([^\t\r\n]+)"),
    start = start,
  }
end

-- ----------------------------------------------------------------------------
-- The two shapes
-- ----------------------------------------------------------------------------
-- Everything below asks P.style_* rather than testing the platform inline, so
-- a test can exercise either shape on either machine and the difference stays
-- in one place.

function P.owner_path(root)
  if C.style == "dir" then return root .. C.sep .. "owner" end
  return root
end

-- Is a lock held at `root`? For the directory style the question is whether
-- the owner file inside it is there, never whether the directory is: an empty
-- directory left behind by a release that could not remove it holds nobody,
-- and POSIX rename is allowed to replace an empty directory, which is exactly
-- what should happen to it. Asking about the directory itself would also be
-- unreliable, because opening a directory for reading succeeds on some POSIX
-- C libraries and fails on Windows.
function P.present(root)
  return P.exists(P.owner_path(root))
end

-- Build a claim at a path nobody else will name, ready to be renamed on. The
-- owner file is written BEFORE the rename, so the lock is never momentarily
-- empty at its real path and never renameable-over on POSIX.
function P.stage(root, rec)
  if C.style == "dir" then C.host.make_dir(root) end
  return C.host.write_file(P.owner_path(root), P.encode(rec)) and true or false
end

-- Remove a lock shaped thing at `root` and prove it is gone. "Gone" means the
-- owner file is gone; a directory that will not delete is left behind empty
-- and is harmless, because the next claim renames over it and the claim after
-- that finds a non-empty directory and refuses.
function P.destroy(root)
  if P.present(root) then C.host.remove(P.owner_path(root)) end
  if C.style == "dir" then C.host.remove(root) end
  return not P.present(root)
end

function P.read_record(root)
  return P.decode(C.host.read_file(P.owner_path(root)))
end

-- On a cold install the lock is the first thing that writes anything into the
-- Recovery folder, so the folder may not be there yet. io.open will not create
-- a missing directory, and a claim that fails for that reason looks exactly
-- like a disk failure, which would stop every first launch.
function P.ensure_parent(path)
  local parent = path:match("^(.*)[\\/][^\\/]+$")
  if parent and parent ~= "" then C.host.make_dir(parent) end
end

-- ----------------------------------------------------------------------------
-- Liveness
-- ----------------------------------------------------------------------------

-- One sidecar per owner, named for the owner. A shared name would let an
-- instance whose lock has already been broken write over the current owner's
-- heartbeat or delete the file that proves it is alive.
function P.beat_path(token) return C.lock_path .. ".beat." .. token end
function P.held_path(token) return C.lock_path .. ".held." .. token end

-- The freshest evidence that the owner of `rec` was alive. Falls back to the
-- acquisition time, so a lock whose owner never got to write a heartbeat still
-- ages out rather than living forever.
function P.last_seen(rec)
  local text = C.host.read_file(P.beat_path(rec.token))
  if text then
    local token, when = text:match("token=([^\t\r\n]+)\tat=(%d+)")
    if token == rec.token and tonumber(when) then return tonumber(when) end
  end
  return rec.acquired
end

-- Three answers, and the difference between two of them matters:
--   true   the owner is proven gone
--   false  the owner is proven ALIVE right now, which outranks silence
--   nil    nothing here can tell, so silence gets to decide
--
-- Proof of life is deliberately narrow: an open file handle nobody can delete.
-- Everything else only narrows the question. In particular a live process id is
-- NOT proof of life, because the id is REAPER's and is shared by every script
-- in it, so a dead launcher inside a live REAPER would otherwise hold its lock
-- until the user quit REAPER. Round 9 found exactly that: this function
-- returned "alive" on a live pid before the heartbeat was ever consulted.
--
-- A proven-alive owner is still never broken however quiet it has been, because
-- an instance holding an open handle is a process that has not exited and may
-- still be finishing the transaction it opened.
function P.owner_gone(rec)
  if rec.pid and rec.pid ~= "-" and type(C.host.pid_alive) == "function" then
    -- Refresh admission keeps a live process claim through modal startup.
    -- The older recovery policy may still use heartbeat expiry below.
    local alive = C.host.pid_alive(rec.pid, rec.start)
    if alive == false then
      return true, "the owning process is gone"
    end
    if alive == true and C.require_dead_owner then return false end
  end
  if C.hold_blocks_remove then
    -- Destructive on purpose, and only destructive when the answer is "gone":
    -- Windows refuses to delete the file while its owner holds it open, so a
    -- deletion IS the finding. A held file that is not there at all proves
    -- nothing, because an owner that could not create it looks the same as an
    -- owner that never existed. The name carries the owner's token, so this
    -- can only ever delete the evidence of the owner being judged.
    local held = P.held_path(rec.token)
    if P.exists(held) then
      C.host.remove(held)
      if not P.exists(held) then
        return true, "the copy of REAPER that was setting up is gone"
      end
      return false
    end
  end
  return nil
end

function P.stale_reason(rec)
  local gone, why = P.owner_gone(rec)
  if gone == true then return why end
  if gone == false then return nil end
  if C.require_dead_owner then return nil end
  local seen = P.last_seen(rec)
  local age = P.now() - seen
  -- A clock that moved backwards leaves a negative age. That is not evidence
  -- of anything, so it is not treated as staleness.
  if age >= C.stale_seconds then
    return "no sign of life for " .. tostring(age) .. " seconds"
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Acquire, break, release
-- ----------------------------------------------------------------------------

-- Returns true when this instance now owns the lock, false when someone else
-- has it, or nil plus a reason when the staging itself failed.
function P.claim()
  local rec = {
    token = P.mint_token(), acquired = P.now(), mode = C.mode,
    pid = (type(C.host.pid) == "function") and C.host.pid() or nil,
  }
  local staging = C.lock_path .. "." .. rec.token .. ".tmp"
  if C.require_dead_owner and C.style == "dir" then
    rec.start = type(C.host.pid_start) == "function" and C.host.pid_start(rec.pid) or nil
    if not tostring(rec.pid or ""):match("^%d+$") or type(rec.start) ~= "string"
        or rec.start == "" or #rec.start > 160 or rec.start:find("[%c]") then
      return nil, "the process identity could not be established", "identity"
    end
  end
  P.ensure_parent(staging)
  P.destroy(staging)
  if not P.stage(staging, rec) then
    P.destroy(staging)
    return nil, "the lock file could not be written"
  end
  local handle
  local function clear_staged_hold()
    if handle then pcall(C.host.unhold, handle) end
    if C.require_dead_owner and C.hold_blocks_remove then
      C.host.remove(P.held_path(rec.token))
    end
  end
  -- Publish Windows liveness before the canonical claim. A crash immediately
  -- after publication must leave evidence that the next process can reclaim.
  if C.require_dead_owner and C.hold_blocks_remove then
    if type(C.host.hold) == "function" and type(C.host.unhold) == "function" then
      local ok, value = pcall(C.host.hold, P.held_path(rec.token))
      if ok then handle = value end
    end
    if not handle then
      clear_staged_hold()
      P.destroy(staging)
      return nil, "the process liveness file could not be held"
    end
  end
  if not C.host.rename(staging, C.lock_path) then
    clear_staged_hold()
    P.destroy(staging)
    return false
  end
  -- Read back rather than trust the rename. On the platform whose rename
  -- refuses to clobber this can only confirm; on the other one it is the
  -- difference between owning the lock and having quietly replaced somebody.
  local got = P.read_record(C.lock_path)
  if not got or got.token ~= rec.token then
    clear_staged_hold()
    return false
  end
  C.record = rec
  -- The held file is opened after the lock is ours, so a failure to open it
  -- costs the Windows liveness signal and nothing else. The heartbeat still
  -- covers this owner.
  if handle then
    C.hold_handle = handle
  elseif type(C.host.hold) == "function" then
    C.hold_handle = C.host.hold(P.held_path(rec.token))
  end
  M.beat()
  return true
end

-- One rename, exclusive on its source. Returns "broken" when the lock this
-- instance judged stale is gone, "lost" when what was taken was not what was
-- judged and went back where it came from (the caller simply retries the
-- ordinary acquire), or "conflict" when it was not what was judged and could
-- not be put back. Only the first of the three destroys anything.
function P.break_stale(rec)
  local grave = C.lock_path .. ".dead." .. P.mint_token()
  if not C.host.rename(C.lock_path, grave) then return "lost" end
  local got = P.read_record(grave)
  -- Only a record that reads AND carries the token this instance judged is the
  -- one it evaluated. Written as its own line because the same comparison
  -- appears in the claim's read-back, and the two must be edited apart.
  local judged = got ~= nil and got.token == rec.token
  if not judged then
    -- Not the lock this instance judged. A foreign token is the obvious case:
    -- the owner released and a third instance acquired between the read that
    -- judged this lock stale and the rename that took it. A record that will
    -- not read at all is the same answer arrived at differently, and it used to
    -- fall through to the destroy below: it names nobody, so nothing here can
    -- show it is the record that was evaluated, and destroying evidence this
    -- function never judged is the defect the whole protocol exists to prevent.
    --
    -- So it goes back exactly as it was found, and when the put-back fails it
    -- is LEFT in the grave rather than destroyed, on the same argument as the
    -- release aside: the grave is named from a token only this call can
    -- produce, every instance names its own, and acquiring only ever looks at
    -- the canonical path, so what is left is inert rather than in anybody's
    -- way. Destroying it instead would take out the ownership evidence of an
    -- instance that may be working right now, which is exactly what the
    -- put-back was for.
    if C.host.rename(grave, C.lock_path) then return "lost" end
    return "conflict"
  end
  P.destroy(grave)
  -- The sidecars of the owner just broken, named for it. Nothing else can be
  -- at these paths, so a later owner's evidence is never in reach here.
  C.host.remove(P.beat_path(rec.token))
  C.host.remove(P.held_path(rec.token))
  return "broken"
end

function M.configure(opts)
  if type(opts) ~= "table" then return nil, "an options table is required" end
  local host = opts.host
  if type(host) ~= "table" then return nil, "opts.host is required" end
  for _, name in ipairs(SEAMS) do
    if type(host[name]) ~= "function" then
      return nil, "opts.host." .. name .. " is required"
    end
  end
  if type(opts.lock_path) ~= "string" or opts.lock_path == "" then
    return nil, "opts.lock_path is required"
  end
  local sep = opts.sep or package.config:sub(1, 1)
  local style = opts.style
  if not style then
    local os_name = host.os_name() or ""
    style = os_name:match("^Win") and "file" or "dir"
  end
  if style ~= "file" and style ~= "dir" then
    return nil, "opts.style must be file or dir"
  end
  local hold_blocks = opts.hold_blocks_remove
  if hold_blocks == nil then hold_blocks = (style == "file") end
  C = {
    host = host,
    sep = sep,
    style = style,
    hold_blocks_remove = hold_blocks and true or false,
    require_dead_owner = opts.require_dead_owner == true,
    mode = (opts.mode == "sr") and "sr" or "standard",
    lock_path = opts.lock_path,
    wait_seconds = tonumber(opts.wait_seconds) or 30,
    stale_seconds = tonumber(opts.stale_seconds) or 600,
    poll_seconds = tonumber(opts.poll_seconds) or 0.25,
    say_every = tonumber(opts.say_every) or 5,
    break_attempts = tonumber(opts.break_attempts) or 5,
    max_dialogs = tonumber(opts.max_dialogs) or 20,
    record = nil,
    hold_handle = nil,
  }
  return true
end

function M.held()
  return (C ~= nil) and (C.record ~= nil)
end

-- ----------------------------------------------------------------------------
-- The fence
-- ----------------------------------------------------------------------------

-- May this instance change anything on disk right now? One read of the
-- canonical record, and the answer is yes only while that record still names
-- this instance's token. A foreign token, a record that will not read and no
-- lock at all are all a no, and the no is LATCHED: an instance that has been
-- revoked once never mutates again, whatever appears at the lock path
-- afterwards.
--
-- An instance that has never held the lock is not revoked and is not fenced.
-- This is a fence against revocation, not a second authorisation system: what
-- keeps every mutation inside the lock is the launcher's sequence, and there
-- is a row for it. Adding a second answer here would turn a wiring mistake
-- into a silent refusal instead of the loud one it should be.
function M.may_mutate()
  if not C then return false end
  if M.revoked() then return false end
  if not C.record then return true end
  local got = P.read_record(C.lock_path)
  if got and got.token == C.record.token then return true end
  -- Worded for the release() that follows: "claimed" is the case where
  -- somebody else is demonstrably working, and it is the one the caller
  -- reports.
  C.revoked = got and "the lock had been claimed by another instance"
    or "the lock this instance was holding is gone"
  return false
end

-- Whether this instance has been revoked. Reads nothing: may_mutate is the
-- only thing that sets the latch, so the pump can ask this every frame.
function M.revoked()
  return (C ~= nil) and (C.revoked ~= nil)
end

-- One announcement and one dialog. The pump shows this INSTEAD of its crash
-- dialog, because a fenced launcher is not a crash: it stopped on purpose,
-- nothing here was damaged, and the sentence the user needs is about the other
-- copy of REAPER rather than about this one failing.
function M.report_revoked()
  if not C then return end
  P.emit("lock_lost")
  pcall(C.host.message_box, REVOKED_DIALOG, P.title())
end

-- Cheap enough to call from a defer pump every frame: it writes one short line
-- and only when a second has passed since the last one. The pump calls this on
-- every frame the engine yields through, including every frame of a download,
-- which is what makes heartbeat silence mean something.
--
-- It writes ONE path and that path carries this instance's own token, so an
-- owner that was broken while it was paused cannot write over the heartbeat of
-- the instance that took over: the file it writes is one nobody reads any more.
-- That is why the write comes BEFORE the ownership question rather than after
-- it. The write cannot reach the current owner whatever the answer is, and the
-- fence that can reach the body asks its own question at every mutation
-- without this one's once-a-second rate limit.
--
-- Asking at all, here, is the early tripwire: an instance parked in a
-- two-minute download would otherwise not find out it had been taken over
-- until the download ended and it tried to write something.
function M.beat()
  if not C or not C.record or C.revoked then return end
  local now = P.now()
  if C.last_beat and now - C.last_beat < 1 then return end
  C.last_beat = now
  C.host.write_file(P.beat_path(C.record.token),
    string.format("token=%s\tat=%d\n", C.record.token, now))
  M.may_mutate()
end

function M.acquire(progress_cb)
  if not C then return nil, "config", "configure() was not called" end
  if C.record then return true, "already held" end
  C.progress = progress_cb
  local started = P.now()
  local deadline = started + C.wait_seconds
  local said_at = nil
  local breaks = 0
  local asked = 0
  while true do
    local claimed, why, claim_kind = P.claim()
    if claimed then
      P.emit("lock_ok")
      return true, "acquired"
    end
    if claimed == nil then
      pcall(C.host.message_box,
        claim_kind == "identity" and IDENTITY_DIALOG or DISK_DIALOG, P.title())
      return nil, claim_kind or "disk", why
    end

    local retry_now = false
    local rec = P.read_record(C.lock_path)
    -- Bounded, because a break that keeps not happening (a filesystem that
    -- refuses the rename for a reason of its own) would otherwise spin here
    -- forever instead of reaching the wait and the dialog that tells the user
    -- something is wrong.
    if rec and breaks < C.break_attempts then
      local stale = P.stale_reason(rec)
      if stale then
        breaks = breaks + 1
        P.emit("lock_stale", stale)
        local outcome = P.break_stale(rec)
        if outcome == "conflict" then
          pcall(C.host.message_box, CONFLICT_DIALOG, P.title())
          return nil, "conflict",
            "another instance claimed the lock during a stale break"
        end
        -- "broken" and "lost" both mean the lock path may be free right now,
        -- so the ordinary claim is retried at once rather than after a wait.
        -- Falling through to the deadline check would spend the whole budget,
        -- or with a zero budget would show the wait dialog for a lock that
        -- nobody holds any more.
        retry_now = true
        said_at = nil
      end
    end
    if retry_now then goto continue end

    local now = P.now()
    if now >= deadline then
      P.emit("lock_busy", now - started)
      asked = asked + 1
      -- A cap on the whole loop, not on the user's patience: twenty rounds is
      -- ten minutes of somebody clicking Retry, and it is the difference
      -- between a launcher that gives up and one that spins forever if the
      -- dialog ever stops answering the way it is supposed to.
      if asked > C.max_dialogs then
        return nil, "busy", "the wait was retried too many times"
      end
      local message = string.format(WAIT_DIALOG, now - started)
      if C.require_dead_owner then
        message = message .. "\n\nIf waiting does not help, close every copy "
          .. "of REAPER using this installation. Then remove the lock below "
          .. "before reopening REAPER:\n" .. C.lock_path
      end
      local answer = C.host.message_box(message, P.title(), "retrycancel")
      -- REAPER's MB returns 4 for Retry and 2 for Cancel. Anything else is
      -- treated as Cancel, on the safe-list principle the engine uses: an
      -- answer nobody classified must not be read as consent to continue.
      if answer ~= 4 then
        return nil, "busy", "the user cancelled the wait"
      end
      started = P.now()
      deadline = started + C.wait_seconds
      said_at = nil
    else
      if not said_at or now - said_at >= C.say_every then
        said_at = now
        P.emit("lock_wait", now - started)
      end
      C.host.sleep(C.poll_seconds)
    end
    ::continue::
  end
end

-- Fenced, for the reason set out at the top of this file: this is a deletion of
-- a shared path, and a deletion of a shared path that has not been read is a
-- deletion of whatever happens to be there. One tokened rename takes the lock
-- out of everybody's way, the record that came with it says whether it was
-- ours, and only then is anything destroyed.
--
--   true            the lock was this instance's and is gone
--   nil, detail     ownership was lost, or the record would not delete
function M.release()
  if not C or not C.record then return true end
  local token = C.record.token
  local lost, stuck
  if C.revoked then
    -- The question the tokened rename below exists to answer has already been
    -- answered: the record at the lock path is somebody else's. So it is not
    -- read, not renamed and not removed. Taking a known-foreign record aside,
    -- even for an instant, is a mutation of the current owner's lock for no
    -- information at all.
    lost = C.revoked
  else
    local aside = C.lock_path .. ".release." .. token
    if not C.host.rename(C.lock_path, aside) then
      -- Nothing was moved, so nothing is deleted. Either another instance
      -- broke this lock and owns the path now, or the filesystem refused;
      -- neither one makes the thing at the lock path this instance's to
      -- remove.
      lost = "the lock at its own path was not this instance's to remove"
    else
      local got = P.read_record(aside)
      if got and got.token == token then
        if not P.destroy(aside) then
          -- The canonical path is free either way, which is better than the
          -- old behaviour: what is left is one file named for this instance,
          -- and the next launch is not blocked by it at all.
          stuck = "the lock could not be removed"
        end
      else
        -- A record this instance never wrote. It belongs to whoever is working
        -- now, so it goes back exactly as it was found and nothing else here
        -- is touched.
        --
        -- And when the put-back itself fails, the record is LEFT WHERE IT IS.
        -- It is the active ownership evidence of a displaced owner rather than
        -- debris: the instance that wrote it is working right now, and this is
        -- the only thing on disk that says so. Destroying it to tidy up would
        -- be this function's whole failure mode over again, one path along.
        -- What it leaves behind is one file at a name derived from THIS
        -- instance's token, which nothing reads: every instance names that path
        -- from its own token and the acquire only ever looks at the canonical
        -- path. Harmless, so it stays; see README.md.
        if not C.host.rename(aside, C.lock_path) then
          lost = "the lock had been claimed by another instance and this "
            .. "instance could not put it back"
        else
          lost = "the lock had been claimed by another instance"
        end
      end
    end
  end
  -- Both sidecars carry this instance's token, so they are this instance's to
  -- clear whatever happened above, and clearing them cannot reach a current
  -- owner's evidence.
  if C.hold_handle and type(C.host.unhold) == "function" then
    pcall(C.host.unhold, C.hold_handle)
  end
  C.hold_handle = nil
  C.host.remove(P.held_path(token))
  C.host.remove(P.beat_path(token))
  C.record = nil
  C.last_beat = nil
  -- Worth reporting rather than swallowing, and both cases are slow rather
  -- than wrong: this instance stops beating, so anything it left behind ages
  -- out on the next launch.
  if lost then return nil, lost end
  if stuck then return nil, stuck end
  return true
end

return M

end)()
-- ---------------------------------------------------------------------------
-- END embedded launcher_lock.lua
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- BEGIN embedded reaper_host.lua
-- ---------------------------------------------------------------------------
local Host = (function()
-- ============================================================================
-- reaper_host.lua - the real REAPER bindings for the launcher engine
-- ============================================================================
--
-- launcher_core.lua and launcher_lock.lua contain no `reaper.` at all: every
-- host touch goes through an injected table. This file is that table, plus the
-- scheduler that lets a synchronous engine run without freezing REAPER, plus
-- the only user interface either of them gets before the application body
-- exists. It is embedded verbatim in both shipped launchers by
-- gen_launchers.lua, so it declares only locals and returns a table.
--
-- Nothing here touches `reaper` or `gfx` at load time. That is deliberate: it
-- lets Dev/Launcher/test load this file in plain Lua and exercise the parts
-- that decide things (the command wrappers, the launch sequence) against the
-- real engine and the real lock under a stubbed host, with no REAPER running.
--
-- ----------------------------------------------------------------------------
-- Why a coroutine, and what ExecProcess actually does
-- ----------------------------------------------------------------------------
-- The engine is synchronous by design and must stay that way: it is a state
-- machine whose correctness argument is "every write happens before the act it
-- describes", and rewriting it as callbacks would put that argument back in
-- play. But a cold bootstrap downloads a whole application body, and a second
-- instance can wait thirty seconds for a lock, and REAPER runs scripts on its
-- UI thread. Blocking that thread for a minute is not acceptable.
--
-- What ExecProcess gives us, from reaper_plugin_functions.h verbatim:
--
--   "Executes command line, returns NULL on total failure, otherwise the
--    return value, a newline, and then the output of the command. If
--    timeoutmsec is 0, command will be allowed to run indefinitely
--    (recommended for large amounts of returned output). timeoutmsec is -1 for
--    no wait/terminate, -2 for no wait and minimize"
--
-- So there are exactly two shapes and neither one is what the engine wants:
--
--   timeoutmsec >= 0   waits for the command and returns its output. This is
--                      the shape that gives us an exit code and the captured
--                      text, and it blocks the UI thread for the whole run.
--   timeoutmsec < 0    returns immediately and gives us nothing at all: no
--                      exit code, no output. ReaAssist.lua also records, from
--                      the field, that this path "flashes a PowerShell/cmd
--                      window on Windows because REAPER's async path skips the
--                      hidden-window flag".
--
-- The resolution is the one the plan expects. The engine runs inside a
-- coroutine driven by a reaper.defer pump, and the two seams that can take
-- time yield instead of blocking:
--
--   sleep  yields until wall-clock time has passed.
--   exec   writes the command into a wrapper script that redirects the
--          command's output to a file and writes the exit code and then a
--          done marker beside it, launches that script detached and hidden,
--          and yields until the done marker appears. Then it reads the two
--          files back and returns exactly what ExecProcess would have
--          returned: the exit code, a newline, and the output.
--
-- The engine is unchanged and cannot tell the difference, which is the whole
-- point: no edit to launcher_core.lua was needed to make it non-blocking.
--
-- Three details of that are worth stating because they are where it could go
-- wrong.
--
-- Percent signs. A batch file eats an unmatched `%`, and the engine's curl line
-- carries `-w "reaassist_http=%{http_code};"`, which is how it tells a busy
-- server from a missing file, so everything written INTO the batch file is
-- doubled: the command and all three paths it redirects into, because a user
-- folder may contain one. The launch line is a different layer with a different
-- rule. cmd expands `%NAME%` in a command line it is handed and there is no
-- escape for it there, so the wrapper's directory is kept off that line
-- entirely: PowerShell passes it as -WorkingDirectory, which is an API
-- parameter rather than text cmd parses, and cmd is asked for the wrapper by
-- the name this launcher chose, written `.\name` because a bare one is not
-- reliably found. A UNC directory cannot go that way, because cmd refuses a
-- UNC working directory, so it travels in the child's environment instead and
-- cmd names it once as `%REAASSIST_WORK%\name`: cmd substitutes a variable
-- without rescanning what it substituted, so a literal percent in the value
-- survives.
--
-- Job identity. Every job path carries a token minted once per launcher run,
-- and the done marker carries that token and the job number in its CONTENT.
-- Without it every instance starts again at exec1 and a wrapper the launcher
-- timed out on (which is deliberately left running) can hand its exit code and
-- its output to a later launcher's job of the same number. With it, a late
-- wrapper writes to its own files. A later run can remove those files only
-- after the wrapper publishes its exact completion marker.
--
-- The detached launch is the shape ReaAssist.lua already ships and has run in
-- the field for every chat request, every update download and every dependency
-- install: a short hidden PowerShell whose only job is Start-Process, so the
-- ExecProcess call that starts it returns in about a second while the real work
-- runs behind it.
--
-- The fallback matters too. If the host is used outside the pump,
-- coroutine.isyieldable() is false and exec goes straight to ExecProcess with
-- the engine's own timeout. That blocks, which is the old behaviour, and it is
-- correct rather than fast.
--
-- ----------------------------------------------------------------------------
-- The visible surface
-- ----------------------------------------------------------------------------
-- The launcher may not assume ReaImGui, so progress is REAPER's built-in gfx:
-- a small window with a state line and a bar, driven by the same pump. It
-- opens only when there is work to do, so the ordinary launch (body present,
-- no journal) never sees it. Every state also goes to OSARA, because a gfx
-- window is not something a screen reader can read.
--
-- In Screen Reader mode it does not open at all (decision 10a.9). The window
-- takes keyboard focus when it appears and carries nothing a screen reader can
-- read, so for that user it is an interruption with no content. The
-- announcements carry every state either way, and the native dialogs are
-- untouched: a failure still stops the launch with something the user can read
-- and dismiss.
-- ============================================================================

local H = {}
local P = {}

-- How often the pump asks whether a detached command has finished. The pump
-- itself runs at REAPER's defer rate; polling the filesystem that fast for two
-- minutes would be thousands of pointless stats.
H.EXEC_POLL = 0.25
-- How long to wait for the short hidden launcher process itself. Not the
-- command: the command runs detached behind it.
H.LAUNCH_TIMEOUT = 5000
-- Slack added to the engine's own timeout to cover the launch, which on a cold
-- Windows machine is one PowerShell start.
H.LAUNCH_SLACK = 20

-- ----------------------------------------------------------------------------
-- The mutation fence
-- ----------------------------------------------------------------------------
-- launcher_lock.lua sets out why an instance whose lock has been broken has to
-- be stopped rather than trusted. This is where it is stopped: every seam that
-- changes the filesystem asks the lock whether this instance still owns it,
-- immediately before it acts.
--
-- A refusal RAISES rather than returning a failure, and that is deliberate. A
-- failure would be handed back to the engine, which would classify it, report
-- it, and on several paths try to undo what it had already done, and every one
-- of those is another mutation by an instance that must not be mutating. An
-- error unwinds the coroutine at the exact statement that was refused, the
-- pump never resumes it, and the user gets one explanation instead of a disk
-- failure that was not a disk failure.
--
-- Reads are not fenced. A probe or a journal read changes nothing, and making
-- it pay for a record read as well would tax every launch that is doing
-- nothing wrong.
H.REVOKED = "reaassist_lock_revoked"

-- `exec` is one of them because everything the engine runs through it exists to
-- write files, so starting one is a mutation whatever the command line says.
H.FENCED_SEAMS = { "write_file", "remove", "rename", "make_dir", "exec" }

-- Raise if this host has a fence and the fence says no. `what` only ever
-- reaches a crash string, so it is a label rather than data.
function H.gate(host, what)
  if host.may_mutate and not host.may_mutate() then
    error(H.REVOKED .. ": " .. tostring(what), 0)
  end
end

-- Fence a host IN PLACE rather than wrapping a copy of it. host.exec performs
-- mutations of its own through these same seams, and a copy would leave the
-- original's calls unfenced while the engine used the fenced ones.
--
-- The lock's host is deliberately never fenced. The lock is what the fence
-- asks, and its acquire has to stage a file and rename it before it owns
-- anything, so fencing it would be circular.
function H.fence_host(host, may_mutate)
  host.may_mutate = may_mutate
  for _, name in ipairs(H.FENCED_SEAMS) do
    local inner = host[name]
    if type(inner) == "function" then
      host[name] = function(...)
        H.gate(host, name)
        return inner(...)
      end
    end
  end
  return host
end

-- ----------------------------------------------------------------------------
-- Shell quoting
-- ----------------------------------------------------------------------------

-- Doubles single quotes for a PowerShell '...' literal. No outer quotes added.
function H.ps_escape(s)
  return (tostring(s):gsub("'", "''"))
end

-- A complete POSIX shell single-quoted literal.
function H.sh_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- A batch file eats a percent sign it cannot resolve, so a literal one is
-- written twice. This is applied to the engine's command line and to every
-- path the wrapper redirects into, because a user folder may contain one. It
-- is NOT the right escape for the cmd command line, which reduces nothing:
-- see the launch below, which keeps paths off that line instead.
function H.bat_escape(s)
  return (tostring(s):gsub("%%", "%%%%"))
end

-- The environment variable a UNC launch carries its wrapper's folder in. It is
-- set in the child's environment and named once on the cmd line, which is the
-- only way found to keep a path with a literal percent in it out of cmd's
-- reach when -WorkingDirectory is not available. See build_exec_job.
H.WORK_VAR = "REAASSIST_WORK"

-- A token no other run can produce, minted the way the lock mints its own:
-- os.time pins the second, math.random is seeded per process by Lua 5.4
-- itself, and the address of a fresh table is unique inside this process and
-- varies between processes under address space layout randomisation. It only
-- ever appears in file names this module chooses, so it carries nothing but
-- digits, hyphens and hex.
function H.mint_token()
  local addr = tostring({}):match("[x%x]+$") or "0"
  return string.format("%d-%d-%s", os.time(),
    math.random(1, 2147483647), addr)
end

-- ----------------------------------------------------------------------------
-- The exec wrapper
-- ----------------------------------------------------------------------------
-- Pure: no reaper, no filesystem. Returns the script to write, the command
-- that launches it, the three paths the wrapper produces, and the exact text
-- its done marker will carry. Written this way so the test suite can generate
-- the script, run it for real, and check that the exit code, the percent signs
-- and the job identity all survived.
--
-- `ident` is what makes a finished job this run's rather than somebody else's.
-- It goes into the marker's content as well as into every path, and the two
-- protect against different things: the paths stop a late wrapper writing over
-- a live job's files, and the content stops a live job reading a marker it did
-- not cause.

function H.build_exec_job(cmd, base, os_name, ident)
  local job = {
    out = base .. ".out", code = base .. ".code", done = base .. ".done",
    marker = "done" .. (ident and (" " .. tostring(ident)) or ""),
  }
  if (tostring(os_name or "")):match("^Win") then
    job.style = "win"
    job.script = base .. ".bat"
    local out, code, done =
      H.bat_escape(job.out), H.bat_escape(job.code), H.bat_escape(job.done)
    job.script_text = table.concat({
      "@echo off",
      "setlocal",
      -- The command's own output, both streams, into one file.
      H.bat_escape(cmd) .. ' 1>"' .. out .. '" 2>&1',
      "set RA_RC=%ERRORLEVEL%",
      -- Redirection first. `echo 0>"file"` would be read as a file-descriptor
      -- redirect and write nothing, and the exit code is usually a digit.
      '>"' .. code .. '" echo %RA_RC%',
      -- Last, so its presence means the two files above are complete, and it
      -- names the job it belongs to so nobody else's completion is read as
      -- this one's.
      '>"' .. done .. '" echo ' .. H.bat_escape(job.marker),
      "",
    }, "\r\n")
    -- The shape ReaAssist.lua already ships: a short hidden PowerShell that
    -- does nothing but Start-Process, so the ExecProcess that runs it returns
    -- while the real work continues behind it.
    --
    -- The wrapper's directory does not cross into the cmd command line, and
    -- that is the whole point: cmd expands %NAME% there and offers no escape
    -- for a literal one, so a resource folder with a percent in its name would
    -- be mangled beyond quoting's reach. There are two ways to keep it off that
    -- line and the local one does not work for a UNC path, so there are two
    -- routes rather than one:
    --
    --   "workdir", for an ordinary local folder. -WorkingDirectory is a
    --   parameter PowerShell hands to the process API rather than text cmd
    --   parses, so cmd starts inside the folder and is asked for the wrapper by
    --   the bare name this launcher chose. The name is written `.\name`,
    --   explicitly relative, because a bare one is not reliably found even from
    --   the directory it sits in: a machine with
    --   NoDefaultCurrentDirectoryInExePath set (a policy, not a rarity) takes
    --   the current directory out of the implicit search path and cmd answers
    --   "not recognized as an internal or external command".
    --
    --   "env", for a UNC folder, which cannot use the above: cmd refuses a UNC
    --   working directory outright ("UNC paths are not supported. Defaulting to
    --   Windows directory") and then cannot find `.\name` at all. So the folder
    --   travels in the CHILD'S ENVIRONMENT, which is not command text either,
    --   and cmd is given `%REAASSIST_WORK%\name`. cmd substitutes that once and
    --   does not rescan what it substituted, so a literal percent inside the
    --   value survives. Two details are load bearing and both were found by
    --   running them rather than by reasoning: `call` must NOT be used, because
    --   call runs a second expansion pass over its own line and that pass does
    --   reach the substituted value; and the quotes are doubled, because
    --   `cmd /c "..."` strips one leading and trailing pair and the path has a
    --   space in it. The variable is named to be unmistakable rather than
    --   short, since a name the user already had set would be substituted
    --   instead of ours.
    local dir = job.script:match("^(.*)[\\/][^\\/]+$")
    local name = job.script:match("[^\\/]+$")
    local route = "absolute"
    if dir and dir ~= "" and name then
      route = dir:match("^\\\\") and "env" or "workdir"
    end
    local prefix, where, inner = "", "", nil
    if route == "workdir" then
      where = " -WorkingDirectory '" .. H.ps_escape(dir) .. "'"
      inner = 'call """.\\' .. name .. '"""'
    elseif route == "env" then
      prefix = "$env:" .. H.WORK_VAR .. " = '" .. H.ps_escape(dir) .. "'; "
      inner = '""""""%' .. H.WORK_VAR .. '%\\' .. name .. '""""""'
    else
      inner = 'call """' .. job.script .. '"""'
    end
    job.launch = 'powershell -NoProfile -WindowStyle Hidden -Command '
      .. '"' .. prefix .. 'Start-Process cmd -ArgumentList \'/c '
      .. H.ps_escape(inner) .. '\'' .. where .. ' -WindowStyle Hidden"'
  else
    job.style = "posix"
    job.script = base .. ".sh"
    job.script_text = table.concat({
      "#!/bin/sh",
      "{ " .. cmd .. " ; } > " .. H.sh_quote(job.out) .. " 2>&1",
      'echo "$?" > ' .. H.sh_quote(job.code),
      "echo " .. H.sh_quote(job.marker) .. " > " .. H.sh_quote(job.done),
      "",
    }, "\n")
    job.launch = "(/bin/sh " .. H.sh_quote(job.script)
      .. " >/dev/null 2>&1) &"
  end
  return job
end

-- ----------------------------------------------------------------------------
-- Waiting
-- ----------------------------------------------------------------------------

function P.now()
  if type(reaper) == "table" and type(reaper.time_precise) == "function" then
    return reaper.time_precise()
  end
  return os.clock()
end

-- Yield until `ready` says so or the budget runs out. Returns whether ready
-- fired. Outside the pump this blocks, which is the honest degradation: the
-- work still happens and still returns the right answer.
function H.await(ready, timeout)
  local deadline = P.now() + (tonumber(timeout) or 0)
  if not coroutine.isyieldable() then
    while P.now() < deadline do
      if ready and ready() then return true end
    end
    return (ready and ready()) and true or false
  end
  while true do
    if ready and ready() then return true end
    if P.now() >= deadline then return false end
    coroutine.yield()
  end
end

-- ----------------------------------------------------------------------------
-- Plain file helpers, shared by the seams and by the wrapper plumbing
-- ----------------------------------------------------------------------------

function P.read(path, limit)
  if limit~=nil and (type(limit)~="number" or limit<1 or limit%1~=0) then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local read_ok,data,read_error = pcall(f.read,f,limit or "*a")
  local close_ok,closed = pcall(f.close,f)
  if not read_ok or read_error~=nil or not close_ok or not closed then return nil end
  return data or ""
end

function P.write(path, data)
  local f = io.open(path, "wb")
  if not f then return nil end
  local ok = pcall(function() assert(f:write(data)) end)
  local closed = pcall(function() assert(f:close()) end)
  if not ok or not closed then return nil end
  return true
end

function P.size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

-- Is something at this name, asked the way a refusal gate has to ask it.
--
-- io.open answering nil is not proof of absence: a file that is there but
-- locked or unreadable answers the same way as one that is not there at all.
-- The uninstall gate and transaction recovery both require proof of absence.
-- A rename probe follows the open; only a real ENOENT counts as gone.
function P.present(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  local renamed, _, code = os.rename(path, path)
  if renamed then return true end
  return tonumber(code) ~= 2
end

-- ----------------------------------------------------------------------------
-- The host table
-- ----------------------------------------------------------------------------

function H.new_host(opts)
  opts = opts or {}
  local sep = opts.sep or package.config:sub(1, 1)
  local work = opts.work_dir
  local host = {}
  local jobs = 0
  -- Once per launcher run, so every wrapper file this instance writes is
  -- named for this instance and nothing it reads can belong to another. Also
  -- published on the table, because the engine needs the same identity for its
  -- download destinations and one run should have one name rather than two.
  local run_token = opts.run_token or H.mint_token()
  host.run_token = run_token

  function host.os_name()
    return reaper.GetOS()
  end

  local function is_windows()
    return (tostring(host.os_name() or "")):match("^Win") ~= nil
  end

  -- kind is nil for a plain notice, "retrycancel" for the lock's wait dialog,
  -- and "yesno" for the uninstall gate's deliberate reinstall question.
  -- REAPER's MB returns 4 for Retry and 2 for Cancel, 6 for Yes and 7 for No.
  function host.message_box(text, title, kind)
    local flag = 0
    if kind == "retrycancel" then
      flag = 5
    elseif kind == "yesno" then
      flag = 4
    end
    local ok, answer = pcall(reaper.MB, tostring(text),
      tostring(title or "ReaAssist"), flag)
    if not ok then return nil end
    return answer
  end

  function host.announce(text)
    if reaper.osara_outputMessage then
      pcall(reaper.osara_outputMessage, tostring(text))
    end
  end

  host.read_file = P.read
  host.write_file = P.write
  host.file_size = P.size
  host.present = P.present

  function host.generation_token()
    if type(reaper.genGuid)~="function" then return nil end
    local ok,guid=pcall(reaper.genGuid,"")
    if not ok or type(guid)~="string" then return nil end
    local token=guid:match("^%{([%x%-]+)%}$")
    if not token or not token:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return nil end
    return token:gsub("%-",""):lower()
  end

  function host.make_dir(path)
    reaper.RecursiveCreateDirectory(path, 0)
  end

  function host.remove(path) return os.remove(path) end
  function host.rename(from, to) return os.rename(from, to) end

  -- The launch check. loadfile is standard Lua rather than a REAPER API, so
  -- this keeps the engine's rule that it depends on nothing the body provides.
  -- Compiling does not run the body.
  function host.compile(path) return loadfile(path) end

  function host.sleep(seconds)
    H.await(nil, tonumber(seconds) or 0)
  end

  -- Whole seconds since the epoch, used by the lock for staleness and for its
  -- wait budget. A seam rather than a direct call inside the lock so the suite
  -- can drive both exactly.
  host.now = os.time

  -- Keep a file open for as long as this instance holds the lock. On Windows
  -- the filesystem then refuses to delete it, which is what lets a later
  -- launch tell a live owner from a dead one without a process check.
  function host.hold(path)
    local f = io.open(path, "wb")
    if not f then return nil end
    pcall(function() f:write("held\n") f:flush() end)
    return f
  end

  function host.unhold(handle)
    if handle then pcall(function() handle:close() end) end
  end

  -- POSIX only, and only because the held-file trick does not work there:
  -- unlinking an open file is allowed. The shell that io.popen forks is a
  -- direct child of REAPER, so its $PPID is REAPER's process id.
  function host.pid()
    if is_windows() then return nil end
    local ok, pipe = pcall(io.popen, "printf '%s\\n' \"$PPID\"")
    if not ok or not pipe then return nil end
    local text = pipe:read("*a") or ""
    pcall(function() pipe:close() end)
    local pid = text:match("(%d+)")
    return pid
  end

  -- A PID can be reused after a process exits. Keep its birth identity with
  -- strict claims so an unrelated later process does not strand the lock.
  function host.pid_start(pid)
    pid = tostring(pid or "")
    if is_windows() or not pid:match("^%d+$") then return nil end
    local platform = host.os_name() or ""
    if platform == "Other" or platform:match("^Linux") then
      local stat = host.read_file("/proc/" .. pid .. "/stat")
      local boot = host.read_file("/proc/sys/kernel/random/boot_id")
      local fields = type(stat) == "string" and stat:match("^%d+ %(.+%) (.+)$")
      boot = type(boot) == "string" and boot:match("^([%x%-]+)%s*$")
      if not fields or not boot or #boot ~= 36 then return nil end
      local index = 0
      for value in fields:gmatch("%S+") do
        index = index + 1
        if index == 20 then
          if not value:match("^%d+$") then return nil end
          return "linux:" .. boot .. ":" .. value
        end
      end
      return nil
    end
    if platform ~= "macOS-arm64" and not platform:match("^OSX") then return nil end
    local opened, pipe = pcall(io.popen,
      "LC_ALL=C TZ=UTC0 /bin/ps -p " .. pid .. " -o lstart= 2>/dev/null")
    if not opened or not pipe then return nil end
    local read_ok, text = pcall(pipe.read, pipe, "*a")
    local closed, ok = pcall(pipe.close, pipe)
    if not read_ok or not closed or (ok ~= true and ok ~= 0) then return nil end
    text = tostring(text):match("^%s*(.-)%s*$")
    if not text:match("^%a%a%a %a%a%a +%d%d? %d%d:%d%d:%d%d %d%d%d%d$") then return nil end
    return "mac:" .. text
  end

  -- true, false, or nil for "cannot tell". Unlike kill -0, ps distinguishes
  -- an absent process from a signal-permission failure.
  function host.pid_alive(pid, start)
    if is_windows() then return nil end
    if not tostring(pid or ""):match("^%d+$") then return nil end
    local opened, pipe = pcall(io.popen, "ps -p " .. pid .. " -o pid= 2>/dev/null")
    if not opened or not pipe then return nil end
    local read_ok, text = pcall(pipe.read, pipe, "*a")
    local closed, ok, how, code = pcall(pipe.close, pipe)
    if not read_ok or not closed then return nil end
    text = tostring(text):match("^%s*(.-)%s*$")
    if (ok == true or ok == 0) and text == tostring(pid) then
      if start ~= nil then
        local actual = host.pid_start(pid)
        if not actual then return nil end
        return actual == start
      end
      return true
    end
    if how == "exit" and code == 1 and text == "" then return false end
    return nil
  end

  -- Fenced from the outside like the other mutating seams, and gated once more
  -- inside, immediately before the launch: the wait between writing the wrapper
  -- and starting it is long enough for the answer to change, and starting a
  -- process is the one mutation no seam can take back.
  function host.exec(cmd, timeout_ms)
    if not coroutine.isyieldable() or not work then
      -- No pump to resume us, so the only honest option is the blocking call
      -- with the engine's own budget.
      return reaper.ExecProcess(cmd, tonumber(timeout_ms) or 0)
    end
    jobs = jobs + 1
    host.make_dir(work)
    -- Retry completed command cleanup on the first job. Unfinished commands
    -- can outlive their launcher and must keep their files.
    if jobs == 1 then H.sweep_work(host, work, run_token) end
    local base = work .. sep .. "exec." .. run_token .. "." .. tostring(jobs)
    local job = H.build_exec_job(cmd, base, host.os_name(),
      "token=" .. run_token .. " job=" .. tostring(jobs))
    for _, path in ipairs({ job.script, job.out, job.code, job.done }) do
      if host.present(path) ~= false then return nil end
    end
    if not host.write_file(job.script, job.script_text) then return nil end
    H.gate(host, "exec launch")
    if job.style == "win" then
      reaper.ExecProcess(job.launch, H.LAUNCH_TIMEOUT)
    else
      os.execute(job.launch)
    end
    local budget = (tonumber(timeout_ms) or 0)
    budget = (budget > 0 and budget / 1000 or 300) + H.LAUNCH_SLACK
    local last = 0
    local finished = H.await(function()
      local now = P.now()
      if now - last < H.EXEC_POLL then return false end
      last = now
      -- The marker's content, not its existence. A file at this path that
      -- names another job is not this job finishing.
      return H.exec_completed(host, job)
    end, budget)
    local answer = nil
    if finished then
      local code = (P.read(job.code) or ""):match("(%-?%d+)")
      if code then answer = code .. "\n" .. (P.read(job.out) or "") end
    end
    if finished then H.cleanup_exec(host, job) end
    return answer
  end

  return host
end

function H.exec_completed(host, job)
  local text = host.read_file(job.done, #job.marker + 3)
  return text == job.marker .. "\n" or text == job.marker .. "\r\n"
end

-- Keep completion evidence until every payload is positively absent. Every
-- removal uses the fenced seam, including retries after a sharing failure.
function H.cleanup_exec(host, job)
  if not H.exec_completed(host, job) then return false end
  local cleared = true
  for _, path in ipairs({ job.script, job.out, job.code }) do
    if host.present(path) ~= false then host.remove(path) end
    if host.present(path) ~= false then cleared = false end
  end
  if not cleared then return false end
  host.remove(job.done)
  return host.present(job.done) == false
end

-- Bounded completion sweep. A foreign run token alone never proves that its
-- command finished. Unknown files and jobs without final evidence stay put.
function H.sweep_work(host, dir, token)
  if type(reaper) ~= "table"
      or type(reaper.EnumerateFiles) ~= "function" then
    return
  end
  local sep = package.config:sub(1, 1)
  local names = {}
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(dir, i)
    if not name then break end
    local owner, number = name:match("^exec%.([%w%-]+)%.([1-9]%d*)%.done$")
    if owner and #owner <= 128 and #number <= 16 and owner ~= token then
      names[#names + 1] = { owner = owner, number = number }
    end
    i = i + 1
    if i > 500 then break end
  end
  for _, entry in ipairs(names) do
    local base = dir .. sep .. "exec." .. entry.owner .. "." .. entry.number
    H.cleanup_exec(host, H.build_exec_job("", base, host.os_name(),
      "token=" .. entry.owner .. " job=" .. entry.number))
  end
end

-- ----------------------------------------------------------------------------
-- The one question that may be asked before the lock is taken
-- ----------------------------------------------------------------------------
-- Free of `reaper.` on purpose, so the REAPER-free suite runs this exact text.

-- Every generation launcher_core.lua can leave behind. The launcher may skip
-- the lock only when NONE of these exists, so this list has to stay in step
-- with the engine; the suite reads both files and fails if the engine ever
-- writes a suffix this does not name.
function H.journal_generations(journal_path)
  return { journal_path, journal_path .. ".old", journal_path .. ".tmp" }
end

-- ----------------------------------------------------------------------------
-- The critical-file list, read from the manifest
-- ----------------------------------------------------------------------------
-- Decision 10a.3: each manifest entry carries a `critical` flag, and the
-- launcher probe and the body's per-tick sentinel read the same list, so the
-- definition ships per release instead of being frozen into two files that
-- change once a year.
--
-- Deliberately a scan rather than a JSON decode. The engine's decoder is
-- private to the engine, this runs before anything the body provides exists,
-- and the file being read is one this project generates: entries are flat
-- objects with a name, a checksum and optionally the flag. Anything this
-- cannot read returns nil and the caller falls back to its built-in list,
-- which is the same failure the launcher already handles when the body (and so
-- the manifest) is missing entirely.
function H.critical_from_manifest(text)
  if type(text) ~= "string" or text == "" then return nil end
  local files = text:match('"files"%s*:%s*%[(.*)')
  if not files then return nil end
  local out, seen = {}, {}
  for entry in files:gmatch("{(.-)}") do
    if entry:match('"critical"%s*:%s*true') then
      local name = entry:match('"name"%s*:%s*"([^"]*)"')
      -- The same shape launcher_core.lua's safe_name demands. A manifest that
      -- names something outside it is not something to pass along.
      if name and name ~= "" and name:match("^[A-Za-z0-9_./ %-]+$")
          and not name:find("..", 1, true) and not seen[name:lower()] then
        seen[name:lower()] = true
        out[#out + 1] = name
      end
    end
  end
  if #out == 0 then return nil end
  return out
end

-- Guarantee the file the launcher is about to compile is in the list it probes
-- for, whatever the manifest said. In Screen Reader mode the body main is the
-- Screen Reader entry point, which the shipped critical set need not name.
function H.with_body_main(list, body_main)
  local out = {}
  local seen = {}
  for _, name in ipairs(list or {}) do
    if not seen[name:lower()] then
      seen[name:lower()] = true
      out[#out + 1] = name
    end
  end
  if body_main and not seen[body_main:lower()] then
    table.insert(out, 1, body_main)
  end
  return out
end

-- Reading is safe without the lock; deciding is not.
--
-- A journal on disk means some instance opened a transaction, so the launcher
-- gets in line BEFORE it resolves anything: two instances resolving one
-- journal is exactly the interleaving the lock exists for. No journal means no
-- live file has moved, because the engine writes the journal before the first
-- rename, so at the instant of this check nobody is part way through anything
-- and the launcher may go on to ask the engine what it thinks.
--
-- This is not a substitute for resolve_pending and never answers on its
-- behalf. It only decides whether to queue first.
function H.pending_journal(host, journal_path)
  for _, path in ipairs(H.journal_generations(journal_path)) do
    if host.present(path) ~= false then return true end
  end
  return false
end

-- ----------------------------------------------------------------------------
-- The gfx progress surface
-- ----------------------------------------------------------------------------

-- `enabled` is decision 10a.9: in Screen Reader mode there is no window at
-- all, and everything below turns into announcements and nothing else.
local Surface = {
  open = false, enabled = true, text = "", pct = 0, title = "ReaAssist",
}

-- Rough, monotonic, and only ever used to fill a bar. The engine's states
-- arrive in this order on a cold bootstrap.
local WEIGHT = {
  recovering = 0.05, recovered = 0.10, probing = 0.12,
  lock_wait = 0.05, lock_stale = 0.06, lock_ok = 0.10, lock_busy = 0.05,
  parked_check = 0.20, parked_ok = 0.45, parked_bad = 0.20,
  manifest = 0.25, downloading = 0.35, verifying = 0.60,
  applying = 0.75, confirming = 0.90, done = 1.00, failed = 1.00,
}

function H.surface_open(title)
  if Surface.open or not Surface.enabled then return end
  if type(gfx) ~= "table" or type(gfx.init) ~= "function" then return end
  Surface.title = title or "ReaAssist"
  local ok = pcall(function()
    gfx.init(Surface.title, 520, 150, 0)
    gfx.setfont(1, "Arial", 16)
  end)
  Surface.open = ok and true or false
end

function H.surface_event(event)
  if type(event) ~= "table" then return end
  -- Opened here rather than up front, so the ordinary launch (no journal, body
  -- present) emits nothing, opens nothing, and looks exactly like a launcher
  -- with no progress surface in it.
  H.surface_open(Surface.wanted_title)
  if event.state == "file" then
    if event.total and event.total > 0 then
      local span = 0.25
      Surface.pct = 0.35 + span * (event.index or 0) / event.total
    end
    Surface.detail = tostring(event.detail or "")
    return
  end
  Surface.text = tostring(event.text or event.state or "")
  Surface.detail = nil
  local weight = WEIGHT[event.state]
  if weight and weight > Surface.pct then Surface.pct = weight end
end

-- Called once per pump tick. A user who closes the window gets no more
-- progress and the bootstrap continues: there is no cancel here, because the
-- engine's transactions are not cancellable part way through, and pretending
-- otherwise would be the lie.
function H.surface_draw()
  if not Surface.open then return end
  local ok = pcall(function()
    if gfx.getchar() == -1 then
      Surface.open = false
      gfx.quit()
      return
    end
    local w, h = gfx.w, gfx.h
    gfx.set(0.106, 0.110, 0.129, 1)
    gfx.rect(0, 0, w, h, 1)
    gfx.set(0.92, 0.93, 0.95, 1)
    gfx.x, gfx.y = 20, 22
    gfx.drawstr(Surface.title)
    gfx.set(0.75, 0.77, 0.82, 1)
    gfx.x, gfx.y = 20, 54
    gfx.drawstr(Surface.text)
    if Surface.detail then
      gfx.set(0.55, 0.57, 0.62, 1)
      gfx.x, gfx.y = 20, 76
      gfx.drawstr(Surface.detail)
    end
    local bx, by, bw, bh = 20, h - 42, w - 40, 14
    gfx.set(0.20, 0.21, 0.25, 1)
    gfx.rect(bx, by, bw, bh, 1)
    gfx.set(0.29, 0.56, 0.91, 1)
    gfx.rect(bx, by, math.floor(bw * math.min(1, Surface.pct)), bh, 1)
    gfx.update()
  end)
  if not ok then Surface.open = false end
end

function H.surface_close()
  if not Surface.open then return end
  Surface.open = false
  pcall(function() gfx.quit() end)
end

-- ----------------------------------------------------------------------------
-- The pump
-- ----------------------------------------------------------------------------

local CRASH =
  "ReaAssist could not finish starting up.\n\nNothing further was changed. "
  .. "Close any other copies of REAPER and start REAPER again. If this keeps "
  .. "happening, reinstall from https://reaassist.app\n\nDetail: %s"

-- deps carries lock, host, title, sequence (a function returning "run" or
-- "stop") and launch (what to run when the sequence says "run"). The sequence
-- lives in the launcher itself rather than here, because the order it works in
-- IS the contract and it should be readable in the shipped file.
--
-- On the ordinary launch the sequence returns without ever yielding, so this
-- runs once, at the top level, and the body starts exactly as it would from a
-- launcher with no scheduler in it at all. The pump only becomes a pump when
-- there is real work.
function H.run(deps)
  Surface.wanted_title = deps.title or "ReaAssist"
  -- Decision 10a.9. Every state still reaches OSARA, and message_box is
  -- untouched, so nothing a Screen Reader user needs is behind the window.
  Surface.enabled = (deps.mode ~= "sr")
  deps.progress = function(event)
    H.surface_event(event)
    H.surface_draw()
  end

  local co = coroutine.create(function() return deps.sequence(deps) end)

  -- The launcher stopped because another copy of REAPER took the lock off it.
  -- Not a crash, so not the crash dialog: nothing here is damaged, and the
  -- coroutine is simply never resumed, so the mutation it was parked in front
  -- of never happens. release() in this state clears this instance's own
  -- sidecars and leaves the canonical path alone, because that path is known
  -- to belong to whoever is working now.
  local function give_up()
    pcall(deps.lock.release)
    H.surface_close()
    pcall(deps.lock.report_revoked)
  end

  local function pump()
    -- The early tripwire. The fence at every mutating seam is what protects
    -- the tree; this is what keeps a launcher parked in a two-minute download
    -- from waiting for the download to end before it finds out.
    if deps.lock.revoked and deps.lock.revoked() then return give_up() end
    local alive, state, kind, detail = coroutine.resume(co)
    if not alive then
      if deps.lock.revoked and deps.lock.revoked() then return give_up() end
      pcall(deps.lock.release)
      H.surface_close()
      pcall(deps.host.announce, "ReaAssist could not finish starting up.")
      pcall(deps.host.message_box,
        string.format(CRASH, tostring(state)), deps.title)
      return
    end
    if coroutine.status(co) ~= "dead" then
      -- The heartbeat is what tells a later launch this instance is alive, so
      -- it ticks from here rather than from the engine, which knows nothing
      -- about the lock.
      pcall(deps.lock.beat)
      H.surface_draw()
      reaper.defer(pump)
      return
    end
    -- A revoked instance does not run the body either. Whatever it learned
    -- about the body, another copy of REAPER has been installing over it
    -- since, and the sentence the user needs is the same one.
    if deps.lock.revoked and deps.lock.revoked() then return give_up() end
    H.surface_close()
    if state == "run" then
      -- Keep the claim until synchronous app initialization publishes its
      -- life file. Releasing before dofile leaves an unannounced reader.
      local launched, launch_error = pcall(deps.launch)
      pcall(deps.lock.release)
      if not launched then error(launch_error, 0) end
    else
      pcall(deps.lock.release)
      local _ = kind, detail
    end
  end

  pump()
end

return H

end)()
-- ---------------------------------------------------------------------------
-- END embedded reaper_host.lua
-- ---------------------------------------------------------------------------

-- Two hosts, and the only difference between them is the fence. Everything the
-- engine touches goes through `host`, which is fenced below once the lock can
-- answer for it. The lock gets one of its own that is never fenced, because
-- the lock IS what the fence asks: its acquire has to stage a file and rename
-- it before it owns anything, so fencing it would be circular.
local host = Host.new_host({ sep = sep, work_dir = at(WORK_REL) })
local lock_host = Host.new_host({ sep = sep })

local function fail_to_start(what)
  pcall(host.announce, TITLE .. ": ReaAssist could not start its installer.")
  pcall(host.message_box,
    "ReaAssist could not start its installer.\n\n" .. tostring(what), TITLE)
end

-- ---------------------------------------------------------------------------
-- The uninstall gate
-- ---------------------------------------------------------------------------
-- This is the first thing the launcher does, before the journal is read,
-- before the body is probed and before any lock is taken, because it is the
-- one question whose wrong answer cannot be undone: an uninstall running in
-- another REAPER window right now cannot see a launcher that starts after its
-- last check, and a launcher that walks past it starts a live session on files
-- that are being deleted.
--
-- So the uninstaller writes a marker before its gate finishes, and a launcher
-- that finds it does not load the body and does not bootstrap.
--
-- WHAT IT DOES INSTEAD DEPENDS ON THE PHASE, and that is the whole of the
-- gate. While a removal is RUNNING, or was running and never reached its end,
-- there is nothing to ask: the offer to put ReaAssist back would be an offer
-- to clear the exclusion in the middle of the run, and one click over here
-- would then start the body on files another REAPER window is deleting. So an
-- active marker is refused outright, with no question and no way past it.
-- Only a marker that says the removal FINISHED carries the deliberate
-- reinstall question, and only a yes to that question removes it. That is what
-- makes a reinstall deliberate: nothing here clears the marker on its own, so
-- an uninstalled install stays uninstalled until somebody says otherwise,
-- however many times an action is run.
--
-- EVERY UNCERTAIN ANSWER IS THE ACTIVE ONE. A marker that cannot be read, or
-- whose first line is not exactly the done line, is treated as a removal in
-- progress, because that is the answer that refuses.
--
-- The gate is asked TWICE, here and again immediately before the body is
-- loaded, which is as narrow as this side can make the window: what is left is
-- the gap between the second read and the body's own first write, and it is
-- named rather than claimed closed.
local function uninstall_marker_phase()
  if not host.present(at(MARKER_REL)) then return nil end
  local text = host.read_file(at(MARKER_REL))
  if type(text) == "string"
      and text:sub(1, #MARKER_DONE + 1) == MARKER_DONE .. "\n" then
    return "done"
  end
  return "active"
end

local function uninstall_gate()
  local phase = uninstall_marker_phase()
  if not phase then return true end
  if phase ~= "done" then
    pcall(host.announce, TITLE .. ": ReaAssist is being removed from this "
      .. "computer, so this action did not start it.")
    pcall(host.message_box,
      "ReaAssist is being removed from this computer, so this action did not "
      .. "start it.\n\nThe note that says so is here:\n" .. at(MARKER_REL)
      .. "\n\nWait for the removal to finish, then run this action again. If "
      .. "nothing is removing ReaAssist, the last removal was interrupted: "
      .. "delete that file yourself and run this action again.", TITLE)
    return false
  end
  local question =
    "ReaAssist was uninstalled on this computer, so this action did not "
    .. "start it.\n\nThe note that says so is here:\n" .. at(MARKER_REL)
    .. "\n\nInstall ReaAssist again now?"
  pcall(host.announce, TITLE .. ": ReaAssist was uninstalled on this "
    .. "computer. This action did not start it. Answer yes to install "
    .. "ReaAssist again.")
  local answer = host.message_box(question, TITLE, "yesno")
  -- 6 is Yes. Anything else, including a dialog that could not be shown at
  -- all, leaves the marker where it is and stops, because the only answer that
  -- may undo an uninstall is a yes somebody actually gave.
  if answer ~= 6 then
    pcall(host.announce, TITLE .. ": ReaAssist was not started.")
    return false
  end
  host.remove(at(MARKER_REL))
  if uninstall_marker_phase() then
    pcall(host.announce, TITLE .. ": ReaAssist could not remove the note.")
    pcall(host.message_box,
      "ReaAssist could not remove the note that records the uninstall, so it "
      .. "did not start.\n\nThe note is here:\n" .. at(MARKER_REL)
      .. "\n\nDelete that file yourself, then run this action again.", TITLE)
    return false
  end
  return true
end

if not uninstall_gate() then return end

-- The list the probe uses. Read from the body's own manifest so the definition
-- ships per release, with the body main forced in because that is the file the
-- launch check compiles.
local critical = Host.with_body_main(
  Host.critical_from_manifest(host.read_file(at(MANIFEST_REL)))
    or FALLBACK_CRITICAL,
  BODY_MAIN)

local configured, why = core.configure({
  host             = host,
  sep              = sep,
  mode             = LAUNCHER_MODE,
  body_root        = at(BODY_REL),
  body_main        = BODY_MAIN,
  critical_files   = critical,
  parked_root      = at(PARKED_REL),
  candidate_root   = at(CANDIDATE_REL),
  journal_path     = at(JOURNAL_REL),
  -- One identity for the whole run: the exec wrapper's files and the engine's
  -- download destinations are both named for it, so nothing this launcher
  -- abandons can ever be at a path the next launcher reads.
  run_token        = host.run_token,
  manifest_url     = MANIFEST_URL,
  payload_base_url = PAYLOAD_BASE,
})
if not configured then
  fail_to_start(why)
  return
end

local locked, lock_why = lock.configure({
  host      = lock_host,
  sep       = sep,
  mode      = LAUNCHER_MODE,
  lock_path = at(LOCK_REL),
})
if not locked then
  fail_to_start(lock_why)
  return
end

-- Every mutation the engine performs from here on asks the lock, immediately
-- before it acts, whether this instance still owns it. Applied in place, so
-- the host the engine was configured with above is the fenced one, and so is
-- the wrapper's own file work inside host.exec.
Host.fence_host(host, lock.may_mutate)

-- ---------------------------------------------------------------------------
-- The sequence
-- ---------------------------------------------------------------------------
-- Read this in order, because the order is the contract.
--
-- 1. A journal on disk means a transaction is open. Get in line before
--    touching it: two instances resolving one journal is the interleaving the
--    lock exists for.
-- 2. Resolve, under the lock, before anything looks at the body. probe() only
--    asks whether the critical files exist and are nonempty, so a crash that
--    landed those and not the rest leaves a body that looks whole behind a
--    journal nobody resolved. A journal that could not be resolved is the one
--    case where the body does not run: something is part applied, nobody can
--    say what, and running it would be guessing.
--
--    Resolving is a mutation, so it never happens outside the lock. Step 1
--    reads the journal generations and resolve_pending reads them again a
--    moment later, and another instance could open a transaction in between;
--    resolving unlocked in that window would put two launchers on one journal.
--    When step 1 found nothing there is nothing to resolve, and the launch
--    either goes straight through or takes the lock at step 4 and resolves
--    there.
-- 3. Probe. Present is the ordinary launch and it ends here, having taken no
--    lock, opened no window and touched no network.
-- 4. Otherwise take the lock and ask BOTH questions again inside it. Whatever
--    was learned before the wait is stale: the instance we queued behind may
--    have restored the whole body already.
-- 5. Restore.
local function sequence(deps)
  if Host.pending_journal(host, at(JOURNAL_REL)) then
    local got, kind, detail = lock.acquire(deps.progress)
    if not got then return "stop", kind, detail end
  end

  if lock.held() then
    local resolved, kind, detail = core.resolve_pending(deps.progress)
    if not resolved and kind then return "stop", kind, detail end
  end

  if core.probe() ~= "present" then
    if not lock.held() then
      local got, lkind, ldetail = lock.acquire(deps.progress)
      if not got then return "stop", lkind, ldetail end
      local again, akind, adetail = core.resolve_pending(deps.progress)
      if not again and akind then return "stop", akind, adetail end
    end
    if core.probe() ~= "present" then
      local ok, rkind, rdetail = core.restore(deps.progress)
      -- restore() has already shown its dialog and announced the failure, so
      -- a failed bootstrap stops quietly rather than stacking a second one.
      if not ok then return "stop", rkind, rdetail end
    end
  end
  return "run"
end

Host.run({
  host     = host,
  lock     = lock,
  title    = TITLE,
  -- Decision 10a.9: no progress window in Screen Reader mode. It would take
  -- keyboard focus and carry nothing a screen reader can read, and every state
  -- reaches OSARA regardless.
  mode     = LAUNCHER_MODE,
  sequence = sequence,
  launch   = function()
    -- Asked again, here, at the last instant this launcher can still decide
    -- not to run. Everything between the first ask and this one is where an
    -- uninstall in another window could have started, and the body loaded
    -- below is the thing that uninstall is deleting. A marker standing now
    -- stops the launch outright, IN EITHER PHASE, rather than asking again:
    -- the question was put once already this run, and putting it a second time
    -- in the same run would be asking the user to answer for a race they
    -- cannot see. The phase only chooses which true sentence they are shown.
    local phase = uninstall_marker_phase()
    if phase then
      local said = (phase == "done")
        and "ReaAssist was uninstalled from this computer while this action "
          .. "was starting, so it did not start."
        or "ReaAssist started being removed from this computer while this "
          .. "action was starting, so it did not start."
      local next_step = (phase == "done")
        and "Run this action again to install ReaAssist again."
        or "Wait for the removal to finish, then run this action again."
      pcall(host.announce, TITLE .. ": " .. said)
      pcall(host.message_box, said .. "\n\nThe note that says so is here:\n"
        .. at(MARKER_REL) .. "\n\n" .. next_step, TITLE)
      return
    end
    dofile(core.body_main_path())
  end,
})
