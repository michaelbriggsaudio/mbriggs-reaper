-- ============================================================================
-- ReaAssist/Resources/Diag.lua
-- Diagnostic + feedback module. Extends the Diag namespace defined inline in
-- ReaAssist.lua (which provides Diag.errors / Diag.add_error / Diag.build_report)
-- with the network-uploader pathway, install/launch/chat IDs, redaction, and
-- manual-feedback draft API. Loaded via dofile from ReaAssist.lua.
--
-- v1.0.6 surface here:
--   Diag.send_draft / Diag.begin_draft / Diag.preview_payload_text
--   Diag.assemble_payload / Diag.tick
--   Diag.install_id / Diag.launch_id / Diag.chat_id / Diag.rotate_chat_id
--   Diag.redact / Diag.content_hash / Diag.uuidv4
--   Diag.uploader_enabled  (gate: false until init succeeds, true at end)
--
-- v1.1+ will add Diag.send_auto_basic / Diag.send_auto_extended in this file,
-- sharing all of the above infrastructure.
--
-- See Dev/DIAG_PLAN.md for the full design.
-- ============================================================================

-- Diag is created in ReaAssist.lua before this dofile fires. We extend it
-- here. uploader_enabled is the gate the rest of the app checks before
-- calling any of the upload-pathway functions; flipped true at the bottom
-- of this file once init completes.
Diag = Diag or {}
Diag.uploader_enabled = false
Diag.tick             = Diag.tick or function() end

if type(RA) ~= "table" then return end

if type(RA.JSON) ~= "table" or type(RA.JSON.encode) ~= "function" then
  if type(Log) == "table" and type(Log.add) == "function" then
    Log.add("Diag: RA.JSON unavailable; uploader disabled")
  end
  return
end

-- ============================================================================
-- Constants
-- ============================================================================
Diag.SCHEMA_VERSION    = 2
Diag.PAYLOAD_CAP_BYTES = 1024 * 1024     -- 1 MB server-side cap
Diag.USER_COMMENT_CAP  = 100 * 1024      -- 100 KB cap on user_comment
Diag.URL               = "https://d.reaassist.app/api/feedback/v1/submit"
Diag.CONNECT_TIMEOUT_S = 10
Diag.CURL_TIMEOUT_S    = 30

local EXT_NS             = "reaassist"
local EXT_KEY_INSTALL_ID = "feedback_install_id"

-- ============================================================================
-- Module-private state (no math.randomseed here -- ReaAssist.lua seeds at init)
--
-- Two distinct id concepts:
--   launch_id  -- generated once at module load, persists for the entire
--                 REAPER process. Use it to group all chats started in one
--                 REAPER launch.
--   chat_id    -- generated at module load AND regenerated every time the
--                 user starts a New Chat (Net.clear_conversation). Use it
--                 to group all feedback events from one conversation.
-- ============================================================================
local install_id_candidate = nil
local launch_id_value      = nil
local launch_started_at    = os.time()
local chat_id_value        = nil
local chat_started_at      = os.time()
local in_flight            = nil

-- ============================================================================
-- UUIDv4
-- ============================================================================
local function uuidv4()
  local r1  = math.random(0, 0xffffffff)
  local r2  = math.random(0, 0xffff)
  local r3  = math.random(0, 0x0fff)
  local r4  = math.random(0, 0x3fff)
  local r5h = math.random(0, 0xffff)
  local r5l = math.random(0, 0xffffffff)
  return string.format("%08x-%04x-4%03x-%x%03x-%04x%08x",
    r1, r2, r3, 8 + (r4 >> 12), r4 & 0x0fff, r5h, r5l)
end
Diag.uuidv4 = uuidv4

launch_id_value = uuidv4()
chat_id_value   = uuidv4()

function Diag.launch_id() return launch_id_value end
function Diag.chat_id()   return chat_id_value end

-- Called by Net.clear_conversation() (and the Settings provider-switch path)
-- whenever conversation-scoped state is reset. Generates a fresh chat_id and
-- resets chat_started_at so per-chat analytics line up with what the user
-- sees as one conversation.
function Diag.rotate_chat_id()
  chat_id_value     = uuidv4()
  chat_started_at   = os.time()
