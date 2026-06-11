-- Resources/Context.lua
-- Eager-loaded by ReaAssist.lua through RA.load_context(). Defines the CTX.*
-- context providers, local read-answer helpers, prompt-bucket preemption, and
-- FX/plugin metadata readers used while building an API request.
--
-- Boundary contract:
--   - Main code should call exported CTX.* helpers, not sidecar-local locals.
--   - Keep startup side effects limited to definitions and cache table setup.
--   - Read REAPER/project state lazily at call time so each send sees fresh
--     data and startup stays cheap apart from parsing this file.
--   - Helper functions exported for main-file call sites are assigned back
--     onto CTX near their local definitions.

CTX = CTX or {}

-- =============================================================================
-- Lightweight status and identity buckets
-- =============================================================================
-- These answer simple "what version/status/settings are active?" questions
-- locally. Most return nil unless the user text clearly asks for that status,
-- allowing the normal provider path to handle advice or mutation requests.

-- Always included in the session snapshot; no prompt filtering needed.
function CTX.reaper_version()
  return "REAPER version: " .. tostring(reaper.GetAppVersion() or "unknown")
end

-- Always included in the session snapshot; reports the shipped script version.
function CTX.reaassist_version()
  return "ReaAssist version: " .. tostring(CFG.VERSION or "unknown")
end

-- Local answer for extension-availability questions (SWS, ReaImGui,
-- JS_ReaScriptAPI, or a broad installed-extensions status request).
function CTX.extension_status(user_text)
  local text = tostring(user_text or ""):lower()
  local clean = text:gsub("[_%-%s]+", " ")
  local compact = clean:gsub("%s+", "")
  local wants_imgui = compact:find("reaimgui", 1, true) ~= nil
  local wants_sws = text:find("%f[%w]sws%f[%W]") ~= nil
  local wants_jsapi = compact:find("jsreascriptapi", 1, true) ~= nil
    or clean:find("js reascript api", 1, true) ~= nil
    or clean:find("reascript api", 1, true) ~= nil
  local wants_all = clean:find("%f[%w]extensions?%f[%W]") ~= nil
    and (clean:find("%f[%w]installed%f[%W]") ~= nil
      or clean:find("%f[%w]available%f[%W]") ~= nil
      or clean:find("%f[%w]status%f[%W]") ~= nil
      or clean:find("%f[%w]version%f[%W]") ~= nil
      or clean:find("%f[%w]have%f[%W]") ~= nil)
  if not (wants_imgui or wants_sws or wants_jsapi or wants_all) then
    return nil
  end

  local function try(fn)
    local ok, a, b, c, d = pcall(fn)
    if ok then return a, b, c, d end
  end
  local function fmt(label, installed, version)
    if not installed then return label .. ": not installed" end
    return label .. ": installed"
      .. (version and version ~= "" and (" (" .. tostring(version) .. ")") or "")
  end
  local function imgui_line()
    local installed = reaper.ImGui_CreateContext ~= nil
    local ver = nil
    if installed and reaper.ImGui_GetVersion then
      local a, _, _, d = try(function() return reaper.ImGui_GetVersion() end)
      ver = d or a
    end
    return fmt("ReaImGui", installed, ver)
  end
  local function sws_line()
    local installed = reaper.CF_GetSWSVersion ~= nil
    local ver = nil
    if installed then
      ver = try(function() return reaper.CF_GetSWSVersion("") end)
      if not ver or ver == "" then
        ver = try(function() return reaper.CF_GetSWSVersion() end)
      end
    end
    return fmt("SWS Extension", installed, ver)
  end
  local function jsapi_line()
    local installed = reaper.JS_ReaScriptAPI_Version ~= nil
    local ver = installed and try(function()
      return reaper.JS_ReaScriptAPI_Version()
    end) or nil
    return fmt("js_ReaScriptAPI", installed, ver)
  end

  local lines = {}
  if wants_all or wants_imgui then lines[#lines + 1] = imgui_line() end
  if wants_all or wants_sws then lines[#lines + 1] = sws_line() end
  if wants_all or wants_jsapi then lines[#lines + 1] = jsapi_line() end
  if #lines == 1 then return lines[1] end
  return "ReaAssist extension status:\n" .. tbl_concat(lines, "\n")
end

-- Local answer for current provider/model/thinking selection. It deliberately
-- ignores broad model advice so recommendation questions still go to the LLM.
function CTX.ai_selection_status(user_text)
  local text = tostring(user_text or ""):lower()
  local clean = text:gsub("[_%-%s]+", " ")
  local mentions_model = clean:find("%f[%w]model%f[%W]") ~= nil
  local mentions_provider = clean:find("%f[%w]provider%f[%W]") ~= nil
  local mentions_thinking = clean:find("%f[%w]thinking%f[%W]") ~= nil
    or clean:find("%f[%w]reasoning%f[%W]") ~= nil
  local mentions_ai = clean:find("%f[%w]ai%f[%W]") ~= nil
    or clean:find("%f[%w]llm%f[%W]") ~= nil
    or clean:find("%f[%w]reaassist%f[%W]") ~= nil
  local selection_word = clean:find("%f[%w]selected%f[%W]") ~= nil
    or clean:find("%f[%w]active%f[%W]") ~= nil
    or clean:find("%f[%w]current%f[%W]") ~= nil
    or clean:find("%f[%w]using%f[%W]") ~= nil
    or clean:find("%f[%w]use%f[%W]") ~= nil
    or clean:find("%f[%w]you%f[%W]") ~= nil
  if not (mentions_model or mentions_provider or mentions_thinking) then
    return nil
  end
  if not (selection_word or mentions_ai) then return nil end
  if type(PROVIDERS) ~= "table"
      or type(PROVIDERS.active) ~= "function"
      or type(MODELS) ~= "table"
      or type(prefs) ~= "table" then
    return nil
  end

  local function try(fn)
    local ok, v = pcall(fn)
    if ok then return v end
  end
  local p = try(function() return PROVIDERS.active() end) or {}
  local m = MODELS[prefs.model_idx] or MODELS[1] or {}
  local provider_label = tostring(p.label or p.id or "unknown")
  if p.id and p.id ~= p.label then
    provider_label = provider_label .. " (" .. tostring(p.id) .. ")"
  end
  local model_id = try(function()
    if type(MODELS.active_id) == "function" then return MODELS.active_id() end
  end) or m.id
  local model_label = tostring(m.label or model_id or "unknown")
  if model_id and tostring(model_id) ~= model_label then
    model_label = model_label .. " (" .. tostring(model_id) .. ")"
  end
  local thinking_label = "not available"
  if p.thinking_levels and prefs.thinking_idx and prefs.thinking_idx > 0 then
    local tl = p.thinking_levels[prefs.thinking_idx]
    if tl and tl.label then thinking_label = tostring(tl.label) end
  end
  return "AI selection:\nProvider: " .. provider_label
    .. "\nModel: " .. model_label
    .. "\nThinking: " .. thinking_label
end

-- Local answer for ReaAssist preference-state questions; returns nil for
-- "should I change this setting?" advice so the model can reason about tradeoffs.
function CTX.reaassist_settings_status(user_text)
  local text = tostring(user_text or ""):lower()
  local clean = text:gsub("[_%-%s]+", " ")
  local compact = clean:gsub("%s+", "")
  local mentions_settings = clean:find("%f[%w]settings%f[%W]") ~= nil
    or clean:find("%f[%w]preferences%f[%W]") ~= nil
  local mentions_reaassist = clean:find("%f[%w]reaassist%f[%W]") ~= nil
  local wants_auto_run = compact:find("autorun", 1, true) ~= nil
  local wants_auto_backup = compact:find("autobackup", 1, true) ~= nil
    or ((clean:find("%f[%w]backup%f[%W]") ~= nil
      or clean:find("%f[%w]backups%f[%W]") ~= nil)
      and (mentions_settings or mentions_reaassist
        or clean:find("%f[%w]enabled%f[%W]") ~= nil
        or clean:find("%f[%w]on%f[%W]") ~= nil
        or clean:find("%f[%w]off%f[%W]") ~= nil))
  local wants_snapshot = clean:find("project snapshot", 1, true) ~= nil
    or clean:find("include snapshot", 1, true) ~= nil
    or clean:find("snapshot context", 1, true) ~= nil
  local wants_api_ref = clean:find("api reference", 1, true) ~= nil
    or clean:find("api ref", 1, true) ~= nil
  local wants_structured = clean:find("structured edit", 1, true) ~= nil
    or clean:find("structured edits", 1, true) ~= nil
    or clean:find("typed action", 1, true) ~= nil
    or clean:find("typed actions", 1, true) ~= nil
  local wants_debug = clean:find("debug logging", 1, true) ~= nil
    or clean:find("debug log", 1, true) ~= nil
  local wants_update_check = clean:find("update check", 1, true) ~= nil
    or clean:find("update checking", 1, true) ~= nil
    or clean:find("check for updates", 1, true) ~= nil
  local wants_reply_language = clean:find("reply language", 1, true) ~= nil
    or clean:find("response language", 1, true) ~= nil
    or clean:find("chat language", 1, true) ~= nil
  local wants_summary = mentions_reaassist and mentions_settings
  if not (wants_summary or wants_auto_run or wants_auto_backup
      or wants_snapshot or wants_api_ref or wants_structured
      or wants_debug or wants_update_check or wants_reply_language) then
    return nil
  end
  if type(prefs) ~= "table" then return nil end

  local function onoff(v) return v and "ON" or "OFF" end
  local structured_state = "built in"
  if type(Code) == "table"
      and type(Code.typed_actions_public_force_off) == "function"
      and Code.typed_actions_public_force_off() then
    structured_state = "temporarily disabled"
  end
  if wants_structured and not (wants_summary or wants_auto_run
      or wants_auto_backup or wants_snapshot or wants_api_ref
      or wants_debug or wants_update_check or wants_reply_language) then
    return "Structured track edits: " .. structured_state
  end
  local lang_label = (CFG.language_label_for_idx
    and CFG.language_label_for_idx(prefs.reply_language_idx or 1))
    or (CFG.REPLY_LANGUAGE_LABELS and CFG.REPLY_LANGUAGE_LABELS[prefs.reply_language_idx or 1])
    or "English"
  return "ReaAssist settings:\n"
    .. "Auto-run scripts: " .. onoff(prefs.auto_run) .. "\n"
    .. "Auto-backup before run: " .. onoff(prefs.auto_backup) .. "\n"
    .. "Include project snapshot: " .. onoff(prefs.include_snapshot) .. "\n"
    .. "Always include API reference: " .. onoff(prefs.include_api_ref) .. "\n"
    .. "Debug logging: " .. onoff(prefs.debug_logging) .. "\n"
    .. "Check for updates: " .. onoff(prefs.update_check) .. "\n"
    .. "Reply language: " .. lang_label
end

-- Local answer for diagnostic telemetry state; advisory/reporting questions
-- still fall through to the provider.
function CTX.diagnostics_status(user_text)
  local text = tostring(user_text or ""):lower()
  local clean = text:gsub("[_%-%s]+", " ")
  local mentions_diag = clean:find("%f[%w]diagnostics?%f[%W]") ~= nil
    or clean:find("automatic diagnostics", 1, true) ~= nil
    or clean:find("anonymous diagnostics", 1, true) ~= nil
  if not mentions_diag then return nil end
  local wants_status = clean:find("%f[%w]status%f[%W]") ~= nil
    or clean:find("%f[%w]tier%f[%W]") ~= nil
    or clean:find("%f[%w]setting%f[%W]") ~= nil
    or clean:find("%f[%w]settings%f[%W]") ~= nil
    or clean:find("%f[%w]selected%f[%W]") ~= nil
    or clean:find("%f[%w]current%f[%W]") ~= nil
    or clean:find("%f[%w]enabled%f[%W]") ~= nil
    or clean:find("%f[%w]on%f[%W]") ~= nil
    or clean:find("%f[%w]off%f[%W]") ~= nil
    or clean:find("%f[%w]basic%f[%W]") ~= nil
    or clean:find("%f[%w]extended%f[%W]") ~= nil
  if not wants_status then return nil end

  local tier = nil
  if type(Diag) == "table" and type(Diag.current_tier) == "function" then
    local ok, value = pcall(Diag.current_tier)
    if ok then tier = value end
  end
  if (tier == nil or tier == "") and type(prefs) == "table" then
    tier = prefs.diag_auto_tier
  end
  tier = tostring(tier or "basic"):lower()
  if tier ~= "basic" and tier ~= "extended" then tier = "off" end

  local label = tier == "extended" and "Extended"
    or tier == "basic" and "Basic"
    or "Off"
  local enabled = tier ~= "off"
  return "Automatic diagnostics: " .. (enabled and "ON" or "OFF")
    .. " (" .. label .. ")"
end

-- =============================================================================
-- Core project snapshot readers
-- =============================================================================
-- These functions read live REAPER state and return compact, stable text
-- buckets. They are used by CTX.build_snapshot and by local read answers.

function CTX.tempo(proj)
  -- TimeMap_GetTimeSigAtTime reads the actual tempo map at the edit cursor
  -- position, correctly reflecting any time signature and BPM set via tempo
  -- map points (e.g. 6/8). GetProjectTimeSignature2 only returns the project
  -- default and ignores tempo map entries entirely.
  -- C signature: (proj, time, *timesig_num, *timesig_denom, *tempo)
  -- Lua returns output params in order: num, denom, bpm
  local cursor = reaper.GetCursorPositionEx(proj)
  local num, denom, bpm = reaper.TimeMap_GetTimeSigAtTime(proj, cursor)
  if not bpm or bpm <= 0 then bpm = 120 end  -- defensive fallback
  num   = (type(num)   == "number" and num   > 0) and math_floor(num)   or 4
  denom = (type(denom) == "number" and denom > 0) and math_floor(denom) or 4
  local bpm_text = str_format("%.2f", bpm)
  if I18N and I18N.t then
    return I18N.t("local.tempo", {
      bpm = bpm_text,
      num = num,
      denom = denom,
    })
  end
  return str_format("Tempo: %s BPM | Time Signature: %d/%d",
    bpm_text, num, denom)
end

-- Replace pipe characters in track / item names so they don't collide with
-- the pipe-delimited row format the snapshot uses. Pipes are exceedingly
-- rare in real REAPER track names; the substitution keeps the format
-- parseable even when they do appear.
local function _scrub_pipes(s)
  s = tostring(s or "")
  -- gsub allocates a new string regardless of whether it matched; pipes
  -- are exceedingly rare in real REAPER track names, so short-circuit
  -- the common case. Called hundreds of times per snapshot on large
  -- sessions.
  if not s:find("|", 1, true) then return s end
  return (s:gsub("|", "_"))
end

-- Best-effort display name for a media item. Prefer take name, then source
-- filename, and keep a stable placeholder when REAPER exposes neither.
function CTX.media_item_name(item)
  if not item then return "(unknown item)" end
  local take = reaper.GetActiveTake and reaper.GetActiveTake(item) or nil
  if take and reaper.GetTakeName then
    local ok, name = pcall(reaper.GetTakeName, take)
    if ok and name and tostring(name) ~= "" then return tostring(name) end
  end
  if take and reaper.GetSetMediaItemTakeInfo_String then
    local ok, _, name = pcall(reaper.GetSetMediaItemTakeInfo_String, take,
      "P_NAME", "", false)
    if ok and name and tostring(name) ~= "" then return tostring(name) end
  end
  if take and reaper.GetMediaItemTake_Source
      and reaper.GetMediaSourceFileName then
    local ok_src, src = pcall(reaper.GetMediaItemTake_Source, take)
    if ok_src and src then
      local ok_name, filename = pcall(reaper.GetMediaSourceFileName, src)
      if ok_name and filename and tostring(filename) ~= "" then
        filename = tostring(filename)
        return filename:match("[^/\\]+$") or filename
      end
    end
  end
  return "(unnamed item)"
end

-- Whether a selected-items readback should include item/take names. Names add
-- tokens, so the snapshot only includes them when the prompt actually asks.
function CTX.prompt_wants_selected_item_names(text)
  local lt = tostring(text or ""):lower()
  if lt == "" then return false end
  if lt:find("what's selected", 1, true)
      or lt:find("whats selected", 1, true)
      or lt:find("what is selected", 1, true)
      or lt:find("what's currently selected", 1, true)
      or lt:find("what is currently selected", 1, true) then
    return true
  end
  if lt:find("selected", 1, true)
      and (lt:find("item", 1, true)
        or lt:find("media", 1, true)
        or lt:find("name", 1, true)) then
    return true
  end
  return lt:find("item name", 1, true) ~= nil
    or lt:find("media item name", 1, true) ~= nil
end

-- Resolve a project pointer for snapshot / context use. S.pending_project
-- is captured at user-send time; long-running scans, popups, or provider
-- round-trips can race with the user closing or swapping the project tab,
-- leaving the cached userdata stale. Walking a snapshot off a stale
-- pointer would emit garbage (or crash on subsequent CTX.* calls). The
-- helper revalidates via ValidatePtr2 before each use; on failure it
-- falls back to the active project so the snapshot is built fresh against
-- the tab the user is now looking at.
-- Exported as CTX.resolve_pending_project for retry/resume code in ReaAssist.lua.
local function _resolve_pending_project()
  local p = S.pending_project
  if p and reaper.ValidatePtr2(0, p, "ReaProject*") then
    return p
  end
  if p then
    Log.line("CTX", "pending_project pointer is stale "
      .. "(project tab closed mid-request); falling back to "
      .. "active project")
  end
  return reaper.EnumProjects(-1)
end
CTX.resolve_pending_project = _resolve_pending_project

-- CTX.tracks(proj, opts)
-- opts.minimal: when true, emit ONLY selected tracks (plus a summary line
-- with the total count). Used by JSFX-intent prompts where the snapshot
-- ships a generic "create me an effect file" request and the per-track
-- listing is dead weight -- the model writes EEL2 against spl0/spl1, not
-- against any specific track. On a 80-track session this drops the tracks
-- block from ~1.1KB to ~80 bytes.
function CTX.tracks(proj, opts)
  local count = R_CountTracks(proj)
  if count == 0 then return "Tracks: none" end
  local minimal = opts and opts.minimal
  local sel_lines = {}
  local lines = {
    str_format("Tracks (N=%d) [idx|name|items|folder_delta]:", count),
  }
  for i = 0, count - 1 do
    -- Long-lived defer scripts can race with project tab close / reload
    -- between R_CountTracks and the following R_GetTrack: the count
    -- snapshot becomes stale and R_GetTrack returns nil for indices the
    -- count thought existed. R_GetTrackName(nil) would then crash.
    local tr = R_GetTrack(proj, i)
    if tr then
      local _, nm      = R_GetTrackName(tr)
      local item_count = R_CountTrackMediaItems(tr)
      local folder_delta =
        math_floor(R_GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
      if minimal then
        if R_IsTrackSelected(tr) then
          sel_lines[#sel_lines+1] = str_format(
            "%d|%s|%d|%d", i + 1, _scrub_pipes(nm), item_count,
            folder_delta)
        end
      else
        lines[#lines+1] = str_format("%d|%s|%d|%d",
          i + 1, _scrub_pipes(nm), item_count, folder_delta)
      end
    end
  end
  if minimal then
    if #sel_lines == 0 then
      return str_format(
        "Tracks (N=%d): none selected (full list omitted -- JSFX prompt)",
        count)
    end
    local out = {
      str_format(
        "Tracks (N=%d, showing selected only -- JSFX prompt) [idx|name|items|folder_delta]:",
        count),
    }
    for _, ln in ipairs(sel_lines) do out[#out+1] = ln end
    return tbl_concat(out, "\n")
  end
  return tbl_concat(lines, "\n")
end

-- CTX.track_flags(proj) -> string
-- On-demand bucket: returns mute/solo/arm state for all tracks.
function CTX.track_flags(proj)
  local count = R_CountTracks(proj)
  local rows = {}
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr then
      local flags = {}
      if R_GetMediaTrackInfo_Value(tr, "B_MUTE")   == 1 then flags[#flags+1] = "muted"  end
      if R_GetMediaTrackInfo_Value(tr, "I_SOLO")   ~= 0 then flags[#flags+1] = "soloed" end
      if R_GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then flags[#flags+1] = "armed"  end
      if #flags > 0 then
        local _, nm = R_GetTrackName(tr)
        rows[#rows+1] = str_format("%d|%s|%s",
          i + 1, _scrub_pipes(nm), tbl_concat(flags, ","))
      end
    end
  end
  if #rows == 0 then return "Track flags: none (no tracks muted/soloed/armed)" end
  table.insert(rows, 1, "Track flags [idx|name|flags]:")
  return tbl_concat(rows, "\n")
end

-- Filtered track-state reader for local questions like "which selected tracks
-- are muted?" or "are any tracks unarmed?". opts chooses flag(s), inversion, and
-- selected-only scope; output stays capped for large sessions.
function CTX.tracks_matching_flags(proj, opts)
  opts = opts or {}
  local selected_only = opts.selected_only == true
  local wanted_count = (opts.muted and 1 or 0)
    + (opts.soloed and 1 or 0)
    + (opts.armed and 1 or 0)
  if wanted_count == 0 then return CTX.track_flags(proj) end
  local single_label
  if wanted_count == 1 then
    if opts.muted then single_label = opts.invert and "Unmuted tracks" or "Muted tracks"
    elseif opts.soloed then single_label = opts.invert and "Unsoloed tracks" or "Soloed tracks"
    else single_label = opts.invert and "Unarmed tracks" or "Armed tracks" end
    if selected_only then single_label = "Selected " .. single_label:lower() end
  end
  local rows = {}
  local total = 0
  local count = R_CountTracks(proj)
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and (not selected_only or R_IsTrackSelected(tr)) then
      local flags = {}
      local muted_value = R_GetMediaTrackInfo_Value(tr, "B_MUTE")
      local soloed_value = R_GetMediaTrackInfo_Value(tr, "I_SOLO")
      local armed_value = R_GetMediaTrackInfo_Value(tr, "I_RECARM")
      local is_muted = muted_value == true or (tonumber(muted_value) or 0) ~= 0
      local is_soloed = soloed_value == true or (tonumber(soloed_value) or 0) ~= 0
      local is_armed = armed_value == true or (tonumber(armed_value) or 0) ~= 0
      if opts.muted and ((opts.invert and not is_muted)
          or ((not opts.invert) and is_muted)) then
        flags[#flags + 1] = "muted"
      end
      if opts.soloed and ((opts.invert and not is_soloed)
          or ((not opts.invert) and is_soloed)) then
        flags[#flags + 1] = "soloed"
      end
      if opts.armed and ((opts.invert and not is_armed)
          or ((not opts.invert) and is_armed)) then
        flags[#flags + 1] = "armed"
      end
      if #flags > 0 then
        total = total + 1
        if #rows < 40 then
          local _, nm = R_GetTrackName(tr)
          if single_label then
            rows[#rows + 1] = str_format("%d. %s", i + 1,
              nm ~= "" and nm or "(unnamed)")
          else
            rows[#rows + 1] = str_format("%d|%s|%s", i + 1,
              _scrub_pipes(nm), tbl_concat(flags, ","))
          end
        end
      end
    end
  end
  if single_label then
    if total == 0 then return single_label .. ": none" end
    local lines = { str_format("%s: %d", single_label, total) }
    for _, row in ipairs(rows) do lines[#lines + 1] = row end
    if total > #rows then
      lines[#lines + 1] = str_format("(+%d more)", total - #rows)
    end
    return tbl_concat(lines, "\n")
  end
  local label = selected_only and "Selected track flags" or "Track flags"
  if total == 0 then return label .. ": none" end
  table.insert(rows, 1, label .. " [idx|name|flags]:")
  if total > #rows - 1 then
    rows[#rows + 1] = str_format("(+%d more)", total - (#rows - 1))
  end
  return tbl_concat(rows, "\n")
end

-- Compact per-track properties bucket used by snapshots and local answers. It
-- intentionally reports only stable scalar state that the model can reason over
-- safely: volume, pan, mute, solo, arm, and master/parent send.
function CTX.track_properties(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local source_track = opts and opts.source_track or nil
  local source_name = opts and opts.source_name or nil
  local rows = {}
  local count = R_CountTracks(proj)
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr
        and (not selected_only or R_IsTrackSelected(tr))
        and (not source_track or tr == source_track) then
      local _, nm = R_GetTrackName(tr)
      local vol = R_GetMediaTrackInfo_Value(tr, "D_VOL") or 1
      local vol_db = vol > 0 and str_format("%.2f", 20 * math.log(vol, 10))
        or "-inf"
      local pan_pct = str_format("%.0f",
        (R_GetMediaTrackInfo_Value(tr, "D_PAN") or 0) * 100)
      local muted = R_GetMediaTrackInfo_Value(tr, "B_MUTE") == 1
      local soloed = (R_GetMediaTrackInfo_Value(tr, "I_SOLO") or 0) ~= 0
      local armed = R_GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
      local main_send = R_GetMediaTrackInfo_Value(tr, "B_MAINSEND") ~= 0
      rows[#rows+1] = str_format("%d|%s|%s|%s|%s|%s|%s|%s",
        i + 1, _scrub_pipes(nm), vol_db, pan_pct,
        muted and "yes" or "no",
        soloed and "yes" or "no",
        armed and "yes" or "no",
        main_send and "yes" or "no")
    end
  end
  if #rows == 0 then
    if source_track then
      return "Track properties: none on " .. (source_name or "track")
    end
    return selected_only and "Track properties: none on selected tracks"
      or "Track properties: none"
  end
  table.insert(rows, 1,
    "Track properties [idx|name|vol_db|pan_pct|muted|solo|armed|main_send]:")
  return tbl_concat(rows, "\n")
end

-- Local target helpers shared by track-property, FX, send, and item readbacks.
-- They prefer exact names, then indexed/selected references, and return clear
-- ambiguity/missing messages instead of guessing a target track.
function CTX.local_track_label(index, name)
  local nm = tostring(name or "")
  if nm ~= "" then return nm end
  if index then return "Track " .. tostring(index) end
  return "track"
end

function CTX.local_track_property_kind(lt)
  local text = tostring(lt or ""):lower()
  local kinds = {}
  local function add(kind)
    for _, existing in ipairs(kinds) do
      if existing == kind then return end
    end
    kinds[#kinds + 1] = kind
  end
  if text:find("%f[%w]volume%f[%W]")
      or text:find("%f[%w]volumes%f[%W]")
      or text:find("%f[%w]fader%f[%W]")
      or text:find("%f[%w]faders%f[%W]") then
    add("volume")
  end
  if text:find("%f[%w]pan%f[%W]")
      or text:find("%f[%w]pans%f[%W]")
      or text:find("%f[%w]panned%f[%W]") then
    add("pan")
  end
  if text:find("%f[%w]mute%f[%W]")
      or text:find("%f[%w]muted%f[%W]")
      or text:find("%f[%w]unmute%f[%W]")
      or text:find("%f[%w]unmuted%f[%W]") then
    add("mute")
  end
  if text:find("%f[%w]solo%f[%W]")
      or text:find("%f[%w]soloed%f[%W]")
      or text:find("%f[%w]unsolo%f[%W]")
      or text:find("%f[%w]unsoloed%f[%W]") then
    add("solo")
  end
  if text:find("%f[%w]armed%f[%W]")
      or text:find("%f[%w]unarmed%f[%W]")
      or text:find("record arm", 1, true)
      or text:find("record-armed", 1, true) then
    add("armed")
  end
  if text:find("main output", 1, true)
      or text:find("master output", 1, true)
      or text:find("main send", 1, true)
      or text:find("master send", 1, true)
      or text:find("master/parent", 1, true)
      or text:find("parent send", 1, true) then
    add("main_send")
  end
  return #kinds == 1 and kinds[1] or nil
end

function CTX.track_property_answer(source_track, source_index, source_name, kind)
  if not source_track then return nil end
  local label = CTX.local_track_label(source_index, source_name)
  if kind == "volume" then
    local vol = R_GetMediaTrackInfo_Value(source_track, "D_VOL") or 1
    local vol_db = vol > 0 and str_format("%.2f dB",
      20 * math.log(vol, 10)) or "-inf dB"
    return str_format("%s volume is %s.", label, vol_db)
  elseif kind == "pan" then
    local raw_pan_pct = (R_GetMediaTrackInfo_Value(
      source_track, "D_PAN") or 0) * 100
    local pan_pct = raw_pan_pct >= 0
      and math_floor(raw_pan_pct + 0.5)
      or -math_floor(math.abs(raw_pan_pct) + 0.5)
    if pan_pct == 0 then return str_format("%s pan is centered.", label) end
    local side = pan_pct < 0 and "left" or "right"
    return str_format("%s pan is %d%% %s.", label, math.abs(pan_pct), side)
  elseif kind == "mute" then
    local muted = R_GetMediaTrackInfo_Value(source_track, "B_MUTE") == 1
    return str_format("%s is %s.", label, muted and "muted" or "not muted")
  elseif kind == "solo" then
    local soloed = (R_GetMediaTrackInfo_Value(source_track, "I_SOLO") or 0) ~= 0
    return str_format("%s is %s.", label, soloed and "soloed" or "not soloed")
  elseif kind == "armed" then
    local armed = R_GetMediaTrackInfo_Value(source_track, "I_RECARM") == 1
    return str_format("%s is %s.", label,
      armed and "record armed" or "not record armed")
  elseif kind == "main_send" then
    local main_send = R_GetMediaTrackInfo_Value(source_track, "B_MAINSEND") ~= 0
    return main_send
      and str_format("%s sends to the master/parent output.", label)
      or str_format("%s does not send to the master/parent output.", label)
  end
  return nil
end

function CTX.tracks_without_master_output(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local label = selected_only and "Selected tracks without master output"
    or "Tracks without master output"
  local total = 0
  local rows = {}
  local count = R_CountTracks(proj)
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and (not selected_only or R_IsTrackSelected(tr)) then
      if R_GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 0 then
        total = total + 1
        if #rows < 40 then
          local _, nm = R_GetTrackName(tr)
          rows[#rows + 1] = str_format("%d. %s", i + 1,
            nm ~= "" and nm or "(unnamed)")
        end
      end
    end
  end
  if total == 0 then return label .. ": none" end
  local lines = { str_format("%s: %d", label, total) }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > #rows then
    lines[#lines + 1] = str_format("(+%d more)", total - #rows)
  end
  return tbl_concat(lines, "\n")
end

function CTX.track_master_output_answer(source_track, source_name)
  if not source_track then return nil end
  local has_master = (R_GetMediaTrackInfo_Value(source_track, "B_MAINSEND") or 0) ~= 0
  if has_master then
    return "Master output: yes, " .. tostring(source_name or "track")
      .. " sends to master"
  end
  return "Master output: no, " .. tostring(source_name or "track")
    .. " does not send to master"
end

function CTX.local_master_output_presence_query(lt)
  local text = tostring(lt or ""):lower()
  text = text:gsub("[%.%?%!]+$", "")
  local track_query =
       text:match("^%s*does%s+(.+)%s+have%s+master%s+output%s*$")
    or text:match("^%s*does%s+(.+)%s+have%s+main%s+output%s*$")
    or text:match("^%s*does%s+(.+)%s+send%s+to%s+master%s*$")
    or text:match("^%s*does%s+(.+)%s+send%s+to%s+the%s+master%s*$")
    or text:match("^%s*is%s+(.+)%s+sent%s+to%s+master%s*$")
    or text:match("^%s*is%s+(.+)%s+sent%s+to%s+the%s+master%s*$")
    or text:match("^%s*is%s+(.+)%s+routed%s+to%s+master%s*$")
    or text:match("^%s*is%s+(.+)%s+routed%s+to%s+the%s+master%s*$")
  if not track_query then return nil end
  track_query = track_query:gsub("^%s+", ""):gsub("%s+$", "")
  if track_query == "" then return nil end
  return track_query
end

-- Cap the per-snapshot FX listing so a 100+ track session doesn't dump
-- 30K+ bytes of FX names every turn. Selected tracks are reported first and
-- always survive the cap; remaining tracks fill up to the limit. The model
-- can request the full listing on demand via <context_needed>fx_chains</...>.
CTX.MAX_FX_REPORT = 30

-- FX chain listing by track. This reports plugin names and indices only; live
-- parameter names/values are intentionally deferred to fx_params or fx_inspect.
function CTX.fx(proj, opts)
  local count = R_CountTracks(proj)
  local selected_only = opts and opts.selected_only == true
  local source_track = opts and opts.source_track or nil
  local source_name = opts and opts.source_name or nil
  local sel_with_fx, other_with_fx = {}, {}
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr
        and (not selected_only or R_IsTrackSelected(tr))
        and (not source_track or tr == source_track) then
      local fx_count = R_TrackFX_GetCount(tr)
      if fx_count > 0 then
        local _, nm = R_GetTrackName(tr)
        local fx_names = {}
        for f = 0, fx_count - 1 do
          local _, fx_nm = R_TrackFX_GetFXName(tr, f, "")
          -- Include 0-based index so the assistant can pass it directly to TrackFX_* functions.
          fx_names[#fx_names+1] = str_format("[%d]%s", f, _scrub_pipes(fx_nm))
        end
        local entry = str_format("%d|%s|%s",
          i + 1, _scrub_pipes(nm), tbl_concat(fx_names, ","))
        if R_IsTrackSelected(tr) then
          sel_with_fx[#sel_with_fx+1] = entry
        else
          other_with_fx[#other_with_fx+1] = entry
        end
      end
    end
  end
  local total = #sel_with_fx + #other_with_fx
  if total == 0 then
    if source_track then
      return "FX chains: none on " .. (source_name or "track")
    end
    return selected_only and "FX chains: none on selected tracks" or "FX chains: none"
  end
  local lines = { "FX chains [track_idx|track_name|[fx_idx]fx_name,...]:" }
  for _, e in ipairs(sel_with_fx) do lines[#lines+1] = e end
  local remaining = math_max(0, CTX.MAX_FX_REPORT - #sel_with_fx)
  local shown = 0
  for _, e in ipairs(other_with_fx) do
    if shown >= remaining then break end
    lines[#lines+1] = e
    shown = shown + 1
  end
  local omitted = #other_with_fx - shown
  if omitted > 0 then
    lines[#lines+1] = str_format(
      "(+%d more tracks with FX -- request <context_needed>fx_chains</context_needed> for full)",
      omitted)
  end
  return tbl_concat(lines, "\n")
end

function CTX.tracks_without_fx(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local total = 0
  local rows = {}
  local count = R_CountTracks(proj)
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and (not selected_only or R_IsTrackSelected(tr)) then
      local fx_count = R_TrackFX_GetCount(tr) or 0
      if fx_count == 0 then
        total = total + 1
        if #rows < 40 then
          local _, nm = R_GetTrackName(tr)
          rows[#rows + 1] = str_format("%d. %s", i + 1,
            nm ~= "" and nm or "(unnamed)")
        end
      end
    end
  end
  local label = selected_only and "Selected tracks without FX"
    or "Tracks without FX"
  if total == 0 then return label .. ": none" end
  local lines = { str_format("%s: %d", label, total) }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > #rows then
    lines[#lines + 1] = str_format("(+%d more)", total - #rows)
  end
  return tbl_concat(lines, "\n")
end

function CTX.local_fx_search_key(s)
  s = tostring(s or ""):lower()
  s = s:gsub("^%w+:%s*", "")
  s = s:gsub("%s*%(.-%)%s*$", "")
  s = s:gsub("[^%a%d]", "")
  return s
end

function CTX.local_fx_search_query(lt)
  local q =
       lt:match("^%s*which%s+tracks%s+have%s+(.+)$")
    or lt:match("^%s*what%s+tracks%s+have%s+(.+)$")
    or lt:match("^%s*list%s+tracks%s+with%s+(.+)$")
    or lt:match("^%s*show%s+tracks%s+with%s+(.+)$")
    or lt:match("^%s*which%s+tracks%s+use%s+(.+)$")
    or lt:match("^%s*what%s+tracks%s+use%s+(.+)$")
    or lt:match("^%s*where%s+is%s+(.+)$")
  if not q then return nil end
  q = q:gsub("[%.%?%!]+$", "")
  q = q:gsub("%s+on%s+them%s*$", "")
  q = q:gsub("%s+inserted%s*$", "")
  q = q:gsub("%s+loaded%s*$", "")
  local original_q = q:gsub("^%s+", ""):gsub("%s+$", "")
  if original_q == "fx" or original_q == "plugin" or original_q == "plugins"
      or original_q == "effect" or original_q == "effects" then
    return "*"
  end
  q = q:gsub("%f[%w]plugins?%f[%W]", " ")
  q = q:gsub("%f[%w]effects?%f[%W]", " ")
  q = q:gsub("%f[%w]fx%f[%W]", " ")
  q = q:gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then return nil end
  if q == "any" or q == "all" then return "*" end
  return q
end

function CTX.local_fx_search_keys_for_track(query)
  local raw = tostring(query or ""):lower()
  raw = raw:gsub("[%.%?%!]+$", "")
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  raw = raw:gsub("^the%s+", ""):gsub("^a%s+", ""):gsub("^an%s+", "")
  local seen, keys = {}, {}
  local function add_key(value)
    local key = CTX.local_fx_search_key(value)
    if key ~= "" and not seen[key] then
      keys[#keys + 1] = key
      seen[key] = true
    end
  end
  add_key(query)
  local aliases = {
    comp = { "reacomp", "comp" },
    compression = { "reacomp", "comp" },
    compressor = { "reacomp", "comp" },
    delay = { "readelay", "delay" },
    eq = { "reaeq", "eq" },
    echo = { "readelay", "echo" },
    gate = { "reagate", "gate" },
    limiter = { "realimit", "limit" },
    limit = { "realimit", "limit" },
    reverb = { "reaverbate", "reverb", "verb" },
    verb = { "reaverbate", "verb" },
  }
  for _, value in ipairs(aliases[raw] or {}) do add_key(value) end
  return keys
end

function CTX.local_fx_query_without_track_name(query, track_name)
  local track_tokens = {}
  for word in tostring(track_name or ""):lower():gsub("[^%w]+", " "):gmatch("%w+") do
    track_tokens[word] = true
  end
  local stop = {
    a = true, an = true, any = true, ["do"] = true, does = true, did = true,
    had = true, has = true, have = true, inserted = true, loaded = true,
    on = true, running = true, selected = true, that = true, the = true,
    this = true, track = true, tracks = true, use = true, uses = true,
    using = true, with = true, current = true,
  }
  local out = {}
  for word in tostring(query or ""):lower():gsub("[^%w]+", " "):gmatch("%w+") do
    if not track_tokens[word] and not stop[word] then out[#out + 1] = word end
  end
  local narrowed = tbl_concat(out, " ")
  if narrowed == "" then return nil end
  return narrowed
end

function CTX.fx_on_track_matching(proj, source_track, source_index, source_name, query)
  if not source_track then return nil end
  local keys = CTX.local_fx_search_keys_for_track(query)
  local total, rows = 0, {}
  local fx_count = R_TrackFX_GetCount(source_track) or 0
  for f = 0, fx_count - 1 do
    local _, fx_nm = R_TrackFX_GetFXName(source_track, f, "")
    local fx_key = CTX.local_fx_search_key(fx_nm)
    local matched = false
    for _, q in ipairs(keys) do
      if (#q >= 3 or q == "eq") and fx_key:find(q, 1, true) then
        matched = true
        break
      end
    end
    if matched then
      total = total + 1
      if #rows < CTX.MAX_FX_REPORT then
        rows[#rows + 1] = str_format("%d|%s|%d|%s",
          source_index or 0, _scrub_pipes(source_name or "(unnamed)"),
          f, _scrub_pipes(fx_nm))
      end
    end
  end
  if total == 0 then
    return "FX search: none matching " .. tostring(query or "")
      .. " on " .. tostring(source_name or "track")
  end
  local lines = {
    str_format("FX search: %s on %s (N=%d) [track_idx|track_name|fx_idx|fx_name]:",
      tostring(query or ""), tostring(source_name or "track"), total)
  }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > CTX.MAX_FX_REPORT then
    lines[#lines + 1] = str_format("(+%d more)", total - CTX.MAX_FX_REPORT)
  end
  return tbl_concat(lines, "\n")
end

function CTX.fx_on_track_presence(proj, source_track, source_index, source_name, query)
  if not source_track then return nil end
  local keys = CTX.local_fx_search_keys_for_track(query)
  local total, rows = 0, {}
  local fx_count = R_TrackFX_GetCount(source_track) or 0
  for f = 0, fx_count - 1 do
    local _, fx_nm = R_TrackFX_GetFXName(source_track, f, "")
    local fx_key = CTX.local_fx_search_key(fx_nm)
    local matched = false
    for _, q in ipairs(keys) do
      if (#q >= 3 or q == "eq") and fx_key:find(q, 1, true) then
        matched = true
        break
      end
    end
    if matched then
      total = total + 1
      if #rows < CTX.MAX_FX_REPORT then
        rows[#rows + 1] = str_format("%d|%s|%d|%s",
          source_index or 0, _scrub_pipes(source_name or "(unnamed)"),
          f, _scrub_pipes(fx_nm))
      end
    end
  end
  if total == 0 then
    local label = CTX.local_track_label(source_index, source_name)
    local q = tostring(query or ""):lower()
    if q == "" or q == "fx" or q == "plugin" or q == "plugins"
        or q == "effect" or q == "effects" or q == "there fx" then
      return label .. " has no FX."
    end
    return label .. " has no " .. tostring(query or "") .. " FX."
  end
  local lines = {
    str_format("FX presence: yes, %s has %s (N=%d) [track_idx|track_name|fx_idx|fx_name]:",
      tostring(source_name or "track"), tostring(query or ""), total)
  }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > CTX.MAX_FX_REPORT then
    lines[#lines + 1] = str_format("(+%d more)", total - CTX.MAX_FX_REPORT)
  end
  return tbl_concat(lines, "\n")
end

function CTX.track_fx_presence_answer(proj, source_track, source_index, source_name)
  if not source_track then return nil end
  local label = CTX.local_track_label(source_index, source_name)
  local fx_count = R_TrackFX_GetCount(source_track) or 0
  if fx_count == 0 then return label .. " has no FX." end
  local names = {}
  for f = 0, fx_count - 1 do
    local _, fx_nm = R_TrackFX_GetFXName(source_track, f, "")
    names[#names + 1] = tostring(fx_nm or "FX")
    if #names >= 3 then break end
  end
  local suffix = fx_count > #names and str_format(", +%d more",
    fx_count - #names) or ""
  return str_format("%s has %d FX: %s%s.", label, fx_count,
    tbl_concat(names, ", "), suffix)
end

function CTX.local_track_target_in_text(facts, query, prefix, force_singular_error)
  local source_track, source_index, source_name, ambiguous, ambiguous_names =
    CTX.local_track_named_in_text(facts, query)
  if ambiguous then
    return nil, nil, nil, CTX.local_track_ambiguity(prefix or "Track target", ambiguous_names)
  end
  if not source_track then
    local text = tostring(query or ""):lower()
    local plural_selected = text:find("%f[%w]selected%s+tracks%f[%W]")
      or text:find("%f[%w]current%s+tracks%f[%W]")
      or text:find("%f[%w]these%s+tracks%f[%W]")
      or text:find("%f[%w]those%s+tracks%f[%W]")
    local singular_selected = not plural_selected
      and (text:find("%f[%w]selected%f[%W]")
        or text:find("%f[%w]current%f[%W]")
        or text:find("%f[%w]this%f[%W]")
        or text:find("%f[%w]that%f[%W]"))
    if singular_selected then
      local singular_text = text:gsub("%f[%w]selected%f[%W]", "selected track")
        :gsub("%f[%w]current%f[%W]", "current track")
        :gsub("%f[%w]this%f[%W]", "this track")
        :gsub("%f[%w]that%f[%W]", "that track")
      local selected_error
      source_track, source_index, source_name, selected_error =
        CTX.local_singular_selected_track_in_text(
          facts, singular_text, prefix or "Track target", true)
      if selected_error and (force_singular_error
          or CTX.local_fx_query_without_track_name(query, "")) then
        return nil, nil, nil, selected_error
      end
    end
  end
  return source_track, source_index, source_name, nil
end

function CTX.local_any_track_target_in_text(facts, query, prefix)
  local source_track, source_index, source_name, missing_index =
    CTX.local_track_index_in_text(facts, query)
  if missing_index then
    return nil, nil, nil, tostring(prefix or "Track target")
      .. ": track " .. tostring(missing_index) .. " not found"
  end
  if source_track then return source_track, source_index, source_name, nil end
  return CTX.local_track_target_in_text(facts, query, prefix, true)
end

function CTX.local_track_fx_query_in_text(facts, query, prefix)
  local source_track, source_index, source_name, target_error =
    CTX.local_track_target_in_text(facts, query, prefix or "FX search")
  if target_error then return nil, nil, nil, nil, target_error end
  if not source_track then return nil end
  local fx_query = CTX.local_fx_query_without_track_name(query, source_name)
  if not fx_query then return nil end
  return source_track, source_index, source_name, fx_query, nil
end

function CTX.local_track_fx_query_from_parts(facts, track_query, fx_query, prefix)
  local source_track, source_index, source_name, target_error =
    CTX.local_track_target_in_text(facts, track_query, prefix or "FX search", true)
  if target_error then return nil, nil, nil, nil, target_error end
  if not source_track then return nil end
  local narrowed_fx_query = CTX.local_fx_query_without_track_name(fx_query, "")
  if not narrowed_fx_query then return nil end
  return source_track, source_index, source_name, narrowed_fx_query, nil
end

function CTX.local_fx_presence_query(lt)
  local text = tostring(lt or ""):lower()
  text = text:gsub("[%.%?%!]+$", "")
  local track_query, fx_query = text:match("^%s*does%s+(.+)%s+have%s+(.+)$")
  if not track_query then
    track_query, fx_query = text:match("^%s*do%s+(.+)%s+have%s+(.+)$")
  end
  if not track_query then
    track_query, fx_query = text:match("^%s*does%s+(.+)%s+use%s+(.+)$")
  end
  if not track_query then
    track_query, fx_query = text:match("^%s*do%s+(.+)%s+use%s+(.+)$")
  end
  if not track_query then
    track_query, fx_query = text:match("^%s*is%s+(.+)%s+using%s+(.+)$")
  end
  if not track_query then
    track_query, fx_query = text:match("^%s*are%s+(.+)%s+using%s+(.+)$")
  end
  if not track_query then
    fx_query, track_query = text:match("^%s*is%s+(.+)%s+on%s+(.+)$")
  end
  if not track_query then
    fx_query, track_query = text:match("^%s*are%s+(.+)%s+on%s+(.+)$")
  end
  if not track_query or not fx_query then return nil end
  track_query = track_query:gsub("^%s+", ""):gsub("%s+$", "")
  fx_query = fx_query:gsub("^%s+", ""):gsub("%s+$", "")
  local fx_clean = CTX.local_fx_query_without_track_name(fx_query, "")
  if not fx_clean then return nil end
  if fx_clean == "fx" or fx_clean == "plugin" or fx_clean == "plugins"
      or fx_clean == "effect" or fx_clean == "effects" then
    return nil
  end
  return track_query, fx_clean
end

function CTX.fx_tracks_with(proj, query)
  local q = CTX.local_fx_search_key(query)
  if q == "" then return nil end
  if #q < 3 and q ~= "eq" then return nil end
  local rows = {}
  local total = 0
  local count = R_CountTracks(proj)
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr then
      local fx_count = R_TrackFX_GetCount(tr)
      for f = 0, fx_count - 1 do
        local _, fx_nm = R_TrackFX_GetFXName(tr, f, "")
        local fx_key = CTX.local_fx_search_key(fx_nm)
        if fx_key:find(q, 1, true) then
          total = total + 1
          if #rows < CTX.MAX_FX_REPORT then
            local _, nm = R_GetTrackName(tr)
            rows[#rows + 1] = str_format("%d|%s|%d|%s",
              i + 1, _scrub_pipes(nm), f, _scrub_pipes(fx_nm))
          end
        end
      end
    end
  end
  local master = reaper.GetMasterTrack and reaper.GetMasterTrack(proj)
  if master then
    local fx_count = R_TrackFX_GetCount(master) or 0
    for f = 0, fx_count - 1 do
      local _, fx_nm = R_TrackFX_GetFXName(master, f, "")
      local fx_key = CTX.local_fx_search_key(fx_nm)
      if fx_key:find(q, 1, true) then
        total = total + 1
        if #rows < CTX.MAX_FX_REPORT then
          local _, nm = R_GetTrackName(master)
          if nm == "" or nm:lower() == "master" then nm = "Master" end
          rows[#rows + 1] = str_format("%s|%s|%d|%s",
            "M", _scrub_pipes(nm), f, _scrub_pipes(fx_nm))
        end
      end
    end
  end
  if total == 0 then
    return "FX search: none matching " .. tostring(query or "")
  end
  local lines = {
    str_format("FX search: %s (N=%d) [track_idx|track_name|fx_idx|fx_name]:",
      tostring(query or ""), total)
  }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > CTX.MAX_FX_REPORT then
    lines[#lines + 1] = str_format("(+%d more)", total - CTX.MAX_FX_REPORT)
  end
  return tbl_concat(lines, "\n")
end

function CTX.master_fx(proj)
  local master = reaper.GetMasterTrack and reaper.GetMasterTrack(proj)
  if not master then return "FX chains: master track unavailable" end
  local _, nm = R_GetTrackName(master)
  if nm == "" or nm:lower() == "master" then nm = "Master" end
  local fx_count = R_TrackFX_GetCount(master) or 0
  if fx_count == 0 then return "FX chains: none on " .. nm end
  local fx_names = {}
  for f = 0, fx_count - 1 do
    local _, fx_nm = R_TrackFX_GetFXName(master, f, "")
    fx_names[#fx_names + 1] = str_format("[%d]%s", f, _scrub_pipes(fx_nm))
  end
  return "FX chains [track_idx|track_name|[fx_idx]fx_name,...]:\n"
    .. str_format("%s|%s|%s", "M", _scrub_pipes(nm),
      tbl_concat(fx_names, ","))
end

function CTX.master_properties(proj)
  local master = reaper.GetMasterTrack and reaper.GetMasterTrack(proj)
  if not master then return "Master properties: master track unavailable" end
  local _, nm = R_GetTrackName(master)
  if nm == "" or nm:lower() == "master" then nm = "Master" end
  local vol = R_GetMediaTrackInfo_Value(master, "D_VOL") or 1
  local vol_db = vol > 0 and str_format("%.2f", 20 * math.log(vol, 10))
    or "-inf"
  local pan_pct = str_format("%.0f",
    (R_GetMediaTrackInfo_Value(master, "D_PAN") or 0) * 100)
  local muted = R_GetMediaTrackInfo_Value(master, "B_MUTE") == 1
  local soloed = (R_GetMediaTrackInfo_Value(master, "I_SOLO") or 0) ~= 0
  local fx_count = R_TrackFX_GetCount(master) or 0
  return "Master properties [name|vol_db|pan_pct|muted|solo|fx_count]:\n"
    .. str_format("%s|%s|%s|%s|%s|%d", _scrub_pipes(nm), vol_db,
      pan_pct, muted and "yes" or "no", soloed and "yes" or "no",
      fx_count)
end

function CTX.selected(proj)
  local count    = R_CountTracks(proj)
  local selected = {}
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and R_IsTrackSelected(tr) then
      local _, nm = R_GetTrackName(tr)
      selected[#selected+1] = str_format("%q (index %d)", nm, i + 1)
    end
  end
  return #selected > 0
    and ("Selected tracks: " .. tbl_concat(selected, ", "))
    or  "Selected tracks: none"
end

-- Returns a TARGET HINT block for the snapshot when one or more tracks are
-- selected at request time. Lifts snapshot data into instruction-shape so
-- the model writes code targeting the captured track(s) by index/name first
-- and falls back to live GetSelectedTrack() only if the captured target no
-- longer exists. Without this, the model commonly emits pure GetSelectedTrack
-- calls and a script delayed past the user's next click produces "No track
-- selected." Returns "" when no tracks are selected (suppresses the block).
function CTX.target_hint(proj, user_text)
  local count = R_CountTracks(proj)
  local sel = {}
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and R_IsTrackSelected(tr) then
      local _, nm = R_GetTrackName(tr)
      sel[#sel+1] = { idx = i + 1, name = nm }
    end
  end
  if #sel == 0 then return "" end
  -- Suppress on clearly create-new-track prompts. Small models have been
  -- observed obeying the hint over the explicit user request ("Create a
  -- new Twin 3 synth track" emitted code that targeted the existing
  -- selected Vocal track instead). Negative-marker filter is conservative
  -- (only suppresses on unambiguous phrases); requests that operate on
  -- existing tracks still get the hint.
  if user_text and user_text ~= "" then
    local t = user_text:lower()
    if t:find("create%s+a?%s*new%s+track")
       or t:find("create%s+a?%s*new%s+%w+%s+track")
       or t:find("add%s+a?%s*new%s+track")
       or t:find("add%s+a?%s*new%s+%w+%s+track")
       or t:find("insert%s+a?%s*new%s+track")
       or t:find("insert%s+track") then
      return ""
    end
  end
  local lines = { "TARGET HINT:" }
  if #sel == 1 then
    lines[#lines+1] = str_format(
      "Selected track at request time: index %d, name %q.", sel[1].idx, sel[1].name)
  else
    local list = {}
    for _, e in ipairs(sel) do
      list[#list+1] = str_format("index %d, name %q", e.idx, e.name)
    end
    lines[#lines+1] = "Selected tracks at request time: " .. tbl_concat(list, "; ") .. "."
  end
  lines[#lines+1] = "Use this captured target ONLY when: (a) the user "
    .. "request says \"the/this/selected/current\" track, OR (b) the request "
    .. "operates on an existing track AND no prior turn in this conversation "
    .. "already operated on a specific track. A targetless follow-up to a "
    .. "prior turn that targeted Track N continues on Track N -- do NOT "
    .. "switch to this captured target unless the user said "
    .. "\"selected/current/this/the\" track or named a different one. "
    .. "IGNORE this block when the user asks to create, insert, or add a "
    .. "new track -- those should call InsertTrackAtIndex and target the "
    .. "freshly created track, not the captured one. When honoring the "
    .. "hint: validate the target still exists (and preferably still has "
    .. "the same name); fall back to reaper.GetSelectedTrack() only if "
    .. "the captured target is invalid."
  return tbl_concat(lines, "\n")
end

-- Uses GetSet_LoopTimeRange2 (project-aware variant) instead of the non-project
-- GetSet_LoopTimeRange so the correct tab's time selection is always queried.
function CTX.time_selection(proj, opts)
  local ts, te = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  if te > ts then
    if opts and opts.include_length then
      return str_format("Time selection: %.3fs - %.3fs | length=%.3fs",
        ts, te, te - ts)
    end
    return str_format("Time selection: %.3fs - %.3fs", ts, te)
  end
  return "Time selection: none"
end

-- CTX.cursor(proj) -> string
-- Reports the edit cursor position in seconds. Useful for scripting questions
-- that involve inserting items, markers, or time selections at the cursor.
-- Uses GetCursorPositionEx (project-aware variant) so the correct tab is
-- always queried even if the user has switched projects while waiting.
function CTX.cursor(proj)
  local pos = reaper.GetCursorPositionEx(proj)
  return str_format("Edit cursor: %.3fs", pos)
end

function CTX.project_length(proj)
  local length = reaper.GetProjectLength and tonumber(reaper.GetProjectLength(proj)) or nil
  if not length or length < 0 then
    length = 0
    if reaper.CountMediaItems and reaper.GetMediaItem then
      local n = reaper.CountMediaItems(proj) or 0
      for i = 0, n - 1 do
        local item = reaper.GetMediaItem(proj, i)
        if item then
          local pos = R_GetMediaItemInfo_Value(item, "D_POSITION") or 0
          local len = R_GetMediaItemInfo_Value(item, "D_LENGTH") or 0
          if pos + len > length then length = pos + len end
        end
      end
    end
  end
  return str_format("Project length: %.3fs", length or 0)
end

-- CTX.sample_rate(proj) -> string
-- Reports the project sample rate. Uses GetSetProjectInfo with "PROJECT_SRATE"
-- which is the project-aware API for reading sample rate as a numeric value.
-- Falls back to 44100 if the call returns 0 (e.g. unsaved new project).
function CTX.sample_rate(proj)
  local sr = reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false)
  if not sr or sr <= 0 then sr = 44100 end
  return str_format("Sample rate: %d Hz", math_floor(sr))
end

-- CTX.play_state(proj) -> string
-- Reports transport state: stopped, playing, recording, or paused.
-- GetPlayStateEx is the project-aware variant; bitmask: bit 0 = playing,
-- bit 1 = paused, bit 2 = recording.
function CTX.play_state(proj)
  local state = reaper.GetPlayStateEx(proj)
  local label
  if     state == 0 then label = "stopped"
  elseif state & 4  ~= 0 then label = "recording"
  elseif state & 2  ~= 0 then label = "paused"
  elseif state & 1  ~= 0 then label = "playing"
  else                        label = "stopped"
  end
  return "Transport: " .. label
end

-- CTX.loop(proj) -> string
-- Reports whether loop is enabled and the loop point range (distinct from the
-- time selection). GetSet_LoopTimeRange2 with is_loop=true returns loop points.
function CTX.loop(proj, opts)
  local ls, le = reaper.GetSet_LoopTimeRange2(proj, false, true, 0, 0, false)
  local enabled = reaper.GetSetRepeatEx(proj, -1) == 1
  if le > ls then
    if opts and opts.include_length then
      return str_format("Loop: %s | %.3fs - %.3fs | length=%.3fs",
        enabled and "enabled" or "disabled", ls, le, le - ls)
    end
    return str_format("Loop: %s | %.3fs - %.3fs",
      enabled and "enabled" or "disabled", ls, le)
  end
  return "Loop: " .. (enabled and "enabled" or "disabled") .. " | no loop points set"
end

function CTX.dynamic_split_settings()
  local resource = reaper.GetResourcePath()
  local ini_path = resource .. RA.SEP .. "reaper.ini"
  local dyn_preset_path = resource .. RA.SEP .. "reaper-dynsplit.ini"
  local function _read_text(path)
    if type(read_file_text) == "function" then return read_file_text(path) end
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  local text = _read_text(ini_path)
  if type(text) ~= "string" or text == "" then
    return "Dynamic Split settings: unavailable"
  end

  local has_dyn = text:find("%[dynamicsplit%]") ~= nil
  local dyn = text:match("%[dynamicsplit%]\r?\n(.-)\r?\n%[")
    or text:match("%[dynamicsplit%]\r?\n(.*)$")
    or ""
  local function kv(src, key)
    return src:match("\n" .. key .. "=([^\r\n]+)")
      or src:match("^" .. key .. "=([^\r\n]+)")
  end
  local function n(src, key)
    return tonumber(kv(src, key) or "")
  end
  local function ms100(v)
    return v and str_format("%.1fms", v / 100) or "?"
  end
  local function db100(v)
    return v and str_format("%.1fdB", v / 100) or "?"
  end
  local function dynsplit_preset_names()
    local preset_text = _read_text(dyn_preset_path)
    if type(preset_text) ~= "string" or preset_text == "" then return "none" end
    local names = {}
    for line in (preset_text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
      local name = line:match("^%s*([^%s]+)%s+")
      if name and name ~= "" then names[#names + 1] = name end
    end
    return #names > 0 and tbl_concat(names, ", ") or "none"
  end

  local sens = n(text, "transientsensitivity")
  local thresh = n(text, "transientthreshold")
  local presets = dynsplit_preset_names()
  if not has_dyn then
    return "Dynamic Split settings [current]: "
      .. "state=not_persisted_likely_defaults"
      .. " | transient_sensitivity="
      .. (sens and str_format("%.1f%%", sens * 100) or "?")
      .. " | transient_threshold="
      .. (thresh and str_format("%.1fdB", thresh) or "?")
      .. " | action_mode=?"
      .. " | min_slice=?"
      .. " | min_silence=?"
      .. " | split_groups=?"
      .. " | saved_presets=" .. presets
  end

  local stretch_mode = n(dyn, "dostretchmarkers")
  local stretch_label = stretch_mode == 3
    and "add stretch markers to selected/grouped"
    or ("raw " .. tostring(stretch_mode or "?"))

  return "Dynamic Split settings [current]: "
    .. "transient_sensitivity="
    .. (sens and str_format("%.1f%%", sens * 100) or "?")
    .. " | transient_threshold="
    .. (thresh and str_format("%.1fdB", thresh) or "?")
    .. " | splitflag=" .. tostring(n(dyn, "splitflag") or "?")
    .. " | action_mode=" .. stretch_label
    .. " | min_slice=" .. ms100(n(dyn, "minslice"))
    .. " | min_silence=" .. ms100(n(dyn, "minsilence"))
    .. " | gate_threshold=" .. db100(n(dyn, "gatethresh"))
    .. " | gate_hysteresis=" .. db100(n(dyn, "gatehyst"))
    .. " | split_groups=" .. tostring(n(dyn, "splitgroups") or "?")
    .. " | snap_offset_window=" .. ms100(n(dyn, "snapoffstime"))
    .. " | saved_presets=" .. presets
end

-- =============================================================================
-- DrumEdit dynamic split profile helper
-- =============================================================================
-- Drum timing edits need deterministic local machinery. The model may choose
-- the workflow, but global Dynamic Split / transient preferences are saved,
-- applied, verified, and restored here rather than in generated ad hoc Lua.
DrumEdit = DrumEdit or {}

DrumEdit.RECOMMENDED_DYNSPLIT_PROFILE = {
  name = "ReaAssist drum guide detection",
  doubles = {
    transientsensitivity = 0.70, -- Transient Detection Settings: Sensitivity
    transientthreshold = -10.0,  -- Transient Detection Settings: Threshold dB
  },
  -- These are the desired Dynamic Split dialog values for the full profile.
  -- The live SWS config API exposes the transient doubles above, but current
  -- REAPER/SWS builds do not expose these Dynamic Split dialog fields as
  -- SNM_*ConfigVar keys. Keep them as an explicit target profile for future
  -- dedicated INI/startup or native-dialog work; do not claim live SWS support.
  dynamic_split = {
    splitflag = 1,        -- split at transients
    minslice = 8900,      -- 89.0 ms
    minsilence = 121000,  -- 1210.0 ms
    postfx = 0,
    minlenLR = 1,
    gatethresh = -2400,
    gatehyst = -600,
    removesilence = 1,
    beatbase = 1,
    snapoffs = 0,
    splitgroups = 1,
    dostretchmarkers = 3, -- add stretch markers to selected/grouped items
    chrommidi = 0,
    padfade = 0,
    snapoffstime = 5000,  -- 50.0 ms, inert while snapoffs=0
    leadpad = 0,
    trailpad = 0,
    lastsplitslider = 100,
    splitcnten = 0,
  },
}

function DrumEdit._config_api(api)
  api = api or reaper
  if type(api) ~= "table" then
    return nil, "REAPER API is unavailable"
  end
  local needed = {
    "SNM_GetDoubleConfigVar",
    "SNM_SetDoubleConfigVar",
  }
  for _, name in ipairs(needed) do
    if type(api[name]) ~= "function" then
      return nil, "SWS config API is unavailable: " .. name
    end
  end
  return api, nil
end

function DrumEdit._sorted_keys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function DrumEdit.snapshot_dynamic_split_profile(opts)
  opts = type(opts) == "table" and opts or {}
  local api, err = DrumEdit._config_api(opts.reaper)
  if not api then return nil, err end
  local profile = opts.profile or DrumEdit.RECOMMENDED_DYNSPLIT_PROFILE
  local snap = {
    doubles = {},
    ints = {},
  }
  for _, key in ipairs(DrumEdit._sorted_keys(profile.doubles)) do
    local value = api.SNM_GetDoubleConfigVar(key, -987654321.25)
    if value == -987654321.25 then
      return nil, "Unsupported SWS double config key: " .. key
    end
    snap.doubles[key] = value
  end
  return snap, nil
end

function DrumEdit.apply_dynamic_split_profile(profile, opts)
  opts = type(opts) == "table" and opts or {}
  local api, err = DrumEdit._config_api(opts.reaper)
  if not api then return false, err end
  profile = profile or DrumEdit.RECOMMENDED_DYNSPLIT_PROFILE

  for _, key in ipairs(DrumEdit._sorted_keys(profile.doubles)) do
    api.SNM_SetDoubleConfigVar(key, profile.doubles[key])
  end
  return true, nil
end

function DrumEdit.verify_dynamic_split_profile(profile, opts)
  opts = type(opts) == "table" and opts or {}
  local api, err = DrumEdit._config_api(opts.reaper)
  if not api then return false, err end
  profile = profile or DrumEdit.RECOMMENDED_DYNSPLIT_PROFILE
  local tolerance = tonumber(opts.tolerance) or 0.0001
  local mismatches = {}

  for _, key in ipairs(DrumEdit._sorted_keys(profile.doubles)) do
    local got = api.SNM_GetDoubleConfigVar(key, -999999)
    local want = profile.doubles[key]
    if math.abs((got or 0) - want) > tolerance then
      mismatches[#mismatches + 1] =
        str_format("%s expected %.4f got %.4f", key, want, got or 0)
    end
  end
  if #mismatches > 0 then return false, tbl_concat(mismatches, "; ") end
  return true, nil
end

function DrumEdit.restore_dynamic_split_profile(snapshot, opts)
  opts = type(opts) == "table" and opts or {}
  local api, err = DrumEdit._config_api(opts.reaper)
  if not api then return false, err end
  if type(snapshot) ~= "table" then
    return false, "Missing Dynamic Split settings snapshot"
  end

  for _, key in ipairs(DrumEdit._sorted_keys(snapshot.doubles)) do
    api.SNM_SetDoubleConfigVar(key, snapshot.doubles[key])
  end
  return true, nil
end

-- CTX.markers(proj) -> string
-- Reports all project markers and region start/end points (capped at
-- CTX.MAX_MARKER_REPORT to keep snapshot size bounded on heavily-markered projects).
-- EnumProjectMarkers3 returns (retval, isrgn, pos, rgnend, name, idx).
-- Markers and region boundaries are both reported; regions include an end pos.
CTX.MAX_MARKER_REPORT, CTX.MAX_ITEM_REPORT, CTX.MAX_SEND_REPORT = 20, 5, 40
function CTX.markers(proj)
  local total = R_CountProjectMarkers(proj)
  if total == 0 then return "Markers/regions: none" end

  local lines = {
    str_format("Markers/regions (N=%d) [type|idx|name|pos_s|end_s]:", total)
  }
  local report_n = math_min(total, CTX.MAX_MARKER_REPORT)
  for i = 0, report_n - 1 do
    local _, isrgn, pos, rgnend, name, idx =
      R_EnumProjectMarkers3(proj, i)
    if isrgn then
      lines[#lines+1] = str_format(
        "R|%d|%s|%.3f|%.3f", idx, _scrub_pipes(name), pos, rgnend)
    else
      lines[#lines+1] = str_format(
        "M|%d|%s|%.3f|", idx, _scrub_pipes(name), pos)
    end
  end
  if total > CTX.MAX_MARKER_REPORT then
    lines[#lines+1] = str_format(
      "(+%d more)", total - CTX.MAX_MARKER_REPORT)
  end
  return tbl_concat(lines, "\n")
end

-- =============================================================================
-- Local read-answer dispatcher support
-- =============================================================================
-- This cluster answers factual project/session questions without making a model
-- call. It is intentionally conservative: read-shaped prompts are answered here,
-- while advice, "how do I", and mutation-shaped prompts return nil so the normal
-- provider/code path can handle them.

-- One pass over the current project used by many local readers. Keeping this
-- fact table small lets local answers avoid repeatedly walking tracks/items.
function CTX.local_project_facts(proj)
  proj = proj or reaper.EnumProjects(-1)
  local _, path = reaper.EnumProjects(-1)
  local facts = {
    proj = proj,
    path = path,
    project_name = path and path ~= "" and path:match("[^/\\]+$") or nil,
    track_count = R_CountTracks(proj),
    selected_tracks = {},
    item_count = 0,
    fx_count = 0,
    tracks_with_fx = 0,
  }
  local _, marker_count, region_count = R_CountProjectMarkers(proj)
  facts.marker_count = marker_count or 0
  facts.region_count = region_count or 0
  for i = 0, facts.track_count - 1 do
    local tr = reaper.GetTrack(proj, i)
    if tr then
      facts.item_count = facts.item_count + (R_CountTrackMediaItems(tr) or 0)
      local fx_count = R_TrackFX_GetCount(tr) or 0
      facts.fx_count = facts.fx_count + fx_count
      if fx_count > 0 then facts.tracks_with_fx = facts.tracks_with_fx + 1 end
    end
  end
  local selected_count = reaper.CountSelectedTracks(proj)
  for i = 0, selected_count - 1 do
    local tr = reaper.GetSelectedTrack(proj, i)
    if tr then
      local _, name = R_GetTrackName(tr)
      facts.selected_tracks[#facts.selected_tracks + 1] = {
        index = math_floor((R_GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) + 0.5),
        name = name ~= "" and name or "(unnamed)",
      }
    end
  end
  return facts
end

function CTX.local_read_selected_tracks(proj)
  local facts = type(proj) == "table" and proj.selected_tracks and proj
    or CTX.local_project_facts(proj)
  local count = #facts.selected_tracks
  if count == 0 then return "Selected tracks: none" end
  local lines = { str_format("Selected tracks: %d", count) }
  for _, tr in ipairs(facts.selected_tracks) do
    lines[#lines + 1] = str_format("%d. %s", tr.index or 0, tr.name or "(unnamed)")
  end
  return tbl_concat(lines, "\n")
end

function CTX.local_read_selection_summary(proj, facts)
  facts = type(facts) == "table" and facts.selected_tracks and facts
    or CTX.local_project_facts(proj)
  local lines = { "Selection:" }
  if #facts.selected_tracks == 0 then
    lines[#lines + 1] = "Selected tracks: none"
  else
    lines[#lines + 1] = str_format("Selected tracks: %d",
      #facts.selected_tracks)
    for _, tr in ipairs(facts.selected_tracks) do
      lines[#lines + 1] = str_format("- %d. %s", tr.index or 0,
        tr.name or "(unnamed)")
    end
  end
  lines[#lines + 1] = CTX.selected_items(facts.proj, {
    human = true,
    include_names = true,
  })
  return tbl_concat(lines, "\n")
end

function CTX.local_read_track_list(proj)
  local facts = type(proj) == "table" and proj.track_count and proj
    or CTX.local_project_facts(proj)
  if facts.track_count == 0 then return "Tracks: none" end
  local lines = { str_format("Tracks: %d", facts.track_count) }
  local limit = math_min(facts.track_count, 40)
  for i = 0, limit - 1 do
    local tr = reaper.GetTrack(facts.proj, i)
    if tr then
      local _, name = R_GetTrackName(tr)
      lines[#lines + 1] = str_format("%d. %s", i + 1,
        name ~= "" and name or "(unnamed)")
    end
  end
  if facts.track_count > limit then
    lines[#lines + 1] = str_format("(+%d more)", facts.track_count - limit)
  end
  return tbl_concat(lines, "\n")
end

function CTX.track_folders(proj)
  local count = R_CountTracks(proj)
  if count == 0 then return "Track folders: none" end
  local rows = {}
  local depth = 0
  local has_folder = false
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr then
      local _, name = R_GetTrackName(tr)
      local delta = math_floor(R_GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
      if depth > 0 or delta ~= 0 then has_folder = true end
      rows[#rows + 1] = str_format("%d|%d|%s|%d",
        i + 1, depth, _scrub_pipes(name ~= "" and name or "(unnamed)"), delta)
      depth = math_max(0, depth + delta)
    end
  end
  if not has_folder then return "Track folders: none" end
  table.insert(rows, 1,
    str_format("Track folders (N=%d) [idx|depth|name|folder_delta]:", count))
  return tbl_concat(rows, "\n")
end

-- Resolve one named/indexed/selected track mention from natural language. Returns
-- nil plus an ambiguity/missing marker when local answering would be unsafe.
function CTX.local_track_named_in_text(facts, lt)
  if type(facts) ~= "table" or not facts.track_count then
    return nil
  end
  local text_key = " " .. tostring(lt or ""):gsub("[^%w]+", " ") .. " "
  local exact_matches = {}
  for i = 0, facts.track_count - 1 do
    local tr = reaper.GetTrack(facts.proj, i)
    if tr then
      local _, name = R_GetTrackName(tr)
      name = tostring(name or "")
      local name_key = name:lower():gsub("[^%w]+", " ")
      name_key = name_key:gsub("^%s+", ""):gsub("%s+$", "")
      if name_key ~= "" and text_key:find(" " .. name_key .. " ", 1, true) then
        exact_matches[#exact_matches + 1] = {
          track = tr,
          index = i + 1,
          name = name ~= "" and name or "(unnamed)",
        }
      end
    end
  end
  if #exact_matches == 1 then
    local m = exact_matches[1]
    return m.track, m.index, m.name, false
  end
  if #exact_matches > 1 then
    local names = {}
    for _, m in ipairs(exact_matches) do names[#names + 1] = m.name end
    return nil, nil, nil, true, names
  end

  local stop = {
    a = true, an = true, ["and"] = true, are = true, armed = true, count = true,
    current = true,
    effect = true, effects = true, fader = true, faders = true, from = true,
    how = true, ["is"] = true, item = true, items = true, list = true,
    main = true, many = true, master = true, media = true, mute = true,
    muted = true, of = true, on = true, output = true, pan = true,
    pans = true, plugin = true, plugins = true, project = true,
    properties = true, property = true, record = true, send = true,
    sends = true, session = true, show = true, solo = true, soloed = true,
    selected = true, that = true, the = true, this = true, to = true, track = true,
    tracks = true, volume = true, volumes = true, what = true,
    whats = true, which = true,
  }
  local query = {}
  for word in tostring(lt or ""):lower():gmatch("%w+") do
    if #word >= 3 and not stop[word] then query[word] = true end
  end

  local best_score, matches = 0, {}
  for i = 0, facts.track_count - 1 do
    local tr = reaper.GetTrack(facts.proj, i)
    if tr then
      local _, name = R_GetTrackName(tr)
      name = tostring(name or "")
      local score = 0
      for token in name:lower():gsub("[^%w]+", " "):gmatch("%w+") do
        if query[token] then score = score + 1 end
      end
      if score > best_score then
        best_score = score
        matches = {
          {
            track = tr,
            index = i + 1,
            name = name ~= "" and name or "(unnamed)",
          },
        }
      elseif score > 0 and score == best_score then
        matches[#matches + 1] = {
          track = tr,
          index = i + 1,
          name = name ~= "" and name or "(unnamed)",
        }
      end
    end
  end
  if best_score <= 0 or #matches == 0 then return nil, nil, nil, false end
  if #matches == 1 then
    local m = matches[1]
    return m.track, m.index, m.name, false
  end
  local names = {}
  for _, m in ipairs(matches) do names[#names + 1] = m.name end
  return nil, nil, nil, true, names
end

function CTX.local_track_ambiguity(prefix, names)
  if type(names) ~= "table" or #names == 0 then
    return tostring(prefix or "Track target") .. ": track name is ambiguous"
  end
  local lines = { tostring(prefix or "Track target") .. ": track name is ambiguous" }
  for i, name in ipairs(names) do
    lines[#lines + 1] = str_format("%d. %s", i, tostring(name or "(unnamed)"))
  end
  return tbl_concat(lines, "\n")
end

function CTX.local_track_index_in_text(facts, lt)
  if type(facts) ~= "table" or not facts.track_count then
    return nil
  end
  local text = tostring(lt or ""):lower()
  local raw = text:match("%f[%w]track%s+index%s*#?%s*(%d+)%f[%W]")
    or text:match("%f[%w]track%s*#%s*(%d+)%f[%W]")
    or text:match("%f[%w]track%s+(%d+)%f[%W]")
  local idx = tonumber(raw)
  if not idx or idx % 1 ~= 0 or idx < 1 then return nil end
  local tr = reaper.GetTrack(facts.proj, idx - 1)
  if not tr then return nil, nil, nil, idx end
  local _, name = R_GetTrackName(tr)
  return tr, idx, name ~= "" and name or "(unnamed)", nil
end

function CTX.local_selected_track_index_in_text(facts, lt)
  if type(facts) ~= "table" or not facts.track_count then
    return nil
  end
  local text = tostring(lt or ""):lower()
  local idx = tonumber(
    text:match("%f[%d](%d+)%s*%a*%s+selected%s+track%f[%W]")
      or text:match("%f[%w]selected%s+track%s*#?%s*(%d+)%f[%W]")
      or text:match("%f[%w]selected%s+index%s*#?%s*(%d+)%f[%W]"))
  if not idx then
    local ordinals = {
      first = 1, second = 2, third = 3, fourth = 4, fifth = 5,
      sixth = 6, seventh = 7, eighth = 8, ninth = 9, tenth = 10,
    }
    for word, n in pairs(ordinals) do
      if text:find("%f[%a]" .. word .. "%s+selected%s+track%f[%W]") then
        idx = n
        break
      end
    end
  end
  if not idx or idx % 1 ~= 0 or idx < 1 then return nil end
  local tr = reaper.GetSelectedTrack(facts.proj, idx - 1)
  if not tr then return nil, nil, nil, idx end
  local project_idx =
    math_floor((R_GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) + 0.5)
  local _, name = R_GetTrackName(tr)
  return tr, project_idx, name ~= "" and name or "(unnamed)", nil
end

function CTX.local_singular_selected_track_in_text(facts, lt, prefix, include_selected)
  if type(facts) ~= "table" or not facts.track_count then
    return nil
  end
  local text = tostring(lt or ""):lower()
  if text:find("%f[%w]selected%s+tracks%f[%W]")
      or text:find("%f[%w]current%s+tracks%f[%W]")
      or text:find("%f[%w]these%s+tracks%f[%W]")
      or text:find("%f[%w]those%s+tracks%f[%W]") then
    return nil
  end
  include_selected = include_selected ~= false
  local refers_to_singular =
       (include_selected and text:find("%f[%w]selected%s+track%f[%W]") ~= nil)
    or text:find("%f[%w]current%s+track%f[%W]") ~= nil
    or text:find("%f[%w]this%s+track%f[%W]") ~= nil
    or text:find("%f[%w]that%s+track%f[%W]") ~= nil
  if not refers_to_singular then return nil end
  if #facts.selected_tracks == 1 then
    local tr = reaper.GetSelectedTrack(facts.proj, 0)
    if tr then
      local project_idx =
        math_floor((R_GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) + 0.5)
      local _, name = R_GetTrackName(tr)
      return tr, project_idx, name ~= "" and name or "(unnamed)", nil
    end
    return nil, nil, nil, tostring(prefix or "Track target")
      .. ": selected track not found"
  end
  if #facts.selected_tracks > 1 then
    local lines = {
      tostring(prefix or "Track target") .. ": selected track is ambiguous",
    }
    for i, tr in ipairs(facts.selected_tracks) do
      lines[#lines + 1] = str_format("%d. %s", i, tr.name or "(unnamed)")
    end
    return nil, nil, nil, tbl_concat(lines, "\n")
  end
  return nil, nil, nil, tostring(prefix or "Track target")
    .. ": selected track not found"
end

function CTX.local_route_endpoint_in_text(facts, text)
  if type(facts) ~= "table" or not facts.track_count then return nil end
  local lt = tostring(text or ""):lower()
  local selected_track, selected_index, selected_name, missing_selected =
    CTX.local_selected_track_index_in_text(facts, lt)
  if missing_selected then
    return nil, nil, nil, "Route: selected track "
      .. tostring(missing_selected) .. " not found"
  end
  if selected_track then return selected_track, selected_index, selected_name end

  selected_track, selected_index, selected_name, missing_selected =
    CTX.local_singular_selected_track_in_text(facts, lt, "Route")
  if missing_selected then return nil, nil, nil, missing_selected end
  if selected_track then return selected_track, selected_index, selected_name end

  local track, index, name, missing_index = CTX.local_track_index_in_text(facts, lt)
  if missing_index then
    return nil, nil, nil, "Route: track " .. tostring(missing_index) .. " not found"
  end
  if track then return track, index, name end

  local ambiguous, ambiguous_names = false, nil
  track, index, name, ambiguous, ambiguous_names =
    CTX.local_track_named_in_text(facts, lt)
  if ambiguous then
    return nil, nil, nil, CTX.local_track_ambiguity("Route", ambiguous_names)
  end
  return track, index, name
end

function CTX.local_route_fragment_for_match(text)
  local s = tostring(text or "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("[%.%?%!]+$", "")
  -- Multi-part readbacks often say "what send level goes to X, and what track
  -- is selected?". Keep only the route endpoint before the next question.
  s = s:gsub("%s*,%s*and%s+what.+$", "")
  s = s:gsub("%s+and%s+what.+$", "")
  s = s:gsub("%s*,%s*what.+$", "")
  s = s:gsub("%s*,%s*whether.+$", "")
  s = s:gsub("%s+whether.+$", "")
  s = s:gsub("%s*,%s*which.+$", "")
  s = s:gsub("^the%s+", "")
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

function CTX.local_read_project_summary(proj)
  local facts = type(proj) == "table" and proj.track_count and proj
    or CTX.local_project_facts(proj)
  local lines = {
    facts.project_name and ("Project: " .. facts.project_name) or "Project: unsaved",
    CTX.tempo(facts.proj),
    str_format("Tracks: %d", facts.track_count),
    str_format("Selected tracks: %d", #facts.selected_tracks),
    str_format("Media items: %d", facts.item_count or 0),
    str_format("Track FX: %d across %d track%s",
      facts.fx_count or 0, facts.tracks_with_fx or 0,
      (facts.tracks_with_fx or 0) == 1 and "" or "s"),
    str_format("Markers: %d | Regions: %d", facts.marker_count, facts.region_count),
  }
  return tbl_concat(lines, "\n")
end

function CTX.local_read_session_overview(proj)
  local facts = type(proj) == "table" and proj.track_count and proj
    or CTX.local_project_facts(proj)
  local lines = {
    "Current REAPER session:",
    "- " .. (facts.project_name and ("Project: " .. facts.project_name)
      or "Project: unsaved"),
    "- " .. CTX.tempo(facts.proj),
    str_format("- Tracks: %d (%d selected)", facts.track_count,
      #facts.selected_tracks),
    str_format("- Media items: %d; track FX: %d across %d track%s",
      facts.item_count or 0, facts.fx_count or 0, facts.tracks_with_fx or 0,
      (facts.tracks_with_fx or 0) == 1 and "" or "s"),
    str_format("- Markers: %d; regions: %d", facts.marker_count,
      facts.region_count),
  }
  if #facts.selected_tracks > 0 then
    local names = {}
    for i = 1, math_min(#facts.selected_tracks, 4) do
      local tr = facts.selected_tracks[i]
      names[#names + 1] = str_format("%d. %s", tr.index or 0,
        tr.name or "(unnamed)")
    end
    if #facts.selected_tracks > 4 then
      names[#names + 1] = "..."
    end
    lines[#lines + 1] = "- Selected: " .. tbl_concat(names, ", ")
  end
  lines[#lines + 1] =
    "- I can use this to target the right tracks/items, inspect routing or FX, "
    .. "and avoid guessing when you ask for edits."
  return tbl_concat(lines, "\n")
end

-- Local plugin inventory answer for "do I have X installed?" style questions.
-- Extension checks are handled above, and recommendation/version questions are
-- intentionally left for the provider.
function CTX.local_installed_plugin_answer(user_text)
  local raw = tostring(user_text or "")
  local lt = raw:lower()
  local mentions_installed = lt:find("installed", 1, true) ~= nil
  local have_plugin_query = lt:find("%f[%w]have%f[%W]") ~= nil
    and (lt:find("plugin", 1, true) ~= nil
      or lt:find("%f[%w]fx%f[%W]") ~= nil
      or lt:find("effect", 1, true) ~= nil)
  local available_plugin_query = lt:find("%f[%w]available%f[%W]") ~= nil
    and (lt:find("plugin", 1, true) ~= nil
      or lt:find("%f[%w]fx%f[%W]") ~= nil
      or lt:find("effect", 1, true) ~= nil)
  if not mentions_installed and not have_plugin_query and not available_plugin_query then
    return nil
  end
  local term =
    raw:match("^[Dd]o%s+I%s+have%s+(.+)%s+installed%??%s*$")
    or raw:match("^[Dd]o%s+I%s+have%s+(.+)%??%s*$")
    or raw:match("^[Ii]s%s+the%s+(.+)%s+plugin%s+installed%??%s*$")
    or raw:match("^[Ii]s%s+(.+)%s+installed%??%s*$")
    or raw:match("^[Ii]s%s+(.+)%s+available%??%s*$")
  term = tostring(term or ""):gsub("^%s+", ""):gsub("%s+$", "")
  term = term:gsub("%?+$", ""):gsub("%s+$", "")
  term = term:gsub("^the%s+", ""):gsub("%s+plugin$", "")
  local term_l = term:lower()
  if term == ""
     or term_l == "plugin"
     or term_l == "plugins"
     or term_l == "fx"
     or term_l == "effects"
     or term_l == "any plugins"
     or term_l == "any effects" then
    return nil
  end
  local term_compact = term_l:gsub("[_%-%s]+", "")
  if term_compact == "reaimgui"
      or term_compact == "jsreascriptapi"
      or term_l == "sws"
      or term_l == "sws extension" then
    return nil
  end
  if type(CTX.populate_installed_fx) ~= "function"
     or not CTX.populate_installed_fx() then
    return "Installed plugin search: unavailable in this REAPER version."
  end
  local matches = {}
  for _, name in ipairs(CTX._installed_fx_list or {}) do
    if CTX.fx_name_matches(name, { term }) then matches[#matches + 1] = name end
  end
  if #matches == 0 then
    return 'Installed plugin search: no matches for "' .. term .. '".'
  end
  local lines = {
    #matches == 1
      and ('Installed plugin: yes, "' .. matches[1] .. '" is available.')
      or ('Installed plugin: found ' .. tostring(#matches)
          .. ' matches for "' .. term .. '":')
  }
  if #matches > 1 then
    for i = 1, math_min(#matches, 8) do
      lines[#lines + 1] = "- " .. matches[i]
    end
    if #matches > 8 then
      lines[#lines + 1] = "... " .. tostring(#matches - 8) .. " more"
    end
  end
  return tbl_concat(lines, "\n")
end

-- Local overview for broad "what kinds of JSFX can you build?" questions. Actual
-- JSFX generation requests return nil so the provider receives the prompt.
function CTX.local_jsfx_capability_overview_answer(user_text)
  local raw = tostring(user_text or "")
  local lt = raw:lower()
  lt = lt:gsub("^%s*no%s+code%s+this%s+time:%s*", "")
  if lt:match("^%s*$") or lt:find("\n", 1, true) then return nil end
  if #raw > 520 then return nil end

  local mentions_jsfx = lt:find("%f[%w]jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]eel2?%f[%W]") ~= nil
    or lt:find("%f[%w]custom%s+audio%s+plugins?%f[%W]") ~= nil
    or lt:find("%f[%w]custom%s+plugins?%f[%W]") ~= nil
  if not mentions_jsfx then return nil end

  local overview_cue =
       lt:find("what%s+kinds?", 1, false) ~= nil
    or lt:find("what%s+types?", 1, false) ~= nil
    or lt:find("which%s+kinds?", 1, false) ~= nil
    or lt:find("which%s+types?", 1, false) ~= nil
    or lt:find("%f[%w]overview%f[%W]") ~= nil
    or lt:find("%f[%w]summari[sz]e%f[%W]") ~= nil
    or lt:find("how%s+the%s+process%s+works", 1, false) ~= nil
    or lt:find("how%s+it%s+works", 1, false) ~= nil
  if not overview_cue then return nil end

  local authoring_start =
       lt:find("^%s*please%s+write%f[%W]") ~= nil
    or lt:find("^%s*please%s+build%f[%W]") ~= nil
    or lt:find("^%s*please%s+make%f[%W]") ~= nil
    or lt:find("^%s*please%s+create%f[%W]") ~= nil
    or lt:find("^%s*please%s+generate%f[%W]") ~= nil
    or lt:find("^%s*write%f[%W]") ~= nil
    or lt:find("^%s*build%f[%W]") ~= nil
    or lt:find("^%s*make%f[%W]") ~= nil
    or lt:find("^%s*create%f[%W]") ~= nil
    or lt:find("^%s*generate%f[%W]") ~= nil
  local authoring_request =
       lt:find("%f[%w]write%s+me%s+a%f[%W]") ~= nil
    or lt:find("%f[%w]build%s+me%s+a%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+me%s+a%f[%W]") ~= nil
    or lt:find("%f[%w]create%s+me%s+a%f[%W]") ~= nil
    or lt:find("%f[%w]generate%s+me%s+a%f[%W]") ~= nil
    or lt:find("%f[%w]write%s+a%s+jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]build%s+a%s+jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+a%s+jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]create%s+a%s+jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]generate%s+a%s+jsfx%f[%W]") ~= nil
    or lt:find("%f[%w]code%s+a%s+jsfx%f[%W]") ~= nil
  if authoring_start or authoring_request then return nil end

  return "I can build JSFX for EQ and filters, dynamics, saturation, "
    .. "delay/reverb/modulation, pitch and time effects, meters, gain/routing "
    .. "utilities, and creative sound-design tools.\n\n"
    .. "Tell me the sound and controls you want; I generate the JSFX code, "
    .. "ReaAssist saves it as an effect, then adds it to the selected track or "
    .. "gives you the exact load step. For risky DSP, I include safety limits "
    .. "and ask a quick follow-up if the design is underspecified."
end

-- Main no-network factual-answer dispatcher. Each branch below either returns a
-- complete user-visible answer or nil to continue into the normal send path.
function CTX.local_read_answer(user_text, proj)
  local raw = tostring(user_text or "")
  local lt = raw:lower()
  lt = lt:gsub("^%s*no%s+code%s+this%s+time:%s*", "")
  if lt:match("^%s*$") then return nil end
  if lt:find("\n", 1, true) then return nil end
  local sound_classification =
    (lt:find("%f[%w]sound%f[%W]") ~= nil
      or lt:find("%f[%w]audio%f[%W]") ~= nil
      or lt:find("%f[%w]waveform%f[%W]") ~= nil
      or lt:find("sound wave", 1, true) ~= nil)
    and (lt:find("%f[%w]classify%w*%f[%W]") ~= nil
      or lt:find("%f[%w]identify%w*%f[%W]") ~= nil
      or lt:find("%f[%w]kind%f[%W]") ~= nil
      or lt:find("%f[%w]type%f[%W]") ~= nil
      or lt:find("%f[%w]category%f[%W]") ~= nil
      or lt:find("%f[%w]ucs%f[%W]") ~= nil
      or lt:find("what is this", 1, true) ~= nil
      or lt:find("what's this", 1, true) ~= nil)
  local forbids_metadata =
    lt:find("%f[%w]not%s+the%s+name", 1, false) ~= nil
    or lt:find("%f[%w]not%s+the%s+names", 1, false) ~= nil
    or lt:find("%f[%w]not%s+.*%f[%w]track", 1, false) ~= nil
    or lt:find("%f[%w]not%s+.*%f[%w]item", 1, false) ~= nil
    or lt:find("%f[%w]not%s+.*%f[%w]project", 1, false) ~= nil
    or lt:find("%f[%w]only%s+on%s+the%s+sound", 1, false) ~= nil
    or lt:find("%f[%w]only%s+on%s+the%s+audio", 1, false) ~= nil
    or lt:find("%f[%w]only%s+on%s+the%s+waveform", 1, false) ~= nil
    or lt:find("based only on the sound", 1, true) ~= nil
    or lt:find("based only on the audio", 1, true) ~= nil
    or lt:find("based only on the waveform", 1, true) ~= nil
    or lt:find("based only on the sound wave", 1, true) ~= nil
  if sound_classification or forbids_metadata then return nil end
  local session_overview =
       (lt:find("what information", 1, true) ~= nil
        and (lt:find("current reaper session", 1, true) ~= nil
          or lt:find("my reaper session", 1, true) ~= nil
          or lt:find("current session", 1, true) ~= nil))
    or (lt:find("what can you see", 1, true) ~= nil
        and (lt:find("reaper session", 1, true) ~= nil
          or lt:find("current session", 1, true) ~= nil
          or lt:find("project", 1, true) ~= nil))
    or (lt:find("what do you see", 1, true) ~= nil
        and (lt:find("reaper session", 1, true) ~= nil
          or lt:find("current session", 1, true) ~= nil
          or lt:find("project", 1, true) ~= nil))
  if #raw > 240 and not session_overview then return nil end
  if lt:find("^%s*how%s+do%s+i")
      or lt:find("^%s*how%s+can%s+i")
      or lt:find("^%s*show%s+me%s+how")
      or lt:find("^%s*show%s+how")
      or lt:find("^%s*can%s+you%s+explain")
      or lt:find("^%s*explain%s+") then
    return nil
  end
  if lt:find("%f[%w]command%f[%W]") then
    return nil
  end
  if lt:find("%f[%w]should%f[%W]")
      or lt:find("shouldn't", 1, true)
      or lt:find("shouldnt", 1, true)
      or lt:find("shouldn\226\128\153t", 1, true)
      or lt:find("%f[%w]recommend%w*%f[%W]")
      or lt:find("%f[%w]best%f[%W]") then
    return nil
  end
  if (lt:find("plugins", 1, true) and lt:find("installed", 1, true))
      or (lt:find("effects", 1, true) and lt:find("installed", 1, true))
      or lt:find("installed fx", 1, true)
      or lt:find("fx installed", 1, true)
      or lt:find("plugin inventory", 1, true)
      or lt:find("fx inventory", 1, true) then
    return "Installed plugin inventory: full installed-plugin lists are not "
      .. "available from the current session. Ask me to check a specific "
      .. "plugin name."
  end
  local installed_plugin_answer = CTX.local_installed_plugin_answer(raw)
  if installed_plugin_answer then return installed_plugin_answer end
  local read_start =
       lt:find("^%s*what") ~= nil
    or lt:find("^%s*what's") ~= nil
    or lt:find("^%s*whats") ~= nil
    or lt:find("^%s*which") ~= nil
    or lt:find("^%s*do%s+") ~= nil
    or lt:find("^%s*does%s+") ~= nil
    or lt:find("^%s*is%s+") ~= nil
    or lt:find("^%s*are%s+") ~= nil
    or lt:find("^%s*how%s+many") ~= nil
    or lt:find("^%s*how%s+long") ~= nil
    or lt:find("^%s*tell%s+me%s+") ~= nil
    or lt:find("^%s*list") ~= nil
    or lt:find("^%s*show") ~= nil
    or lt:find("^%s*where%s+is%s+") ~= nil
    or lt:find("^%s*summarize") ~= nil
    or lt:find("^%s*summary") ~= nil
    or lt:find("^%s*project%s+summary") ~= nil
    or lt:find("^%s*session%s+summary") ~= nil
  if not read_start then return nil end
  local incoming_send_read =
    (lt:find("^%s*what") ~= nil
      or lt:find("^%s*which") ~= nil
      or lt:find("^%s*list") ~= nil
      or lt:find("^%s*show") ~= nil
      or lt:find("^%s*tell%s+me%s+") ~= nil
      or lt:find("^%s*are%s+") ~= nil)
    and (lt:find("tracks send to", 1, true) ~= nil
      or lt:find("tracks send into", 1, true) ~= nil
      or lt:find("tracks route to", 1, true) ~= nil
      or lt:find("tracks route into", 1, true) ~= nil
      or lt:find("tracks routed to", 1, true) ~= nil
      or lt:find("tracks routed into", 1, true) ~= nil
      or lt:find("tracks are routed to", 1, true) ~= nil
      or lt:find("tracks are routed into", 1, true) ~= nil
      or lt:find("tracks sending to", 1, true) ~= nil
      or lt:find("tracks sending into", 1, true) ~= nil
      or lt:find("tracks are sending to", 1, true) ~= nil
      or lt:find("tracks are sending into", 1, true) ~= nil
      or lt:find("tracks feed", 1, true) ~= nil
      or lt:find("tracks feeding", 1, true) ~= nil)
  local receive_from_read =
    (lt:find("^%s*what") ~= nil
      or lt:find("^%s*which") ~= nil
      or lt:find("^%s*list") ~= nil
      or lt:find("^%s*show") ~= nil)
    and (lt:find("tracks receive from", 1, true) ~= nil
      or lt:find("tracks receiving from", 1, true) ~= nil
      or lt:find("tracks are receiving from", 1, true) ~= nil)
  local send_level_read =
    read_start
    and (lt:find("send level", 1, true) ~= nil
      or lt:find("send volume", 1, true) ~= nil
      or lt:find("send gain", 1, true) ~= nil
      or lt:find("level of the send", 1, true) ~= nil
      or lt:find("volume of the send", 1, true) ~= nil
      or lt:find("gain of the send", 1, true) ~= nil)
  local route_yesno_read =
    (lt:find("^%s*does%s+") ~= nil
      or lt:find("^%s*is%s+") ~= nil)
    and (lt:find("%f[%w]send%s+to%f[%W]") ~= nil
      or lt:find("%f[%w]send%s+into%f[%W]") ~= nil
      or lt:find("%f[%w]sending%s+to%f[%W]") ~= nil
      or lt:find("%f[%w]sending%s+into%f[%W]") ~= nil
      or lt:find("%f[%w]routed%s+to%f[%W]") ~= nil
      or lt:find("%f[%w]routed%s+into%f[%W]") ~= nil
      or lt:find("%f[%w]receive%s+from%f[%W]") ~= nil
      or lt:find("%f[%w]receiving%s+from%f[%W]") ~= nil)
  local mutating =
       lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]delete%f[%W]") ~= nil
    or lt:find("%f[%w]remove%f[%W]") ~= nil
    or (lt:find("%f[%w]route%f[%W]") ~= nil
      and not incoming_send_read and not route_yesno_read)
    or (lt:find("%f[%w]routed%f[%W]") ~= nil
      and not incoming_send_read and not route_yesno_read)
    or (lt:find("%f[%w]routing%f[%W]") ~= nil
      and not incoming_send_read and not route_yesno_read)
    or (lt:find("%f[%w]send%f[%W]") ~= nil
      and not incoming_send_read and not send_level_read and not route_yesno_read)
    or (lt:find("%f[%w]sending%f[%W]") ~= nil
      and not incoming_send_read and not route_yesno_read)
    or lt:find("%f[%w]set%f[%W]") ~= nil
    or lt:find("%f[%w]change%f[%W]") ~= nil
    or lt:find("%f[%w]move%f[%W]") ~= nil
  if mutating then return nil end

  proj = proj or reaper.EnumProjects(-1)
  local facts = CTX.local_project_facts(proj)
  if session_overview then
    return CTX.local_read_session_overview(facts)
  end
  local selected_track_phrase = lt:find("selected track", 1, true) ~= nil
    or lt:find("selected tracks", 1, true) ~= nil
  if lt:find("what is selected", 1, true)
      or lt:find("what's selected", 1, true)
      or lt:find("whats selected", 1, true)
      or lt:find("current selection", 1, true)
      or lt:find("selection status", 1, true)
      or lt:find("^%s*is%s+anything%s+selected") then
    return CTX.local_read_selection_summary(proj, facts)
  end
  if lt:find("project summary", 1, true)
      or lt:find("session summary", 1, true)
      or lt:find("project status", 1, true)
      or lt:find("session status", 1, true)
      or lt:find("^%s*summarize")
      or lt:find("^%s*summary") then
    return CTX.local_read_project_summary(facts)
  end
  if lt:find("project name", 1, true)
      or lt:find("project file", 1, true)
      or lt:find("session name", 1, true)
      or lt:find("what project", 1, true)
      or lt:find("which project", 1, true) then
    return facts.project_name and ("Project: " .. facts.project_name)
      or "Project: unsaved"
  end
  if lt:find("reaassist version", 1, true)
      or lt:find("version of reaassist", 1, true) then
    return CTX.reaassist_version()
  end
  if lt:find("reaper version", 1, true)
      or lt:find("version of reaper", 1, true) then
    return CTX.reaper_version()
  end
  local extension_answer = CTX.extension_status(raw)
  if extension_answer then return extension_answer end
  local ai_status = CTX.ai_selection_status(raw)
  if ai_status then return ai_status end
  local settings_status = CTX.reaassist_settings_status(raw)
  if settings_status then return settings_status end
  local diagnostics_status = CTX.diagnostics_status(raw)
  if diagnostics_status then return diagnostics_status end
  if lt:find("%f[%w]tempo%f[%W]")
      or lt:find("%f[%w]bpm%f[%W]")
      or lt:find("song speed", 1, true)
      or lt:find("time signature", 1, true) then
    return CTX.tempo(proj)
  end
  if lt:find("time selection", 1, true) then
    return CTX.time_selection(proj, {
      include_length = lt:find("^%s*how%s+long", 1, false) ~= nil
        or lt:find("%f[%w]duration%f[%W]") ~= nil
        or lt:find("%f[%w]length%f[%W]") ~= nil,
    })
  end
  if lt:find("project length", 1, true)
      or lt:find("project duration", 1, true)
      or lt:find("session length", 1, true)
      or lt:find("session duration", 1, true)
      or lt:find("^%s*how%s+long%s+is%s+this%s+project")
      or lt:find("^%s*how%s+long%s+is%s+the%s+project")
      or lt:find("^%s*how%s+long%s+is%s+this%s+session")
      or lt:find("^%s*how%s+long%s+is%s+the%s+session")
      or lt:find("^%s*how%s+long%s+is%s+this%s+song")
      or lt:find("^%s*how%s+long%s+is%s+the%s+song") then
    return CTX.project_length(proj)
  end
  if lt:find("edit cursor", 1, true)
      or lt:find("cursor position", 1, true)
      or lt:find("play cursor", 1, true)
      or lt:find("playhead", 1, true)
      or lt:find("play head", 1, true) then
    return CTX.cursor(proj)
  end
  if lt:find("sample rate", 1, true) then
    return CTX.sample_rate(proj)
  end
  if lt:find("transport", 1, true)
      or lt:find("play state", 1, true)
      or lt:find("playback state", 1, true) then
    return CTX.play_state(proj)
  end
  if lt:find("loop points", 1, true)
      or lt:find("loop range", 1, true)
      or lt:find("loop status", 1, true)
      or lt:find("loop length", 1, true)
      or lt:find("loop duration", 1, true)
      or lt:find("length of the loop", 1, true)
      or lt:find("duration of the loop", 1, true)
      or lt:find("^%s*how%s+long%s+is%s+the%s+loop") then
    return CTX.loop(proj, {
      include_length = lt:find("^%s*how%s+long", 1, false) ~= nil
        or lt:find("%f[%w]duration%f[%W]") ~= nil
        or lt:find("%f[%w]length%f[%W]") ~= nil,
    })
  end
  if lt:find("dynamic split", 1, true)
      or lt:find("dynamic splitting", 1, true) then
    return CTX.dynamic_split_settings()
  end
  local master_context = lt:find("%f[%w]master%f[%W]") ~= nil
    and lt:find("master output", 1, true) == nil
    and lt:find("master send", 1, true) == nil
    and lt:find("master/parent", 1, true) == nil
  if master_context
      and (lt:find("%f[%w]fx%f[%W]") ~= nil
      or lt:find("%f[%w]plugin%f[%W]") ~= nil
      or lt:find("%f[%w]plugins%f[%W]") ~= nil
      or lt:find("%f[%w]effect%f[%W]") ~= nil
      or lt:find("%f[%w]effects%f[%W]") ~= nil
      or lt:find("on the master", 1, true) ~= nil) then
    return CTX.master_fx(proj)
  end
  if master_context
      and (lt:find("%f[%w]volume%f[%W]") ~= nil
      or lt:find("%f[%w]fader%f[%W]") ~= nil
      or lt:find("%f[%w]pan%f[%W]") ~= nil
      or lt:find("%f[%w]mute%f[%W]") ~= nil
      or lt:find("%f[%w]muted%f[%W]") ~= nil
      or lt:find("%f[%w]solo%f[%W]") ~= nil
      or lt:find("%f[%w]soloed%f[%W]") ~= nil
      or lt:find("%f[%w]properties%f[%W]") ~= nil
      or lt:find("%f[%w]status%f[%W]") ~= nil) then
    return CTX.master_properties(proj)
  end
  local master_output_query = CTX.local_master_output_presence_query(lt)
  if master_output_query then
    local source_track, _, source_name, target_error =
      CTX.local_track_target_in_text(
        facts, master_output_query, "Master output", true)
    if target_error then return target_error end
    if source_track then
      return CTX.track_master_output_answer(source_track, source_name)
    end
  end
  local send_presence_text = lt:gsub("[%.%?%!]+$", "")
  local send_presence_target =
       send_presence_text:match("^%s*does%s+(.+)%s+have%s+any%s+sends%s*$")
    or send_presence_text:match("^%s*does%s+(.+)%s+have%s+sends%s*$")
    or send_presence_text:match("^%s*do%s+(.+)%s+have%s+any%s+sends%s*$")
    or send_presence_text:match("^%s*do%s+(.+)%s+have%s+sends%s*$")
    or send_presence_text:match("^%s*is%s+(.+)%s+sending%s+to%s+any%s+other%s+tracks%s*$")
    or send_presence_text:match("^%s*is%s+(.+)%s+sending%s+to%s+any%s+other%s+track%s*$")
    or send_presence_text:match("^%s*does%s+(.+)%s+send%s+to%s+any%s+other%s+tracks%s*$")
    or send_presence_text:match("^%s*does%s+(.+)%s+send%s+to%s+any%s+other%s+track%s*$")
  if send_presence_target then
    local source_track, source_index, source_name, target_error =
      CTX.local_any_track_target_in_text(facts, send_presence_target, "Sends")
    if target_error then return target_error end
    if source_track then
      return CTX.track_send_presence_answer(
        proj, source_track, source_index, source_name)
    end
  end
  if route_yesno_read then
    local source_fragment, dest_fragment =
      lt:match("^%s*does%s+(.+)%s+send%s+to%s+(.+)%??%s*$")
    if not source_fragment then
      source_fragment, dest_fragment =
        lt:match("^%s*does%s+(.+)%s+send%s+into%s+(.+)%??%s*$")
    end
    if not source_fragment then
      source_fragment, dest_fragment =
        lt:match("^%s*is%s+(.+)%s+sending%s+to%s+(.+)%??%s*$")
    end
    if not source_fragment then
      source_fragment, dest_fragment =
        lt:match("^%s*is%s+(.+)%s+sending%s+into%s+(.+)%??%s*$")
    end
    if not source_fragment then
      source_fragment, dest_fragment =
        lt:match("^%s*is%s+(.+)%s+routed%s+to%s+(.+)%??%s*$")
    end
    if not source_fragment then
      source_fragment, dest_fragment =
        lt:match("^%s*is%s+(.+)%s+routed%s+into%s+(.+)%??%s*$")
    end
    if not source_fragment then
      dest_fragment, source_fragment =
        lt:match("^%s*does%s+(.+)%s+receive%s+from%s+(.+)%??%s*$")
    end
    if not source_fragment then
      dest_fragment, source_fragment =
        lt:match("^%s*is%s+(.+)%s+receiving%s+from%s+(.+)%??%s*$")
    end
    if not source_fragment or not dest_fragment then return nil end
    local source_track, source_index, source_name
    local route_error
    source_track, source_index, source_name, route_error =
      CTX.local_route_endpoint_in_text(facts, source_fragment)
    if route_error then return route_error end
    local dest_track, dest_index, dest_name
    dest_track, dest_index, dest_name, route_error =
      CTX.local_route_endpoint_in_text(facts, dest_fragment)
    if route_error then return route_error end
    if not source_track or not dest_track then return nil end
    return CTX.send_route_answer(proj, source_track, source_name,
      dest_track, dest_name)
  end
  if lt:find("tracks have no sends", 1, true)
      or lt:find("tracks with no sends", 1, true)
      or lt:find("tracks without sends", 1, true)
      or lt:find("tracks dont have sends", 1, true)
      or lt:find("tracks don't have sends", 1, true) then
    return CTX.tracks_without_sends(proj, {
      selected_only = selected_track_phrase,
    })
  end
  if lt:find("%f[%w]sends%f[%W]")
      or incoming_send_read or receive_from_read or send_level_read then
    local dest_fragment =
         lt:match("%f[%w]go%s+to%s+(.+)$")
      or lt:match("%f[%w]goes%s+to%s+(.+)$")
      or lt:match("%f[%w]going%s+to%s+(.+)$")
      or lt:match("%f[%w]send%s+to%s+(.+)$")
      or lt:match("%f[%w]send%s+into%s+(.+)$")
      or lt:match("%f[%w]route%s+to%s+(.+)$")
      or lt:match("%f[%w]routed%s+to%s+(.+)$")
      or lt:match("%f[%w]route%s+into%s+(.+)$")
      or lt:match("%f[%w]feed%s+into%s+(.+)$")
      or lt:match("%f[%w]feeding%s+into%s+(.+)$")
      or lt:match("%f[%w]feed%s+(.+)$")
      or lt:match("%f[%w]feeding%s+(.+)$")
      or lt:match("%f[%w]to%s+(.+)$")
      or lt:match("%f[%w]into%s+(.+)$")
    local source_fragment = lt:match("%f[%w]from%s+(.+)%s+to%s+")
      or lt:match("%f[%w]from%s+(.+)%s+into%s+")
      or lt:match("%f[%w]from%s+(.+)$")
    dest_fragment = CTX.local_route_fragment_for_match(dest_fragment)
    source_fragment = CTX.local_route_fragment_for_match(source_fragment)
    if dest_fragment == "" then dest_fragment = nil end
    if source_fragment == "" then source_fragment = nil end
    local dest_track, dest_index, dest_name
    if dest_fragment then
      local ambiguous, ambiguous_names = false, nil
      dest_track, dest_index, dest_name, ambiguous, ambiguous_names =
        CTX.local_track_named_in_text(facts, dest_fragment)
      if ambiguous then return CTX.local_track_ambiguity("Sends", ambiguous_names) end
      if not dest_track then
        local target_error
        dest_track, dest_index, dest_name, target_error =
          CTX.local_singular_selected_track_in_text(
            facts, dest_fragment, "Sends", false)
        if target_error then return target_error end
      end
    end
    local explicit_source_track, explicit_source_index, explicit_source_name
    if source_fragment then
      local ambiguous, ambiguous_names = false, nil
      explicit_source_track, explicit_source_index, explicit_source_name,
        ambiguous, ambiguous_names =
        CTX.local_track_named_in_text(facts, source_fragment)
      if ambiguous then return CTX.local_track_ambiguity("Sends", ambiguous_names) end
      if not explicit_source_track then
        local target_error
        explicit_source_track, explicit_source_index, explicit_source_name,
          target_error =
          CTX.local_singular_selected_track_in_text(
            facts, source_fragment, "Sends", false)
        if target_error then return target_error end
      end
    end
    local selected_track, selected_index, selected_name, missing_selected =
      CTX.local_selected_track_index_in_text(facts, lt)
    if missing_selected then
      return "Sends: selected track " .. tostring(missing_selected) .. " not found"
    end
    if not selected_track and not dest_track and not explicit_source_track then
      selected_track, selected_index, selected_name, missing_selected =
        CTX.local_singular_selected_track_in_text(
          facts, lt, "Sends", false)
      if missing_selected then return missing_selected end
    end
    local send_opts = {
      dest_track = dest_track,
      dest_index = dest_index,
      dest_name = dest_name,
      selected_only = not selected_track
        and not explicit_source_track
        and (lt:find("selected track", 1, true) ~= nil
          or lt:find("selected tracks", 1, true) ~= nil),
    }
    if explicit_source_track then
      send_opts.source_track = explicit_source_track
      send_opts.source_index = explicit_source_index
      send_opts.source_name = explicit_source_name
    elseif selected_track then
      send_opts.source_track = selected_track
      send_opts.source_index = selected_index
      send_opts.source_name = selected_name
    elseif not send_opts.selected_only and not dest_track then
      local source_track, source_index, source_name, missing_index =
        CTX.local_track_index_in_text(facts, lt)
      if missing_index then
        return "Sends: track " .. tostring(missing_index) .. " not found"
      end
      local ambiguous, ambiguous_names = false, nil
      if not source_track then
        source_track, source_index, source_name, ambiguous, ambiguous_names =
          CTX.local_track_named_in_text(facts, lt)
      end
      if ambiguous then return CTX.local_track_ambiguity("Sends", ambiguous_names) end
      if source_track then
        send_opts.source_track = source_track
        send_opts.source_index = source_index
        send_opts.source_name = source_name
      end
    end
    local answer = CTX.sends(proj, send_opts)
    local dest_pat = tostring(dest_name or ""):lower():gsub("([^%w])", "%%%1")
    local whether_source = dest_track and (
         lt:match("%f[%w]whether%s+(.+)%s+feeds%s+it")
      or lt:match("%f[%w]whether%s+(.+)%s+feeds%s+" .. dest_pat)
      or lt:match("%f[%w]whether%s+(.+)%s+sends%s+to%s+it")
      or lt:match("%f[%w]whether%s+(.+)%s+sends%s+to%s+" .. dest_pat))
    whether_source = CTX.local_route_fragment_for_match(whether_source)
    if whether_source and whether_source ~= "" then
      local src_track, _, src_name
      local route_error
      src_track, _, src_name, route_error =
        CTX.local_route_endpoint_in_text(facts, whether_source)
      if route_error then return route_error end
      if src_track then
        answer = answer .. "\n" .. CTX.send_route_answer(proj, src_track,
          src_name, dest_track, dest_name)
      end
    end
    if lt:find("what track is selected", 1, true)
        or lt:find("what tracks are selected", 1, true)
        or lt:find("which track is selected", 1, true)
        or lt:find("which tracks are selected", 1, true)
        or lt:find("track is selected", 1, true)
        or lt:find("tracks are selected", 1, true) then
      answer = answer .. "\n" .. CTX.local_read_selected_tracks(facts)
    end
    return answer
  end
  if lt:find("tracks have items", 1, true)
      or lt:find("any tracks have items", 1, true)
      or lt:find("any track has items", 1, true)
      or lt:find("tracks have media", 1, true)
      or lt:find("any tracks have media", 1, true)
      or lt:find("any track has media", 1, true)
      or lt:find("tracks with items", 1, true)
      or lt:find("tracks with media", 1, true)
      or lt:find("tracks contain items", 1, true)
      or lt:find("tracks contain media", 1, true) then
    return CTX.tracks_with_items(proj, {
      selected_only = selected_track_phrase,
    })
  end
  if lt:find("selected item", 1, true)
      or lt:find("selected items", 1, true)
      or lt:find("item is selected", 1, true)
      or lt:find("items are selected", 1, true) then
    return CTX.selected_items(proj, {
      human = true,
      include_names = true,
    })
  end
  if lt:find("item count", 1, true)
      or lt:find("number of items", 1, true)
      or lt:find("how many items", 1, true)
      or lt:find("media items", 1, true)
      or lt:find("%f[%w]items%f[%W]") then
    local selected_track, selected_index, selected_name, missing_selected =
      CTX.local_selected_track_index_in_text(facts, lt)
    if missing_selected then
      return "Items: selected track " .. tostring(missing_selected) .. " not found"
    end
    if not selected_track then
      selected_track, selected_index, selected_name, missing_selected =
        CTX.local_singular_selected_track_in_text(
          facts, lt, "Items", false)
      if missing_selected then return missing_selected end
    end
    local item_opts = {
      count_only = lt:find("item count", 1, true) ~= nil
        or lt:find("number of items", 1, true) ~= nil
        or lt:find("how many items", 1, true) ~= nil,
      selected_only = not selected_track
        and (lt:find("selected track", 1, true) ~= nil
          or lt:find("selected tracks", 1, true) ~= nil),
      include_names = true,
    }
    if selected_track then
      item_opts.source_track = selected_track
      item_opts.source_index = selected_index
      item_opts.source_name = selected_name
    elseif not item_opts.selected_only then
      local source_track, source_index, source_name, missing_index =
        CTX.local_track_index_in_text(facts, lt)
      if missing_index then
        return "Items: track " .. tostring(missing_index) .. " not found"
      end
      local ambiguous, ambiguous_names = false, nil
      if not source_track then
        source_track, source_index, source_name, ambiguous, ambiguous_names =
          CTX.local_track_named_in_text(facts, lt)
      end
      if ambiguous then return CTX.local_track_ambiguity("Items", ambiguous_names) end
      if source_track then
        item_opts.source_track = source_track
        item_opts.source_index = source_index
        item_opts.source_name = source_name
      end
    end
    return CTX.media_items(proj, item_opts)
  end
  local wants_muted_flag =
       lt:find("%f[%w]muted%f[%W]") ~= nil
    or lt:find("%f[%w]mute%f[%W]") ~= nil
    or lt:find("%f[%w]unmuted%f[%W]") ~= nil
  local wants_soloed_flag =
       lt:find("%f[%w]soloed%f[%W]") ~= nil
    or lt:find("%f[%w]solo%f[%W]") ~= nil
    or lt:find("%f[%w]unsoloed%f[%W]") ~= nil
  local wants_armed_flag =
       lt:find("%f[%w]armed%f[%W]") ~= nil
    or lt:find("record armed", 1, true) ~= nil
    or lt:find("record-armed", 1, true) ~= nil
    or lt:find("%f[%w]unarmed%f[%W]") ~= nil
  if (wants_muted_flag or wants_soloed_flag or wants_armed_flag)
      and lt:find("%f[%w]tracks%f[%W]") ~= nil then
    local flag_count = (wants_muted_flag and 1 or 0)
      + (wants_soloed_flag and 1 or 0)
      + (wants_armed_flag and 1 or 0)
    local inverse_flag =
         lt:find("not muted", 1, true) ~= nil
      or lt:find("not mute", 1, true) ~= nil
      or lt:find("%f[%w]unmuted%f[%W]") ~= nil
      or lt:find("not soloed", 1, true) ~= nil
      or lt:find("not solo", 1, true) ~= nil
      or lt:find("%f[%w]unsoloed%f[%W]") ~= nil
      or lt:find("not armed", 1, true) ~= nil
      or lt:find("not record armed", 1, true) ~= nil
      or lt:find("not record-armed", 1, true) ~= nil
      or lt:find("%f[%w]unarmed%f[%W]") ~= nil
    if inverse_flag and flag_count ~= 1 then return nil end
    return CTX.tracks_matching_flags(proj, {
      selected_only = selected_track_phrase,
      muted = wants_muted_flag,
      soloed = wants_soloed_flag,
      armed = wants_armed_flag,
      invert = inverse_flag,
    })
  end
  if not selected_track_phrase
      and (lt:find("track flags", 1, true)
      or lt:find("muted tracks", 1, true)
      or lt:find("tracks are muted", 1, true)
      or lt:find("tracks muted", 1, true)
      or lt:find("soloed tracks", 1, true)
      or lt:find("tracks are soloed", 1, true)
      or lt:find("tracks soloed", 1, true)
      or lt:find("armed tracks", 1, true)
      or lt:find("tracks are armed", 1, true)
      or lt:find("tracks armed", 1, true)
      or lt:find("record armed tracks", 1, true)) then
    return CTX.track_flags(proj)
  end
  if lt:find("empty tracks", 1, true)
      or lt:find("tracks are empty", 1, true)
      or lt:find("tracks empty", 1, true)
      or lt:find("tracks have no items", 1, true)
      or lt:find("any tracks have no items", 1, true)
      or lt:find("any track has no items", 1, true)
      or lt:find("tracks with no items", 1, true)
      or lt:find("tracks without items", 1, true) then
    return CTX.empty_tracks(proj, {
      selected_only = selected_track_phrase,
    })
  end
  if lt:find("tracks have no master output", 1, true)
      or lt:find("tracks with no master output", 1, true)
      or lt:find("tracks without master output", 1, true)
      or lt:find("tracks have no main output", 1, true)
      or lt:find("tracks with no main output", 1, true)
      or lt:find("tracks without main output", 1, true)
      or lt:find("tracks are not sent to master", 1, true)
      or lt:find("tracks not sent to master", 1, true)
      or lt:find("tracks are not sending to master", 1, true)
      or lt:find("tracks not sending to master", 1, true)
      or lt:find("tracks are not routed to master", 1, true)
      or lt:find("tracks not routed to master", 1, true) then
    return CTX.tracks_without_master_output(proj, {
      selected_only = selected_track_phrase,
    })
  end
  local track_property_word =
       lt:find("%f[%w]volume%f[%W]") ~= nil
    or lt:find("%f[%w]volumes%f[%W]") ~= nil
    or lt:find("%f[%w]fader%f[%W]") ~= nil
    or lt:find("%f[%w]faders%f[%W]") ~= nil
    or lt:find("%f[%w]pan%f[%W]") ~= nil
    or lt:find("%f[%w]pans%f[%W]") ~= nil
    or lt:find("%f[%w]mute%f[%W]") ~= nil
    or lt:find("%f[%w]muted%f[%W]") ~= nil
    or lt:find("%f[%w]solo%f[%W]") ~= nil
    or lt:find("%f[%w]soloed%f[%W]") ~= nil
    or lt:find("%f[%w]armed%f[%W]") ~= nil
    or lt:find("record arm", 1, true) ~= nil
    or lt:find("main output", 1, true) ~= nil
    or lt:find("master output", 1, true) ~= nil
    or lt:find("track properties", 1, true) ~= nil
    or lt:find("track property", 1, true) ~= nil
  local wants_track_property_list =
       lt:find("track properties", 1, true) ~= nil
    or lt:find("track property", 1, true) ~= nil
    or lt:find("track volume", 1, true) ~= nil
    or lt:find("track volumes", 1, true) ~= nil
    or lt:find("track fader", 1, true) ~= nil
    or lt:find("track faders", 1, true) ~= nil
    or lt:find("track pan", 1, true) ~= nil
    or lt:find("track pans", 1, true) ~= nil
  if track_property_word then
    local selected_track, selected_index, selected_name, missing_selected =
      CTX.local_selected_track_index_in_text(facts, lt)
    if missing_selected then
      return "Track properties: selected track "
        .. tostring(missing_selected) .. " not found"
    end
    if not selected_track then
      selected_track, selected_index, selected_name, missing_selected =
        CTX.local_singular_selected_track_in_text(
          facts, lt, "Track properties", false)
      if missing_selected then return missing_selected end
    end
    local prop_opts = {
      selected_only = not selected_track
        and (lt:find("selected track", 1, true) ~= nil
          or lt:find("selected tracks", 1, true) ~= nil),
    }
    if selected_track then
      prop_opts.source_track = selected_track
      prop_opts.source_index = selected_index
      prop_opts.source_name = selected_name
    elseif not prop_opts.selected_only then
      local source_track, source_index, source_name, missing_index =
        CTX.local_track_index_in_text(facts, lt)
      if missing_index then
        return "Track properties: track " .. tostring(missing_index) .. " not found"
      end
      local ambiguous, ambiguous_names = false, nil
      if not source_track then
        source_track, source_index, source_name, ambiguous, ambiguous_names =
          CTX.local_track_named_in_text(facts, lt)
      end
      if ambiguous then
        return CTX.local_track_ambiguity("Track properties", ambiguous_names)
      end
      if source_track then
        prop_opts.source_track = source_track
        prop_opts.source_index = source_index
        prop_opts.source_name = source_name
      end
    end
    if not wants_track_property_list
        and not prop_opts.selected_only
        and not prop_opts.source_track then
      return nil
    end
    local property_kind = CTX.local_track_property_kind(lt)
    if property_kind
        and prop_opts.source_track
        and not wants_track_property_list then
      return CTX.track_property_answer(prop_opts.source_track,
        prop_opts.source_index, prop_opts.source_name, property_kind)
    end
    return CTX.track_properties(proj, prop_opts)
  end
  if lt:find("tracks have no fx", 1, true)
      or lt:find("tracks with no fx", 1, true)
      or lt:find("tracks without fx", 1, true)
      or lt:find("tracks have no plugins", 1, true)
      or lt:find("tracks with no plugins", 1, true)
      or lt:find("tracks without plugins", 1, true)
      or lt:find("tracks have no effects", 1, true)
      or lt:find("tracks with no effects", 1, true)
      or lt:find("tracks without effects", 1, true)
      or lt:find("tracks dont have fx", 1, true)
      or lt:find("tracks don't have fx", 1, true) then
    return CTX.tracks_without_fx(proj, {
      selected_only = selected_track_phrase,
    })
  end
  local fx_presence_text = lt:gsub("[%.%?%!]+$", "")
  local generic_fx_presence_target =
       fx_presence_text:match("^%s*are%s+there%s+any%s+fx%s+on%s+(.+)$")
    or fx_presence_text:match("^%s*is%s+there%s+any%s+fx%s+on%s+(.+)$")
    or fx_presence_text:match("^%s*are%s+there%s+any%s+plugins%s+on%s+(.+)$")
    or fx_presence_text:match("^%s*are%s+there%s+any%s+effects%s+on%s+(.+)$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+any%s+fx%s*$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+fx%s*$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+any%s+plugins%s*$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+plugins%s*$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+any%s+effects%s*$")
    or fx_presence_text:match("^%s*does%s+(.+)%s+have%s+effects%s*$")
  if generic_fx_presence_target then
    local source_track, source_index, source_name, target_error =
      CTX.local_any_track_target_in_text(
        facts, generic_fx_presence_target, "FX presence")
    if target_error then return target_error end
    if source_track then
      return CTX.track_fx_presence_answer(
        proj, source_track, source_index, source_name)
    end
  end
  local fx_presence_track, fx_presence_query = CTX.local_fx_presence_query(lt)
  if fx_presence_track then
    local source_track, source_index, source_name, narrowed_fx_query, fx_error =
      CTX.local_track_fx_query_from_parts(
        facts, fx_presence_track, fx_presence_query, "FX presence")
    if fx_error then return fx_error end
    if source_track and narrowed_fx_query then
      return CTX.fx_on_track_presence(
        proj, source_track, source_index, source_name, narrowed_fx_query)
    end
  end
  if lt:find("fx chains", 1, true)
      or lt:find("track fx", 1, true)
      or lt:find("have fx", 1, true)
      or lt:find("has fx", 1, true)
      or lt:find("have plugin", 1, true)
      or lt:find("has plugin", 1, true)
      or lt:find("have effect", 1, true)
      or lt:find("has effect", 1, true)
      or lt:find("fx are on", 1, true)
      or lt:find("fx on ", 1, true)
      or lt:find("plugins are on", 1, true)
      or lt:find("plugins on ", 1, true)
      or lt:find("effects are on", 1, true)
      or lt:find("effects on ", 1, true) then
    local selected_track, selected_index, selected_name, missing_selected =
      CTX.local_selected_track_index_in_text(facts, lt)
    if missing_selected then
      return "FX chains: selected track " .. tostring(missing_selected) .. " not found"
    end
    if not selected_track then
      selected_track, selected_index, selected_name, missing_selected =
        CTX.local_singular_selected_track_in_text(
          facts, lt, "FX chains", false)
      if missing_selected then return missing_selected end
    end
    local fx_opts = {
      selected_only = not selected_track
        and (lt:find("selected track", 1, true) ~= nil
          or lt:find("selected tracks", 1, true) ~= nil),
    }
    if selected_track then
      fx_opts.source_track = selected_track
      fx_opts.source_index = selected_index
      fx_opts.source_name = selected_name
    elseif not fx_opts.selected_only then
      local source_track, source_index, source_name, missing_index =
        CTX.local_track_index_in_text(facts, lt)
      if missing_index then
        return "FX chains: track " .. tostring(missing_index) .. " not found"
      end
      local ambiguous, ambiguous_names = false, nil
      if not source_track then
        source_track, source_index, source_name, ambiguous, ambiguous_names =
          CTX.local_track_named_in_text(facts, lt)
      end
      if ambiguous then return CTX.local_track_ambiguity("FX chains", ambiguous_names) end
      if source_track then
        fx_opts.source_track = source_track
        fx_opts.source_index = source_index
        fx_opts.source_name = source_name
      end
    end
    return CTX.fx(proj, fx_opts)
  end
  local fx_query = CTX.local_fx_search_query(lt)
  if fx_query then
    if fx_query ~= "*" then
      local source_track, source_index, source_name, narrowed_fx_query, fx_error =
        CTX.local_track_fx_query_in_text(facts, fx_query)
      if fx_error then return fx_error end
      if source_track and narrowed_fx_query then
        return CTX.fx_on_track_matching(
          proj, source_track, source_index, source_name, narrowed_fx_query)
      end
    end
    return fx_query == "*" and CTX.fx(proj, {}) or CTX.fx_tracks_with(proj, fx_query)
  end
  if lt:find("selected track", 1, true)
      or lt:find("selected tracks", 1, true)
      or lt:find("track is selected", 1, true)
      or lt:find("tracks are selected", 1, true) then
    return CTX.local_read_selected_tracks(facts)
  end
  if lt:find("marker count", 1, true)
      or lt:find("region count", 1, true)
      or lt:find("how many markers", 1, true)
      or lt:find("how many regions", 1, true) then
    return str_format("Markers: %d | Regions: %d",
      facts.marker_count, facts.region_count)
  end
  if lt:find("track count", 1, true)
      or lt:find("number of tracks", 1, true)
      or lt:find("how many tracks", 1, true) then
    return str_format("Track count: %d", facts.track_count)
  end
  if lt:find("folder structure", 1, true)
      or lt:find("track folder", 1, true)
      or lt:find("track folders", 1, true)
      or lt:find("folder tracks", 1, true)
      or lt:find("folders in this project", 1, true)
      or lt:find("folders in the project", 1, true) then
    return CTX.track_folders(proj)
  end
  if lt:find("track names", 1, true)
      or lt:find("list tracks", 1, true)
      or lt:find("show tracks", 1, true)
      or lt:find("show all tracks", 1, true)
      or lt:find("what tracks", 1, true)
      or lt:find("which tracks", 1, true) then
    return CTX.local_read_track_list(facts)
  end
  if lt:find("%f[%w]markers%f[%W]")
      or lt:find("%f[%w]marker%f[%W]")
      or lt:find("%f[%w]regions%f[%W]")
      or lt:find("%f[%w]region%f[%W]") then
    return CTX.markers(proj)
  end
  return nil
end

-- CTX.selected_items(proj) -> string
-- Reports the count and key properties (track, position, length) of selected
-- media items. Capped at CTX.MAX_ITEM_REPORT items to keep snapshot size bounded
-- for projects with large block-selections. Items beyond the cap are noted
-- with a summary count so the assistant knows additional items exist.
--
-- Item indices in output are 1-based (matching REAPER's UI display) even
-- though CountSelectedMediaItems / GetSelectedMediaItem are 0-based.
function CTX.selected_items(proj, opts)
  local count = R_CountSelectedMediaItems(proj)
  if count == 0 then return "Selected items: none" end

  local include_names = opts and opts.include_names == true
  if opts and opts.human == true then
    local lines = { str_format("Selected items: %d", count) }
    local report_n = math_min(count, CTX.MAX_ITEM_REPORT)
    for i = 0, report_n - 1 do
      local item = R_GetSelectedMediaItem(proj, i)
      local pos = R_GetMediaItemInfo_Value(item, "D_POSITION") or 0
      local len = R_GetMediaItemInfo_Value(item, "D_LENGTH") or 0
      local track = R_GetMediaItem_Track(item)
      local track_idx = -1
      local track_nm = "unknown"
      if track then
        track_idx = math_floor(R_GetMediaTrackInfo_Value(track,
          "IP_TRACKNUMBER") or -1)
        local _, nm = R_GetTrackName(track)
        track_nm = nm ~= "" and nm or "(unnamed)"
      end
      local item_nm = include_names and CTX.media_item_name(item) or nil
      if item_nm then item_nm = item_nm:gsub('"', "'") end
      track_nm = tostring(track_nm):gsub('"', "'")
      local track_label = track_idx > 0
        and str_format('track %d "%s"', track_idx, track_nm)
        or "unknown track"
      if item_nm and item_nm ~= "" then
        lines[#lines + 1] = str_format(
          '- "%s" on %s (start %.3fs, length %.3fs)',
          item_nm, track_label, pos, len)
      else
        lines[#lines + 1] = str_format(
          "- Item %d on %s (start %.3fs, length %.3fs)",
          i + 1, track_label, pos, len)
      end
    end
    if count > CTX.MAX_ITEM_REPORT then
      lines[#lines + 1] = str_format("(+%d more)",
        count - CTX.MAX_ITEM_REPORT)
    end
    return tbl_concat(lines, "\n")
  end

  local lines = {
    include_names
      and str_format("Selected items (N=%d) [item_idx|track_idx|track_name|item_name|pos_s|len_s]:", count)
      or str_format("Selected items (N=%d) [item_idx|track_idx|track_name|pos_s|len_s]:", count)
  }
  local report_n = math_min(count, CTX.MAX_ITEM_REPORT)
  for i = 0, report_n - 1 do
    local item  = R_GetSelectedMediaItem(proj, i)
    local pos   = R_GetMediaItemInfo_Value(item, "D_POSITION")
    local len   = R_GetMediaItemInfo_Value(item, "D_LENGTH")
    -- GetMediaItem_Track returns the track that owns this item. We resolve its
    -- display name and 1-based index for a human-readable description.
    local track = R_GetMediaItem_Track(item)
    local track_idx = -1
    local track_nm  = "unknown"
    if track then
      -- MediaTrackInfo "IP_TRACKNUMBER" returns the 1-based track number.
      track_idx = math_floor(R_GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
      local _, nm = R_GetTrackName(track)
      track_nm = nm
    end
    if include_names then
      lines[#lines+1] = str_format(
        "%d|%d|%s|%s|%.3f|%.3f",
        i + 1, track_idx, _scrub_pipes(track_nm),
        _scrub_pipes(CTX.media_item_name(item)), pos, len)
    else
      lines[#lines+1] = str_format(
        "%d|%d|%s|%.3f|%.3f",
        i + 1, track_idx, _scrub_pipes(track_nm), pos, len)
    end
  end
  if count > CTX.MAX_ITEM_REPORT then
    lines[#lines+1] = str_format(
      "(+%d more)", count - CTX.MAX_ITEM_REPORT)
  end
  return tbl_concat(lines, "\n")
end

-- Item inventory bucket for local read answers. It can scope to selected tracks
-- or one source track, optionally count-only, and caps row output like selected_items.
function CTX.media_items(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local source_track = opts and opts.source_track or nil
  local source_name = opts and opts.source_name or nil
  local count_only = opts and opts.count_only == true
  local include_names = opts and opts.include_names == true
  local total = 0
  local items = {}
  if source_track then
    total = R_CountTrackMediaItems(source_track)
    local report_n = math_min(total, CTX.MAX_ITEM_REPORT)
    for i = 0, report_n - 1 do
      local item = reaper.GetTrackMediaItem(source_track, i)
      if item then items[#items+1] = item end
    end
  else
    local project_total = reaper.CountMediaItems
      and (reaper.CountMediaItems(proj) or 0)
      or 0
    for i = 0, project_total - 1 do
      local item = reaper.GetMediaItem and reaper.GetMediaItem(proj, i) or nil
      local tr = item and R_GetMediaItem_Track(item) or nil
      if item and (not selected_only or (tr and R_IsTrackSelected(tr))) then
        total = total + 1
        if #items < CTX.MAX_ITEM_REPORT then items[#items+1] = item end
      end
    end
  end
  if count_only then
    if source_track then
      return str_format("Items on %s: %d", source_name or "track", total)
    end
    return selected_only and str_format("Items on selected tracks: %d", total)
      or str_format("Items: %d", total)
  end
  if total == 0 then
    if source_track then
      return "Items: none on " .. (source_name or "track")
    end
    return selected_only and "Items: none on selected tracks" or "Items: none"
  end
  local lines = {
    include_names
      and str_format("Items (N=%d) [item_idx|track_idx|track_name|item_name|pos_s|len_s]:", total)
      or str_format("Items (N=%d) [item_idx|track_idx|track_name|pos_s|len_s]:", total)
  }
  for i, item in ipairs(items) do
    local pos = R_GetMediaItemInfo_Value(item, "D_POSITION") or 0
    local len = R_GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    local track = R_GetMediaItem_Track(item)
    local track_idx = -1
    local track_nm = "unknown"
    if track then
      track_idx = math_floor(R_GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or -1)
      local _, nm = R_GetTrackName(track)
      track_nm = nm
    end
    if include_names then
      lines[#lines+1] = str_format("%d|%d|%s|%s|%.3f|%.3f",
        i, track_idx, _scrub_pipes(track_nm),
        _scrub_pipes(CTX.media_item_name(item)), pos, len)
    else
      lines[#lines+1] = str_format("%d|%d|%s|%.3f|%.3f",
        i, track_idx, _scrub_pipes(track_nm), pos, len)
    end
  end
  if total > CTX.MAX_ITEM_REPORT then
    lines[#lines+1] = str_format("(+%d more)", total - CTX.MAX_ITEM_REPORT)
  end
  return tbl_concat(lines, "\n")
end

function CTX.empty_tracks(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local total = 0
  local rows = {}
  local track_count = R_CountTracks(proj)
  for i = 0, track_count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr
        and (not selected_only or R_IsTrackSelected(tr))
        and R_CountTrackMediaItems(tr) == 0 then
      total = total + 1
      if #rows < 40 then
        local _, nm = R_GetTrackName(tr)
        rows[#rows + 1] = str_format("%d. %s", i + 1,
          nm ~= "" and nm or "(unnamed)")
      end
    end
  end
  local label = selected_only and "Empty selected tracks" or "Empty tracks"
  if total == 0 then return label .. ": none" end
  local lines = { str_format("%s: %d", label, total) }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > #rows then
    lines[#lines + 1] = str_format("(+%d more)", total - #rows)
  end
  return tbl_concat(lines, "\n")
end

function CTX.tracks_with_items(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local total = 0
  local rows = {}
  local track_count = R_CountTracks(proj)
  for i = 0, track_count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and (not selected_only or R_IsTrackSelected(tr)) then
      local item_count = R_CountTrackMediaItems(tr) or 0
      if item_count > 0 then
        total = total + 1
        if #rows < 40 then
          local _, nm = R_GetTrackName(tr)
          rows[#rows + 1] = str_format("%d. %s | items=%d", i + 1,
            nm ~= "" and nm or "(unnamed)", item_count)
        end
      end
    end
  end
  local label = selected_only and "Selected tracks with items"
    or "Tracks with items"
  if total == 0 then return label .. ": none" end
  local lines = { str_format("%s: %d", label, total) }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > #rows then
    lines[#lines + 1] = str_format("(+%d more)", total - #rows)
  end
  return tbl_concat(lines, "\n")
end

-- Routing bucket for send/bus/sidechain questions. Reports normal track sends
-- only (category 0); hardware outputs and master/parent send are handled by
-- separate track-property/master-output helpers.
function CTX.sends(proj, opts)
  if not reaper.GetTrackNumSends or not reaper.GetTrackSendInfo_Value then
    return "Sends: unavailable"
  end
  local selected_only = opts and opts.selected_only == true
  local source_track = opts and opts.source_track or nil
  local source_name = opts and opts.source_name or nil
  local dest_track = opts and opts.dest_track or nil
  local dest_name = opts and opts.dest_name or nil
  local total = 0
  local rows = {}
  local track_count = R_CountTracks(proj)
  for i = 0, track_count - 1 do
    local src = R_GetTrack(proj, i)
    if src
        and (not selected_only or R_IsTrackSelected(src))
        and (not source_track or src == source_track) then
      local _, src_name = R_GetTrackName(src)
      local send_count = reaper.GetTrackNumSends(src, 0) or 0
      for si = 0, send_count - 1 do
        local dest = reaper.GetTrackSendInfo_Value(src, 0, si, "P_DESTTRACK")
        if not dest_track or dest == dest_track then
          total = total + 1
          if #rows < CTX.MAX_SEND_REPORT then
            local dest_idx = -1
            local row_dest_name = "unknown"
            if dest then
              dest_idx = math_floor(R_GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER") or -1)
              local _, nm = R_GetTrackName(dest)
              row_dest_name = nm
            end
            local vol = reaper.GetTrackSendInfo_Value(src, 0, si, "D_VOL") or 1
            local vol_db = vol > 0 and (20 * math.log(vol, 10)) or -150
            local pan = reaper.GetTrackSendInfo_Value(src, 0, si, "D_PAN") or 0
            local mode = math_floor(reaper.GetTrackSendInfo_Value(src, 0, si, "I_SENDMODE") or 0)
            rows[#rows + 1] = str_format("%d|%s|%d|%d|%s|%.2f|%.2f|%d",
              i + 1, _scrub_pipes(src_name), si + 1, dest_idx,
              _scrub_pipes(row_dest_name), vol_db, pan, mode)
          end
        end
      end
    end
  end
  if total == 0 then
    if source_track and dest_track then
      return "Sends: none from " .. (source_name or "track")
        .. " to " .. (dest_name or "track")
    end
    if dest_track then
      return "Sends: none to " .. (dest_name or "track")
    end
    if source_track then
      return "Sends: none on " .. (source_name or "track")
    end
    return selected_only and "Sends: none on selected tracks" or "Sends: none"
  end
  local lines = {
    str_format("Sends (N=%d) [src_idx|src_name|send_idx|dest_idx|dest_name|vol_db|pan|mode]:", total)
  }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > CTX.MAX_SEND_REPORT then
    lines[#lines + 1] = str_format("(+%d more)", total - CTX.MAX_SEND_REPORT)
  end
  return tbl_concat(lines, "\n")
end

function CTX.track_send_presence_answer(proj, source_track, source_index, source_name)
  if not source_track then return nil end
  local label = CTX.local_track_label(source_index, source_name)
  if not reaper.GetTrackNumSends or not reaper.GetTrackSendInfo_Value then
    return "Sends: unavailable"
  end
  local send_count = reaper.GetTrackNumSends(source_track, 0) or 0
  if send_count == 0 then return label .. " has no sends to other tracks." end
  local dests = {}
  for si = 0, send_count - 1 do
    local dest = reaper.GetTrackSendInfo_Value(source_track, 0, si, "P_DESTTRACK")
    if dest then
      local _, nm = R_GetTrackName(dest)
      dests[#dests + 1] = CTX.local_track_label(
        math_floor(R_GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER") or 0),
        nm)
    end
    if #dests >= 3 then break end
  end
  if #dests == 0 then
    return str_format("%s has %d send%s to other tracks.", label, send_count,
      send_count == 1 and "" or "s")
  end
  local suffix = send_count > #dests and str_format(", +%d more",
    send_count - #dests) or ""
  return str_format("%s has %d send%s to %s%s.", label, send_count,
    send_count == 1 and "" or "s", tbl_concat(dests, ", "), suffix)
end

function CTX.tracks_without_sends(proj, opts)
  local selected_only = opts and opts.selected_only == true
  local label = selected_only and "Selected tracks without sends"
    or "Tracks without sends"
  if not reaper.GetTrackNumSends then return label .. ": unavailable" end
  local total = 0
  local rows = {}
  local track_count = R_CountTracks(proj)
  for i = 0, track_count - 1 do
    local tr = R_GetTrack(proj, i)
    if tr and (not selected_only or R_IsTrackSelected(tr)) then
      local send_count = reaper.GetTrackNumSends(tr, 0) or 0
      if send_count == 0 then
        total = total + 1
        if #rows < 40 then
          local _, nm = R_GetTrackName(tr)
          rows[#rows + 1] = str_format("%d. %s", i + 1,
            nm ~= "" and nm or "(unnamed)")
        end
      end
    end
  end
  if total == 0 then return label .. ": none" end
  local lines = { str_format("%s: %d", label, total) }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  if total > #rows then
    lines[#lines + 1] = str_format("(+%d more)", total - #rows)
  end
  return tbl_concat(lines, "\n")
end

function CTX.send_route_answer(proj, source_track, source_name, dest_track, dest_name)
  if not source_track or not dest_track then return nil end
  if not reaper.GetTrackNumSends or not reaper.GetTrackSendInfo_Value then
    return "Route: unavailable"
  end
  local send_count = reaper.GetTrackNumSends(source_track, 0) or 0
  for si = 0, send_count - 1 do
    local dest = reaper.GetTrackSendInfo_Value(source_track, 0, si, "P_DESTTRACK")
    if dest == dest_track then
      return "Route: yes, " .. (source_name or "source track")
        .. " sends to " .. (dest_name or "destination track")
        .. str_format(" (send %d)", si + 1)
    end
  end
  return "Route: no, " .. (source_name or "source track")
    .. " does not send to " .. (dest_name or "destination track")
end

-- =============================================================================
-- fx_params helpers
-- =============================================================================

-- CTX.fx_normalize_name(name) -> string
-- Produces a maximally-flexible search key from a raw plugin name string.
-- Transformations applied (in order):
--   1. Lowercase everything.
--   2. Strip the REAPER format prefix (VST:, VST3:, AU:, CLAP:, JS:, etc.)
--      and the vendor/manufacturer suffix in parentheses, e.g. "(Valhalla DSP)".
--      These are added by REAPER and should not affect matching.
--   3. Remove all non-alphanumeric characters (spaces, hyphens, underscores,
--      dots, slashes ...). This makes "Pro-Q 3", "ProQ3", "Pro Q3" all resolve
--      to "proq3", so minor punctuation differences never break a match.
-- The same transformation is applied to both the FX name from REAPER and the
-- search term supplied by the assistant, so matching is symmetric.

-- Returns true when (name, idx) match a VST3 host-appended tail param
-- (Internal / Delta / Wet@>0 / Bypass@>0). Extracted so CTX.fx_params,
-- the shallow scan, the deep scan, and the deep-probe estimator share a
-- single predicate -- previously this was inlined four times with
-- subtly different parenthesisation, and Stage 1 of the review pass
-- found a nil-deref bug in two of those copies.
local function _is_vst3_tail(name, idx)
  return name == "Internal" or name == "Delta"
      or ((name == "Wet" or name == "Bypass") and idx > 0)
end

function CTX.fx_normalize_name(name)
  local s = name:lower()
  -- Strip format prefix (VST3:, VST2:, CLAP:, JS:, etc.) - use %w+ to cover
  -- prefixes that contain digits like "VST3:".
  s = s:gsub("^%w+:%s*", "")
  -- Strip vendor suffix: " (anything)" at the end.
  s = s:gsub("%s*%(.-%)%s*$", "")
  -- Collapse all non-alphanumeric characters so spacing/punctuation is ignored.
  s = s:gsub("[^%a%d]", "")
  return s
end

-- CTX.fx_name_matches(fx_full_name, search_terms) -> bool
-- Returns true if fx_full_name fuzzy-matches ANY entry in the search_terms list.
-- Two levels of matching are attempted, from strictest to most lenient:
--   1. Normalized contains: the normalized search term appears as a substring
--      of the normalized FX name. Catches "VintageVerb" vs "Vintage Verb",
--      "Pro-Q 3" vs "ProQ3", etc.
--   2. Token subset: the normalized FX name contains all of the search term's
--      individual digit-run and alpha-run tokens. Catches abbreviated queries
--      like "reverb" matching "ValhallaVintageVerb" or "q3" matching "ProQ3".
-- Returning on the first match avoids redundant work when multiple terms are
-- provided.
function CTX.fx_name_matches(fx_full_name, search_terms)
  local norm_fx = CTX.fx_normalize_name(fx_full_name)
  for _, term in ipairs(search_terms) do
    local norm_term = CTX.fx_normalize_name(term)
    if norm_term ~= "" then
      -- Level 1: normalized substring match (whole term).
      if norm_fx:find(norm_term, 1, true) then
        return true
      end
      -- Level 2: token subset match. Split norm_term into alpha and digit runs
      -- and check that every token appears as a substring of norm_fx.
      -- Example: term "q 3" -> tokens {"q","3"} -> both in "proq3" -> match.
      local all_match = true
      local token_count = 0
      for token in norm_term:gmatch("[%a]+") do
        token_count = token_count + 1
        if not norm_fx:find(token, 1, true) then all_match = false; break end
      end
      for token in norm_term:gmatch("[%d]+") do
        token_count = token_count + 1
        if not norm_fx:find(token, 1, true) then all_match = false; break end
      end
      if token_count > 0 and all_match then
        return true
      end
      -- Level 3: word-level match. Split the ORIGINAL term on spaces and
      -- normalize each word individually, then check ALL appear in norm_fx.
      -- Catches "Fabfilter ProQ" matching "Pro-Q 4" -- "proq" is in "proq4"
      -- even though the full "fabfilterproq" is not.
      local words = {}
      for w in term:gmatch("%S+") do
        local nw = CTX.fx_normalize_name(w)
        if nw ~= "" then words[#words+1] = nw end
      end
      if #words > 1 then
        local all_words = true
        for _, w in ipairs(words) do
          if not norm_fx:find(w, 1, true) then
            all_words = false
            break
          end
        end
        if all_words then return true end
      end
    end
  end
  return false
end

-- CTX.fx_filter_parse(payload) -> { name, track }
-- Parse a single fx_params payload like "Pro-Q 4" or "Pro-Q 4@2". The "@N"
-- suffix is optional and scopes the lookup to a single 1-based track index
-- (matching the human-facing "Track N" labels in fx_params output). Without
-- "@N" the filter applies to every track. Whitespace around the @ and around
-- the name is ignored; an unparsable "@..." (non-integer or zero) falls back
-- to whole-string-as-name with no scope, so a literal "@" inside an exotic
-- plugin name doesn't cause a silent miss.
function CTX.fx_filter_parse(payload)
  payload = payload or ""
  local nm, tn = payload:match("^(.-)%s*@%s*(%d+)%s*$")
  if nm and nm ~= "" then
    local n = tonumber(tn)
    if n and n >= 1 then
      return { name = nm:match("^%s*(.-)%s*$"), track = n }
    end
  end
  return { name = payload:match("^%s*(.-)%s*$"), track = nil }
end

-- CTX.fx_filter_key(filters) -> string
-- Re-serialize a list of filter records back into "Pro-Q 4@2/Pro-C 3" form
-- for use as a sticky_context key and ctx_label chip. Tolerates legacy
-- string entries (no scope).
function CTX.fx_filter_key(filters)
  local parts = {}
  for _, f in ipairs(filters or {}) do
    local nm, tr
    if type(f) == "string" then nm = f
    else nm, tr = f.name, f.track end
    if nm and nm ~= "" then
      parts[#parts+1] = tr and (nm .. "@" .. tr) or nm
    end
  end
  return tbl_concat(parts, "/")
end

-- CTX.fx_filter_names_only(filters) -> { string, ... }
-- Names-only view, used by callers that need to fuzzy-match without caring
-- about track scope (e.g. the auto-cache trigger in the bucket dispatcher,
-- which inspects any matching plugin to populate the FX cache regardless of
-- which track instance the model asked about).
function CTX.fx_filter_names_only(filters)
  local out = {}
  for _, f in ipairs(filters or {}) do
    local nm = (type(f) == "string") and f or f.name
    if nm and nm ~= "" then out[#out+1] = nm end
  end
  return out
end

-- CTX.fx_params(proj, filter_names) -> string, matched_count
-- On-demand bucket (NOT included in the default session snapshot).
-- Returns current parameter values ONLY for FX whose names fuzzy-match at
-- least one entry in filter_names (see CTX.fx_name_matches above). filter_names
-- entries may be strings ("Pro-Q 4") OR records ({name="Pro-Q 4", track=2})
-- produced by CTX.fx_filter_parse. A record's track field, when present,
-- restricts the match to that single 1-based track index -- so the model can
-- request "fx_params:Pro-Q 4@2" to read only track 2's instance instead of
-- triggering a 200K-token dump across every Pro-Q 4 in the project.
--
-- Identical-state dedup: when multiple matched FX produce byte-identical
-- param bodies (typical for freshly-added EQ instances on N tracks: only the
-- ones actually edited differ from the default), emit the body once and
-- annotate the FX header with "(also identical on tracks 3-10)". Cuts the
-- output for 10x default Pro-Q 4 from ~6000 lines to ~600.
--
-- A non-empty filter_names list is ALWAYS required. Full-session dumps are
-- intentionally not supported: on large sessions they can exceed the model's
-- context limit and cost several dollars per call. The assistant is instructed
-- to always request specific plugin names via fx_params:PluginName.
--
-- FX indices in output are 0-based (matching REAPER API) so the assistant can
-- pass them directly to TrackFX_GetParam / TrackFX_SetParam without adjustment.
-- Parameter values are reported as normalised [0..1] floats followed by the
-- formatted display string (e.g. "-6.0 dB") so the assistant has both.
--
-- Returns two values: the formatted string and the count of FX that matched
-- (0 means no FX matched the filter, which the caller should surface as a
-- friendly error rather than sending an empty block to the assistant).
function CTX.fx_params(proj, filter_names)
  -- Normalize the filter list: callers may pass strings (legacy) or records
  -- (new). Records carry an optional `track` field that scopes the match to
  -- a single 1-based track index. Inlined to avoid blowing past the 200
  -- module-scope-local limit in this large file.
  local filters = {}
  for _, f in ipairs(filter_names or {}) do
    if type(f) == "string" then
      filters[#filters+1] = CTX.fx_filter_parse(f)
    else
      filters[#filters+1] = { name = f.name or "", track = f.track }
    end
  end
  -- Guard: filters must be non-empty. If the assistant somehow emits a bare
  -- <context_needed>fx_params</context_needed> with no plugin name, the
  -- parser catches it before calling this function, but defend here too.
  if #filters == 0 then
    return "FX PARAMETER VALUES: (error: no plugin name specified -- "
      .. "use fx_params:PluginName to request specific plugins)", 0
  end

  -- Format the "(also identical on ...)" annotation. When every duplicate
  -- shares the primary's FX index, collapse to "tracks 3-10" / "tracks 3, 5,
  -- 7-9". When the FX index varies across dups (uncommon: same plugin at
  -- different chain positions on different tracks), emit "Track N FX[I]"
  -- verbatim so the model can disambiguate.
  local function format_dup_list(dups, primary_fx_idx)
    local same_fx = true
    for _, d in ipairs(dups) do
      if d.fx_idx ~= primary_fx_idx then same_fx = false; break end
    end
    if same_fx then
      local nums = {}
      for _, d in ipairs(dups) do nums[#nums+1] = d.track_idx end
      table.sort(nums)
      local out, i = {}, 1
      while i <= #nums do
        local j = i
        while j < #nums and nums[j+1] == nums[j] + 1 do j = j + 1 end
        if j > i then
          out[#out+1] = nums[i] .. "-" .. nums[j]
        else
          out[#out+1] = tostring(nums[i])
        end
        i = j + 1
      end
      return "tracks " .. tbl_concat(out, ", ")
    else
      local out = {}
      for _, d in ipairs(dups) do
        out[#out+1] = "Track " .. d.track_idx .. " FX[" .. d.fx_idx .. "]"
      end
      return tbl_concat(out, ", ")
    end
  end

  local track_count = R_CountTracks(proj)
  -- Re-emit the filters in canonical "Name@Track" form for the header so the
  -- model sees its own scope decisions echoed back (helps it learn the syntax
  -- via positive reinforcement on subsequent turns).
  local header_parts = {}
  for _, f in ipairs(filters) do
    header_parts[#header_parts+1] = f.track and (f.name .. "@" .. f.track) or f.name
  end
  local header = "FX PARAMETER VALUES (filtered: "
    .. tbl_concat(header_parts, ", ") .. "):"
  local lines = { header }

  -- A filter matches a (track_idx_1based, fx_name) pair when the FX name
  -- fuzzy-matches the filter's name AND the filter has either no track scope
  -- or a track scope equal to this track.
  local function matches_any(track_idx_1based, fx_nm)
    for _, f in ipairs(filters) do
      if (not f.track) or f.track == track_idx_1based then
        if CTX.fx_name_matches(fx_nm, { f.name }) then return true end
      end
    end
    return false
  end

  -- Walk all tracks/FX once, building a per-FX "entry" with the parameter
  -- body buffered as a single string. We dedup by (fx_nm, body) below so
  -- N identical instances of a freshly-added EQ collapse to one block.
  local entries = {}
  for ti = 0, track_count - 1 do
    -- Nil-guard R_GetTrack against project-tab close races: track_count
    -- was sampled at the top of fx_params, but on long FX walks the user
    -- can swap or close the project tab mid-loop. R_GetTrackName(nil)
    -- would crash; skipping the iteration is safe.
    local tr = R_GetTrack(proj, ti)
    if tr then
      local _, nm    = R_GetTrackName(tr)
      local fx_count = R_TrackFX_GetCount(tr)
      for fi = 0, fx_count - 1 do
        local _, fx_nm = R_TrackFX_GetFXName(tr, fi, "")
        if matches_any(ti + 1, fx_nm) then
          -- Look up cached enum data for this plugin (if available).
          local cached_key, cached_plugin = FXCache.find_plugin(fx_nm)
          local cached_enums = {}  -- idx -> enum list
          local cached_ranges = {} -- idx -> {display_min, display_max}
          if cached_plugin and cached_plugin.params then
            if S._fx_cache_events then
              local t = S._fx_cache_events
              t.hit = t.hit or {}
              t.hit[#t.hit+1] = cached_key or fx_nm
            end
            for _, cp in ipairs(cached_plugin.params) do
              if cp.enum then cached_enums[cp.idx] = cp.enum end
              if cp.display_min and cp.display_max then
                cached_ranges[cp.idx] = { cp.display_min, cp.display_max }
              end
            end
          end
          local body_lines = {}
          local param_count = R_TrackFX_GetNumParams(tr, fi)
          local param_shown = 0
          for pi = 0, param_count - 1 do
            local _, param_nm = R_TrackFX_GetParamName(tr, fi, pi, "")
            -- Filter MIDI CC automation parameters (VST3 plugins expose 2000+).
            if param_nm:match("^CC %d") or param_nm:match("^MIDI CC") then
              goto continue_param
            end
            -- Filter MIDI message params injected by the host.
            if param_nm == "Channel Pressure" or param_nm == "Poly Pressure"
               or param_nm == "Pitch Bend" or param_nm == "Program Change" then
              goto continue_param
            end
            -- Filter generic unnamed params with no useful display value.
            local _, disp = R_TrackFX_GetFormattedParamValue(tr, fi, pi, "")
            disp = disp or ""  -- ReaImGui binding can return nil on unusual plugins
            if (param_nm:match("^Param %d+$") or param_nm:match("^Parameter %d+$"))
               and (disp == "" or disp:match("^[%d%.%%]*$")) then
              goto continue_param
            end
            -- Filter VST3 host-appended params (Bypass/Wet/Delta/Internal at tail).
            if _is_vst3_tail(param_nm, pi) then
              if disp == "normal" or disp == "-" or disp:match("^%d+$") then
                goto continue_param
              end
            end
            local val, mn, mx = R_TrackFX_GetParam(tr, fi, pi)
            local norm = 0
            if mx ~= mn then norm = (val - mn) / (mx - mn) end
            -- Annotate with [enum:] or [range:] if we have cached data for this param.
            local suffix = ""
            if cached_enums[pi] then
              suffix = "  [enum: " .. tbl_concat(cached_enums[pi], ", ") .. "]"
            elseif cached_ranges[pi] then
              suffix = "  [range: " .. cached_ranges[pi][1] .. ".." .. cached_ranges[pi][2] .. "]"
            end
            -- Display value first (human-readable), normalized in brackets.
            body_lines[#body_lines+1] = str_format(
              "    [%d] %s: %s  [norm: %.4f]%s",
              pi, param_nm, disp, norm, suffix)
            param_shown = param_shown + 1
            ::continue_param::
          end
          if param_shown < param_count then
            body_lines[#body_lines+1] = str_format(
              "    (%d host/uninformative params filtered)",
              param_count - param_shown)
          end
          entries[#entries+1] = {
            track_idx = ti + 1,
            track_nm  = nm,
            fx_idx    = fi,
            fx_nm     = fx_nm,
            body      = tbl_concat(body_lines, "\n"),
          }
        end
      end
    end
  end

  -- Group entries by (fx_nm, body). Order is preserved by the order entries
  -- were inserted (track-major, FX-minor), so the "primary" of each group is
  -- always the first occurrence of that body. Later occurrences become
  -- "(also identical on tracks ...)" annotations on the primary's FX header.
  local groups, group_idx = {}, {}
  for _, e in ipairs(entries) do
    local key = e.fx_nm .. "\0" .. e.body
    local gi = group_idx[key]
    if gi then
      groups[gi].dups[#groups[gi].dups + 1] = e
    else
      groups[#groups+1] = { primary = e, dups = {} }
      group_idx[key] = #groups
    end
  end

  -- Emit. Track headers ride along the primary entries; non-primary entries
  -- are folded into the dedup annotation so identical bodies aren't repeated.
  local last_track_emitted = -1
  for _, g in ipairs(groups) do
    local p = g.primary
    if last_track_emitted ~= p.track_idx then
      last_track_emitted = p.track_idx
      lines[#lines+1] = str_format("Track %d %q:", p.track_idx, p.track_nm)
    end
    local also = ""
    if #g.dups > 0 then
      also = "  (also identical on " .. format_dup_list(g.dups, p.fx_idx) .. ")"
    end
    lines[#lines+1] = str_format("  FX [%d] %s:%s", p.fx_idx, p.fx_nm, also)
    if p.body ~= "" then lines[#lines+1] = p.body end
  end

  if #entries == 0 then
    lines[#lines+1] = "  (no matching FX found on any track -- the plugin is not loaded yet. "
      .. "If fx_list results are available above, use them to write code that adds the plugin and sets parameters "
      .. "using find_param and set_param_display at runtime. Do NOT request fx_list again -- proceed with the code.)"
  end

  return tbl_concat(lines, "\n"), #entries
end

-- =============================================================================
-- CTX.docs / CTX.midi / CTX.theme
-- =============================================================================
-- Loads the REAPER Lua API + workflow reference from a single file in the
-- script's Resources folder (API_Ref.md). The file contains ten buckets
-- delimited by `<!-- SECTION:name -->` markers:
--   core      always-pinned when "Always include REAPER API reference" is
--             on; otherwise fetched on-demand via the docs bucket.
--   extended  less-common API surface; on-demand via docs_extended.
--   items / envelopes / take_fx / routing / tempo / sws
--             on-demand via docs:NAME.
--   midi      MIDI workflow reference; auto-injected on midi prompts or
--             on-demand via the midi bucket. Served by CTX.midi.
--   theme     theme color reference; auto-injected on theme+color prompts
--             or on-demand via the theme bucket. Served by CTX.theme.
-- The whole file is read once per session and parsed into
-- S.api_ref_section_cache, but each bucket is still served individually
-- -- only the requested bucket is sent to the model. Does not take a proj
-- argument because the reference is project-independent.
--
-- The file's leading HTML-comment header sits before the first SECTION
-- marker so it is naturally ignored by the marker parser; it never ships
-- to the model.
--
-- Returns the formatted reference string on success, or nil + error message
-- on failure. Callers MUST check for nil and show the error to the user in
-- chat rather than sending the error text to the assistant.

local function _read_ref_file(path, filename)
  local f = io.open(path, "r")
  if not f then
    return nil, "API reference file not found at:\n" .. path
      .. "\n\nPlace " .. filename .. " in the Resources/ subfolder "
      .. "next to this script, or turn off \"Always include REAPER API reference\" in Settings."
  end
  local content = f:read("*a")
  f:close()
  if #content > CFG.MAX_API_REF_BYTES then
    return nil, str_format(
      "%s is too large (%.1f KB, max %d KB).\n"
      .. "This may not be the correct file.",
      filename, #content / 1024, CFG.MAX_API_REF_BYTES / 1024)
  end
  return content
end

-- The REAPER Lua API + workflow reference lives in a single physical file
-- (Resources/API_Ref.md) with ten buckets delimited by
-- `<!-- SECTION:name -->` ... `<!-- /SECTION:name -->` markers:
--   core      always-pinned default reference (CTX.docs)
--   extended  on-demand via <context_needed>docs_extended</context_needed>
--   items, envelopes, take_fx, routing, tempo, sws
--             on-demand via <context_needed>docs:NAME</context_needed>
--   midi      auto-injected on midi prompts / on-demand via
--             <context_needed>midi</context_needed> (CTX.midi)
--   theme     auto-injected on theme+color prompts / on-demand via
--             <context_needed>theme</context_needed> (CTX.theme)
-- The file is read once per session and parsed into S.api_ref_section_cache
-- keyed by bucket name. Each bucket is still served individually -- only
-- the requested name is sent to the model -- but the loader and cache are
-- unified, replacing what used to be five separate per-file loaders.
local API_REF_FILE = "API_Ref.md"
-- Buckets the model can request. The dispatcher gates docs:<x> against
-- DOCS_SECTION_NAMES (the on-demand-section subset); the loader parses
-- the full set including core/extended/midi/theme.
local API_REF_SECTION_NAMES = {
  core      = true,
  extended  = true,
  items     = true,
  envelopes = true,
  take_fx   = true,
  routing   = true,
  tempo     = true,
  sws       = true,
  midi      = true,
  theme     = true,
}
local DOCS_SECTION_NAMES = {
  items     = true,
  envelopes = true,
  take_fx   = true,
  routing   = true,
  tempo     = true,
  sws       = true,
}
-- Singular / hyphenated / spaced variants the model commonly emits. Map
-- each to its canonical key in DOCS_SECTION_NAMES. Always lookup against
-- a lowercased key.
local DOCS_SECTION_ALIASES = {
  ["take-fx"]  = "take_fx",
  ["takefx"]   = "take_fx",
  ["take fx"]  = "take_fx",
  ["sends"]    = "routing",
  ["receives"] = "routing",
  ["envelope"] = "envelopes",
  ["item"]     = "items",
  ["send"]     = "routing",
  ["receive"]  = "routing",
  ["sws-extension"] = "sws",
  ["sws extension"] = "sws",
  ["sws_ext"]   = "sws",
  ["cf"]        = "sws",
  ["br"]        = "sws",
  ["nf"]        = "sws",
  ["fng"]       = "sws",
}
-- Normalize an incoming docs:<payload> to a canonical section key, or
-- nil if the payload is not a known section. Used by both the dispatcher
-- and the pre-pin scanner so they agree on what's a valid section.
local function _docs_section_canonical(payload)
  if type(payload) ~= "string" or payload == "" then return nil end
  local lower = payload:lower():match("^%s*(.-)%s*$")
  local canonical = DOCS_SECTION_ALIASES[lower] or lower
  if DOCS_SECTION_NAMES[canonical] then return canonical end
  return nil
end
CTX.docs_section_canonical = _docs_section_canonical

-- Sorted list of canonical on-demand section names for error messages.
local function _docs_section_list()
  local names = {}
  for k in pairs(DOCS_SECTION_NAMES) do names[#names+1] = k end
  table.sort(names)
  return tbl_concat(names, ", ")
end
-- Exported for invalid docs:NAME acknowledgements in ReaAssist.lua.
CTX.docs_section_list = _docs_section_list

-- Load and parse the API reference file once per session. After this
-- returns, S.api_ref_section_cache[name] holds the body for each
-- successfully parsed bucket, and S._api_ref_section_err[name] holds
-- the error string for any bucket that failed (file-level read error,
-- duplicate marker, or bucket missing from the allowlist's expected
-- set). S.api_ref_loaded is the sentinel: subsequent calls return
-- without re-reading the file. A missing/corrupt file in this session
-- stays missing -- the user can't fix it mid-session anyway, and the
-- error table holds a clear reason for any CTX.docs* call.
local function _load_api_ref_file()
  if S.api_ref_loaded then return end
  S.api_ref_section_cache = {}
  S._api_ref_section_err  = {}
  local content, err = _read_ref_file(
    RA.RESOURCES_DIR .. API_REF_FILE, API_REF_FILE)
  if not content then
    -- File-level failure: mark every known bucket so any CTX.docs* call
    -- surfaces a real error instead of "section not loaded".
    for name in pairs(API_REF_SECTION_NAMES) do
      S._api_ref_section_err[name] = err
    end
    S.api_ref_loaded = true
    return
  end
  -- Whitespace-tolerant marker pattern (matches both `<!--SECTION:items-->`
  -- and `<!-- SECTION:items -->`). The %1 back-reference forces the
  -- closing marker to name the same section.
  local pattern =
    "<!%-%-%s*SECTION:([%w_]+)%s*%-%->%s*(.-)%s*<!%-%-%s*/SECTION:%1%s*%-%->"
  local seen = {}
  for name, body in content:gmatch(pattern) do
    if not API_REF_SECTION_NAMES[name] then
      S._api_ref_section_err[name] =
        "Unknown section '" .. name .. "' in " .. API_REF_FILE
    elseif seen[name] then
      -- Duplicate marker block: fail loud rather than silently
      -- overwriting. Catches accidental copy/paste in the source file.
      S._api_ref_section_err[name] =
        "Duplicate SECTION:" .. name .. " block in " .. API_REF_FILE
      S.api_ref_section_cache[name] = nil
    else
      seen[name] = true
      S.api_ref_section_cache[name] = body:gsub("%s+$", "")
    end
  end
  -- Mark missing buckets (declared in allowlist but not parsed out).
  for name in pairs(API_REF_SECTION_NAMES) do
    if not S.api_ref_section_cache[name]
        and not S._api_ref_section_err[name] then
      S._api_ref_section_err[name] =
        "Section '" .. name .. "' missing from " .. API_REF_FILE
    end
  end
  S.api_ref_loaded = true
end

function CTX.docs()
  _load_api_ref_file()
  if S._api_ref_section_err.core then
    return nil, S._api_ref_section_err.core
  end
  return "REAPER LUA API REFERENCE:\n" .. S.api_ref_section_cache.core
end

function CTX.docs_extended()
  _load_api_ref_file()
  if S._api_ref_section_err.extended then
    return nil, S._api_ref_section_err.extended
  end
  return "REAPER LUA API REFERENCE (EXTENDED):\n"
    .. S.api_ref_section_cache.extended
end

-- Returns the formatted on-demand section payload, or nil + error string.
-- The caller is responsible for sticky_set'ing it under "docs:<name>" --
-- this loader just produces the content. Section name MUST be a canonical
-- key from DOCS_SECTION_NAMES (use _docs_section_canonical to normalize).
-- Defensive early-out for unknown names: don't trigger a file load on
-- bad input. The dispatcher already validates via _docs_section_canonical,
-- but CTX.docs_section is module-public and could be called directly with
-- a bad name from future code.
function CTX.docs_section(name)
  if not DOCS_SECTION_NAMES[name] then
    return nil, "Unknown docs section: '" .. tostring(name) .. "'. "
      .. "Valid: " .. _docs_section_list() .. "."
  end
  _load_api_ref_file()
  if S._api_ref_section_err[name] then
    return nil, S._api_ref_section_err[name]
  end
  if not S.api_ref_section_cache[name] then
    return nil, "Section '" .. tostring(name) .. "' not loaded."
  end
  return "REAPER LUA API REFERENCE (" .. name:upper() .. "):\n"
    .. S.api_ref_section_cache[name]
end

function CTX.recent_reaper_changes()
  local path = RA.RESOURCES_DIR .. "Reaper_Recent_Changes.md"
  local f = io.open(path, "r")
  if not f then
    return nil, "Recent REAPER changes file not found at:\n" .. path
  end
  local content = f:read("*a") or ""
  f:close()
  content = content:gsub("^%s+", ""):gsub("%s+$", "")
  if content == "" then
    return nil, "Recent REAPER changes file is empty:\n" .. path
  end
  if #content > 65536 then
    return nil, "Recent REAPER changes file is too large ("
      .. tostring(#content) .. " bytes)."
  end
  return "RECENT REAPER CHANGES (OFFICIAL CHANGELOG EXCERPT):\n" .. content
end

-- =============================================================================
-- CTX.prompt_bundle
-- =============================================================================
-- Conditional prompt bundles -- sections of the system prompt that apply only
-- to certain request types. They live in a single physical file
-- (Resources/Prompts.md) with buckets delimited by
-- `<!-- SECTION:name -->` ... `<!-- /SECTION:name -->` markers:
--   plugin          plugin / FX add + configure workflow
--   plugin_helpers  parameter-helper code patterns (find_param, etc.)
--   drums           phase-safe drum edit / quantize workflow
--   jsfx            JSFX (EEL2) generation rules
--   jsfx_dsp_cookbook  Delay/reverb/modulation JSFX memory recipes
--   theme           SetThemeColor backup safety rule
-- Each is fetched on-demand when the model emits
-- `<context_needed>prompt_bundle:NAME</context_needed>` so the always-on
-- system prompt can stay small. Once fetched, the bundle pins via
-- sticky_context for the rest of the conversation.
--
-- The whole file is read once per session and parsed into
-- S.prompt_bundle_cache; each bundle is still served individually --
-- only the requested name is sent to the model. Unknown names return
-- nil + error string so callers can surface a clean error.
local PROMPTS_FILE = "Prompts.md"
local PROMPT_BUNDLE_NAMES = {
  plugin         = true,
  plugin_helpers = true,
  drums          = true,
  jsfx           = true,
  jsfx_dsp_cookbook = true,
  jsfx_pitch     = true,
  theme          = true,
}

local function _prompt_bundle_list()
  local names = {}
  for k in pairs(PROMPT_BUNDLE_NAMES) do names[#names+1] = k end
  table.sort(names)
  return tbl_concat(names, ", ")
end

local function _load_prompts_file()
  if S.prompts_loaded then return end
  S.prompt_bundle_cache = {}
  S._prompt_bundle_err  = {}
  local content, err = _read_ref_file(
    RA.RESOURCES_DIR .. PROMPTS_FILE, PROMPTS_FILE)
  if not content then
    for n in pairs(PROMPT_BUNDLE_NAMES) do S._prompt_bundle_err[n] = err end
    S.prompts_loaded = true
    return
  end
  -- Same whitespace-tolerant pattern as the API ref loader.
  local pattern =
    "<!%-%-%s*SECTION:([%w_]+)%s*%-%->%s*(.-)%s*<!%-%-%s*/SECTION:%1%s*%-%->"
  local seen = {}
  for n, body in content:gmatch(pattern) do
    if not PROMPT_BUNDLE_NAMES[n] then
      S._prompt_bundle_err[n] =
        "Unknown bundle '" .. n .. "' in " .. PROMPTS_FILE
    elseif seen[n] then
      S._prompt_bundle_err[n] =
        "Duplicate SECTION:" .. n .. " block in " .. PROMPTS_FILE
      S.prompt_bundle_cache[n] = nil
    else
      seen[n] = true
      local header = "PROMPT BUNDLE (" .. n:upper() .. "):\n"
      S.prompt_bundle_cache[n] = header .. body:gsub("%s+$", "")
    end
  end
  for n in pairs(PROMPT_BUNDLE_NAMES) do
    if not S.prompt_bundle_cache[n] and not S._prompt_bundle_err[n] then
      S._prompt_bundle_err[n] =
        "Bundle '" .. n .. "' missing from " .. PROMPTS_FILE
    end
  end
  S.prompts_loaded = true
end

function CTX.prompt_bundle(name)
  if type(name) ~= "string" or name == "" then
    return nil, "prompt_bundle requires a bundle name ("
      .. _prompt_bundle_list() .. ")."
  end
  name = name:lower()
  if not PROMPT_BUNDLE_NAMES[name] then
    return nil, "Unknown prompt bundle: '" .. name .. "'. "
      .. "Valid names: " .. _prompt_bundle_list() .. "."
  end
  _load_prompts_file()
  if S._prompt_bundle_err[name] then
    return nil, S._prompt_bundle_err[name]
  end
  if not S.prompt_bundle_cache[name] then
    return nil, "Bundle '" .. name .. "' not loaded."
  end
  return S.prompt_bundle_cache[name]
end

-- =============================================================================
-- CTX.midi
-- =============================================================================
-- Returns the MIDI workflow reference (PPQ explainer, value ranges, function
-- signatures, worked examples). Body content lives in API_Ref.md under
-- SECTION:midi; the unified API-ref loader caches every bucket on first
-- access. Returns the formatted reference string on success, or nil + error
-- message on failure.
function CTX.midi()
  _load_api_ref_file()
  if S._api_ref_section_err.midi then
    return nil, S._api_ref_section_err.midi
  end
  return "REAPER MIDI WORKFLOW REFERENCE:\n" .. S.api_ref_section_cache.midi
end

-- =============================================================================
-- Theme utilities + CTX.theme
-- =============================================================================

-- Restore any saved theme color backups from ExtState.  Called by the Undo
-- button so theme color changes can be reverted.  Returns count restored.
--
-- NOTE: Theme backups use the literal namespace "ReaAssist" (capital R), NOT
-- CFG.EXT_NS ("reaassist"). This is intentional: generated theme-change scripts
-- also write to "ReaAssist" so backup/restore works without the scripts needing
-- to know CFG.EXT_NS. Do NOT change to CFG.EXT_NS without updating the system
-- prompt's theme reference and all generated code patterns.
Theme = {}

function Theme._t(key, values, fallback)
  return (RA and RA.t and RA.t(key, values, fallback)) or fallback or key
end

function Theme.restore_backups()
  -- Read the manifest of changed keys written by the theme change script.
  local manifest = reaper.GetExtState("ReaAssist", "ThemeBackup__KEYS")
  if manifest == "" then return 0 end
  local keys = {}
  for k in manifest:gmatch("[^,]+") do
    keys[#keys+1] = k:match("^%s*(.-)%s*$")
  end
  if #keys == 0 then return 0 end
  reaper.PreventUIRefresh(1)
  -- Wrap in pcall so a corrupted ext-state value (or any unexpected
  -- SetThemeColor failure) cannot leave PreventUIRefresh suppressed.
  pcall(function()
    for _, ini_key in ipairs(keys) do
      local saved = reaper.GetExtState("ReaAssist", "ThemeBackup_" .. ini_key)
      if saved ~= "" then
        local n = tonumber(saved)
        if n then
          reaper.SetThemeColor(ini_key, n, 0)
        end
        reaper.DeleteExtState("ReaAssist", "ThemeBackup_" .. ini_key, false)
      end
    end
    reaper.DeleteExtState("ReaAssist", "ThemeBackup__KEYS", false)
  end)
  reaper.PreventUIRefresh(-1)
  reaper.ThemeLayout_RefreshAll()
  reaper.UpdateArrange()
  return #keys
end

-- ---------------------------------------------------------------------------
-- Theme.save_to_file() -- write current runtime colors into the .ReaperTheme
-- file so they persist across theme reloads. Only works with unzipped
-- .ReaperTheme files; shows a message for .ReaperThemeZip.
-- Returns true on success, false + error string on failure.
-- ---------------------------------------------------------------------------
function Theme.save_to_file()
  local manifest = reaper.GetExtState("ReaAssist", "ThemeBackup__KEYS")
  if manifest == "" then
    return false, Theme._t("code.theme_error.no_changes", nil,
      "No theme changes to save.")
  end
  local theme_path = reaper.GetLastColorThemeFile()
  if not theme_path or theme_path == "" then
    return false, Theme._t("code.theme_error.no_theme_file", nil,
      "Could not determine the current theme file.")
  end
  if theme_path:lower():match("%.reaperthemezip$") then
    return false, Theme._t("code.theme_error.zip_theme", nil,
      "Your current theme is a .ReaperThemeZip file which "
        .. "cannot be edited directly.\n\nTo save changes: open the Theme "
        .. "development/tweaker window (Actions > Theme development/tweaker) "
        .. "and click 'Save Theme...' to export as a .ReaperTheme file.")
  end
  -- Collect the keys and their current runtime values.
  local keys = {}
  for k in manifest:gmatch("[^,]+") do
    local trimmed = k:match("^%s*(.-)%s*$")
    keys[trimmed] = reaper.GetThemeColor(trimmed, 0)
  end
  -- Read the existing theme file.
  local f, err = io.open(theme_path, "r")
  if not f then
    local detail = err or theme_path
    return false, Theme._t("code.theme_error.read_failed",
      { error = detail }, "Cannot read theme file: " .. detail)
  end
  local content = f:read("*a")
  f:close()
  -- Update existing keys and track which ones were found.
  local found = {}
  for key, val in pairs(keys) do
    local pattern = "(" .. key:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1") .. "=)[^\r\n]*"
    local new_content, count = content:gsub(pattern, "%1" .. tostring(val))
    if count > 0 then
      content = new_content
      found[key] = true
    end
  end
  -- Append any new keys that weren't already in the file.
  local to_append = {}
  for key, val in pairs(keys) do
    if not found[key] then
      to_append[#to_append+1] = key .. "=" .. tostring(val)
    end
  end
  if #to_append > 0 then
    -- Insert before the end of the [color theme] section or at end of file.
    local append_str = table.concat(to_append, "\n") .. "\n"
    -- Find the end of the [color theme] section (next section header or EOF).
    local next_section = content:find("\n%[", 2)
    if next_section then
      content = content:sub(1, next_section - 1) .. append_str .. content:sub(next_section)
    else
      -- No other sections; append at end.
      if content:sub(-1) ~= "\n" then content = content .. "\n" end
      content = content .. append_str
    end
  end
  -- Write back. Use a temp file + rename so a partial write or process kill
  -- mid-write cannot corrupt the user's .ReaperTheme. On Windows os.rename
  -- fails if the destination exists, so we delete the original first; this
  -- leaves a small window where the file is briefly absent, but a complete
  -- file is much better than a half-written one.
  local tmp_path = theme_path .. ".tmp"
  f, err = io.open(tmp_path, "w")
  if not f then
    local detail = err or tmp_path
    return false, Theme._t("code.theme_error.write_failed",
      { error = detail }, "Cannot write theme file: " .. detail)
  end
  local ok_w, err_w = f:write(content)
  local ok_c, err_c = f:close()
  if not ok_w or not ok_c then
    os.remove(tmp_path)
    local detail = tostring(err_w or err_c or "close failed")
    return false, Theme._t("code.theme_error.write_close_failed",
      { error = detail }, "Failed to write theme file: " .. detail)
  end
  os.remove(theme_path)
  local ok_r, err_r = os.rename(tmp_path, theme_path)
  if not ok_r then
    os.remove(tmp_path)
    local detail = tostring(err_r)
    return false, Theme._t("code.theme_error.replace_failed",
      { error = detail }, "Failed to replace theme file: " .. detail)
  end
  -- Clear backups since the changes are now permanent.
  for key in pairs(keys) do
    reaper.DeleteExtState("ReaAssist", "ThemeBackup_" .. key, false)
  end
  reaper.DeleteExtState("ReaAssist", "ThemeBackup__KEYS", false)
  return true
end

-- theme color ini_key names for SetThemeColor/GetThemeColor, plus usage patterns.
-- On-demand bucket: injected when the user asks about changing theme colors or
-- appearance. Also auto-injected when the prompt contains theme + color keywords.
-- Body content lives in API_Ref.md under SECTION:theme; served by the unified
-- API-ref loader.
--
-- Returns the formatted reference string on success, or nil + error message
-- on failure.
function CTX.theme()
  _load_api_ref_file()
  if S._api_ref_section_err.theme then
    return nil, S._api_ref_section_err.theme
  end
  return "REAPER THEME COLOR REFERENCE:\n" .. S.api_ref_section_cache.theme
end

-- =============================================================================
-- CTX.plugin_ref
-- =============================================================================
-- Loads Plugin_Ref.md and returns ONLY the sections matching
-- the requested plugin names (e.g. {"ReaVerbate", "ReaComp"}). The full file
-- is parsed once into a per-plugin cache; subsequent calls just look up keys.
--
-- The reference file contains curated parameter data for both REAPER's stock
-- plugins (ReaEQ, ReaComp, etc.) and selected third-party plugins ReaAssist
-- ships curated knowledge for (e.g. ReEQ).
--
-- Alias map: common synonyms resolve to the canonical plugin name so the LLM
-- can request plugin_ref:reverb and get ReaVerbate.
--
-- filter_names: list of plugin name strings. If empty/nil, returns an error.

-- Alias map for plugin names -> canonical section header in the .md file.
local PLUGIN_REF_ALIASES = {
  eq         = "reaeq",
  equalizer  = "reaeq",
  equaliser  = "reaeq",
  comp       = "reacomp",
  compressor = "reacomp",
  gate       = "reagate",
  expander   = "reagate",
  delay      = "readelay",
  echo       = "readelay",
  limiter    = "realimit",
  limit      = "realimit",
  pitch      = "reapitch",
  ["pitch shift"] = "reapitch",
  tune       = "reatune",
  tuner      = "reatune",
  ["pitch correction"] = "reatune",
  reverb     = "reaverbate",
  verb       = "reaverbate",
  synth      = "reasynth",
  synthesizer = "reasynth",
  -- Stock-JSFX fallbacks (section keys are short single-word names; aliases
  -- cover common type synonyms AND the full AddByName paths so the LLM can
  -- round-trip a preferred-plugin identifier back to its ref section).
  deesser                     = "deesser",
  ["de-esser"]                = "deesser",
  ["liteon/deesser"]          = "deesser",
  ["js: liteon/deesser"]      = "deesser",
  saturation                  = "saturation",
  saturator                   = "saturation",
  ["loser/saturation"]        = "saturation",
  ["js: loser/saturation"]    = "saturation",
  chorus                      = "chorus",
  chorus_stereo               = "chorus",
  ["sstillwell/chorus_stereo"]     = "chorus",
  ["js: sstillwell/chorus_stereo"] = "chorus",
  phaser                      = "phaser",
  ["guitar/phaser"]           = "phaser",
  ["js: guitar/phaser"]       = "phaser",
  -- Stock multiband compressor (curated section)
  ["reaxcomp"]                = "reaxcomp",
  ["multiband_compressor"]    = "reaxcomp",
  ["multiband compressor"]    = "reaxcomp",
  ["multiband comp"]          = "reaxcomp",
  ["multi-band compressor"]   = "reaxcomp",
  ["mbcomp"]                  = "reaxcomp",
  -- FabFilter Pro-Q series (EQ)
  ["pro-q 4"]                 = "pro-q 4",
  ["pro-q"]                   = "pro-q 4",
  ["fabfilter pro-q 4"]       = "pro-q 4",
  ["vst3: pro-q 4"]           = "pro-q 4",
  ["vst3: pro-q 4 (fabfilter)"] = "pro-q 4",
  -- FabFilter Pro-C (compressor)
  ["pro-c 3"]                 = "pro-c 3",
  ["pro-c"]                   = "pro-c 3",
  ["fabfilter pro-c 3"]       = "pro-c 3",
  ["vst3: pro-c 3"]           = "pro-c 3",
  ["vst3: pro-c 3 (fabfilter)"] = "pro-c 3",
  -- FabFilter Pro-L (limiter)
  ["pro-l 2"]                 = "pro-l 2",
  ["pro-l"]                   = "pro-l 2",
  ["fabfilter pro-l 2"]       = "pro-l 2",
  ["vst3: pro-l 2"]           = "pro-l 2",
  ["vst3: pro-l 2 (fabfilter)"] = "pro-l 2",
  -- FabFilter Pro-MB (multiband compressor)
  ["pro-mb"]                  = "pro-mb",
  ["fabfilter pro-mb"]        = "pro-mb",
  ["vst3: pro-mb"]            = "pro-mb",
  ["vst3: pro-mb (fabfilter)"] = "pro-mb",
  -- FabFilter Pro-R 2 (reverb)
  ["pro-r 2"]                 = "pro-r 2",
  ["pro-r"]                   = "pro-r 2",
  ["fabfilter pro-r 2"]       = "pro-r 2",
  ["vst3: pro-r 2"]           = "pro-r 2",
  ["vst3: pro-r 2 (fabfilter)"] = "pro-r 2",
  -- FabFilter Pro-DS (de-esser)
  ["pro-ds"]                  = "pro-ds",
  ["fabfilter pro-ds"]        = "pro-ds",
  ["vst3: pro-ds"]            = "pro-ds",
  ["vst3: pro-ds (fabfilter)"] = "pro-ds",
  -- FabFilter Pro-G (gate)
  ["pro-g"]                   = "pro-g",
  ["fabfilter pro-g"]         = "pro-g",
  ["vst3: pro-g"]             = "pro-g",
  ["vst3: pro-g (fabfilter)"] = "pro-g",
  -- FabFilter Saturn (saturation)
  ["saturn 2"]                = "saturn 2",
  ["saturn"]                  = "saturn 2",
  ["fabfilter saturn 2"]      = "saturn 2",
  ["vst3: saturn 2"]          = "saturn 2",
  ["vst3: saturn 2 (fabfilter)"] = "saturn 2",
  -- FabFilter Timeless (delay)
  ["timeless 3"]              = "timeless 3",
  ["timeless"]                = "timeless 3",
  ["fabfilter timeless 3"]    = "timeless 3",
  ["vst3: timeless 3"]        = "timeless 3",
  ["vst3: timeless 3 (fabfilter)"] = "timeless 3",
}

-- =============================================================================
-- CURATED_IDENT
-- =============================================================================
-- Maps chain-entry identifiers (as stored in preferred_types) to the matching
-- curated section name in Plugin_Ref.md. Entries here trigger plugin_ref:<Name>
-- injection (verified indices, scale formulas, recipes) instead of the thinner
-- live-scan preferred_plugins:<type>. Chain entries that aren't in this map
-- fall through to live-scan fallback. Extend as more curated plugins are added
-- to Plugin_Ref.md.
local CURATED_IDENT = {
  -- Stock plugins. Multiple ReEQ keys because REAPER's EnumInstalledFX
  -- returns the JSFX file path on Windows ("JS: ReJJ/ReEQ/ReEQ.jsfx") but
  -- the JSFX `desc:` line on macOS ("JS: ReEQ - Parametric Graphic
  -- Equalizer"); whichever string the user picks from the Pref Plugins
  -- autocomplete becomes the saved pref_types value, and we need to
  -- recognise both forms (with and without the "JS: " prefix that the save
  -- path may or may not strip) so the curated plugin_ref:ReEQ content fires
  -- regardless of platform.
  ["ReJJ/ReEQ/ReEQ.jsfx"]                       = "ReEQ",
  ["JS: ReJJ/ReEQ/ReEQ.jsfx"]                   = "ReEQ",
  ["ReEQ - Parametric Graphic Equalizer"]       = "ReEQ",
  ["JS: ReEQ - Parametric Graphic Equalizer"]   = "ReEQ",
  ["ReaEQ"]               = "ReaEQ",
  ["ReaComp"]             = "ReaComp",
  ["ReaXcomp"]            = "ReaXcomp",
  ["ReaGate"]             = "ReaGate",
  ["ReaDelay"]            = "ReaDelay",
  ["ReaLimit"]            = "ReaLimit",
  ["ReaPitch"]            = "ReaPitch",
  ["ReaTune"]             = "ReaTune",
  ["ReaSynth"]            = "ReaSynth",
  ["ReaVerbate"]          = "ReaVerbate",
  -- FabFilter (format-agnostic chain entries)
  ["Pro-Q 4"]             = "Pro-Q 4",
  ["Pro-C 3"]             = "Pro-C 3",
  ["Pro-L 2"]             = "Pro-L 2",
  ["Pro-MB"]              = "Pro-MB",
  ["Pro-R 2"]             = "Pro-R 2",
  ["Pro-DS"]              = "Pro-DS",
  ["Pro-G"]               = "Pro-G",
  ["Saturn 2"]            = "Saturn 2",
  ["Timeless 3"]          = "Timeless 3",
}
CTX.PLUGIN_REF_ALIASES = PLUGIN_REF_ALIASES

-- Curated lookup that tolerates AddByName prefix + vendor suffix on the
-- input. After preferred_types canonicalization, identifiers stored as
-- chain-entry form ("Pro-Q 4") become AddByName form ("VST3: Pro-Q 4"
-- or "VST3: Pro-Q 4 (FabFilter)"). A direct CURATED_IDENT[ident] lookup
-- only matches the bare keys in the table -- which would silently
-- bypass the curated plugin_ref:<Name> path for any canonicalized
-- pref, regressing the Pro-Q / Pro-C / Pro-R routes that depend on it.
--
-- Strategy: try the original ident first (handles ReEQ JSFX paths and
-- the legacy bare-name entries). Then strip a recognized AddByName
-- prefix (matched against PLUGIN_REF_ALIASES so the prefix list stays
-- authoritative in one place) and the trailing " (Vendor)" suffix and
-- retry. Returns nil when neither form matches.
local function _curated_for_ident(ident)
  if not ident or ident == "" then return nil end
  local hit = CURATED_IDENT[ident]
  if hit then return hit end
  -- Strip the prefix only if it looks like an AddByName format prefix
  -- (e.g., "VST3: ", "AUi: "). A leading "ReJJ/" path component must NOT
  -- be touched -- those paths are first-class CURATED_IDENT keys and
  -- the direct lookup above already handles them.
  local stripped = ident:match("^[A-Za-z][A-Za-z0-9]*:%s*(.+)$")
  if stripped then
    -- Drop trailing " (Vendor)" to recover the bare chain-entry form.
    local bare = stripped:gsub("%s*%(.-%)%s*$", "")
    hit = CURATED_IDENT[bare]
    if hit then return hit end
    -- Try without stripping the suffix too (some entries embed parens
    -- in the actual name, though none do today).
    if bare ~= stripped then
      hit = CURATED_IDENT[stripped]
      if hit then return hit end
    end
  end
  return nil
end
-- Exported for response-bucket de-duplication outside this sidecar.
CTX.curated_for_ident = _curated_for_ident

-- Build the per-plugin section cache from Plugin_Ref.md. Idempotent;
-- lazy -- call before reading CTX._plugin_ref_cache. Returns true on
-- success, false + error string if the file is missing.
function CTX.ensure_plugin_ref_cache()
  if CTX._plugin_ref_cache then return true end
  local ref_path = RA.RESOURCES_DIR .. "Plugin_Ref.md"
  local f = io.open(ref_path, "r")
  if not f then
    return false, "Plugin reference file not found at:\n" .. ref_path
      .. "\n\nPlace Plugin_Ref.md in the Resources/ subfolder "
      .. "next to this script."
  end
  local content = f:read("*a")
  f:close()

  -- Parse only `<!-- PLUGIN:Name --> ... <!-- /PLUGIN:Name -->` blocks. Other
  -- `## Heading` lines (e.g. "ENUM PARAM NORMS", "FALLBACK CHAINS", or any
  -- future explanatory section) are intentionally NOT cached so they can't
  -- silently become bogus plugin keys reachable via plugin_ref:<heading>.
  -- Marker lines themselves are stripped from the cached body; everything
  -- between (including the `## Name` header) is preserved.
  CTX._plugin_ref_cache = {}
  local cur_name = nil
  local cur_lines = {}
  for line in content:gmatch("[^\n]+") do
    local open_name  = line:match("^<!%-%- PLUGIN:(.-) %-%->%s*$")
    local close_name = line:match("^<!%-%- /PLUGIN:(.-) %-%->%s*$")
    if open_name then
      cur_name = open_name
      cur_lines = {}
    elseif close_name then
      if cur_name then
        CTX._plugin_ref_cache[cur_name:lower()] = tbl_concat(cur_lines, "\n")
      end
      cur_name = nil
      cur_lines = {}
    elseif cur_name then
      cur_lines[#cur_lines+1] = line
    end
  end

  -- Validation: warn if any PLUGIN_REF_ALIASES target doesn't resolve to a
  -- parsed plugin block. Catches typos in the alias map and stale aliases
  -- that point at plugins removed from Plugin_Ref.md. Runs once per
  -- session (this function is idempotent via the cache check at the top).
  local missing, seen = {}, {}
  for _, target in pairs(PLUGIN_REF_ALIASES) do
    if not CTX._plugin_ref_cache[target] and not seen[target] then
      seen[target] = true
      missing[#missing + 1] = target
    end
  end
  if #missing > 0 then
    table.sort(missing)
    Log.line("plugin_ref",
      "alias targets missing from Plugin_Ref.md: " .. tbl_concat(missing, ", "))
  end

  return true
end

-- Whether the given plugin identifier resolves to a curated Plugin_Ref
-- section. Used by the UI to hide Rescan (curated plugins don't benefit
-- from live-scanned cache data -- preempt routes through plugin_ref).
function Code.is_curated_plugin(ident)
  if not ident or ident == "" then return false end
  if not CTX.ensure_plugin_ref_cache() then return false end
  local k = ident:lower():match("^%s*(.-)%s*$") or ""
  k = PLUGIN_REF_ALIASES[k] or k
  return CTX._plugin_ref_cache[k] ~= nil
end

-- Return the stock fallback spec for a given type, or nil. Reads the
-- ```chains block in Plugin_Ref.md and derives the plugin_ref section key
-- via PLUGIN_REF_ALIASES so the popup knows which curated section to inject
-- when the user picks the stock option. Co-located with is_curated_plugin
-- because both rely on PLUGIN_REF_ALIASES being in lexical scope.
function Code.get_stock_fallback(type_key)
  if not type_key or type_key == "" then return nil end
  local chains = Code.get_fallback_chains()
  local entry = chains[type_key]
  if not entry or not entry.stock then return nil end
  local add   = entry.stock.add
  local alias = entry.stock.alias
  local k = add:lower():match("^%s*(.-)%s*$") or ""
  k = PLUGIN_REF_ALIASES[k] or k
  return {
    add   = add,
    label = alias or add,  -- display label for popup button
    ref   = k,              -- plugin_ref section key (lowercased)
  }
end

function CTX.plugin_ref(filter_names)
  if not filter_names or #filter_names == 0 then
    return "PLUGIN_REF: (error: no plugin specified -- "
      .. "use plugin_ref:ReaComp or plugin_ref:reverb, eq)"
  end

  local ok, err = CTX.ensure_plugin_ref_cache()
  if not ok then return nil, err end

  -- Look up each requested plugin. Resolve aliases first.
  local out = {}
  local matched_names = {}
  for _, name in ipairs(filter_names) do
    local k = name:lower():match("^%s*(.-)%s*$") or ""
    k = PLUGIN_REF_ALIASES[k] or k
    local section = CTX._plugin_ref_cache[k]
    if section then
      matched_names[#matched_names+1] = k
      out[#out+1] = section
      out[#out+1] = ""
    end
  end

  if #matched_names == 0 then
    return "PLUGIN_REF (no reference data for: "
      .. tbl_concat(filter_names, ", ")
      .. "). Use the parameter helpers (find_param, set_param_display) at runtime instead."
  end

  -- Title with the matched plugin names so weak models can string-scan for
  -- "is ReEQ here?" without parsing the body. Was previously just
  -- "PLUGIN PARAMETER REFERENCE:" which left models re-requesting the data
  -- via <context_needed>resolve:eq</context_needed> after preempt injection.
  return "PLUGIN PARAMETER REFERENCE (" .. tbl_concat(matched_names, ", ") .. "):\n"
    .. tbl_concat(out, "\n")
end

-- =============================================================================
-- CTX.installed_fx
-- =============================================================================
-- CTX.populate_installed_fx
-- =============================================================================
-- Idempotent helper that builds CTX._installed_fx_list by walking
-- reaper.EnumInstalledFX (REAPER 7.42+). Safe to call multiple times; the list
-- is only built once per session. Returns the list on success, or nil if the
-- REAPER build doesn't expose EnumInstalledFX.
--
-- Consolidated from previously-duplicated loops in: CTX.installed_fx,
-- pref_plugins_scan_start, the Preferred Plugins render, the per-row Rescan
-- handler, and the Plugin Resolve popup.
-- Dev-only filter: FabFilter product stems used when the
-- "dev_hide_fabfilter" ExtState flag is set (Debug Helper "Hide FabFilter"
-- toggle) to simulate "not installed" without touching REAPER state. Mirrors the
-- FabFilter section of PLUGIN_REF_ALIASES so short-form entries ("Pro-Q 4")
-- and vendor-suffixed entries ("VST3: Pro-Q 4 (FabFilter)") both match.
local FABFILTER_DEV_STEMS = {
  "fabfilter",
  "pro-q", "pro-c", "pro-l", "pro-mb", "pro-r", "pro-ds", "pro-g",
  "saturn", "timeless", "twin", "volcano", "simplon",
}

-- Returns true when the identifier (FX name as stored in preferred_types or
-- emitted by EnumInstalledFX) matches a FabFilter product stem. Used to gate
-- both the installed-FX enumeration AND the preferred_types read paths, so
-- the dev toggle hides FabFilter everywhere it could surface -- even if the
-- dev_signal refresh never reaches the main loop.
-- NOTE: declared with `function` (no `local`) so RA.load_context can pull the
-- binding back into ReaAssist.lua's forward-declared helper slot for
-- Code.ensure_preferred_from_chains.
function _is_fabfilter_ident(ident)
  if not ident or ident == "" then return false end
  local lc = ident:lower()
  for _, stem in ipairs(FABFILTER_DEV_STEMS) do
    if lc:find(stem, 1, true) then return true end
  end
  return false
end

function CTX.populate_installed_fx()
  -- ExtState is process-shared and always current, so consumers read
  -- the dev_hide_fabfilter flag directly here rather than mirroring it
  -- in a prefs field that could go stale if the dev_signal ever missed.
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
  -- Invalidate the cached list when the flag flips so the next read rebuilds
  -- with (or without) the FabFilter filter applied. Without this, the cache
  -- stays fixed at whatever filter state was active when the list was first
  -- built, and a live toggle wouldn't affect the installed-FX view.
  if CTX._installed_fx_list_hide_ff ~= hide_ff then
    CTX._installed_fx_list         = nil
    CTX._installed_fx_list_deduped = nil
  end
  CTX._installed_fx_list_hide_ff = hide_ff
  if CTX._installed_fx_list then return CTX._installed_fx_list end
  if not reaper.EnumInstalledFX then return nil end
  CTX._installed_fx_list = {}
  local idx = 0
  -- Hard upper bound is defensive: a misbehaving REAPER build that
  -- returned truthy retval with an empty name forever would otherwise
  -- spin this loop indefinitely. 100k installed FX is far beyond any
  -- realistic library size; the falsy retval still terminates first
  -- on a sane build.
  while idx < 100000 do
    local retval, name = reaper.EnumInstalledFX(idx)
    if not retval or retval == 0 or retval == false then break end
    if name and name ~= "" then
      if not (hide_ff and _is_fabfilter_ident(name)) then
        CTX._installed_fx_list[#CTX._installed_fx_list+1] = name
      end
    end
    idx = idx + 1
  end
  -- Build the VST2/VST3-dedup variant in the same pass. Previously the
  -- UI populated this on first paint of the Preferred Plugins / resolve
  -- popup, which produced a noticeable stall on large FX libraries
  -- (thousands of plugins) the first time those screens opened. Doing
  -- it here folds it into the one-shot enumeration cost.
  do
    local has_vst3, has_vst3i = {}, {}
    for _, iname in ipairs(CTX._installed_fx_list) do
      local base3i = iname:match("^VST3i:%s*(.*)$")
      if base3i then
        base3i = base3i:gsub("%s*%(.-%)%s*$", "")
        has_vst3i[base3i:lower()] = true
      else
        local base3 = iname:match("^VST3:%s*(.*)$")
        if base3 then
          base3 = base3:gsub("%s*%(.-%)%s*$", "")
          has_vst3[base3:lower()] = true
        end
      end
    end
    local dedup = {}
    for _, iname in ipairs(CTX._installed_fx_list) do
      local hide = false
      local vst2i_base = iname:match("^VSTi:%s*(.*)$")
      if vst2i_base then
        vst2i_base = vst2i_base:gsub("%s*%(.-%)%s*$", "")
        if has_vst3i[vst2i_base:lower()] then hide = true end
      else
        local vst2_base = iname:match("^VST:%s*(.*)$")
        if vst2_base then
          vst2_base = vst2_base:gsub("%s*%(.-%)%s*$", "")
          if has_vst3[vst2_base:lower()] then hide = true end
        end
      end
      if not hide then dedup[#dedup+1] = iname end
    end
    CTX._installed_fx_list_deduped = dedup
  end
  return CTX._installed_fx_list
end

-- =============================================================================
-- Searches installed FX plugins by name and returns matching entries.
-- Uses reaper.EnumInstalledFX (REAPER 7.42+). The full list is cached
-- internally; only entries matching the search terms are returned.
-- search_terms is a list of strings to fuzzy-match (uses CTX.fx_name_matches).
-- Returns (formatted_string, match_count) on success, or (nil, error) on failure.
function CTX.installed_fx(search_terms)
  -- Build/cache the full list on first call.
  if not CTX.populate_installed_fx() then
    return nil, "Your REAPER version does not support listing installed plugins "
      .. "(requires REAPER 7.42+)."
  end
  -- Filter to matching entries.
  if not search_terms or #search_terms == 0 then
    return nil, "fx_list requires a plugin name to search for."
  end
  local matches = {}
  for _, name in ipairs(CTX._installed_fx_list) do
    if CTX.fx_name_matches(name, search_terms) then
      matches[#matches+1] = name
    end
  end
  if #matches == 0 then
    return "INSTALLED FX SEARCH (no matches for: "
      .. tbl_concat(search_terms, ", ") .. "):\n"
      .. "No installed plugins matched. The user may be using a nickname or "
      .. "abbreviation. Ask them for the exact name as it appears in their FX browser.",
      0
  end
  -- Format each match inside backticks with a leading dash. Makes it
  -- visually obvious to the model that each identifier is a verbatim
  -- string to copy. Preceded by a strict anti-hallucination header because
  -- C-tier models routinely merge vendor suffixes from CLAP entries onto
  -- VST3 entries (e.g. "VST3: Pro-Q 4" + CLAP's "(FabFilter)" ->
  -- hallucinated "VST3: Pro-Q 4 (FabFilter)" which doesn't exist).
  local quoted = {}
  for _, name in ipairs(matches) do
    quoted[#quoted+1] = "  - `" .. name .. "`"
  end
  return "INSTALLED FX MATCHING " .. tbl_concat(search_terms, ", ") .. ":\n"
    .. tbl_concat(quoted, "\n") .. "\n"
    .. "COPY the chosen identifier CHARACTER-BY-CHARACTER from the list "
    .. "above. Do NOT add vendor names like \"(FabFilter)\" to entries "
    .. "that don't already have them. Do NOT remove suffixes. Each entry "
    .. "above is an EXACT string from EnumInstalledFX; REAPER only "
    .. "accepts these exact strings.\n"
    .. "Pick the BEST match by format priority (VST3 > VSTi > VST > AU > "
    .. "CLAP) and newest version number.",
    #matches
end

-- =============================================================================
-- CTX.scan_fx_params  (unified param scanner)
-- =============================================================================
-- Reads all parameters from an FX instance on a track, applying junk filtering
-- (MIDI CC, host params, generic unnamed, repeating groups 3+) and enum
-- detection (21-probe sweep). Returns a structured table of param entries and
-- the max group number for truncation notes.
--
-- Returns: params_list, max_group, total_param_count
--   params_list: { {idx=N, name="...", default=0.5, display="...", enum={...}}, ... }
--   max_group:   highest numbered group found (0 if none)
--   total_param_count: raw TrackFX_GetNumParams value

function CTX.scan_fx_params(tr, fx_idx)
  local params = {}
  local param_count = R_TrackFX_GetNumParams(tr, fx_idx)
  -- A stale FX handle (plugin removed mid-scan, track deleted) can make
  -- REAPER return nil / -1 instead of a real count. Without this guard
  -- the `param_count - 1` upper bound below and the log concat above
  -- would throw before we get a chance to report a clean failure.
  if type(param_count) ~= "number" or param_count <= 0 then
    return params, 0, 0, false
  end
  Log.line("SCAN", "scan_fx_params start: param_count=" .. param_count)

  -- Readback-lag detection: some VST3 plugins (e.g. Soundtoys) process param
  -- writes on the next audio cycle, so same-tick GetParamNormalized returns the
  -- pre-write value. If detected, we skip enum/range probing (which produces
  -- garbage data under lag) and return needs_deep_scan=true so callers can
  -- trigger a defer-paced deep scan that captures accurate data.
  --
  -- Test design:
  --  * Probe up to 3 params, skipping Bypass / MIDI CC / host-injected names.
  --    Bypass is host-handled (REAPER intercepts it), so it always responds
  --    synchronously even on plugins whose DSP params lag -- probing it alone
  --    would miss real lag (false negative observed on Decapitator).
  --  * Lag means readback returned the OLD value despite the write. Test as:
  --    |orig - probe_val| > 0.5 (the write is meaningfully far from orig) AND
  --    |readback - orig|  < 0.05 (readback stayed at orig).
  --    The naive |readback - probe_val| > 0.1 test catches enum/binary
  --    quantization and produces false positives.
  local needs_deep_scan = false
  if param_count > 0 then
    local probes_done = 0
    for pi = 0, math.min(param_count - 1, 20) do
      if probes_done >= 3 then break end
      local _, pnm = R_TrackFX_GetParamName(tr, fx_idx, pi, "")
      local skip_name = pnm == "Bypass"
        or pnm:match("^CC %d") or pnm:match("^MIDI CC")
        or pnm == "Channel Pressure" or pnm == "Poly Pressure"
        or pnm == "Pitch Bend" or pnm == "Program Change"
      if not skip_name then
        local orig = reaper.TrackFX_GetParamNormalized(tr, fx_idx, pi)
        local probe_val = (orig < 0.5) and 0.9 or 0.1
        reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, probe_val)
        local readback = reaper.TrackFX_GetParamNormalized(tr, fx_idx, pi)
        reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig)
        probes_done = probes_done + 1
        if math.abs(orig - probe_val) > 0.5
           and math.abs(readback - orig) < 0.05 then
          needs_deep_scan = true
          Log.line("SCAN", "lag_detect: pi=" .. pi .. " name=" .. pnm
            .. " orig=" .. str_format("%.4f", orig)
            .. " probe=" .. str_format("%.4f", probe_val)
            .. " readback=" .. str_format("%.4f", readback)
            .. " -> needs_deep_scan=true")
          break
        end
      end
    end
    if not needs_deep_scan then
      Log.line("SCAN", "lag_detect: " .. probes_done
        .. " params probed, no lag detected")
    end
  end

  -- If we already know this plugin needs a deep scan, skip the main loop:
  -- callers will replace these entries via put_plugin(... deep_results) once
  -- the coroutine-paced deep scan completes. Building ~80 throwaway entries
  -- here just burns API calls on a first-scan that's about to be overwritten.
  if needs_deep_scan then
    return {}, 0, param_count, true
  end

  -- max_group is tracked inline as we visit each param (see the
  -- group_num extraction below). Previously a separate post-loop walk
  -- re-called R_TrackFX_GetParamName for every param just to compute
  -- this -- doubling the API calls per scan on dense plugins.
  local max_group = 0

  for pi = 0, param_count - 1 do
    local _, param_nm = R_TrackFX_GetParamName(tr, fx_idx, pi, "")
    -- Skip MIDI CC automation parameters.
    if param_nm:match("^CC %d") or param_nm:match("^MIDI CC") then
      goto continue_scan
    end
    -- Skip MIDI message params injected by the host.
    if param_nm == "Channel Pressure" or param_nm == "Poly Pressure"
       or param_nm == "Pitch Bend" or param_nm == "Program Change" then
      goto continue_scan
    end
    -- Skip VST3 host-appended params (Bypass/Wet/Delta/Internal at the tail).
    if _is_vst3_tail(param_nm, pi) then
      local _, disp_chk = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
      disp_chk = disp_chk or ""
      if disp_chk == "normal" or disp_chk == "-" or disp_chk:match("^%d+$") then
        goto continue_scan
      end
    end
    -- Skip generic "Param N" / "Parameter N" with no useful display value.
    local _, disp = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
    disp = disp or ""
    if (param_nm:match("^Param %d+$") or param_nm:match("^Parameter %d+$"))
       and (disp == "" or disp:match("^[%d%.%%]*$")) then
      goto continue_scan
    end
    -- Detect repeating numbered groups. Keep groups 1-2 as reference; skip 3+.
    local group_num = param_nm:match("^%d+")
      or param_nm:match("(%d+) %a")
      or param_nm:match("%(Band (%d+)")
      or param_nm:match("Mod (%d+)")
      or param_nm:match("%s(%d+)$")
    -- Track max_group inline so the trailing re-walk over all params
    -- isn't needed. Captured before the > 2 skip so groups 3+ that get
    -- filtered out still count toward the "highest group" used by the
    -- truncation-note in CTX.format_fx_params.
    if group_num then
      local gn_n = tonumber(group_num)
      if gn_n and gn_n > max_group then max_group = gn_n end
    end
    if group_num and tonumber(group_num) > 2 then
      goto continue_scan
    end
    local val, mn, mx = R_TrackFX_GetParam(tr, fx_idx, pi)
    local norm = 0
    if mx ~= mn then norm = (val - mn) / (mx - mn) end
    -- Probe 21 evenly-spaced normalised values: 2-20 distinct display
    -- strings -> record as enum; otherwise capture display@0 / display@1
    -- so the model knows the API display range. The earlier early-return
    -- at "if needs_deep_scan then return ..." above guarantees
    -- needs_deep_scan is false here, so no `if not needs_deep_scan`
    -- wrapper is needed.
    local enum_list = nil
    local disp_at_min, disp_at_max = nil, nil
    local probe_seen, probe_order = {}, {}
    local orig_norm = reaper.TrackFX_GetParamNormalized(tr, fx_idx, pi)
    for pn = 0, 20 do
      local pv = pn / 20
      reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, pv)
      local _, pd = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
      if pn == 0  then disp_at_min = pd end
      if pn == 20 then disp_at_max = pd end
      if not probe_seen[pd] then
        probe_seen[pd] = true
        probe_order[#probe_order+1] = pd
      end
    end
    reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
    if #probe_order >= 2 and #probe_order <= 20 then
      enum_list = probe_order
    end
    local entry = {
      idx     = pi,
      name    = param_nm,
      default = tonumber(str_format("%.4f", norm)),
      display = disp,
    }
    if enum_list then entry.enum = enum_list end
    -- Store display range for continuous params so the model can detect
    -- API-vs-GUI display scale mismatches and compute normalized values.
    -- If min == max, the param is read-only / host-driven (e.g. Tempo
    -- reflecting project tempo) - the range would mislead the model.
    if not enum_list and disp_at_min and disp_at_max
       and disp_at_min ~= disp_at_max then
      entry.display_min = disp_at_min
      entry.display_max = disp_at_max
    end
    params[#params+1] = entry
    ::continue_scan::
  end

  -- max_group is now tracked inline within the main param loop above.

  -- Cap cached params to keep cache files and LLM context manageable.
  -- Main controls are at low indices; modulation/sequencer/slot params at
  -- higher indices are omitted. Use find_param at runtime for those.
  if #params > CFG.MAX_CACHED_PARAMS then
    local trimmed = {}
    for i = 1, CFG.MAX_CACHED_PARAMS do trimmed[i] = params[i] end
    params = trimmed
  end

  Log.line("SCAN", "scan_fx_params done: kept=" .. #params
    .. " max_group=" .. max_group
    .. " needs_deep_scan=" .. tostring(needs_deep_scan))
  return params, max_group, param_count, needs_deep_scan
end

-- =============================================================================
-- CTX.scan_fx_params_deep  (coroutine, defer-paced)
-- =============================================================================
-- Same filters + probe strategy as scan_fx_params, but yields one REAPER frame
-- between each param write and readback so VST3 plugins with one-cycle
-- readback lag (Soundtoys etc.) return accurate enum/range data. Intended to
-- run inside a coroutine resumed from loop().
--
-- Returns (via coroutine end): params_list, max_group, total_param_count

local function _fx_param_filter_skip(param_nm, disp)
  -- REAPER's TrackFX_GetFormattedParamValue can return nil for plugins
  -- that don't supply a formatted value (some VST3 host params, certain
  -- internal slots). Coerce so callers that pattern-match on disp aren't
  -- on the hook for the guard.
  disp = disp or ""
  if param_nm:match("^CC %d") or param_nm:match("^MIDI CC") then return true end
  if param_nm == "Channel Pressure" or param_nm == "Poly Pressure"
     or param_nm == "Pitch Bend" or param_nm == "Program Change" then
    return true
  end
  if (param_nm:match("^Param %d+$") or param_nm:match("^Parameter %d+$"))
     and (disp == "" or disp:match("^[%d%.%%]*$")) then
    return true
  end
  local group_num = param_nm:match("^%d+")
    or param_nm:match("(%d+) %a")
    or param_nm:match("%(Band (%d+)")
    or param_nm:match("Mod (%d+)")
    or param_nm:match("%s(%d+)$")
  if group_num and tonumber(group_num) > 2 then return true end
  return false
end

function CTX.scan_fx_params_deep_body(tr, fx_idx)
  local params = {}
  local max_group = 0
  local param_count = R_TrackFX_GetNumParams(tr, fx_idx)
  -- See CTX.scan_fx_params for the same guard's rationale; a stale FX
  -- handle here would crash on the log concat and the `0, param_count - 1`
  -- loop below.
  if type(param_count) ~= "number" or param_count <= 0 then
    return params, 0, 0
  end
  Log.line("DEEP_SCAN", "scan_fx_params_deep start: param_count=" .. param_count)

  -- Release the UI-refresh lock that fx_inspect_load held. Holding
  -- PreventUIRefresh(+1) across many defer cycles can put REAPER into
  -- a bad internal state and, combined with rapid VST3 param writes,
  -- has produced hard crashes. The cleanup callbacks will not call
  -- PreventUIRefresh(-1) again, since we released it here.
  reaper.PreventUIRefresh(-1)
  deep_scan._ui_refresh_released = true

  -- Helper: confirm the track pointer + plugin slot are still alive.
  -- REAPER invalidates MediaTrack pointers on project reloads, track
  -- deletions, and some undo actions. Touching a dead pointer with
  -- TrackFX_* is a segfault.
  local function _alive()
    if not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return false end
    if R_TrackFX_GetNumParams(tr, fx_idx) <= 0 then return false end
    return true
  end

  for pi = 0, param_count - 1 do
    if deep_scan.cancel_req then return params, 0, param_count end
    if not _alive() then
      Log.line("DEEP_SCAN", "track/fx invalidated at pi=" .. pi .. " -- aborting")
      deep_scan.cancel_req = true
      return params, 0, param_count
    end
    -- Cap at probe time (not trim time) so giant plugins with 500+ params
    -- don't spend minutes probing entries we'd just drop on the floor.
    if #params >= CFG.MAX_CACHED_PARAMS then
      Log.line("DEEP_SCAN", "reached MAX_CACHED_PARAMS cap at pi=" .. pi .. ", stopping probe")
      break
    end

    -- Grab the name up front for filter checks + heavy-selector match.
    local _, _probe_nm = R_TrackFX_GetParamName(tr, fx_idx, pi, "")

    -- Track the highest group number seen, captured before the filter
    -- skip below so groups 3+ that get dropped still inform max_group
    -- (used by CTX.format_fx_params for the "shown groups 1-2 of N"
    -- truncation note). Replaces a trailing per-param re-walk.
    do
      local _gn = _probe_nm:match("^%d+")
        or _probe_nm:match("(%d+) %a")
        or _probe_nm:match("%(Band (%d+)")
        or _probe_nm:match("Mod (%d+)")
        or _probe_nm:match("%s(%d+)$")
      if _gn then
        local _gn_n = tonumber(_gn)
        if _gn_n and _gn_n > max_group then max_group = _gn_n end
      end
    end

    -- Apply the same name/group filter the shallow scan uses (and the deep-
    -- scan progress estimator already uses). Without this, repeating numbered
    -- groups (Pro-C 3's Side Chain EQ Bands 3-6, multi-mod plugins' Mod 3+)
    -- get fully probed even though shallow scan dropped them -- a 6-band
    -- plugin wastes ~4 bands x ~9 params x 21 probes = ~750 probes here.
    -- Saves ~50s of wall time on Pro-C 3-class plugins.
    local _, _probe_disp = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
    if _fx_param_filter_skip(_probe_nm, _probe_disp) then
      goto continue_deep
    end

    -- Fast-path: Bypass is always a binary Off/On enum, host-handled by
    -- REAPER. Synthesize the entry directly to skip ~21 yield cycles
    -- (~1.4s + plugin GUI flicker) of redundant sweeping.
    if _probe_nm == "Bypass" then
      local val, mn, mx = R_TrackFX_GetParam(tr, fx_idx, pi)
      local norm = 0
      if mx ~= mn then norm = (val - mn) / (mx - mn) end
      local _, d = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
      params[#params+1] = {
        idx     = pi,
        name    = _probe_nm,
        default = tonumber(str_format("%.4f", norm)),
        display = d,
        enum    = { "Off", "On" },
      }
      Log.line("DEEP_SCAN", "pi=" .. pi .. " name=Bypass -- fast-path synthesized")
      goto continue_deep
    end

    -- Heavy-selector candidate: params whose values *might* trigger expensive
    -- DSP reinit (impulse-response reload, sample-library swap, algorithm
    -- rewire). Name pattern is a hint, not a verdict -- some matches are
    -- lightweight (Decapitator's Style is just a saturation curve), others
    -- can hard-crash the plugin under rapid sweep (EchoBoy's Style swaps
    -- tape IRs). A single isolated write is safe on any plugin (the user
    -- changes Style manually all the time without crash); only RAPID writes
    -- queue faster than the asset loader can process and trip the race.
    --
    -- Strategy: do ONE calibration write, watch how long the plugin takes
    -- to settle (display changes from orig). Light -> fall through to full
    -- sweep. Heavy -> cooldown wait, restore orig with another wait, record
    -- bare entry. At most two writes spaced ~1s apart -- never a queue.
    local low_nm = _probe_nm:lower()
    local is_heavy_candidate =
         low_nm == "style"     or low_nm:match("^style$")
      or low_nm == "algorithm" or low_nm:match("algorithm")
      or low_nm == "engine"    or low_nm:match("^engine$")
      or low_nm == "character" or low_nm:match("^character$")
      or low_nm == "preset"    or low_nm:match("preset")
      or low_nm == "model"     or low_nm:match("^model$")
    if is_heavy_candidate then
      local CALIBRATION_MAX_YIELDS = 30  -- ~1s at 30fps
      local cal_orig = reaper.TrackFX_GetParamNormalized(tr, fx_idx, pi)
      local _, cal_orig_disp = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
      local cal_probe = (cal_orig < 0.5) and 1.0 or 0.0
      Log.line("DEEP_SCAN", "pi=" .. pi .. " name=" .. _probe_nm
        .. " -- calibrating (orig_disp=" .. tostring(cal_orig_disp)
        .. " probe=" .. cal_probe .. ")")
      reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, cal_probe)
      local settled = false
      for _try = 1, CALIBRATION_MAX_YIELDS do
        if deep_scan.cancel_req then
          if _alive() then
            reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, cal_orig)
          end
          return params, 0, param_count
        end
        coroutine.yield()
        if not _alive() then
          Log.line("DEEP_SCAN", "track/fx invalidated during calibration -- aborting")
          deep_scan.cancel_req = true
          return params, 0, param_count
        end
        local _, dnow = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
        if dnow ~= cal_orig_disp then settled = true; break end
      end

      if not settled then
        -- Heavy DSP detected. Cool down BEFORE restoring orig so the
        -- in-progress load can finish first (avoids stacking two heavy
        -- loads back-to-back). Then write orig and wait again. Bare entry.
        Log.line("DEEP_SCAN", "pi=" .. pi .. " name=" .. _probe_nm
          .. " -- HEAVY (no settle in " .. CALIBRATION_MAX_YIELDS
          .. " yields), cooling down + synthesizing bare entry")
        -- Estimator budgeted 21 probes for this param; the heavy path skips
        -- the standard sweep without incrementing probes_done, so retract
        -- the budget here to keep the progress bar denominator honest.
        deep_scan.total_probes = math_max(0, deep_scan.total_probes - 21)
        for _ = 1, CALIBRATION_MAX_YIELDS do
          if deep_scan.cancel_req or not _alive() then break end
          coroutine.yield()
        end
        if _alive() then
          reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, cal_orig)
          for _ = 1, CALIBRATION_MAX_YIELDS do
            if deep_scan.cancel_req or not _alive() then break end
            coroutine.yield()
          end
        end
        local val, mn, mx = R_TrackFX_GetParam(tr, fx_idx, pi)
        local norm = 0
        if mx ~= mn then norm = (val - mn) / (mx - mn) end
        params[#params+1] = {
          idx     = pi,
          name    = _probe_nm,
          default = tonumber(str_format("%.4f", norm)),
          display = cal_orig_disp,
          -- Intentionally no enum / display_min / display_max: LLM should
          -- find_param at runtime if it needs a specific value.
        }
        goto continue_deep
      end

      -- Light: restore orig, give one frame to settle, then fall through
      -- to the standard sweep below.
      reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, cal_orig)
      coroutine.yield()
      Log.line("DEEP_SCAN", "pi=" .. pi .. " name=" .. _probe_nm
        .. " -- calibration ok (light), proceeding with full sweep")
    end

    local _, param_nm = R_TrackFX_GetParamName(tr, fx_idx, pi, "")

    -- Deferred disp read: fetch current display before any filter so we can
    -- pass it to the generic-param filter. Peek without yielding.
    local _, disp = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
    disp = disp or ""

    -- VST3 host-appended tail params (Bypass/Wet/Delta/Internal).
    if _is_vst3_tail(param_nm, pi) then
      if disp == "normal" or disp == "-" or disp:match("^%d+$") then
        goto continue_deep
      end
    end

    if _fx_param_filter_skip(param_nm, disp) then goto continue_deep end

    -- Per-param log breadcrumb so a crash mid-probe tells us exactly
    -- which param index the plugin died on. Logged AFTER filters so the
    -- log only shows params that actually get swept.
    Log.line("DEEP_SCAN", "probing pi=" .. pi .. " name=" .. tostring(_probe_nm))

    -- Standard 21-probe sweep, yielding between write and readback so the
    -- plugin has a full frame to propagate the set before we read the
    -- formatted display. Orig norm is restored after probing.
    do
      local val, mn, mx = R_TrackFX_GetParam(tr, fx_idx, pi)
      local norm = 0
      if mx ~= mn then norm = (val - mn) / (mx - mn) end

      local orig_norm = reaper.TrackFX_GetParamNormalized(tr, fx_idx, pi)
      local probe_seen, probe_order = {}, {}
      local disp_at_min, disp_at_max = nil, nil

      -- Heavy-candidate pacing: instead of a fixed 2-frame gap between probes
      -- (which queues IR loads faster than the plugin's asset loader can
      -- process, crashing REAPER on e.g. EchoBoy Style at ~21 swaps), wait
      -- after each write until the display has been stable for
      -- STABLE_FRAMES_HEAVY consecutive frames or the hard cap is reached.
      -- Each IR/preset finishes loading before the next probe fires.
      -- If 3 probes in a row hit the cap (display never stabilizes), bail
      -- out for this param -- the plugin is misbehaving and no amount of
      -- extra probing will produce trustworthy enum data.
      local STABLE_FRAMES_HEAVY   = 3   -- must match N frames in a row to call "settled"
      local MAX_YIELDS_HEAVY      = 30  -- ~1 second cap per probe at 30fps
      local MAX_CONSEC_STUCK      = 3   -- abort-sweep threshold
      local heavy_sweep_aborted   = false
      local consec_stuck          = 0

      for pn = 0, 20 do
        if heavy_sweep_aborted then break end
        if deep_scan.cancel_req then
          if _alive() then
            reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
          end
          return params, 0, param_count
        end
        if not _alive() then
          Log.line("DEEP_SCAN", "track/fx invalidated mid-probe -- aborting")
          deep_scan.cancel_req = true
          return params, 0, param_count
        end
        local pv = pn / 20
        reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, pv)
        if is_heavy_candidate then
          -- Settle-wait: loop yielding until display stabilizes.
          local last_disp, stable = nil, 0
          local settled = false
          for _y = 1, MAX_YIELDS_HEAVY do
            coroutine.yield()
            if deep_scan.cancel_req then
              if _alive() then
                reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
              end
              return params, 0, param_count
            end
            if not _alive() then
              Log.line("DEEP_SCAN", "track/fx invalidated during settle-wait -- aborting")
              deep_scan.cancel_req = true
              return params, 0, param_count
            end
            local _, cur = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
            if cur == last_disp then
              stable = stable + 1
              if stable >= STABLE_FRAMES_HEAVY then
                settled = true
                break
              end
            else
              stable = 0
              last_disp = cur
            end
          end
          if settled then
            consec_stuck = 0
          else
            consec_stuck = consec_stuck + 1
            if consec_stuck >= MAX_CONSEC_STUCK then
              Log.line("DEEP_SCAN", "pi=" .. pi .. " name=" .. _probe_nm
                .. " -- " .. MAX_CONSEC_STUCK
                .. " consecutive probes never settled, aborting sweep (bare entry will be synthesized)")
              heavy_sweep_aborted = true
              -- Refund the remaining budget so the progress bar stays honest.
              -- pn is the probe that just failed (probes_done was NOT yet
              -- incremented for it), so `21 - pn` covers this probe plus the
              -- 20-pn still-untried iterations.
              local remaining = 21 - pn
              if remaining > 0 then
                deep_scan.total_probes = math_max(0, deep_scan.total_probes - remaining)
              end
              break
            end
          end
        else
          coroutine.yield()  -- wait 1 frame
          coroutine.yield()  -- extra frame: some VST3s crash under rapid-fire
                             -- writes; giving two frames between write+read
                             -- lets audio thread process at least one buffer.
        end
        if not _alive() then
          Log.line("DEEP_SCAN", "track/fx invalidated after yield -- aborting")
          deep_scan.cancel_req = true
          return params, 0, param_count
        end
        local _, pd = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
        if pn == 0  then disp_at_min = pd end
        if pn == 20 then disp_at_max = pd end
        if not probe_seen[pd] then
          probe_seen[pd] = true
          probe_order[#probe_order+1] = pd
        end
        deep_scan.probes_done = deep_scan.probes_done + 1
      end

      -- Aborted heavy sweep: restore orig and synthesize bare entry, then
      -- skip the rest of this iteration (endpoint check / extended pass /
      -- normal record).
      if heavy_sweep_aborted then
        if _alive() then
          reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
          for _ = 1, MAX_YIELDS_HEAVY do
            if deep_scan.cancel_req or not _alive() then break end
            coroutine.yield()
          end
        end
        local bare_val, bare_mn, bare_mx = R_TrackFX_GetParam(tr, fx_idx, pi)
        local bare_norm = 0
        if bare_mx ~= bare_mn then bare_norm = (bare_val - bare_mn) / (bare_mx - bare_mn) end
        local _, bare_disp = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
        params[#params+1] = {
          idx     = pi,
          name    = _probe_nm,
          default = tonumber(str_format("%.4f", bare_norm)),
          display = bare_disp,
        }
        goto continue_deep
      end

      -- Determine whether endpoints look numeric (real range) or text
      -- (enum/preset list). Match requires the display to be a number with
      -- optional sign/decimal and an optional unit suffix composed of
      -- letters, spaces, slashes, or percent signs. This correctly rejects
      -- tokens like "1/64th" or "1/2 note" (digits embedded in unit) which
      -- are enum entries, not ranges.
      local function _looks_numeric(s)
        if not s or s == "" then return false end
        local clean = s:gsub(",", ""):match("^%s*(.-)%s*$")
        return clean:match("^[-+]?%d*%.?%d+[%a%s/%%]*$") ~= nil
      end
      local endpoints_numeric = _looks_numeric(disp_at_min) and _looks_numeric(disp_at_max)

      -- If endpoints are non-numeric, this is almost certainly an enum/preset
      -- list, possibly with more than 21 distinct values (e.g. EchoBoy Style
      -- has ~30 presets). Do a second interleaved pass at midpoints between
      -- the first-pass positions to capture more distinct values.
      --
      -- SAFETY GATE: heavy-named params (style/algorithm/engine/...) DO NOT
      -- get the extended pass. Calibration only measures display latency, not
      -- burst safety -- EchoBoy Style calibrates as "light" yet crashes at
      -- 41 IR-swaps. Cap heavy params at the empirically-safe 21 probes; the
      -- resulting enum is flagged `enum_partial` below so the model knows to
      -- use the paced runtime helper if the user's target is not in the cache.
      --
      -- RICHNESS GATE: also skip the extended pass for small enums. If the
      -- first 21 probes surfaced fewer than 15 distinct values, the enum is
      -- almost certainly small (Mode=4, HighSlope=2, PrimeNumbers=2, etc.)
      -- and the first pass already captured everything. The second pass
      -- would just re-observe the same handful of values at a cost of ~2s
      -- per param. Only extend when the first pass hit the "rich" threshold,
      -- suggesting there are more distinct values to discover.
      if not endpoints_numeric and not is_heavy_candidate
         and #probe_order >= 15 then
        -- Extended pass commits now -- grow the progress total so the bar
        -- tracks real work. Estimator only budgeted the first pass.
        deep_scan.total_probes = deep_scan.total_probes + 20
        for pn = 0, 19 do
          if deep_scan.cancel_req then
            if _alive() then
              reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
            end
            return params, 0, param_count
          end
          if not _alive() then
            Log.line("DEEP_SCAN", "track/fx invalidated mid-probe2 -- aborting")
            deep_scan.cancel_req = true
            return params, 0, param_count
          end
          local pv = (2 * pn + 1) / 40  -- midpoint between pn/20 and (pn+1)/20
          reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, pv)
          coroutine.yield()
          coroutine.yield()
          if not _alive() then
            Log.line("DEEP_SCAN", "track/fx invalidated after yield2 -- aborting")
            deep_scan.cancel_req = true
            return params, 0, param_count
          end
          local _, pd = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
          if not probe_seen[pd] then
            probe_seen[pd] = true
            probe_order[#probe_order+1] = pd
          end
          deep_scan.probes_done = deep_scan.probes_done + 1
        end
      end

      reaper.TrackFX_SetParamNormalized(tr, fx_idx, pi, orig_norm)
      coroutine.yield()  -- one more frame so the restore doesn't bleed into the next read

      -- Post-restore display for the entry (after one-frame settle).
      local _, disp_after = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
      local entry = {
        idx     = pi,
        name    = param_nm,
        default = tonumber(str_format("%.4f", norm)),
        display = disp_after,
      }
      -- Classify by endpoint content, not just probe count:
      --   numeric endpoints           -> range (display_min/max)
      --   non-numeric, 2..64 distinct -> enum (full preset list)
      --   else if distinct endpoints  -> fallback string range (rare)
      --   else                        -> plain (no annotation; e.g. host-driven)
      if endpoints_numeric then
        if disp_at_min ~= disp_at_max then
          entry.display_min = disp_at_min
          entry.display_max = disp_at_max
        end
      elseif #probe_order >= 2 and #probe_order <= 64 then
        entry.enum = probe_order
        -- Heavy params capped at 21 probes may have more enum values than we
        -- captured. Mark partial so the model falls back to the paced runtime
        -- helper when the target isn't among the cached entries.
        if is_heavy_candidate then entry.enum_partial = true end
      elseif disp_at_min and disp_at_max and disp_at_min ~= disp_at_max then
        entry.display_min = disp_at_min
        entry.display_max = disp_at_max
      end
      params[#params+1] = entry
    end
    ::continue_deep::
  end

  -- max_group tracked inline within the param probe loop above.
  -- No post-loop trim needed: the loop body breaks at `#params >=
  -- MAX_CACHED_PARAMS` (probe-time cap, not trim-time), so by the time
  -- we get here #params is already <= the cap.

  Log.line("DEEP_SCAN", "scan_fx_params_deep done: kept=" .. #params
    .. " max_group=" .. max_group)
  return params, max_group, param_count
end

-- Estimate probe count for progress UI. Heavy-named params get 21 probes
-- (capped for burst-safety). Non-heavy params MAY get an extra 20-probe
-- interleaved pass if their endpoints are non-numeric; we can't tell in
-- advance, so we budget 41 for non-heavy to guarantee the progress bar
-- never goes over 100%. (Numeric non-heavy params finish faster than the
-- budget, so the bar simply completes early -- acceptable.)
local function _estimate_deep_probes(tr, fx_idx)
  local n = R_TrackFX_GetNumParams(tr, fx_idx)
  -- A stale FX handle could return nil / -1; the `0, n - 1` loop below
  -- would then crash on the comparison. Returning 0 makes the caller
  -- treat the budget as "no work to do", which is correct -- the scan
  -- body's matching guard will refuse to run anyway.
  if type(n) ~= "number" or n <= 0 then return 0 end
  local total = 0
  local kept = 0
  for pi = 0, n - 1 do
    local _, nm = R_TrackFX_GetParamName(tr, fx_idx, pi, "")
    local _, d  = R_TrackFX_GetFormattedParamValue(tr, fx_idx, pi, "")
    d = d or ""
    local skip = _fx_param_filter_skip(nm, d)
    -- Mirror the VST3-tail filter that's inlined in scan_fx_params so our
    -- progress total matches the probes actually performed.
    if not skip and _is_vst3_tail(nm, pi) then
      if d == "normal" or d == "-" or d:match("^%d+$") then skip = true end
    end
    if not skip then
      kept = kept + 1
      -- Bypass is fast-path synthesized in scan_fx_params_deep_body (0 probes).
      -- Exclude it from the budget so the progress bar doesn't overcount.
      if nm ~= "Bypass" then
        -- Base budget: the guaranteed first pass (21 probes at pn=0..20).
        -- The optional +20 extended pass is added dynamically inside the deep
        -- scan body at the moment it commits to running, so the total stays
        -- honest whether or not the extension triggers.
        total = total + 21
      end
      if kept >= CFG.MAX_CACHED_PARAMS then break end  -- matches the probe-time cap in scan_fx_params_deep_body
    end
  end
  return total
end

-- Start a deep scan. The temp track + plugin must already be loaded and
-- passed in; this function does NOT create the track. `on_complete` is called
-- with (params_list, max_group, total_param_count) when the coroutine
-- finishes. `on_cancel` is called with no args if the user cancels or an
-- error occurs (caller is responsible for cleaning up the temp track in both
-- success and cancel paths).
function CTX.start_deep_scan(opts)
  if deep_scan.active then
    Log.line("DEEP_SCAN", "start_deep_scan: already active, ignoring")
    return false
  end
  -- Validate inputs up front. Without these, the coroutine body would crash
  -- on first resume with cryptic nil-deref errors and the scan would still
  -- have been marked active, blocking future scans until manual reset.
  if not opts or not opts.tr or not opts.fx_idx then
    Log.line("DEEP_SCAN", "start_deep_scan: missing tr/fx_idx, ignoring")
    return false
  end
  -- Build everything as locals first; commit to the deep_scan table only
  -- after every step succeeds. Previously the function set deep_scan.active
  -- early then computed total_probes / built the coroutine -- if any of
  -- those threw, the scan was wedged at active=true with coro=nil, and
  -- pump_deep_scan would silently no-op forever.
  local ok_est, est = pcall(_estimate_deep_probes, opts.tr, opts.fx_idx)
  if not ok_est then
    Log.line("DEEP_SCAN", "estimate_deep_probes error: " .. tostring(est))
    return false
  end
  local co = coroutine.create(function()
    return CTX.scan_fx_params_deep_body(opts.tr, opts.fx_idx)
  end)
  -- Single commit point. Order: clear cancel flag, populate fields, then
  -- flip active=true LAST so pump_deep_scan can never observe a half-built
  -- state (active=true, coro=nil).
  deep_scan.cancel_req   = false
  deep_scan.tr           = opts.tr
  deep_scan.fx_idx       = opts.fx_idx
  deep_scan.identifier   = opts.identifier
  deep_scan.search_names = opts.search_names
  deep_scan.origin       = opts.origin or "chat"
  deep_scan.on_complete  = opts.on_complete
  deep_scan.on_cancel    = opts.on_cancel
  deep_scan.started_at   = time_precise()
  deep_scan.probes_done  = 0
  deep_scan.total_probes = est or 0
  deep_scan.coro         = co
  deep_scan.active       = true
  Log.line("DEEP_SCAN", "started: " .. (opts.identifier or "?")
    .. " est_probes=" .. deep_scan.total_probes
    .. " origin=" .. deep_scan.origin)
  -- Auto-scroll the chat: the explainer + progress block grows the status
  -- area by a few lines, which would otherwise push the new content below
  -- the visible area without moving the viewport.
  if deep_scan.origin == "chat" then S.scroll_to_bottom = true end
  return true
end

-- Ask the running deep scan to stop at its next yield point. The coroutine
-- body checks deep_scan.cancel_req and returns early.
function CTX.cancel_deep_scan()
  if not deep_scan.active then return end
  Log.line("DEEP_SCAN", "cancel requested")
  deep_scan.cancel_req = true
end

-- Resume the deep-scan coroutine one step. Called from loop() each frame.
function CTX.pump_deep_scan()
  if not deep_scan.active or not deep_scan.coro then return end
  local co = deep_scan.coro
  local ok, a, b, c = coroutine.resume(co)
  if not ok then
    Log.line("DEEP_SCAN", "coroutine error: " .. tostring(a))
    local cb = deep_scan.on_cancel
    deep_scan.active = false
    deep_scan.coro   = nil
    if cb then cb(tostring(a)) end
    return
  end
  if coroutine.status(co) == "dead" then
    -- a/b/c = params_list, max_group, total_param_count (from return)
    local cancelled = deep_scan.cancel_req
    local cb_complete = deep_scan.on_complete
    local cb_cancel   = deep_scan.on_cancel
    deep_scan.active = false
    deep_scan.coro   = nil
    if cancelled then
      if cb_cancel then cb_cancel("cancelled") end
    else
      if cb_complete then cb_complete(a or {}, b or 0, c or 0) end
    end
  end
end

-- Derive the GetByName-safe "display name" form of an EnumInstalledFX
-- identifier. REAPER reports two distinct name spaces for FX: the registry
-- identifier (what TrackFX_AddByName accepts -- e.g. "VST3: Manipulator
-- (Polyverse Music)") and the loaded-instance display name (what
-- TrackFX_GetByName matches against, what TrackFX_GetFXName returns --
-- e.g. just "Manipulator"). Using the long identifier with GetByName
-- silently fails -- the model previously hit this path repeatedly.
-- Strips the format prefix and the trailing vendor suffix.
local function _derive_display_name(identifier)
  if not identifier or identifier == "" then return identifier end
  local s = identifier:gsub("^[%w]+:%s*", "")     -- "VST3: " / "VST: " / "AU: " / "CLAP: " / "JS: "
  s = s:gsub("%s*%([^)]+%)%s*$", "")              -- " (Polyverse Music)"
  return s
end

-- Format scanned param data (table) into the text format the LLM expects.
-- Used by both fx_inspect and preferred_plugins context buckets.
function CTX.format_fx_params(identifier, params_list, max_group, search_names, is_inspect)
  local lines = {}
  local display_name = _derive_display_name(identifier)
  if is_inspect then
    lines[#lines+1] = "FX INSPECT (" .. tbl_concat(search_names or {}, ", ") .. "):"
    lines[#lines+1] = "AddByName identifier (use with TrackFX_AddByName): " .. identifier
    if display_name and display_name ~= identifier then
      lines[#lines+1] = "GetByName display name (use with TrackFX_GetByName / TrackFX_GetCount loops): "
        .. display_name
      lines[#lines+1] = "WARNING: TrackFX_GetByName matches against the display name, NOT the AddByName identifier. Passing the long identifier with the vendor suffix WILL return -1 even when the plugin is loaded."
    end
    lines[#lines+1] = "IMPORTANT: Use the EXACT parameter indices [N] below. Do NOT use find_param to re-discover them."
    lines[#lines+1] = "Apply the DECIDE FIRST flowchart in your instructions (prompt_bundle:plugin) per param. Include helper definitions (find_param, set_param_display, set_param_enum, set_param_enum_paced) ONLY if your script actually calls them."
  else
    lines[#lines+1] = "AddByName identifier: " .. identifier
    if display_name and display_name ~= identifier then
      lines[#lines+1] = "GetByName display name: " .. display_name
    end
  end
  lines[#lines+1] = ""
  for _, p in ipairs(params_list) do
    -- Display value first (human-readable), normalized in brackets.
    if p.enum then
      local partial_tag = p.enum_partial and "  [partial]" or ""
      lines[#lines+1] = str_format("  [%d] %s: %s  [norm: %.4f]  [enum: %s]%s",
        p.idx, p.name, p.display, p.default, tbl_concat(p.enum, ", "), partial_tag)
    elseif p.display_min and p.display_max then
      lines[#lines+1] = str_format("  [%d] %s: %s  [norm: %.4f]  [range: %s..%s]",
        p.idx, p.name, p.display, p.default, p.display_min, p.display_max)
    else
      lines[#lines+1] = str_format("  [%d] %s: %s  [norm: %.4f]",
        p.idx, p.name, p.display, p.default)
    end
  end
  if max_group and max_group > 2 then
    lines[#lines+1] = str_format(
      "(Bands/groups 3-%d follow the same parameter pattern as 1-2. "
      .. "Use the same param names with the group number replaced.)", max_group)
  end
  -- Note if the param list was capped during scanning.
  if #params_list >= 80 then
    lines[#lines+1] = "(Additional modulation/sequencer params exist beyond this list. "
      .. "Use find_param at runtime to access them.)"
  end
  return tbl_concat(lines, "\n")
end

-- =============================================================================
-- CTX.fx_inspect  (on-demand scoped bucket - two-phase, async)
-- =============================================================================
-- Temporarily loads a plugin to discover its parameter names, indices, and
-- default display values. Used when the model needs to configure a third-party
-- plugin it has no cached metadata for.
--
-- Phase 1 (fx_inspect_load): searches installed plugins, inserts a temp track
-- at the end of the track list, and adds the best-matching plugin. Phase 2
-- (params read + cleanup) is handled inline in finalize_context so the
-- shallow-vs-deep-scan branch can share state with the rest of the turn.

function CTX.fx_inspect_load(search_names)
  if not search_names or #search_names == 0 then
    return nil, nil, nil, "fx_inspect requires a plugin name to search for."
  end
  Log.line("FX_INSPECT", "fx_inspect_load: search=" .. tbl_concat(search_names, ", "))

  -- Reuse installed_fx to find matching identifiers.
  local fl_content, fl_result = CTX.installed_fx(search_names)
  if not fl_content or fl_result == 0 then
    return nil, nil, nil, "No installed plugins matched: "
      .. tbl_concat(search_names, ", ")
      .. ". Ask the user for the exact name as it appears in their FX browser."
  end

  -- Pick the best match: prefer VST3, then CLAP, then first overall.
  -- installed_fx wraps each entry as `  - `VST3: Name`` (markdown bullet +
  -- backticks) for anti-hallucination; strip that before format-priority
  -- matching so TrackFX_AddByName receives the bare identifier.
  local best_id, first_id = nil, nil
  for line in fl_content:gmatch("[^\n]+") do
    local id = line:match("^%s*%-%s*`(.-)`%s*$")
    if id then
      if not first_id then first_id = id end
      if not best_id and id:find("^VST3:") then best_id = id end
      if not best_id and id:find("^CLAP:") then best_id = id end
    end
  end
  best_id = best_id or first_id
  if not best_id then
    return nil, nil, nil, "Could not determine plugin identifier from search results."
  end

  -- Check the FX cache. If this plugin is already cached and the param count
  -- hasn't changed (proxy for version updates), return cached data directly.
  local cached = FXCache.get_plugin(best_id)
  if cached and cached.params then
    Log.line("FX_INSPECT", "cache HIT: " .. best_id
      .. " (" .. #cached.params .. " params"
      .. (cached.needs_deep_scan and ", needs_deep_scan" or "") .. ")")
    -- Return nil track (no temp track needed), nil fx, identifier, nil error, cached data.
    return nil, nil, best_id, nil, cached
  end
  Log.line("FX_INSPECT", "cache MISS: " .. best_id .. " -- scanning")

  -- Insert temp track at end, add plugin. The setup block is closed before
  -- returning to REAPER so the later deferred reader does not inherit it.
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local track_count = R_CountTracks(0)
  reaper.InsertTrackAtIndex(track_count, false)
  local tmp_tr = R_GetTrack(0, track_count)
  if not tmp_tr then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: fx_inspect (failed)", 0)
    return nil, nil, nil, "Failed to create temporary track for plugin inspection."
  end

  -- Hide from TCP and mixer so user doesn't see it flash.
  reaper.SetMediaTrackInfo_Value(tmp_tr, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(tmp_tr, "B_SHOWINMIXER", 0)

  local fx_idx = reaper.TrackFX_AddByName(tmp_tr, best_id, false, -1)
  if fx_idx < 0 then
    reaper.DeleteTrack(tmp_tr)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: fx_inspect (failed)", 0)
    return nil, nil, nil, "Failed to load plugin: " .. best_id
  end

  -- Hide the plugin UI (don't flash a window).
  reaper.TrackFX_Show(tmp_tr, fx_idx, 2)  -- 2 = hide floating window

  -- Do not leave the undo block open while the caller waits for plugin
  -- initialization on later defer ticks. Cleanup deletes the temp track later;
  -- this flags=0 block discards the setup work from the user's undo history.
  reaper.Undo_EndBlock("ReaAssist: fx_inspect load", 0)
  return tmp_tr, fx_idx, best_id, nil, nil, false
end

-- =============================================================================
-- CTX.preferred_plugins  (on-demand scoped bucket)
-- =============================================================================
-- Reads the unified JSON cache and returns parameter data for the preferred
-- plugins matching the requested type keys (e.g. {"eq", "reverb"}).
-- Falls back to plugin_ref data when no preferred plugin is configured.
--
-- filter_types: list of type key strings (e.g. {"eq", "compressor"}).
--               If empty/nil, returns an error asking for specific types.

function CTX.preferred_plugins(filter_types)
  if not filter_types or #filter_types == 0 then
    return "PREFERRED PLUGINS: (error: no plugin type specified -- "
      .. "use preferred_plugins:eq or preferred_plugins:compressor, reverb)"
  end

  -- Read from the unified JSON cache.
  local cache = FXCache.load()
  local pref_types = cache.preferred_types or {}
  -- ExtState is process-shared and always current, so consumers read
  -- the dev_hide_fabfilter flag directly here rather than mirroring it
  -- in a prefs field that could go stale if the dev_signal ever missed.
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"

  -- Build output for only the requested types. Resolve aliases first.
  -- When a type has no preferred plugin set, do NOT silently fall back to
  -- curated data -- that bypasses the resolve popup and silently commits
  -- the user to a stock choice they never picked. Instead return a hint
  -- that tells the model to emit resolve:<type>, which fires the popup.
  local out = {}
  local matched = 0
  local no_pref_types = {}
  local pp_aliases = pref_plugins.alias_lookup()
  for _, type_key in ipairs(filter_types) do
    local k = type_key:lower():match("^%s*(.-)%s*$") or ""
    k = pp_aliases[k] or k
    local identifier = pref_types[k]
    local original_identifier = identifier
    if identifier and identifier ~= ""
       and FXCache and FXCache.canonicalize_identifier then
      identifier = FXCache.canonicalize_identifier(k, identifier)
    end
    -- Dev-only: treat FabFilter entries as "no pref set" when the hide
    -- flag is on, so the model emits resolve:<type> and fires the popup
    -- the dev wants to exercise.
    if hide_ff and _is_fabfilter_ident(identifier) then
      identifier = nil
    end
    if identifier and identifier ~= "" then
      local plugin_data = cache.plugins[identifier]
        or (original_identifier and cache.plugins[original_identifier])
      matched = matched + 1
      out[#out+1] = k .. ": " .. identifier
      if plugin_data and plugin_data.params then
        if S._fx_cache_events then
          local t = S._fx_cache_events
          t.hit = t.hit or {}
          t.hit[#t.hit+1] = identifier
        end
        out[#out+1] = CTX.format_fx_params(
          identifier, plugin_data.params, plugin_data.max_group, nil, false)
      end
      out[#out+1] = ""
    else
      no_pref_types[#no_pref_types+1] = k
    end
  end

  -- Types with no preferred plugin: emit an explicit directive telling the
  -- model to re-request via resolve:<type>. DO NOT load plugins here.
  if #no_pref_types > 0 then
    local directives = {}
    for _, tk in ipairs(no_pref_types) do
      directives[#directives+1] =
        "  " .. tk .. ": NO PREFERRED PLUGIN SET. Emit "
        .. "<context_needed>resolve:" .. tk .. "</context_needed> so the "
        .. "user can pick one via the popup. Do NOT call TrackFX_AddByName "
        .. "with a generic type name."
    end
    if matched == 0 then
      return "PREFERRED PLUGINS:\n" .. tbl_concat(directives, "\n")
    end
    out[#out+1] = "Types with no preferred plugin set:"
    for _, d in ipairs(directives) do out[#out+1] = d end
  end

  return "PREFERRED PLUGINS:\n" .. tbl_concat(out, "\n")
end

-- =============================================================================
-- Preferred Plugins I/O (JSON cache)
-- =============================================================================

-- Merged alias lookup. Starts from PREF_PLUGIN_ALIASES (cross-type redirects
-- like expander->gate live here and stay code-owned), then layers in the
-- per-row user aliases from cache.preferred_aliases. User aliases can
-- override the code map for their own key; that's intentional.
-- Attached to pref_plugins (not file-scope) so callers declared above this
-- point resolve it via table lookup at call time, and so we don't burn new
-- file-scope local slots.
function pref_plugins.alias_lookup()
  -- Memoize on FXCache._mutation_count: the lookup table only depends on
  -- PREF_PLUGIN_ALIASES (constant) plus cache.preferred_aliases (mutates
  -- via the mutation-counted FXCache writers). Previously every caller
  -- did its own FXCache.load + pairs walk + gmatch; with multiple callers
  -- looping per-row over rows on a Save/Scan, that was 20+ JSON cache
  -- parses on a 20-row save.
  local mc = FXCache._mutation_count or 0
  if pref_plugins._alias_lookup_mc == mc and pref_plugins._alias_lookup then
    return pref_plugins._alias_lookup
  end
  local out = {}
  for k, v in pairs(PREF_PLUGIN_ALIASES) do out[k] = v end
  local cache = FXCache.load()
  local pa = cache.preferred_aliases
  if type(pa) == "table" then
    for key, aliases_str in pairs(pa) do
      for piece in tostring(aliases_str):gmatch("[^,]+") do
        local a = (piece:match("^%s*(.-)%s*$") or ""):lower()
        if a ~= "" then out[a] = key end
      end
    end
  end
  pref_plugins._alias_lookup    = out
  pref_plugins._alias_lookup_mc = mc
  return out
end

-- Reverse-index PREF_PLUGIN_ALIASES to seed per-row alias defaults. Returns
-- { eq = "equalizer, equaliser", compressor = "comp, compression", ... }.
-- Cross-type redirects (expander->gate, flanger->phaser) ARE included so the
-- user sees them as editable suggestions and can remove ones they dislike.
-- PREF_PLUGIN_ALIASES also carries entries whose alias is just the lowercased
-- canonical label ("pitch shift" -> "pitch_shift", "de-esser" -> "deesser",
-- "multiband compressor" -> ...); those exist for label_to_type_key
-- normalization, not as user-visible alternates, so we drop them.
function pref_plugins.default_aliases()
  local is_default_label = {}
  for _, lbl in ipairs(PREF_PLUGIN_DEFAULTS) do
    is_default_label[lbl:lower()] = true
  end
  local by_key = {}
  for alias, key in pairs(PREF_PLUGIN_ALIASES) do
    -- Drop identity hits (gate -> gate, synth -> synth) AND alias entries
    -- that are just the canonical label spelled out.
    if alias ~= key and not is_default_label[alias] then
      by_key[key] = by_key[key] or {}
      by_key[key][#by_key[key]+1] = alias
    end
  end
  -- Short-form seeds for long-label defaults: the canonical key (eq, synth)
  -- IS a natural alias when the row label is the long form (Equalizer,
  -- Synthesizer), but it doesn't live in PREF_PLUGIN_ALIASES (label_to_type_key
  -- falls through to the lowercase key for these; no alias entry required).
  -- Seed them explicitly so users see the short form in the alias column.
  local SHORT_FORMS = { eq = "eq", synth = "synth" }
  for key, short in pairs(SHORT_FORMS) do
    by_key[key] = by_key[key] or {}
    by_key[key][#by_key[key]+1] = short
  end
  local out = {}
  for key, list in pairs(by_key) do
    table.sort(list)
    out[key] = tbl_concat(list, ", ")
  end
  return out
end

-- Convert a user-facing label (e.g. "De-esser", "Pitch Correction") into its
-- canonical type key as used by pref_types, chain keys, and resolve:<type>
-- tokens. Applies the merged alias lookup so storage and lookup share one
-- vocabulary.
function label_to_type_key(label)
  local canonical = label:match("^([^,]+)") or label
  canonical = (canonical:match("^%s*(.-)%s*$") or ""):lower()
  if canonical == "" then return "" end
  local aliases = pref_plugins.alias_lookup()
  if aliases[canonical] then
    return aliases[canonical]
  end
  -- Fall back to space->underscore + strip-slash normalization. Matches the
  -- chain key form for types without a hyphen alias
  -- (e.g. "Multiband Compressor" -> "multiband_compressor").
  return (canonical:gsub("%s+", "_"):gsub("[/]+", ""))
end

-- Collect the current pref_plugins.rows aliases buffers into a
-- cache.preferred_aliases-shaped map. Rows with no type/aliases text
-- contribute nothing. Called from every save path so Save, scan_start
-- (zero-scan branch), and scan_read all persist alias edits.
function pref_plugins.collect_aliases()
  local out = {}
  for _, row in ipairs(pref_plugins.rows) do
    local lbl     = (row.label   or ""):match("^%s*(.-)%s*$") or ""
    local aliases = (row.aliases or ""):match("^%s*(.-)%s*$") or ""
    if lbl ~= "" and aliases ~= "" then
      local rkey = label_to_type_key(lbl)
      if rkey ~= "" then out[rkey] = aliases end
    end
  end
  return out
end

function CTX.load_pref_plugins()
  local cache = FXCache.load()
  local pref_types = cache.preferred_types or {}
  -- One-shot seed: if the cache has never carried preferred_aliases, populate
  -- it from the code defaults (reverse of PREF_PLUGIN_ALIASES). Absent field
  -- means "never seeded"; an empty table means "seeded then user cleared all".
  -- After seeding, we write back so subsequent loads skip this block.
  if cache.preferred_aliases == nil then
    cache.preferred_aliases = pref_plugins.default_aliases()
    local err = FXCache.save(cache)
    if err and Store and Store._notify_write_failure then
      Store._notify_write_failure("FX cache", err)
    end
  end
  local pref_aliases = cache.preferred_aliases or {}
  -- ExtState is process-shared and always current, so consumers read
  -- the dev_hide_fabfilter flag directly here rather than mirroring it
  -- in a prefs field that could go stale if the dev_signal ever missed.
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
  for ri, row in ipairs(pref_plugins.rows) do
    local rkey = label_to_type_key(row.label or "")
    if rkey ~= "" then
      local ident = pref_types[rkey]
      if ident and ident ~= "" then
        -- Dev-only filter: skip FabFilter entries when the hide flag is on
        -- so the row visibly reverts to empty (triggering the not-found /
        -- resolve popups the dev is trying to exercise). Cache stays
        -- untouched; real preferences come back the moment the flag is off.
        if not (hide_ff and _is_fabfilter_ident(ident)) then
          pref_plugins.rows[ri].name = ident
        end
      end
      local aliases_str = pref_aliases[rkey]
      if aliases_str and aliases_str ~= "" then
        pref_plugins.rows[ri].aliases = aliases_str
      end
    end
  end
end

-- Save preferences to the JSON cache.
-- Updates preferred_types (type -> ident mapping) AND preferred_aliases
-- (type -> user-alias string) from pref_plugins.rows.
function CTX.save_pref_plugins()
  local cache = FXCache.load()
  cache.preferred_types = {}
  for _, row in ipairs(pref_plugins.rows) do
    local lbl  = (row.label or ""):match("^%s*(.-)%s*$") or ""
    local name = (row.name  or ""):match("^%s*(.-)%s*$") or ""
    if lbl ~= "" and name ~= "" then
      local rkey = label_to_type_key(lbl)
      if rkey ~= "" then
        -- Canonicalize on save so the on-disk form is AddByName-ready
        -- (e.g., "Twin 3" -> "VST3i: Twin 3"). Logs the upgrade once
        -- per save when it actually changes the value.
        local canonical, upgraded = FXCache.canonicalize_identifier(rkey, name)
        if upgraded then
          Log.line("PREF", str_format(
            "preferred_types.%s = %s -> %s (canonicalized on UI save)",
            rkey, name, canonical))
        end
        cache.preferred_types[rkey] = canonical
      end
    end
  end
  cache.preferred_aliases = pref_plugins.collect_aliases()
  return FXCache.save(cache)
end

-- Tokenize a plugin-name-ish string into an ORDERED list of lowercased
-- tokens. Splits on any non-alphanumeric character AND across alpha/digit
-- boundaries so "Pro-Q 4" and "proq4" both yield ("pro","q","4"). Strips
-- the REAPER format prefix (VST3:, JS:, etc.) from the front. Vendor text
-- inside parentheses is included as tokens -- e.g. "VST3: Pro-Q 4 (FabFilter)"
-- yields ("pro","q","4","fabfilter"), so typing "Fabfilter" as a search term
-- matches through the vendor name without any special casing.
local function pref_plugins_tokenize(s)
  s = (s or ""):lower():gsub("^%w+:%s*", "")
  local tokens = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%a") then
      local j = i
      while j <= n and s:sub(j, j):match("%a") do j = j + 1 end
      tokens[#tokens+1] = s:sub(i, j-1)
      i = j
    elseif c:match("%d") then
      local j = i
      while j <= n and s:sub(j, j):match("%d") do j = j + 1 end
      tokens[#tokens+1] = s:sub(i, j-1)
      i = j
    else
      i = i + 1
    end
  end
  return tokens
end

-- Score a single FX candidate against a tokenized search. Returns 0 if no
-- meaningful match. Designed to be strict enough that "Pro-C" doesn't pull
-- in everything containing "proc" (processor, production, ...) while still
-- letting "filter" match "Fabfilter" and vendor-prefix searches resolve.
--
-- Tiers (highest first):
--   1. Exact blob match        (10000)       -- "proq4" == "proq4"
--   2. Blob prefix match        (~8000)      -- search is prefix of plugin
--                                              blob, catches "proq4" -> "Pro-Q 4"
--   3. Single-token search:
--        token equals search     (5000)
--        token has search prefix (3000)      -- "pro" -> "Pro-Q"
--        search is substring of
--           a token              ( 500)      -- "filter" -> "Fabfilter"
--   4. Multi-token search:
--        EVERY search token must equal or prefix some plugin token.
--        Substring-only matches rejected (too noisy once the user has
--        committed to multiple tokens -- e.g. "Pro-C" = {"pro","c"}
--        must NOT match "Video processor" just because "processor"
--        contains "proc"). Sum of per-token subscores (500 eq, 200 pfx).
-- A small "shorter name wins" bonus breaks ties in favor of more specific
-- matches ("Pro-Q 4" beats "Pro-Q Multiband").
local function pref_plugins_score(search_tokens, plugin_tokens, fx_name_len)
  if #search_tokens == 0 or #plugin_tokens == 0 then return 0 end

  local search_blob = table.concat(search_tokens)
  local plugin_blob = table.concat(plugin_tokens)
  if plugin_blob == search_blob then return 10000 end
  if #search_blob > 0 and plugin_blob:sub(1, #search_blob) == search_blob then
    return 8000 + math_max(0, 200 - fx_name_len)
  end

  -- Helper: is `s` acceptable as a prefix match against plugin token `p`?
  -- Single-character search tokens are too noisy as prefixes (e.g. "c"
  -- prefix-matches "cntrl", "cat's", "convolution"), so we require them to
  -- match a plugin token EXACTLY. Two+ character search tokens can match
  -- either exactly or as a prefix.
  local function _prefix_ok(s, p)
    if #s == 1 then return false end
    return #s <= #p and p:sub(1, #s) == s
  end

  if #search_tokens == 1 then
    local s = search_tokens[1]
    local best = 0
    for _, p in ipairs(plugin_tokens) do
      if p == s then
        if best < 5000 then best = 5000 end
      elseif _prefix_ok(s, p) then
        if best < 3000 then best = 3000 end
      elseif #s > 1 and p:find(s, 1, true) then
        if best < 500 then best = 500 end
      end
    end
    if best == 0 then return 0 end
    return best + math_max(0, 200 - fx_name_len)
  end

  -- Multi-token: every search token must equal OR prefix some plugin token.
  local total = 0
  for _, s in ipairs(search_tokens) do
    local best = 0
    for _, p in ipairs(plugin_tokens) do
      if p == s then
        if best < 500 then best = 500 end
      elseif _prefix_ok(s, p) then
        if best < 200 then best = 200 end
      end
    end
    if best == 0 then return 0 end
    total = total + best
  end
  return total + math_max(0, 200 - fx_name_len)
end

-- Split the normalized blob of a plugin name into (alpha_base, trailing_num).
-- "proq4" -> ("proq", 4); "reaeq" -> ("reaeq", -1). Used for the version
-- tie-break (Pro-Q 4 beats Pro-Q 2 when scores match).
local function pref_plugins_split_trailing_num(s)
  local base, num = s:match("^(.-)(%d+)$")
  if base and num then return base, tonumber(num) end
  return s, -1
end

-- Best-match for preferred plugin search. Returns (best_identifier, score)
-- from the installed FX list, or nil if nothing scores > 0.
function pref_plugins_best_match(search_name, fx_list)
  local search_tokens = pref_plugins_tokenize(search_name)
  if #search_tokens == 0 then return nil, 0 end

  local best_ident = nil
  local best_score = 0
  local best_blob  = nil  -- concatenated plugin blob of current best

  for _, fx_name in ipairs(fx_list) do
    local plugin_tokens = pref_plugins_tokenize(fx_name)
    local score = pref_plugins_score(search_tokens, plugin_tokens, #fx_name)

    if score > best_score then
      best_score = score
      best_ident = fx_name
      best_blob  = table.concat(plugin_tokens)
    elseif score > 0 and score == best_score and best_blob then
      -- Version tie-break: if blobs share the same alpha base and differ
      -- only by a trailing number, prefer the higher number (newer version).
      local cand_blob = table.concat(plugin_tokens)
      local b_base, b_num = pref_plugins_split_trailing_num(best_blob)
      local c_base, c_num = pref_plugins_split_trailing_num(cand_blob)
      if b_base == c_base and c_num > b_num then
        best_ident = fx_name
        best_blob  = cand_blob
      end
    end
  end

  return best_ident, best_score
end

-- Rank installed FX by match score and return the top `limit` canonical
-- names (scored > 0). Same scoring + tie-break as pref_plugins_best_match.
function pref_plugins_rank_matches(search_name, fx_list, limit)
  limit = limit or 8
  local search_tokens = pref_plugins_tokenize(search_name)
  if #search_tokens == 0 then return {} end

  local scored = {}
  for _, fx_name in ipairs(fx_list) do
    local plugin_tokens = pref_plugins_tokenize(fx_name)
    local score = pref_plugins_score(search_tokens, plugin_tokens, #fx_name)
    if score > 0 then
      local blob = table.concat(plugin_tokens)
      local base, num = pref_plugins_split_trailing_num(blob)
      scored[#scored+1] = {
        ident = fx_name, score = score, base = base, num = num,
      }
    end
  end

  -- Sort by score desc; tie-break by (base match -> higher num), then name.
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.base == b.base and a.num ~= b.num then return a.num > b.num end
    return a.ident < b.ident
  end)

  local out = {}
  for i = 1, math_min(limit, #scored) do out[i] = scored[i].ident end
  return out
end

-- Start an async parameter scan for all non-empty preferred plugins.
-- Phase 1 ("adding"): creates a temp track and adds each plugin.
-- Phase 2 ("reading"): runs on the next loop frame (FX are initialised by then),
-- reads all parameters using the unified scanner, caches to JSON, and cleans up.
-- force: if true, re-scan every resolved ident even if it's already cached.
-- Default (false/nil) skips idents already present in cache.plugins so that
-- Save acts as "save + scan only new plugins".
function CTX.pref_plugins_scan_start(force)
  local function pp_t(key, values, fallback)
    if I18N and I18N.t then
      local text = I18N.t(key, values)
      if type(text) == "string" and text ~= "" and text ~= key then
        return text
      end
    end
    return fallback or key
  end
  local scan = pref_plugins.scan
  -- Defensive guard: also bail if a single-plugin rescan is in flight.
  -- (The buttons on the page already disable on this condition, but the
  --  guard protects against future callers.)
  if scan.active or fx_cache_ui.rescan.active then return end
  scan.force = force and true or false

  -- Ensure the installed FX cache is populated.
  CTX.populate_installed_fx()

  -- Build the list of plugins to scan using best-match scoring.
  scan.fx_map  = {}
  scan.results = {}
  -- Entries whose ident is already cached and we're not forcing: still need
  -- their preferred_types mapping updated but should not be re-inserted on
  -- the temp track. Collected separately and applied in scan_read.
  scan.skipped_cached = {}
  -- Load the cache ONCE here and pass it through scan state so scan_read
  -- reuses the same in-memory copy. Previously this was loaded 2-3 times
  -- per Save (here, in the zero-scan branch, and again in scan_read),
  -- which is wasteful for sessions with large param caches.
  scan.cache = FXCache.load()
  if CTX._installed_fx_list then
    for _, row in ipairs(pref_plugins.rows) do
      local lbl  = (row.label or ""):match("^%s*(.-)%s*$") or ""
      local name = (row.name  or ""):match("^%s*(.-)%s*$") or ""
      if lbl ~= "" and name ~= "" then
        local rkey = label_to_type_key(lbl)
        if rkey ~= "" then
          if Code.is_curated_plugin(name) then
            -- Curated plugins: commit the pref_types mapping but skip the
            -- live scan. Their param docs live in Plugin_Ref.md and preempt
            -- routes through plugin_ref:<Name>, never consulting the live
            -- scan cache -- scanning them is wasted work.
            scan.skipped_cached[#scan.skipped_cached+1] =
              { key = rkey, ident = name }
          else
            local ident = pref_plugins_best_match(name, CTX._installed_fx_list)
            if ident then
              local cached_entry = scan.cache.plugins
                and scan.cache.plugins[ident]
              local already_cached = cached_entry
                and cached_entry.params
                and #cached_entry.params > 0
              if (not scan.force) and already_cached then
                scan.skipped_cached[#scan.skipped_cached+1] =
                  { key = rkey, ident = ident }
              else
                scan.fx_map[#scan.fx_map+1] =
                  { key = rkey, name = name, ident = ident, fx_idx = -1 }
              end
            end
          end
        end
      end
    end
  end

  if #scan.fx_map == 0 then
    -- Nothing to actually scan, but we may still need to commit
    -- preferred_types mappings for already-cached entries. Reuse the
    -- cache we loaded above instead of re-reading from disk.
    if #scan.skipped_cached > 0 then
      -- Wipe-and-rebuild: skipped_cached reflects the CURRENT row set,
      -- so resetting preferred_types here is the only way a user-deleted
      -- row actually disappears from the saved mapping. Without this,
      -- deletions silently persisted.
      scan.cache.preferred_types = {}
      for _, entry in ipairs(scan.skipped_cached) do
        scan.cache.preferred_types[entry.key] = entry.ident
      end
      scan.cache.preferred_aliases = pref_plugins.collect_aliases()
      local err = FXCache.save(scan.cache)
      if err then
        scan.status = err
        UI.show_float_toast(pp_t(
          "settings.pref_plugins.toast.save_failed_short", nil,
          "Save failed"), "err")
      else
        scan.status = ""
        UI.show_float_toast(pp_t("settings.pref_plugins.toast.saved", nil,
          "Preferences saved"), "ok")
        pref_plugins.pending_exit = true
      end
    else
      scan.status = ""
      -- Still save the preferences (without param data).
      local err = CTX.save_pref_plugins()
      if err then
        UI.show_float_toast(pp_t("settings.pref_plugins.toast.save_failed",
          { error = err }, "Save failed: " .. err), "err")
      else
        UI.show_float_toast(pp_t(
          "settings.pref_plugins.toast.no_matches", nil,
          "No matching plugins found"), "err")
        pref_plugins.pending_exit = true
      end
    end
    scan.cache = nil
    return
  end

  -- Phase 1: create temp track and add all plugins.
  reaper.Undo_BeginBlock()
  scan.undo_open = true
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  if not tr then
    reaper.PreventUIRefresh(-1)
    scan.status = ""
    UI.show_float_toast(pp_t(
      "settings.pref_plugins.toast.scan_failed_track", nil,
      "Scan failed: couldn't create temp track"), "err")
    reaper.Undo_EndBlock("ReaAssist: scan (failed)", 0)
    scan.undo_open = false
    scan.cache = nil
    return
  end
  -- Hide from TCP and mixer so user doesn't see it flash.
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  scan.track = tr

  for _, entry in ipairs(scan.fx_map) do
    local fx = reaper.TrackFX_AddByName(tr, entry.ident, false, -1)
    entry.fx_idx = fx
    -- Hide plugin UI.
    if fx >= 0 then reaper.TrackFX_Show(tr, fx, 2) end
  end

  -- Close the setup undo block before returning to the main loop. The read and
  -- cleanup phase runs on a later frame, so it must not inherit this block.
  reaper.Undo_EndBlock("ReaAssist: preferred plugins scan load", 0)
  scan.undo_open = false

  scan.active = true
  scan.phase  = "reading"  -- will be processed on the next loop() frame
  scan.status = pp_t("settings.pref_plugins.status.scanning", nil,
    "Scanning parameters...")
end

-- Phase 2: read parameters from all added plugins using the unified scanner,
-- cache to JSON, then clean up.
-- Called from the main loop on the frame AFTER scan_start.
function CTX.pref_plugins_scan_read()
  local function pp_t(key, values, fallback)
    if I18N and I18N.t then
      local text = I18N.t(key, values)
      if type(text) == "string" and text ~= "" and text ~= key then
        return text
      end
    end
    return fallback or key
  end
  local scan = pref_plugins.scan
  if not scan.active or scan.phase ~= "reading" then return end

  local tr = scan.track
  -- ValidatePtr2 guards against project switches or explicit deletions
  -- between the scan_start frame and this reader frame. A non-nil but
  -- stale userdata handle would crash TrackFX_GetNumParams below.
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    scan.active = false
    scan.phase  = "done"
    scan.cache  = nil
    scan.track  = nil
    scan.status = ""
    UI.show_float_toast(pp_t(
      "settings.pref_plugins.toast.scan_failed_lost", nil,
      "Scan failed: temp track lost"), "err")
    reaper.PreventUIRefresh(-1)
    if scan.undo_open then
      reaper.Undo_EndBlock("ReaAssist: scan (failed)", 0)
      scan.undo_open = false
    end
    return
  end

  -- Read parameters for each successfully added plugin using unified scanner.
  -- Also update the preferred_types mapping in the cache. Reuse the cache
  -- that scan_start loaded and stashed on scan.cache so we don't re-parse
  -- the JSON file (fall back to a fresh load if the stash was cleared,
  -- which shouldn't happen during a normal active scan).
  local cache = scan.cache or FXCache.load()
  -- Per-entry xpcall: if scan_fx_params throws on one plugin (stale handle,
  -- REAPER returning nil mid-probe, etc.) we do NOT want to skip the cleanup
  -- at the end of this function -- that would leave an orphaned hidden temp
  -- track plus a stuck PreventUIRefresh(-1) imbalance.
  -- The failed entry is logged and skipped so the remaining plugins still scan.
  local scan_failures = {}
  for _, entry in ipairs(scan.fx_map) do
    if entry.fx_idx >= 0 then
      local _ok, params_list, max_group, total_count, needs_deep_scan =
        xpcall(function()
          return CTX.scan_fx_params(tr, entry.fx_idx)
        end, debug.traceback)
      if not _ok then
        Log.line("PREF_PLUGINS_SCAN", string.format(
          "scan_fx_params threw for %s: %s",
          entry.ident or "?", tostring(params_list)))
        scan_failures[#scan_failures+1] = entry.ident or "?"
      else
        -- Store in unified cache keyed by identifier.
        cache.plugins[entry.ident] = {
          param_count      = total_count,
          max_group        = max_group,
          params           = params_list,
          needs_deep_scan  = needs_deep_scan or nil,
        }
        -- Collected scanned entries into fx_map; preferred_types is rebuilt
        -- below from fx_map + skipped_cached in a single wipe-then-populate
        -- pass so deleted rows are removed cleanly.
      end
    end
  end

  -- Wipe-and-rebuild preferred_types from scan.fx_map + scan.skipped_cached,
  -- which together represent the CURRENT row set after any Add/Modify/Delete
  -- edits. Additive-only updates (the earlier behavior) left deleted rows'
  -- mappings in the cache forever, so the UI appeared to discard deletions.
  --
  -- Skip entries whose plugin failed to load (entry.fx_idx < 0) or whose
  -- scan threw. Earlier code committed every entry unconditionally, baking
  -- in a saved preference that pointed at an identifier the user couldn't
  -- actually use; the next session would silently fail to load it with no
  -- breadcrumb in the UI. Track skipped names so the toast surfaces it.
  local _failed_idents = {}
  for _, ident in ipairs(scan_failures) do
    _failed_idents[ident] = true
  end
  local skipped_idents = {}
  cache.preferred_types = {}
  for _, entry in ipairs(scan.fx_map) do
    if entry.fx_idx >= 0 and not _failed_idents[entry.ident] then
      cache.preferred_types[entry.key] = entry.ident
    else
      skipped_idents[#skipped_idents+1] = entry.ident or entry.key or "?"
    end
  end
  if scan.skipped_cached then
    for _, entry in ipairs(scan.skipped_cached) do
      cache.preferred_types[entry.key] = entry.ident
    end
  end
  cache.preferred_aliases = pref_plugins.collect_aliases()
  -- Bump the mutation counter: scan_read mutates cache.preferred_types
  -- and cache.plugins directly (without going through put_plugin), so
  -- the FX-cache settings list cache wouldn't otherwise know to
  -- invalidate after a scan finishes.
  FXCache._mutation_count = (FXCache._mutation_count or 0) + 1

  -- Clean up: remove temp track.
  reaper.DeleteTrack(tr)
  reaper.PreventUIRefresh(-1)
  if scan.undo_open then
    -- Legacy guard: the setup block should already be closed before this
    -- deferred read phase, but never let an unexpected open block leak.
    reaper.Undo_EndBlock("ReaAssist: preferred plugins scan", 0)
    scan.undo_open = false
  end

  -- Save the unified JSON cache.
  local err = FXCache.save(cache)
  scan.active = false
  scan.phase  = "done"
  scan.cache  = nil  -- release stashed reference
  if err then
    scan.status = err
    UI.show_float_toast(pp_t(
      "settings.pref_plugins.toast.save_failed_short", nil,
      "Save failed"), "err")
  else
    scan.status = ""
    if #skipped_idents > 0 then
      -- Partial success: some plugins couldn't load (or threw mid-scan), so
      -- the rest were saved but those rows have no preferred_types entry.
      -- Surface the count + first few names; full list goes to the debug
      -- log so the user has something to triage with.
      Log.line("PREF_PLUGINS_SCAN", "skipped " .. #skipped_idents
        .. " unloadable/failed: " .. tbl_concat(skipped_idents, ", "))
      local preview_n = (#skipped_idents < 2) and #skipped_idents or 2
      local preview = tbl_concat(skipped_idents, ", ", 1, preview_n)
      local more = #skipped_idents - preview_n
      local more_txt = ""
      if more > 0 then
        more_txt = pp_t("settings.pref_plugins.toast.more",
          { count = more }, ", +" .. more .. " more")
      end
      local msg = pp_t("settings.pref_plugins.toast.saved_skipped", {
        count = #skipped_idents,
        preview = preview,
        more = more_txt,
      }, "Saved (" .. #skipped_idents .. " skipped: "
        .. preview .. more_txt .. ")")
      UI.show_float_toast(msg, "err")
    else
      UI.show_float_toast(pp_t("settings.pref_plugins.toast.saved", nil,
        "Preferences saved"), "ok")
    end
    pref_plugins.pending_exit = true
  end
end

-- =============================================================================
-- CTX.build_snapshot
-- =============================================================================
-- Gathers all lightweight context buckets for the given project and returns
-- a formatted "SESSION CONTEXT:\n..." block. Called on every send so the data
-- is always fresh. The result is passed to Net.build_body() but never stored in
-- S.history, so older turns do not carry stale snapshot data.
--
-- Included buckets (all cheap, read-only REAPER API calls):
--   tempo/time sig   - project BPM and time signature (e.g. 6/8)
--   sample rate      - project sample rate in Hz
--   transport        - play/record/pause/stopped state
--   loop             - loop enable state and loop point range
--   markers/regions  - all markers and region start/end points (capped)
--   tracks           - track list with name, item count, mute/solo/arm flags
--   fx chains        - which FX are loaded on each track (names only; not params)
--   selected tracks  - which tracks are currently selected
--   time selection   - start/end of the current time selection (or "none")
--   edit cursor      - current cursor position in seconds
--   selected items   - position/length/track of selected media items (capped)
--
-- NOTE: FX parameter values are intentionally excluded here because they can
-- be very large on dense sessions (dozens of parameters per plugin across many
-- tracks). The assistant requests them on demand via
-- <context_needed>fx_params:PluginName</context_needed>, which scopes the
-- collection to only the named plugin(s).
-- Heavy-snapshot memoization. tracks() walks every track + FX chain and
-- markers() walks every marker/region; both can take hundreds of ms on
-- dense projects. Cache them keyed on reaper.GetProjectStateChangeCount(),
-- which increments on every undo-tracked mutation (track/FX/marker/loop
-- edits). The cheap + volatile bits (tempo, cursor, selection, transport,
-- selected items, time selection) are re-read every call -- they're each
-- under ~1ms, AND some of them (cursor, selection, transport) aren't
-- reflected in the state-count so we'd risk serving stale data if we
-- cached them. Invalidated automatically on project switch because proj
-- is part of the key.
CTX._snapshot_heavy_cache = nil

-- =============================================================================
-- CTX.preempt_buckets_for_prompt
-- =============================================================================
-- Scan the user's prompt for plugin-type keywords that match their saved
-- preferred_types. For each hit, load the corresponding preferred_plugins
-- content and drop it directly into S.sticky_context BEFORE the first API
-- send. That way the model sees the relevant plugin reference data in the
-- initial request and doesn't need to emit <context_needed>preferred_plugins:X
-- to ask for it -- saving a full API round trip.
--
-- This is a best-effort optimization. Word-boundary matching against the
-- user's preferred_types keys (whatever labels they typed on the Preferred
-- Plugins page, lowercased-with-underscores: "compressor", "eq", "de-esser",
-- etc.). Skipped when a type is already in sticky_context (user already has
-- that data from an earlier turn) or already marked sent for this turn.
--
-- Returns a list of preemption-reason strings for the debug log.
--
-- CHAIN_PHRASE_HINTS extends the trigger surface beyond single-keyword
-- matches: broad multi-FX phrases (e.g. "drum kit", "vocal chain", "mix
-- bus") strongly imply specific plugin types without naming them by type
-- word. When a phrase matches, the preempt loop treats each implied type
-- as if its own keyword had hit, pre-pinning that type's plugin_ref + pref
-- hint and saving the <context_needed>resolve:X</context_needed> round-trip
-- the model would otherwise emit. Each entry is {pattern, {implied_types}};
-- only types the user actually has a pref for get pinned (the main loop
-- iterates pref_types keys, so unconfigured types fall through naturally).
-- Saved per matched phrase: one full API round-trip (~2s + small request
-- cost) on the common drum-kit / vocal-chain / mix-bus creation requests.
local CHAIN_PHRASE_HINTS = {
  { "drum%s+kit",         {"eq", "compressor", "gate"} },
  { "drum%s+chain",       {"eq", "compressor", "gate"} },
  { "drum%s+bus",         {"eq", "compressor"} },
  -- Vocal-chain variants: the literal "vocal%s+chain" alone misses
  -- common phrasings like "chain of effects ... rock vocal" (observed
  -- in a turn-2 user prompt that paid a wasted resolve round-trip
  -- because reverb + compressor weren't preempted). Order matters
  -- for trigger-phrase attribution: more-specific patterns first so
  -- the debug log records the tightest match. All three entries imply
  -- the same type set, so type-pinning is unaffected by order.
  --
  -- All patterns require BOTH a vocal mention AND a chain/effects
  -- mention. "rock vocal" alone would over-preempt on add-only or
  -- record-only prompts ("add a rock vocal track", "record a rock
  -- vocal") that don't ask for a chain. Genre-prefixed phrasings
  -- like "rock vocal chain" already hit via vocal%s+chain anyway,
  -- since the substring "vocal chain" is present.
  { "chain%s+of%s+effects.-vocal", {"eq", "compressor", "deesser", "reverb"} },
  { "chain.-rock%s+vocal", {"gate", "eq", "compressor", "saturation", "limiter"} },
  { "chain.-vocal", {"eq", "compressor", "deesser", "reverb"} },
  { "vocal%s+chain",      {"eq", "compressor", "deesser", "reverb"} },
  { "vocal.-chain",       {"eq", "compressor", "deesser", "reverb"} },
  { "vocal%s+bus",        {"eq", "compressor"} },
  { "guitar%s+chain",     {"eq", "compressor", "saturation"} },
  { "bass%s+chain",       {"eq", "compressor"} },
  { "mix%s+bus",          {"eq", "compressor", "limiter"} },
  { "master%s+bus",       {"eq", "compressor", "limiter"} },
  { "mastering%s+chain",  {"eq", "compressor", "limiter"} },
  { "recording%s+chain",  {"eq", "compressor", "gate"} },
}
-- Exported for the chain-upsert validator retry gate in ReaAssist.lua.
CTX.CHAIN_PHRASE_HINTS = CHAIN_PHRASE_HINTS

function CTX.prompt_indicates_chain_context(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  for _, hint in ipairs(CHAIN_PHRASE_HINTS) do
    if t:find(hint[1]) then return true end
  end
  if not t:find("%f[%w]chain%f[%W]") then return false end
  return t:find("%f[%w]drum%f[%W]") ~= nil
    or t:find("%f[%w]drums%f[%W]") ~= nil
    or t:find("%f[%w]snare%f[%W]") ~= nil
    or t:find("%f[%w]kick%f[%W]") ~= nil
    or t:find("%f[%w]tom%f[%W]") ~= nil
    or t:find("%f[%w]percussion%f[%W]") ~= nil
    or t:find("%f[%w]vocal%f[%W]") ~= nil
    or t:find("%f[%w]guitar%f[%W]") ~= nil
    or t:find("%f[%w]bass%f[%W]") ~= nil
    or t:find("%f[%w]mix%f[%W]") ~= nil
    or t:find("%f[%w]master%f[%W]") ~= nil
    or t:find("%f[%w]mastering%f[%W]") ~= nil
    or t:find("%f[%w]recording%f[%W]") ~= nil
    or t:find("%f[%w]effects%f[%W]") ~= nil
    or t:find("%f[%w]processing%f[%W]") ~= nil
end

function CTX.prompt_indicates_typed_action_plan(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  return t:find("typed action plan", 1, true) ~= nil
    or t:find("typed-action plan", 1, true) ~= nil
    or t:find("typed-action contract", 1, true) ~= nil
    or t:find("reaassist-actions", 1, true) ~= nil
end

-- DOCS_PHRASE_HINTS: keyword/phrase -> docs:<section> pre-pin map. When the
-- user prompt contains any of these, the matched section is loaded into
-- sticky_context BEFORE the first API call, saving the round-trip the
-- model would otherwise spend emitting <context_needed>docs:envelopes</context_needed>
-- (or whichever). Only fires for sections in DOCS_SECTION_NAMES; the
-- canonical key is what gets pinned.
--
-- Pattern style: multi-word phrases (e.g. "send to") use literal substring
-- match; common single words use the %f[%w]X%f[%W] frontier syntax for
-- whole-word boundaries (Lua has no \b). The frontier pattern requires the
-- bracket sets -- a bare %f without [...] errors out.
--
-- "automation" -> docs:envelopes intentionally. REAPER's "automation items"
-- are media-item-shaped objects layered onto envelopes, but the scripting
-- surface (Envelope_*, GetSetEnvelope*, InsertEnvelopePoint, etc.) lives
-- in the envelopes section. Users saying "automate the volume" or "add
-- automation" need envelope functions, not item functions.
local DOCS_PHRASE_HINTS = {
  -- envelopes
  { "envelope",              "envelopes" },
  { "automation",            "envelopes" },
  { "automate",              "envelopes" },
  { "pan envelope",          "envelopes" },
  { "pan automation",        "envelopes" },
  { "%f[%w]autopan%f[%W]",   "envelopes" },
  { "auto%-pan",             "envelopes" },
  { "%f[%w]lfo%f[%W]",       "envelopes" },
  { "%f[%w]panner%f[%W]",    "envelopes" },
  -- routing (multi-word phrases avoid frontier-pattern needs)
  { "sidechain",             "routing"   },
  { "send to",               "routing"   },
  { "send from",             "routing"   },
  { "create a send",         "routing"   },
  { "create send",           "routing"   },
  { "add a send",            "routing"   },
  { "add send",              "routing"   },
  { "set up a send",         "routing"   },
  { "set up send",           "routing"   },
  { "receive from",          "routing"   },
  { "%f[%w]route%f[%W]",     "routing"   },
  { "%f[%w]routing%f[%W]",   "routing"   },
  { "%f[%w]bus%f[%W]",       "routing"   },
  { "%f[%w]aux%f[%W]",       "routing"   },
  { "return track",          "routing"   },
  { "hardware output",       "routing"   },
  -- take_fx. The phrase set covers both explicit "take FX" wording and
  -- the more common item-scoped FX targeting ("add an EQ to the selected
  -- item", "on this clip", "to the active take") -- when the user
  -- targets an item rather than a track, the model needs TakeFX_* not
  -- TrackFX_*, and reaching for core's TrackFX_* by default is the
  -- semantic mistake we want to prevent. Phrases are chosen to imply
  -- "applying FX TO X" (preposition + item/take noun) so plain item
  -- queries like "trim the selected item" or "count selected items"
  -- don't trigger an unnecessary take_fx pin.
  { "take fx",               "take_fx"   },
  { "take effect",           "take_fx"   },
  { "item fx",               "take_fx"   },
  { "per%-item fx",          "take_fx"   },
  { "to the selected item",  "take_fx"   },
  { "on the selected item",  "take_fx"   },
  { "to this item",          "take_fx"   },
  { "on this item",          "take_fx"   },
  { "to this clip",          "take_fx"   },
  { "on this clip",          "take_fx"   },
  { "to the active take",    "take_fx"   },
  { "on the active take",    "take_fx"   },
  { "to the take",           "take_fx"   },
  { "on the take",           "take_fx"   },
  -- items (markers/regions stay in core, so don't pin items on those words)
  { "razor edit",            "items"     },
  { "razor area",            "items"     },
  { "media item",            "items"     },
  { "midi item",             "items"     },
  { "midi items",            "items"     },
  -- tempo (markers/regions stay in core, so don't pin tempo on those words)
  { "%f[%w]tempo%f[%W]",     "tempo"     },
  { "time signature",        "tempo"     },
}

CTX = CTX or {}
CTX.DRUM_EDIT_PHRASE_HINTS = {
  "quantize drums",
  "quantize the drums",
  "drum quantize",
  "edit drums",
  "edit the drums",
  "editing drums",
  "tighten drums",
  "tighten the drums",
  "snap drums",
  "snap the drums",
  "drum transients",
  "drum hits",
  "drum editing",
}

function CTX.prompt_indicates_drum_edit(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  for _, phrase in ipairs(CTX.DRUM_EDIT_PHRASE_HINTS) do
    if t:find(phrase, 1, true) then return true end
  end
  local has_drum =
       t:find("%f[%w]drum%f[%W]") ~= nil
    or t:find("%f[%w]drums%f[%W]") ~= nil
  if not has_drum then return false end
  if t:find("%f[%w]quantiz") then return true end
  if t:find("%f[%w]tighten") then return true end
  if t:find("%f[%w]transient") then return true end
  if t:find("stretch marker", 1, true) then return true end
  if t:find("guide track", 1, true) then return true end
  return false
end

CTX.TIMECODE_GENERATOR_TIME_TERMS = {
  "%f[%w]smpte%f[%W]",
  "%f[%w]ltc%f[%W]",
  "%f[%w]mtc%f[%W]",
  "time%s*code",
  "timecode",
  "codice%s+temporale",
}

CTX.TIMECODE_GENERATOR_READER_TERMS = {
  "%f[%w]read%f[%W]",
  "%f[%w]reader%f[%W]",
  "%f[%w]meter%f[%W]",
  "%f[%w]decode%f[%W]",
  "%f[%w]decodes%f[%W]",
  "%f[%w]decoding%f[%W]",
  "%f[%w]decoder%f[%W]",
  "%f[%w]sync",
  "%f[%w]synchron",
  "%f[%w]receive",
  "%f[%w]incoming%f[%W]",
  "%f[%w]chase%f[%W]",
  "%f[%w]monitor",
  "%f[%w]legg[eiou]",
  "%f[%w]lett[oua]",
  "%f[%w]decodific",
  "%f[%w]misur[aeio]",
  "%f[%w]sincron[io]",
  "%f[%w]ricev[eiou]",
}

CTX.TIMECODE_GENERATOR_NOUN_TERMS = {
  "%f[%w]generator%f[%W]",
  "%f[%w]generators%f[%W]",
  "%f[%w]generatore%f[%W]",
  "%f[%w]generatori%f[%W]",
  "%f[%w]source%f[%W]",
  "%f[%w]sorgente%f[%W]",
}

CTX.TIMECODE_GENERATOR_VERB_TERMS = {
  "%f[%w]generate%f[%W]",
  "%f[%w]generates%f[%W]",
  "%f[%w]generating%f[%W]",
  "%f[%w]generare%f[%W]",
  "%f[%w]genera%f[%W]",
  "%f[%w]generi%f[%W]",
}

CTX.TIMECODE_GENERATOR_CREATE_TERMS = {
  "%f[%w]add%f[%W]",
  "%f[%w]create%f[%W]",
  "%f[%w]insert%f[%W]",
  "%f[%w]put%f[%W]",
  "%f[%w]place%f[%W]",
  "%f[%w]setup%f[%W]",
  "set%s+up",
  "%f[%w]inserisci%f[%W]",
  "%f[%w]inserire%f[%W]",
  "%f[%w]aggiungi%f[%W]",
  "%f[%w]aggiungere%f[%W]",
  "%f[%w]crea%f[%W]",
  "%f[%w]creare%f[%W]",
}

function CTX.prompt_indicates_timecode_generator(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  local has_timecode = false
  for _, pat in ipairs(CTX.TIMECODE_GENERATOR_TIME_TERMS) do
    if t:find(pat) then
      has_timecode = true
      break
    end
  end
  if not has_timecode then return false end

  local reader_intent = false
  for _, pat in ipairs(CTX.TIMECODE_GENERATOR_READER_TERMS) do
    if t:find(pat) then
      reader_intent = true
      break
    end
  end

  for _, pat in ipairs(CTX.TIMECODE_GENERATOR_VERB_TERMS) do
    if t:find(pat) then return true end
  end
  for _, pat in ipairs(CTX.TIMECODE_GENERATOR_NOUN_TERMS) do
    if t:find(pat) then return not reader_intent end
  end
  if reader_intent then return false end
  for _, pat in ipairs(CTX.TIMECODE_GENERATOR_CREATE_TERMS) do
    if t:find(pat) then return true end
  end
  return false
end

if REQUIRE_SWS_EXTENSION and not SupportExtFlag("optoutsws") then
  -- SWS docs are advertised only when the rollout flag is enabled. The
  -- loader accepts docs:sws either way, but normal releases should not
  -- nudge the model toward extension-only calls while SWS is still optional.
  local sws_hints = {
    { "%f[%w]sws%f[%W]",                  "sws" },
    { "s&m",                              "sws" },
    { "system clipboard",                 "sws" },
    { "%f[%w]clipboard%f[%W]",            "sws" },
    { "mouse cursor context",             "sws" },
    { "mouse cursor",                     "sws" },
    { "under my mouse",                   "sws" },
    { "under the mouse",                  "sws" },
    { "%f[%w]hovering%f[%W]",             "sws" },
    { "%f[%w]hovered%f[%W]",              "sws" },
    { "br_getmousecursorcontext",         "sws" },
    { "%f[%w]loudness%f[%W]",             "sws" },
    { "%f[%w]lufs%f[%W]",                 "sws" },
    { "sws notes",                        "sws" },
    { "marker region subtitle",           "sws" },
    { "region subtitle",                  "sws" },
  }
  for _, hint in ipairs(sws_hints) do
    DOCS_PHRASE_HINTS[#DOCS_PHRASE_HINTS + 1] = hint
  end
end

-- JSFX-intent detection: returns true when the user's prompt explicitly
-- asks for JSFX/EEL2/custom-DSP work. Intentionally narrow -- only fires on
-- the literal "jsfx" / "eel2" / "reajs" tokens, the "@init" / "@sample"
-- section markers (which only appear in JSFX code discussions), or the
-- common phrasing "write/build/make a (custom) plugin/effect/DSP". JSFX
-- family hints (shimmer, harmonizer, etc.) alone do NOT trigger -- those
-- words apply equally to plugin tasks, and a false positive here would
-- suppress plugin_ref / api_ref injection that the user actually needed.
--
-- Used by the send pipeline to:
--   - Skip plugin_ref / pref / docs co-pin in the keyword loop below
--     (saves ~25-30K input tokens per turn when user has a curated reverb
--     pref and types "reverb" alongside "JSFX").
--   - Trim the tracks list in the snapshot (no track is referenced when
--     generating an effect file).
local function _prompt_indicates_jsfx(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  -- Ignore negative/instructional mentions such as the typed-action
  -- contract's "Do not write Lua, ReaScript, JSFX..." line. Those are
  -- constraints, not JSFX authoring intent, and pre-pinning the JSFX bundle
  -- wastes tokens on otherwise compact local-action plans.
  t = t:gsub("do%s+not%s+write[^%.\n]*%f[%w]jsfx%f[%W][^%.\n]*", " ")
  t = t:gsub("don't%s+write[^%.\n]*%f[%w]jsfx%f[%W][^%.\n]*", " ")
  t = t:gsub("dont%s+write[^%.\n]*%f[%w]jsfx%f[%W][^%.\n]*", " ")
  t = t:gsub("without%s+%f[%w]jsfx%f[%W]", " ")
  t = t:gsub("no%s+%f[%w]jsfx%f[%W]", " ")
  t = t:gsub("not%s+%f[%w]jsfx%f[%W]", " ")
  if t:find("%f[%w]jsfx%f[%W]")  then return true end
  if t:find("%f[%w]eel2?%f[%W]") then return true end
  if t:find("%f[%w]reajs%f[%W]") then return true end
  if t:find("@init") or t:find("@sample") or t:find("@gfx")
     or t:find("@slider") or t:find("@block") then return true end
  return false
end

-- JSFX effect-family bundles. When the user prompt matches any phrase
-- below, the corresponding prompt_bundle:jsfx_<family> gets pinned on top
-- of the always-on prompt_bundle:jsfx core. Bundle content is in
-- Resources/Prompts.md (one SECTION per family). False-positive pins are
-- low-cost (one bundle, ~1.5K tokens) and don't change behavior beyond
-- giving the model more relevant DSP recipes; bias keywords toward
-- multi-word phrases when the single word is too generic to be safe.
local JSFX_FAMILY_HINTS = {
  -- jsfx_pitch: pitch shifters, shimmer reverbs, harmonizers, granular
  -- octave effects. Single-word `pitch` is too broad ("pitch the snare"
  -- in mixing context); require multi-word or context-specific phrasing.
  { "shimmer",                     "jsfx_pitch" },
  { "pitch shift",                 "jsfx_pitch" },
  { "pitch shifter",               "jsfx_pitch" },
  { "pitch%-shift",                "jsfx_pitch" },
  { "octave up",                   "jsfx_pitch" },
  { "octave down",                 "jsfx_pitch" },
  { "%f[%w]harmoniz",              "jsfx_pitch" },  -- harmonizer / harmoniser / harmonize
  { "%f[%w]transpose",             "jsfx_pitch" },
  { "%f[%w]grain%f[%W]",           "jsfx_pitch" },
  { "%f[%w]granular",              "jsfx_pitch" },
}

-- Exposed for callers outside this module (Net.send, the snapshot builder).
-- Keep the local in scope for in-module callers that already use it.
CTX.prompt_indicates_jsfx = _prompt_indicates_jsfx

function CTX.prompt_has_explicit_stock_fx_constraint(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  local stock_word = t:find("%f[%w]stock%f[%W]") ~= nil
    or t:find("%f[%w]cockos%f[%W]") ~= nil
  if not stock_word then return false end
  local names = { "reaeq", "reacomp", "reaxcomp", "reagate", "readelay",
    "realimit", "reapitch", "reatune", "reasynth", "reaverbate" }
  for _, name in ipairs(names) do
    if t:find(name, 1, true) then return true end
  end
  return t:find("%f[%w]only%f[%W]") ~= nil
    or t:find("stock only", 1, true) ~= nil
    or t:find("stock%-only", 1, false) ~= nil
    or t:find("no third%-party", 1, false) ~= nil
    or t:find("no third party", 1, true) ~= nil
end

function CTX.sticky_has_fx_params_for_ident(ident)
  if not ident or ident == "" or not S.sticky_context then return false end
  local target = _curated_for_ident(ident) or tostring(ident)
  target = target:gsub("^%w+:%s*", ""):lower()
  if target == "" then return false end
  for k in pairs(S.sticky_context) do
    local payload = k:match("^fx:(.+)$")
    if payload then
      for piece in payload:gmatch("[^/]+") do
        local name = piece:gsub("@%d+$", ""):lower()
        if name ~= "" and (name:find(target, 1, true)
            or target:find(name, 1, true)) then
          return true
        end
      end
    end
  end
  return false
end

function CTX.prompt_has_fx_param_read_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = text:lower()
  local names_params =
       t:find("%f[%w]parameters?%f[%W]") ~= nil
    or t:find("%f[%w]params?%f[%W]") ~= nil
  local names_settings =
       t:find("%f[%w]settings?%f[%W]") ~= nil
    or t:find("%f[%w]values?%f[%W]") ~= nil
    or t:find("set%s+to") ~= nil
  if not names_params and not names_settings then return false end
  return t:find("^%s*what%s+") ~= nil
    or t:find("^%s*which%s+") ~= nil
    or t:find("^%s*show%s+") ~= nil
    or t:find("^%s*list%s+") ~= nil
    or t:find("^%s*tell%s+") ~= nil
    or t:find("%f[%w]current%f[%W]") ~= nil
    or t:find("%f[%w]live%f[%W]") ~= nil
    or t:find("%f[%w]read%f[%W]") ~= nil
end

function CTX.live_fx_params_filter_for_ident(ident)
  if not ident or ident == "" then return nil end
  local proj = S.pending_project or reaper.EnumProjects(-1)
  if not proj then return nil end
  local target = _curated_for_ident(ident) or tostring(ident)
  target = target:gsub("^%w+:%s*", "")
  if target == "" then return nil end
  local queries = { target }
  if tostring(ident) ~= target then queries[#queries+1] = tostring(ident) end
  local track_count = R_CountTracks(proj)
  local tracks, seen = {}, {}
  for ti = 0, track_count - 1 do
    local tr = R_GetTrack(proj, ti)
    if tr then
      local fx_count = R_TrackFX_GetCount(tr) or 0
      for fi = 0, fx_count - 1 do
        local _, fx_nm = R_TrackFX_GetFXName(tr, fi, "")
        if CTX.fx_name_matches(fx_nm, queries) then
          local track_idx = ti + 1
          if not seen[track_idx] then
            tracks[#tracks+1] = track_idx
            seen[track_idx] = true
          end
        end
      end
    end
  end
  if #tracks == 1 then
    return { name = target, track = tracks[1] }
  end
  if #tracks > 1 and reaper.CountSelectedTracks and reaper.GetSelectedTrack then
    local selected_count = reaper.CountSelectedTracks(proj) or 0
    for si = 0, selected_count - 1 do
      local sel = reaper.GetSelectedTrack(proj, si)
      if sel then
        for ti = 0, track_count - 1 do
          if R_GetTrack(proj, ti) == sel and seen[ti + 1] then
            return { name = target, track = ti + 1 }
          end
        end
      end
    end
  end
  return nil
end

function CTX.preempt_live_fx_params_for_ident(ident, injected, reason, need_helpers)
  local filter = CTX.live_fx_params_filter_for_ident(ident)
  if not filter then return false end
  local fp_key = "fx:" .. CTX.fx_filter_key({ filter })
  if not S.sticky_context[fp_key] then
    local fx_str, matched = CTX.fx_params(S.pending_project or reaper.EnumProjects(-1),
      { filter })
    if not fx_str or not matched or matched < 1 then return false end
    Net.sticky_set(fp_key, fx_str, "preempt")
    injected[#injected+1] = fp_key
    Log.line("PREEMPT",
      "injected " .. fp_key .. " (live fx_params for " .. tostring(reason) .. ")")
  end
  if need_helpers then
    Net.copin_plugin_bundle(injected)
    Net.copin_docs_core(injected)
    Net.copin_plugin_helpers(injected, "preempt")
  end
  return true
end

function CTX.preempt_buckets_for_prompt(user_text)
  if not user_text or user_text == "" then return {} end
  local text = user_text:lower()
  if CTX.prompt_indicates_typed_action_plan(user_text) then
    Log.line("PREEMPT",
      "skipped context preempt (typed-action plan prompt)")
    return {}
  end
  local cache = FXCache.load()
  local pref_types = cache.preferred_types or {}
  -- JSFX-only intent suppresses the plugin_ref / pref / docs co-pin path
  -- in the type-keyword loop below. The JSFX_FAMILY_HINTS scan still runs
  -- (so prompt_bundle:jsfx_pitch etc. are pinned for "shimmer"-style
  -- prompts), and DOCS_PHRASE_HINTS still runs (envelopes/routing/etc.
  -- don't conflict with JSFX). What we skip is the `for tkey in keys` loop
  -- that pins plugin_ref:Pro-R 2 + pref:reverb + plugin bundle + docs core
  -- when the user has a curated pref for a type whose name appears in the
  -- prompt. Those payloads are useless for "create a JSFX <effect>" --
  -- the model writes EEL2, not reaper.* TrackFX_AddByName, and the docs
  -- gate is the safety net if it does choose to add a Lua companion.
  local jsfx_intent = _prompt_indicates_jsfx(user_text)
  local timecode_generator_intent =
    CTX.prompt_indicates_timecode_generator(user_text)
  local stock_fx_constraint = CTX.prompt_has_explicit_stock_fx_constraint(user_text)
  local forbids_fx_addition =
    type(Code) == "table"
    and type(Code.prompt_forbids_fx_addition) == "function"
    and Code.prompt_forbids_fx_addition(user_text) or false

  -- Scan chain-phrase hints first. Builds tkey -> matching_phrase so the
  -- main loop below can treat phrase hits identically to keyword hits and
  -- the log line can attribute the trigger.
  local phrase_implied = {}
  if not stock_fx_constraint and not forbids_fx_addition then
    for _, hint in ipairs(CHAIN_PHRASE_HINTS) do
      if text:find(hint[1]) then
        for _, t in ipairs(hint[2]) do
          if not phrase_implied[t] then phrase_implied[t] = hint[1] end
        end
      end
    end
  end
  if forbids_fx_addition then
    Log.line("PREEMPT",
      "skipped plugin/FX preempt (prompt explicitly forbids effects/FX/plugins)")
  end
  if phrase_implied.gate == "chain.-rock%s+vocal" then
    if phrase_implied.deesser == "chain.-vocal" then phrase_implied.deesser = nil end
    if phrase_implied.reverb == "chain.-vocal" then phrase_implied.reverb = nil end
  end
  local chain_phrase_hit = next(phrase_implied) ~= nil
  local preempt_needs_plugin_helpers =
    chain_phrase_hit or Code.prompt_has_param_write_intent(user_text)
  local preempt_live_fx_params =
    CTX.prompt_has_fx_param_read_intent(user_text)
    or Code.prompt_has_param_write_intent(user_text)

  -- injected: collected sticky_context keys we pre-pin this call. Hoisted
  -- above the docs-phrase scan so both the docs scan and the existing
  -- preferred-types loop below append to the same list. Returned at the end
  -- as the caller's "what we just preempted" log payload.
  local injected = {}

  do
    local recent_hit = false
    local recent_phrases = {
      "latest reaper", "current reaper", "new reaper", "recent reaper",
      "new in reaper", "what's new", "whats new",
      "reaper 7.65", "reaper 7.66", "reaper 7.67", "reaper 7.68",
      "reaper 7.69", "reaper 7.70", "reaper 7.71", "reaper 7.72",
      "reaper 7.73", "left/right to grid", "envelope points",
      "midi choke", "choke group", "track grouping", "grouped razor",
      "sample edit", "sample editing", "sample edit envelope",
      "set sample values to zero", "render hidden marker",
      "render hidden region", "hidden marker", "hidden region",
      "wavpack", "render metadata", "embed project markers",
      "embed project regions", "font scaling", "font-size scaling",
      "theme font", "item label font", "ruler lane", "mouse modifier",
      "marker left drag", "region edge", "ruler lane header",
    }
    for _, phrase in ipairs(recent_phrases) do
      if text:find(phrase, 1, true) then
        recent_hit = phrase
        break
      end
    end
    if recent_hit and not S.sticky_context["recent_reaper_changes"] then
      local recent_content, recent_err = CTX.recent_reaper_changes()
      if recent_content then
        Net.sticky_set("recent_reaper_changes", recent_content, "preempt")
        injected[#injected+1] = "recent_reaper_changes"
        Log.line("PREEMPT",
          "injected recent_reaper_changes (recent phrase: '"
          .. tostring(recent_hit) .. "')")
      else
        Log.line("PREEMPT",
          "wanted to inject recent_reaper_changes but loader failed: "
          .. (recent_err or "?"))
      end
    end
  end

  -- Chain-build follow-up: pre-pin fx_chains so the model can honor the
  -- ADD-VS-REUSE rule. When the prompt is a chain phrase AND there's
  -- already prior conversation history, an earlier turn may have placed
  -- plugins on the target track(s) -- if the model can't see what's
  -- already there it defaults to AddByName for everything and silently
  -- duplicates the existing plugins. The bundle's CHAIN BUILD / UPSERT
  -- RULE describes the right behavior; this gives the model the data
  -- it needs to actually do it. First-turn chain prompts skip this
  -- (no prior plugins to reuse) so we don't pay for a snapshot that
  -- adds nothing.
  if chain_phrase_hit and #S.history > 0
     and not S.fx_chains_already_sent
     and not S.sticky_context["fx_chains"] then
    local proj = S.pending_project or 0
    local fx_snapshot = CTX.fx(proj)
    if fx_snapshot and fx_snapshot ~= "" then
      -- Prepend a short, high-salience upsert skeleton ahead of the
      -- chain data. The CHAIN BUILD / UPSERT RULE in prompt_bundle:plugin
      -- is correct but buried in a long bundle; small models often skip
      -- past it on first draft and the UPSERT-VALIDATOR catches them on
      -- retry. Putting the skeleton next to the data it applies to
      -- improves first-draft compliance for ~80 bytes.
      local upsert_header =
           "CHAIN BUILD = UPSERT (read this rule before writing code):\n"
        .. "  local fx = reaper.TrackFX_GetByName(tr, \"<bare name>\", false)\n"
        .. "  if fx < 0 then\n"
        .. "    fx = reaper.TrackFX_AddByName(tr, \"<format-prefixed id>\", false, -1)\n"
        .. "  end\n"
        .. "  if fx < 0 then ShowMessageBox + return end\n"
        .. "Apply to EVERY plugin in the chain. The static UPSERT-VALIDATOR "
        .. "rejects direct AddByName-only chains and forces a retry.\n"
        .. "HELPERS YOU CALL MUST BE PASTED: if your script calls "
        .. "set_param_display / set_param_enum / set_param_enum_paced / "
        .. "find_param, paste each helper's `local function NAME(...) end` "
        .. "source from prompt_bundle:plugin_helpers ABOVE main(). The "
        .. "static HELPER-VALIDATOR rejects called-but-undefined helpers "
        .. "and forces a retry.\n\n"
      Net.sticky_set("fx_chains", upsert_header .. fx_snapshot, "preempt")
      S.fx_chains_already_sent = true
      injected[#injected+1] = "fx_chains"
      Log.line("PREEMPT",
        "injected fx_chains (chain-phrase follow-up; lets the model "
        .. "honor ADD-VS-REUSE)")
    end
  end

  -- Scan docs-phrase hints. Each match pre-pins the docs:<section> bucket
  -- so the model doesn't need to emit <context_needed>docs:envelopes</context_needed>
  -- (etc.) on a follow-up. Idempotent via S.docs_section_sent + the sticky
  -- "already pinned" check. Errors are non-fatal (logged) -- a missing
  -- section file doesn't block the user's request.
  S.docs_section_sent = S.docs_section_sent or {}
  local sec_seen = {}
  for _, hint in ipairs(DOCS_PHRASE_HINTS) do
    if text:find(hint[1]) then
      local section = hint[2]
      if not sec_seen[section] then
        sec_seen[section] = true
        local sticky_key = "docs:" .. section
        if not S.sticky_context[sticky_key]
           and not S.docs_section_sent[section] then
          local sec_content, sec_err = CTX.docs_section(section)
          if sec_content then
            Net.sticky_set(sticky_key, sec_content)
            S.docs_section_sent[section] = true
            injected[#injected+1] = sticky_key
            Log.line("PREEMPT",
              "injected " .. sticky_key .. " (docs phrase: '" .. hint[1] .. "')")
          else
            Log.line("PREEMPT",
              "wanted to inject " .. sticky_key
              .. " but loader failed: " .. (sec_err or "?"))
          end
        end
      end
    end
  end
  if CTX.prompt_indicates_drum_edit(user_text) then
    local drums_key = "prompt_bundle:drums"
    local drums_already = S.sticky_context[drums_key]
    Net.copin_jsfx_family("drums", injected)
    if not drums_already and S.sticky_context[drums_key] then
      Log.line("PREEMPT",
        "injected " .. drums_key .. " (drum edit/quantize workflow)")
    end
    local docs_already = S.api_ref_message ~= nil
    Net.copin_docs_core(injected)
    if not docs_already and S.api_ref_message then
      Log.line("PREEMPT",
        "injected docs (drum edit/quantize workflow)")
    end
    if not S.sticky_context["docs_extended"]
       and not S.docs_extended_already_sent then
      S.docs_extended_already_sent = true
      local ext_content, ext_err = CTX.docs_extended()
      if ext_content then
        Net.sticky_set("docs_extended", ext_content)
        injected[#injected+1] = "docs_extended"
        Log.line("PREEMPT",
          "injected docs_extended (drum edit/quantize workflow)")
      else
        Log.line("PREEMPT",
          "wanted to inject docs_extended for drum edit/quantize but "
          .. "loader failed: " .. (ext_err or "?"))
      end
    end
    for _, section in ipairs({ "items", "tempo" }) do
      local sticky_key = "docs:" .. section
      if not S.sticky_context[sticky_key]
         and not S.docs_section_sent[section] then
        local sec_content, sec_err = CTX.docs_section(section)
        if sec_content then
          Net.sticky_set(sticky_key, sec_content)
          S.docs_section_sent[section] = true
          injected[#injected+1] = sticky_key
          Log.line("PREEMPT",
            "injected " .. sticky_key
            .. " (drum edit/quantize workflow)")
        else
          Log.line("PREEMPT",
            "wanted to inject " .. sticky_key
            .. " for drum edit/quantize but loader failed: "
            .. (sec_err or "?"))
        end
      end
    end
  end
  if timecode_generator_intent then
    local docs_already = S.api_ref_message ~= nil
    Net.copin_docs_core(injected)
    if not docs_already and S.api_ref_message then
      Log.line("PREEMPT",
        "injected docs (native timecode-generator workflow)")
    end
    if not S.sticky_context["docs_extended"]
       and not S.docs_extended_already_sent then
      S.docs_extended_already_sent = true
      local ext_content, ext_err = CTX.docs_extended()
      if ext_content then
        Net.sticky_set("docs_extended", ext_content)
        injected[#injected+1] = "docs_extended"
        Log.line("PREEMPT",
          "injected docs_extended (native timecode-generator workflow)")
      else
        Log.line("PREEMPT",
          "wanted to inject docs_extended for native timecode generator "
          .. "but loader failed: " .. (ext_err or "?"))
      end
    end
    local section = "routing"
    local sticky_key = "docs:" .. section
    if not S.sticky_context[sticky_key]
       and not S.docs_section_sent[section] then
      local sec_content, sec_err = CTX.docs_section(section)
      if sec_content then
        Net.sticky_set(sticky_key, sec_content)
        S.docs_section_sent[section] = true
        injected[#injected+1] = sticky_key
        Log.line("PREEMPT",
          "injected " .. sticky_key
          .. " (native timecode-generator output routing)")
      else
        Log.line("PREEMPT",
          "wanted to inject " .. sticky_key
          .. " for native timecode generator but loader failed: "
          .. (sec_err or "?"))
      end
    end
  end
  if forbids_fx_addition and not jsfx_intent then
    return injected
  end
  if timecode_generator_intent and not jsfx_intent then
    Log.line("PREEMPT",
      "skipped plugin_ref/pref keyword loop (native timecode-generator workflow)")
    return injected
  end
  -- JSFX effect-family bundles (jsfx_pitch, jsfx_reverb, ...). Each match
  -- pins the family bundle ON TOP OF the always-on prompt_bundle:jsfx
  -- core. Multiple families can fire in one turn (e.g. "shimmer chorus"
  -- would trigger jsfx_pitch + jsfx_modulation if both are registered).
  local fam_seen = {}
  for _, hint in ipairs(JSFX_FAMILY_HINTS) do
    if text:find(hint[1]) then
      local family = hint[2]
      if not fam_seen[family] then
        fam_seen[family] = true
        local pb_key = "prompt_bundle:" .. family
        local already_pinned = S.sticky_context[pb_key]
        Net.copin_jsfx_family(family, injected)
        if not already_pinned and S.sticky_context[pb_key] then
          Log.line("PREEMPT",
            "injected " .. pb_key .. " (jsfx phrase: '" .. hint[1] .. "')")
        end
      end
    end
  end

  -- Whenever JSFX intent is detected -- even for a generic request like
  -- "hall reverb" with no family-hint match -- pre-pin the base
  -- `prompt_bundle:jsfx` and `docs` (REAPER core API ref). The base bundle
  -- carries the safety mandates (feedback clamp, no output saturator,
  -- output-stage rules, srate / num_ch / play_state JSFX builtins) that
  -- weak models like GPT-5.4-mini-no-thinking won't request via
  -- <context_needed>; they just generate from training memory and produce
  -- typos like `samplespersec` (instead of `srate`) plus output sliders
  -- the bundle would have forbidden. Pre-pinning closes that hole.
  --
  -- Idempotent via the sticky_context already-pinned check inside
  -- Net.copin_jsfx_family / Net.copin_docs_core.
  if jsfx_intent then
    local base_key = "prompt_bundle:jsfx"
    local base_already = S.sticky_context[base_key]
    Net.copin_jsfx_family("jsfx", injected)
    if not base_already and S.sticky_context[base_key] then
      Log.line("PREEMPT",
        "injected " .. base_key .. " (JSFX intent: any JSFX request)")
    end
    local docs_already = S.api_ref_message ~= nil
    Net.copin_docs_core(injected)
    if not docs_already and S.api_ref_message then
      Log.line("PREEMPT",
        "injected docs (co-pin for JSFX Lua-companion path)")
    end
    local wants_memory_cookbook =
         text:find("%f[%w]delay%f[%W]")
      or text:find("%f[%w]delays%f[%W]")
      or text:find("%f[%w]echo%f[%W]")
      or text:find("%f[%w]reverb")
      or text:find("%f[%w]chorus")
      or text:find("%f[%w]flang")
      or text:find("%f[%w]phaser")
      or text:find("%f[%w]comb%f[%W]")
      or text:find("%f[%w]allpass%f[%W]")
      or text:find("%f[%w]diffus")
      or (text:find("%f[%w]feedback%f[%W]") and text:find("%f[%w]modulat"))
    if wants_memory_cookbook then
      local cookbook_key = "prompt_bundle:jsfx_dsp_cookbook"
      local cookbook_already = S.sticky_context[cookbook_key]
      Net.copin_jsfx_family("jsfx_dsp_cookbook", injected)
      if not cookbook_already and S.sticky_context[cookbook_key] then
        Log.line("PREEMPT",
          "injected " .. cookbook_key .. " (JSFX delay/reverb memory intent)")
      end
    end
  end
  -- Dev-only: when the FabFilter-hide flag is on, treat matching entries
  -- in preferred_types as absent so the preempt path falls through to
  -- "no pref set" behavior (emits resolve:<type> and fires the popup we
  -- want to test). Read the flag fresh from ExtState rather than prefs
  -- so it stays current even if the dev_signal refresh didn't reach the
  -- main loop. Matches the same gate applied in CTX.preferred_plugins
  -- and CTX.load_pref_plugins.
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
  -- Sorted key iteration for deterministic sticky_context ordering (keeps
  -- provider caches stable across turns when the same set of types hits).
  local keys = {}
  for k in pairs(pref_types) do keys[#keys+1] = k end
  table.sort(keys)
  local aliases_by_pref_type = {}
  if pref_plugins and pref_plugins.alias_lookup then
    for alias, key in pairs(pref_plugins.alias_lookup() or {}) do
      alias = tostring(alias or ""):lower()
      key = tostring(key or ""):lower()
      local skip_scan_alias =
        alias == "" or alias == key or #alias < 3 or
        alias == "a" or alias == "an" or alias == "the" or
        alias == "add" or alias == "make" or alias == "create" or
        alias == "set" or alias == "setup" or alias == "route" or
        alias == "send" or alias == "sends" or
        alias == "track" or alias == "tracks" or alias == "bus" or alias == "buses" or
        alias == "fx" or alias == "selected" or alias == "selection" or
        alias == "master" or alias == "folder" or
        alias == "drive" or alias == "limit" or alias == "echo" or
        alias == "tuner" or alias == "multiband"
      if not skip_scan_alias and key ~= "" then
        local list = aliases_by_pref_type[key]
        if not list then
          list = {}
          aliases_by_pref_type[key] = list
        end
        list[#list+1] = alias
      end
    end
    for _, list in pairs(aliases_by_pref_type) do table.sort(list) end
  end
  local explicit_type_named = {}
  do
    local by_type = {
      ReaEQ = "eq", ReEQ = "eq", ["Pro-Q 4"] = "eq",
      ReaComp = "compressor", ["Pro-C 3"] = "compressor",
      ReaXcomp = "multiband_compressor", ["Pro-MB"] = "multiband_compressor",
      ReaGate = "gate", ["Pro-G"] = "gate",
      ReaDelay = "delay", ["Timeless 3"] = "delay",
      ReaLimit = "limiter", ["Pro-L 2"] = "limiter",
      ReaPitch = "pitch_shift", ReaTune = "pitch_correction",
      ReaSynth = "synth", ReaVerbate = "reverb", ["Pro-R 2"] = "reverb",
      ["Pro-DS"] = "deesser", ["Saturn 2"] = "saturation",
    }
    for curated_name, tkey in pairs(by_type) do
      if text:find(curated_name:lower(), 1, true) then
        explicit_type_named[tkey] = curated_name
      end
    end
  end
  -- Curated-pref dispatch shared with the resolve handler: when the user's
  -- saved preference for a type matches a CURATED_IDENT entry, both paths
  -- route through plugin_ref:<Name> instead of the live-scan
  -- preferred_plugins:<type>. The map lives at module scope (see
  -- CURATED_IDENT definition near PLUGIN_REF_ALIASES) so both the preempt
  -- and resolve paths stay in lockstep when the list is extended.
  --
  -- JSFX-intent skip: when the user explicitly asked for JSFX, do not pin
  -- any plugin_ref / pref / plugin bundle / docs core via this loop. The
  -- type-keyword match (e.g. "reverb" in "create a JSFX shimmer reverb")
  -- triggers all four pins on a Pro-R 2 user; the model never reads any of
  -- them while writing EEL2, and the docs co-pin alone is ~19K input
  -- tokens of waste. The docs-gate inside Net.try_finish_curl is
  -- still the safety net if the model does emit a Lua companion that
  -- needs reaper.* signatures.
  if jsfx_intent then
    if #keys > 0 then
      Log.line("PREEMPT",
        "skipped plugin_ref/pref keyword loop (JSFX intent)")
    end
    return injected
  end

  -- Direct curated-plugin-name preempt: when the user names a curated
  -- plugin in the prompt ("Add Pro-Q 4 to every track..."), pin
  -- plugin_ref:<Name> immediately even when no type-keyword ("eq")
  -- appears. Without this, the model has to emit
  -- <context_needed>fx_inspect:Pro-Q 4 + prompt_bundle:plugin</context_needed>
  -- on the first turn and then a SECOND retry once the docs gate fires --
  -- 3 calls instead of 1 for what's clearly a curated-plugin task. For
  -- each match, also pin pref:<tkey> if any saved pref maps to the same
  -- curated name (so the model gets the "this IS your saved pref" signal
  -- and skips a defensive resolve emission).
  local curated_unique = {}
  for _, name in pairs(CURATED_IDENT) do curated_unique[name] = true end
  for curated_name in pairs(curated_unique) do
    if text:find(curated_name:lower(), 1, true) then
      if preempt_live_fx_params
         and CTX.preempt_live_fx_params_for_ident(curated_name, injected,
           "direct curated name match", Code.prompt_has_param_write_intent(user_text)) then
        goto continue_curated_name
      end
      local pr_key = "plugin_ref:" .. curated_name
      if not S.sticky_context[pr_key]
         and not (S.plugin_ref_sent or {})[curated_name] then
        local rp_content, _ = CTX.plugin_ref({curated_name})
        if rp_content then
          CTX.populate_installed_fx()
          local exact_ident = nil
          if Code.resolve_chain_entry and CTX._installed_fx_list then
            exact_ident = Code.resolve_chain_entry(curated_name, CTX._installed_fx_list)
          end
          local prefix = ""
          if exact_ident and exact_ident ~= curated_name then
            prefix = "AddByName identifier on this system: `" .. exact_ident
              .. "` -- use this EXACT string with TrackFX_AddByName.\n\n"
          end
          Net.sticky_set(pr_key, prefix .. rp_content)
          if S.plugin_ref_sent then S.plugin_ref_sent[curated_name] = true end
          Net.copin_plugin_bundle(injected)
          Net.copin_docs_core(injected)
          if preempt_needs_plugin_helpers then
            Net.copin_plugin_helpers(injected, "preempt")
          end
          injected[#injected+1] = pr_key
          Log.line("PREEMPT",
            "injected " .. pr_key .. " (curated content, direct name match)"
            .. (exact_ident and (" exact=" .. exact_ident) or ""))
          -- Reverse-lookup pref:<tkey> if any saved pref maps to this curated.
          for tkey, ident in pairs(pref_types) do
            local mapped = ident and _curated_for_ident(ident) or nil
            if mapped == curated_name then
              if hide_ff and _is_fabfilter_ident(ident) then break end
              local pp_key = "pref:" .. tkey
              if not S.sticky_context[pp_key]
                 and not (S.pref_plugins_sent or {})[tkey] then
                local hint = "PREFERRED PLUGINS:\n"
                  .. "  " .. tkey .. " = " .. (exact_ident or ident or curated_name) .. "\n"
                  .. "(User's saved preference; full parameter reference above "
                  .. "in plugin_ref:" .. curated_name .. ". Use this plugin directly "
                  .. "and do NOT emit <context_needed>resolve:" .. tkey
                  .. "</context_needed>. For add-only/load-only tasks (no parameter "
                  .. "values set), use the AddByName identifier directly -- do NOT "
                  .. "emit <context_needed>fx_inspect:" .. (exact_ident or ident or curated_name)
                  .. "</context_needed> just to load the plugin. After every "
                  .. "TrackFX_AddByName, the next non-blank line MUST be `if "
                  .. "fx < 0 then ShowMessageBox(...) return end` before "
                  .. "using fx -- the static FX-CHECK-VALIDATOR rejects "
                  .. "unchecked AddByName results and forces a retry.)"
                Net.sticky_set(pp_key, hint)
                if S.pref_plugins_sent then S.pref_plugins_sent[tkey] = true end
                injected[#injected+1] = pp_key
                Log.line("PREEMPT",
                  "injected " .. pp_key .. " (pref hint for curated " .. curated_name .. ")")
              end
              break
            end
          end
        end
      end
    end
    ::continue_curated_name::
  end

  if stock_fx_constraint then
    if #keys > 0 then
      Log.line("PREEMPT",
        "skipped preferred-plugin keyword loop (explicit stock FX constraint)")
    end
    return injected
  end

  for _, tkey in ipairs(keys) do
    -- Word-boundary match so "eq" doesn't fire on "equal" / "sequence".
    -- %b pattern wouldn't help here; %f[%w] + %f[%W] brackets catch whole
    -- words including hyphenated ones like "de-esser".
    -- ALSO trigger when a CHAIN_PHRASE_HINTS entry implied this type (e.g.
    -- "drum kit" implies eq + compressor + gate). The phrase scan above
    -- populated phrase_implied[tkey] with the matching pattern so the log
    -- can attribute the trigger.
    local pat = "%f[%w]" .. tkey:gsub("(%W)", "%%%1") .. "%f[%W]"
    local kw_hit     = text:find(pat) ~= nil
    local alias_hit  = nil
    if not kw_hit then
      for _, alias in ipairs(aliases_by_pref_type[tkey] or {}) do
        local alias_pat = "%f[%w]" .. alias:gsub("(%W)", "%%%1") .. "%f[%W]"
        if text:find(alias_pat) ~= nil then
          alias_hit = alias
          break
        end
      end
    end
    local phrase_hit = phrase_implied[tkey]
    if kw_hit or alias_hit or phrase_hit then
      local trigger = kw_hit
        and ("keyword match in user prompt")
        or  (alias_hit and ("alias match in user prompt: '" .. alias_hit .. "'"))
        or  ("chain-phrase match: '" .. phrase_hit .. "'")
      if explicit_type_named[tkey] then
        Log.line("PREEMPT",
          "skipped " .. tkey .. " preferred-plugin preempt (exact plugin named: "
          .. explicit_type_named[tkey] .. ")")
        goto continue_preempt
      end
      local ident = pref_types[tkey]
      if hide_ff and _is_fabfilter_ident(ident) then
        ident = nil
      end
      -- When the filter (or a missing cache entry) leaves ident empty, skip
      -- the whole preempt for this type. Pinning a "no pref set" sticky
      -- here + marking pref_plugins_sent[tkey] would make the resolve
      -- dispatcher dedupe the model's <context_needed>resolve:<tkey></context_needed>
      -- request -- and the sticky itself tells the model to emit that
      -- tag -- so the two paths would chase each other forever. Letting
      -- the preempt fall through lets the resolve handler fire the popup.
      if not ident or ident == "" then
        goto continue_preempt
      end
      if preempt_live_fx_params
         and CTX.preempt_live_fx_params_for_ident(ident, injected,
           trigger, Code.prompt_has_param_write_intent(user_text)) then
        goto continue_preempt
      end
      if Code.prompt_has_param_write_intent(user_text)
         and CTX.sticky_has_fx_params_for_ident(ident) then
        Net.copin_plugin_bundle(injected)
        Net.copin_docs_core(injected)
        Net.copin_plugin_helpers(injected, "preempt")
        Log.line("PREEMPT",
          "skipped " .. tkey .. " plugin_ref (scoped live fx_params already pinned)")
        goto continue_preempt
      end
      -- Use the prefix/vendor-tolerant lookup so canonicalized prefs
      -- ("VST3: Pro-Q 4") still resolve to the curated section. A direct
      -- CURATED_IDENT[ident] would only match bare chain-entry form and
      -- would silently bypass curated plugin_ref content for every
      -- FabFilter pref after the preferred_types canonicalization.
      local curated = ident and _curated_for_ident(ident) or nil
      if curated then
        -- Curated plugin: inject plugin_ref:<Name> instead of
        -- preferred_plugins:<type>. Richer content, and doesn't depend
        -- on cache.plugins having scanned param data for the JSFX/stock.
        -- Also prepend the best enumerated identifier (e.g. "VST3: Pro-Q 4")
        -- so the model uses the exact format-prefixed string for
        -- TrackFX_AddByName -- prevents the bare-name fuzzy-match from
        -- loading a wrong version/format when multiple are installed.
        local pr_key = "plugin_ref:" .. curated
        if not S.sticky_context[pr_key]
           and not (S.plugin_ref_sent or {})[curated] then
          local rp_content, _ = CTX.plugin_ref({curated})
          if rp_content then
            local preferred_ident = ident
            if FXCache and FXCache.canonicalize_identifier then
              preferred_ident = FXCache.canonicalize_identifier(tkey, ident)
            end
            -- Resolve the chain entry to the exact enumerated identifier
            -- (e.g. "Pro-Q 4" -> "VST3: Pro-Q 4") so the model uses the
            -- format-prefixed form. populate_installed_fx is cached -- the
            -- first preempt pays the one-time enumeration walk.
            CTX.populate_installed_fx()
            local exact_ident = nil
            if Code.resolve_chain_entry and preferred_ident
               and CTX._installed_fx_list then
              exact_ident = Code.resolve_chain_entry(preferred_ident,
                CTX._installed_fx_list)
            end
            if exact_ident and FXCache and FXCache.canonicalize_identifier then
              exact_ident = FXCache.canonicalize_identifier(tkey, exact_ident)
            end
            local prefix = ""
            if exact_ident and exact_ident ~= preferred_ident then
              prefix = "AddByName identifier on this system: `" .. exact_ident
                .. "` -- use this EXACT string with TrackFX_AddByName.\n\n"
            end
            Net.sticky_set(pr_key, prefix .. rp_content)
            if S.plugin_ref_sent then S.plugin_ref_sent[curated] = true end
            -- Piggyback prompt_bundle:plugin onto every plugin_ref pin: any
            -- plugin ADD/CONFIGURE task needs the plugin workflow rules, and
            -- co-pinning here saves the round-trip where the model would
            -- otherwise emit <context_needed>prompt_bundle:plugin</context_needed>.
            Net.copin_plugin_bundle(injected)
            -- Same rationale for docs core: every plugin add/configure task
            -- needs reaper.* signatures (TrackFX_*, defer, Undo_*). Without
            -- this, the rich plugin context biases the model into bypassing
            -- the API REF REQUIREMENT rule and the docs-gate has to retry.
            Net.copin_docs_core(injected)
            -- Co-pin plugin_helpers ON THE SAME TURN as plugin_bundle so
            -- helpers rides the stable rung's first emission instead of
            -- arriving mid-session via <context_needed>. Tagged "preempt"
            -- so Net.sticky_parts routes it to the stable rung (along with
            -- plugin_bundle) instead of growing -- the stable rung is
            -- being initialized this turn anyway, so adding helpers costs
            -- no extra cache miss but saves the helpers re-write that
            -- would otherwise happen on every subsequent growing-rung
            -- invalidation (each new plugin_ref / pref / fx_inspect).
            --
            -- Pre-pin helpers for explicit value writes and open-ended
            -- chain phrases. Add-only prompts ("add Pro-Q to track 1") still
            -- skip the ~17.8K-char helper bundle, but "build a vocal chain"
            -- / "chain suitable for a rock vocal" usually makes the model
            -- choose display-unit values and helper calls on its own. Pinning
            -- helpers here prevents the missing-helper retry for that family.
            if preempt_needs_plugin_helpers then
              Net.copin_plugin_helpers(injected, "preempt")
            end
            injected[#injected+1] = pr_key
            Log.line("PREEMPT",
              "injected " .. pr_key .. " (curated content, " .. trigger .. ")"
              .. (exact_ident and (" exact=" .. exact_ident) or ""))
            -- Co-pin a compact pref:<tkey> hint. Without it, the model
            -- sees plugin_ref:<Name> pinned but can't tell whether the name
            -- is the user's saved preference or just a curated default,
            -- and defensively emits <context_needed>resolve:<tkey></context_needed>
            -- to re-confirm -- a wasted round-trip (observed on the first
            -- plugin-type turn of every session). The pref:<tkey> entry
            -- gives the model an unambiguous "yes this IS the user's pref"
            -- signal, so it skips the resolve and writes code directly.
            -- Also marks pref_plugins_sent so the resolve dedup path fires
            -- if the model still emits resolve anyway.
            local pp_key = "pref:" .. tkey
            if not S.sticky_context[pp_key]
               and not (S.pref_plugins_sent or {})[tkey] then
              local add_ident = exact_ident or preferred_ident or ident or curated
              local hint = "PREFERRED PLUGINS:\n"
                .. "  " .. tkey .. " = " .. add_ident .. "\n"
                .. "(User's saved preference; full parameter reference above "
                .. "in plugin_ref:" .. curated .. ". Use this plugin directly "
                .. "and do NOT emit <context_needed>resolve:" .. tkey
                .. "</context_needed>. For add-only/load-only tasks (no parameter "
                .. "values set), use the AddByName identifier directly -- do NOT "
                .. "emit <context_needed>fx_inspect:" .. add_ident
                .. "</context_needed> just to load the plugin. After every "
                .. "TrackFX_AddByName, the next non-blank line MUST check "
                .. "`if fx < 0 then ... return end` before storing or using "
                .. "the FX index.)"
              Net.sticky_set(pp_key, hint)
              if S.pref_plugins_sent then S.pref_plugins_sent[tkey] = true end
              injected[#injected+1] = pp_key
              Log.line("PREEMPT",
                "injected " .. pp_key .. " (pref hint for curated " .. curated .. ")")
            end
          end
        end
      else
        -- Non-curated plugin: inject preferred_plugins:<type>.
        local pp_key = "pref:" .. tkey
        if not S.sticky_context[pp_key]
           and not (S.pref_plugins_sent or {})[tkey] then
          local pp_content, pp_err = CTX.preferred_plugins({tkey})
          if pp_content then
            -- Always-on directive (conditional in wording): tells the
            -- model that for add-only/load-only tasks the AddByName
            -- identifier in pp_content is sufficient, and fx_inspect
            -- isn't needed just to load the plugin. Without this, the
            -- model defensively emits <context_needed>fx_inspect:Name</context_needed>
            -- on add-only synth/instrument tasks even when pref already
            -- pins the AddByName string -- observed costing one extra
            -- API call on a "create a synth track + MIDI item" prompt
            -- where Twin 3 was already in pref:synth.
            local pp_directive = "\n\nDIRECTIVE: For add-only/load-only "
              .. "tasks (no parameter values set), use the AddByName "
              .. "identifier above directly with TrackFX_AddByName. Do "
              .. "NOT emit <context_needed>fx_inspect:Name</context_needed> "
              .. "just to load the plugin -- the parameter map is only "
              .. "needed when configuring values. After every "
              .. "TrackFX_AddByName, the next non-blank line MUST be `if "
              .. "fx < 0 then ShowMessageBox(...) return end` before using "
              .. "fx -- the static FX-CHECK-VALIDATOR rejects unchecked "
              .. "AddByName results and forces a retry."
            Net.sticky_set(pp_key, pp_content .. pp_directive)
            -- Mark sent so the model's <context_needed>preferred_plugins:tkey
            -- (if it emits one anyway) gets deduped by the bucket dispatcher.
            if S.pref_plugins_sent then S.pref_plugins_sent[tkey] = true end
            -- Co-pin plugin bundle + docs core (same rationale as the
            -- plugin_ref branch above: every pref-plugin pin drives a
            -- plugin task that needs both the workflow guide and the
            -- reaper.* signatures). Helpers rides the stable rung via
            -- the "preempt" source tag when this is an explicit value write
            -- or an open-ended chain phrase.
            Net.copin_plugin_bundle(injected)
            Net.copin_docs_core(injected)
            if preempt_needs_plugin_helpers then
              Net.copin_plugin_helpers(injected, "preempt")
            end
            injected[#injected+1] = pp_key
            Log.line("PREEMPT",
              "injected " .. pp_key .. " (" .. trigger .. ")")
          end
        end
      end
    end
    ::continue_preempt::
  end
  return injected
end

-- True when a normal session snapshot should include routing/sends. Routing is
-- useful for send/bus/sidechain questions but expensive and noisy for routine
-- edits, so it is opt-in based on prompt wording.
function CTX.prompt_wants_routing_snapshot(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  if lt:find("send level", 1, true)
      or lt:find("send volume", 1, true)
      or lt:find("send gain", 1, true)
      or lt:find("level of the send", 1, true)
      or lt:find("volume of the send", 1, true)
      or lt:find("%f[%w]sends%f[%W]")
      or lt:find("%f[%w]receives%f[%W]")
      or lt:find("%f[%w]receive%s+from%f[%W]")
      or lt:find("%f[%w]send%s+to%f[%W]")
      or lt:find("%f[%w]send%s+into%f[%W]")
      or lt:find("%f[%w]route%s+to%f[%W]")
      or lt:find("%f[%w]routed%s+to%f[%W]")
      or lt:find("%f[%w]routing%f[%W]")
      or lt:find("%f[%w]sidechain%f[%W]")
      or lt:find("%f[%w]aux%f[%W]")
      or lt:find("%f[%w]bus%f[%W]")
      or lt:find("return track", 1, true) then
    return true
  end
  return false
end

-- CTX.build_snapshot(proj, opts)
-- opts.minimal_tracks: emit a tracks-list trimmed to selected tracks +
-- count summary instead of the full per-track listing. Used by JSFX-only
-- prompts where the snapshot ships with a "create me an effect file"
-- request and the per-track names/item counts are dead weight.
-- The minimal listing bypasses the heavy-cache to keep the regular path
-- unaffected (the cache stores the full listing; reusing it across modes
-- would either return the wrong shape on a re-entry or require keying the
-- cache by mode).
CTX.build_snapshot = function(proj, opts)
  local minimal_tracks = opts and opts.minimal_tracks
  local drum_edit = (opts and opts.drum_edit) or S.pending_drum_edit_intent
  local state_count = reaper.GetProjectStateChangeCount(proj or 0)
  local c = CTX._snapshot_heavy_cache
  local tracks_txt, markers_txt
  if minimal_tracks then
    tracks_txt  = CTX.tracks(proj, { minimal = true })
    if c and c.proj == proj and c.state_count == state_count then
      markers_txt = c.markers
    else
      markers_txt = CTX.markers(proj)
    end
  elseif c and c.proj == proj and c.state_count == state_count then
    tracks_txt  = c.tracks
    markers_txt = c.markers
  else
    tracks_txt  = CTX.tracks(proj)
    markers_txt = CTX.markers(proj)
    CTX._snapshot_heavy_cache = {
      proj        = proj,
      state_count = state_count,
      tracks      = tracks_txt,
      markers     = markers_txt,
    }
  end
  local parts = {
    CTX.reaper_version(),
    CTX.tempo(proj),
    CTX.sample_rate(proj),
    CTX.play_state(proj),
    CTX.loop(proj),
    markers_txt,
    tracks_txt,
    CTX.selected(proj),
    CTX.time_selection(proj),
    CTX.cursor(proj),
    CTX.selected_items(proj, {
      include_names = CTX.prompt_wants_selected_item_names(
        S.pending_orig_prompt),
    }),
  }
  if not minimal_tracks
      and CTX.prompt_wants_routing_snapshot(S.pending_orig_prompt) then
    parts[#parts + 1] = CTX.sends(proj, {})
  end
  if drum_edit then parts[#parts + 1] = CTX.dynamic_split_settings() end
  -- Multi-row sections (Tracks, FX chains, Track flags, Markers/regions,
  -- Selected items) use a compact pipe-delimited format with a header row
  -- declaring the columns. This shaves ~15-25% snapshot tokens on large
  -- sessions vs the previous prose form. Single-value lines remain
  -- human-readable. Selected item names are included only when the prompt
  -- explicitly asks about selected items/names, not on every context send.
  -- Pipe characters in track/item names are scrubbed to "_" to keep parsing
  -- trivial.
  local body = "SESSION CONTEXT (multi-row sections use pipe-delimited rows -- "
    .. "see each section's [col|col|...] header for column names):\n"
    .. tbl_concat(parts, "\n") .. "\n\n"
  local hint = CTX.target_hint(proj, S.pending_orig_prompt)
  if hint ~= "" then body = body .. hint .. "\n\n" end
  return body
end