end

-- ============================================================================
-- install_id lifecycle
-- ============================================================================
function Diag.install_id()
  if type(reaper) == "table" and type(reaper.GetExtState) == "function" then
    local persisted = reaper.GetExtState(EXT_NS, EXT_KEY_INSTALL_ID)
    if persisted and persisted ~= "" then return persisted end
  end
  if not install_id_candidate then install_id_candidate = uuidv4() end
  return install_id_candidate
end

function Diag.commit_install_id()
  if type(reaper) ~= "table" or type(reaper.SetExtState) ~= "function" then
    return
  end
  local existing = reaper.GetExtState(EXT_NS, EXT_KEY_INSTALL_ID)
  if existing and existing ~= "" then return end
  if not install_id_candidate then return end
  reaper.SetExtState(EXT_NS, EXT_KEY_INSTALL_ID, install_id_candidate, true)
end

-- ============================================================================
-- SHA-256 (pure-Lua fallback if RA.sha256_hex not exposed by 3B)
-- ============================================================================
local function _local_sha256(msg)
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local H = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }
  local M32 = 0xffffffff
  local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & M32 end

  local len = #msg
  local bits = len * 8
  local padded = msg .. "\x80"
  while (#padded % 64) ~= 56 do padded = padded .. "\x00" end
  for i = 7, 0, -1 do
    padded = padded .. string.char((bits >> (i * 8)) & 0xff)
  end

  for chunk = 1, #padded, 64 do
    local W = {}
    for i = 0, 15 do
      local off = chunk + i * 4
      W[i + 1] = (string.byte(padded, off)     << 24)
              | (string.byte(padded, off + 1) << 16)
              | (string.byte(padded, off + 2) <<  8)
              |  string.byte(padded, off + 3)
    end
    for i = 17, 64 do
      local s0 = (rrot(W[i - 15], 7)  ~ rrot(W[i - 15], 18) ~ (W[i - 15] >> 3))  & M32
      local s1 = (rrot(W[i - 2], 17)  ~ rrot(W[i - 2], 19)  ~ (W[i - 2]  >> 10)) & M32
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) & M32
    end

    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 1, 64 do
      local S1 = (rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)) & M32
      local ch = ((e & f) ~ ((~e) & g)) & M32
      local t1 = (h + S1 + ch + K[i] + W[i]) & M32
      local S0 = (rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)) & M32
      local mj = ((a & b) ~ (a & c) ~ (b & c)) & M32
      local t2 = (S0 + mj) & M32
      h, g, f = g, f, e
      e = (d + t1) & M32
      d, c, b = c, b, a
      a = (t1 + t2) & M32
    end

    H[1] = (H[1] + a) & M32; H[2] = (H[2] + b) & M32
    H[3] = (H[3] + c) & M32; H[4] = (H[4] + d) & M32
    H[5] = (H[5] + e) & M32; H[6] = (H[6] + f) & M32
    H[7] = (H[7] + g) & M32; H[8] = (H[8] + h) & M32
  end

  return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
    H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

function Diag.content_hash(s)
  s = tostring(s or "")
  if type(RA.sha256_hex) == "function" then
    local ok, h = pcall(RA.sha256_hex, s)
    if ok and type(h) == "string" and #h == 64 then return h end
  end
  return _local_sha256(s)
end

-- ============================================================================
-- Redaction
-- Order: live S keys -> provider prefixes -> Authorization/Bearer ->
-- home paths -> install paths in Diag report -> Log.scrub_url_secrets
-- (Live keys must run BEFORE provider prefixes so an exact match becomes
-- "***" rather than the generic "sk-***".)
-- ============================================================================
local function _esc_pat(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function Diag.redact(s)
  if type(s) ~= "string" then return tostring(s or "") end

  -- 1. Live API keys from S (highest precision -> exact match -> "***")
  if type(S) == "table" then
    if type(S.api_key) == "string" and #S.api_key >= 8 then
      s = s:gsub(_esc_pat(S.api_key), "***")
    end
    if type(S.api_key_map) == "table" then
      for _, key in pairs(S.api_key_map) do
        if type(key) == "string" and #key >= 8 then
          s = s:gsub(_esc_pat(key), "***")
        end
      end
    end
  end

  -- 2. Provider key prefixes
  s = s:gsub("sk%-ant%-[A-Za-z0-9%-_]+", "sk-ant-***")
  s = s:gsub("sk%-[A-Za-z0-9%-_]+", function(m)
    return #m >= 20 and "sk-***" or m
  end)
  s = s:gsub("AIza[A-Za-z0-9%-_]+", "AIza***")

  -- 3. Authorization header lines (case-preserving) + standalone Bearer
  s = s:gsub("([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]):%s*[^\n\r]+",
             "%1: ***")
  s = s:gsub("[Bb]earer%s+[%w%-_%.]+", "Bearer ***")

  -- 4. Home paths
  s = s:gsub("([A-Za-z]:\\Users\\)[^\\%s\"']+", "%1<user>")
  s = s:gsub("(/Users/)[^/%s\"']+",            "%1<user>")
  s = s:gsub("(/home/)[^/%s\"']+",             "%1<user>")

  -- 5. Diagnostic-report install paths. The Diag.build_report output
  -- includes lines like:
  --   Log file:               C:\REAPER\Scripts\...\Debug.log
  --   Plugin_Ref.md:          MISSING at C:\REAPER\Scripts\...\Plugin_Ref.md
  -- These are full install paths that the home-path rule above can't
  -- catch when REAPER is installed outside C:\Users (or under /opt etc.
  -- on POSIX). Reduce both to just the basename / a marker -- the
  -- analyst still learns "logging is on, file name is Debug.log" or
  -- "Plugin_Ref.md is missing", without leaking install topology.
  s = s:gsub("(Log file:%s+)([^\n\r]*)", function(prefix, path)
    local name = path:match("[^/\\]*$")
    return prefix .. (name ~= "" and name or path)
  end)
  s = s:gsub("(Plugin_Ref%.md:%s+MISSING) at [^\n\r]+", "%1 (path scrubbed)")

  -- 6. Reuse Log.scrub_url_secrets if present
  if type(Log) == "table" and type(Log.scrub_url_secrets) == "function" then
    local ok, scrubbed = pcall(Log.scrub_url_secrets, s)
    if ok and type(scrubbed) == "string" then s = scrubbed end
  end

  return s
end

-- ============================================================================
-- Helpers
-- ============================================================================
local function _detect_os()
  if type(reaper) == "table" and type(reaper.GetOS) == "function" then
    local o = reaper.GetOS() or ""
    if     o:match("^Win") then return "win"
    elseif o:match("^macOS") or o:match("^OSX") then return "mac"
    else return "linux" end
  end
  return "unknown"
end

local function _serialize(payload) return RA.JSON.encode(payload, "  ") end

local function _shallow_copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function _turn_to_table(msg, redact_content)
  if type(msg) ~= "table" then return { role = "?", content = "" } end
  local t = { role = msg.role }
  t.content = redact_content and Diag.redact(msg.content or "") or (msg.content or "")
  if msg.ts          then t.ts          = msg.ts end
  if msg.intent_tag  then t.intent_tag  = msg.intent_tag end
  if msg.role == "assistant" then
    if msg.model_label then t.model_label = msg.model_label end
    if msg.code_block then
      t.code_block = redact_content and Diag.redact(msg.code_block) or msg.code_block
      t.code_type  = msg.code_type
    end
    if msg.auto_ran      ~= nil then t.auto_ran      = msg.auto_ran end
    if msg.truncated     ~= nil then t.truncated     = msg.truncated end
    if msg.docs_gate_hit ~= nil then t.docs_gate_hit = msg.docs_gate_hit end
    if msg.api_calls     ~= nil then t.api_calls     = msg.api_calls end
  end
  return t
end

-- ============================================================================
-- Draft API: snapshot at modal open, render byte-exact at preview/send time
-- ============================================================================
function Diag.begin_draft(target_idx)
  target_idx = target_idx or 0

  local msgs = (type(S) == "table" and type(S.display_messages) == "table")
               and S.display_messages or {}
  local total = #msgs

  local turns = {}
  for i = 1, total do turns[i] = _turn_to_table(msgs[i], true) end

  -- Hash the REDACTED target content (better cross-user dedup posture)
  local target_content = ""
  if target_idx >= 1 and target_idx <= total then
    target_content = turns[target_idx].content or ""
  end

  -- provider id (NOT the table)
  local provider_id = "unknown"
  if type(PROVIDERS) == "table" and type(PROVIDERS.active) == "function" then
    local ok, p = pcall(PROVIDERS.active)
    if ok then
      if type(p) == "table" then
        provider_id = p.id or p.label or "unknown"
      elseif type(p) == "string" then
        provider_id = p
      end
    end
  end

  -- model id via MODELS.active_id() if available, else S.model
  local model_id = "unknown"
  if type(MODELS) == "table" and type(MODELS.active_id) == "function" then
    local ok, m = pcall(MODELS.active_id)
    if ok and type(m) == "string" then model_id = m end
  end
  if model_id == "unknown" and type(S) == "table" and type(S.model) == "string" then
    model_id = S.model
  end

  local thinking_level = (type(S) == "table") and S.thinking_level or nil

  local reaper_version = "unknown"
  if type(reaper) == "table" and type(reaper.GetAppVersion) == "function" then
    local ok, v = pcall(reaper.GetAppVersion)
    if ok and type(v) == "string" then reaper_version = v end
  end

  -- Diagnostic Report -- the same plain-text snapshot the user can preview at
  -- Help > Report a Bug. Wrapped in pcall so a transient Diag.build_report
  -- failure can never block a feedback draft from opening. Run through
  -- Diag.redact so home paths in `Log path:` are scrubbed before the user
  -- ever sees the preview.
  local diagnostic_report = nil
  if type(Diag) == "table" and type(Diag.build_report) == "function" then
    local ok, rep = pcall(Diag.build_report, { skip_followup_note = true })
    if ok and type(rep) == "string" then
      diagnostic_report = Diag.redact(rep)
    end
  end

  return {
    event_id             = uuidv4(),
    drafted_at           = os.time(),
    install_id           = Diag.install_id(),
    launch_id            = launch_id_value,
    launch_started_at    = launch_started_at,
    chat_id              = chat_id_value,
    chat_started_at      = chat_started_at,
    app_version          = (type(CFG) == "table" and CFG.VERSION) or "unknown",
    os                   = _detect_os(),
    reaper_version       = reaper_version,
    provider             = provider_id,
    model                = model_id,
    thinking_level       = thinking_level,
    target_message_index = target_idx,
    target_content_hash  = Diag.content_hash(target_content),
    _turns               = turns,
    _turn_count_total    = total,
    _diagnostic_report   = diagnostic_report,
  }
end

function Diag.assemble_payload(draft, comment, flags)
  comment = comment or ""
  flags   = flags or {}

  -- Cap user_comment at input BEFORE redaction so the cap applies to text the
  -- user actually typed, not redaction-expanded text.
  if #comment > Diag.USER_COMMENT_CAP then
    comment = comment:sub(1, Diag.USER_COMMENT_CAP)
      .. " [...truncated " .. (#comment - Diag.USER_COMMENT_CAP) .. " bytes...]"
  end

  local payload = {
    schema_version       = Diag.SCHEMA_VERSION,
    event_type           = "manual",
    event_id             = draft.event_id,
    install_id           = draft.install_id,
    launch_id            = draft.launch_id,
    launch_started_at    = draft.launch_started_at,
    chat_id              = draft.chat_id,
    chat_started_at      = draft.chat_started_at,
    drafted_at           = draft.drafted_at,
    app_version          = draft.app_version,
    os                   = draft.os,
    reaper_version       = draft.reaper_version,
    provider             = draft.provider,
    model                = draft.model,
    thinking_level       = draft.thinking_level,
    target_message_index = draft.target_message_index,
    target_content_hash  = draft.target_content_hash,
    session = {
      turn_count_total = draft._turn_count_total,
      turns            = draft._turns,
    },
    user_comment     = Diag.redact(comment),
    structured_flags = flags,
  }
  -- Diagnostic Report (optional). Already redacted in begin_draft.
  -- Field is omitted when nil so the JSON stays clean for old test fixtures.
  if draft._diagnostic_report then
    payload.diagnostic_report = draft._diagnostic_report
  end

  local serialized = _serialize(payload)
  if #serialized <= Diag.PAYLOAD_CAP_BYTES then
    return payload, nil
  end

  -- Truncation needed.
  local original_byte_estimate = #serialized
  local original_turn_count    = draft._turn_count_total
  local target_idx             = draft.target_message_index

  local mandatory = { [1] = true }
  local target_window = nil
  if target_idx >= 1 and target_idx <= original_turn_count then
    target_window = {
      math.max(1, target_idx - 1),
      target_idx,
      math.min(original_turn_count, target_idx + 1),
    }
    for _, idx in ipairs(target_window) do mandatory[idx] = true end
  end

  local function build(last_n)
    local kept = {}
    for i = 1, original_turn_count do
      if mandatory[i] or i > original_turn_count - last_n then
        kept[#kept + 1] = draft._turns[i]   -- reference; do NOT mutate
      end
    end
    payload.session.turns = kept
    payload.truncation_info = {
      applied                = true,
      original_turn_count    = original_turn_count,
      kept_first_n           = 1,
      kept_target_window     = target_window,
      kept_last_n            = last_n,
      dropped_count          = original_turn_count - #kept,
      original_byte_estimate = original_byte_estimate,
      final_byte_estimate    = 0,
    }
    return _serialize(payload)
  end

  local function stabilize(s)
    -- Fixed-point: re-serialize after writing final_byte_estimate so the
    -- recorded value matches the actual serialized size.
    for _ = 1, 5 do
      if payload.truncation_info.final_byte_estimate == #s then break end
      payload.truncation_info.final_byte_estimate = #s
      s = _serialize(payload)
    end
    return s
  end

  -- Phase 0: try decreasing last_n; if any value of last_n fits, return.
  for last_n = original_turn_count, 0, -1 do
    local s = build(last_n)
    if #s <= Diag.PAYLOAD_CAP_BYTES then
      stabilize(s)
      return payload, payload.truncation_info
    end
  end

  -- Even with last_n = 0 we're over: enter the shrink phases.
  build(0)
  local kept = payload.session.turns

  -- Track which kept[i] entries we've already shallow-copied (so subsequent
  -- mutations don't touch draft._turns).
  local copied = {}
  local function ensure_copy(i)
    if kept[i] and not copied[i] then
      kept[i] = _shallow_copy(kept[i])
      copied[i] = true
    end
  end

  local function shrinkable_largest(min_size)
    local biggest_i, biggest_size = nil, min_size or 200
    for i, t in ipairs(kept) do
      local clen = #(t.content or "")
      if clen > biggest_size then
        biggest_i, biggest_size = i, clen
      end
    end
    return biggest_i, biggest_size
  end

  local s = stabilize(_serialize(payload))

  -- Phase 1: iteratively shrink the largest kept turn's content. With at most
  -- 4 mandatory turns (first + target_window), this converges in <= 4 iters.
  local guard = 0
  while #s > Diag.PAYLOAD_CAP_BYTES and guard < 16 do
    guard = guard + 1
    local i, sz = shrinkable_largest(200)
    if not i then break end
    ensure_copy(i)
    -- Target: half of current, but no smaller than 100 and no larger than 10 KB
    local target = math.max(100, math.min(math.floor(sz / 2), 10 * 1024))
    local orig_content = kept[i].content or ""
    if #orig_content > target then
      kept[i].content = orig_content:sub(1, target)
        .. " [...truncated " .. (#orig_content - target) .. " bytes...]"
    end
    s = stabilize(_serialize(payload))
  end

  -- Phase 2: if STILL over, force minimal placeholder content on every kept
  -- turn (and clear any code_block, which can also be large).
  if #s > Diag.PAYLOAD_CAP_BYTES then
    for i = 1, #kept do
      ensure_copy(i)
      kept[i].content = "[...content removed for size...]"
      if kept[i].code_block then
        kept[i].code_block = "[...code removed for size...]"
      end
    end
    s = stabilize(_serialize(payload))
  end

  -- Phase 2.5: drop the diagnostic_report before mangling user_comment. The
  -- report is reproducible from the Help > Report a Bug page; the user's
  -- typed comment is not. We mark the drop in truncation_info so analysts
  -- know the absent field wasn't a "Diag unavailable" case.
  if #s > Diag.PAYLOAD_CAP_BYTES and payload.diagnostic_report then
    payload.diagnostic_report = nil
    payload.truncation_info.diagnostic_report_dropped = true
    s = stabilize(_serialize(payload))
  end

  -- Phase 3: if STILL over, the user_comment is the remaining culprit.
  if #s > Diag.PAYLOAD_CAP_BYTES then
    local cc = payload.user_comment or ""
    local over = #s - Diag.PAYLOAD_CAP_BYTES
    if #cc > over + 200 then
      payload.user_comment = cc:sub(1, #cc - over - 200) .. " [...overflow truncated...]"
    else
      payload.user_comment = "[...overflow truncated...]"
    end
    s = stabilize(_serialize(payload))
  end

  -- Phase 4 (defense in depth): drop everything to bare metadata. Should be
  -- unreachable for any reasonable input.
  if #s > Diag.PAYLOAD_CAP_BYTES then
    payload.session.turns = {}
    payload.user_comment = ""
    payload.truncation_info.fatal_overflow = true
    s = stabilize(_serialize(payload))
  end

  return payload, payload.truncation_info
end

function Diag.preview_payload_text(draft, comment, flags)
  local payload = Diag.assemble_payload(draft, comment, flags)
  return _serialize(payload)
end

-- ============================================================================
-- Send (async via curl) + tick
-- Mirrors Net.fire_curl pattern (ReaAssist.lua:13931+).
-- ============================================================================
local function _instance_id()
  if type(S) == "table" and type(S.INSTANCE_ID) == "string" and S.INSTANCE_ID ~= "" then
    return S.INSTANCE_ID
  end
  return string.format("%d_%d", os.time(), math.random(0, 0xffffff))
end

local function _tmp_dir()
  if type(reaper) == "table" and type(reaper.GetResourcePath) == "function" then
    local rp = reaper.GetResourcePath()
    if type(rp) == "string" and rp ~= "" then
      local sep = (type(RA) == "table" and type(RA.SEP) == "string") and RA.SEP or "/"
      return rp .. sep
    end
  end
  return "/tmp/"
end

local function _tmp_path(suffix)
  return _tmp_dir() .. "reaassist_fb_" .. suffix .. "_" .. _instance_id()
end

local function _path_safe(p) return type(p) == "string" and not p:find('"', 1, true) end

local function _ps_escape(s) return s:gsub("'", "''") end
local function _sq(p) return "'" .. p:gsub("'", "'\\''") .. "'" end

local function _build_windows(body_path, resp_path, status_path, exit_path)
  for _, p in ipairs({ body_path, resp_path, status_path, exit_path, Diag.URL }) do
    if not _path_safe(p) then
      return nil, "path/URL contains literal quote: " .. tostring(p)
    end
  end

  local cmd_line = string.format(
    'curl -s --connect-timeout %d --max-time %d'
    .. ' -X POST -H """Content-Type: application/json"""'
    .. ' --data-binary @"""%s"""'
    .. ' -o """%s""" -w """%%{http_code}"""'
    .. ' """%s"""'
    .. ' > """%s"""'
    .. ' & echo %%errorlevel%% > """%s"""',
    Diag.CONNECT_TIMEOUT_S, Diag.CURL_TIMEOUT_S,
    body_path, resp_path, Diag.URL, status_path, exit_path
  )

  return string.format(
    'powershell -NoProfile -WindowStyle Hidden'
    .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
    .. ' -WindowStyle Hidden"',
    _ps_escape(cmd_line)
  )
end

local function _build_posix(body_path, resp_path, status_path, exit_path)
  for _, p in ipairs({ body_path, resp_path, status_path, exit_path, Diag.URL }) do
    if not _path_safe(p) then
      return nil, "path/URL contains literal quote: " .. tostring(p)
    end
  end

  return string.format(
    "(curl -s --connect-timeout %d --max-time %d"
    .. " -X POST -H 'Content-Type: application/json'"
    .. " --data-binary @%s -o %s -w '%%{http_code}'"
    .. " %s > %s ; echo $? > %s) &",
    Diag.CONNECT_TIMEOUT_S, Diag.CURL_TIMEOUT_S,
    _sq(body_path), _sq(resp_path),
    _sq(Diag.URL), _sq(status_path), _sq(exit_path)
  )
end

local function _launch_curl(cmd, is_windows)
  if is_windows then
    if type(reaper) == "table" and type(reaper.ExecProcess) == "function" then
      reaper.ExecProcess(cmd, 5000)
    end
  else
    os.execute(cmd)
  end
end

function Diag.send_draft(draft, comment, flags, on_done)
  if in_flight then
    if on_done then on_done(false, nil, "send already in flight") end
    return
  end

  local body = Diag.preview_payload_text(draft, comment, flags)

  -- Pre-flight cap check: refuse to attempt POST if assemble_payload couldn't
  -- shrink under cap. Surfaces as a clear local error rather than a 413.
  if #body > Diag.PAYLOAD_CAP_BYTES then
    if on_done then
      on_done(false, nil, "payload exceeds cap after truncation: " .. #body .. " bytes")
    end
    return
  end

  local body_path   = _tmp_path("body")
  local resp_path   = _tmp_path("resp")
  local status_path = _tmp_path("status")
  local exit_path   = _tmp_path("exit")

  local is_win = _detect_os() == "win"
  local cmd, cerr
  if is_win then
    cmd, cerr = _build_windows(body_path, resp_path, status_path, exit_path)
  else
    cmd, cerr = _build_posix(body_path, resp_path, status_path, exit_path)
  end
  if not cmd then
    if on_done then on_done(false, nil, cerr) end
    return
  end

  local f, ferr = io.open(body_path, "wb")
  if not f then
    if on_done then on_done(false, nil, "cannot open body: " .. tostring(ferr)) end
    return
  end
  f:write(body); f:close()

  os.remove(resp_path); os.remove(status_path); os.remove(exit_path)

  in_flight = {
    body_path   = body_path,
    resp_path   = resp_path,
    status_path = status_path,
    exit_path   = exit_path,
    started_at  = os.time(),
    on_done     = on_done,
  }

  _launch_curl(cmd, is_win)
end

local function _read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function _cleanup_inflight()
  if not in_flight then return end
  os.remove(in_flight.body_path)
  os.remove(in_flight.resp_path)
  os.remove(in_flight.status_path)
  os.remove(in_flight.exit_path)
end

function Diag.tick()
  if not in_flight then return end

  local exit_str = _read_file(in_flight.exit_path)
  if not exit_str then
    if os.time() - in_flight.started_at > 60 then
      local cb = in_flight.on_done
      _cleanup_inflight(); in_flight = nil
      if cb then cb(false, nil, "timeout waiting for curl") end
    end
    return
  end

  local exit_code   = tonumber((exit_str or ""):match("%-?%d+")) or -1
  local status_code = tonumber((_read_file(in_flight.status_path) or ""):match("%d+")) or 0

  local ok = (exit_code == 0) and (status_code == 204)
  local err = nil
  if not ok then
    if exit_code ~= 0 then err = "curl exit " .. exit_code
    else                   err = "http "      .. status_code end
  end

  local cb = in_flight.on_done
  _cleanup_inflight(); in_flight = nil

  if ok then Diag.commit_install_id() end
  if cb then cb(ok, status_code, err) end
end

-- ============================================================================
-- Module load complete.
-- ============================================================================
Diag.uploader_enabled = true
