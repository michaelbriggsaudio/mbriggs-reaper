-- =============================================================================
-- ReaAssist - REAPER Smart Assistant
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
--
-- Use of this software is permitted through official distribution channels
-- (ReaPack, GitHub release downloads). Users may modify it locally for
-- personal use, including the documented ReaAssist_System_Prompt_Custom.md
-- override mechanism. Redistribution, resale, sublicensing, repackaging,
-- and presenting this software (modified or unmodified) as your own are
-- prohibited without prior written permission. See LICENSE.txt.
-- =============================================================================

-- ReaAssist.lua
-- REAPER Smart Assistant: sends prompts to Claude, ChatGPT, Gemini, or a
-- custom OpenAI-compatible endpoint; displays responses in a ReaImGui chat
-- window; executes returned Lua code inside REAPER; installs JSFX effects.
--
-- Architecture:
--   - Optional SESSION CONTEXT snapshot (tempo, tracks, FX, markers, cursor,
--     items) is injected into each API call when enabled; never stored in
--     S.history, so older turns never carry stale project state.
--   - On-demand context buckets (session, docs, plugin_ref, fx_params, fx_list,
--     fx_chains, track_flags, midi, theme, preferred_plugins) are requested via
--     <context_needed>...</context_needed> and fetched on a follow-up round-trip.
--   - Pinned API reference is sent as a stable first message so the provider's
--     prompt cache hits every turn after the first load.
--   - Multi-project-tab safe: active project captured at send time.
--   - First-run flow: Terms of Use screen, then API key entry with validation.
--
-- Requirements: ReaImGui (via ReaPack), at least one provider key, curl on PATH,
-- and ReaAssist_System_Prompt.md in Resources/. See CHANGELOG.md for features.

-- ReaImGui constraints for this environment -- DO NOT REMOVE:
--   - ImGui_End must be paired with every ImGui_Begin (standard Dear
--     ImGui contract). Begin returns false when the window is collapsed
--     or fully clipped to indicate widget submission can be skipped, but
--     End must still be called either way. All Begin/End pairs in this
--     codebase put End() OUTSIDE the `if visible then` block.
--   - The open bool (X button) must be checked OUTSIDE/AFTER that block.
--   - ImGui_TextWrapped corrupts window state when passed strings containing \n.
--     Use UI.selectable_text() for all multi-line chat content (pre-wraps in Lua).
--   - ImGui_Begin open-bool only works correctly when passed literal true.
--   - ImGui_InputTextFlags_ReadOnly() returns a userdata incompatible as a flags
--     integer; use flags=0 and discard the returned buffer for display-only fields.
--   - ImGui_InputTextMultiline does not honour NoHorizontalScroll reliably;
--     word-wrap is handled by UI.wrap_text() in Lua before passing text to the widget.
--   - ImGui_BeginChild: use ImGui_ChildFlags_Borders() for borders (not a bool).
--   - ImGui_PushFont requires 3 arguments: (ctx, font, size_override).
--     Pass 0 as size_override to use the font's default size.
--   - Use plain ASCII in source (comments + identifiers) to avoid encoding
--     pitfalls when distributing across Win/Mac/Linux. The one intentional
--     exception is the AppleScript guillemets at the macOS clipboard-as-PNG
--     site (set imgData to the clipboard as <<class PNGf>>); AppleScript
--     has no ASCII alternative for that record-class reference syntax.

-- =============================================================================
-- ReaImGui availability check
-- =============================================================================
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox([[
ReaAssist requires the ReaImGui extension.

To install it:
1. Open REAPER's Extensions menu and click ReaPack > Browse Packages
2. Search for "ReaImGui"
3. Right-click the result and select Install
4. Click Apply in the lower-right corner
5. Restart REAPER, then re-run this script

If you do not see a ReaPack menu entry, install ReaPack first from:
https://reapack.com]], "ReaAssist - Missing Dependency", 0)
  return
end
local ImGui = reaper  -- secondary alias used for ImGui calls (reads as ImGui.ImGui_*)

-- =============================================================================
-- RA: shared-state namespace for cross-file access
-- =============================================================================
-- Shared state namespace read by both files (main + Resources/ReaAssist_UI.lua).
-- Covers items that would otherwise be bare globals: the ImGui context,
-- UI-scale helper, path constants, OS flags, shared font handles, and
-- the sel_cb EEL callback. Pre-existing namespaces (S, CFG, TK, COL,
-- FONT, prefs, Log, Net, UI, Render, ...) stay as plain globals.
RA = {}


-- =============================================================================
-- LOCAL ALIASES
-- Lua resolves local variables faster than global/table lookups.
-- Caching frequently-called functions here gives a measurable speedup in the
-- snapshot inner loops (track/FX/item iteration) and the per-character JSON
-- decode path. Standard library aliases also benefit the draw loop helpers.
-- =============================================================================

-- Short alias for the reaper global -- matches the style of companion scripts
-- and makes the declaration block below more readable.
local R = reaper

-- Standard library
local str_format  = string.format
local str_find    = string.find
local str_sub     = string.sub
local str_byte    = string.byte
local str_char    = string.char
local str_match   = string.match
local tbl_concat  = table.concat
local tbl_remove  = table.remove
local math_floor  = math.floor
local math_min    = math.min
local math_max    = math.max

-- REAPER timing (called every loop frame and in the single-instance handshake)
local time_precise = R.time_precise

-- REAPER track / item API -- called repeatedly in snapshot inner loops
local R_CountTracks              = R.CountTracks
local R_GetTrack                 = R.GetTrack
local R_GetTrackName             = R.GetTrackName
local R_CountTrackMediaItems     = R.CountTrackMediaItems
local R_GetMediaTrackInfo_Value  = R.GetMediaTrackInfo_Value
local R_IsTrackSelected          = R.IsTrackSelected
local R_TrackFX_GetCount         = R.TrackFX_GetCount
local R_TrackFX_GetFXName        = R.TrackFX_GetFXName
local R_TrackFX_GetNumParams     = R.TrackFX_GetNumParams
local R_TrackFX_GetParamName     = R.TrackFX_GetParamName
local R_TrackFX_GetParam         = R.TrackFX_GetParam
local R_TrackFX_GetFormattedParamValue = R.TrackFX_GetFormattedParamValue
local R_CountSelectedMediaItems  = R.CountSelectedMediaItems
local R_GetSelectedMediaItem     = R.GetSelectedMediaItem
local R_GetMediaItemInfo_Value   = R.GetMediaItemInfo_Value
local R_GetMediaItem_Track       = R.GetMediaItem_Track
local R_EnumProjectMarkers3      = R.EnumProjectMarkers3
local R_CountProjectMarkers      = R.CountProjectMarkers

-- ImGui hot-path aliases. Names match upstream with ImGui_ stripped so
-- call sites stay self-documenting (PushStyleColor(ctx, ...)).
local PushStyleColor     = reaper.ImGui_PushStyleColor
local PopStyleColor      = reaper.ImGui_PopStyleColor
local PushStyleVar       = reaper.ImGui_PushStyleVar
local PushFont           = reaper.ImGui_PushFont
local PopFont            = reaper.ImGui_PopFont
local Text               = reaper.ImGui_Text
local SameLine           = reaper.ImGui_SameLine
local CalcTextSize       = reaper.ImGui_CalcTextSize
local GetCursorPosX      = reaper.ImGui_GetCursorPosX
local SetCursorPosX      = reaper.ImGui_SetCursorPosX
local Dummy              = reaper.ImGui_Dummy

-- =============================================================================
-- Action context (single call, used for toolbar IDs and script path)
-- =============================================================================
-- Destructured once here; avoids a duplicate get_action_context() call.
-- SECTION_ID and CMD_ID are main-file-only (toolbar-toggle use).
-- script_path is cross-file and lives on RA; it is assigned inside
-- the `do` block below via `RA.script_path = asp:match(...)`.
local SECTION_ID, CMD_ID
do
  local _, asp
  _, asp, SECTION_ID, CMD_ID = reaper.get_action_context()
  RA.script_path = asp:match("^(.+[\\/])")
  -- Collapse any `X/../` segments in the action-context path. REAPER
  -- stores action paths verbatim, so if a previous relauncher bug (or
  -- any other code) ever called AddRemoveReaScript with a dot-dot
  -- path, this instance's asp may contain those segments; everything
  -- downstream that concatenates RA.script_path (the relauncher
  -- registration, the "running" ExtState comparison, etc.) inherits
  -- them unless we normalize once here. Loop until the pattern stops
  -- matching so sequences like `a/b/../c/../d/` fully resolve.
  -- Bounded: each match shortens the path by at least 4 chars, so 32
  -- iterations covers any plausible path depth. The cap is purely
  -- defensive against pathological action-registry strings.
  for _ = 1, 32 do
    local normalized, n = RA.script_path:gsub("[^\\/]+[\\/]%.%.[\\/]", "")
    RA.script_path = normalized
    if n == 0 then break end
  end
  local fn = asp:match("[^\\/]+$") or ""
  if not fn:lower():find("reaassist") then
    reaper.ShowMessageBox(
      "This script has been modified and cannot run.",
      "Error", 0)
    return
  end
end

-- Compute the relauncher script path for later on-demand use by
-- Updater.try_auto_restart. The relauncher is only needed when an
-- update / repair completes and we want to re-fire ReaAssist from
-- a separate script context (firing Main_OnCommand on ReaAssist's
-- own CMD_ID from inside ReaAssist's running defer chain triggers
-- REAPER's re-entrance handling, which the single-instance handshake
-- interprets as a toggle-off). Registering the relauncher as an
-- action lazily -- at fire time, not at startup -- keeps it out of
-- the user's Actions list for sessions where no auto-restart ever
-- happens. advance_after_rename checks the file's existence before
-- scheduling restart so the done-view messaging can still pick the
-- right copy ("Restarting..." vs "Close and reopen...") without
-- touching REAPER's action registry until the restart actually fires.
local RELAUNCHER_PATH
do
  -- RA.script_path was set in the previous `do` block; RA.SEP lives
  -- further down in the OS-detection block, so hard-code the
  -- separator here rather than defer this path resolution.
  local sep = package.config:sub(1, 1)
  -- One-shot cleanup of dirty action registrations left behind by an
  -- earlier relauncher bug where REAASSIST_PATH and relauncher_path
  -- were concatenated with `..` segments. REAPER keyed them as
  -- separate actions from the normalized versions, so users ended up
  -- with duplicate entries in the Actions list. Remove-by-path with
  -- commit=true persists the cleanup; subsequent launches no-op.
  reaper.AddRemoveReaScript(false, 0,
    RA.script_path .. "Resources" .. sep .. ".." .. sep .. "ReaAssist.lua",
    true)
  reaper.AddRemoveReaScript(false, 0,
    RA.script_path .. "Resources" .. sep .. ".." .. sep
      .. "Resources" .. sep .. "ReaAssist_Relaunch.lua",
    true)

  RELAUNCHER_PATH = RA.script_path .. "Resources" .. sep
                 .. "ReaAssist_Relaunch.lua"

  -- Defensively unregister any stale relauncher entry. commit=false
  -- was supposed to make the previous run's try_auto_restart
  -- registration session-only, but REAPER persists the action path to
  -- reaper-kb.ini anyway so a fresh REAPER session still sees it in
  -- the Actions list. Always removing at startup with commit=true
  -- flushes that stale row; try_auto_restart re-registers on demand
  -- if and when the next auto-restart actually needs the helper. No-
  -- op if nothing is registered, so cheap on normal launches.
  reaper.AddRemoveReaScript(false, 0, RELAUNCHER_PATH, true)
end

-- =============================================================================
-- OS detection
-- =============================================================================
-- Used for platform-specific curl invocation, font selection, and path separators.
RA.IS_WINDOWS = reaper.GetOS():match("Win") ~= nil
RA.IS_MACOS = reaper.GetOS():match("OS")  ~= nil  -- "OSX" or "macOS"
RA.SEP = RA.IS_WINDOWS and "\\" or "/"

-- JSFX auto-save directory: Effects/ReaAssist/ inside the REAPER resource path.
-- Created on startup so auto-saved JSFX effects have a consistent home.
local JSFX_DIR = reaper.GetResourcePath() .. RA.SEP .. "Effects" .. RA.SEP .. "ReaAssist"
reaper.RecursiveCreateDirectory(JSFX_DIR, 0)

-- Resources directory: holds all .md reference files, the system prompt, the
-- bundled ReEQ source, and runtime-created files (FX cache, debug log).
-- Created on startup so the first file write never fails on a fresh install.
RA.RESOURCES_DIR = RA.script_path .. "Resources" .. RA.SEP
reaper.RecursiveCreateDirectory(RA.RESOURCES_DIR, 0)

RA.FX_CACHE_PATH = RA.RESOURCES_DIR .. "ReaAssist_FX_Cache.json"

-- =============================================================================
-- Toolbar toggle support
-- =============================================================================
-- Reflects the script's on/off state in the REAPER toolbar button.
local function set_toolbar(state)
  if SECTION_ID and CMD_ID and SECTION_ID ~= -1 and CMD_ID ~= -1 then
    reaper.SetToggleCommandState(SECTION_ID, CMD_ID, state and 1 or 0)
    reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
  end
end

-- =============================================================================
-- Single-instance handshake
-- =============================================================================
-- If a second instance is launched, it signals the first to close and exits.
-- ExtState key "running" stores "instance_id|timestamp" so stale locks from
-- hard crashes (process kill, BSOD) can be detected. If the lock is older than
-- 60 seconds, it is treated as stale and claimed by this instance.
-- "request_close" carries the new instance's ID. The running instance checks
-- that the value differs from its own ID to avoid self-shutdown from stale
-- signals. A non-empty, non-self value triggers a graceful close.
CFG = {
  EXT_NS            = "reaassist",
  VERSION           = "1.0.3", -- public release version
  CURL_TIMEOUT      = 1800,      -- curl --max-time HARD CEILING (cloud providers). Stays high (30 min) so curl never bites before the watchdog -- the user-facing timeout is enforced by the watchdog using prefs.cloud_request_timeout, which the user can change in Settings AND can extend mid-request via the "Extend by 60s" button.
  CLOUD_TIMEOUT_DEFAULT = 180,   -- default value for prefs.cloud_request_timeout (the user-facing watchdog timeout for cloud providers)
  CLOUD_TIMEOUT_MIN     = 30,    -- min/max for the Settings input
  CLOUD_TIMEOUT_MAX     = 1800,
  EXTEND_BY_SECS    = 60,        -- "Extend by Ns" button bumps timeout by this many seconds per click
  EXTEND_SHOW_BEFORE_TIMEOUT = 30,  -- show the Extend button when within this many seconds of timeout
  MAX_TOKENS        = 8192,      -- max output tokens per API call (overridden by pref)
  MAX_TOKENS_OPTIONS = { 4096, 8192, 16384, 32768, 65536 },  -- dropdown choices
  UI_SCALE_OPTIONS   = { 0.75, 0.85, 1.0, 1.25, 1.5, 2.0 },  -- UI zoom choices
  UI_SCALE_LABELS    = { "75%", "85%", "100%", "125%", "150%", "200%" },
  CHAT_FONT_SIZES    = { 10, 12, 14 },   -- Small, Medium, Large (px before SC).
  -- Details-card mono font, indexed the same as CHAT_FONT_SIZES so
  -- the Chat Font preference scales both together. Sized -1 px vs the
  -- chat text to preserve the "secondary info" visual hierarchy the
  -- details card has always had (was a fixed SC(11) against chat 12).
  DETAILS_FONT_SIZES = { 9, 11, 13 },
  CHAT_FONT_LABELS   = { "Small", "Medium", "Large" },
  MAX_HISTORY_TURNS = 6,         -- sliding window size (keep even)
  MAX_DISPLAY_MSGS  = 120,       -- soft cap on display_messages; oldest pruned
  MAX_CACHED_PARAMS = 80,        -- per-plugin cap in scan_fx_params / scan_fx_params_deep_body / _estimate_deep_probes (cache file size + LLM context budget)
  WIN_W             = 600,       -- initial window width (user can resize)
  WIN_H             = 800,       -- initial window height
  MAX_API_REF_BYTES = 512 * 1024, -- reject API ref files larger than 512 KB
  POLL_THROTTLE     = 0.1,       -- min interval between poll-loop file checks
  MAX_RETRIES       = 3,         -- max auto-retries on transient 529 failures
  RETRY_DELAY_BASE  = 2,         -- base seconds for exponential backoff
  -- Auto-update / repair / bootstrap URL. Points at the raw GitHub base
  -- for the release tag or test branch. Current setting is the `test`
  -- branch for pre-release smoke testing; switch to a pinned tag like
  -- `v1.0.0` before public release so rolling heads cannot mutate under
  -- users mid-session. The manifest file at UPDATE_BASE_URL/UPDATE_MANIFEST
  -- lists the target version and every updatable file with its SHA-256,
  -- used by three flows:
  --   1. Update flow:  server version > CFG.VERSION -> prompt & download
  --   2. Repair flow:  version matches but local files differ -> prompt & download
  --   3. Bootstrap:    critical files missing at launch -> recovery screen
  -- Generate manifest.json per release by running:
  --   python .tools/gen_manifest.py --out manifest.json
  -- Then commit + push the manifest alongside the release tag.
  UPDATE_BASE_URL   = "https://raw.githubusercontent.com/michaelbriggsaudio/mbriggs-reaper/main/ReaAssist",
  UPDATE_MANIFEST   = "manifest.json",
  UPDATE_CURL_TIMEOUT = 15,      -- seconds; short timeout for lightweight checks
  -- Pure-Lua SHA-256 work budget per tick_sha_diff() call, in seconds.
  -- The verifier loops over small (16-block) chunks until this budget is
  -- spent or the file's hash state exhausts. Time-based instead of fixed
  -- block count so the per-frame cost adapts to the host CPU: a 10x slower
  -- machine processes 10x fewer blocks per frame, takes 10x longer wall
  -- clock, but never stalls a single frame past the budget. 5 ms keeps
  -- well inside a 16.67 ms 60 Hz frame, with headroom for the ImGui
  -- redraw and any other per-frame work.
  UPDATE_SHA_TIME_BUDGET = 0.005,
  _PRODUCT          = "ReaAssist",  -- product identity token
}
if CFG.EXT_NS ~= CFG._PRODUCT:lower() then return end

S = {
  -- Set dynamically below
  INSTANCE_ID       = nil,
  -- Conversation state
  history           = {},
  display_messages  = {},
  sticky_context    = {},  -- cached bucket content to re-inject on follow-up turns
  sticky_context_age = {}, -- per-key turn_counter when each entry was last touched (LRU eviction)
  sticky_context_order = {}, -- insertion-order key list; drives sticky_parts() emit order so appends
                             -- preserve byte-prefix cache stability. See Net.sticky_set / sticky_parts.
  turn_counter      = 0,   -- monotonic per-send counter; drives sticky_context_age expiry
  input_buf         = "",
  status            = "idle",  -- "idle" | "waiting" | "running" | "error"
  pending_code      = nil,     -- Lua code block waiting for user confirmation
  show_help         = false,   -- true shows the full-window help overlay
  show_credits      = false,   -- true shows the full-window credits overlay
  show_bug_report   = false,   -- true shows the bug report overlay
  refocus_prompt    = false,   -- set true to auto-focus prompt on next frame
  backup_flash      = {},      -- backup_flash[msg_idx] = { text="saved"|"unchanged"|"unsaved", t=time }
  backup_warn_code  = nil,     -- deferred code to run after unsaved-project warning
  backup_warn_jsfx  = nil,     -- deferred JSFX code to auto-save before running companion
  backup_warn_idx   = nil,     -- message index for the deferred run
  open_backup_warn  = false,   -- deferred flag: open warning popup next frame
  risky_warn_code   = nil,     -- deferred code to run after risky-code confirmation
  risky_warn_idx    = nil,     -- message index for the deferred risky run
  risky_warn_detail = nil,     -- scanner warning string to show in the modal
  open_risky_warn   = false,   -- deferred flag: open risky-code popup next frame
  last_backup_path  = nil,     -- full path of most recent backup file
  last_backup_state = nil,     -- GetProjectStateChangeCount at time of last backup
  scroll_to_bottom  = false,   -- set true to auto-scroll chat on next frame
  scroll_to_top     = false,   -- set true to smooth-scroll chat to top
  scroll_to_msg     = nil,    -- message index to smooth-scroll to (top of viewport)
  scroll_to_msg_frames = nil, -- frame counter for scroll_to_msg auto-expiry
  from_card         = false,   -- true when current send was triggered by a welcome card
  logo_alpha        = 0,       -- 0..1 alpha for bottom-right mini logo fade
  _top_logo_visible = true,    -- true until welcome screen scrolls away
  script_open       = true,    -- false triggers shutdown in loop()
  -- Session start timestamp. Captured once at script load for the
  -- Feedback diagnostic report's "Session uptime" line -- helps
  -- triage bugs where staleness / memory growth after long runs
  -- matters (e.g. "after 6h the UI froze").
  session_start_ts  = reaper.time_precise(),
  send_time         = nil,     -- time_precise() at curl launch; for watchdog
  -- Token accumulators (reset each script run)
  session_tok_in    = 0,
  session_tok_out   = 0,
  session_cost      = 0,       -- cumulative USD cost for the session
  -- curl/poll state
  curl_pid          = nil,     -- truthy while a request is pending, nil when idle
  curl_os_pid       = nil,     -- OS PID of in-flight curl process (for Cancel kill)
  curl_exited_clean = false,   -- true once exit code 0 has been observed (skips
                               -- partial-read brace guard so HTML/non-JSON
                               -- responses surface as errors instead of hanging)
  kill_pending      = false,   -- Cancel was clicked but tmp.pid hadn't appeared
                               -- yet; main loop retries the kill until it lands.
  kill_pending_until = 0,      -- deadline (time_precise) for kill_pending retry
  last_poll_time    = 0,       -- timestamp of last poll-loop file check
  pending_provider_idx = nil,  -- provider index snapshot at send time (for response parsing)
  pending_model_idx    = nil,  -- model index snapshot at send time
  -- Retry state for 529 auto-retry
  retry_count       = 0,
  retry_scheduled   = false,
  retry_fire_time   = 0,
  retry_saved_body  = nil,     -- saved request body for retry
  -- Anthropic extended-cache-ttl beta header fallback. Set true if the API
  -- ever rejects the beta header (likely after Anthropic deprecates it).
  -- Causes Net.fire_curl to strip the header and build_body_anthropic to
  -- emit 5-minute ephemeral cache markers instead of 1-hour. Not persisted --
  -- resets on script reload, which is fine (worst case: one 400 per session).
  anthropic_beta_disabled = false,
  pending_attachments     = nil,  -- snapshot of attachments for rebuild retries
  -- API reference (core = always-pinned portion, extended = on-demand portion)
  api_ref_message       = nil, -- pinned API ref message, or nil
  api_ref_cache_core    = nil, -- cached pre-marker content (loaded once)
  api_ref_cache_extended = nil,-- cached post-marker content (loaded once)
  -- MIDI reference (auto-injected when user prompt contains "midi", or
  -- on-demand via <context_needed>midi</context_needed>). Mirrors api_ref:
  -- once set, prepended to every request as a synthetic user/assistant pair.
  midi_ref_message  = nil,     -- pinned MIDI ref message, or nil
  midi_ref_cache    = nil,     -- cached file content (loaded once)
  -- Theme reference (on-demand via <context_needed>theme</context_needed>).
  -- Auto-injected when user prompt contains "theme" + color-related keywords.
  -- Once set, prepended to every request as a synthetic message, like api_ref.
  theme_ref_message = nil,     -- pinned theme ref message, or nil
  theme_ref_cache   = nil,     -- cached file content (loaded once)
  -- Gemini explicit context cache (paid tier only, when api_ref is loaded).
  -- Caches system_instruction + api_ref priming exchange to reduce per-turn
  -- input token cost. Created lazily at send time; deleted on invalidation.
  gemini_cache_name     = nil, -- e.g. "cachedContents/abc123"
  gemini_cache_model    = nil, -- model id the cache is bound to
  gemini_cache_expires  = 0,   -- os.time() epoch seconds when cache expires
  gemini_cache_creating   = false, -- true while a cache-create curl is in flight
  gemini_cache_started_at = 0,     -- time_precise() when cache-create curl launched (watchdog)
  last_cache_poll_time    = 0,     -- throttle for cache-create response polling
  -- Script save state
  saved_script_path = nil,
  open_actions_modal = false,
  js_hint_shown     = false,
  -- Wrap cache
  wrap_cache        = {},
  -- API key state
  api_key           = nil,     -- decoded API key for the active provider (convenience alias)
  api_key_map       = {},      -- decoded per-provider keys: {anthropic=key, openai=key, google=key, ...}
                               -- (distinct from the `api_keys` screen-state namespace)
  key_install_moved = false,   -- true if key decode failed due to moved install
  key_test_pending  = false,   -- true while validation request is in flight
  key_test_provider = nil,     -- provider id being tested (for multi-key validation)
  gemini_paid_tier    = nil,   -- nil=unknown, true=paid, false=free
  gemini_tier_pending = false, -- true while tier test is in flight
  show_gemini_free_warn = false, -- triggers free-tier warning popup next frame
  open_no_tracks_warn   = false, -- triggers no-tracks-selected popup next frame
  -- Transient toast below the chip row. { text, expires_at } or nil.
  -- Set via UI.show_toast(); auto-clears when time_precise() passes expires_at.
  toast                 = nil,
  -- One-shot guard: fires the lowest-tier hint toast once per script session
  -- when the main UI first renders on a provider's fast model. Mid-session
  -- switch-to-lowest fires the toast independently of this flag.
  lowtier_toast_shown_session = false,
  -- Context follow-up state
  pending_orig_prompt    = nil,    -- bare user text, saved for follow-up resend
  pending_snapshot       = nil,    -- snapshot from original send
  docs_already_sent      = false,  -- one-shot guard per turn
  docs_extended_already_sent = false,  -- one-shot guard per turn (extended)
  docs_fetched_session   = false,  -- session-level flag: docs has been inlined
                                   -- into history at least once this chat.
                                   -- Used by the docs-gate to know whether
                                   -- reaper.* in a reply was guessed or was
                                   -- grounded in the reference. Survives until
                                   -- session clear / factory reset.
  session_already_sent   = false,
  fx_params_already_sent = false,
  plugin_ref_sent          = {},   -- set of plugin names sent this turn (dedup per-name, not turn-wide)
  pending_resolves         = {},   -- queue of resolve:Type tokens deferred when a popup blocks the loop
  pending_plugin_ref_names = {},   -- plugin_ref names accumulated before a popup bailed the parse loop
  pending_pref_plugin_types= {},   -- preferred_plugins types accumulated before a popup bailed the parse loop
  context_loop_retries     = 0,    -- per-turn counter -- model re-asking for already-provided context (max 1 retry)
  api_validator_retries    = 0,    -- per-turn counter -- model emitted nonexistent reaper.* calls (max 1 retry)
  fx_list_already_sent   = false,
  fx_chains_already_sent = false,
  track_flags_already_sent = false,
  midi_already_sent      = false,
  pref_plugins_sent        = {},   -- set of pref-plugin types sent this turn (per-type dedup)
  theme_already_sent     = false,
  fx_inspect_already_sent = false,
  prompt_bundle_sent       = {},   -- set of prompt-bundle names sent in this session (per-name, NOT reset per turn -- bundles are system-prompt content and stay pinned until Clear)
  prompt_bundle_cache      = nil,  -- file-content cache: {[name]=formatted payload}; nil until first load
  pending_display_idx    = nil,    -- index into display_messages for current user msg
  pending_project        = nil,    -- captured project pointer at send time
  -- Resolve-type popup (Phase 5b): blocks the round when the user has no
  -- preference set for a requested plugin type. resolve_popup carries
  -- { type = "eq"|"compressor"|... } while the modal is open; nil otherwise.
  -- open_resolve_popup is a one-shot flag consumed inside the render frame
  -- to call ImGui.OpenPopup (must be invoked from the render pass).
  resolve_popup          = nil,
  open_resolve_popup     = false,
  resolve_pending_type   = nil,    -- popup type stashed by typed-pick (since popup state is cleared early so the "Waiting for selection" UI clears during the scan)
  resolve_popup_text     = "",    -- text-field buffer for custom plugin name
  resolve_popup_error    = nil,   -- inline error message (install-failed, no-match)
  -- Autocomplete (Phase 5d): list of top matches for the current buffer.
  -- _matches: array of canonical FX names (strings). _sel: 1-based index
  -- into _matches of the currently-highlighted row, or 0 for "none" (in
  -- which case Enter falls back to submitting the raw buffer text).
  -- _last_filter: the buffer value used to build _matches (cache key, so
  -- we only re-run the match scan when the text actually changed).
  resolve_popup_matches     = {},
  resolve_popup_sel         = 0,
  resolve_popup_last_filter = nil,
  -- Attachment queue
  attachments       = {},
  attach_error      = nil,
  attach_error_time = 0,
}

S.INSTANCE_ID = string.format("%.6f_%d", time_precise(), math.random(100000, 999999))
do
  -- Stale lock timeout: how long before a lock from a (presumed-crashed)
  -- prior instance is considered abandoned. Set short so the user can
  -- relaunch the script almost immediately after a REAPER crash. The live
  -- instance refreshes its lock every loop frame, so 15s is plenty of margin
  -- against false positives even on a heavily loaded machine.
  local STALE_LOCK_SECS = 15
  local existing_lock = reaper.GetExtState(CFG.EXT_NS, "running")
  if existing_lock ~= "" then
    -- Lock format: "instance_id|timestamp"
    local lock_time = tonumber(existing_lock:match("|(.+)$"))
    local now = time_precise()
    local age = lock_time and math.abs(now - lock_time) or math.huge
    if age < STALE_LOCK_SECS then
      -- Lock is fresh: another instance is genuinely running. Signal it to close
      -- and pass our instance ID so the running instance can verify the request.
      reaper.SetExtState(CFG.EXT_NS, "request_close", S.INSTANCE_ID, false)
      set_toolbar(false)
      return
    end
    -- Lock is stale or non-numeric: claim it for this instance (fall through).
  end
  reaper.SetExtState(CFG.EXT_NS, "running",
    S.INSTANCE_ID .. "|" .. tostring(time_precise()), false)
  reaper.DeleteExtState(CFG.EXT_NS, "request_close", false)
  set_toolbar(true)
end

-- =============================================================================
-- API key obfuscation
-- =============================================================================
-- Keys are XOR-encoded against the REAPER install path before storage in
-- ExtState. This prevents accidental key leakage when users share portable
-- installs or sync config files to another machine -- the encoded value
-- decodes to garbage on any machine with a different GetExePath().
--
-- This is NOT encryption. The deobfuscation logic is visible in this source
-- file. It protects against *accidental* exposure, not intentional theft.

-- Machine-specific anchor: REAPER's executable directory. Stable across
-- sessions on the same machine, different on every other machine.
Key = {}
Key.ANCHOR = reaper.GetExePath()

-- XOR helper: pure-arithmetic implementation that works in any Lua version
-- without requiring bit/bit32 libraries (which REAPER may not expose).
-- Operates on byte values (0-255) so only needs to XOR 8 bits.
function Key.byte_xor(a, b)
  local result = 0
  local bit_val = 1
  for _ = 1, 8 do
    local a_bit = a % 2
    local b_bit = b % 2
    if a_bit ~= b_bit then result = result + bit_val end
    a = math_floor(a / 2)
    b = math_floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

-- Key.xor_with_anchor(str) -> string
-- XORs each byte of str against the corresponding byte in the anchor,
-- cycling the anchor if str is longer. Returns a raw byte string.
function Key.xor_with_anchor(str)
  local anchor = Key.ANCHOR
  local anchor_len = #anchor
  local out = {}
  for i = 1, #str do
    local s_byte = str:byte(i)
    local a_byte = anchor:byte(((i - 1) % anchor_len) + 1)
    out[i] = str_char(Key.byte_xor(s_byte, a_byte))
  end
  return tbl_concat(out)
end

-- Magic prefix prepended to the plaintext before XOR encoding. On decode, its
-- presence confirms the install path has not changed. Without it, a moved
-- install would produce garbage on decode and we'd have no way to distinguish
-- "corrupted" from "wrong anchor" -- previously this caused the key to be
-- permanently erased on a temporary install-path change.
local KEY_MAGIC = "RA1\0"

-- Key.encode(plain_key) -> hex string suitable for ExtState storage
-- Encodes a plain-text API key into a hex-encoded, machine-locked blob.
-- Prepends KEY_MAGIC so decode can verify the anchor matched.
function Key.encode(plain_key)
  local xored = Key.xor_with_anchor(KEY_MAGIC .. plain_key)
  local hex = {}
  for i = 1, #xored do
    hex[i] = str_format("%02x", xored:byte(i))
  end
  return tbl_concat(hex)
end

-- Key.decode(hex_string) -> plain_key or nil
-- Reverses Key.encode. Returns nil if the hex string is malformed or the
-- magic prefix is absent (install path changed). Does NOT erase the stored
-- key on failure -- the caller decides what to do.
function Key.decode(hex_str)
  -- Validate hex format (even length, only hex chars).
  if #hex_str % 2 ~= 0 or hex_str:match("[^0-9a-fA-F]") then
    return nil
  end
  local bytes = {}
  for i = 1, #hex_str, 2 do
    bytes[#bytes + 1] = str_char(tonumber(hex_str:sub(i, i + 1), 16))
  end
  local decoded = Key.xor_with_anchor(tbl_concat(bytes))
  -- Verify magic prefix. If absent, the anchor (install path) has changed
  -- and the decode produced garbage. Return nil but leave the stored blob
  -- intact so restoring the original path recovers the key.
  if decoded:sub(1, #KEY_MAGIC) ~= KEY_MAGIC then
    return nil
  end
  return decoded:sub(#KEY_MAGIC + 1)
end

-- Key.save(plain_key, extstate_key) -- encodes and persists to ExtState.
-- extstate_key defaults to the active provider's key_extstate.
function Key.save(plain_key, extstate_key)
  extstate_key = extstate_key or PROVIDERS.active().key_extstate
  reaper.SetExtState(CFG.EXT_NS, extstate_key, Key.encode(plain_key), true)
end

-- Key.clear(extstate_key) -- removes key from ExtState.
-- extstate_key defaults to the active provider's key_extstate.
function Key.clear(extstate_key)
  extstate_key = extstate_key or PROVIDERS.active().key_extstate
  reaper.DeleteExtState(CFG.EXT_NS, extstate_key, true)
end

-- =============================================================================
-- First-run full-screen flow
-- =============================================================================
-- On first launch, the main UI is hidden and the user is walked through two
-- full-window screens before reaching the chat: a Terms of Use / disclaimer
-- screen, then an API key entry screen. Once both are complete the main UI
-- replaces them for the rest of this session and all future sessions.
--
-- api_keys.screen is the single source of truth for which screen is active:
--   "tos"       -- Terms of Use / disclaimer screen (shown first if not yet
--                  accepted at the current TOS version)
--   "api_key"   -- API key entry screen (shown when TOS is accepted but no
--                  valid API key is stored)
--   nil         -- main chat UI (TOS accepted AND key present)
--
-- TOS acceptance is persisted in ExtState as a version string. Bumping
-- api_keys.tos_version below will force every user to re-accept on next
-- launch (use this only when the disclaimer text changes substantively).
--
-- All state for the API keys / first-run setup flow. This single table holds
-- the screen-routing flag, the TOS acceptance state, the API key entry
-- buffers/validation, and the custom LLM section state. Kept in one table
-- to stay under Lua's per-function 200-local limit.
api_keys = {
  -- Current screen: "tos" / "api_key" / nil. Set below.
  screen         = nil,
  -- Per-screen state for the API key entry screen.
  key_bufs       = {},     -- per-provider input buffers: {[1]="", [2]="", [3]=""}
  key_errors     = {},     -- per-provider validation errors: {[1]=nil, [2]=nil, [3]=nil}
  key_error      = nil,    -- general inline error string, or nil
  key_validating = false,  -- true while a test API call is in flight
  key_validating_idx = nil, -- which provider index is being validated (nil = none)
  key_focused    = false,  -- true after the input field has been auto-focused once
  is_reentry     = false,  -- true when opened via Settings button (not first launch)
  -- Multi-key test state (Test API Keys button).
  test_queue       = {},     -- list of {idx, prov} to test sequentially
  test_results     = {},     -- collected results: {[prov_id]={ok=bool, label=str, error=str}}
  show_test_results = false, -- true = open the results popup next frame
  -- Single-key validation error popup state.
  show_key_error_popup = false,   -- true = open error popup next frame
  key_error_provider   = nil,     -- provider label for the error popup
  key_error_detail     = nil,     -- human-readable error message
  key_error_hint       = nil,     -- how-to-fix hint
  key_error_url        = nil,     -- console URL for the provider (clickable link)
  key_error_url_label  = nil,     -- display text for the URL
  -- TOS persistence.
  tos_version    = "2",
  -- Disclaimer text shown on the first-run TOS screen. When this text
  -- changes substantively, bump tos_version above to force re-acceptance.
  tos_text = string.format([[
YOUR PRIVACY
API keys are encoded and stored locally on your machine. They are never sent to the author. Data is sent only to your chosen provider to fulfill your request. To provide relevant help, ReaAssist may send session data included in your prompt, such as track names, routing, and project settings. ReaAssist does not access, transmit, or create audio files. You may use a local LLM to keep all data offline and on your machine.

SECURITY & SAFEGUARDS
ReaAssist scans generated code for potentially high-risk operations, such as file system changes or shell commands, and requires your confirmation before flagged code can run. Project backups can be created before execution, and REAPER Undo history is preserved. No project changes are made without your approval.

TERMS & LIABILITY
ReaAssist is provided "as is," without warranties of any kind, express or implied, including merchantability or fitness for a particular purpose. Generated code may contain errors or unintended results. You are responsible for reviewing code before execution. You are also responsible for your provider's terms, privacy practices, availability, and API charges. Displayed cost estimates are approximate only.

Copyright %s Michael Briggs. All rights reserved. ReaAssist is proprietary software; local personal modification is permitted, but redistribution, resale, repackaging, and presenting this software as your own (modified or unmodified) are prohibited without prior written permission.

By clicking "I Agree," you confirm that you have read and agree to these Terms of Use.]], os.date("%Y")),
}

function api_keys.tos_is_accepted()
  return reaper.GetExtState(CFG.EXT_NS, "tos_accepted_version") == api_keys.tos_version
end
function api_keys.mark_tos_accepted()
  reaper.SetExtState(CFG.EXT_NS, "tos_accepted_version", api_keys.tos_version, true)
end

-- NOTE: api_keys.screen is assigned after PROVIDERS, key loading, and
-- MODELS.refresh complete (see the first-run routing block further down).

-- =============================================================================
-- Preferred Plugins state
-- =============================================================================
-- Default suggested plugin type labels. These pre-fill the rows on first use
-- but the user can rename, reorder, or delete any of them.
PREF_PLUGIN_DEFAULTS = {
  "Equalizer", "Compressor", "Multiband Compressor", "Reverb", "Delay",
  "Synthesizer", "Saturation", "De-esser", "Pitch Correction", "Limiter",
  "Gate", "Chorus", "Phaser", "Pitch Shift",
}

-- Synonym/alias map: common alternative names -> canonical type key.
-- Used both in the Lua bucket lookup and documented in the system prompt.
local PREF_PLUGIN_ALIASES = {
  equalizer   = "eq",
  equaliser   = "eq",
  comp        = "compressor",
  compression = "compressor",
  ["multiband compressor"]  = "multiband_compressor",
  ["multi-band compressor"] = "multiband_compressor",
  ["multiband comp"]        = "multiband_compressor",
  ["multi-band comp"]       = "multiband_compressor",
  mbcomp      = "multiband_compressor",
  multiband   = "multiband_compressor",
  verb        = "reverb",
  echo        = "delay",
  distortion  = "saturation",
  overdrive   = "saturation",
  drive       = "saturation",
  deesser     = "deesser",
  ["de-esser"]= "deesser",
  desser      = "deesser",
  autotune    = "pitch_correction",
  tuner       = "pitch_correction",
  ["pitch correction"] = "pitch_correction",
  ["pitch shift"]      = "pitch_shift",
  limit       = "limiter",
  gate        = "gate",
  expander    = "gate",
  flanger     = "phaser",
  synth       = "synth",
  synthesizer = "synth",
  synthesiser = "synth",
}

pref_plugins = {
  rows         = {},      -- { {label="EQ", name="Pro-Q 4"}, {label="Compressor", name=""}, ... }
  initialized  = false,   -- true after first render loads from file
  dirty        = false,   -- true when buffers have unsaved changes
  -- Parameter scan state machine
  scan = {
    active  = false,    -- true while a scan is running
    phase   = nil,      -- "adding" | "reading" | "done"
    track   = nil,      -- temp MediaTrack created for scanning
    fx_map  = {},       -- { {key="eq", name="...", ident="...", fx_idx=0}, ... }
    results = {},       -- keyed by type key: formatted param string
    status  = "",       -- status message for UI
  },
  -- Autocomplete dropdown for the "Plugin name" columns. Only one row
  -- owns the autocomplete at a time (whichever field is focused). Structure
  -- mirrors the resolve-popup autocomplete for consistency.
  ac = {
    row_idx     = nil,  -- pref_plugins.rows index of the field currently focused
    matches     = {},
    sel         = 0,
    last_filter = nil,
    field_x1    = 0,    -- screen-rect of the active field (for dropdown pos)
    field_y2    = 0,
    field_w     = 0,
  },
}

-- Set of default labels (built from PREF_PLUGIN_DEFAULTS). Used to decide
-- whether a row's Type column is locked (defaults) or editable (user-added).
-- Stored on pref_plugins instead of a fresh file-scope local to stay under
-- the 200-locals budget.
pref_plugins.default_set = {}
for _, _lbl in ipairs(PREF_PLUGIN_DEFAULTS) do
  pref_plugins.default_set[_lbl] = true
end

-- FX Param Cache management screen state
fx_cache_ui = {
  -- Rescan state machine (single plugin)
  rescan = {
    active = false,
    phase  = nil,   -- "adding" | "reading" | "done"
    track  = nil,   -- temp MediaTrack
    ident  = nil,   -- plugin identifier being rescanned
    fx_idx = -1,
    status = "",
    deep   = false, -- if true, use coroutine-based defer-paced scanner
  },
  -- Batch rescan state (Rescan All on the FX Cache page). Queues every
  -- cached plugin and feeds them through `rescan` one at a time so there
  -- is never more than one temp track / plugin load in flight.
  rescan_all = {
    active    = false,
    queue     = {},     -- list of remaining idents to scan (FIFO)
    total     = 0,      -- total queue size when started
    index     = 0,      -- 1-based count of plugins started so far
    current   = nil,    -- ident currently in flight (for display)
    failures  = {},     -- idents that failed to load (missing plugins)
  },
}

-- Deep FX scan state (coroutine-paced param probe for laggy VST3 plugins).
-- Resumed one step per frame from loop(); kicks its completion callback
-- when the coroutine finishes or is cancelled.
deep_scan = {
  active      = false,
  coro        = nil,          -- running coroutine
  tr          = nil,          -- temp MediaTrack holding the plugin
  fx_idx      = -1,
  identifier  = nil,
  search_names= nil,          -- for chat-status display
  started_at  = 0,            -- time_precise() at start (for elapsed display)
  probes_done = 0,
  origin      = nil,          -- "chat" | "fx_cache" (who to notify on completion)
  on_complete = nil,          -- function(params_list, max_group, total_count)
  on_cancel   = nil,          -- function() called if user cancels / errors
  cancel_req  = false,
}

-- =============================================================================
-- Auto-update state
-- =============================================================================
update = {
  -- State machine: idle -> checking -> verifying -> (available |
  -- repair_available | idle); user click -> downloading -> rename_retry?
  -- -> done; any error -> failed (with last_step / last_error stamped
  -- by Updater._set_failure for the Update Failed dialog to read).
  state           = "idle",
  remote_version  = nil,     -- version string from manifest (e.g. "0.9.1")
  manifest        = nil,     -- parsed manifest table
  download_queue  = {},      -- list of {filename, url, sha256} to download
  download_idx    = 0,       -- index into download_queue (current file)
  applied_files   = {},      -- list of {path=dest, bak_existed=bool} for rollback;
                             -- bak_existed=false means "fresh-install add" so rollback
                             -- must delete dest (not try to restore a nonexistent .bak)
  send_time       = nil,     -- time_precise() when the current curl was launched
  applied         = false,   -- true once files have been written to disk
  popup_opened    = false,   -- true once the "Update Available" popup has been shown
  force           = false,   -- true to bypass version comparison (integrity reinstall)
  rename_failures = 0,       -- consecutive os.rename failures for AV-locked retry (initial fail = 1; each defer retry increments; gives up at 15)
  rename_tmp      = nil,     -- tmp_path for pending rename retry
  rename_dest     = nil,     -- dest path for pending rename retry
  rename_bak      = nil,     -- bak path for pending rename retry
  rename_bak_existed = false,-- true if the .bak was actually created (file existed pre-rename);
                             -- false means "fresh install add" so rollback must not restore
  -- Structured diagnostics stamped on every failure path so a support
  -- dump (Bug Report -> Copy Diagnostics) can attribute which step of
  -- the update/repair pipeline failed and why. Surfaced to the user via
  -- the Bootstrap repair prompt when the previous attempt failed.
  last_error      = nil,     -- short human-readable reason (last failure only)
  last_step       = nil,     -- step identifier ("manifest_read", "download",
                             --   "sha_verify", "rename", "rollback", ...)
}

-- =============================================================================
-- ImGui context, fonts, and atexit cleanup
-- =============================================================================
RA.ctx = ImGui.ImGui_CreateContext(CFG._PRODUCT .. " v" .. CFG.VERSION)

-- EEL callback for InputTextMultiline: tracks selection start/end each
-- frame. Lives on RA so UI.selectable_text (in the UI chunk) can reach
-- it across the dofile boundary.
RA.sel_cb = ImGui.ImGui_CreateFunctionFromEEL([[
  sel_start = SelectionStart;
  sel_end   = SelectionEnd;
]])
ImGui.ImGui_Attach(RA.ctx, RA.sel_cb)

-- CharFilter callback for the chat prompt InputTextMultiline. ImGui
-- inserts \n into the widget's internal edit buffer the moment Enter
-- is pressed in a multiline widget; that insertion renders for one
-- frame -- a visible 1-line -> 2-line jump -- before the post-widget
-- handler in the UI chunk strips the \n and triggers send. Filtering
-- the \n at the source prevents the insert and the flicker. Lua sets
-- `discard_newline = 1` only on frames where Enter is pressed WITHOUT
-- Shift; multi-line paste still works because the same frame won't
-- have a fresh Enter keypress, so discard_newline stays 0 and pasted
-- newlines pass through. Keypath: ReaAssist_UI.lua's prompt render.
RA.prompt_charfilter = ImGui.ImGui_CreateFunctionFromEEL([[
  EventChar == 10 && discard_newline ? EventChar = 0;
]])
ImGui.ImGui_Attach(RA.ctx, RA.prompt_charfilter)

-- V5 font atlas declared below, after RA.SC() is defined (sizes are scaled
-- by the user's UI Scale preference).
-- FONT is a plain global (assigned as `FONT = {}` in the atlas block
-- below). bold_font and code_font are cross-file and live on RA
-- (RA.bold_font, RA.code_font). No forward declaration is needed.

-- Tmp file paths for curl I/O. Files are written to the REAPER resource
-- root (e.g. %AppData%\REAPER on Windows) rather than the script's own
-- directory, keeping them out of the source folder regardless of ReaPack
-- install depth. The resource root is guaranteed writable on all platforms.
-- CMD_ID suffix makes filenames unique per script instance.
local tmp = {}
do
  local tmp_dir    = reaper.GetResourcePath() .. RA.SEP
  local tmp_suffix = tostring(CMD_ID or 0)
  tmp.out    = tmp_dir .. "reaassist_resp_"       .. tmp_suffix .. ".json"
  tmp.body   = tmp_dir .. "reaassist_body_"       .. tmp_suffix .. ".json"
  tmp.log    = tmp_dir .. "reaassist_last_error_" .. tmp_suffix .. ".json"
  tmp.auth   = tmp_dir .. "reaassist_auth_"       .. tmp_suffix .. ".txt"
  -- Exit code file. curl writes its exit code here so the poll loop can detect
  -- network errors on both platforms. Windows: written by the PowerShell
  -- command. macOS/Linux: written by the shell pipeline via "echo $?".
  tmp.exit   = tmp_dir .. "reaassist_exit_"       .. tmp_suffix .. ".txt"
  -- Gemini cache-create I/O. Separate from the main pipeline so cache creation
  -- can run concurrently with a user send without trampling response files.
  tmp.cache_body = tmp_dir .. "reaassist_cbody_" .. tmp_suffix .. ".json"
  tmp.cache_out  = tmp_dir .. "reaassist_cresp_" .. tmp_suffix .. ".json"
  tmp.cache_exit = tmp_dir .. "reaassist_cexit_" .. tmp_suffix .. ".txt"
  -- Pid file: holds the OS PID of the in-flight curl process so Cancel can
  -- kill it via taskkill/kill rather than just orphaning it.
  tmp.pid    = tmp_dir .. "reaassist_pid_"        .. tmp_suffix .. ".txt"
  -- Gemini side-path auth file. Separate from tmp.auth so cache-create can run
  -- concurrently with a main API request without trampling the auth header file.
  tmp.gemini_auth = tmp_dir .. "reaassist_gauth_" .. tmp_suffix .. ".txt"
  -- Auto-update I/O. Separate from the main pipeline so the update check
  -- runs independently without trampling API request/response files.
  tmp.update_out  = tmp_dir .. "reaassist_update_"     .. tmp_suffix .. ".txt"
  tmp.update_exit = tmp_dir .. "reaassist_uexit_"      .. tmp_suffix .. ".txt"
  tmp.screenshot  = tmp_dir .. "reaassist_screenshot_" .. tmp_suffix .. ".png"
  tmp.clipboard   = tmp_dir .. "reaassist_clipboard_"  .. tmp_suffix .. ".png"
end

-- Startup cleanup: wipe any temp files left behind by a prior hard crash (BSOD,
-- power loss, OOM kill). atexit handles graceful shutdown but cannot run on
-- crash, so temp files (including the plaintext auth header) could otherwise
-- persist on disk. Doing this at startup is the only safe net.
os.remove(tmp.auth)
os.remove(tmp.gemini_auth)
os.remove(tmp.pid)
os.remove(tmp.out)
os.remove(tmp.body)
os.remove(tmp.log)
os.remove(tmp.exit)
os.remove(tmp.cache_body)
os.remove(tmp.cache_out)
os.remove(tmp.cache_exit)
os.remove(tmp.update_out)
os.remove(tmp.update_exit)
os.remove(tmp.screenshot)
os.remove(tmp.clipboard)

reaper.atexit(function()
  set_toolbar(false)
  -- Only clear the "running" lock if it still belongs to this instance.
  -- During auto-restart (Updater.try_auto_restart -> Main_OnCommand) the
  -- new instance has already claimed the lock by the time this atexit
  -- fires, and wiping it here would leave the new instance unlocked for
  -- up to a heartbeat interval.
  local current = reaper.GetExtState(CFG.EXT_NS, "running")
  if current:match("^([^|]+)") == S.INSTANCE_ID then
    reaper.DeleteExtState(CFG.EXT_NS, "running", false)
  end
  reaper.DeleteExtState(CFG.EXT_NS, "request_close", false)
  -- Remove any hidden temp tracks owned by an in-flight scan. Without this,
  -- closing mid-scan (or being displaced by a second instance) would leave
  -- the user's project with a stray hidden track in the TCP/mixer-invisible
  -- state - surprising if they later look at the track list directly.
  local _inflight = {}
  if pref_plugins.scan  and pref_plugins.scan.track  then _inflight[#_inflight+1] = pref_plugins.scan.track  end
  if fx_cache_ui.rescan and fx_cache_ui.rescan.track then _inflight[#_inflight+1] = fx_cache_ui.rescan.track end
  if S._fx_inspect_tmp  and S._fx_inspect_tmp.tr     then _inflight[#_inflight+1] = S._fx_inspect_tmp.tr     end
  if deep_scan.tr                                    then _inflight[#_inflight+1] = deep_scan.tr             end
  for _, _tr in ipairs(_inflight) do
    if reaper.ValidatePtr2(0, _tr, "MediaTrack*") then
      pcall(reaper.DeleteTrack, _tr)
    end
  end
  -- Close the Undo + PreventUIRefresh scopes those scans hold open. Each
  -- scope owner (pref scan / fx_cache rescan / fx_inspect) opened one
  -- Undo_BeginBlock + one PreventUIRefresh(1) on entry; without closing
  -- them here, a mid-scan exit would leave the TCP/MCP redraw suppressed
  -- and an undo block dangling. deep_scan body releases PreventUIRefresh(-1)
  -- early on behalf of its owner (fx_inspect or fx_cache rescan), so skip
  -- one refresh release if that already happened.
  local _owners = 0
  if pref_plugins.scan  and pref_plugins.scan.track  then _owners = _owners + 1 end
  if fx_cache_ui.rescan and fx_cache_ui.rescan.track then _owners = _owners + 1 end
  if S._fx_inspect_tmp                               then _owners = _owners + 1 end
  local _refreshes = _owners
  if deep_scan._ui_refresh_released then _refreshes = _refreshes - 1 end
  if _refreshes < 0 then _refreshes = 0 end
  for _ = 1, _refreshes do pcall(reaper.PreventUIRefresh, -1) end
  for _ = 1, _owners do
    pcall(reaper.Undo_EndBlock, "ReaAssist: scan (closed at exit)", 0)
  end
  if reaper.ImGui_DestroyContext and RA.ctx then
    pcall(reaper.ImGui_DestroyContext, RA.ctx)
  end
  -- Remove all temp files so nothing persists on disk after exit. Every
  -- tmp.* field is unconditionally assigned in the do-block above, so
  -- the previous `if tmp.X then` guards on each line were dead. The
  -- auth file should already be removed after each curl call, but
  -- os.remove silently no-ops on missing files so cleaning up
  -- defensively here is harmless.
  os.remove(tmp.out)
  os.remove(tmp.body)
  os.remove(tmp.log)
  os.remove(tmp.auth)
  os.remove(tmp.gemini_auth)
  os.remove(tmp.exit)
  os.remove(tmp.cache_body)
  os.remove(tmp.cache_out)
  os.remove(tmp.cache_exit)
  os.remove(tmp.pid)
  os.remove(tmp.update_out)
  os.remove(tmp.update_exit)
  os.remove(tmp.screenshot)
  os.remove(tmp.clipboard)
end)

-- =============================================================================
-- Persisted UI preferences (saved across REAPER restarts via ExtState)
-- =============================================================================
-- ~= "0" pattern: default ON for a fresh install (empty ExtState returns "")
-- == "1" pattern: default OFF for a fresh install
prefs = {
  auto_run         = reaper.GetExtState(CFG.EXT_NS, "auto_run")         == "1",  -- default off
  auto_backup      = reaper.GetExtState(CFG.EXT_NS, "auto_backup")      ~= "0",  -- default on
  show_details     = reaper.GetExtState(CFG.EXT_NS, "show_details")     == "1",  -- default off
  debug_logging    = reaper.GetExtState(CFG.EXT_NS, "debug_logging")    ~= "0",  -- default ON during early-release window so testers' bug reports include full traffic without manual opt-in; flip to == "1" later when bug volume settles
  include_api_ref  = reaper.GetExtState(CFG.EXT_NS, "include_api_ref")  == "1",  -- default off (prompt-bundle era; request docs on-demand)
  include_snapshot = reaper.GetExtState(CFG.EXT_NS, "include_snapshot") ~= "0", -- default on
  update_check     = reaper.GetExtState(CFG.EXT_NS, "update_check")    ~= "0", -- default on
  max_tokens_idx   = 3,  -- index into CFG.MAX_TOKENS_OPTIONS (default 3 = 16384)
  provider_idx     = 1,  -- set below from ExtState (1=Claude, 2=ChatGPT, 3=Gemini)
  model_idx        = 2,  -- set below by MODELS.refresh() per active provider
  thinking_idx     = 0,  -- 0 = provider has no thinking; set by MODELS.refresh()
  ui_scale_idx     = 3,  -- index into CFG.UI_SCALE_OPTIONS (default 3 = 1.0)
  theme            = "auto",  -- "auto", "dark", or "light"
  chat_font_idx    = 2,  -- index into CHAT_FONT_SIZES: 1=Small, 2=Medium, 3=Large
  cloud_request_timeout = 180,  -- seconds; user-facing watchdog timeout for cloud providers (Claude/ChatGPT/Gemini). Set below from ExtState. Custom providers use their own per-provider timeout instead.
  -- Testing-only: when true, a per-send timestamp is appended to the
  -- system prompt as a hidden comment so every request hashes to a new
  -- cache prefix across all three providers. Gives reliably cold-cache
  -- measurements during cost testing. Persisted so a test session
  -- survives a reload, but users who forget to toggle it off will see
  -- higher costs until they do.
  test_force_cold_cache = reaper.GetExtState(CFG.EXT_NS, "test_force_cold_cache") == "1",
  -- Dev-only: the FabFilter-hide flag (used to test resolve/not-found
  -- popups without physically uninstalling anything) lives in ExtState
  -- under "dev_hide_fabfilter" and is read directly at every consumer.
  -- The Debug Helper's "Hide FabFilter" toggle writes ExtState and fires
  -- the "refresh_fx_filter" dev_signal to invalidate the installed-FX
  -- caches. No prefs field is mirrored here because nothing reads it
  -- (the flag's read sites all hit ExtState fresh, so a mirror would be
  -- dead state that could go stale if the signal ever missed a delivery).
}

-- Forward-declare JSON so the Log module (defined below) can reference it;
-- JSON is main-file-local and later assigned without `local` so it
-- reassigns this upvalue rather than shadowing it.
local JSON
-- PROVIDERS, MODELS, FXCache, and Net are cross-file shared state and
-- live as plain globals so both ReaAssist.lua and Resources/ReaAssist_UI.lua
-- can read and write them. Their `= {}` initializers appear later in
-- this file; before those run the names are nil, so any code that touches
-- them at load time must appear after the initializers.

-- =============================================================================
-- Log: verbose debug logger (gated by prefs.debug_logging)
-- =============================================================================
-- When enabled via the "Debug log" checkbox in settings, appends tagged entries
-- to a log file including every outgoing API request body, every incoming
-- response body, every FX scan event, and every cache hit/miss. Includes
-- auto-follow-up requests (hidden from the chat UI) so the full exchange is
-- visible. Users can send this file to the developer for bug reports.
-- No-op when disabled so there's zero perf cost in normal use.
Log = {}
-- Single-writer log, shared across launches. Safe because the lock mechanism
-- above (S.INSTANCE_ID + ExtState "running" key) guarantees only one
-- ReaAssist can be writing to ExtState/log at a time on a given machine:
-- second-launch instances detect the fresh lock, send request_close, and
-- exit BEFORE the Log module loads. Each session writes a clear "session
-- start" header so multiple sessions in one file remain easy to navigate.
--
-- Cross-machine edge case (script directory synced via Dropbox/OneDrive,
-- both machines running ReaAssist simultaneously) is NOT covered -- ExtState
-- is per-machine so neither sees the other's lock, and the synced log file
-- could see interleaved appends. If you hit that scenario, the workaround
-- is to disable debug logging on all but one machine.
Log.path = RA.RESOURCES_DIR .. "ReaAssist_Debug.log"
Log.enabled = function() return prefs.debug_logging end

-- Simple append-at-bottom log (standard chronological order). On first request
-- per session we write a header with system info at the top of the file; each
-- subsequent event is appended.
local function _log_write(text)
  local f = io.open(Log.path, "a")
  if not f then return end
  f:write(text)
  f:close()
end

-- Indent every line of a multi-line string by `pad`.
local function _indent(s, pad)
  if s == nil or s == "" then return pad .. "(empty)" end
  pad = pad or "    "
  local out = {}
  for line in (tostring(s) .. "\n"):gmatch("([^\n]*)\n") do
    out[#out+1] = pad .. line
  end
  if out[#out] == pad then table.remove(out) end
  return table.concat(out, "\n")
end

-- Known static reference-doc prefixes. Their content is versioned with the
-- script and available in the repo; the log only needs to show that they were
-- injected, not their bodies.
local _STATIC_REF_PREFIXES = {
  "REAPER LUA API REFERENCE:",
  "REAPER MIDI WORKFLOW REFERENCE:",
  "REAPER THEME COLOR REFERENCE:",
  "PLUGIN PARAMETER REFERENCE:",
}

-- Explicit list of known top-level context section markers. The elision
-- function stops a section at the next \n\n followed by any of these prefixes
-- (exact match, not regex) so that "NOTE:" or "IMPORTANT:" lines INSIDE a
-- reference doc don't falsely terminate the elision.
local _SECTION_MARKERS = {
  "REAPER LUA API REFERENCE:",
  "REAPER MIDI WORKFLOW REFERENCE:",
  "REAPER THEME COLOR REFERENCE:",
  "PLUGIN PARAMETER REFERENCE:",
  "INSTALLED FX MATCHING ",
  "PREFERRED PLUGINS:",
  "SESSION CONTEXT:",
  "FX INSPECT ",
  "FX INSPECT:",
  "FX INSPECT ERROR:",
  "FX PARAMETER VALUES",
  "Track flags:",
  "USER REQUEST:",
}

local function _line_starts_new_section(s, line_start)
  for _, marker in ipairs(_SECTION_MARKERS) do
    if s:sub(line_start, line_start + #marker - 1) == marker then
      return true
    end
  end
  return false
end

-- Walk a message-content string and replace each static reference section with
-- a size placeholder. A section ends at the next \n\n that is followed by a
-- line starting with one of _SECTION_MARKERS, or at end of string.
local function _elide_static_refs(s)
  if type(s) ~= "string" then return s end
  for _, hdr in ipairs(_STATIC_REF_PREFIXES) do
    local pos = 1
    while true do
      local hs = s:find(hdr, pos, true)
      if not hs then break end
      local he = hs + #hdr
      local section_end = #s + 1
      local scan = he
      while true do
        local blank = s:find("\n\n", scan, true)
        if not blank then break end
        local line_start = blank + 2
        if _line_starts_new_section(s, line_start) then
          section_end = blank
          break
        end
        scan = blank + 2
      end
      local body_len = section_end - he
      if body_len > 200 then
        s = s:sub(1, he - 1)
          .. "  [" .. body_len .. " chars omitted -- static reference doc]"
          .. s:sub(section_end)
        pos = hs + #hdr
      else
        pos = he
      end
    end
  end
  -- Also elide the static FX INSPECT guidance block (same text every time
  -- fx_inspect is injected). Match from "IMPORTANT: Use the EXACT parameter
  -- indices" through the "Apply the DECIDE FIRST flowchart..." line; replace
  -- with a single placeholder.
  local g_start = s:find("IMPORTANT: Use the EXACT parameter indices", 1, true)
  if g_start then
    local g_anchor = "Apply the DECIDE FIRST flowchart"
    local g_a = s:find(g_anchor, g_start, true)
    if g_a then
      local g_end = s:find("\n", g_a, true) or #s
      s = s:sub(1, g_start - 1)
        .. "[fx_inspect guidance omitted -- static]"
        .. s:sub(g_end)
    end
  end
  return s
end

-- Replace big base64-looking strings with a size placeholder so the log stays
-- readable when the user pastes in screenshots or images; also elide static
-- reference docs that bloat the request without adding debug value.
local function _trim_base64(s)
  if type(s) ~= "string" then return s end
  if #s > 1000 and s:match("^[A-Za-z0-9+/=\r\n]+$") then
    return "[base64 data omitted, " .. #s .. " bytes]"
  end
  return _elide_static_refs(s)
end

-- Render a single Anthropic-style content block (also handles OpenAI parts).
local function _render_block(block, pad)
  pad = pad or "    "
  if type(block) == "string" then
    return _indent(_trim_base64(block), pad)
  end
  if type(block) ~= "table" then return pad .. tostring(block) end
  local bt = block.type or (block.text and "text") or "?"
  if bt == "text" then
    return pad .. "[text]\n" .. _indent(_trim_base64(block.text or ""), pad .. "  ")
  elseif bt == "image" or bt == "image_url" then
    local sz = 0
    if block.source and block.source.data then sz = #block.source.data end
    if block.image_url and block.image_url.url then sz = #block.image_url.url end
    local mt = (block.source and block.source.media_type) or "image"
    return pad .. "[image] " .. mt .. " (" .. sz .. " bytes)"
  elseif bt == "tool_use" then
    local head = pad .. "[tool_use] name=" .. tostring(block.name)
      .. " id=" .. tostring(block.id)
    local body = block.input and _indent(JSON.encode(block.input), pad .. "  ") or ""
    return head .. (body ~= "" and ("\n" .. body) or "")
  elseif bt == "tool_result" then
    local head = pad .. "[tool_result] tool_use_id=" .. tostring(block.tool_use_id)
    local body = block.content and _indent(_trim_base64(tostring(block.content)), pad .. "  ") or ""
    return head .. (body ~= "" and ("\n" .. body) or "")
  else
    return pad .. "[" .. bt .. "]\n" .. _indent(JSON.encode(block), pad .. "  ")
  end
end

-- Render the `content` or `parts` field of a message (string or array).
local function _render_content(content, pad)
  pad = pad or "    "
  if content == nil then return pad .. "(no content)" end
  if type(content) == "string" then
    return _indent(_trim_base64(content), pad)
  end
  if type(content) == "table" then
    local out = {}
    for _, b in ipairs(content) do out[#out+1] = _render_block(b, pad) end
    return table.concat(out, "\n")
  end
  return pad .. tostring(content)
end

-- Decode the request body JSON and produce a readable view. The system prompt
-- content is deliberately omitted (it lives in ReaAssist_System_Prompt.md and
-- is versioned with the script) -- only its length is reported.
local function _render_request(body)
  local ok, req = pcall(JSON.decode, body)
  if not ok or type(req) ~= "table" then
    return "(unparseable JSON)\n" .. body
  end
  local out = {}
  if req.model then out[#out+1] = "Model: " .. tostring(req.model) end
  if req.max_tokens then out[#out+1] = "Max tokens: " .. tostring(req.max_tokens) end
  if req.temperature ~= nil then out[#out+1] = "Temperature: " .. tostring(req.temperature) end

  -- System prompt length. Three shapes:
  --   Anthropic: top-level `system` (string or array of text blocks)
  --   Gemini:    top-level `systemInstruction.parts`
  --   OpenAI:    first `messages` entry with role=="system"
  local sys = req.system or (req.systemInstruction and req.systemInstruction.parts)
  local messages = req.messages or req.contents
  local openai_sys_idx = nil
  if not sys and type(messages) == "table" and type(messages[1]) == "table"
     and messages[1].role == "system" then
    sys = messages[1].content
    openai_sys_idx = 1
  end
  if sys then
    local sys_len = 0
    if type(sys) == "string" then sys_len = #sys
    elseif type(sys) == "table" then
      for _, s in ipairs(sys) do
        if type(s) == "table" and s.text then sys_len = sys_len + #s.text
        elseif type(s) == "string" then sys_len = sys_len + #s
        end
      end
    end
    out[#out+1] = "System prompt: " .. sys_len
      .. " chars (omitted -- content is in ReaAssist_System_Prompt.md)"
  end

  if type(req.tools) == "table" and #req.tools > 0 then
    local names = {}
    for _, t in ipairs(req.tools) do names[#names+1] = t.name or "?" end
    out[#out+1] = "Tools: " .. table.concat(names, ", ")
  end

  -- Any other top-level keys: dump as a compact JSON line so the log reveals
  -- vendor-specific extras (custom-provider extra_body merges, reasoning
  -- configs, Anthropic cache controls, Gemini generationConfig, etc.) that
  -- would otherwise be invisible in the rendered request. Keys already
  -- rendered above are skipped so the line stays focused on the "extras".
  do
    local shown = {
      model = true, max_tokens = true, max_completion_tokens = true,
      temperature = true, system = true, systemInstruction = true,
      messages = true, contents = true, tools = true,
      prompt_cache_key = true,  -- fixed per-session id; noise in the log
    }
    local extras = {}
    local extra_keys = {}
    for k, v in pairs(req) do
      if not shown[k] then
        extras[k] = v
        extra_keys[#extra_keys+1] = k
      end
    end
    if #extra_keys > 0 then
      table.sort(extra_keys)
      local rendered, err = JSON.encode(extras)
      if rendered then
        out[#out+1] = "Extra fields: " .. rendered
      else
        out[#out+1] = "Extra fields: (encode failed: " .. tostring(err) .. ")"
      end
    end
  end

  -- Messages: Anthropic/OpenAI use `messages`; Gemini uses `contents`.
  if type(messages) == "table" then
    -- Count excluding an OpenAI system message we already summarized above.
    local shown = #messages - (openai_sys_idx and 1 or 0)
    out[#out+1] = "Messages (" .. shown .. "):"
    for i, m in ipairs(messages) do
      if i ~= openai_sys_idx then
        out[#out+1] = ""
        out[#out+1] = "  [" .. i .. "] role=" .. tostring(m.role or "?")
        out[#out+1] = _render_content(m.content or m.parts, "      ")
      end
    end
  end

  return table.concat(out, "\n")
end

-- Decode and render the response body.
local function _render_response(body)
  local ok, resp = pcall(JSON.decode, body)
  if not ok or type(resp) ~= "table" then
    return "(unparseable JSON)\n" .. body
  end
  local out = {}

  if resp.error then
    out[#out+1] = "ERROR: " .. JSON.encode(resp.error)
    return table.concat(out, "\n")
  end

  -- Anthropic shape.
  if resp.content or resp.stop_reason then
    if resp.stop_reason then out[#out+1] = "Stop reason: " .. tostring(resp.stop_reason) end
    if type(resp.usage) == "table" then
      local u, parts = resp.usage, {}
      if u.input_tokens              then parts[#parts+1] = "input="       .. u.input_tokens end
      if u.output_tokens             then parts[#parts+1] = "output="      .. u.output_tokens end
      if u.cache_read_input_tokens   then parts[#parts+1] = "cache_read="  .. u.cache_read_input_tokens end
      if u.cache_creation_input_tokens then parts[#parts+1] = "cache_write=" .. u.cache_creation_input_tokens end
      out[#out+1] = "Usage: " .. table.concat(parts, ", ")
    end
    if resp.content then
      out[#out+1] = "Content:"
      out[#out+1] = _render_content(resp.content, "    ")
    end
    return table.concat(out, "\n")
  end

  -- OpenAI shape.
  if type(resp.choices) == "table" then
    for i, c in ipairs(resp.choices) do
      out[#out+1] = "Choice " .. i .. ": finish_reason=" .. tostring(c.finish_reason)
      local msg = c.message or {}
      out[#out+1] = _indent(_trim_base64(tostring(msg.content or "")), "    ")
    end
    if type(resp.usage) == "table" then
      local u = resp.usage
      out[#out+1] = "Usage: prompt=" .. tostring(u.prompt_tokens)
        .. " completion=" .. tostring(u.completion_tokens)
        .. " total=" .. tostring(u.total_tokens)
    end
    return table.concat(out, "\n")
  end

  -- Gemini shape.
  if type(resp.candidates) == "table" then
    for i, c in ipairs(resp.candidates) do
      out[#out+1] = "Candidate " .. i .. ": finish_reason=" .. tostring(c.finishReason)
      if c.content and c.content.parts then
        for _, p in ipairs(c.content.parts) do
          if p.text then out[#out+1] = _indent(_trim_base64(p.text), "    ") end
        end
      end
    end
    if type(resp.usageMetadata) == "table" then
      local u = resp.usageMetadata
      out[#out+1] = "Usage: prompt=" .. tostring(u.promptTokenCount)
        .. " candidates=" .. tostring(u.candidatesTokenCount)
        .. " total=" .. tostring(u.totalTokenCount)
    end
    return table.concat(out, "\n")
  end

  return "(unknown response shape)\n" .. body
end

-- Rolling prune: cap the debug log at MAX_LOG_TURNS newest REQUEST /
-- RESPONSE pairs so a user who forgets to disable logging does not end
-- up with a multi-MB file. Runs at the top of Log.request so the cap
-- holds after the new turn is appended. Session header + system info
-- above the first kept REQUEST delimiter are preserved.
local MAX_LOG_TURNS = 20
local _REQ_DELIM = "\n======= REQUEST #"

-- Monotonic turn counter, shared by REQUEST / RESPONSE pairs so it's obvious
-- which response belongs to which request. Lazily initialized on first use by
-- scanning the existing log file for the highest existing #N so numbers never
-- repeat across script reloads.
Log._turn_counter = nil

local function _init_turn_counter()
  if Log._turn_counter then return end
  Log._turn_counter = 0
  local f = io.open(Log.path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  if not content then return end
  -- Find the largest "#N" immediately after a REQUEST delimiter.
  for n in content:gmatch("======= REQUEST #(%d+)") do
    local num = tonumber(n)
    if num and num > Log._turn_counter then Log._turn_counter = num end
  end
end

local function _prune_log()
  local f = io.open(Log.path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local positions, pos = {}, 1
  while true do
    local p = content:find(_REQ_DELIM, pos, true)
    if not p then break end
    positions[#positions+1] = p
    pos = p + #_REQ_DELIM
  end
  if #positions < MAX_LOG_TURNS then return end
  -- Preserve the prefix (session header / system info) above positions[1],
  -- then keep the newest (MAX_LOG_TURNS - 1) turns so the append makes MAX.
  local prefix_end = positions[1] - 1
  local prefix     = content:sub(1, prefix_end)
  local keep_from  = positions[#positions - (MAX_LOG_TURNS - 1) + 1]
  if not keep_from then return end
  local trimmed = content:sub(keep_from)
  local fw = io.open(Log.path, "w")
  if not fw then return end
  fw:write(prefix)
  fw:write("\n[earlier entries pruned -- auto-pruning to newest "
    .. MAX_LOG_TURNS .. " turns]\n")
  fw:write(trimmed)
  fw:close()
end

Log.request = function(provider_label, body)
  if not prefs.debug_logging then return end
  -- If the log file is missing or empty (user manually deleted it mid-session),
  -- re-arm the session header so it gets rewritten at the top of the new file.
  do
    local f = io.open(Log.path, "r")
    if not f then
      Log._session_header_written = false
    else
      local first = f:read(1)
      f:close()
      if not first then Log._session_header_written = false end
    end
  end
  -- First request since script load (or file was externally deleted): drop a
  -- session header (with system info) at the top so the log always has current
  -- environment info, even if the user didn't just toggle the checkbox.
  if not Log._session_header_written then
    Log._session_header_written = true
    Log.session_header()
  end
  _prune_log()
  _init_turn_counter()
  Log._turn_counter = Log._turn_counter + 1
  Log._current_turn_num = Log._turn_counter
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  _log_write(_REQ_DELIM .. Log._current_turn_num .. " ======= " .. ts
    .. " (" .. tostring(provider_label) .. ", " .. #body .. " bytes) =======\n"
    .. _render_request(body) .. "\n")
end

Log.response = function(body, elapsed)
  if not prefs.debug_logging then return end
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local elapsed_str = elapsed and string.format(", %.2fs", elapsed) or ""
  local num = Log._current_turn_num or "?"
  _log_write("\n======= RESPONSE #" .. tostring(num) .. " ====== " .. ts
    .. " (" .. #body .. " bytes" .. elapsed_str .. ") ===============================\n"
    .. _render_response(body) .. "\n")
end

-- Short tagged line (used for scan events, cache hit/miss, etc.).
Log.line = function(tag, msg)
  if not prefs.debug_logging then return end
  local ts = os.date("%H:%M:%S")
  _log_write("[" .. ts .. "] [" .. tag .. "] " .. tostring(msg) .. "\n")
end

-- Exchange-summary block: mirrors the details bubble (Model, Context, Tokens,
-- Cache, Estimated cost, Response time, FX Cache) so the log captures the same
-- info the user sees on hover. Written after each completed turn.
Log.exchange_summary = function(dmsg)
  if not prefs.debug_logging or not dmsg then return end
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local num = Log._current_turn_num or "?"
  local L = {}
  L[#L+1] = "\n------- EXCHANGE SUMMARY #" .. tostring(num) .. " ----- " .. ts
    .. " -------------------------"
  if dmsg.model_label then
    L[#L+1] = "Model: " .. dmsg.model_label:gsub(" %b()", "")
  end
  if dmsg.thinking_label then
    L[#L+1] = "Thinking: " .. dmsg.thinking_label
  end
  if dmsg.ctx_label then
    L[#L+1] = "Context: " .. dmsg.ctx_label
  end
  if dmsg.tok_in then
    L[#L+1] = string.format("Tokens: %d in / %d out",
      dmsg.tok_in, dmsg.tok_out or 0)
    local cr = dmsg.tok_cache_read   or 0
    local cc = dmsg.tok_cache_create or 0
    if cr > 0 or cc > 0 then
      L[#L+1] = string.format("Cache: %d read, %d created", cr, cc)
    end
    if dmsg.cost and MODELS and MODELS.format_cost then
      if dmsg.free_tier then
        L[#L+1] = "Estimated cost: Free Tier (would have been ~"
          .. MODELS.format_cost(dmsg.cost) .. ")"
      else
        L[#L+1] = "Estimated cost: " .. MODELS.format_cost(dmsg.cost)
      end
    end
  end
  if dmsg.response_time then
    L[#L+1] = string.format("Response time: %.1fs", dmsg.response_time)
  end
  if dmsg.fx_cache_label then
    L[#L+1] = "FX Cache: " .. dmsg.fx_cache_label
  end
  _log_write(table.concat(L, "\n") .. "\n")
end

Log.clear = function()
  Log._session_header_written = false
  Log._turn_counter = 0  -- reset numbering when log is cleared
  Log._current_turn_num = nil
  local f = io.open(Log.path, "w")
  if f then f:close() end
end

-- Build a privacy-safe system info block for the session header. Uses pcall
-- around every extension probe so a missing extension never errors.
local function _build_sysinfo()
  local L = {}
  local function try(fn) local ok, v = pcall(fn); if ok then return v end end

  L[#L+1] = "--- System ---"
  L[#L+1] = "ReaAssist:       " .. tostring(CFG.VERSION)
  L[#L+1] = "REAPER:          " .. tostring(reaper.GetAppVersion())
  L[#L+1] = "OS:              " .. tostring(reaper.GetOS())
  L[#L+1] = "Lua:             " .. tostring(_VERSION)

  -- Extensions (install status + version when available).
  local js_ver = try(function() return reaper.JS_ReaScriptAPI_Version and reaper.JS_ReaScriptAPI_Version() end)
  L[#L+1] = "js_ReaScriptAPI: " .. (js_ver and tostring(js_ver) or "not installed")
  local sws_ok = (reaper.CF_GetSWSVersion ~= nil)
  local sws_ver = sws_ok and try(function() return reaper.CF_GetSWSVersion("") end) or nil
  L[#L+1] = "SWS extension:   " .. (sws_ok and (sws_ver and tostring(sws_ver) or "installed") or "not installed")
  -- ReaImGui version: try a few possible probes (signature varies across
  -- ReaImGui releases; some take no args, some take ctx, some expose a constant).
  local imgui_ver = try(function()
    if not ImGui then return nil end
    if ImGui.ImGui_GetVersion then
      local v = select(1, ImGui.ImGui_GetVersion())
      if v then return v end
    end
    if ImGui.ReaImGui_Version then return ImGui.ReaImGui_Version end
    return nil
  end)
  L[#L+1] = "ReaImGui:        " .. (imgui_ver and tostring(imgui_ver) or "unknown")

  L[#L+1] = ""
  L[#L+1] = "--- Provider / Model ---"
  local p = try(function() return PROVIDERS and PROVIDERS.active and PROVIDERS.active() end)
  L[#L+1] = "Provider:        " .. (p and p.label or "?")
  local model_id = try(function() return MODELS and MODELS.active_id and MODELS.active_id() end)
  L[#L+1] = "Model:           " .. (model_id or "?")
  if p and p.thinking_levels and prefs and p.thinking_levels[prefs.thinking_idx] then
    L[#L+1] = "Thinking:        " .. p.thinking_levels[prefs.thinking_idx].label
  end

  L[#L+1] = ""
  L[#L+1] = "--- Preferences ---"
  if prefs then
    L[#L+1] = "Auto-run:        " .. tostring(prefs.auto_run)
    L[#L+1] = "Auto-backup:     " .. tostring(prefs.auto_backup)
    L[#L+1] = "Snapshot ctx:    " .. tostring(prefs.include_snapshot)
    L[#L+1] = "API ref:         " .. tostring(prefs.include_api_ref)
    local max_tok = try(function() return CFG and CFG.MAX_TOKENS_OPTIONS and CFG.MAX_TOKENS_OPTIONS[prefs.max_tokens_idx] end)
    L[#L+1] = "Max tokens:      " .. tostring(max_tok or "?")
  end
  L[#L+1] = "Max history:     " .. tostring(CFG and CFG.MAX_HISTORY_TURNS or "?")
  L[#L+1] = "API ref loaded:  " .. tostring((S and S.api_ref_cache_core) ~= nil)

  -- FX cache size (plugin-count only; names can be identifying so we omit them).
  local cache_count = try(function()
    if FXCache and FXCache.load then
      local c = FXCache.load()
      if c and c.plugins then
        local n = 0
        for _ in pairs(c.plugins) do n = n + 1 end
        return n
      end
    end
  end)
  if cache_count then
    L[#L+1] = "FX cache size:   " .. tostring(cache_count) .. " plugins"
  end

  -- Excluded on purpose (PII / not debug-relevant):
  --   script path (contains username), API keys, project/track names,
  --   cached plugin identifiers.

  return tbl_concat(L, "\n") .. "\n"
end

Log.session_header = function()
  if not prefs.debug_logging then return end
  Log._session_header_written = true
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  _log_write("\n================================================================\n"
    .. "ReaAssist debug log session start: " .. ts .. "\n"
    .. "================================================================\n\n"
    .. _build_sysinfo() .. "\n")
end

-- =============================================================================
-- MODEL NAMES & PRICING  (easy to update -- edit this table when models change)
-- =============================================================================
-- Each entry: { label, id, price_in, price_out, price_cache_r [, price_cache_w] [, flags] }
-- Prices are USD per 1 million tokens.
-- Sources: anthropic.com/pricing, openai.com/api/pricing, ai.google.dev/gemini-api/docs/pricing
-- Last updated: April 2026
-- =============================================================================
-- Provider definitions
-- =============================================================================
-- Each provider entry holds its API endpoint, authentication style, model list,
-- key format rules, and console/billing URLs. The active provider is selected
-- by prefs.provider_idx (1-based). Adding a new provider is a single table entry.
--
-- auth_style:  "header"      = key sent as an HTTP header (all providers)
-- endpoint:    static URL (Claude, OpenAI) or nil when endpoint_tpl is used.
-- endpoint_tpl: format string with %s for model id (Gemini).
-- key_exclude: reject keys that match this prefix (prevents cross-provider confusion).
-- has_caching: true enables prompt-cache token display/accounting.
-- cache_write applies to Claude only; OpenAI's caching is free to write and
-- Gemini charges a separate per-hour storage fee which is not modeled here.
PROVIDERS = {
  {
    id            = "anthropic",
    label         = "Claude",
    endpoint      = "https://api.anthropic.com/v1/messages",
    auth_style    = "header",
    auth_header   = "x-api-key",
    auth_prefix   = "",
    extra_headers = {
      "anthropic-version: 2023-06-01",
      "anthropic-beta: extended-cache-ttl-2025-04-11",
    },
    key_prefix    = "sk-ant-",
    key_min_len   = 40,
    key_extstate  = "api_key",
    has_caching   = true,
    console_url   = "https://console.anthropic.com/settings/keys",
    console_label = "console.anthropic.com/settings/keys",
    billing_url   = "https://console.anthropic.com/settings/billing",
    billing_label = "console.anthropic.com/settings/billing",
    default_model_idx = 2,
    thinking_levels = nil,  -- Claude: no configurable thinking
    -- price_cache_w reflects the 1-hour cache write rate (2x input). All cache
    -- breakpoints in build_body_anthropic use ttl="1h" via the
    -- extended-cache-ttl-2025-04-11 beta header. (5-min writes would be 1.25x.)
    models = {
      { label = "Haiku 4.5",  chip_label = "HAIKU",  id = "claude-haiku-4-5",
        price_in = 1.00,  price_out = 5.00,  price_cache_r = 0.10, price_cache_w = 2.00  },
      { label = "Sonnet 4.6", chip_label = "SONNET", id = "claude-sonnet-4-6",
        price_in = 3.00,  price_out = 15.00, price_cache_r = 0.30, price_cache_w = 6.00  },
      { label = "Opus 4.6",   chip_label = "OPUS",   id = "claude-opus-4-6",
        price_in = 5.00,  price_out = 25.00, price_cache_r = 0.50, price_cache_w = 10.00 },
    },
  },
  {
    id            = "openai",
    label         = "ChatGPT",
    endpoint      = "https://api.openai.com/v1/chat/completions",
    auth_style    = "header",
    auth_header   = "Authorization",
    auth_prefix   = "Bearer ",
    extra_headers = {},
    key_prefix    = "sk-",
    key_exclude   = "sk-ant-",
    key_min_len   = 30,
    key_extstate  = "api_key_openai",
    has_caching   = true,
    console_url   = "https://platform.openai.com/api-keys",
    console_label = "platform.openai.com/api-keys",
    billing_url   = "https://platform.openai.com/settings/organization/billing",
    billing_label = "platform.openai.com/settings/organization/billing",
    default_model_idx = 2,
    thinking_levels = {
      { label = "None",   value = "none"   },
      { label = "Low",    value = "low"    },
      { label = "Medium", value = "medium" },
      { label = "High",   value = "high"   },
    },
    default_thinking_idx = 3,  -- Medium
    models = {
      { label = "GPT-5.4 nano", chip_label = "NANO", id = "gpt-5.4-nano",
        price_in = 0.20,  price_out = 1.25,  price_cache_r = 0.02  },
      { label = "GPT-5.4 mini", chip_label = "MINI", id = "gpt-5.4-mini",
        price_in = 0.75,  price_out = 4.50,  price_cache_r = 0.075 },
      { label = "GPT-5.4",      chip_label = "FULL", id = "gpt-5.4",
        price_in = 2.50,  price_out = 15.00, price_cache_r = 0.25  },
    },
  },
  {
    id            = "google",
    label         = "Gemini",
    endpoint_tpl  = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent",
    auth_style    = "header",
    auth_header   = "x-goog-api-key",
    extra_headers = {},
    key_prefix    = "AIza",
    key_min_len   = 35,
    key_extstate  = "api_key_google",
    has_caching   = true,
    console_url   = "https://aistudio.google.com/apikey",
    console_label = "aistudio.google.com/apikey",
    billing_url   = "https://aistudio.google.com/apikey",
    billing_label = "aistudio.google.com/apikey",
    default_model_idx = 2,
    thinking_levels = {
      { label = "Minimal", value = "MINIMAL", flash_only = true },
      { label = "Low",     value = "LOW"     },
      { label = "Medium",  value = "MEDIUM"  },
      { label = "High",    value = "HIGH"    },
    },
    default_thinking_idx = 3,  -- Medium
    -- price_cache_r is the text/image/video rate at the lower (<=200K for Pro)
    -- prompt-size tier. Audio cache reads are ~2x and >200K Pro requests are
    -- billed at 2x; the script has no per-request tier tracking so the
    -- lower-tier value is used for the displayed cost estimate.
    models = {
      { label = "Flash Lite 3.1", chip_label = "FLASH LITE", id = "gemini-3.1-flash-lite-preview",
        price_in = 0.25,  price_out = 1.50, price_cache_r = 0.025, is_flash = true },
      { label = "Flash 3",        chip_label = "FLASH",      id = "gemini-3-flash-preview",
        price_in = 0.50,  price_out = 3.00, price_cache_r = 0.05,  is_flash = true },
      { label = "Pro 3.1",        chip_label = "PRO",        id = "gemini-3.1-pro-preview",
        price_in = 2.00,  price_out = 12.00, price_cache_r = 0.20, paid_only = true },
    },
  },
}

-- Provider lookup helpers. No new top-level locals; everything hangs off PROVIDERS.
PROVIDERS._by_id = {}
for i, p in ipairs(PROVIDERS) do PROVIDERS._by_id[p.id] = i end
function PROVIDERS.get(id)    return PROVIDERS[PROVIDERS._by_id[id] or 0] end
function PROVIDERS.active()   return PROVIDERS[prefs.provider_idx] end

-- =============================================================================
-- Custom LLM / custom-endpoint provider support
-- =============================================================================
-- Registers OpenAI-compatible chat-completions endpoints as additional
-- providers. Works with truly local servers (Ollama, LM Studio, llama.cpp,
-- vLLM, text-generation-webui) and online services that speak the OpenAI wire
-- format (OpenRouter, Groq, DeepSeek, Together AI, Mistral, Fireworks, etc.).
-- Configured via the Custom Providers list page, persisted to ExtState.
--
-- The user can register any number of custom providers. Each record is a
-- self-contained endpoint with its own label, URL, timeout, API key, and
-- model list. Each model row is id + per-million-token input/output prices
-- + context window. Prices are displayed in the Show Details bubble;
-- ReaAssist is NOT optimized for these endpoints and the cost number is an
-- estimate only.
--
-- Storage (ExtState, per-install). One index key plus four per-record keys,
-- keyed by a stable record id of the form "custom_<8 hex chars>":
--
--   custom_provider_ids                 -- comma-separated ordered id list
--   custom_<id>_label                   -- friendly name shown in combo
--   custom_<id>_endpoint                -- full URL
--   custom_<id>_timeout_secs            -- request timeout in seconds (curl --max-time)
--   custom_<id>_connect_timeout         -- TCP/TLS handshake timeout in seconds
--                                          (curl --connect-timeout)
--   custom_<id>_allow_insecure          -- "1" to pass curl --insecure (skip TLS
--                                          verification; for self-signed local servers)
--   custom_<id>_model_prefix            -- optional string prepended to each model
--                                          id sent in the request body (e.g. "openrouter/")
--   custom_<id>_extra_headers           -- newline-delimited HTTP headers, each
--                                          "Name: value". Values are validated on
--                                          save to reject triple-quotes / newlines
--                                          that would break Windows curl argv.
--   custom_<id>_extra_body              -- optional provider-wide JSON object
--                                          merged into every chat-completions
--                                          body. Validated as a JSON object at
--                                          save time and stored in canonical
--                                          (JSON.encode) form. Per-model
--                                          extra_body (stored inside the models
--                                          blob) overrides these keys on a
--                                          per-request basis.
--   custom_<id>_models                  -- newline-delimited rows, pipe-delimited
--                                          fields with optional tab-prefixed
--                                          extra_body suffix. Full 6-field form:
--                                            id|price_in|price_out|context|price_cache_r|notes[\t<extra_body_json>]
--                                          4- and 5-field legacy shapes are still
--                                          accepted on read; writes always use
--                                          the 6-field canonical form.
--   api_key_<id>                        -- optional Bearer token, encoded via Key.encode
--
-- The record id doubles as the provider id in the PROVIDERS table, so every
-- existing lookup that goes through PROVIDERS.get(id) / PROVIDERS._by_id[id]
-- continues to work. Flat per-record keys (rather than a single JSON blob)
-- let this module run at script load without waiting on the JSON codec,
-- which is defined 8k lines later.
Custom = {}

CUSTOM_DEFAULT_CTX          = 65536  -- per-model fallback if everything is missing
CUSTOM_DEFAULT_TIMEOUT      = 600    -- 10 minutes
CUSTOM_MIN_TIMEOUT          = 10
CUSTOM_MAX_TIMEOUT          = 3600   -- 1 hour cap
CUSTOM_MIN_CTX              = 256
CUSTOM_DEFAULT_TEST_TIMEOUT = 30     -- Test Connection curl --max-time (hard-coded;
                                           -- 30s accommodates remote/cloud-compatible
                                           -- endpoints while staying responsive locally)
-- Connect-timeout bounds live on the Custom namespace (not as file-scope
-- locals) because ReaAssist's main chunk is at the 200-locals ceiling --
-- adding three more would overflow. Referenced anywhere we currently use
-- the CUSTOM_DEFAULT_* constants.
Custom.DEFAULT_CONNECT = 10
Custom.MIN_CONNECT     = 1
Custom.MAX_CONNECT     = 60
-- Per-model free-text label shown in the main-screen model dropdown next to
-- the id (e.g. "kimi-k2.6 . fast" vs "kimi-k2.6 . thinking"). Capped so the
-- dropdown stays readable and rejected at save time if it contains delimiters
-- ("|" or "\t") that would break the models blob parser.
Custom.MAX_NOTES_LEN   = 20

-- Return true if s is safe to drop into an HTTP-header slot on the curl
-- command line across both shells we target. Rejects newlines (which would
-- split the argument), null bytes, and the triple-quote boundary that our
-- Windows PowerShell launcher uses to terminate each -H argument. Everything
-- else (Unicode, spaces, dollar signs, backticks, single/double quotes) is
-- fine because the POSIX branch wraps each header in sq() (POSIX single-
-- quote escape) and the Windows branch wraps each header in triple double
-- quotes for cmd.exe; neither shell interpolates inside those contexts.
function Custom.header_is_safe(s)
  if type(s) ~= "string" then return false end
  if s:find("[%z\n\r]") then return false end
  if s:find('"""', 1, true) then return false end
  return true
end

-- Parse a multi-line "Name: value" buffer into an array of header strings.
-- Returns (array, err). err is non-nil if any non-blank line fails
-- validation -- we return on the FIRST bad line so the user gets one
-- specific error to fix rather than a pile. Blank lines are skipped.
function Custom.parse_headers_text(text)
  local out = {}
  local lineno = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
      if not Custom.header_is_safe(trimmed) then
        return nil, str_format(
          "Line %d contains a newline, null byte, or triple-quote that "
          .. "can't be sent safely. Remove those characters.", lineno)
      end
      local name, rest = trimmed:match("^([^:]+):%s*(.*)$")
      if not name or name:match("^%s*$") then
        return nil, str_format(
          "Line %d is not in \"Name: value\" format. Each header must "
          .. "have a name, a colon, and a value.", lineno)
      end
      -- Reject Authorization collision: users should use the API Key
      -- field for bearer tokens, not here. Also blocks accidental
      -- duplicate Authorization headers overriding the auth file.
      if name:lower():match("^%s*authorization%s*$") then
        return nil, str_format(
          "Line %d: use the API Key field for Authorization; don't "
          .. "set it here.", lineno)
      end
      out[#out+1] = trimmed
    end
  end
  return out, nil
end

-- Validate a user-typed Extra Body JSON buffer. Trims whitespace. Empty input
-- is considered valid (returns "" with nil err). Non-empty input must parse
-- as a JSON OBJECT (not an array, not a scalar) via JSON.decode, and re-encode
-- cleanly; the re-encoded canonical form is what gets stored. Called from the
-- UI save handlers for both the provider-level field and the per-model popup.
--
-- Runs after JSON.decode is defined (line ~11369), so all call sites (Save
-- button in the custom_llm edit screen) reach it lazily at click time.
function Custom.validate_extra_body(text)
  if not text then return "", nil end
  local trimmed = text:match("^%s*(.-)%s*$") or ""
  if trimmed == "" then return "", nil end
  local obj, err = JSON.decode(trimmed)
  if err or obj == nil then
    return nil, "Not valid JSON: " .. (err or "unknown parse error")
  end
  if type(obj) ~= "table" then
    return nil, "Must be a JSON object like {\"thinking\":{\"type\":\"disabled\"}}"
  end
  -- Reject arrays and the null sentinel: valid JSON but not an object.
  if obj == JSON.NULL then
    return nil, "Must be a JSON object, got null"
  end
  local n = 0
  local is_array = true
  for k in pairs(obj) do
    n = n + 1
    if type(k) ~= "number" then is_array = false end
  end
  if n > 0 and is_array then
    return nil, "Must be a JSON object, got an array"
  end
  -- Canonicalize by re-encoding so storage is normalized (no trailing whitespace,
  -- no comments, stable key order as emitted by JSON.encode). An empty object
  -- still canonicalizes to "{}", which is semantically a no-op at build time.
  local encoded, eerr = JSON.encode(obj)
  if not encoded then
    return nil, "Failed to canonicalize: " .. tostring(eerr)
  end
  return encoded, nil
end

-- Validate a per-model short notes string. Trims whitespace, enforces the
-- length cap, and rejects the two delimiter characters (pipe, tab) that the
-- models blob format uses between fields. Newlines are also rejected because
-- the blob uses "\n" as the row separator. Returns (clean_string, nil) on
-- success or (nil, error_string) on failure.
function Custom.validate_notes(text)
  if not text then return "", nil end
  local trimmed = text:match("^%s*(.-)%s*$") or ""
  if trimmed == "" then return "", nil end
  if #trimmed > Custom.MAX_NOTES_LEN then
    return nil, str_format("Notes must be %d characters or fewer.",
      Custom.MAX_NOTES_LEN)
  end
  if trimmed:find("[|\t\n\r]") then
    return nil, "Notes cannot contain pipe (|), tab, or newline characters."
  end
  return trimmed, nil
end

-- Seed math.random once per script load so consecutive Custom.gen_id calls
-- don't return the same value. math.randomseed is otherwise never called;
-- Lua's default seed is deterministic, so two reloads would otherwise mint
-- identical ids and collide with previously-saved records.
math.randomseed(math.floor((reaper.time_precise() or 0) * 1e6) % 2147483647)
-- Generate a new stable record id. Prefixed "custom_" so logs and ExtState
-- dumps are self-describing; 8 random hex chars for 4-billion-wide namespace
-- (collision-resistant for any realistic record count).
function Custom.gen_id()
  local chars = {}
  for i = 1, 8 do chars[i] = str_format("%x", math.random(0, 15)) end
  return "custom_" .. tbl_concat(chars)
end

-- Read the ordered id list. Returns {} when unset. IDs are re-validated by
-- the caller against the per-record keys before being trusted.
function Custom.load_ids()
  local raw = reaper.GetExtState(CFG.EXT_NS, "custom_provider_ids")
  if raw == "" then return {} end
  local ids = {}
  for id in (raw .. ","):gmatch("([^,]*),") do
    id = id:match("^%s*(.-)%s*$") or ""
    if id ~= "" then ids[#ids+1] = id end
  end
  return ids
end

function Custom.save_ids(ids)
  reaper.SetExtState(CFG.EXT_NS, "custom_provider_ids",
    tbl_concat(ids or {}, ","), true)
end

-- Parse a per-record "models" ExtState blob. Pipe-delimited fields, one line
-- per model. The extra_body field (optional JSON object) is appended after a
-- tab separator to avoid pipe-in-JSON collisions; single-line JSON.encode
-- output never contains a literal tab, so tab is a safe sentinel. The notes
-- field (short free-text label shown in the main-screen model dropdown) is
-- rejected at save time if it contains "|" or "\t", so it's safe inside the
-- pipe-delimited main part.
--
-- Row formats accepted (parser chooses by pipe-field count, then peels off
-- optional extra_body after the first tab):
--   4 fields: id|price_in|price_out|context                            (original)
--   5 fields: id|price_in|price_out|context|price_cache_r              (+cache hit)
--   6 fields: id|price_in|price_out|context|price_cache_r|notes        (+notes)
--   ...any of the above + "\t" + JSON                                  (+extra_body)
--
-- Empty / malformed rows are dropped. Missing optional fields default to 0/"".
local function parse_models_blob(raw)
  local out = {}
  if not raw or raw == "" then return out end
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      -- Peel off optional extra_body after the tab sentinel.
      local main, extra = line:match("^(.-)\t(.*)$")
      if not main then main = line end
      local id, pin, pout, ctx, pcache, notes =
        main:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
      if not id then
        id, pin, pout, ctx, pcache =
          main:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        notes = ""
      end
      if not id then
        id, pin, pout, ctx = main:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        pcache, notes = "", ""
      end
      if id and id ~= "" then
        local ctx_n = tonumber(ctx) or CUSTOM_DEFAULT_CTX
        if ctx_n < CUSTOM_MIN_CTX then ctx_n = CUSTOM_MIN_CTX end
        out[#out+1] = {
          id             = id,
          price_in       = tonumber(pin)    or 0,
          price_out      = tonumber(pout)   or 0,
          price_cache_r  = tonumber(pcache) or 0,
          context_window = ctx_n,
          notes          = notes or "",
          extra_body     = extra or "",
        }
      end
    end
  end
  return out
end

local function encode_models_blob(models)
  local lines = {}
  for _, m in ipairs(models or {}) do
    local ctx    = tonumber(m.context_window) or CUSTOM_DEFAULT_CTX
    local pcache = tonumber(m.price_cache_r)  or 0
    local base = (m.id or "") .. "|"
              .. tostring(m.price_in  or 0) .. "|"
              .. tostring(m.price_out or 0) .. "|"
              .. tostring(ctx) .. "|"
              .. tostring(pcache) .. "|"
              .. (m.notes or "")
    local extra = m.extra_body or ""
    if extra ~= "" then
      lines[#lines+1] = base .. "\t" .. extra
    else
      lines[#lines+1] = base
    end
  end
  return tbl_concat(lines, "\n")
end

-- Read one record by id. Returns nil if the record has no endpoint or
-- no valid models (either field missing = record is effectively empty,
-- same treatment as a record that was never saved).
function Custom.load_record(id)
  if not id or id == "" then return nil end
  local endpoint = reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_endpoint")
  if endpoint == "" then return nil end
  local label      = reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_label")
  local models_raw = reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_models")
  local timeout    = tonumber(
    reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_timeout_secs"))
    or CUSTOM_DEFAULT_TIMEOUT
  if timeout < CUSTOM_MIN_TIMEOUT then timeout = CUSTOM_MIN_TIMEOUT end
  if timeout > CUSTOM_MAX_TIMEOUT then timeout = CUSTOM_MAX_TIMEOUT end
  local connect_t = tonumber(
    reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_connect_timeout"))
    or Custom.DEFAULT_CONNECT
  if connect_t < Custom.MIN_CONNECT then connect_t = Custom.MIN_CONNECT end
  if connect_t > Custom.MAX_CONNECT then connect_t = Custom.MAX_CONNECT end
  local allow_insecure =
    reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_allow_insecure") == "1"
  local model_prefix   =
    reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_model_prefix")
  -- Parse extra headers. One "Name: value" per line; drop empty and unsafe
  -- lines silently (they were either blanks the user left between edits or
  -- characters that slipped past UI validation -- better to drop than to
  -- try to render a command line with them).
  local headers_raw =
    reaper.GetExtState(CFG.EXT_NS, "custom_" .. id .. "_extra_headers")
  local extra_headers = {}
  if headers_raw and headers_raw ~= "" then
    for line in (headers_raw .. "\n"):gmatch("([^\n]*)\n") do
      line = line:match("^%s*(.-)%s*$") or ""
      if line ~= "" and Custom.header_is_safe(line) and line:find(":", 1, true) then
        extra_headers[#extra_headers+1] = line
      end
    end
  end
  local models = parse_models_blob(models_raw)
  if #models == 0 then return nil end
  -- Provider-level extra_body: raw JSON string (canonicalized at save time).
  -- Trusted as-is at load; the save validator is the only gate that checks
  -- syntax, so a hand-edited ExtState with garbage JSON would flow through
  -- until the first send and be rejected by the remote API. That's an
  -- acceptable tradeoff for not re-parsing on every script load.
  local extra_body = reaper.GetExtState(
    CFG.EXT_NS, "custom_" .. id .. "_extra_body") or ""
  return {
    id                  = id,
    label               = (label ~= "" and label) or "Custom",
    endpoint            = endpoint,
    timeout_secs        = timeout,
    connect_timeout_secs = connect_t,
    allow_insecure      = allow_insecure,
    model_prefix        = model_prefix or "",
    extra_headers       = extra_headers,
    extra_body          = extra_body,
    models              = models,
  }
end

-- Read every valid record in the order the id list specifies. Records whose
-- per-key data is missing/empty are silently skipped AND pruned from the
-- stored id list, so the list is self-healing against manual ini edits
-- (or partial factory-reset states) that leave a dangling id with no
-- backing data.
function Custom.load_all()
  local ids = Custom.load_ids()
  local records = {}
  local valid_ids = {}
  local pruned = false
  for _, id in ipairs(ids) do
    local rec = Custom.load_record(id)
    if rec then
      records[#records+1]     = rec
      valid_ids[#valid_ids+1] = id
    else
      pruned = true
    end
  end
  if pruned then Custom.save_ids(valid_ids) end
  return records
end

-- Persist one record's per-key data. Does NOT touch the id list -- that's
-- managed by upsert_record / remove_record so save_record stays idempotent
-- for in-place edits.
function Custom.save_record(record)
  local id = record.id
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_endpoint",
    record.endpoint or "", true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_label",
    record.label or "", true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_timeout_secs",
    tostring(record.timeout_secs or CUSTOM_DEFAULT_TIMEOUT), true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_connect_timeout",
    tostring(record.connect_timeout_secs or Custom.DEFAULT_CONNECT), true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_allow_insecure",
    record.allow_insecure and "1" or "0", true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_model_prefix",
    record.model_prefix or "", true)
  -- Extra headers: filter unsafe entries here too, so a record can't carry
  -- a malformed header even if save_record is called from a code path that
  -- skipped the UI validator.
  local safe_headers = {}
  for _, h in ipairs(record.extra_headers or {}) do
    if Custom.header_is_safe(h) and h:find(":", 1, true) then
      safe_headers[#safe_headers+1] = h
    end
  end
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_extra_headers",
    tbl_concat(safe_headers, "\n"), true)
  -- Provider-level extra_body: stored as-is. Save handlers are expected to
  -- have already canonicalized it via Custom.validate_extra_body before
  -- reaching here, so this write is a straight pass-through.
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_extra_body",
    record.extra_body or "", true)
  reaper.SetExtState(CFG.EXT_NS, "custom_" .. id .. "_models",
    encode_models_blob(record.models or {}), true)
end

-- Save + ensure the record's id appears in the ordered id list. If the id
-- is already present, only the per-key data is rewritten (the list order
-- is preserved so the provider dropdown doesn't reshuffle on every edit).
function Custom.upsert_record(record)
  Custom.save_record(record)
  local ids = Custom.load_ids()
  for _, existing in ipairs(ids) do
    if existing == record.id then return end
  end
  ids[#ids+1] = record.id
  Custom.save_ids(ids)
end

-- Delete one record: wipe its per-key ExtState, drop from the id list, clear
-- its API key. The caller is responsible for calling unregister_id if the
-- record is currently registered in PROVIDERS.
function Custom.remove_record(id)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_endpoint",        true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_label",           true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_timeout_secs",    true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_connect_timeout", true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_allow_insecure",  true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_model_prefix",    true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_extra_headers",   true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_extra_body",      true)
  reaper.DeleteExtState(CFG.EXT_NS, "custom_" .. id .. "_models",          true)
  reaper.DeleteExtState(CFG.EXT_NS, "api_key_" .. id,                      true)
  local ids = Custom.load_ids()
  for i = #ids, 1, -1 do
    if ids[i] == id then table.remove(ids, i) end
  end
  Custom.save_ids(ids)
end

function Custom.build_provider(record)
  -- Build one entry per configured model so the main UI's model dropdown
  -- shows them all and per-message cost uses the correct prices. Each model
  -- carries its own context_window so the preflight check can warn against
  -- requests that would overflow the specific model the user has loaded.
  --
  -- Display label: the raw model id, with an optional short notes tag
  -- appended (" . <notes>") so rows that share a model id but differ in
  -- tuning (thinking on/off, temperature preset, etc.) are distinguishable
  -- in the main-screen dropdown. The on-wire id stays unmodified.
  local prov_models = {}
  for _, m in ipairs(record.models or {}) do
    local label = m.id or ""
    if m.notes and m.notes ~= "" then
      label = label .. " \xc2\xb7 " .. m.notes  -- utf-8 middle dot
    end
    prov_models[#prov_models+1] = {
      label          = label,
      id             = m.id,
      price_in       = m.price_in       or 0,
      price_out      = m.price_out      or 0,
      price_cache_r  = m.price_cache_r  or 0,
      context_window = m.context_window or CUSTOM_DEFAULT_CTX,
      extra_body     = m.extra_body     or "",
      notes          = m.notes          or "",
    }
  end
  if #prov_models == 0 then
    -- Defensive: build_provider should never be called with an empty list,
    -- but if it is, give the dropdown a single placeholder so the main UI
    -- doesn't crash on MODELS[1] indexing.
    prov_models[1] = { label = "Custom", id = "custom", price_in = 0,
                       price_out = 0, price_cache_r = 0,
                       context_window = CUSTOM_DEFAULT_CTX,
                       extra_body = "", notes = "" }
  end
  -- Pass-through the saved extra headers (already sanitized at save time).
  -- A defensive second pass here catches any record that was hand-written
  -- directly into ExtState, bypassing the UI's validator.
  local headers_pass = {}
  for _, h in ipairs(record.extra_headers or {}) do
    if Custom.header_is_safe(h) and h:find(":", 1, true) then
      headers_pass[#headers_pass+1] = h
    end
  end
  -- has_caching: true when any model on this provider has a non-zero cache-hit
  -- price. Gates the cost-accounting display so custom providers that surface
  -- usage.prompt_tokens_details.cached_tokens (Kimi, OpenRouter, some vLLM
  -- builds) get their cached portion billed at the discounted rate instead
  -- of being silently dropped from the cost estimate.
  local has_caching = false
  for _, m in ipairs(prov_models) do
    if (m.price_cache_r or 0) > 0 then has_caching = true; break end
  end

  return {
    id                = record.id,
    label             = record.label or "Custom",
    endpoint          = record.endpoint,
    auth_style        = "header",
    auth_header       = "Authorization",
    auth_prefix       = "Bearer ",
    extra_headers     = headers_pass,
    key_prefix        = "",
    key_min_len       = 0,
    key_extstate      = "api_key_" .. record.id,
    has_caching       = has_caching,
    console_url       = nil,
    console_label     = nil,
    billing_url       = nil,
    billing_label     = nil,
    default_model_idx = 1,
    thinking_levels   = nil,
    is_custom         = true,
    -- Request timeout is provider-wide (one curl --max-time value applies
    -- regardless of which model is currently selected from the dropdown).
    request_timeout   = record.timeout_secs or CUSTOM_DEFAULT_TIMEOUT,
    connect_timeout   = record.connect_timeout_secs or Custom.DEFAULT_CONNECT,
    allow_insecure    = record.allow_insecure and true or false,
    -- Prepended to MODELS.active_id() when building the OpenAI-compatible
    -- request body. Empty string is the no-op default.
    model_prefix      = record.model_prefix or "",
    -- Provider-wide JSON object merged into every chat-completions request
    -- body. Stored in canonical JSON.encode form (validated at save time).
    -- Per-model extra_body overrides keys set here on a per-request basis;
    -- see Net.build_body_openai for the merge.
    extra_body        = record.extra_body or "",
    models            = prov_models,
  }
end

-- Append one provider entry to PROVIDERS and refresh lookup tables. Returns
-- the 1-based index of the new entry. Does NOT remove existing customs --
-- that's register_all's job; register_one is primarily for the in-flight
-- connection-test path that registers a single temporary provider.
-- Bumped whenever the custom-provider list mutates (register_one /
-- unregister_all / unregister_id). Render-side code can key cached
-- "list custom records" walks on this cookie and only rebuild on
-- change rather than rebuilding every frame on the screens that show
-- them.
Custom._records_version = 0

function Custom.register_one(record)
  local prov = Custom.build_provider(record)
  PROVIDERS[#PROVIDERS+1]    = prov
  PROVIDERS._by_id[prov.id]  = #PROVIDERS
  Custom._records_version    = Custom._records_version + 1
  return #PROVIDERS
end

-- Remove every entry flagged is_custom. Caller is responsible for clamping
-- prefs.provider_idx after -- indices shift when entries disappear.
function Custom.unregister_all()
  for i = #PROVIDERS, 1, -1 do
    if PROVIDERS[i].is_custom then table.remove(PROVIDERS, i) end
  end
  PROVIDERS._by_id = {}
  for i, p in ipairs(PROVIDERS) do PROVIDERS._by_id[p.id] = i end
  Custom._records_version = Custom._records_version + 1
end

-- Remove one specific custom entry by id. Used by the connection-test path
-- to pull the temporary test provider without disturbing saved records.
function Custom.unregister_id(id)
  for i = #PROVIDERS, 1, -1 do
    if PROVIDERS[i].id == id then table.remove(PROVIDERS, i) end
  end
  PROVIDERS._by_id = {}
  for i, p in ipairs(PROVIDERS) do PROVIDERS._by_id[p.id] = i end
  Custom._records_version = Custom._records_version + 1
end

-- Full refresh: clear every custom entry, then re-register each persisted
-- record in the saved order. Safe to call multiple times.
function Custom.register_all()
  Custom.unregister_all()
  for _, rec in ipairs(Custom.load_all()) do
    Custom.register_one(rec)
  end
end

-- Register every persisted record at startup so prefs.provider_idx clamping
-- below sees every custom entry as a valid index.
Custom.register_all()

-- =============================================================================
-- Provider + Model selector
-- =============================================================================
-- prefs.provider_idx selects the active AI service (1-based index into PROVIDERS).
-- prefs.model_idx selects the model within that provider (1-based).
-- Both are persisted in ExtState. The model index is stored per-provider so
-- switching providers remembers each provider's last-used model.
--
-- MODELS is a dynamic proxy that always reflects the active provider's model list.
-- All existing code that reads MODELS[prefs.model_idx], MODELS.active_id(), and
-- MODELS.calc_cost() continues to work unchanged.
MODELS = {}

-- Load provider_idx (default 1 = Claude for existing and new users).
-- Helper: load an ExtState integer index into a 1..#list range, falling
-- back to `default` on a missing / corrupt / out-of-range value. Used
-- for the four index-into-list prefs below; standalone clamps remain
-- inline for cloud_request_timeout (MIN/MAX in CFG) and help_font_scale
-- (decimal range).
local function _prefs_load_idx(key, default, list)
  local v = tonumber(reaper.GetExtState(CFG.EXT_NS, key)) or default
  if v < 1 or v > #list then v = default end
  return v
end

prefs.provider_idx = _prefs_load_idx("provider_idx", 1, PROVIDERS)

-- Load max_tokens_idx (default 3 = 16384 / 16K). 16K gives ~5x headroom
-- over the largest responses ReaAssist typically generates (~2-3K tokens)
-- without inflating the rare-failure cost ceiling that a higher default
-- would create. Apply to CFG.MAX_TOKENS immediately.
prefs.max_tokens_idx = _prefs_load_idx("max_tokens_idx", 3, CFG.MAX_TOKENS_OPTIONS)
CFG.MAX_TOKENS = CFG.MAX_TOKENS_OPTIONS[prefs.max_tokens_idx]

-- Load cloud_request_timeout (default CFG.CLOUD_TIMEOUT_DEFAULT = 180s). Clamp
-- to [CLOUD_TIMEOUT_MIN, CLOUD_TIMEOUT_MAX] so a corrupt ExtState value can't
-- break the watchdog.
prefs.cloud_request_timeout = tonumber(
  reaper.GetExtState(CFG.EXT_NS, "cloud_request_timeout"))
  or CFG.CLOUD_TIMEOUT_DEFAULT
if prefs.cloud_request_timeout < CFG.CLOUD_TIMEOUT_MIN
   or prefs.cloud_request_timeout > CFG.CLOUD_TIMEOUT_MAX then
  prefs.cloud_request_timeout = CFG.CLOUD_TIMEOUT_DEFAULT
end

-- Load ui_scale_idx (default 3 = 100%). SC() scales any pixel value by the factor.
prefs.ui_scale_idx = _prefs_load_idx("ui_scale_idx", 3, CFG.UI_SCALE_OPTIONS)
function RA.SC(px)
  return math.floor(px * CFG.UI_SCALE_OPTIONS[prefs.ui_scale_idx] + 0.5)
end

-- =============================================================================
-- V5 FONT ATLAS -- Inter (5 weights) + JetBrains Mono (3 weights), shipped as
-- TTFs in Resources/fonts/. ReaImGui 0.10+ API: CreateFontFromFile takes no
-- size argument (it was dropped); the pixel size is specified per-PushFont and
-- ReaImGui re-rasterizes via FreeType on the fly, so one font handle per
-- weight renders crisply at any size. inter_reg is attached first so
-- the ReaImGui default-font slot resolves to Inter Regular for any
-- PushFont(ctx, nil, size) call.
-- =============================================================================
local FONTS_DIR = RA.RESOURCES_DIR .. "fonts" .. RA.SEP
-- Canonical font file list. Shared by the atlas build below and the
-- bootstrap CRITICAL_FILES check so the two lists cannot drift.
FONT_FILES = {
  inter_reg   = "Inter_18pt-Regular.ttf",
  inter_light = "Inter_18pt-Light.ttf",
  inter_semi  = "Inter_18pt-SemiBold.ttf",
  inter_bold  = "Inter_18pt-Bold.ttf",
  mono_reg    = "JetBrainsMono-Regular.ttf",
  mono_med    = "JetBrainsMono-Medium.ttf",
  mono_semi   = "JetBrainsMono-SemiBold.ttf",
  -- Lucide icon font (MIT). Icons are addressed by their Private Use Area
  -- codepoints; see the ICON table below. Ship as Resources/fonts/lucide.ttf.
  lucide      = "lucide.ttf",
}
-- Missing-file tolerance: early Stage 3.3 check logic downstream needs the
-- atlas build to survive a broken Resources/fonts directory. If the file is
-- missing, return nil instead of crashing -- the bootstrap pre-loop guard
-- (further down this file) detects the same missing fonts and routes into
-- recovery mode before any rendering code would deref the nil handle.
local function _mkfont(rel)
  local path = FONTS_DIR .. rel
  local probe = io.open(path, "r")
  if not probe then return nil end
  probe:close()
  local f = ImGui.ImGui_CreateFontFromFile(path, 0, 0)
  if f then ImGui.ImGui_Attach(RA.ctx, f) end
  return f
end
FONT = {}
FONT.inter_reg   = _mkfont(FONT_FILES.inter_reg)
FONT.inter_light = _mkfont(FONT_FILES.inter_light)
FONT.inter_semi  = _mkfont(FONT_FILES.inter_semi)
FONT.inter_bold  = _mkfont(FONT_FILES.inter_bold)
FONT.mono_reg    = _mkfont(FONT_FILES.mono_reg)
FONT.mono_med    = _mkfont(FONT_FILES.mono_med)
FONT.mono_semi   = _mkfont(FONT_FILES.mono_semi)
FONT.lucide      = _mkfont(FONT_FILES.lucide)
RA.bold_font = FONT.inter_bold
RA.code_font = FONT.mono_reg

-- Build a UTF-8 string for a Unicode codepoint in the U+0800..U+FFFF range.
-- Lucide glyphs live in PUA (U+E000..U+F8FF), which always encodes to 3-byte
-- UTF-8. The ICON table precomputes these so source stays ASCII.
local function _utf8(cp)
  return string.char(
    0xE0 | (cp >> 12),
    0x80 | ((cp >> 6) & 0x3F),
    0x80 | (cp & 0x3F))
end
-- Codepoints extracted from lucide-static's font/info.json (encodedCode field).
ICON = {
  PAPERCLIP        = _utf8(0xE12D),
  SEND             = _utf8(0xE152),
  SETTINGS         = _utf8(0xE154),
  HEART            = _utf8(0xE0F2),
  CHEVRON_DOWN     = _utf8(0xE06D),
  X                = _utf8(0xE1B2),
  PLUS             = _utf8(0xE13D),
  COPY             = _utf8(0xE09E),
  INFO             = _utf8(0xE0F9),
  CHECK            = _utf8(0xE06C),
  PLAY             = _utf8(0xE13C),
  ZAP              = _utf8(0xE1B4),
  CORNER_DOWN_LEFT = _utf8(0xE0A1),
  FILE             = _utf8(0xE0C0),
  SUN              = _utf8(0xE178),
  MOON             = _utf8(0xE11E),
  -- Credits-screen link-row glyphs (verified against lucide.ttf's
  -- Unicode cmap). Prefer these over hand-drawn arrows so the icon
  -- weight matches the rest of the V5 Lucide icons (gear, plus, sun,
  -- etc.) rather than standing out as a one-off line-draw.
  LINK             = _utf8(0xE102),
  MAIL             = _utf8(0xE10F),
  PHONE            = _utf8(0xE133),
  SAVE             = _utf8(0xE14D),  -- floppy-disk glyph, for Save buttons
  REDO_2           = _utf8(0xE2A0),  -- Lucide redo-2 glyph; used as Rescan affordance
}

-- Load chat_font_idx (default 2 = Medium/14px).
prefs.chat_font_idx = _prefs_load_idx("chat_font_idx", 2, CFG.CHAT_FONT_SIZES)

-- Help-page text-scale multiplier (applies only to help section titles
-- and body text, not to chat / settings / chrome). Default 1.0, range
-- clamped 0.8 -> 1.5 in 0.1 steps -- changed via the - / + buttons on
-- the Help page's search row. Persisted so the user's reading size
-- survives reloads.
prefs.help_font_scale = tonumber(reaper.GetExtState(CFG.EXT_NS, "help_font_scale")) or 1.0
if prefs.help_font_scale < 0.8 then prefs.help_font_scale = 0.8 end
if prefs.help_font_scale > 1.5 then prefs.help_font_scale = 1.5 end

-- MODELS.refresh: syncs the MODELS array with the active provider's model list,
-- loads the per-provider model_idx from ExtState, and invalidates the combo cache.
function MODELS.refresh()
  local p = PROVIDERS.active()
  -- Build the visible model list. For Gemini, hide paid-only models when the
  -- tier is known-free OR untested. Untested-as-free is the safer default:
  -- showing Pro on a free-tier account that just hasn't tier-tested yet
  -- means the user picks Pro, sends, and gets a confusing API error. The
  -- tier-test fires automatically right after a Google key save (see
  -- post_save_settle), so the nil window is short -- once it resolves,
  -- MODELS.refresh fires again and a paid user immediately sees the full
  -- list.
  local src = p.models
  if p.id == "google" and S.gemini_paid_tier ~= true then
    src = {}
    for _, m in ipairs(p.models) do
      if not m.paid_only then src[#src+1] = m end
    end
  end
  -- Copy into MODELS array slots; clear any stale extras. Use clear-then-
  -- fill instead of a single mixed loop, because writing nil to slots past
  -- #src leaves nil holes -- safe for direct index access but breaks any
  -- future `for i=1,#MODELS do` iterator (which stops at the first hole).
  for i = #MODELS, 1, -1 do MODELS[i] = nil end
  for i, m in ipairs(src) do MODELS[i] = m end
  -- Load per-provider model_idx.
  local key = "model_idx_" .. p.id
  local default_idx
  if p.id == "google" and S.gemini_paid_tier ~= true then
    default_idx = math_min(2, #src)  -- Flash (mid) to match paid-tier default
  else
    default_idx = p.default_model_idx or #src
  end
  prefs.model_idx = _prefs_load_idx(key, default_idx, src)
  -- Load per-provider thinking_idx (0 = not supported).
  if p.thinking_levels then
    local tkey = "thinking_idx_" .. p.id
    local tdefault = p.default_thinking_idx or 1
    prefs.thinking_idx = tonumber(reaper.GetExtState(CFG.EXT_NS, tkey)) or tdefault
    if prefs.thinking_idx < 1 or prefs.thinking_idx > #p.thinking_levels then
      prefs.thinking_idx = tdefault
    end
  else
    prefs.thinking_idx = 0
  end
end

function MODELS.active_id()
  local m = MODELS[prefs.model_idx] or MODELS[1]
  return m and m.id or PROVIDERS.active().models[1].id
end

-- =============================================================================
-- API key loading
-- =============================================================================
-- The API key is stored in REAPER's ExtState (persisted in reaper-extstate.ini)
-- as an XOR-obfuscated hex string locked to this machine's install path.
-- On first launch with no key, a welcome message prompts the user to paste
-- their key directly into the chat. The key can be changed later via the
-- Settings button.
--
-- Install-moved detection: if the stored value decodes to something that
-- doesn't look like an API key, the install path has changed. Set a flag
-- so the UI can show a re-entry prompt with an explanation.
-- Load API keys for all providers from ExtState. Each provider's key is stored
-- under its own ExtState key (key_extstate field). The decoded key is validated
-- against the provider's expected prefix and minimum length.
do
  for _, p in ipairs(PROVIDERS) do
    local stored = reaper.GetExtState(CFG.EXT_NS, p.key_extstate)
    if stored ~= "" then
      local decoded = Key.decode(stored)
      local prefix_pat = "^" .. p.key_prefix:gsub("%-", "%%-")
      if decoded and decoded:match(prefix_pat) and #decoded >= p.key_min_len then
        S.api_key_map[p.id] = decoded
      else
        -- Decode failed (magic prefix mismatch): install path has changed.
        -- Do NOT clear the stored blob -- restoring the original path will
        -- recover the key because the XOR anchor will match again.
        S.key_install_moved = true
      end
    end
  end
  -- Convenience alias: active provider's key.
  S.api_key = S.api_key_map[PROVIDERS.active().id]
  -- Load persisted Gemini tier (nil if never tested).
  local tier_str = reaper.GetExtState(CFG.EXT_NS, "gemini_paid_tier")
  if tier_str == "true" then S.gemini_paid_tier = true
  elseif tier_str == "false" then S.gemini_paid_tier = false
  end
  -- If force-cold-cache is persisted on from a prior session, mint a fresh
  -- stamp for this session. The stamp lives per script lifetime, so
  -- reloading = new cold start even if the pref stayed on.
  if prefs.test_force_cold_cache then
    S.cold_cache_stamp = tostring(reaper.time_precise())
  end
end

-- Must run AFTER the ExtState tier/key load above: refresh()'s free-
-- tier filter reads S.gemini_paid_tier, so calling it earlier would
-- leave paid_only models (Gemini Pro) visible to free-tier users.
MODELS.refresh()

-- Determine the initial first-run screen. Order: TOS first, then API key, then main UI.
-- Show the first-run API key screen only if NO provider has a key set.
if not api_keys.tos_is_accepted() then
  api_keys.screen = "tos"
elseif not next(S.api_key_map) then
  api_keys.screen = "first_run"
else
  api_keys.screen = nil
end

-- =============================================================================
-- Script state
-- =============================================================================
-- S.history: API conversation pairs {role, content}.
--   Content stores the user's prompt text (prefixed with "USER REQUEST:\n") and
--   optionally the API reference, but NEVER the session snapshot. The snapshot is
--   injected at send time by Net.build_body() so only the current turn gets fresh
--   project state. Only the most recent CFG.MAX_HISTORY_TURNS entries are sent to the
--   API (via Net.trimmed_history); older entries are kept for display only.
--
-- S.display_messages: UI-only list for rendering the chat. Each entry:
--   role             (string)  "user" or "assistant"
--   content          (string)  text shown in the chat (bare prompt for user, response for assistant)
--   code_block       (string)  extracted Lua code from ```lua fences, or nil
--   ctx_label        (string)  context info for Show Details: "snapshot", "snapshot + api_ref",
--                              "snapshot + docs", "error", "timeout"
--   tok_in           (number)  total input tokens for this exchange (set on response)
--   tok_out          (number)  output tokens for this exchange (set on response)
--   tok_cache_read   (number)  input tokens served from cache (subset of tok_in)
--   tok_cache_create (number)  input tokens written to cache this call (subset of tok_in)
--   cost             (number)  estimated USD cost for this exchange (set on response)
--   model_label      (string)  model label captured at send time
--   link_url         (string)  optional clickable URL rendered after content
--   link_label       (string)  display text for the link (defaults to link_url if omitted)
--   storage_note     (string)  optional dim secondary line shown after the link (used on key-entry messages)

-- If the REAPER install path changed since the key was last saved, the
-- key can't be decoded and the user must re-enter it. Surface as an
-- inline error on the API key screen.
if S.key_install_moved then
  api_keys.key_error = "Your REAPER install location has changed since your "
    .. "API key was last saved. For security, the key is locked to the install "
    .. "path and cannot be decoded from a different location. Please paste "
    .. "your API key again to continue."
end


-- =============================================================================
-- Utility: MODELS.calc_cost
-- =============================================================================
-- Returns the estimated USD cost for one API exchange given token counts and
-- a model entry from the MODELS table. Prices are per million tokens.
-- tok_in_base: non-cached input tokens; tok_cache_r: cache-hit read tokens;
-- tok_cache_w: cache-write tokens; tok_out: output tokens.
function MODELS.calc_cost(model_entry, tok_in_base, tok_cache_r, tok_cache_w, tok_out)
  if not model_entry then return 0 end
  local M = 1000000
  return (tok_in_base  * (model_entry.price_in      or 0)
        + tok_cache_r  * (model_entry.price_cache_r  or 0)
        + tok_cache_w  * (model_entry.price_cache_w  or 0)
        + tok_out      * (model_entry.price_out      or 0)) / M
end

-- MODELS.format_cost(usd) -> string like "$0.000123" or "$1.23"
-- Uses 6 significant digits for sub-cent amounts, 4 for larger values.
function MODELS.format_cost(usd)
  if usd == 0 then return "$0.000000" end
  if usd < 0.01 then
    return str_format("$%.6f", usd)
  elseif usd < 1 then
    return str_format("$%.4f", usd)
  else
    return str_format("$%.2f", usd)
  end
end

-- =============================================================================
-- STYLING -- Edit hex colours here to restyle the entire plugin.
-- All values are RGBA 32-bit integers: 0xRRGGBBAA (AA=FF means fully opaque).
-- =============================================================================

-- Dark palette - the original Monochrome Pro color scheme.
local PALETTE_DARK = {
  -- Backgrounds
  WIN_BG    = 0x2A2A2AFF,  -- main window bg (bottom of gradient; lifted for a more visible top->bottom fade)
  FRAME_BG  = 0x363636FF,  -- prompt input box background (lifted graphite for readability)
  INPUT_BG  = 0x3E3E3EFF,  -- input when nested on a darker card (needs extra lift)
  USER_BG   = 0x0A0A0AFF,  -- user message bubble background (near black)
  ASSIST_BG = 0x00000000,  -- reserved: assistant has no bubble
  CODE_BG   = 0x0B111CFF,  -- V5: deep navy-black, matches TK.code_bg so dark-mode code blocks read as distinct framed containers
  COPY_BTN  = 0x313E44FF,  -- Copy, Save, Undo, Backup, etc. button normal
  COPY_HOV  = 0x3E4F57FF,  -- Copy, Save, etc. button hovered
  COPY_ACT  = 0x263238FF,  -- Copy, Save, etc. button active/pressed
  -- Chrome (borders, title bars, separators, popup backgrounds)
  BORDER    = 0x37474FFF,  -- window/popup borders and title bars
  SEP       = 0x3E4348FF,  -- separator lines (brightened for readability on dark BG)
  HDR       = 0x1E1E1EFF,  -- selectable header normal (darker than bg)
  HDR_HOV   = 0x2A2A2AFF,  -- selectable header hovered
  SUCCESS   = 0x66CC66FF,  -- success/green text
  WARN_HOV  = 0xDD8800FF,  -- warning button hovered
  WARN_ACT  = 0xBB7700FF,  -- warning button active
  CARD_HOV  = 0x83BCEB22,  -- card hover overlay (ice-blue tint for clickable feel)
  -- Semi-transparent overlay buttons (e.g. scroll-to-bottom)
  OBTN      = 0x37474F88,  -- overlay button normal
  OBTN_HOV  = 0x455A6488,  -- overlay button hovered
  OBTN_ACT  = 0x26323888,  -- overlay button active
  -- Chat text
  CHAT_TEXT = 0xFFFFFFFF,  -- main chat text (pure white)
  USER      = 0x90A4AEFF,  -- user message label ("You") (muted blue-grey)
  ASSIST    = 0x83BCEBFF,  -- assistant label ("ReaAssist") - ice blue accent
  CODE_FG   = 0xE7ECF3FF,  -- code block text -- TK.text bright so id/var/etc. read crisply on the dark gradient
  -- V5 syntax palette: purple keywords, amber functions (API), orange numbers,
  -- green strings, faint comments. Matches the V5 mockup and the TK_DARK tokens.
  CODE_KW   = 0xB57EE6FF,  -- keywords (local / for / end / do / if / ... )
  CODE_STR  = 0x7CCDA0FF,  -- string literals
  CODE_NUM  = 0xF0A46BFF,  -- numeric literals
  CODE_COM  = 0x6B7484FF,  -- comments (text_faint tone)
  CODE_API  = 0xEAB07EFF,  -- API / function names (reaper.Xxx)
  STATUS    = 0x607D8BFF,  -- status / welcome text (blue-grey)
  DETAIL    = 0x546E7AFF,  -- dim detail text (dark blue-grey)
  ERROR     = 0xFF6060FF,  -- error label
  WARN      = 0xFFAA44FF,  -- warning / "running code" indicator
  LINK      = 0x5D809CFF,  -- clickable URL text
  -- Buttons
  SEND_BTN  = 0x5D809CFF,  -- Send button normal (muted ice blue)
  SEND_HOV  = 0x7A9BB2FF,  -- Send button hovered
  SEND_ACT  = 0x4A6A80FF,  -- Send button active/pressed
  SEND_DIM  = 0x455A64FF,  -- Send button when prompt is empty
  SEND_TEXT = 0xFFFFFFFF,  -- white text on primary buttons
  RUN_BTN   = 0x5D809CFF,  -- Run Code button
  BTN       = 0x37474FFF,  -- bottom bar buttons / checkbox backgrounds
  BTN_HOV   = 0x455A64FF,  -- bottom bar buttons hovered
  BTN_ACT   = 0x263238FF,  -- bottom bar buttons active/pressed
  -- Welcome screen
  CARD_BG   = 0x282828FF,  -- card background
  CARD_HEAD = 0xB0BEC5FF,  -- card heading text
  CARD_DESC = 0x78909CFF,  -- card description text
  CARD_BRD  = 0x3E4348FF,  -- card border (brightened so edges read cleanly)
  FOOTER    = 0x78909CFF,  -- footer / attribution text
  -- Scrollbar (chat pane)
  SCROLL_BG      = 0x1A1A1AFF,  -- track
  SCROLL_GRAB    = 0x455A64FF,  -- thumb (matches BTN_HOV)
  SCROLL_GRAB_H  = 0x546E7AFF,  -- thumb hovered
  SCROLL_GRAB_A  = 0x37474FFF,  -- thumb active
  WIN_BG_TOP     = 0x0B0B0BFF,  -- window bg gradient top (darker)
  CARD_BRD_HI    = 0x55606AFF,  -- top-edge highlight for bevel-like border gradient
  ASSIST_DK      = 0x4A7DA8FF,  -- darker ice-blue for visible stripe/accent gradients
}

-- Light palette - soft blue-white background, dark text, blue accents.
-- Base:  BG #F4F7FB  Surface #FFFFFF  Card #EDF2F7
--        Button #DCE7F3  Text #1F2A37  Muted #5B6B7C  Accent #5B8DEF
local PALETTE_LIGHT = {
  -- Backgrounds
  WIN_BG    = 0xECF2F9FF,  -- BG: soft blue-white (subtly darkened)
  FRAME_BG  = 0xEDF1F7FF,  -- Surface: light gray input fields (distinct from WIN_BG)
  INPUT_BG  = 0xFFFFFFFF,  -- input when nested on a darker card (white surface)
  USER_BG   = 0xE3EBF5FF,  -- user bubble: light blue tint
  ASSIST_BG = 0x00000000,  -- no assistant bubble
  CODE_BG   = 0xE4E9F1FF,  -- V5: cool light gray-blue -- deeper than the chat bg so the code box reads as a framed container rather than blending with the bg in light mode
  COPY_BTN  = 0xDCE7F3FF,  -- Button: copy/save normal
  COPY_HOV  = 0xC6D5E9FF,  -- copy/save hovered
  COPY_ACT  = 0xB0C3DFFF,  -- copy/save active
  -- Chrome
  BORDER    = 0xCBD5E1FF,  -- borders and title bars
  SEP       = 0xD8E0E9FF,  -- separator lines
  HDR       = 0xEDF2F7FF,  -- selectable header normal (Card)
  HDR_HOV   = 0xE0E7EFFF,  -- selectable header hovered
  SUCCESS   = 0x2E7D32FF,  -- success green
  WARN_HOV  = 0xE68A00FF,  -- warning button hovered
  WARN_ACT  = 0xCC7A00FF,  -- warning button active
  CARD_HOV  = 0x5B8DEF18,  -- card hover overlay (accent blue tint for clickable feel)
  -- Semi-transparent overlay buttons
  OBTN      = 0xCBD5E188,  -- overlay button normal
  OBTN_HOV  = 0xB0C3DF88,  -- overlay button hovered
  OBTN_ACT  = 0x9AB2D288,  -- overlay button active
  -- Chat text
  CHAT_TEXT = 0x1F2A37FF,  -- Text: dark charcoal
  USER      = 0x3B4B5AFF,  -- user label (slightly lighter than text)
  ASSIST    = 0x5B8DEFFF,  -- Accent: logo and accent blue
  CODE_FG   = 0x0F1824FF,  -- code text -- TK.text dark so id/var/etc. read crisply
  -- V5 syntax palette: purple keywords, amber functions (API), orange numbers,
  -- green strings, faint comments. Matches the V5 mockup and TK_LIGHT tokens.
  CODE_KW   = 0x7A3DB8FF,  -- keywords (local / for / end / do / if / ... )
  CODE_STR  = 0x2E8A4FFF,  -- string literals
  CODE_NUM  = 0xB55A18FF,  -- numeric literals
  CODE_COM  = 0x8B94A3FF,  -- comments (text_faint tone)
  CODE_API  = 0xA06A26FF,  -- API / function names (reaper.Xxx)
  STATUS    = 0x5B6B7CFF,  -- Muted: status text
  DETAIL    = 0x5B6B7CFF,  -- Muted: dim detail text
  ERROR     = 0xDC2626FF,  -- error red
  WARN      = 0xE65100FF,  -- warning orange
  LINK      = 0x5B8DEFFF,  -- Accent: links
  -- Buttons
  SEND_BTN  = 0x91B1F1FF,  -- primary button
  SEND_HOV  = 0xA8C3F5FF,  -- primary hovered (lighter)
  SEND_ACT  = 0x7A9FE8FF,  -- primary active (darker)
  SEND_DIM  = 0xB0BCCCFF,  -- send when empty (muted)
  SEND_TEXT = 0xFFFFFFFF,  -- white text on primary buttons
  RUN_BTN   = 0x91B1F1FF,  -- primary: run code button
  BTN       = 0xDCE7F3FF,  -- Button: bottom bar
  BTN_HOV   = 0xC6D5E9FF,  -- bottom bar hovered
  BTN_ACT   = 0xB0C3DFFF,  -- bottom bar active
  -- Welcome screen
  CARD_BG   = 0xEDF2F7FF,  -- Card: card background
  CARD_HEAD = 0x1F2A37FF,  -- Text: card heading
  CARD_DESC = 0x5B6B7CFF,  -- Muted: card description
  CARD_BRD  = 0xBFCBDDFF,  -- card border (darkened so edges read cleanly on light BG)
  FOOTER    = 0x5B6B7CFF,  -- Muted: footer text
  -- Scrollbar (chat pane) - soft blue-gray that complements BORDER/SEP
  SCROLL_BG      = 0xE6ECF3FF,  -- track (slightly darker than WIN_BG)
  SCROLL_GRAB    = 0xB8C5D6FF,  -- thumb (muted blue-gray)
  SCROLL_GRAB_H  = 0x9AB2D2FF,  -- thumb hovered
  SCROLL_GRAB_A  = 0x7A9FE8FF,  -- thumb active (ties to accent)
  WIN_BG_TOP     = 0xE5EBF3FF,  -- window bg gradient top (very slightly darker than WIN_BG)
  CARD_BRD_HI    = 0xD0DAE8FF,  -- top-edge highlight for bevel-like border gradient
  ASSIST_DK      = 0x2E57A8FF,  -- darker ice-blue for visible stripe/accent gradients
}

-- =============================================================================
-- V5 design tokens (authoritative palette)
-- =============================================================================
-- TK.* is the canonical palette for all redesigned surfaces. The legacy
-- COL table above covers a few remaining untouched sections.
local TK_DARK = {
  bg            = 0x161D29FF,    -- brighter canvas -- lifted from 0x0D131B so dark mode reads less black-hole
  bg_elev       = 0x1C2534FF,    -- (was 0x121924)
  card          = 0x242D3BFF,    -- (was 0x171E28) -- more distinct against the lifted bg
  card_hover    = 0x2C3648FF,    -- (was 0x1C2330)
  prompt_bg     = 0x2E3847FF,    -- slightly brighter than card so the prompt reads as the active input
                                 -- (was sharing TK.card with the capability tiles)
  border        = 0x7896C835,    -- rgba(120,150,200,0.21) -- bumped alpha for stronger card edges
  border_str    = 0x7896C85A,    -- rgba(120,150,200,0.35) (was 0.28)
  text          = 0xE7ECF3FF,
  text_muted    = 0x9FA7B8FF,    -- lifted from 0x9199AA for better readability of URL links and helper text on the dark card. Hue preserved; brightness up ~8%.
  text_faint    = 0x6B7484FF,    -- lifted from 0x5B6474 so mono section labels still read
  accent        = 0x5E84DCFF,    -- primary blue, toned down from the original 0x6B8FF0 so Save/Run buttons, the "ReaAssist" wordmark, and the "Unsaved changes" indicator read less shouty against the dark bg. Saturation dropped ~17% + brightness shaved ~6% while keeping the hue, so the blue still reads as ReaAssist's signature colour.
  accent_ui     = 0x44598CFF,    -- default accent for interactive surfaces in dark mode (card-toward-accent 0.45 blend). The pure `accent` above is reserved for text-on-bg uses (wordmark, status label, etc.) where the hotter tone reads right.
  accent_soft   = 0x243358FF,    -- hero gradient top -- deepened to keep gradient visible against new bg
  accent_text   = 0xFFFFFFFF,    -- text on accent fills
  nc_chip_bg    = 0x2E3847FF,    -- "+ new chat" chip rest fill -- subtle lift above accent_soft so the chip reads as a surface
  nc_chip_hover = 0x3D4A5EFF,    -- "+ new chat" chip hover fill -- clearly brighter than rest for affordance
  details_bg    = 0x242D3B80,    -- details card fill (TK.card at 50% alpha -- the chat bg gradient shows through)
  user_bg       = 0x2A386066,    -- user bubble fill -- muted dark-blue @ 40% alpha so the chat gradient behind shows through
  user_border   = 0x526C99FF,    -- user bubble border -- subtle blue outline, closer to the fill than to the pure accent
  user_text     = 0xE7ECF3FF,    -- user bubble text -- bright white for contrast against the dark-blue fill
  model_pill_bg = 0x242D3BFF,    -- assistant model-name pill fill (= TK.card tone in dark mode -- reads as a subtle surface)
  toggle_off_bg = 0x2A3240FF,    -- V5 toggle switch "off" pill fill (dark mode)
  input_bg      = 0x171C27FF,    -- V5 password/text input fill -- one notch darker than TK.card so inputs read as recessed wells on the card surface
  green         = 0x49C27AFF,    -- LIVE dot / success
  red           = 0xD46F6FFF,    -- V5 destructive-action fill (Factory Reset, Clear Cache, Run Anyway). Softer than COL.ERROR so it reads as "serious action" not "error state".
  amber         = 0xE0A040FF,    -- V5 warning tone (TESTING pill, advisory text). Matches the warmer muted amber used across TK.
  autorun_fill  = 0x784559FF,    -- AUTO-RUN active-segment fill. Darker + less saturated than the light-mode pink so it reads as a subtle caution cue against the dark canvas, not a bright attention-grabber.
  footer_bg     = 0x00000026,    -- rgba(0,0,0,0.15)
  code_bg       = 0x0B111CFF,    -- V5: deep navy-black, noticeably darker than TK.bg so code blocks read as distinct containers in dark mode
  kw_purple     = 0xB57EE6FF,    -- code keywords
  fn_amber      = 0xEAB07EFF,    -- code function names
  num_orange    = 0xF0A46BFF,    -- code numbers
  str_green     = 0x7CCDA0FF,    -- code strings/booleans
}
local TK_LIGHT = {
  bg            = 0xE6EAF1FF,    -- slightly darker than the original #EEF1F6
  bg_elev       = 0xF3F6FBFF,
  card          = 0xFFFFFFFF,
  card_hover    = 0xF3F6FAFF,
  prompt_bg     = 0xFFFFFFFF,    -- same as card in light mode (already pure white)
  border        = 0x465F8C42,    -- rgba(70,95,140,0.26) -- bumped from 0.18 so V5 cards read against the light bg
  border_str    = 0x465F8C5C,
  text          = 0x0F1824FF,
  text_muted    = 0x475467FF,
  text_faint    = 0x8B94A3FF,
  accent        = 0x5A80CCFF,    -- slightly desaturated from the original 0x4A73D6 so Save/Run buttons (which fill with TK.accent) read calmer against the near-white light-mode bg. Hue preserved; saturation dropped ~12% for a gentler pop.
  accent_ui     = 0x89A4E4FF,    -- default accent for interactive surfaces in light mode (card-toward-accent 0.65 blend)
  accent_soft   = 0xBDD1EEFF,    -- deeper pale blue for a more visible hero gradient in light mode
  accent_text   = 0xFFFFFFFF,
  nc_chip_bg    = 0xDDE5EEFF,    -- "+ new chat" chip rest fill -- solid light gray-blue, reads as a contained surface on the hero gradient
  nc_chip_hover = 0xFFFFFF8C,    -- "+ new chat" chip hover fill -- white @ ~55% alpha, a brighter/airier highlight on hover
  details_bg    = 0xD9E0EBB3,    -- details card fill -- cool light gray-blue @ 70% alpha; less bright than pure white so the card reads as contextual info, not a primary surface
  user_bg       = 0xD3E7FF66,    -- user bubble fill -- mockup's #D3E7FF pale blue @ 40% alpha so the chat gradient shows through
  user_border   = 0x89A4E4FF,    -- user bubble border -- TK.accent_ui tone, softer than the saturated primary accent so the outline doesn't shout
  user_text     = 0x4A73D6FF,    -- user bubble text -- TK.accent blue; colouring the text instead of the border carries the "user" identity
  model_pill_bg = 0xDDE5EEFF,    -- assistant model-name pill fill -- cool light gray-blue, noticeably less bright than pure white so the pill doesn't blow out against the chat bg in light mode
  toggle_off_bg = 0xD2D8E2FF,    -- V5 toggle switch "off" pill fill (light mode)
  input_bg      = 0xECEFF5FF,    -- V5 password/text input fill -- subtle gray vs pure-white card so inputs read as recessed wells
  green         = 0x3AA268FF,
  red           = 0xC14747FF,    -- V5 destructive-action fill (light-mode pair for TK.red)
  amber         = 0xB87A20FF,    -- V5 warning tone (light-mode pair for TK.amber)
  autorun_fill  = 0xEB88B0FF,    -- AUTO-RUN active-segment fill (light-mode pair for TK.autorun_fill). Soft pink that signals "risky mode active" as a gentle cue rather than an error-state red.
  footer_bg     = 0x00000005,    -- rgba(0,0,0,0.02)
  code_bg       = 0xF3F6FBFF,    -- V5: subtle cool off-white, reads as a framed container on the near-white chat bg in light mode
  kw_purple     = 0x7A3DB8FF,
  fn_amber      = 0xA06A26FF,
  num_orange    = 0xB55A18FF,
  str_green     = 0x2E8A4FFF,
}
TK = {}
local TK_PALETTES = { dark = TK_DARK, light = TK_LIGHT }
local function apply_tk(palette)
  for k, v in pairs(palette) do TK[k] = v end
end

-- Active color table - populated from the selected palette at startup and on change.
COL = {}
PALETTES = { dark = PALETTE_DARK, light = PALETTE_LIGHT }
function apply_palette(palette)
  for k, v in pairs(palette) do COL[k] = v end
  -- Keep the V5 token table in lockstep with theme changes.
  local theme_key = (palette == PALETTE_LIGHT) and "light" or "dark"
  apply_tk(TK_PALETTES[theme_key])
  -- Drop any palette-derived caches in the UI module so chat code blocks
  -- and other cached color tables rebuild against the new COL.* slots on
  -- next render. Guarded because apply_palette runs once at boot before
  -- ReaAssist_UI.lua is loaded; UI.invalidate_palette_caches is nil then.
  if UI and UI.invalidate_palette_caches then
    UI.invalidate_palette_caches()
  end
end
-- Detect OS light/dark mode (Windows registry, macOS defaults, Linux gsettings).
-- Results are cached in ExtState for 1 hour to avoid repeated ExecProcess calls
-- on startup (PowerShell invocation alone can add 100-500ms on Windows). The
-- in-memory cache further guarantees at most one detection per session.
local OS_THEME_TTL = 3600  -- seconds
local _os_theme_cache     -- in-memory cache for this session
local function detect_os_theme()
  if _os_theme_cache then return _os_theme_cache end
  local cached    = reaper.GetExtState(CFG.EXT_NS, "os_theme_cache")
  local cached_ts = tonumber(reaper.GetExtState(CFG.EXT_NS, "os_theme_cache_ts") or "") or 0
  local now       = os.time()
  if (cached == "dark" or cached == "light") and (now - cached_ts) < OS_THEME_TTL then
    _os_theme_cache = cached
    return cached
  end
  -- Cache miss / stale / corrupted: re-detect below and persist the result.
  -- Skip the ExtState write when Factory Reset has set the suppress flag,
  -- so the freshly-cleared cache keys don't reappear within seconds of
  -- reset. The in-memory cache still updates so detection isn't repeated
  -- until the next OS_THEME_TTL window.
  local function _store(theme)
    _os_theme_cache = theme
    if not (S and S._suppress_os_theme_cache) then
      reaper.SetExtState(CFG.EXT_NS, "os_theme_cache", theme, true)
      reaper.SetExtState(CFG.EXT_NS, "os_theme_cache_ts", tostring(now), true)
    end
    return theme
  end
  if RA.IS_WINDOWS then
    local cmd = 'powershell -NoProfile -WindowStyle Hidden -Command "'
      .. '(Get-ItemProperty -Path '
      .. "'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' "
      .. '-Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme"'
    local result = reaper.ExecProcess(cmd, 3000)
    if result then
      -- ExecProcess returns "exitcode\nstdout..." - skip exit code line
      local output = result:match("^[^\n]*\n(.*)") or ""
      local val = output:match("%d+")
      if val == "0" then return _store("dark") end
      if val == "1" then return _store("light") end
    end
  elseif RA.IS_MACOS then
    local cmd = '/bin/sh -c "defaults read -g AppleInterfaceStyle 2>/dev/null"'
    local result = reaper.ExecProcess(cmd, 2000)
    if result then
      local output = result:match("^[^\n]*\n(.*)") or ""
      if output:match("Dark") then return _store("dark") end
    end
    return _store("light")
  else
    -- Linux: check common desktop environment settings.
    local cmd = '/bin/sh -c "gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null"'
    local result = reaper.ExecProcess(cmd, 2000)
    if result then
      local output = result:match("^[^\n]*\n(.*)") or ""
      if output:match("dark") then return _store("dark") end
      if output:match("light") then return _store("light") end
    end
    -- Fallback: check gtk-theme name for "dark" substring.
    cmd = '/bin/sh -c "gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null"'
    result = reaper.ExecProcess(cmd, 2000)
    if result then
      local output = result:match("^[^\n]*\n(.*)") or ""
      if output:lower():match("dark") then return _store("dark") end
    end
  end
  return _store("dark")  -- fallback
end
-- Resolve the effective palette name for a theme preference.
function resolve_theme(theme)
  if theme == "auto" then return detect_os_theme() end
  return theme
end
-- Load theme preference and apply the initial palette.
prefs.theme = reaper.GetExtState(CFG.EXT_NS, "theme")
if prefs.theme ~= "dark" and prefs.theme ~= "light" then prefs.theme = "auto" end
-- Shift-Launch failsafe: if Shift is held when the script starts, reset UI
-- scale to 100%, theme to Auto, and clear saved window geometry.
-- Uses js_ReaScriptAPI to read the keyboard state at init time (before ImGui).
if reaper.JS_Mouse_GetState then
  -- JS_Mouse_GetState modifier bits: 8 = Shift, 4 = Ctrl, 16 = Alt
  if reaper.JS_Mouse_GetState(8) == 8 then
    prefs.ui_scale_idx = 3  -- 100%
    prefs.theme = "auto"
    reaper.SetExtState(CFG.EXT_NS, "ui_scale_idx", "3", true)
    reaper.SetExtState(CFG.EXT_NS, "theme", "auto", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_x", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_y", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_w", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_h", true)
  end
end
apply_palette(PALETTES[resolve_theme(prefs.theme)])
-- =============================================================================

-- =============================================================================
-- Utility: Key.mask
-- =============================================================================
-- Returns a masked display of the API key matching each provider's console format:
--   Anthropic: first 15 chars + "..." + last 4     e.g. "sk-ant-api03-75f...iwAA"
--   OpenAI:    literal "sk-..." + last 4           e.g. "sk-...KVwA"
--   Google:    "..." + last 4                      e.g. "..._U0M"
--   Custom / unknown: Anthropic-style long prefix (most informative fallback)
-- For very short keys (unlikely), returns the full key unmasked.
function Key.mask(key, provider_id)
  if not key then return "" end
  if #key <= 8 then return key end
  if provider_id == "google" then
    return "..." .. key:sub(-4)
  elseif provider_id == "openai" then
    return "sk-..." .. key:sub(-4)
  end
  if #key <= 19 then return key end
  return key:sub(1, 15) .. "..." .. key:sub(-4)
end

-- =============================================================================
-- Utility: Key.validate_format
-- =============================================================================
-- Checks whether a string looks like a plausible API key for a given provider
-- before sending it to the network. This catches common mistakes:
--   - pasting a URL instead of a key
--   - partial clipboard pastes
--   - random text or sentences
--   - pasting the wrong provider's key
-- Returns true if the format is plausible, false + reason string otherwise.
-- provider defaults to the active provider if omitted.
function Key.validate_format(key, provider)
  provider = provider or PROVIDERS.active()
  -- Custom providers: key is OPTIONAL (many custom endpoints run without auth).
  -- Skip prefix and length checks; only enforce no-whitespace if a key is set.
  if provider.is_custom then
    if key and #key > 0 and key:match("%s") then
      return false, "Key contains spaces or newlines. Please paste the key "
        .. "as a single unbroken string."
    end
    return true
  end
  if not key or #key == 0 then
    return false, "No key was entered."
  end
  -- Check for wrong-provider keys first (e.g. Claude key pasted in OpenAI field).
  if provider.key_exclude then
    local exclude_pat = "^" .. provider.key_exclude:gsub("%-", "%%-")
    if key:match(exclude_pat) then
      return false, "This looks like a different provider's key."
    end
  end
  local prefix_pat = "^" .. provider.key_prefix:gsub("%-", "%%-")
  if not key:match(prefix_pat) then
    return false, "Key does not start with \"" .. provider.key_prefix .. "\". "
      .. provider.label .. " API keys always begin with this prefix."
  end
  if #key < (provider.key_min_len or 30) then
    return false, "Key appears too short (only " .. #key .. " characters). "
      .. "This may be an incomplete paste."
  end
  -- Reject keys containing whitespace (multi-line paste, trailing newlines).
  if key:match("%s") then
    return false, "Key contains spaces or newlines. Please paste the key "
      .. "as a single unbroken string."
  end
  return true
end

UI = {}

-- Per-model hover descriptions shown in the V5 model dropdown. Keyed by model
-- id (not label) so renaming a label doesn't silently desync the text. Kept
-- to one short sentence so the tooltip reads at a glance.
UI.MODEL_TIPS = {
  ["claude-haiku-4-5"]               = "Fastest + cheapest Claude. Best for quick questions, simple edits, and short scripts.",
  ["claude-sonnet-4-6"]              = "Balanced Claude default. Best for most coding, debugging, and session-analysis tasks.",
  ["claude-opus-4-6"]                = "Smartest Claude. Best for complex architecture, tricky bugs, and nuanced audio advice.",
  ["gpt-5.4-nano"]                   = "Fastest + cheapest GPT. Best for simple lookups and short replies.",
  ["gpt-5.4-mini"]                   = "Balanced GPT default. Solid reasoning at moderate cost.",
  ["gpt-5.4"]                        = "Flagship GPT. Best for deep reasoning, tough debugging, and nuanced prompts.",
  ["gemini-3.1-flash-lite-preview"]  = "Fastest + cheapest Gemini. Best for simple chat and high-volume tasks.",
  ["gemini-3-flash-preview"]         = "Balanced Gemini. Strong quality/speed tradeoff for everyday use.",
  ["gemini-3.1-pro-preview"]         = "Smartest Gemini. Best for complex reasoning and long-context work (paid tier).",
}

-- Transient below-chip toast. Caller passes plain text; the chip-row renderer
-- draws it in the whitespace above the footer, left-aligned with the model
-- chip. Animation: 200ms fade-in, 5s hold, 800ms fade-out (6s total). Click
-- on the text dismisses immediately.
function UI.show_toast(text)
  local now = reaper.time_precise()
  local FADE_IN, HOLD, FADE_OUT = 0.2, 5.0, 0.8
  S.toast = {
    text            = text,
    start_at        = now,
    fade_in_end_at  = now + FADE_IN,
    hold_end_at     = now + FADE_IN + HOLD,
    fade_out_end_at = now + FADE_IN + HOLD + FADE_OUT,
    fade_in_s       = FADE_IN,
    fade_out_s      = FADE_OUT,
  }
end

-- Floating toast: a top-level rounded bubble near the bottom-center of the
-- ReaAssist window. Unlike UI.show_toast (which prints text in a fixed spot
-- in the chat chrome), this draws its OWN window on top of whatever's below,
-- so it's visible regardless of scroll position or which settings page is
-- current. Animation: 180ms fade-in, 1.6s hold, 500ms fade-out (2.3s total).
-- Sticky=true skips the hold/fade-out and keeps the toast visible until the
-- caller replaces it (by firing another show_float_toast) or clears it
-- (S.float_toast = nil). Used by the Settings "Check for Updates" button
-- to show "Checking for updates..." throughout the async manifest fetch.
function UI.show_float_toast(text, kind, sticky)
  local now = reaper.time_precise()
  local FADE_IN, HOLD, FADE_OUT = 0.18, 1.6, 0.5
  S.float_toast = {
    text            = text,
    kind            = kind or "ok",  -- "ok" (green accent) | "err" (red accent)
    sticky          = sticky == true,
    start_at        = now,
    fade_in_end_at  = now + FADE_IN,
    hold_end_at     = now + FADE_IN + HOLD,
    fade_out_end_at = now + FADE_IN + HOLD + FADE_OUT,
    fade_in_s       = FADE_IN,
    fade_out_s      = FADE_OUT,
  }
end

-- =============================================================================
-- Utility: UI.open_url
-- =============================================================================
-- Opens a URL in the user's default browser. Tries SWS CF_ShellExecute first
-- (available when the SWS extension is installed), then falls back to
-- platform-native commands.
function UI.open_url(url)
  -- Only allow http(s) / mailto: / tel: URLs. Reject file://, javascript:,
  -- data:, and other schemes that could execute local code or inject
  -- content. mailto: + tel: are safe schemes handled by the OS shell
  -- (mail client / dialer) and are used by the Credits screen's contact
  -- links.
  if not (url:match("^https?://")
       or url:match("^mailto:")
       or url:match("^tel:")) then
    return
  end
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(url)
  else
    -- Sanitise: strip any characters that could enable shell injection.
    -- Excluded: $, (, ), %, `, ", \, ', and non-printable chars.
    -- $() = command substitution on Unix; %VAR% = expansion on Windows;
    -- backtick/backslash/quotes could break quoting boundaries.
    local safe = url:gsub("[^%w%-%.%_%~%:%/%?%#%[%]%@%!%&%*%+%,%;%=%{%}]", "")
    if RA.IS_WINDOWS then
      os.execute('start "" "' .. safe .. '"')
    else
      -- Single quotes disable all shell interpretation (no $(), no \, no `).
      os.execute("open '" .. safe .. "' 2>/dev/null || xdg-open '" .. safe .. "' &")
    end
  end
end

-- =============================================================================
-- Attachment system (base64, file I/O, screenshot, clipboard, attach helpers)
-- =============================================================================
-- Wrapped in do...end to keep internal helpers out of the main-chunk local
-- count (Lua 5.x limit: 200 locals per function/chunk).
Attach = {}
do -- attachment system scope

local b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
Attach.base64_encode = function(data, start_pos, end_pos)
  if not data or #data == 0 then return "" end
  start_pos = start_pos or 1
  end_pos   = end_pos   or #data
  local out = {}
  local i = start_pos
  while i <= end_pos - 2 do
    local a, b, c = str_byte(data, i, i + 2)
    local n = a * 65536 + b * 256 + c
    out[#out+1] = str_sub(b64_chars, math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
    out[#out+1] = str_sub(b64_chars, math_floor(n / 4096) % 64 + 1, math_floor(n / 4096) % 64 + 1)
    out[#out+1] = str_sub(b64_chars, math_floor(n / 64) % 64 + 1, math_floor(n / 64) % 64 + 1)
    out[#out+1] = str_sub(b64_chars, n % 64 + 1, n % 64 + 1)
    i = i + 3
  end
  local remain = end_pos - i + 1
  if remain == 2 then
    local a, b = str_byte(data, i, i + 1)
    local n = a * 65536 + b * 256
    out[#out+1] = str_sub(b64_chars, math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
    out[#out+1] = str_sub(b64_chars, math_floor(n / 4096) % 64 + 1, math_floor(n / 4096) % 64 + 1)
    out[#out+1] = str_sub(b64_chars, math_floor(n / 64) % 64 + 1, math_floor(n / 64) % 64 + 1)
    out[#out+1] = "="
  elseif remain == 1 then
    local a = str_byte(data, i)
    local n = a * 65536
    out[#out+1] = str_sub(b64_chars, math_floor(n / 262144) + 1, math_floor(n / 262144) + 1)
    out[#out+1] = str_sub(b64_chars, math_floor(n / 4096) % 64 + 1, math_floor(n / 4096) % 64 + 1)
    out[#out+1] = "=="
  end
  return tbl_concat(out)
end

-- Chunked base64 encoder for large attachments. Pure Lua base64 over a 10MB
-- file is ~13M operations and freezes the UI thread for hundreds of ms in a
-- single synchronous pass -- catastrophic for low-latency audio. Instead we
-- pre-encode at attach time, processing one ~256KB chunk per main-loop frame
-- via Attach.pump_encoding(). The Send button stays disabled until every
-- binary attachment has finished encoding.
--
-- Chunk size is 3-byte aligned (every base64 group is 3 input bytes -> 4
-- output chars) so each chunk produces padding-free output that can be
-- concatenated directly. The very last chunk may include 1-2 leftover bytes
-- and gets the standard '='/'==' padding from base64_encode.
local B64_CHUNK_BYTES = math_floor(256 * 1024 / 3) * 3  -- ~256KB, 3-aligned

-- Attach.pump_encoding() -- called once per main-loop frame.
-- Encodes one chunk for the first attachment that still needs encoding.
-- Returns true while any work remains, false when all attachments are done.
Attach.pump_encoding = function()
  for _, att in ipairs(S.attachments) do
    if att.kind ~= "text" and not att.b64 then
      if not att.b64_pos then
        att.b64_pos   = 1
        att.b64_parts = {}
      end
      local len       = #att.data
      local remaining = len - att.b64_pos + 1
      local take      = (remaining <= B64_CHUNK_BYTES) and remaining or B64_CHUNK_BYTES
      att.b64_parts[#att.b64_parts+1] = Attach.base64_encode(att.data, att.b64_pos, att.b64_pos + take - 1)
      att.b64_pos = att.b64_pos + take
      if att.b64_pos > len then
        -- Encoding complete: flatten to a single string and free the source
        -- bytes so we don't carry around two copies of a 10MB file in memory.
        att.b64       = tbl_concat(att.b64_parts)
        att.b64_parts = nil
        att.b64_pos   = nil
        att.data      = nil
      end
      return true  -- one chunk per frame is enough
    end
  end
  return false
end

-- Attach.all_encoded() -- true when every binary attachment has finished
-- base64 encoding. Used by the Send button can_send check to block sending
-- until pre-encoding completes.
Attach.all_encoded = function()
  for _, att in ipairs(S.attachments) do
    if att.kind ~= "text" and not att.b64 then return false end
  end
  return true
end

-- Attach.encoding_progress() -> {bytes_done, bytes_total} or nil if no work
-- pending. Used by the attachment strip to draw a progress indicator.
Attach.encoding_progress = function()
  local done, total = 0, 0
  local any_pending = false
  for _, att in ipairs(S.attachments) do
    if att.kind ~= "text" then
      if att.b64 then
        -- Already encoded -- we no longer have att.data, but we tracked the
        -- byte count by counting base64 chars * 3 / 4 (close enough for the
        -- progress display).
        local approx_bytes = math_floor(#att.b64 * 3 / 4)
        done  = done  + approx_bytes
        total = total + approx_bytes
      else
        any_pending = true
        local len = #att.data
        total = total + len
        done  = done  + (att.b64_pos or 1) - 1
      end
    end
  end
  if not any_pending then return nil end
  return done, total
end

-- =============================================================================
-- Attachment utilities
-- =============================================================================
-- Supported image MIME types for the AI provider vision endpoints.
local IMAGE_EXTENSIONS = {
  jpg = "image/jpeg", jpeg = "image/jpeg", png = "image/png",
  gif = "image/gif", webp = "image/webp",
}
-- Text file extensions that are read as UTF-8 text and sent as text blocks.
local TEXT_EXTENSIONS = {
  lua = true, txt = true, csv = true, py = true, js = true, ts = true,
  json = true, xml = true, html = true, css = true, md = true, yaml = true,
  yml = true, ini = true, cfg = true, conf = true, sh = true, bat = true,
  log = true, rpp = true, reascript = true, c = true, cpp = true, h = true,
}

-- get_file_extension(path) -> lowercase extension without dot, or ""
local function get_file_extension(path)
  local ext = path:match("%.([^%.]+)$")
  return ext and ext:lower() or ""
end

-- get_filename(path) -> filename with extension
local function get_filename(path)
  return path:match("[^\\/]+$") or path
end

-- Maximum size (bytes) for text attachments. Files larger than this are
-- rejected to avoid blowing up token budgets and provider context windows.
local TEXT_ATTACH_MAX_BYTES = 200 * 1024  -- 200 KB

-- is_likely_binary(path) -> true if the file appears to be binary.
-- Reads the first 512 bytes and checks for null bytes, which are absent
-- in well-formed UTF-8 / ASCII text but common in binary formats.
local function is_likely_binary(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local head = f:read(512)
  f:close()
  if not head then return false end
  return head:find("\0") ~= nil
end

-- classify_file(path) -> "image", "pdf", "text", or "unsupported" + media_type
-- Only files with a recognised text extension (or that pass a binary sniff
-- test) are treated as text. Unknown extensions default to "unsupported" to
-- prevent binary files from being shoved into the prompt as garbage.
local function classify_file(path)
  local ext = get_file_extension(path)
  if IMAGE_EXTENSIONS[ext] then return "image", IMAGE_EXTENSIONS[ext] end
  if ext == "pdf" then return "pdf", "application/pdf" end
  if TEXT_EXTENSIONS[ext] then return "text", nil end
  -- Unknown extension: attempt a binary sniff. If the file looks like text,
  -- allow it; otherwise reject it as unsupported.
  if ext ~= "" and not is_likely_binary(path) then return "text", nil end
  return "unsupported", nil
end

-- read_file_binary(path) -> data string or nil, error
local function read_file_binary(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

-- read_file_text(path) -> text string or nil, error
local function read_file_text(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local text = f:read("*a")
  f:close()
  return text
end

-- read_image_dimensions(data, media_type) -> width, height or nil, nil
-- Reads pixel dimensions from PNG/JPEG/GIF/WebP file headers without
-- decoding the full image. Returns nil if the format is unrecognized.
local function read_image_dimensions(data, media_type)
  if not data or #data < 24 then return nil, nil end

  -- PNG: bytes 1-8 are signature, IHDR chunk starts at byte 9.
  -- Width at bytes 17-20, height at bytes 21-24 (big-endian uint32).
  if media_type == "image/png" then
    if str_sub(data, 1, 4) == "\137PNG" then
      local w = str_byte(data,17)*16777216 + str_byte(data,18)*65536
             + str_byte(data,19)*256 + str_byte(data,20)
      local h = str_byte(data,21)*16777216 + str_byte(data,22)*65536
             + str_byte(data,23)*256 + str_byte(data,24)
      if w > 0 and h > 0 then return w, h end
    end
  end

  -- JPEG: scan for SOF0/SOF2 marker (0xFF 0xC0 or 0xFF 0xC2).
  -- Height at marker+5 (2 bytes), width at marker+7 (2 bytes), big-endian.
  if media_type == "image/jpeg" then
    local pos = 1
    local len = #data
    while pos < len - 10 do
      if str_byte(data, pos) == 0xFF then
        local marker = str_byte(data, pos + 1)
        if marker == 0xC0 or marker == 0xC2 then
          local h = str_byte(data, pos+5)*256 + str_byte(data, pos+6)
          local w = str_byte(data, pos+7)*256 + str_byte(data, pos+8)
          if w > 0 and h > 0 then return w, h end
        end
        -- Skip to next marker using segment length
        if marker ~= 0x00 and marker ~= 0xFF and marker ~= 0xD8 and marker ~= 0xD9 then
          if pos + 3 <= len then
            local seg_len = str_byte(data, pos+2)*256 + str_byte(data, pos+3)
            -- A valid JPEG segment includes the 2-byte length field
            -- itself; seg_len < 2 is malformed and would either loop
            -- forever (seg_len = 0) or rewind into the marker we just
            -- read. Bail rather than risk the loop on hostile input.
            if seg_len < 2 then break end
            pos = pos + 2 + seg_len
          else
            break
          end
        else
          pos = pos + 1
        end
      else
        pos = pos + 1
      end
    end
  end

  -- GIF: width at bytes 7-8, height at bytes 9-10 (little-endian uint16).
  if media_type == "image/gif" then
    if str_sub(data, 1, 3) == "GIF" then
      local w = str_byte(data,7) + str_byte(data,8)*256
      local h = str_byte(data,9) + str_byte(data,10)*256
      if w > 0 and h > 0 then return w, h end
    end
  end

  -- WebP: "RIFF" at 1-4, "WEBP" at 9-12. VP8 chunk has dimensions.
  if media_type == "image/webp" then
    if str_sub(data, 1, 4) == "RIFF" and str_sub(data, 9, 12) == "WEBP" then
      local chunk = str_sub(data, 13, 16)
      if chunk == "VP8 " and #data >= 30 then
        -- Lossy VP8: width at 27-28, height at 29-30 (little-endian, masked)
        local w = (str_byte(data,27) + str_byte(data,28)*256) % 16384
        local h = (str_byte(data,29) + str_byte(data,30)*256) % 16384
        if w > 0 and h > 0 then return w, h end
      elseif chunk == "VP8L" and #data >= 26 then
        -- Lossless VP8L: packed bits at byte 22-25
        local b1,b2,b3,b4 = str_byte(data,22,25)
        local w = (b1 + (b2 % 64) * 256) + 1
        local h = (math_floor(b2/64) + b3*4 + (b4 % 16)*1024) + 1
        if w > 0 and h > 0 then return w, h end
      end
    end
  end

  return nil, nil
end

-- Estimate token cost for an attachment. Returns estimated tokens (number).
-- Images: based on pixel dimensions (tokens ~ width*height/750).
-- PDFs: ~1500 tokens per page; estimated from file size (~50KB per page).
-- Text: ~4 chars per token.
local function estimate_attachment_tokens(attachment)
  if attachment.kind == "image" then
    -- Try to read actual dimensions from the image header.
    -- Claude resizes images so the longest side is at most 1568px before
    -- calculating tokens. Apply the same scaling here for accuracy.
    local w, h = read_image_dimensions(attachment.data, attachment.media_type)
    if w and h then
      local MAX_SIDE = 1568
      if w > MAX_SIDE or h > MAX_SIDE then
        local scale = MAX_SIDE / math_max(w, h)
        w = math_floor(w * scale)
        h = math_floor(h * scale)
      end
      return math_max(85, math_floor(w * h / 750))
    end
    -- Fallback: rough estimate from file size (conservative 2 bytes/pixel
    -- for PNG screenshots which compress heavily).
    local pixels = #attachment.data / 2
    return math_max(85, math_floor(pixels / 750))
  elseif attachment.kind == "pdf" then
    local pages = math_max(1, math_floor(#attachment.data / 50000))
    return pages * 1500
  elseif attachment.kind == "text" then
    return math_floor(#attachment.data / 4)
  end
  return 0
end

-- Estimate USD cost for attachment tokens given the current model.
local function estimate_attachment_cost(tokens)
  local model = MODELS[prefs.model_idx]
  if not model then return 0 end
  return tokens * model.price_in / 1000000
end

-- Max attachment size (bytes) -- warn above 5MB, reject above 10MB.
-- Claude resizes images internally, so >10MB rarely adds value.
local ATTACH_WARN_BYTES  = 5 * 1024 * 1024
local ATTACH_MAX_BYTES   = 10 * 1024 * 1024
local ATTACH_MAX_COUNT   = 10  -- max attachments per message

-- =============================================================================
-- Screenshot capture
-- =============================================================================
-- Captures the screen to a temporary PNG file for use as an attachment.
-- Windows: uses PowerShell + .NET GDI to capture the REAPER main window
--   region specifically (requires js_ReaScriptAPI for JS_Window_GetRect;
--   falls back to full primary screen if the extension is not installed).
-- macOS: uses the built-in screencapture utility (silent, no shutter sound).
--   This captures all screens, not just the REAPER window -- macOS does not
--   expose a simple per-window capture via shell without extra dependencies.
-- Linux: not currently supported (returns nil).
-- Returns the PNG file path on success, or nil + error string.
local function capture_screenshot()
  local png_path = tmp.screenshot

  if RA.IS_WINDOWS then
    local hwnd = reaper.GetMainHwnd()
    if not hwnd then return nil, "Could not find REAPER main window." end

    local ps_script
    if reaper.JS_Window_GetRect then
      local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
      local w = right - left
      local h = bottom - top
      if w <= 0 or h <= 0 then return nil, "Invalid window dimensions." end
      -- Minimized REAPER on Windows reports rect coords near (-32000,
      -- -32000) -- the standard ShowWindow(SW_MINIMIZE) sentinel. The
      -- positive w/h above passes the previous guard, but CopyFromScreen
      -- from those coordinates produces a uniformly black bitmap that
      -- attaches as a useless screenshot. Treat any far-off-screen
      -- origin as minimized/hidden and refuse the capture so the user
      -- gets a clear error instead of a black image.
      if left < -10000 or top < -10000 then
        return nil, "REAPER window is minimized or off-screen. "
          .. "Restore it before taking a screenshot."
      end
      ps_script = str_format(
        "Add-Type -AssemblyName System.Drawing; "
        .. "$bmp = New-Object System.Drawing.Bitmap(%d, %d); "
        .. "$g = [System.Drawing.Graphics]::FromImage($bmp); "
        .. "$g.CopyFromScreen(%d, %d, 0, 0, $bmp.Size); "
        .. "$g.Dispose(); "
        .. "$bmp.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png); "
        .. "$bmp.Dispose(); "
        .. "Write-Output 'OK'",
        w, h, left, top, png_path:gsub("'", "''"))
    else
      ps_script =
        "Add-Type -AssemblyName System.Drawing; "
        .. "Add-Type -AssemblyName System.Windows.Forms; "
        .. "$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; "
        .. "$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height); "
        .. "$g = [System.Drawing.Graphics]::FromImage($bmp); "
        .. "$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size); "
        .. "$g.Dispose(); "
        .. "$bmp.Save('" .. png_path:gsub("'", "''") .. "', "
        .. "[System.Drawing.Imaging.ImageFormat]::Png); "
        .. "$bmp.Dispose(); "
        .. "Write-Output 'OK'"
    end

    local ps_cmd = 'powershell -NoProfile -WindowStyle Hidden -Command "' .. ps_script .. '"'
    local result = reaper.ExecProcess(ps_cmd, 10000)
    if not result or not result:match("OK") then
      os.remove(png_path)
      return nil, "Screenshot capture failed. PowerShell returned: "
        .. tostring(result and result:sub(1, 200) or "nil")
    end

    local f = io.open(png_path, "rb")
    if f then
      local size = f:seek("end")
      f:close()
      if size and size > 0 then
        return png_path
      end
    end
    os.remove(png_path)
    return nil, "Screenshot produced an empty file."

  elseif RA.IS_MACOS then
    -- screencapture -x: silent (no shutter sound). Captures all screens.
    local sq_path = "'" .. png_path:gsub("'", "'\\''") .. "'"
    os.execute("screencapture -x " .. sq_path)
    local f = io.open(png_path, "rb")
    if f then
      local size = f:seek("end")
      f:close()
      if size and size > 0 then return png_path end
    end
    os.remove(png_path)
    return nil, "Screenshot capture failed."
  end

  return nil, "Screenshot capture is not supported on Linux."
end

-- =============================================================================
-- Clipboard image paste
-- =============================================================================
-- Checks if the clipboard contains an image and returns it as a PNG file path.
-- Windows: uses PowerShell with .NET to read the clipboard.
-- macOS: uses osascript to read clipboard image data and write it as PNG.
local function get_clipboard_image()
  local png_path = tmp.clipboard

  if RA.IS_WINDOWS then
    local ps_cmd = 'powershell -NoProfile -WindowStyle Hidden -Command "'
      .. "Add-Type -AssemblyName System.Windows.Forms; "
      .. "Add-Type -AssemblyName System.Drawing; "
      .. "$img = [System.Windows.Forms.Clipboard]::GetImage(); "
      .. "if ($img -ne $null) { "
      .. "$img.Save('" .. png_path:gsub("'", "''") .. "', "
      .. "[System.Drawing.Imaging.ImageFormat]::Png); "
      .. "Write-Output 'OK' "
      .. '} else { Write-Output \'EMPTY\' }"'

    local result = reaper.ExecProcess(ps_cmd, 5000)
    if result and result:match("OK") then
      local f = io.open(png_path, "rb")
      if f then
        local size = f:seek("end")
        f:close()
        if size and size > 0 then return png_path end
      end
    end
    os.remove(png_path)
    return nil

  elseif RA.IS_MACOS then
    -- Use osascript to grab clipboard image data as PNG and write to file.
    local sq_path = png_path:gsub("'", "'\\''")
    local cmd = "osascript -e '"
      .. 'try\n'
      .. '  set imgData to the clipboard as «class PNGf»\n'
      .. '  set fp to open for access POSIX file "' .. sq_path .. '" with write permission\n'
      .. '  set eof fp to 0\n'
      .. '  write imgData to fp\n'
      .. '  close access fp\n'
      .. '  return "OK"\n'
      .. 'on error\n'
      .. '  return "EMPTY"\n'
      .. "end try'"
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result:match("OK") then
        local f = io.open(png_path, "rb")
        if f then
          local size = f:seek("end")
          f:close()
          if size and size > 0 then return png_path end
        end
      end
    end
    os.remove(png_path)
    return nil
  end

  return nil
end

-- Attach.file(path) -> true on success, false + sets S.attach_error on failure.
-- Reads the file, classifies it, estimates cost, and adds to the queue.
Attach.file = function(path)
  if #S.attachments >= ATTACH_MAX_COUNT then
    S.attach_error = str_format("Maximum %d attachments per message.", ATTACH_MAX_COUNT)
    S.attach_error_time = time_precise()
    return false
  end

  local kind, media_type = classify_file(path)

  if kind == "unsupported" then
    local ext = get_file_extension(path)
    S.attach_error = str_format(
      "Unsupported file type%s. Supported: images, PDFs, and common text formats.",
      ext ~= "" and (" (." .. ext .. ")") or "")
    S.attach_error_time = time_precise()
    return false
  end

  local data, err
  if kind == "text" then
    data, err = read_file_text(path)
  else
    data, err = read_file_binary(path)
  end

  if not data then
    S.attach_error = "Could not read file: " .. tostring(err)
    S.attach_error_time = time_precise()
    return false
  end

  -- Text-specific size cap: prevents token budget blow-ups from large logs,
  -- data files, etc. Binary attachments (images, PDFs) use the general cap.
  if kind == "text" and #data > TEXT_ATTACH_MAX_BYTES then
    S.attach_error = str_format("Text file too large (%.0f KB, max %d KB).",
      #data / 1024, TEXT_ATTACH_MAX_BYTES / 1024)
    S.attach_error_time = time_precise()
    return false
  end

  if #data > ATTACH_MAX_BYTES then
    S.attach_error = str_format("File too large (%.1f MB, max %d MB).",
      #data / 1048576, ATTACH_MAX_BYTES / 1048576)
    S.attach_error_time = time_precise()
    return false
  end

  if #data == 0 then
    S.attach_error = "File is empty."
    S.attach_error_time = time_precise()
    return false
  end

  local entry = {
    kind       = kind,
    name       = get_filename(path),
    data       = data,
    media_type = media_type,
    path       = path,
  }
  entry.tokens = estimate_attachment_tokens(entry)
  entry.cost   = estimate_attachment_cost(entry.tokens)

  S.attachments[#S.attachments+1] = entry

  if #data > ATTACH_WARN_BYTES then
    S.attach_error = str_format("Large file (%.1f MB), estimated cost: %s",
      #data / 1048576, MODELS.format_cost(entry.cost))
    S.attach_error_time = time_precise()
  end

  return true
end

-- Attach.screenshot() -> true on success, false on failure (sets S.attach_error)
Attach.screenshot = function()
  if #S.attachments >= ATTACH_MAX_COUNT then
    S.attach_error = str_format("Maximum %d attachments per message.", ATTACH_MAX_COUNT)
    S.attach_error_time = time_precise()
    return false
  end

  local png_path, err = capture_screenshot()
  if not png_path then
    S.attach_error = err or "Screenshot failed."
    S.attach_error_time = time_precise()
    return false
  end

  local data = read_file_binary(png_path)
  os.remove(png_path)  -- clean up temp file

  if not data or #data == 0 then
    S.attach_error = "Screenshot produced an empty file."
    S.attach_error_time = time_precise()
    return false
  end

  if #data > ATTACH_MAX_BYTES then
    S.attach_error = str_format("Screenshot too large (%.1f MB, max %d MB).",
      #data / 1048576, ATTACH_MAX_BYTES / 1048576)
    S.attach_error_time = time_precise()
    return false
  end

  local entry = {
    kind       = "image",
    name       = "Screenshot",
    data       = data,
    media_type = "image/png",
    path       = nil,
  }
  entry.tokens = estimate_attachment_tokens(entry)
  entry.cost   = estimate_attachment_cost(entry.tokens)

  S.attachments[#S.attachments+1] = entry
  return true
end

-- Attach.clipboard() -> true if an image was found and attached, false otherwise
Attach.clipboard = function()
  if #S.attachments >= ATTACH_MAX_COUNT then
    S.attach_error = str_format("Maximum %d attachments per message.", ATTACH_MAX_COUNT)
    S.attach_error_time = time_precise()
    return false
  end

  local png_path = get_clipboard_image()
  if not png_path then
    S.attach_error = "No image found in clipboard."
    S.attach_error_time = time_precise()
    return false
  end

  local data = read_file_binary(png_path)
  os.remove(png_path)  -- clean up temp file

  if not data or #data == 0 then
    S.attach_error = "Clipboard image is empty."
    S.attach_error_time = time_precise()
    return false
  end

  if #data > ATTACH_MAX_BYTES then
    S.attach_error = str_format("Clipboard image too large (%.1f MB, max %d MB).",
      #data / 1048576, ATTACH_MAX_BYTES / 1048576)
    S.attach_error_time = time_precise()
    return false
  end

  local entry = {
    kind       = "image",
    name       = "Clipboard image",
    data       = data,
    media_type = "image/png",
    path       = nil,
  }
  entry.tokens = estimate_attachment_tokens(entry)
  entry.cost   = estimate_attachment_cost(entry.tokens)

  S.attachments[#S.attachments+1] = entry
  return true
end

end -- attachment system scope

-- =============================================================================
-- System prompt
-- =============================================================================
-- Loaded from ReaAssist_System_Prompt.md at startup. {VERSION} is replaced
-- with CFG.VERSION.
--
-- Power-user override: if ReaAssist_System_Prompt_Custom.md exists in the
-- same Resources/ folder, it is loaded INSTEAD of the stock prompt. The
-- custom file is not in the update manifest, so it survives updates and
-- is never touched by repair. The stock file may still change across
-- updates; advance_after_rename detects that and queues a one-time toast
-- on next launch reminding the user to review the new stock prompt.
local SYSTEM_PROMPT
local SYSTEM_PROMPT_IS_CUSTOM = false
-- Loads the system prompt at the kick-off block (after the bootstrap
-- critical-files check has run) so a missing or token-gutted stock prompt
-- can route into bootstrap recovery instead of returning from the main
-- chunk before recovery has a chance to render. Returns true on success;
-- on failure either sets S.bootstrap_active (stock missing/corrupt, repair
-- can fix it) or shows a message box (custom override is the user's file
-- and bootstrap cannot restore it).
local function load_system_prompt()
  local stock_path  = RA.RESOURCES_DIR .. "ReaAssist_System_Prompt.md"
  local custom_path = RA.RESOURCES_DIR .. "ReaAssist_System_Prompt_Custom.md"
  local prompt_path = stock_path
  if reaper.file_exists(custom_path) then
    prompt_path = custom_path
    SYSTEM_PROMPT_IS_CUSTOM = true
  end
  local f = io.open(prompt_path, "r")
  if not f then
    if SYSTEM_PROMPT_IS_CUSTOM then
      reaper.ShowMessageBox(
        "Could not load system prompt file:\n" .. prompt_path
        .. "\n\nPlease make sure ReaAssist_System_Prompt.md is in the "
        .. "Resources/ subfolder next to ReaAssist.lua.",
        "ReaAssist", 0)
      return false
    end
    S.bootstrap_active = true
    S.bootstrap_missing[#S.bootstrap_missing + 1] =
      "Resources/ReaAssist_System_Prompt.md"
    Updater._set_failure("system_prompt_load",
      "System prompt file is missing.")
    return false
  end
  local raw = f:read("*a"); f:close()
  -- Strip the HTML comment header (<!-- ... -->) lines so they don't leak
  -- into the prompt sent to the API.
  raw = raw:gsub("<!%-%-.-%-%->\n?", "")
  SYSTEM_PROMPT = raw:gsub("{VERSION}", CFG.VERSION)
  -- Tamper guard for the SHIPPED prompt only: if the stock file has been
  -- gutted, partially truncated, or replaced with junk, route into bootstrap
  -- recovery so repair can restore it. Custom overrides bypass this check;
  -- power users may legitimately rewrite the branding in their own copy.
  --
  -- We require multiple structural anchors (not just the product token) so
  -- a partial corruption that still contains "ReaAssist" somewhere in the
  -- file passes through and produces one bad chat session before the SHA
  -- repair check catches it on the next launch. The anchors below are the
  -- prompt's load-bearing section headers; if any one is missing, the file
  -- is structurally broken and unsafe to feed to a model.
  if not SYSTEM_PROMPT_IS_CUSTOM then
    local required_anchors = {
      CFG._PRODUCT,
      "CORE BEHAVIOR:",
      "CONTEXT BUCKETS",
      "API REF REQUIREMENT",
      "PROMPT BUNDLES",
    }
    for _, anchor in ipairs(required_anchors) do
      if not SYSTEM_PROMPT:find(anchor, 1, true) then
        S.bootstrap_active = true
        S.bootstrap_missing[#S.bootstrap_missing + 1] =
          "Resources/ReaAssist_System_Prompt.md (corrupt)"
        Updater._set_failure("system_prompt_load",
          "System prompt file is corrupted (missing anchor: "
          .. anchor .. ").")
        return false
      end
    end
  end
  -- Log custom-prompt usage so support can rule it in/out when triaging
  -- "weird model output" reports. No-op if debug logging is disabled.
  if SYSTEM_PROMPT_IS_CUSTOM then
    Log.line("PROMPT",
      "Using ReaAssist_System_Prompt_Custom.md (override active)")
  end
  return true
end

-- CTX is a plain global (cross-file shared state; its `= {}` initializer
-- runs later in this file). Code.auto_save_jsfx invalidates the installed-FX
-- cache after saving a new plugin by touching CTX, which is harmless before
-- the initializer because the touch happens inside a function body, not at
-- load time.

Code = {}

-- Forward declaration so Code.ensure_preferred_from_chains (defined further
-- down) can call _is_fabfilter_ident, which is itself defined later in the
-- file alongside FABFILTER_DEV_STEMS. Without this forward decl, Lua's
-- parser treats the call site as a global lookup and the call resolves to
-- nil at runtime. Assignment happens via the (de-localised) `function
-- _is_fabfilter_ident(ident)` at the original definition site below; that
-- form looks up the existing local in scope and re-binds it instead of
-- shadowing it with a fresh local.
local _is_fabfilter_ident

-- =============================================================================
-- Utility: Code.safe_write
-- =============================================================================
-- Writes content to a file path with crash- and failure-safe semantics:
--   1. Write to <path>.tmp, checking both f:write and f:close for nil+err
--      returns (not just thrown errors -- short writes/disk full/permission
--      failures come back that way in Lua, not as exceptions).
--   2. Rename any existing <path> to <path>.bak so the original is preserved.
--   3. Rename <path>.tmp -> <path>. If that fails, restore from .bak.
--   4. On success, remove .bak.
-- The original file is never destroyed unless the replacement is in place.
-- Returns true on success, shows a message box and returns false on failure.
function Code.safe_write(path, content)
  local tmp_path = path .. ".tmp"
  local bak_path = path .. ".bak"
  local f, err = io.open(tmp_path, "wb")
  if not f then
    reaper.ShowMessageBox(
      "Could not write file:\n" .. tmp_path .. "\n\n" .. tostring(err),
      "ReaAssist - File Error", 0)
    return false
  end
  local w_ok, w_err = pcall(function()
    local ok, perr = f:write(content)
    if not ok then error(perr or "write returned nil", 0) end
  end)
  local c_ok, c_err = pcall(function()
    local ok, perr = f:close()
    if not ok then error(perr or "close returned nil", 0) end
  end)
  if not w_ok or not c_ok then
    os.remove(tmp_path)
    reaper.ShowMessageBox(
      "Failed writing temp file:\n" .. tmp_path .. "\n\n" .. tostring(w_err or c_err),
      "ReaAssist - File Error", 0)
    return false
  end
  -- Preserve the original until the new file is definitely in place. Windows
  -- os.rename fails when the destination exists, so move the original out of
  -- the way first. os.rename returns nil when the source does not exist (a
  -- fresh write); had_original tracks that so restoration is only attempted
  -- when there was actually something to restore.
  os.remove(bak_path)
  local had_original = os.rename(path, bak_path)
  local ok_r, ren_err = os.rename(tmp_path, path)
  if not ok_r then
    if had_original then os.rename(bak_path, path) end
    os.remove(tmp_path)
    reaper.ShowMessageBox(
      "Could not finalize file:\n" .. path .. "\n\n" .. tostring(ren_err),
      "ReaAssist - File Error", 0)
    return false
  end
  os.remove(bak_path)
  return true
end

-- =============================================================================
-- Utility: Code.derive_filename
-- =============================================================================
-- Suggests a .lua filename from code content without an API call.
-- Strategy (in priority order):
--   1. First line if it is a comment: "-- My Script" -> "My Script.lua"
--   2. Undo_EndBlock label: "ReaAssist: Create 20 tracks" -> "Create 20 tracks.lua"
--   3. First function name: "local function do_thing()" -> "do_thing.lua"
--   4. Fallback: "reaassist_script.lua"
-- Result is safe for all OSes: filesystem-unsafe chars stripped,
-- spaces preserved, length capped at 60 chars.
-- Windows reserved device names. Any filename whose stem (case-insensitive,
-- ignoring extension) matches one of these is rejected by Win32 even on NTFS,
-- so we can't write "CON.lua" or "AUX.jsfx". Suffix with "_" to dodge.
local WIN_RESERVED_NAMES = {
  CON=true, PRN=true, AUX=true, NUL=true,
  COM1=true, COM2=true, COM3=true, COM4=true, COM5=true,
  COM6=true, COM7=true, COM8=true, COM9=true,
  LPT1=true, LPT2=true, LPT3=true, LPT4=true, LPT5=true,
  LPT6=true, LPT7=true, LPT8=true, LPT9=true,
}
-- Shared filename sanitizer: strip filesystem-unsafe chars, collapse whitespace,
-- cap at 60 chars. Returns cleaned string (caller appends extension).
local function sanitize_filename(s, fallback)
  s = s:gsub('[<>:"/\\|%?%*]', ""):gsub("%s+", " "):gsub("^ +", ""):gsub(" +$", "")
  -- Strip trailing dots/spaces (Windows truncates them silently, breaking
  -- subsequent open-by-name lookups).
  s = s:gsub("[%. ]+$", "")
  if #s > 60 then s = s:sub(1, 60):gsub("[%. ]+$", "") end
  if s == "" then s = fallback end
  -- Reject Windows reserved device names. Match the stem before any extension
  -- the caller will append, so "CON" alone is enough to trigger.
  if WIN_RESERVED_NAMES[s:upper()] then s = s .. "_" end
  return s
end

function Code.derive_filename(code)
  -- 1. First line comment.
  local first_line = code:match("^%-%-+%s*(.-)%s*[\r\n]")
  if first_line and first_line ~= "" and not first_line:match("^!") then
    return sanitize_filename(first_line, "reaassist_script") .. ".lua"
  end

  -- 2. Undo_EndBlock label: e.g. Undo_EndBlock("ReaAssist: Create 20 tracks", -1)
  --    Strip a leading "ReaAssist: " prefix if present so the filename is clean.
  local undo_label = code:match("Undo_EndBlock%s*%(%s*\"(.-)\"%s*,")
                  or code:match("Undo_EndBlock%s*%(%s*'(.-)'%s*,")
  if undo_label and undo_label ~= "" then
    undo_label = undo_label:gsub("^ReaAssist:%s*", "")
    return sanitize_filename(undo_label, "reaassist_script") .. ".lua"
  end

  -- 3. First function name (covers local function and bare function forms).
  local fn_name = code:match("local%s+function%s+([%w_]+)%s*%(")
               or code:match("^function%s+([%w_]+)%s*%(")
  if fn_name then return sanitize_filename(fn_name, "reaassist_script") .. ".lua" end

  -- 4. Fallback.
  return "reaassist_script.lua"
end

-- =============================================================================
-- Utility: Code.derive_filename_jsfx
-- =============================================================================
-- Suggests a filename from JSFX code content.
-- Uses the desc: line if present, otherwise falls back to a generic name.
function Code.derive_filename_jsfx(code)
  local desc = code:match("^%s*desc:%s*(.-)%s*[\r\n]")
  if desc and desc ~= "" then return sanitize_filename(desc, "reaassist_effect") .. ".jsfx" end
  return "reaassist_effect.jsfx"
end

-- =============================================================================
-- Utility: Code.auto_save_jsfx
-- =============================================================================
-- Silently saves JSFX code to Effects/ReaAssist/<derived_name>.jsfx.
-- Returns the saved path on success, nil on failure.
function Code.auto_save_jsfx(code)
  local base_name = Code.derive_filename_jsfx(code)
  local name = base_name
  local stem = base_name:match("^(.+)%.jsfx$") or base_name
  local dest = JSFX_DIR .. RA.SEP .. name
  -- Check existing files: if one has identical content, return it (no duplicate).
  -- If content differs, skip past it and try the next numeric suffix.
  local n = 1
  local f = io.open(dest, "r")
  while f do
    local existing = f:read("*a")
    f:close()
    if existing == code then
      -- Exact same content already on disk -- reuse it.
      return dest, "ReaAssist/" .. name
    end
    n = n + 1
    name = stem .. "_" .. n .. ".jsfx"
    dest = JSFX_DIR .. RA.SEP .. name
    f = io.open(dest, "r")
  end
  local ok = Code.safe_write(dest, code)
  if ok then
    -- Refresh JSFX list so TrackFX_AddByName can find it immediately.
    if reaper.EnumInstalledFX then
      reaper.EnumInstalledFX(-1)
    end
    -- Invalidate our cached installed-FX list so a follow-up
    -- <context_needed>fx_list:...</context_needed> for the newly saved
    -- plugin actually sees it instead of reporting "not installed".
    CTX._installed_fx_list = nil
    return dest, "ReaAssist/" .. name
  end
  return nil
end

-- =============================================================================
-- ReEQ bundled-install support
-- =============================================================================
-- ReEQ (by Justin Johnson, MIT) is bundled with ReaAssist and installed on
-- demand at the standard ReaPack location so sessions remain portable: anyone
-- with ReEQ from ReaPack will resolve the same `ReJJ/ReEQ/ReEQ.jsfx` path.
--
-- The bundled source lives in <script>/Resources/ReEQ/ and contains:
--   ReEQ.jsfx, LICENSE.txt, Dependencies/{firhalfband,spectrum,svf_filter}.jsfx-inc
-- LICENSE keeps a .txt extension because gen_manifest.py only ships files
-- on a safe-extension whitelist (no-extension files are excluded). The
-- .txt suffix lets the file flow through both ReaPack's index.xml source
-- list and the internal updater's manifest.
--
-- After install we call EnumInstalledFX(-1) so TrackFX_AddByName finds the
-- new JSFX immediately (the FX Browser does not visually refresh until REAPER
-- restarts, but plugin lookup by path works right away).

local REEQ_SRC_DIR  = RA.RESOURCES_DIR .. "ReEQ"
local REEQ_DEST_DIR = reaper.GetResourcePath() .. RA.SEP .. "Effects" .. RA.SEP .. "ReJJ" .. RA.SEP .. "ReEQ"
local REEQ_DEPS     = { "firhalfband.jsfx-inc", "spectrum.jsfx-inc", "svf_filter.jsfx-inc" }

-- Returns true iff the canonical ReEQ.jsfx file is present at the ReaPack path.
function Code.is_reeq_installed()
  local f = io.open(REEQ_DEST_DIR .. RA.SEP .. "ReEQ.jsfx", "r")
  if f then f:close(); return true end
  return false
end

-- Internal: copies a single file if the destination doesn't already exist.
-- Returns true on success (including "already present" no-op), false + err on failure.
local function reeq_copy_file(src, dest)
  local existing = io.open(dest, "r")
  if existing then existing:close(); return true end  -- idempotent: don't overwrite
  local sf, err = io.open(src, "rb")
  if not sf then return false, "Cannot read " .. src .. ": " .. tostring(err) end
  local data = sf:read("*a"); sf:close()
  local df, derr = io.open(dest, "wb")
  if not df then return false, "Cannot write " .. dest .. ": " .. tostring(derr) end
  -- Check write/close return values. A short write (disk full mid-copy)
  -- or a close failure (filesystem flush error) used to leave a corrupt
  -- destination but return true; Code.is_reeq_installed() then sees the
  -- file exists and short-circuits any reinstall, so the user is stuck
  -- with a broken JSFX until they manually delete it. Remove the partial
  -- file on failure so a reinstall can recover.
  local wok, werr = df:write(data)
  local cok, cerr = df:close()
  if not wok or not cok then
    os.remove(dest)
    return false, "Write failed for " .. dest .. ": "
      .. tostring(werr or cerr or "unknown")
  end
  return true
end

-- Installs the bundled ReEQ to {resource_path}/Effects/ReJJ/ReEQ/.
-- Idempotent: skips files that already exist at the destination.
-- Returns (true, nil) on success or (false, error_message) on failure.
function Code.install_reeq()
  -- Sanity check that the bundled source is present.
  local probe = io.open(REEQ_SRC_DIR .. RA.SEP .. "ReEQ.jsfx", "r")
  if not probe then
    return false, "Bundled ReEQ source not found at " .. REEQ_SRC_DIR
  end
  probe:close()

  -- Create destination tree.
  reaper.RecursiveCreateDirectory(REEQ_DEST_DIR .. RA.SEP .. "Dependencies", 0)

  -- Copy main JSFX + LICENSE.txt.
  local ok, err = reeq_copy_file(REEQ_SRC_DIR .. RA.SEP .. "ReEQ.jsfx",
                                 REEQ_DEST_DIR .. RA.SEP .. "ReEQ.jsfx")
  if not ok then return false, err end
  ok, err = reeq_copy_file(REEQ_SRC_DIR .. RA.SEP .. "LICENSE.txt",
                           REEQ_DEST_DIR .. RA.SEP .. "LICENSE.txt")
  if not ok then return false, err end

  -- Copy dependencies.
  for _, dep in ipairs(REEQ_DEPS) do
    ok, err = reeq_copy_file(REEQ_SRC_DIR  .. RA.SEP .. "Dependencies" .. RA.SEP .. dep,
                             REEQ_DEST_DIR .. RA.SEP .. "Dependencies" .. RA.SEP .. dep)
    if not ok then return false, err end
  end

  -- Force REAPER to rescan installed FX so AddByName finds ReEQ immediately.
  -- Same trick used by Code.auto_save_jsfx; the FX Browser doesn't visually
  -- refresh, but lookup-by-path works right away.
  if reaper.EnumInstalledFX then reaper.EnumInstalledFX(-1) end
  CTX._installed_fx_list = nil

  -- Re-run fallback chains now that ReEQ is on disk. Fills pref_types.eq
  -- with the first chain candidate that's installed (ReEQ if the user has
  -- no FabFilter EQ) so the Preferred Plugins page reflects it and preempt
  -- injection fires for "eq" keywords from now on. No-op if the user
  -- already has an EQ preference set.
  Code.ensure_preferred_from_chains()

  return true, nil
end

-- =============================================================================
-- Fallback chains: auto-assign preferred plugins from Plugin_Ref.md
-- =============================================================================
-- PLUGIN AUTO-ASSIGN / POPUP FLOW
-- -------------------------------
-- Single source of truth: the ```chains block in Resources/ReaAssist_Plugin_Ref.md.
-- Line format:
--   type: chain1 | chain2 | ... || stock-fallback [optional alias]
--
-- AUTO-ASSIGN CHAIN (left of `||`):
--   Walked at startup by Code.ensure_preferred_from_chains (and again after
--   install_reeq invalidates the FX list cache). First installed entry wins
--   and is written to pref_types[type]. Appears on the Preferred Plugins
--   page. Only high-quality third-party picks belong here -- they commit
--   users silently. Stock REAPER plugins are NEVER in chains.
--
-- STOCK FALLBACK (right of `||`):
--   Offered by the resolve popup as a one-click "Use <name> instead" button
--   when no chain entry is installed and the model emits resolve:<type>.
--   Used for THIS TURN ONLY -- never saved to pref_types, never shown on
--   the Preferred Plugins page. The popup fires again next time the type
--   comes up. Users who want a stock plugin permanent must type it into the
--   Preferred Plugins page themselves.
--
-- DISPLAY ALIAS (in brackets after any entry):
--   Optional. Overrides the button label for stock fallbacks. Example:
--     JS: Liteon/deesser [JSFX De-esser]
--   Shows as "Use JSFX De-esser instead" on the popup button.
--
-- LINE FORMAT EXAMPLES:
--   eq: Pro-Q 4 | ReJJ/ReEQ/ReEQ.jsfx || ReaEQ      -- 2-entry chain + stock
--   chorus:  || JS: SStillwell/chorus_stereo [JSFX Chorus]
--                                                    -- stock-only type
--   custom_thing: MyPlugin                           -- chain-only (rare)
--
-- TO ADD A NEW AUTO-ASSIGN CANDIDATE: add to the matching chain line in
-- Plugin_Ref.md. Entries are format-agnostic (just the plugin name); the
-- resolver tries VST3 > VSTi > VST > AU > CLAP. JSFX entries use the full
-- relative path (e.g. ReJJ/ReEQ/ReEQ.jsfx, or JS: vendor/file for stock).
--
-- TO ADD A NEW PLUGIN TYPE: add to PREF_PLUGIN_DEFAULTS, PREF_PLUGIN_ALIASES,
-- VALID_RESOLVE_TYPES, and add a chain line in Plugin_Ref.md. The popup
-- picks up the stock fallback automatically via Code.get_stock_fallback.
-- See Dev/Plugin Scanner Script/README.md for the full integration recipe.
-- -----------------------------------------------------------------------------

-- Reads the ```chains code block from Resources/ReaAssist_Plugin_Ref.md.
-- Line format:
--   type: chain1 | chain2 | ... || stock-fallback
-- Any entry (chain or stock) may have an optional display alias in brackets:
--   JS: Liteon/deesser [JSFX De-esser]
-- Types with no auto-chain are written as:
--   type: || stock-fallback
--
-- Returns { type_key = { chain = {name1, ...}, stock = {add=..., alias=...} } }.
-- Parsed once per session; the file is authoritative.
local _fallback_chains

-- Parse a single entry string like "Pro-Q 4" or "JS: Liteon/deesser [JSFX De-esser]"
-- into { name = "...", alias = "..." or nil }.
local function _parse_chain_entry(s)
  s = s:match("^%s*(.-)%s*$") or ""
  if s == "" then return nil end
  local name, alias = s:match("^(.-)%s*%[(.-)%]%s*$")
  if name and alias and name ~= "" then
    return { name = name:match("^%s*(.-)%s*$"),
             alias = alias:match("^%s*(.-)%s*$") }
  end
  return { name = s, alias = nil }
end

function Code.get_fallback_chains()
  if _fallback_chains then return _fallback_chains end
  _fallback_chains = {}
  local ref_path = RA.RESOURCES_DIR .. "ReaAssist_Plugin_Ref.md"
  local f = io.open(ref_path, "r")
  if not f then
    Log.line("CHAIN", "Plugin_Ref.md not found; no fallback chains loaded")
    return _fallback_chains
  end
  local content = f:read("*a")
  f:close()
  local block = content:match("```chains%s*\n(.-)\n```")
  if not block then
    Log.line("CHAIN", "no ```chains block found in Plugin_Ref.md")
    return _fallback_chains
  end
  local loaded = {}
  for line in block:gmatch("[^\n]+") do
    -- Skip comment lines and blank lines.
    local stripped = line:match("^%s*(.-)%s*$") or ""
    if stripped ~= "" and stripped:sub(1, 1) ~= "#" then
      local type_key, rest = line:match("^%s*([%w_]+)%s*:%s*(.*)$")
      if type_key and rest then
        -- Split on "||" to separate auto-chain from stock fallback.
        local chain_str, stock_str = rest:match("^(.-)%s*||%s*(.+)$")
        if not chain_str then
          -- No "||" found -- treat whole line as chain (no stock fallback).
          chain_str, stock_str = rest, nil
        end
        local chain_entries = {}
        for entry in chain_str:gmatch("[^|]+") do
          local parsed = _parse_chain_entry(entry)
          if parsed then chain_entries[#chain_entries+1] = parsed.name end
        end
        local stock = nil
        if stock_str then
          local parsed_stock = _parse_chain_entry(stock_str)
          if parsed_stock then
            stock = { add = parsed_stock.name, alias = parsed_stock.alias }
          end
        end
        if #chain_entries > 0 or stock then
          _fallback_chains[type_key] = {
            chain = chain_entries,
            stock = stock,
          }
          loaded[#loaded+1] = type_key
        end
      end
    end
  end
  Log.line("CHAIN", "loaded chains for types: " .. tbl_concat(loaded, ", "))
  return _fallback_chains
end

-- Code.get_stock_fallback is defined near Code.is_curated_plugin (same file,
-- after PLUGIN_REF_ALIASES declaration) because it reads that alias map to
-- derive the curated section key from the stock AddByName string.

-- Format preference for format-agnostic chain entries. Plugins installed in
-- multiple formats are resolved in this order so VST3 wins over CLAP, etc.
local CHAIN_FORMAT_PREFIXES = {
  "VST3:", "VST3i:", "VSTi:", "VST:", "AU:", "AUi:", "CLAP:", "CLAPi:",
}

-- Test whether a chain entry (plugin name or JSFX path) is installed on the
-- system by searching the enumerated FX list. Returns the full enumerated
-- name on match, or nil. JSFX paths match exactly; plugin names use a
-- case-insensitive substring match plus format-prefix preference.
function Code.resolve_chain_entry(entry, installed_list)
  -- Bundled-ReEQ fallback: check the filesystem regardless of what
  -- installed_list contains. EnumInstalledFX on macOS has been observed
  -- to omit our installed ReEQ.jsfx even after a REAPER restart while
  -- the file is unambiguously present at the canonical install path.
  -- Same coverage gap that the resolve handler already works around
  -- via Code.is_reeq_installed (mid-session filesystem check); we
  -- apply it to the chain walk too so the auto-pref slot populates
  -- without requiring a chat round-trip. Runs before the empty-list
  -- guard so it works even on a fresh launch where EnumInstalledFX
  -- hasn't returned any rows yet.
  if entry == "ReJJ/ReEQ/ReEQ.jsfx" and Code.is_reeq_installed() then
    return entry
  end
  if not installed_list or #installed_list == 0 then return nil end
  if entry:find("/", 1, true) then
    for _, inst in ipairs(installed_list) do
      if inst == entry or inst == "JS: " .. entry then return inst end
    end
    return nil
  end
  local entry_lower = entry:lower()
  local best, best_rank = nil, math.huge
  for _, inst in ipairs(installed_list) do
    if inst:lower():find(entry_lower, 1, true) then
      local rank = math.huge
      for i, p in ipairs(CHAIN_FORMAT_PREFIXES) do
        if inst:sub(1, #p) == p then rank = i; break end
      end
      if rank < best_rank then best, best_rank = inst, rank end
    end
  end
  return best
end

-- Walk every fallback chain and auto-assign pref_types[type] to the first
-- installed entry, ONLY when no existing preference is set. Never overwrites
-- user choices. Called at script load and after installing bundled plugins.
-- Idempotent; returns count of types newly assigned this call.
function Code.ensure_preferred_from_chains()
  local chains = Code.get_fallback_chains()
  if not next(chains) then return 0 end
  CTX.populate_installed_fx()
  local installed = CTX._installed_fx_list or {}
  local cache = FXCache.load()
  cache.preferred_types = cache.preferred_types or {}
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
  -- Dev-only HideFabFilter override: when the flag is on AND the cached
  -- pref for a type is a FabFilter ident (Pro-Q 4 / Pro-C 3 / ...), treat
  -- the cached value as empty so the chain walk falls through to the next
  -- resolvable alternative (ReEQ for eq, etc.). This makes "Hide FabFilter"
  -- actually simulate a no-FabFilter install instead of just hiding the
  -- value at display time. The override is SESSION-ONLY: ephemeral_originals
  -- captures the pre-override values so we can restore them before
  -- persisting to disk -- toggling HideFabFilter back off must restore the
  -- user's real preferred plugin (e.g. Pro-Q 4) cleanly.
  local ephemeral_originals = {}
  local assigned = 0
  local sorted_types = {}
  for k in pairs(chains) do sorted_types[#sorted_types+1] = k end
  table.sort(sorted_types)
  for _, type_key in ipairs(sorted_types) do
    local original = cache.preferred_types[type_key]
    local existing = original
    local overridden = false
    if hide_ff and existing and existing ~= ""
        and _is_fabfilter_ident(existing) then
      existing = ""
      overridden = true
    end
    if not existing or existing == "" then
      local chain_list = chains[type_key].chain or {}
      for _, entry in ipairs(chain_list) do
        if Code.resolve_chain_entry(entry, installed) then
          cache.preferred_types[type_key] = entry
          Log.line("PREF", str_format(
            "auto-assigned preferred_types.%s = %s%s",
            type_key, entry,
            overridden and " (ephemeral; hide_fabfilter override of "
              .. tostring(original) .. ")" or " (from chain)"))
          assigned = assigned + 1
          if overridden then ephemeral_originals[type_key] = original end
          break
        end
      end
    end
  end
  if assigned > 0 then
    if next(ephemeral_originals) then
      -- Snapshot-and-restore: write the rolled-back values to disk, then
      -- re-apply the in-memory overrides so the rest of the session keeps
      -- using the simulated alternatives. Both `cache` and the table held
      -- in FXCache._fx_cache_mem are the same Lua table, so restoring
      -- `cache.preferred_types[k]` also updates the module-level cache
      -- that FXCache.load returns to other callers.
      --
      -- Save is wrapped in pcall and the in-memory restore runs
      -- unconditionally: if FXCache.save errors mid-write (disk full /
      -- permission failure surfaces a message-box from Code.safe_write),
      -- we still want the session to keep simulating "no FabFilter".
      -- Without unconditional restore, an error here would leave
      -- cache.preferred_types[k] at the original FabFilter ident (the
      -- value we just swapped in for the save), silently breaking the
      -- HideFabFilter override until the next ReaAssist relaunch.
      local in_memory_values = {}
      for k in pairs(ephemeral_originals) do
        in_memory_values[k] = cache.preferred_types[k]
      end
      for k, original_v in pairs(ephemeral_originals) do
        cache.preferred_types[k] = original_v
      end
      -- FXCache.save returns nil on success or an error STRING on failure
      -- (it does not raise). pcall therefore returns (true, err_string) on
      -- the failure path, so the previous `if not ok` guard alone never
      -- caught a normal save error. Capture the function's return value
      -- too and log when it's non-nil, otherwise the operator triaging a
      -- "HideFabFilter override didn't persist" report would see no log
      -- breadcrumb at all.
      local ok, save_ret = pcall(FXCache.save, cache)
      for k, mem_v in pairs(in_memory_values) do
        cache.preferred_types[k] = mem_v
      end
      if not ok then
        Log.line("PREF", "FXCache.save raised during HideFabFilter "
                       .. "rollback; in-memory override preserved: "
                       .. tostring(save_ret))
      elseif save_ret then
        Log.line("PREF", "FXCache.save failed during HideFabFilter "
                       .. "rollback; in-memory override preserved: "
                       .. tostring(save_ret))
      end
    else
      local save_err = FXCache.save(cache)
      if save_err then
        Log.line("PREF", "FXCache.save failed (HideFabFilter assign): "
                       .. tostring(save_err))
      end
    end
  end
  return assigned
end

-- =============================================================================
-- Utility: Code._save_generated (internal)
-- =============================================================================
-- Shared save-dialog + write flow used by Code.save_file and
-- Code.save_file_jsfx. Opens a native save dialog when js_ReaScriptAPI is
-- present; otherwise falls back to a GetUserInputs prompt and strips path
-- separators from the input so the user cannot escape opts.base_dir.
-- Returns the saved path on success, or nil on cancellation/error.
function Code._save_generated(code, suggested_name, opts)
  local dest_path
  if reaper.JS_Dialog_BrowseForSaveFile then
    local ret, path = reaper.JS_Dialog_BrowseForSaveFile(
      opts.dialog_title, opts.base_dir, suggested_name, opts.filter)
    if ret ~= 1 or not path or path == "" then return nil end
    -- Lower-case the path before matching ext_pattern. Filesystems on
    -- Windows / macOS preserve the typed case, so a user who picks
    -- "MyScript.LUA" in the dialog used to fall through the case-
    -- sensitive `%.lua$` pattern and we'd append .lua, producing the
    -- ugly double-extension MyScript.LUA.lua.
    if not path:lower():match(opts.ext_pattern) then path = path .. opts.ext end
    dest_path = path
  else
    local ret, name = reaper.GetUserInputs(
      opts.fallback_title, 1, opts.fallback_label, suggested_name)
    if not ret or name == "" then return nil end
    if not name:lower():match(opts.ext_pattern) then name = name .. opts.ext end
    name = name:match("[^\\/]+$") or name
    dest_path = opts.base_dir .. RA.SEP .. name
  end
  if Code.safe_write(dest_path, code) then return dest_path end
  return nil
end

-- Save JSFX code to REAPER's Effects folder (thin wrapper over _save_generated).
function Code.save_file_jsfx(code, suggested_name)
  return Code._save_generated(code, suggested_name, {
    dialog_title   = "Save JSFX Effect",
    base_dir       = reaper.GetResourcePath() .. RA.SEP .. "Effects",
    filter         = "JSFX files (.jsfx)\0*.jsfx\0All files\0*.*\0",
    ext            = ".jsfx",
    ext_pattern    = "%.jsfx$",
    fallback_title = "Save JSFX",
    fallback_label = "Filename (saved to REAPER Effects folder):,extrawidth=260",
  })
end

-- Save Lua script to REAPER's Scripts folder (thin wrapper over _save_generated).
function Code.save_file(code, suggested_name)
  return Code._save_generated(code, suggested_name, {
    dialog_title   = "Save Lua Script",
    base_dir       = reaper.GetResourcePath() .. RA.SEP .. "Scripts",
    filter         = "Lua files (.lua)\0*.lua\0All files\0*.*\0",
    ext            = ".lua",
    ext_pattern    = "%.lua$",
    fallback_title = "Save Script",
    fallback_label = "Filename (saved to REAPER Scripts folder):,extrawidth=260",
  })
end

-- Strips API keys and secrets from URLs/error strings before they reach the
-- UI. Covers ?key= / &key= style query params (case-insensitive) and Bearer
-- tokens in headers. Lua patterns do not support alternation, so each secret
-- name is scrubbed with its own gsub; an earlier "one-pattern" attempt used a
-- pipe character that matches literally, so it never fired.
local SCRUB_KEYS = {
  "[Kk][Ee][Yy]",
  "[Tt][Oo][Kk][Ee][Nn]",
  "[Ss][Ee][Cc][Rr][Ee][Tt]",
  "[Aa][Pp][Ii][_]?[Kk][Ee][Yy]",
  "[Aa][Cc][Cc][Ee][Ss][Ss][_][Tt][Oo][Kk][Ee][Nn]",
  "[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]",
}
-- Shared scrubber: both Log.add_error and Diag.add_error route error
-- strings through this before display / storage. SCRUB_KEYS stays a
-- local because nothing else references it.
function Log.scrub_url_secrets(s)
  if not s then return s end
  for _, name in ipairs(SCRUB_KEYS) do
    s = s:gsub("([?&]" .. name .. "=)[^&%s\"']+", "%1***")
  end
  s = s:gsub("([Bb]earer%s+)[^%s\"']+", "%1***")
  return s
end

-- Queue an error message into S.display_messages as an assistant turn,
-- flip S.status to "error", clear S.send_time, and scroll to bottom.
-- Optional link_url/link_label render a clickable URL beneath the text.
-- Optional `recovery = "token_limit"` renders inline recovery buttons
-- (bump max tokens / lower thinking), scoped to the provider that was
-- active at error time via provider_id on the message.
function Log.add_error(msg, link_url, link_label, recovery)
  S.status    = "error"
  S.send_time = nil
  local entry = {
    role       = "assistant",
    content    = Log.scrub_url_secrets(msg),
    link_url   = link_url,
    link_label = link_label,
    recovery   = recovery,
  }
  if recovery == "token_limit" then
    local p = PROVIDERS.active()
    entry.provider_id = p and p.id or nil
  end
  S.display_messages[#S.display_messages+1] = entry
  S.scroll_to_bottom = true
end

-- =============================================================================
-- Diag -- Diagnostic report builder for bug reports
-- =============================================================================
-- Captures recent code-execution errors and assembles a plain-text diagnostic
-- report the user can copy to their clipboard and paste into a bug report.

-- Schema version stamped into every saved FX cache file. Bump when the
-- on-disk structure changes in a way old code can't safely read. Files
-- with a missing or mismatched version are discarded cleanly on load
-- (fresh scan rebuilds the cache rather than silently misreading it).
-- Declared here (above Diag) because Diag.build_report reads it for the
-- diagnostic report's Plugin System section.
local FXCACHE_VERSION = 1

Diag = { errors = {}, MAX_ERRORS = 20 }

function Diag.add_error(msg, traceback, code)
  local entry = {
    time = os.date("%Y-%m-%d %H:%M:%S"),
    msg  = Log.scrub_url_secrets(tostring(msg)),
    traceback = traceback and Log.scrub_url_secrets(tostring(traceback)) or nil,
    code = code and (code:sub(1, 500) .. (#code > 500 and "..." or "")) or nil,
  }
  Diag.errors[#Diag.errors + 1] = entry
  if #Diag.errors > Diag.MAX_ERRORS then
    table.remove(Diag.errors, 1)
  end
end

-- opts (optional table):
--   skip_followup_note = true  -- omit the trailing "For detailed bugs..."
--                                 guidance paragraph. Used when the report
--                                 is embedded in a pre-filled email body
--                                 that already surfaces its own log-attach
--                                 instruction, so the two don't repeat.
function Diag.build_report(opts)
  local parts = {}
  -- Small pcall wrapper so a broken / missing extension probe can't
  -- crash the report build mid-stream.
  local function _try(fn) local ok, v = pcall(fn); if ok then return v end end
  -- On / Off formatter -- normalises booleans (and nil) to the
  -- ON / OFF convention the rest of the header already uses for
  -- "Auto model" / "Debug logging".
  local function _onoff(v) return v and "ON" or "OFF" end

  parts[#parts + 1] = "=== ReaAssist Diagnostic Report ==="
  parts[#parts + 1] = ""
  parts[#parts + 1] = "ReaAssist version: " .. CFG.VERSION
  parts[#parts + 1] = "REAPER version:    " .. tostring(reaper.GetAppVersion())
  parts[#parts + 1] = "OS:                " .. tostring(reaper.GetOS())
  -- ReaImGui version -- UI / rendering bugs hinge on this. Probe
  -- covers a few possible shapes across ReaImGui releases.
  local imgui_ver = _try(function()
    if not ImGui then return nil end
    if ImGui.ImGui_GetVersion then
      return select(1, ImGui.ImGui_GetVersion())
    end
    if ImGui.ReaImGui_Version then return ImGui.ReaImGui_Version end
  end)
  parts[#parts + 1] = "ReaImGui version:  " .. (imgui_ver and tostring(imgui_ver) or "unknown")
  parts[#parts + 1] = "Provider:          " .. (PROVIDERS.active().label or "unknown")
  parts[#parts + 1] = "Model:             " .. (MODELS.active_id() or "unknown")
  local p = PROVIDERS.active()
  if p.thinking_levels and p.thinking_levels[prefs.thinking_idx] then
    parts[#parts + 1] = "Thinking:          " .. p.thinking_levels[prefs.thinking_idx].label
  end
  -- Gemini paid-tier flag -- only meaningful when the active provider
  -- is Google, since it gates which models are visible and controls
  -- the "free tier data may be used for training" advisory.
  if p and p.id == "google" then
    parts[#parts + 1] = "Gemini paid tier:  " .. _onoff(S.gemini_paid_tier)
  end
  parts[#parts + 1] = "Debug logging:     " .. _onoff(prefs.debug_logging)
  if prefs.debug_logging then
    parts[#parts + 1] = "Log file:          " .. Log.path
    local f = io.open(Log.path, "r")
    if f then
      local size = f:seek("end") or 0
      f:close()
      parts[#parts + 1] = "Log file size:     " .. size .. " bytes"
    end
  end
  -- Current page / screen (which UI view the user was on when they copied
  -- the report). Useful for UI-specific bug reports.
  local screen = "chat"
  if api_keys.screen then
    screen = api_keys.screen
  elseif S.show_bug_report then screen = "bug_report"
  elseif S.show_help       then screen = "help"
  elseif S.show_credits    then screen = "credits"
  end
  parts[#parts + 1] = "Current screen:    " .. screen
  -- Session uptime -- seconds -> human-readable. Helps triage "UI
  -- froze after 6h" / "memory balloon" / long-session issues.
  local uptime_s = math_floor((reaper.time_precise() - (S.session_start_ts or reaper.time_precise())) + 0.5)
  local function _fmt_uptime(sec)
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then
      return string.format("%dm %02ds", math_floor(sec / 60), sec % 60)
    end
    local h = math_floor(sec / 3600)
    local m = math_floor((sec % 3600) / 60)
    return string.format("%dh %02dm", h, m)
  end
  parts[#parts + 1] = "Session uptime:    " .. _fmt_uptime(uptime_s)
  parts[#parts + 1] = ""

  -- Required + optional REAPER extensions. Missing / old extensions
  -- cause a long tail of "button did nothing" / "file dialog didn't
  -- open" bugs that are otherwise a pain to diagnose.
  parts[#parts + 1] = "--- Extensions ---"
  local sws_ok  = reaper.CF_GetSWSVersion ~= nil
  local sws_ver = sws_ok and _try(function() return reaper.CF_GetSWSVersion("") end) or nil
  parts[#parts + 1] = "SWS:               " ..
    (sws_ok and (sws_ver and tostring(sws_ver) or "installed") or "not installed")
  local js_ver = _try(function() return reaper.JS_ReaScriptAPI_Version and reaper.JS_ReaScriptAPI_Version() end)
  parts[#parts + 1] = "js_ReaScriptAPI:   " ..
    (js_ver and tostring(js_ver) or "not installed")
  -- Probe the specific calls ReaAssist uses, so a partially-working
  -- extension (e.g. old SWS / JS build missing a newer symbol) shows
  -- up here too rather than reading as "fully installed."
  parts[#parts + 1] = "CF_ShellExecute:   " ..
    _onoff(reaper.CF_ShellExecute ~= nil)
  parts[#parts + 1] = "CF_LocateInExplorer: " ..
    _onoff(reaper.CF_LocateInExplorer ~= nil)
  parts[#parts + 1] = "JS_Dialog_BrowseForSaveFile: " ..
    _onoff(reaper.JS_Dialog_BrowseForSaveFile ~= nil)
  parts[#parts + 1] = ""

  -- User preferences
  parts[#parts + 1] = "--- Preferences ---"
  parts[#parts + 1] = "Auto-run:          " .. _onoff(prefs.auto_run)
  parts[#parts + 1] = "Auto-backup:       " .. _onoff(prefs.auto_backup)
  parts[#parts + 1] = "Include snapshot:  " .. _onoff(prefs.include_snapshot)
  parts[#parts + 1] = "Include API ref:   " .. _onoff(prefs.include_api_ref)
  parts[#parts + 1] = "Max tokens:        " .. (CFG.MAX_TOKENS_OPTIONS[prefs.max_tokens_idx] or "?")
  parts[#parts + 1] = "Max history turns: " .. CFG.MAX_HISTORY_TURNS
  -- Cloud request timeout (seconds) -- affects "request hung" /
  -- "503 / timeout" bug reports directly.
  if prefs.cloud_request_timeout then
    parts[#parts + 1] = "Cloud timeout:     " .. tostring(prefs.cloud_request_timeout) .. "s"
  end
  parts[#parts + 1] = "API ref loaded:    " .. _onoff(S.api_ref_cache_core ~= nil)
  parts[#parts + 1] = "UI theme:          " .. tostring(prefs.theme_id or "default")
  local scale_val = CFG.UI_SCALE_OPTIONS[prefs.ui_scale_idx or 3] or 1.0
  parts[#parts + 1] = str_format("UI scale:          %.2fx", scale_val)
  -- API keys configured per provider (without revealing the keys). Helps
  -- diagnose "Test API Keys fails" or wrong-provider-selected reports.
  local configured = {}
  for _, pk in ipairs(PROVIDERS) do
    if S.api_key_map and S.api_key_map[pk.id] and S.api_key_map[pk.id] ~= "" then
      configured[#configured+1] = pk.label or pk.id
    end
  end
  parts[#parts + 1] = "API keys set:      " ..
    (#configured > 0 and tbl_concat(configured, ", ") or "(none)")
  parts[#parts + 1] = ""

  -- Plugin system state (chains, preferences, FX cache). Critical for
  -- diagnosing plugin-resolve / popup / auto-assign bugs.
  parts[#parts + 1] = "--- Plugin System ---"
  local ok_chains, chains = pcall(Code.get_fallback_chains)
  if ok_chains and chains then
    local chain_types = {}
    for k in pairs(chains) do chain_types[#chain_types+1] = k end
    table.sort(chain_types)
    parts[#parts + 1] = "Fallback chains loaded: " .. #chain_types
      .. (#chain_types > 0 and " (" .. tbl_concat(chain_types, ", ") .. ")" or "; check Plugin_Ref.md")
  else
    parts[#parts + 1] = "Fallback chains:        ERROR loading"
  end
  local ok_cache, fx_cache = pcall(FXCache.load)
  if ok_cache and fx_cache then
    local pref_types = fx_cache.preferred_types or {}
    local pref_keys = {}
    for k in pairs(pref_types) do pref_keys[#pref_keys+1] = k end
    table.sort(pref_keys)
    if #pref_keys == 0 then
      parts[#parts + 1] = "Preferred plugins:      (none set)"
    else
      parts[#parts + 1] = "Preferred plugins:"
      for _, k in ipairs(pref_keys) do
        parts[#parts + 1] = "  " .. k .. " = " .. tostring(pref_types[k])
      end
    end
    local plugin_count = 0
    for _ in pairs(fx_cache.plugins or {}) do
      plugin_count = plugin_count + 1
    end
    parts[#parts + 1] = "FX cache size:          " .. plugin_count .. " plugins scanned"
  end
  if CTX._installed_fx_list then
    parts[#parts + 1] = "Installed FX enumerated: " .. #CTX._installed_fx_list
  else
    parts[#parts + 1] = "Installed FX enumerated: (not populated yet this session)"
  end
  if ok_cache and fx_cache then
    parts[#parts + 1] = "FX cache schema:        v" .. tostring(fx_cache._version or "?")
      .. " (expected v" .. FXCACHE_VERSION .. ")"
  end
  -- Plugin_Ref.md status. Missing / unreadable file breaks chains + curated
  -- injection; size signals whether it looks truncated.
  local ref_path = RA.RESOURCES_DIR .. "ReaAssist_Plugin_Ref.md"
  local rf = io.open(ref_path, "r")
  if rf then
    local sz = rf:seek("end") or 0
    rf:close()
    parts[#parts + 1] = "Plugin_Ref.md:          present (" .. sz .. " bytes)"
  else
    parts[#parts + 1] = "Plugin_Ref.md:          MISSING at " .. ref_path
  end
  parts[#parts + 1] = ""

  -- Recent errors
  if #Diag.errors > 0 then
    parts[#parts + 1] = "--- Recent Errors (" .. #Diag.errors .. ") ---"
    for i, e in ipairs(Diag.errors) do
      parts[#parts + 1] = ""
      parts[#parts + 1] = "[" .. i .. "] " .. e.time
      parts[#parts + 1] = "  Error: " .. e.msg
      if e.traceback then
        parts[#parts + 1] = "  Traceback: " .. e.traceback
      end
      if e.code then
        parts[#parts + 1] = "  Code snippet: " .. e.code
      end
    end
  else
    parts[#parts + 1] = "--- No recent errors ---"
  end
  parts[#parts + 1] = ""

  -- Recent chat (last 5 exchanges, truncated) with details metadata.
  -- Trailing blank moved INSIDE the `if` so an empty chat doesn't
  -- leave a stray double-blank between "No recent errors" above and
  -- "Session State" below.
  if #S.display_messages > 0 then
    parts[#parts + 1] = "--- Recent Chat (last 5 exchanges, truncated) ---"
    local start = math.max(1, #S.display_messages - 9)
    for i = start, #S.display_messages do
      local m = S.display_messages[i]
      local content = m.content or ""
      if #content > 300 then content = content:sub(1, 300) .. "..." end
      parts[#parts + 1] = ""
      parts[#parts + 1] = "[" .. (m.role or "?") .. "] " .. content
      -- Include exchange details when available (context sent, tokens, cost).
      local details = {}
      if m.ctx_label   then details[#details + 1] = "context: " .. m.ctx_label end
      if m.model_label then details[#details + 1] = "model: " .. m.model_label end
      if m.tok_in      then details[#details + 1] = "in: " .. m.tok_in end
      if m.tok_out     then details[#details + 1] = "out: " .. m.tok_out end
      if m.tok_cache_read and m.tok_cache_read > 0 then
        details[#details + 1] = "cache_read: " .. m.tok_cache_read
      end
      if m.tok_cache_create and m.tok_cache_create > 0 then
        details[#details + 1] = "cache_create: " .. m.tok_cache_create
      end
      if m.cost and m.cost > 0 then
        details[#details + 1] = str_format("cost: $%.4f", m.cost)
      end
      if m.fx_cache_label then
        details[#details + 1] = "fx_cache: " .. m.fx_cache_label
      end
      if #details > 0 then
        parts[#parts + 1] = "  [" .. tbl_concat(details, " | ") .. "]"
      end
      -- Include generated code block if present (truncated).
      if m.code_block then
        local code = m.code_block
        if #code > 800 then code = code:sub(1, 800) .. "\n  ...(truncated)" end
        parts[#parts + 1] = "  Code block:"
        for cline in code:gmatch("[^\n]+") do
          parts[#parts + 1] = "    " .. cline
        end
      end
    end
    parts[#parts + 1] = ""
  end

  -- Status
  parts[#parts + 1] = "--- Session State ---"
  parts[#parts + 1] = "Status: " .. tostring(S.status)
  parts[#parts + 1] = "Messages: " .. #S.display_messages
  parts[#parts + 1] = "History turns: " .. #S.history
  -- In-flight request state. Only meaningful while a request is
  -- actually pending -- `S.send_time` is non-nil for the duration of
  -- the curl call and cleared on completion. Catches "my send is
  -- stuck" reports where the watchdog hasn't tripped yet.
  if S.send_time then
    local elapsed = reaper.time_precise() - S.send_time
    parts[#parts + 1] = str_format("In-flight request: started %.1fs ago", elapsed)
  end

  -- Resolve popup state: useful for diagnosing "popup didn't fire" reports.
  if S.resolve_popup then
    parts[#parts + 1] = "Resolve popup: ACTIVE (type=" ..
      tostring(S.resolve_popup.type) .. ")"
  elseif S.open_resolve_popup then
    parts[#parts + 1] = "Resolve popup: pending open"
  else
    parts[#parts + 1] = "Resolve popup: inactive"
  end

  -- Pending request state: captures an in-flight or stuck turn.
  local pending_bits = {}
  if S.pending_orig_prompt then pending_bits[#pending_bits+1] = "orig_prompt" end
  if S.pending_snapshot    then pending_bits[#pending_bits+1] = "snapshot"    end
  if S.pending_code        then pending_bits[#pending_bits+1] = "code"        end
  if S.pending_resolves and #S.pending_resolves > 0 then
    pending_bits[#pending_bits+1] = "queued_resolves=" ..
      tbl_concat(S.pending_resolves, ",")
  end
  if #pending_bits > 0 then
    parts[#parts + 1] = "Pending turn state: " .. tbl_concat(pending_bits, ", ")
  end

  -- Sticky context keys pinned this session (e.g. plugin_ref:Pro-Q 4). Shows
  -- what the preempt / resolve flow injected so "model got wrong params"
  -- reports can be traced.
  if S.sticky_context and next(S.sticky_context) then
    local sticky_keys = {}
    for k in pairs(S.sticky_context) do sticky_keys[#sticky_keys+1] = k end
    table.sort(sticky_keys)
    parts[#parts + 1] = "Sticky context pinned: " ..
      tbl_concat(sticky_keys, ", ")
  end

  -- Last script execution result (from the most recent generated-code run).
  -- Captures compile + runtime errors from user-run code. Errors get cleared
  -- on next send, so a non-nil here means "the last thing the user saw".
  if S.last_run_error and S.last_run_error ~= "" then
    parts[#parts + 1] = "Last script error: " .. tostring(S.last_run_error)
  end

  -- FX scan state: catches stuck/in-flight rescans.
  if fx_cache_ui and fx_cache_ui.rescan and fx_cache_ui.rescan.active then
    parts[#parts + 1] = "FX scan in progress: " ..
      tostring(fx_cache_ui.rescan.ident or "?")
  end
  if pref_plugins and pref_plugins.scan and pref_plugins.scan.active then
    parts[#parts + 1] = "Preferred-plugins scan in progress: " ..
      tostring(pref_plugins.scan.phase or "?")
  end

  -- Update-check state: "why isn't my update showing" reports.
  if update and update.state and update.state ~= "idle" then
    parts[#parts + 1] = "Update check state: " .. tostring(update.state)
      .. (update.remote_version and (" (remote v" .. update.remote_version .. ")") or "")
  end

  -- Follow-up note block. Skipped when the caller (the Feedback page's
  -- email flow) embeds this report inside an email body that already
  -- surfaces a tailored log-attach instruction of its own -- printing
  -- both creates redundant back-to-back "please attach the log" text.
  -- Default behaviour (used by the standalone Copy button) keeps the
  -- note in so a hand-pasted report carries the instruction with it.
  if not (opts and opts.skip_followup_note) then
    parts[#parts + 1] = ""
    parts[#parts + 1] = "For detailed bugs (wrong model output, multi-turn issues, API errors),"
    parts[#parts + 1] = "also attach the debug log: " .. Log.path
    parts[#parts + 1] = "Enable \"Enable Advanced Log\" on the Report a Bug page if it's off, reproduce, then send."
  end
  parts[#parts + 1] = ""
  parts[#parts + 1] = "=== End Report ==="
  return tbl_concat(parts, "\n")
end

-- =============================================================================
-- Context bucket functions
-- =============================================================================
-- Each takes a project pointer (proj) captured at send time and returns a
-- plain-text string describing a slice of that project's state. Track indices
-- are reported as 1-based for the assistant's benefit (REAPER API is 0-based).
-- =============================================================================
-- Unified FX parameter cache (JSON)
-- =============================================================================
-- Persists plugin parameter metadata (names, indices, defaults, enum values)
-- to ReaAssist_FX_Cache.json. Two top-level maps:
--
--   preferred_types  -- user preferences (one plugin per type). Values are
--                       the chain-entry form (format-agnostic), e.g.
--                       "Pro-Q 4" or "ReJJ/ReEQ/ReEQ.jsfx". Populated either
--                       by Code.ensure_preferred_from_chains at startup or
--                       by user edits on the Preferred Plugins page.
--   plugins          -- live-scanned param data keyed by full enumerated FX
--                       name (e.g. "VST3: Pro-Q 4"). Only populated by
--                       user-triggered scans for non-curated plugins.
--
-- Structure:
--   {
--     "preferred_types": { "eq": "Pro-Q 4", ... },
--     "plugins": {
--       "VST3: Some Plugin": {
--         "param_count": 234,
--         "max_group": 24,
--         "params": [
--           { "idx": 0, "name": "1 Frequency", "default": 0.3040,
--             "display": "100.0 Hz" },
--           { "idx": 5, "name": "1 Shape", "default": 0.0,
--             "display": "Bell", "enum": ["Bell","Low Cut",...] }
--         ]
--       }
--     }
--   }

JSON = { NULL = {} }

FXCache = {}

-- In-memory cache. Loaded lazily on first access, invalidated on save.
local _fx_cache_mem = nil

function FXCache.load()
  if _fx_cache_mem then return _fx_cache_mem end
  local ok_f, f = pcall(io.open, RA.FX_CACHE_PATH, "r")
  if not ok_f or not f then
    -- Stamp _version on every fresh-table return so the schema invariant
    -- doesn't depend on a save round-trip to land. Earlier shape varied
    -- per branch (no-file / empty / corrupt / schema-mismatch) which left
    -- a brief window where _fx_cache_mem._version was nil.
    _fx_cache_mem = { _version = FXCACHE_VERSION, preferred_types = {}, plugins = {} }
    return _fx_cache_mem
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    _fx_cache_mem = { _version = FXCACHE_VERSION, preferred_types = {}, plugins = {} }
    return _fx_cache_mem
  end
  local data, err = JSON.decode(content)
  if not data then
    -- Surface the parse error to the debug log. Without this, the user
    -- silently loses their cache on a truncated or corrupted file with
    -- no breadcrumb to triage from -- only the schema-mismatch branch
    -- below logged.
    Log.line("FX_CACHE", "JSON decode failed (" .. tostring(err)
      .. "); discarding cache")
    _fx_cache_mem = { _version = FXCACHE_VERSION, preferred_types = {}, plugins = {} }
    return _fx_cache_mem
  end
  -- Reject files from a different schema version. Missing _version means
  -- the file was written before this field was added; treat it the same
  -- way -- start fresh rather than silently misread. User's only real
  -- loss is re-scanning plugins on next use.
  if data._version ~= FXCACHE_VERSION then
    Log.line("FX_CACHE", "schema version mismatch (file="
      .. tostring(data._version) .. ", expected=" .. FXCACHE_VERSION
      .. ") -- discarding cache")
    _fx_cache_mem = { _version = FXCACHE_VERSION, preferred_types = {}, plugins = {} }
    return _fx_cache_mem
  end
  -- Ensure required top-level keys exist.
  data.preferred_types = data.preferred_types or {}
  data.plugins = data.plugins or {}
  _fx_cache_mem = data
  return _fx_cache_mem
end

function FXCache.save(cache)
  cache = cache or _fx_cache_mem
  if not cache then return "No cache data to save." end
  -- Stamp the schema version so future builds can reject old files cleanly.
  cache._version = FXCACHE_VERSION
  local json_str, err = JSON.encode(cache, "  ")
  if not json_str then return "JSON encode failed: " .. tostring(err) end
  -- Atomic write: temp file + rename. AV scanners and abrupt exits can
  -- otherwise leave the 60+ KB cache JSON half-written, breaking parse on
  -- the next session.
  local tmp_path = RA.FX_CACHE_PATH .. ".tmp"
  local ok_f, f = pcall(io.open, tmp_path, "w")
  if not ok_f or not f then return "Failed to open " .. tmp_path end
  local ok_w, w_err = pcall(function() f:write(json_str .. "\n") end)
  pcall(function() f:close() end)
  if not ok_w then
    os.remove(tmp_path)
    return "Failed writing " .. tmp_path .. ": " .. tostring(w_err)
  end
  -- Backup-and-restore rename: Windows os.rename cannot overwrite, so the
  -- original cache must be moved out of the way before renaming tmp into
  -- place. If the rename fails (AV lock, disk full, permission flip), the
  -- .bak is restored so the user never loses their existing cache.
  local bak_path = RA.FX_CACHE_PATH .. ".bak"
  os.remove(bak_path)
  local had_existing = os.rename(RA.FX_CACHE_PATH, bak_path)
  local ok_r, ren_err = os.rename(tmp_path, RA.FX_CACHE_PATH)
  if not ok_r then
    os.remove(tmp_path)
    if had_existing then os.rename(bak_path, RA.FX_CACHE_PATH) end
    return "Failed renaming temp cache: " .. tostring(ren_err)
  end
  if had_existing then os.remove(bak_path) end
  _fx_cache_mem = cache
  return nil  -- success
end

function FXCache.get_plugin(identifier)
  local cache = FXCache.load()
  return cache.plugins[identifier]
end

-- Look up a plugin by fuzzy-matching the identifier against cache keys.
-- Uses bidirectional case-insensitive substring match (each direction catches
-- both "Pro-Q 4" in "VST3: Pro-Q 4 (FabFilter)" and vice versa).
function FXCache.find_plugin(name)
  local cache = FXCache.load()
  -- Exact match first.
  if cache.plugins[name] then return name, cache.plugins[name] end
  -- Fuzzy match against all cached identifiers. Pick the longest
  -- matching key (most specific) instead of `pairs`-first match: when
  -- two cached plugins share a common substring (e.g. "Pro-Q" and
  -- "Pro-Q 4 (FabFilter)") `pairs` order is hash-bucket-dependent, so
  -- the same lookup could pick either across saves/reloads. CTX.fx_params
  -- attaches the cached plugin's enum/range data via this lookup, so
  -- non-deterministic resolution corrupts the [enum: ...] annotation
  -- sent to the model.
  local name_lower = name:lower()
  local best_ident, best_data, best_len = nil, nil, -1
  for ident, data in pairs(cache.plugins) do
    local ident_lower = ident:lower()
    if ident_lower:find(name_lower, 1, true)
       or name_lower:find(ident_lower, 1, true) then
      if #ident > best_len then
        best_ident, best_data, best_len = ident, data, #ident
      end
    end
  end
  return best_ident, best_data
end

-- Mutation counter bumped whenever cache.plugins or cache.preferred_types
-- changes. Lets render-side code cheaply cache lists derived from these
-- (FX cache settings page, preempt scans) and invalidate on change
-- without having to thread invalidation calls through every mutator.
FXCache._mutation_count = 0

function FXCache.put_plugin(identifier, params_list, param_count, max_group, needs_deep_scan)
  local cache = FXCache.load()
  cache.plugins[identifier] = {
    param_count      = param_count or 0,
    max_group        = max_group or 0,
    params           = params_list,
    needs_deep_scan  = needs_deep_scan or nil,
  }
  FXCache._mutation_count = FXCache._mutation_count + 1
  return FXCache.save(cache)
end

function FXCache.remove_plugin(identifier)
  local cache = FXCache.load()
  cache.plugins[identifier] = nil
  FXCache._mutation_count = FXCache._mutation_count + 1
  return FXCache.save(cache)
end

function FXCache.clear_plugins()
  local cache = FXCache.load()
  cache.plugins = {}
  FXCache._mutation_count = FXCache._mutation_count + 1
  return FXCache.save(cache)
end

-- Wipe all type->plugin mappings. Used by the "Clear All" button on the
-- Preferred Plugins page. Does NOT touch cache.plugins (scanned param data
-- stays intact so we don't have to re-scan everything when the user reconfigures).
function FXCache.clear_preferred_types()
  local cache = FXCache.load()
  cache.preferred_types = {}
  FXCache._mutation_count = FXCache._mutation_count + 1
  return FXCache.save(cache)
end

function FXCache.set_preferred_type(type_key, identifier)
  local cache = FXCache.load()
  cache.preferred_types[type_key] = identifier
  FXCache._mutation_count = FXCache._mutation_count + 1
  return FXCache.save(cache)
end

function FXCache.get_preferred_types()
  local cache = FXCache.load()
  return cache.preferred_types
end

function FXCache.invalidate()
  _fx_cache_mem = nil
  FXCache._mutation_count = (FXCache._mutation_count or 0) + 1
end

-- =============================================================================
-- Context bucket builders (CTX)
-- =============================================================================
-- Stored in a table to conserve top-level local variable slots
-- (Lua 5.x 200-local limit). Each function takes (proj) and returns a string.
CTX = {}

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
  return str_format("Tempo: %.2f BPM | Time Signature: %d/%d", bpm, num, denom)
end

-- Replace pipe characters in track / item names so they don't collide with
-- the pipe-delimited row format the snapshot uses. Pipes are exceedingly
-- rare in real REAPER track names; the substitution keeps the format
-- parseable even when they do appear.
local function _scrub_pipes(s) return (tostring(s or ""):gsub("|", "_")) end

function CTX.tracks(proj)
  local count = R_CountTracks(proj)
  if count == 0 then return "Tracks: none" end
  local lines = { str_format("Tracks (N=%d) [idx|name|items]:", count) }
  for i = 0, count - 1 do
    local tr         = R_GetTrack(proj, i)
    local _, nm      = R_GetTrackName(tr)
    local item_count = R_CountTrackMediaItems(tr)
    lines[#lines+1] = str_format("%d|%s|%d", i + 1, _scrub_pipes(nm), item_count)
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
  if #rows == 0 then return "Track flags: none (no tracks muted/soloed/armed)" end
  table.insert(rows, 1, "Track flags [idx|name|flags]:")
  return tbl_concat(rows, "\n")
end

-- Cap the per-snapshot FX listing so a 100+ track session doesn't dump
-- 30K+ bytes of FX names every turn. Selected tracks are reported first and
-- always survive the cap; remaining tracks fill up to the limit. The model
-- can request the full listing on demand via <context_needed>fx_chains</...>.
CTX.MAX_FX_REPORT = 30

function CTX.fx(proj)
  local count = R_CountTracks(proj)
  local sel_with_fx, other_with_fx = {}, {}
  for i = 0, count - 1 do
    local tr       = R_GetTrack(proj, i)
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
  local total = #sel_with_fx + #other_with_fx
  if total == 0 then return "FX chains: none" end
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

function CTX.selected(proj)
  local count    = R_CountTracks(proj)
  local selected = {}
  for i = 0, count - 1 do
    local tr = R_GetTrack(proj, i)
    if R_IsTrackSelected(tr) then
      local _, nm = R_GetTrackName(tr)
      selected[#selected+1] = str_format("%q (index %d)", nm, i + 1)
    end
  end
  return #selected > 0
    and ("Selected tracks: " .. tbl_concat(selected, ", "))
    or  "Selected tracks: none"
end

-- Uses GetSet_LoopTimeRange2 (project-aware variant) instead of the non-project
-- GetSet_LoopTimeRange so the correct tab's time selection is always queried.
function CTX.time_selection(proj)
  local ts, te = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  return te > ts
    and str_format("Time selection: %.3fs - %.3fs", ts, te)
    or  "Time selection: none"
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
function CTX.loop(proj)
  local ls, le = reaper.GetSet_LoopTimeRange2(proj, false, true, 0, 0, false)
  local enabled = reaper.GetSetRepeatEx(proj, -1) == 1
  if le > ls then
    return str_format("Loop: %s | %.3fs - %.3fs",
      enabled and "enabled" or "disabled", ls, le)
  end
  return "Loop: " .. (enabled and "enabled" or "disabled") .. " | no loop points set"
end

-- CTX.markers(proj) -> string
-- Reports all project markers and region start/end points (capped at
-- CTX.MAX_MARKER_REPORT to keep snapshot size bounded on heavily-markered projects).
-- EnumProjectMarkers3 returns (retval, isrgn, pos, rgnend, name, idx).
-- Markers and region boundaries are both reported; regions include an end pos.
CTX.MAX_MARKER_REPORT, CTX.MAX_ITEM_REPORT = 20, 5
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

-- CTX.selected_items(proj) -> string
-- Reports the count and key properties (track, position, length) of selected
-- media items. Capped at CTX.MAX_ITEM_REPORT items to keep snapshot size bounded
-- for projects with large block-selections. Items beyond the cap are noted
-- with a summary count so the assistant knows additional items exist.
--
-- Item indices in output are 1-based (matching REAPER's UI display) even
-- though CountSelectedMediaItems / GetSelectedMediaItem are 0-based.
function CTX.selected_items(proj)
  local count = R_CountSelectedMediaItems(proj)
  if count == 0 then return "Selected items: none" end

  local lines = {
    str_format("Selected items (N=%d) [item_idx|track_idx|track_name|pos_s|len_s]:", count)
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
    lines[#lines+1] = str_format(
      "%d|%d|%s|%.3f|%.3f",
      i + 1, track_idx, _scrub_pipes(track_nm), pos, len)
  end
  if count > CTX.MAX_ITEM_REPORT then
    lines[#lines+1] = str_format(
      "(+%d more)", count - CTX.MAX_ITEM_REPORT)
  end
  return tbl_concat(lines, "\n")
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

-- CTX.fx_params(proj, filter_names) -> string, matched_count
-- On-demand bucket (NOT included in the default session snapshot).
-- Returns current parameter values ONLY for FX whose names fuzzy-match at
-- least one entry in filter_names (see CTX.fx_name_matches above).
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
  -- Guard: filter_names must be a non-empty table. If the assistant somehow emits a
  -- bare <context_needed>fx_params</context_needed> with no plugin name, the
  -- parser catches it before calling this function, but defend here too.
  if not filter_names or #filter_names == 0 then
    return "FX PARAMETER VALUES: (error: no plugin name specified -- "
      .. "use fx_params:PluginName to request specific plugins)", 0
  end

  local track_count = R_CountTracks(proj)
  local header = "FX PARAMETER VALUES (filtered: "
    .. tbl_concat(filter_names, ", ") .. "):"
  local lines = { header }
  local matched_fx = 0  -- count of FX blocks actually written

  for ti = 0, track_count - 1 do
    local tr       = R_GetTrack(proj, ti)
    local _, nm    = R_GetTrackName(tr)
    local fx_count = R_TrackFX_GetCount(tr)
    local track_lines = {}  -- buffered so we only emit the track header when
                            -- at least one FX on this track matches the filter

    for fi = 0, fx_count - 1 do
      local _, fx_nm = R_TrackFX_GetFXName(tr, fi, "")

      -- Skip this FX if the name does not match any filter term.
      if not CTX.fx_name_matches(fx_nm, filter_names) then
        goto continue_fx
      end

      matched_fx = matched_fx + 1

      -- Emit the track header once on the first matching FX for this track.
      if #track_lines == 0 then
        track_lines[#track_lines+1] = str_format("Track %d %q:", ti + 1, nm)
      end

      track_lines[#track_lines+1] = str_format("  FX [%d] %s:", fi, fx_nm)
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
        track_lines[#track_lines+1] = str_format(
          "    [%d] %s: %s  [norm: %.4f]%s",
          pi, param_nm, disp, norm, suffix)
        param_shown = param_shown + 1
        ::continue_param::
      end
      if param_shown < param_count then
        track_lines[#track_lines+1] = str_format(
          "    (%d host/uninformative params filtered)", param_count - param_shown)
      end

      ::continue_fx::
    end

    -- Append this track's lines to the master list if any FX matched.
    for _, l in ipairs(track_lines) do lines[#lines+1] = l end
  end

  if matched_fx == 0 then
    lines[#lines+1] = "  (no matching FX found on any track -- the plugin is not loaded yet. "
      .. "If fx_list results are available above, use them to write code that adds the plugin and sets parameters "
      .. "using find_param and set_param_display at runtime. Do NOT request fx_list again -- proceed with the code.)"
  end

  return tbl_concat(lines, "\n"), matched_fx
end

-- =============================================================================
-- CTX.docs
-- =============================================================================
-- Loads the REAPER Lua API reference from two files in the script's Resources
-- folder: ReaAssist_API_Ref.md (core, pinned only when "Always include REAPER
-- API reference" is on; otherwise fetched on-demand via the docs bucket) and
-- ReaAssist_API_Ref_Extended.md (less-common surface; on-demand only via
-- the docs_extended bucket). Contents are cached in S.api_ref_cache_core /
-- S.api_ref_cache_extended so subsequent calls within a session do not hit
-- the filesystem. Does not take a proj argument because the API reference is
-- project-independent.
--
-- For the extended file, leading HTML-comment header lines (and blank lines
-- between them) are skipped so file-level dev commentary doesn't leak into
-- the model-facing payload. Caller-visible content begins at the first
-- non-comment, non-blank line.
--
-- Returns the formatted reference string on success, or nil + error message on
-- failure. Callers MUST check for nil and show the error to the user in chat
-- rather than sending the error text to the assistant.

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

local function _strip_leading_html_comments(s)
  -- Consume any leading run of `<!-- ... -->` lines + blank lines so the
  -- file-level dev header added to ReaAssist_API_Ref_Extended.md (three
  -- single-line HTML comments) doesn't ship to the model.
  local i = 1
  while true do
    local _, e = s:find("^%s*<!%-%-.-%-%->%s*\n", i)
    if not e then break end
    i = e + 1
  end
  return s:sub(i)
end

local function _load_api_ref_split()
  if S.api_ref_cache_core then return end
  local core_path = RA.RESOURCES_DIR .. "ReaAssist_API_Ref.md"
  local ext_path  = RA.RESOURCES_DIR .. "ReaAssist_API_Ref_Extended.md"
  local core, core_err = _read_ref_file(core_path, "ReaAssist_API_Ref.md")
  if not core then S._api_ref_load_err = core_err; return end
  local ext,  ext_err  = _read_ref_file(ext_path,  "ReaAssist_API_Ref_Extended.md")
  if not ext  then S._api_ref_load_err = ext_err;  return end
  S.api_ref_cache_core     = core:gsub("%s+$", "")
  S.api_ref_cache_extended = _strip_leading_html_comments(ext):gsub("%s+$", "")
end

function CTX.docs()
  _load_api_ref_split()
  if S._api_ref_load_err then return nil, S._api_ref_load_err end
  return "REAPER LUA API REFERENCE:\n" .. S.api_ref_cache_core
end

function CTX.docs_extended()
  _load_api_ref_split()
  if S._api_ref_load_err then return nil, S._api_ref_load_err end
  return "REAPER LUA API REFERENCE (EXTENDED):\n" .. S.api_ref_cache_extended
end

-- =============================================================================
-- CTX.prompt_bundle
-- =============================================================================
-- Loads a conditional prompt bundle file from the Resources/ folder. Bundles
-- carry sections of the system prompt that only apply to certain request types
-- (plugin workflow, JSFX generation, theme color changes). They are fetched
-- on-demand when the model emits <context_needed>prompt_bundle:NAME</context_needed>
-- so the always-on system prompt can stay small. Once fetched, the bundle
-- stays pinned via sticky_context for the rest of the conversation.
--
-- Name mapping (lowercase request -> Resources filename):
--   plugin -> ReaAssist_Plugin_Prompt.md
--   jsfx   -> ReaAssist_JSFX_Prompt.md
--   theme  -> ReaAssist_Theme_Prompt.md
-- Unknown names return a nil + error string so the caller can surface a clean
-- error to the user instead of silently no-op'ing.
local PROMPT_BUNDLE_FILES = {
  plugin = "ReaAssist_Plugin_Prompt.md",
  jsfx   = "ReaAssist_JSFX_Prompt.md",
  theme  = "ReaAssist_Theme_Prompt.md",
}

function CTX.prompt_bundle(name)
  if type(name) ~= "string" or name == "" then
    return nil, "prompt_bundle requires a bundle name (plugin / jsfx / theme)."
  end
  name = name:lower()
  local filename = PROMPT_BUNDLE_FILES[name]
  if not filename then
    return nil, "Unknown prompt bundle: '" .. name .. "'. "
      .. "Valid names: plugin, jsfx, theme."
  end
  S.prompt_bundle_cache = S.prompt_bundle_cache or {}
  if S.prompt_bundle_cache[name] then return S.prompt_bundle_cache[name] end
  local path = RA.RESOURCES_DIR .. filename
  local f = io.open(path, "r")
  if not f then
    return nil, "Prompt bundle file not found at:\n" .. path
      .. "\n\nPlace " .. filename .. " in the Resources/ subfolder "
      .. "next to this script."
  end
  local content = f:read("*a")
  f:close()
  if #content > CFG.MAX_API_REF_BYTES then
    return nil, str_format(
      "%s is too large (%.1f KB, max %d KB). "
      .. "This may not be the correct file.",
      filename, #content / 1024, CFG.MAX_API_REF_BYTES / 1024)
  end
  -- Strip the leading HTML-comment header (dev metadata: "served by X",
  -- "requested via Y", etc.) so it doesn't ship with the model-facing
  -- payload. Saves ~70 tokens per bundle per turn and prevents the
  -- model from seeing internal routing detail that isn't relevant to
  -- its task. Files stay fully readable for humans editing them.
  content = _strip_leading_html_comments(content)
  local header = "PROMPT BUNDLE (" .. name:upper() .. "):\n"
  local payload = header .. content:gsub("%s+$", "")
  S.prompt_bundle_cache[name] = payload
  return payload
end

-- =============================================================================
-- CTX.midi
-- =============================================================================
-- Loads ReaAssist_MIDI_Ref.md from the script folder. Contains MIDI workflow
-- patterns, PPQ explainer, value ranges, function signatures, and worked
-- examples for note/CC/event manipulation. Cached after first read like
-- CTX.docs().
--
-- Returns the formatted reference string on success, or nil + error message
-- on failure.
function CTX.midi()
  if not S.midi_ref_cache then
    local ref_path = RA.RESOURCES_DIR .. "ReaAssist_MIDI_Ref.md"
    local f = io.open(ref_path, "r")
    if not f then
      return nil, "MIDI reference file not found at:\n" .. ref_path
        .. "\n\nPlace ReaAssist_MIDI_Ref.md in the Resources/ subfolder "
        .. "next to this script."
    end
    local content = f:read("*a")
    f:close()
    if #content > CFG.MAX_API_REF_BYTES then
      return nil, str_format(
        "MIDI reference file is too large (%.1f KB, max %d KB).\n"
        .. "Expected ReaAssist_MIDI_Ref.md.",
        #content / 1024, CFG.MAX_API_REF_BYTES / 1024)
    end
    S.midi_ref_cache = content
  end
  return "REAPER MIDI WORKFLOW REFERENCE:\n" .. S.midi_ref_cache
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
    return false, "No theme changes to save."
  end
  local theme_path = reaper.GetLastColorThemeFile()
  if not theme_path or theme_path == "" then
    return false, "Could not determine the current theme file."
  end
  if theme_path:lower():match("%.reaperthemezip$") then
    return false, "Your current theme is a .ReaperThemeZip file which "
      .. "cannot be edited directly.\n\nTo save changes: open the Theme "
      .. "development/tweaker window (Actions > Theme development/tweaker) "
      .. "and click 'Save Theme...' to export as a .ReaperTheme file."
  end
  -- Collect the keys and their current runtime values.
  local keys = {}
  for k in manifest:gmatch("[^,]+") do
    local trimmed = k:match("^%s*(.-)%s*$")
    keys[trimmed] = reaper.GetThemeColor(trimmed, 0)
  end
  -- Read the existing theme file.
  local f, err = io.open(theme_path, "r")
  if not f then return false, "Cannot read theme file: " .. (err or theme_path) end
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
  if not f then return false, "Cannot write theme file: " .. (err or tmp_path) end
  local ok_w, err_w = f:write(content)
  local ok_c, err_c = f:close()
  if not ok_w or not ok_c then
    os.remove(tmp_path)
    return false, "Failed to write theme file: " .. tostring(err_w or err_c or "close failed")
  end
  os.remove(theme_path)
  local ok_r, err_r = os.rename(tmp_path, theme_path)
  if not ok_r then
    os.remove(tmp_path)
    return false, "Failed to replace theme file: " .. tostring(err_r)
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
--
-- Returns the formatted reference string on success, or nil + error message
-- on failure.
function CTX.theme()
  if not S.theme_ref_cache then
    local ref_path = RA.RESOURCES_DIR .. "ReaAssist_Theme_Ref.md"
    local f = io.open(ref_path, "r")
    if not f then
      return nil, "Theme reference file not found at:\n" .. ref_path
        .. "\n\nPlace ReaAssist_Theme_Ref.md in the Resources/ subfolder "
        .. "next to this script."
    end
    local content = f:read("*a")
    f:close()
    if #content > CFG.MAX_API_REF_BYTES then
      return nil, str_format(
        "Theme reference file is too large (%.1f KB, max %d KB).\n"
        .. "Expected ReaAssist_Theme_Ref.md.",
        #content / 1024, CFG.MAX_API_REF_BYTES / 1024)
    end
    S.theme_ref_cache = content
  end
  return "REAPER THEME COLOR REFERENCE:\n" .. S.theme_ref_cache
end

-- =============================================================================
-- CTX.plugin_ref
-- =============================================================================
-- Loads ReaAssist_Plugin_Ref.md and returns ONLY the sections matching
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

-- Build the per-plugin section cache from Plugin_Ref.md. Idempotent;
-- lazy -- call before reading CTX._plugin_ref_cache. Returns true on
-- success, false + error string if the file is missing.
function CTX.ensure_plugin_ref_cache()
  if CTX._plugin_ref_cache then return true end
  local ref_path = RA.RESOURCES_DIR .. "ReaAssist_Plugin_Ref.md"
  local f = io.open(ref_path, "r")
  if not f then
    return false, "Plugin reference file not found at:\n" .. ref_path
      .. "\n\nPlace ReaAssist_Plugin_Ref.md in the Resources/ subfolder "
      .. "next to this script."
  end
  local content = f:read("*a")
  f:close()

  -- Parse into sections keyed by "## <name>" headers. Full trailing string
  -- captured + trimmed so multi-word headers like "## Pro-Q 4" cache as
  -- "pro-q 4" (not "pro-q").
  CTX._plugin_ref_cache = {}
  local cur_name = nil
  local cur_lines = {}
  for line in content:gmatch("[^\n]+") do
    local sec_name = line:match("^##%s+(.-)%s*$")
    if sec_name then
      if cur_name then
        CTX._plugin_ref_cache[cur_name:lower()] = tbl_concat(cur_lines, "\n")
      end
      cur_name = sec_name
      cur_lines = { line }
    elseif cur_name then
      cur_lines[#cur_lines+1] = line
    end
  end
  if cur_name then
    CTX._plugin_ref_cache[cur_name:lower()] = tbl_concat(cur_lines, "\n")
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
-- NOTE: declared with `function` (no `local`) so it assigns to the
-- forward-declared local near `Code = {}`, which is needed by
-- Code.ensure_preferred_from_chains earlier in the file.
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
    -- Detect enum params: probe 21 evenly-spaced values. If 2-20 distinct
    -- display strings, record as enum. Also capture display at norm 0/1
    -- for continuous params so the model knows the API display range.
    -- Probe 21 evenly-spaced normalised values to detect enum params and
    -- capture display@0 / display@1 for continuous params. The earlier
    -- early-return at "if needs_deep_scan then return ..." above guarantees
    -- needs_deep_scan is false at this point in the loop, so no `if not
    -- needs_deep_scan` wrapper is needed here.
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

  -- Insert temp track at end, add plugin. Wrap in an explicit undo block so
  -- the flags=0 Undo_EndBlock in the read phase discards our own edits
  -- cleanly; without a matching Begin, the End would mismatch the stack.
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

  return tmp_tr, fx_idx, best_id, nil
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
    -- Dev-only: treat FabFilter entries as "no pref set" when the hide
    -- flag is on, so the model emits resolve:<type> and fires the popup
    -- the dev wants to exercise.
    if hide_ff and _is_fabfilter_ident(identifier) then
      identifier = nil
    end
    if identifier and identifier ~= "" then
      local plugin_data = cache.plugins[identifier]
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
    FXCache.save(cache)
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
        cache.preferred_types[rkey] = name
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
        UI.show_float_toast("Save failed", "err")
      else
        scan.status = ""
        UI.show_float_toast("Preferences saved", "ok")
        pref_plugins.pending_exit = true
      end
    else
      scan.status = ""
      -- Still save the preferences (without param data).
      local err = CTX.save_pref_plugins()
      if err then
        UI.show_float_toast("Save failed: " .. err, "err")
      else
        UI.show_float_toast("No matching plugins found", "err")
        pref_plugins.pending_exit = true
      end
    end
    scan.cache = nil
    return
  end

  -- Phase 1: create temp track and add all plugins.
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  if not tr then
    reaper.PreventUIRefresh(-1)
    scan.status = ""
    UI.show_float_toast("Scan failed: couldn't create temp track", "err")
    reaper.Undo_EndBlock("ReaAssist: scan (failed)", 0)
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

  scan.active = true
  scan.phase  = "reading"  -- will be processed on the next loop() frame
  scan.status = "Scanning parameters..."
end

-- Phase 2: read parameters from all added plugins using the unified scanner,
-- cache to JSON, then clean up.
-- Called from the main loop on the frame AFTER scan_start.
function CTX.pref_plugins_scan_read()
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
    UI.show_float_toast("Scan failed: temp track lost", "err")
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: scan (failed)", 0)
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
  -- track + a stuck PreventUIRefresh(-1) imbalance + an unclosed Undo block.
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
  -- flags=0 (instead of -1) explicitly discards the block so the temp-track
  -- insert + probe writes + delete never enter the user's undo history.
  -- The earlier pattern relied on Undo_EndBlock(-1) + Undo_DoUndo2(0), which
  -- walks back one slot -- safe only when REAPER's heuristic actually
  -- registered this block. If it didn't (net-zero change detection), the
  -- DoUndo2 would walk into the user's previous action.
  reaper.Undo_EndBlock("ReaAssist: preferred plugins scan", 0)

  -- Save the unified JSON cache.
  local err = FXCache.save(cache)
  scan.active = false
  scan.phase  = "done"
  scan.cache  = nil  -- release stashed reference
  if err then
    scan.status = err
    UI.show_float_toast("Save failed", "err")
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
      local msg = "Saved (" .. #skipped_idents .. " skipped: " .. preview
      if more > 0 then msg = msg .. ", +" .. more .. " more" end
      msg = msg .. ")"
      UI.show_float_toast(msg, "err")
    else
      UI.show_float_toast("Preferences saved", "ok")
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
function CTX.preempt_buckets_for_prompt(user_text)
  if not user_text or user_text == "" then return {} end
  local text = user_text:lower()
  local cache = FXCache.load()
  local pref_types = cache.preferred_types or {}
  -- Dev-only: when the FabFilter-hide flag is on, treat matching entries
  -- in preferred_types as absent so the preempt path falls through to
  -- "no pref set" behavior (emits resolve:<type> and fires the popup we
  -- want to test). Read the flag fresh from ExtState rather than prefs
  -- so it stays current even if the dev_signal refresh didn't reach the
  -- main loop. Matches the same gate applied in CTX.preferred_plugins
  -- and CTX.load_pref_plugins.
  local hide_ff = reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
  local injected = {}
  -- Sorted key iteration for deterministic sticky_context ordering (keeps
  -- provider caches stable across turns when the same set of types hits).
  local keys = {}
  for k in pairs(pref_types) do keys[#keys+1] = k end
  table.sort(keys)
  -- Identifier -> curated plugin_ref section name. When the user's saved
  -- preference for a type points at one of these, prefer the curated
  -- plugin_ref content (golden-ratio recipes, per-band examples) over the
  -- live-scanned preferred_plugins block (just raw param values). Extend
  -- this map as more curated plugins get added to Plugin_Ref.md.
  -- Maps chain-entry identifiers (as stored in preferred_types) to the
  -- matching curated section name in Plugin_Ref.md. Entries here trigger
  -- plugin_ref:<Name> preempt injection instead of the thinner live-scan
  -- preferred_plugins:<type>. Chain entries that aren't in this map fall
  -- through to live-scan fallback.
  local CURATED_IDENT = {
    -- Stock plugins. Multiple ReEQ keys because REAPER's EnumInstalledFX
    -- returns the JSFX file path on Windows ("JS: ReJJ/ReEQ/ReEQ.jsfx")
    -- but the JSFX `desc:` line on macOS ("JS: ReEQ - Parametric Graphic
    -- Equalizer"); whichever string the user picks from the Pref Plugins
    -- autocomplete becomes the saved pref_types value, and we need to
    -- recognise both forms (with and without the "JS: " prefix that the
    -- save path may or may not strip) so the curated plugin_ref:ReEQ
    -- content fires regardless of platform.
    ["ReJJ/ReEQ/ReEQ.jsfx"]                       = "ReEQ",
    ["JS: ReJJ/ReEQ/ReEQ.jsfx"]                   = "ReEQ",
    ["ReEQ - Parametric Graphic Equalizer"]       = "ReEQ",
    ["JS: ReEQ - Parametric Graphic Equalizer"]   = "ReEQ",
    ["ReaEQ"]               = "ReaEQ",
    ["ReaComp"]             = "ReaComp",
    ["ReaXcomp"]            = "ReaXcomp",
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
  for _, tkey in ipairs(keys) do
    -- Word-boundary match so "eq" doesn't fire on "equal" / "sequence".
    -- %b pattern wouldn't help here; %f[%w] + %f[%W] brackets catch whole
    -- words including hyphenated ones like "de-esser".
    local pat = "%f[%w]" .. tkey:gsub("(%W)", "%%%1") .. "%f[%W]"
    if text:find(pat) then
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
      local curated = ident and CURATED_IDENT[ident] or nil
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
            -- Resolve the chain entry to the exact enumerated identifier
            -- (e.g. "Pro-Q 4" -> "VST3: Pro-Q 4") so the model uses the
            -- format-prefixed form. populate_installed_fx is cached -- the
            -- first preempt pays the one-time enumeration walk.
            CTX.populate_installed_fx()
            local exact_ident = nil
            if Code.resolve_chain_entry and CTX._installed_fx_list then
              exact_ident = Code.resolve_chain_entry(ident, CTX._installed_fx_list)
            end
            local prefix = ""
            if exact_ident and exact_ident ~= ident then
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
            injected[#injected+1] = pr_key
            Log.line("PREEMPT",
              "injected " .. pr_key .. " (curated content, keyword match)"
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
              local hint = "PREFERRED PLUGINS:\n"
                .. "  " .. tkey .. " = " .. (exact_ident or ident or curated) .. "\n"
                .. "(User's saved preference; full parameter reference above "
                .. "in plugin_ref:" .. curated .. ". Use this plugin directly "
                .. "and do NOT emit <context_needed>resolve:" .. tkey
                .. "</context_needed>.)"
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
            Net.sticky_set(pp_key, pp_content)
            -- Mark sent so the model's <context_needed>preferred_plugins:tkey
            -- (if it emits one anyway) gets deduped by the bucket dispatcher.
            if S.pref_plugins_sent then S.pref_plugins_sent[tkey] = true end
            -- Co-pin plugin bundle (same rationale as the plugin_ref branch
            -- above: every pref-plugin pin drives a plugin task).
            Net.copin_plugin_bundle(injected)
            injected[#injected+1] = pp_key
            Log.line("PREEMPT",
              "injected " .. pp_key .. " (keyword match in user prompt)")
          end
        end
      end
    end
    ::continue_preempt::
  end
  return injected
end

CTX.build_snapshot = function(proj)
  local state_count = reaper.GetProjectStateChangeCount(proj or 0)
  local c = CTX._snapshot_heavy_cache
  local tracks_txt, markers_txt
  if c and c.proj == proj and c.state_count == state_count then
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
    CTX.tempo(proj),
    CTX.sample_rate(proj),
    CTX.play_state(proj),
    CTX.loop(proj),
    markers_txt,
    tracks_txt,
    CTX.selected(proj),
    CTX.time_selection(proj),
    CTX.cursor(proj),
    CTX.selected_items(proj),
  }
  -- Multi-row sections (Tracks, FX chains, Track flags, Markers/regions,
  -- Selected items) use a compact pipe-delimited format with a header row
  -- declaring the columns. This shaves ~15-25% snapshot tokens on large
  -- sessions vs the previous prose form. Single-value lines remain
  -- human-readable. Pipe characters in track names are scrubbed to "_" to
  -- keep parsing trivial.
  return "SESSION CONTEXT (multi-row sections use pipe-delimited rows -- "
    .. "see each section's [col|col|...] header for column names):\n"
    .. tbl_concat(parts, "\n") .. "\n\n"
end

-- =============================================================================
-- JSON helpers
-- =============================================================================
-- Sanitises a Lua byte string into valid UTF-8 by replacing any invalid byte
-- sequences with '?'. REAPER allows raw 8-bit bytes in track names, item
-- notes, and marker labels (often a result of dragged-in corrupt audio files
-- or weird VST presets), and the AI provider APIs reject any payload that
-- isn't strict UTF-8 with a 400 Bad Request.
--
-- Validates the four legal multi-byte forms (per RFC 3629):
--   1-byte: 0xxxxxxx
--   2-byte: 110xxxxx 10xxxxxx              (U+0080..U+07FF)
--   3-byte: 1110xxxx 10xxxxxx 10xxxxxx     (U+0800..U+FFFF, excluding surrogates)
--   4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx (U+10000..U+10FFFF)
-- Single-pass byte scan, no allocations on the happy path (string is returned
-- unchanged when it is already valid UTF-8).
local function sanitize_utf8(s)
  local len = #s
  local i = 1
  local out = nil  -- lazily allocated only if we hit invalid bytes
  while i <= len do
    local b1 = str_byte(s, i)
    local size, ok = 1, true
    if b1 < 0x80 then
      -- ASCII
      size = 1
    elseif b1 < 0xC2 then
      -- Continuation byte or overlong 2-byte form: invalid as a leading byte
      ok = false
    elseif b1 < 0xE0 then
      -- 2-byte sequence
      size = 2
      if i + 1 > len then ok = false
      else
        local b2 = str_byte(s, i + 1)
        if b2 < 0x80 or b2 > 0xBF then ok = false end
      end
    elseif b1 < 0xF0 then
      -- 3-byte sequence
      size = 3
      if i + 2 > len then ok = false
      else
        local b2 = str_byte(s, i + 1)
        local b3 = str_byte(s, i + 2)
        if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then
          ok = false
        elseif b1 == 0xE0 and b2 < 0xA0 then
          ok = false  -- overlong
        elseif b1 == 0xED and b2 > 0x9F then
          ok = false  -- UTF-16 surrogate half
        end
      end
    elseif b1 < 0xF5 then
      -- 4-byte sequence
      size = 4
      if i + 3 > len then ok = false
      else
        local b2 = str_byte(s, i + 1)
        local b3 = str_byte(s, i + 2)
        local b4 = str_byte(s, i + 3)
        if b2 < 0x80 or b2 > 0xBF
           or b3 < 0x80 or b3 > 0xBF
           or b4 < 0x80 or b4 > 0xBF then
          ok = false
        elseif b1 == 0xF0 and b2 < 0x90 then
          ok = false  -- overlong
        elseif b1 == 0xF4 and b2 > 0x8F then
          ok = false  -- > U+10FFFF
        end
      end
    else
      ok = false  -- 0xF5..0xFF: never valid
    end

    if ok then
      if out then out[#out+1] = str_sub(s, i, i + size - 1) end
      i = i + size
    else
      if not out then
        out = {}
        if i > 1 then out[1] = str_sub(s, 1, i - 1) end
      end
      out[#out+1] = "?"
      i = i + 1
    end
  end
  if out then return tbl_concat(out) end
  return s
end
JSON.sanitize_utf8 = sanitize_utf8

-- Escapes a Lua string for safe embedding inside a JSON string value.
-- Order matters: backslashes must be escaped first.
-- Also escapes control characters below 0x20 (backspace, form feed,
-- null bytes, etc.) that can appear in track names or user input and would
-- produce invalid JSON, causing silent API call failures. Invalid UTF-8 byte
-- sequences are replaced with '?' so the API never sees malformed payloads.
function JSON.escape(s)
  return sanitize_utf8(s)
           :gsub('\\', '\\\\')
           :gsub('"',  '\\"')
           :gsub('\n', '\\n')
           :gsub('\r', '\\r')
           :gsub('\t', '\\t')
           :gsub('[\x00-\x08\x0b\x0c\x0e-\x1f]', function(c)
             -- Encode remaining control chars as \u00XX JSON unicode escapes.
             return str_format('\\u%04x', str_byte(c))
           end)
end

-- =============================================================================
-- Minimal recursive-descent JSON decoder
-- =============================================================================
-- Proper parser that handles the full JSON spec: objects, arrays, strings
-- (with all escape sequences including \uXXXX), numbers, booleans, and null.
--
-- The decoder returns a native Lua table/value on success, or nil + error
-- string on malformed input. It never throws.
--
-- JSON null is represented by the sentinel table JSON.NULL rather than Lua nil.
-- This prevents silent key loss when a JSON object contains {"key": null},
-- since obj[key] = nil is a no-op in Lua. Callers should compare values
-- against JSON.NULL when null-awareness matters.
--
-- Performance: single-pass, no string copying for non-string values, avoids
-- gsub inside the hot path. Fast enough for the response sizes we handle
-- (typically 1-20 KB).
do
  -- Forward declarations for mutual recursion.
  local decode_value, decode_string, decode_number, decode_object, decode_array

  -- Skip whitespace and return the next non-whitespace position.
  local function skip_ws(s, pos)
    return str_match(s, "^%s*()", pos)
  end

  -- Decode a JSON string starting at the opening quote.
  -- Returns (lua_string, next_position) or (nil, error_string).
  decode_string = function(s, pos)
    -- pos points to the opening '"'
    pos = pos + 1  -- skip opening quote
    local len = #s
    local buf = {}
    while pos <= len do
      local ch = str_sub(s, pos, pos)
      if ch == '"' then
        return tbl_concat(buf), pos + 1
      elseif ch == '\\' then
        pos = pos + 1
        if pos > len then return nil, "unterminated string escape" end
        local esc = str_sub(s, pos, pos)
        if     esc == 'n'  then buf[#buf+1] = '\n'
        elseif esc == 't'  then buf[#buf+1] = '\t'
        elseif esc == 'r'  then buf[#buf+1] = '\r'
        elseif esc == '"'  then buf[#buf+1] = '"'
        elseif esc == '\\' then buf[#buf+1] = '\\'
        elseif esc == '/'  then buf[#buf+1] = '/'
        elseif esc == 'b'  then buf[#buf+1] = '\b'
        elseif esc == 'f'  then buf[#buf+1] = '\f'
        elseif esc == 'u'  then
          -- \uXXXX unicode escape. Decode to UTF-8 bytes.
          -- Handles surrogate pairs (\uD800-\uDFFF) for emoji/CJK.
          local hex = str_sub(s, pos + 1, pos + 4)
          local cp  = tonumber(hex, 16)
          if not cp then
            buf[#buf+1] = '\\u' .. hex
          else
            -- Surrogate pair: high surrogate followed by \uXXXX low surrogate.
            if cp >= 0xD800 and cp <= 0xDBFF then
              local lo_hex = str_sub(s, pos + 5, pos + 10)
              if str_sub(lo_hex, 1, 2) == "\\u" then
                local lo_cp = tonumber(str_sub(lo_hex, 3, 6), 16)
                if lo_cp and lo_cp >= 0xDC00 and lo_cp <= 0xDFFF then
                  cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo_cp - 0xDC00)
                  pos = pos + 6  -- skip the low surrogate
                end
              end
            end
            -- Encode codepoint as UTF-8.
            if cp < 0x80 then
              buf[#buf+1] = str_char(cp)
            elseif cp < 0x800 then
              buf[#buf+1] = str_char(0xC0 + math_floor(cp / 64),
                                     0x80 + cp % 64)
            elseif cp < 0x10000 then
              buf[#buf+1] = str_char(0xE0 + math_floor(cp / 4096),
                                     0x80 + math_floor(cp / 64) % 64,
                                     0x80 + cp % 64)
            else
              buf[#buf+1] = str_char(0xF0 + math_floor(cp / 262144),
                                     0x80 + math_floor(cp / 4096) % 64,
                                     0x80 + math_floor(cp / 64) % 64,
                                     0x80 + cp % 64)
            end
          end
          pos = pos + 4
        else
          -- Unknown escape: preserve as-is for debugging.
          buf[#buf+1] = '\\' .. esc
        end
      else
        buf[#buf+1] = ch
      end
      pos = pos + 1
    end
    return nil, "unterminated string"
  end

  -- Decode a JSON number. Returns (number, next_position).
  decode_number = function(s, pos)
    local num_str = str_match(s, "^-?%d+%.?%d*[eE]?[+-]?%d*()", pos)
    if not num_str then return nil, "invalid number" end
    local val = tonumber(str_sub(s, pos, num_str - 1))
    if not val then return nil, "invalid number" end
    return val, num_str
  end

  -- Decode a JSON object. Returns (table, next_position).
  decode_object = function(s, pos)
    pos = pos + 1  -- skip '{'
    local obj = {}
    pos = skip_ws(s, pos)
    if str_sub(s, pos, pos) == '}' then return obj, pos + 1 end
    while true do
      pos = skip_ws(s, pos)
      if str_sub(s, pos, pos) ~= '"' then return nil, "expected string key" end
      local key, next_pos = decode_string(s, pos)
      if not key then return nil, next_pos end
      pos = skip_ws(s, next_pos)
      if str_sub(s, pos, pos) ~= ':' then return nil, "expected ':'" end
      pos = skip_ws(s, pos + 1)
      local val
      val, pos = decode_value(s, pos)
      if val == nil and type(pos) == "string" then return nil, pos end
      obj[key] = val
      pos = skip_ws(s, pos)
      local sep = str_sub(s, pos, pos)
      if sep == '}' then return obj, pos + 1 end
      if sep ~= ',' then return nil, "expected ',' or '}'" end
      pos = pos + 1
    end
  end

  -- Decode a JSON array. Returns (table, next_position).
  decode_array = function(s, pos)
    pos = pos + 1  -- skip '['
    local arr = {}
    pos = skip_ws(s, pos)
    if str_sub(s, pos, pos) == ']' then return arr, pos + 1 end
    while true do
      pos = skip_ws(s, pos)
      local val
      val, pos = decode_value(s, pos)
      if val == nil and type(pos) == "string" then return nil, pos end
      arr[#arr+1] = val
      pos = skip_ws(s, pos)
      local sep = str_sub(s, pos, pos)
      if sep == ']' then return arr, pos + 1 end
      if sep ~= ',' then return nil, "expected ',' or ']'" end
      pos = pos + 1
    end
  end

  -- Decode any JSON value. Top-level dispatch.
  decode_value = function(s, pos)
    pos = skip_ws(s, pos)
    local ch = str_sub(s, pos, pos)
    if ch == '"' then return decode_string(s, pos)
    elseif ch == '{' then return decode_object(s, pos)
    elseif ch == '[' then return decode_array(s, pos)
    elseif ch == 't' then
      if str_sub(s, pos, pos + 3) == "true" then return true, pos + 4 end
      return nil, "invalid value"
    elseif ch == 'f' then
      if str_sub(s, pos, pos + 4) == "false" then return false, pos + 5 end
      return nil, "invalid value"
    elseif ch == 'n' then
      if str_sub(s, pos, pos + 3) == "null" then return JSON.NULL, pos + 4 end
      return nil, "invalid value"
    elseif ch == '-' or (ch >= '0' and ch <= '9') then
      return decode_number(s, pos)
    else
      return nil, "unexpected character: " .. ch
    end
  end

  -- Public API: decode a JSON string into a Lua value.
  -- Returns (value, nil) on success, or (nil, error_string) on failure.
  -- Wrapped in pcall as a final safety net against any unforeseen edge case.
  JSON.decode = function(s)
    if type(s) ~= "string" or #s == 0 then
      return nil, "empty or non-string input"
    end
    local ok, result, next_pos = pcall(decode_value, s, 1)
    if not ok then return nil, tostring(result) end
    if result == nil and type(next_pos) == "string" then
      return nil, next_pos
    end
    return result, nil
  end
end

-- =============================================================================
-- Minimal recursive JSON encoder
-- =============================================================================
-- Encodes Lua values into compact or pretty-printed JSON strings.
-- Handles strings, numbers, booleans, nil, JSON.NULL, and tables
-- (auto-detects array vs object by checking sequential integer keys).
do
  local function is_array(t)
    local n = #t
    if n == 0 then
      -- Empty table: always encode as {} (object), never [].
      -- In this codebase empty tables are dictionaries, not empty arrays.
      return false
    end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == n
  end

  local encode_value  -- forward declaration

  local function encode_string(s)
    return '"' .. JSON.escape(s) .. '"'
  end

  local function encode_number(n)
    if n ~= n then return '"NaN"' end             -- NaN safety
    if n == math.huge then return '"Infinity"' end
    if n == -math.huge then return '"-Infinity"' end
    if math.floor(n) == n and math.abs(n) < 2^53 then
      return str_format("%d", n)
    end
    return str_format("%.4f", n)
  end

  local function encode_array(t, indent, depth)
    if #t == 0 then return "[]" end
    local parts = {}
    for i = 1, #t do
      parts[i] = encode_value(t[i], indent, depth)
    end
    if indent then
      local pad = string.rep(indent, depth)
      local inner_pad = string.rep(indent, depth + 1)
      return "[\n" .. inner_pad .. tbl_concat(parts, ",\n" .. inner_pad) .. "\n" .. pad .. "]"
    end
    return "[" .. tbl_concat(parts, ",") .. "]"
  end

  local function encode_object(t, indent, depth)
    local parts = {}
    -- Collect and sort keys for deterministic output.
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    for _, k in ipairs(keys) do
      local ks = type(k) == "string" and encode_string(k) or ('"' .. tostring(k) .. '"')
      local vs = encode_value(t[k], indent, depth)
      if indent then
        parts[#parts+1] = ks .. ": " .. vs
      else
        parts[#parts+1] = ks .. ":" .. vs
      end
    end
    if #parts == 0 then return "{}" end
    if indent then
      local pad = string.rep(indent, depth)
      local inner_pad = string.rep(indent, depth + 1)
      return "{\n" .. inner_pad .. tbl_concat(parts, ",\n" .. inner_pad) .. "\n" .. pad .. "}"
    end
    return "{" .. tbl_concat(parts, ",") .. "}"
  end

  encode_value = function(v, indent, depth)
    depth = depth or 0
    if v == nil or v == JSON.NULL then return "null" end
    local tv = type(v)
    if tv == "string"  then return encode_string(v) end
    if tv == "number"  then return encode_number(v) end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "table"   then
      if is_array(v) then
        return encode_array(v, indent, depth + 1)
      else
        return encode_object(v, indent, depth + 1)
      end
    end
    return '"' .. tostring(v) .. '"'
  end

  -- Public API: encode a Lua value into a JSON string.
  -- Pass indent string (e.g. "  ") for pretty-printing, or nil for compact.
  JSON.encode = function(value, indent)
    local ok, result = pcall(encode_value, value, indent, 0)
    if not ok then return nil, tostring(result) end
    return result, nil
  end
end

-- =============================================================================
-- Auto-update module
-- =============================================================================
-- Non-blocking update checker. On startup (when prefs.update_check is on
-- and UPDATE_BASE_URL is configured) fires an async curl for manifest.json;
-- if a newer version exists the UI offers "Update Available". Each file
-- is fetched, SHA-256 verified against the manifest, and written to the
-- script directory (any hash mismatch rolls back the whole update). An
-- organic check failure stays silent (update.state = "idle"); only a
-- user-forced Repair surfaces errors via Updater._set_failure.
-- Manifest schema: see .tools/gen_manifest.py.

-- =============================================================================
-- SHA-256 (pure Lua, no external dependencies)
-- =============================================================================
-- Minimal implementation for update integrity verification. Operates on
-- 8-bit byte strings via string.byte. Lua 5.3+ bitwise operators; loaded
-- via load() so this whole block parses cleanly on older linters too.
--
-- Two interfaces:
--   sha256_hash(msg)              -- single-shot. Used by download_poll
--                                    where each file is small and gets
--                                    hashed once after a successful write.
--   _SHA.create(content)          -- chunked: returns state ready for step().
--   _SHA.step(state, max_blocks)  -- process up to N 64-byte blocks; returns
--                                    true when state is exhausted.
--   _SHA.finalize(state)          -- return hex digest of completed state.
--
-- Pure-Lua SHA-256 throughput on commodity hardware sits around ~1 MB/s
-- on Lua 5.4. The two largest manifest files (ReaAssist.lua and
-- ReaAssist_UI.lua, ~700 KB each) take 600+ ms each in single-shot mode
-- which is a visible REAPER hitch. The chunked interface lets
-- Updater.tick_sha_diff process work for a per-frame time budget
-- (CFG.UPDATE_SHA_TIME_BUDGET), spreading the same total work across
-- many frames so each frame stays inside the budget regardless of CPU.
local sha256_hash
local _SHA = {}
do
  local band   = load("return function(a,b) return a & b end")()
  local bor    = load("return function(a,b) return a | b end")()
  local bxor   = load("return function(a,b) return a ~ b end")()
  local bnot   = load("return function(a) return ~a & 0xFFFFFFFF end")()
  local rshift = load("return function(a,n) return (a >> n) & 0xFFFFFFFF end")()
  local lshift = load("return function(a,n) return (a << n) & 0xFFFFFFFF end")()

  local function rrotate(x, n) return bor(rshift(x, n), lshift(x, 32 - n)) end

  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }

  -- Build incremental state from a plain content string. Pre-pads the
  -- message to a 64-byte boundary so subsequent step() calls only need
  -- to compress complete 64-byte blocks (no partial-block bookkeeping
  -- across calls). Pre-padding cost is O(n) memcpy, negligible vs the
  -- compression work that follows.
  function _SHA.create(content)
    local len = #content
    local extra = 64 - ((len + 9) % 64)
    if extra == 64 then extra = 0 end
    local msg = content .. "\128" .. ("\0"):rep(extra + 4)
       .. string.char(
            band(rshift(len * 8, 24), 0xFF),
            band(rshift(len * 8, 16), 0xFF),
            band(rshift(len * 8, 8), 0xFF),
            band(len * 8, 0xFF))
    return {
      msg = msg,
      pos = 1,                        -- next byte (1-indexed) to compress
      h0  = 0x6a09e667, h1 = 0xbb67ae85,
      h2  = 0x3c6ef372, h3 = 0xa54ff53a,
      h4  = 0x510e527f, h5 = 0x9b05688c,
      h6  = 0x1f83d9ab, h7 = 0x5be0cd19,
    }
  end

  -- Process up to max_blocks complete 64-byte chunks starting at
  -- state.pos. Updates state.h0..h7 and advances state.pos. Returns
  -- true when all blocks have been compressed (state ready for
  -- finalize), false when more remain. Pass math.huge to drain all
  -- remaining blocks in one call (single-shot mode).
  function _SHA.step(state, max_blocks)
    local msg = state.msg
    local total = #msg
    local h0, h1, h2, h3 = state.h0, state.h1, state.h2, state.h3
    local h4, h5, h6, h7 = state.h4, state.h5, state.h6, state.h7
    local pos = state.pos
    local processed = 0
    while pos <= total and processed < max_blocks do
      local W = {}
      for t = 1, 16 do
        local b = pos + (t - 1) * 4
        W[t] = lshift(string.byte(msg, b), 24)
             + lshift(string.byte(msg, b + 1), 16)
             + lshift(string.byte(msg, b + 2), 8)
             + string.byte(msg, b + 3)
      end
      for t = 17, 64 do
        local s0 = bxor(rrotate(W[t-15], 7),
                        bxor(rrotate(W[t-15], 18), rshift(W[t-15], 3)))
        local s1 = bxor(rrotate(W[t-2], 17),
                        bxor(rrotate(W[t-2], 19), rshift(W[t-2], 10)))
        W[t] = (W[t-16] + s0 + W[t-7] + s1) % 0x100000000
      end
      local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
      for t = 1, 64 do
        local S1 = bxor(rrotate(e, 6),
                        bxor(rrotate(e, 11), rrotate(e, 25)))
        local ch = bxor(band(e, f), band(bnot(e), g))
        local temp1 = (h + S1 + ch + K[t] + W[t]) % 0x100000000
        local S0 = bxor(rrotate(a, 2),
                        bxor(rrotate(a, 13), rrotate(a, 22)))
        local maj = bxor(band(a, b), bxor(band(a, c), band(b, c)))
        local temp2 = (S0 + maj) % 0x100000000
        h = g; g = f; f = e; e = (d + temp1) % 0x100000000
        d = c; c = b; b = a; a = (temp1 + temp2) % 0x100000000
      end
      h0 = (h0 + a) % 0x100000000; h1 = (h1 + b) % 0x100000000
      h2 = (h2 + c) % 0x100000000; h3 = (h3 + d) % 0x100000000
      h4 = (h4 + e) % 0x100000000; h5 = (h5 + f) % 0x100000000
      h6 = (h6 + g) % 0x100000000; h7 = (h7 + h) % 0x100000000
      pos = pos + 64
      processed = processed + 1
    end
    state.h0, state.h1, state.h2, state.h3 = h0, h1, h2, h3
    state.h4, state.h5, state.h6, state.h7 = h4, h5, h6, h7
    state.pos = pos
    return pos > total
  end

  function _SHA.finalize(state)
    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
      state.h0, state.h1, state.h2, state.h3,
      state.h4, state.h5, state.h6, state.h7)
  end

  sha256_hash = function(msg)
    local s = _SHA.create(msg)
    _SHA.step(s, math.huge)
    return _SHA.finalize(s)
  end
end

-- Cross-chunk namespace. The UI file's Update-Available and File-
-- Integrity dialogs call Updater.download_start / Updater.force_reinstall,
-- so this table must be a plain global (chunk-local `local` would make
-- it invisible to the dofile'd UI chunk). The state table next to it is
-- lowercase `update`.
Updater = {}

-- Stamp a structured failure reason onto the update state so the
-- Bootstrap repair prompt can show the user *why* the last attempt
-- failed instead of silently re-rendering the Repair button. Also
-- emits a Log.line so Resources/ReaAssist_Debug.log records the same
-- detail for post-mortem.
function Updater._set_failure(step, err)
  update.last_step  = step
  update.last_error = err
  Log.line("UPDATE", string.format("fail [%s]: %s",
                                   tostring(step), tostring(err)))
end

-- True when the updater is mid-flight on a fetch, verification, download,
-- or rename. Centralises the four-state predicate that gates re-entry on
-- force_reinstall, manual_check, the chat-piggyback check_start, and the
-- UI's ver_busy / busy disabled-button flags. A single helper means a
-- future state addition only needs to land in one place rather than five
-- separate condition lists.
function Updater.is_busy()
  return update.state == "checking"
      or update.state == "verifying"
      or update.state == "downloading"
      or update.state == "rename_retry"
end

-- Compare two semver strings numerically. Returns true if remote > local.
function Updater.is_newer(remote_ver, local_ver)
  local function parse(v)
    local parts = {}
    for n in v:gmatch("(%d+)") do parts[#parts+1] = tonumber(n) end
    return parts
  end
  local r, l = parse(remote_ver), parse(local_ver)
  for i = 1, math_max(#r, #l) do
    local rv, lv = r[i] or 0, l[i] or 0
    if rv > lv then return true end
    if rv < lv then return false end
  end
  return false
end

-- Fire an async curl GET. Writes response to out_path, exit code to exit_path.
-- Returns true if launched, false if URL is empty or launch fails.
function Updater.fire_get(url, out_path, exit_path)
  if not url or url == "" then return false end
  os.remove(out_path)
  os.remove(exit_path)
  -- Cache-busting: append a unix-time query parameter to the URL.
  -- GitHub's raw CDN keys on URL, so a unique timestamp guarantees a
  -- cache miss on every check. This eliminates the propagation race we
  -- have hit during rapid test-branch iteration where a new manifest
  -- and its updated file SHAs can be cached separately, leading to
  -- false repair popups on first launch after an update push.
  --
  -- We previously also sent Cache-Control / Pragma no-cache headers,
  -- but on Windows the literal double quotes around those header
  -- values broke the outer PowerShell -Command argument parse: the
  -- inner `"` terminated PowerShell's -Command string early, curl
  -- never ran, and the manual update check toasted "Could not reach
  -- update server" on every press. The timestamp query alone is
  -- sufficient (a CDN cannot serve a cached response for a URL it has
  -- never seen before), so the headers were dropped.
  local sep = url:find("?", 1, true) and "&" or "?"
  -- Cache-bust query: combine os.time() seconds with time_precise()
  -- millisecond fraction so two fetches inside the same second still
  -- produce distinct URLs. Pure os.time() collides on rapid Retry
  -- clicks (the v0.9.8.22 CDN-propagation fix encourages users to
  -- click Retry repeatedly), and a duplicate URL re-hits whatever
  -- the CDN has cached for that key, defeating the whole point.
  local ms = math.floor((time_precise() % 1) * 1000)
  url = url .. sep .. "_=" .. tostring(os.time())
                  .. string.format("%03d", ms)
  local timeout = CFG.UPDATE_CURL_TIMEOUT
  if RA.IS_WINDOWS then
    -- Defensive: a literal " in url / out_path / exit_path would
    -- terminate the inner cmd shell's quoted arguments early and
    -- break PowerShell's outer -Command parse. Today's URL contains
    -- only digits in its query string and the temp paths come from
    -- RA.script_path, but reject defensively rather than silently
    -- launching a malformed command.
    if url:find('"', 1, true)
        or out_path:find('"', 1, true)
        or exit_path:find('"', 1, true) then
      Log.line("UPDATE",
        "fire_get: refusing to launch with literal '\"' in URL or path")
      return false
    end
    local function ps_escape(p) return p:gsub("'", "''") end
    local cmd_line = str_format(
      'curl -s --connect-timeout 10 --max-time %d'
      .. ' "%s" -o """%s"""'
      .. ' & echo %%errorlevel%% > """%s"""',
      timeout, url, out_path, exit_path)
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden"',
      ps_escape(cmd_line))
    reaper.ExecProcess(ps_cmd, 5000)
  else
    local function sq(p) return "'" .. p:gsub("'", "'\\''") .. "'" end
    -- Single-quote the URL on POSIX shells. Double quotes still allow
    -- $(...) and `...` command substitution, so a malicious or malformed
    -- manifest filename baked into the URL could execute. is_safe_filename
    -- already blocks shell-sensitive characters, but quoting cleanly here
    -- closes the gap as defense-in-depth.
    local cmd = str_format(
      '(curl -s --connect-timeout 10 --max-time %d'
      .. ' %s -o %s ; echo $? > %s) &',
      timeout, sq(url), sq(out_path), sq(exit_path))
    os.execute(cmd)
  end
  -- NOTE: Neither ExecProcess nor os.execute reliably indicate launch failure,
  -- so send_time is set unconditionally. If the process never started, the
  -- watchdog in Updater.poll() will time out after UPDATE_CURL_TIMEOUT + 10s.
  update.send_time = time_precise()
  return true
end

-- Poll for completion of the current async curl. Returns "done", "waiting", or "error".
function Updater.poll()
  if not update.send_time then return "error" end
  -- Watchdog: give up after timeout + generous slack.
  if (time_precise() - update.send_time) > (CFG.UPDATE_CURL_TIMEOUT + 10) then
    return "error"
  end
  local ok_ef, ef = pcall(io.open, tmp.update_exit, "r")
  if not ok_ef or not ef then return "waiting" end
  local exit_str = ef:read("*a"); ef:close()
  local exit_code = tonumber(exit_str:match("(%d+)"))
  if not exit_code then return "waiting" end
  if exit_code ~= 0 then return "error" end
  return "done"
end

-- Read and parse the response file. Returns parsed table or nil.
function Updater.read_response()
  local ok_f, f = pcall(io.open, tmp.update_out, "r")
  if not ok_f or not f then return nil end
  local raw = f:read("*a"); f:close()
  if not raw or #raw < 2 then return nil end
  local data, err = JSON.decode(raw)
  if not data or type(data) ~= "table" then return nil end
  return data
end

-- Force a reinstall: bypass version check, daily cap, and snooze.
-- Re-entry guard: bail when a curl is already in flight. Without it, a
-- double-click on Bootstrap's Repair button (which stays rendered during
-- "checking" because Bootstrap's state dispatcher falls through to
-- render_prompt on unknown states) would double-fire the curl while the
-- first one is still writing to tmp.update_out / tmp.update_exit,
-- corrupting the read.
function Updater.force_reinstall()
  if CFG.UPDATE_BASE_URL == "" then return false end
  if Updater.is_busy() then return false end
  update.force = true
  update.popup_opened = false
  -- Clear stale failure metadata from a previous attempt. Without this,
  -- a Retry-after-failed click inherits the prior failure's last_step /
  -- last_error / repair_missing / repair_mismatched / action_was_repair
  -- values until the new check_poll result lands. The Update Failed
  -- dialog branches its copy on update.last_step (sha_verify gets the
  -- CDN-propagation message; everything else gets the generic copy), so
  -- a brief frame with a stale last_step could flash the wrong message.
  -- Mirror download_start's clean-slate pattern (download_queue,
  -- applied_files, skipped_count) for the failure-display fields too.
  update.last_step         = nil
  update.last_error        = nil
  update.repair_missing    = nil
  update.repair_mismatched = nil
  update.action_was_repair = nil
  local url = CFG.UPDATE_BASE_URL .. "/" .. CFG.UPDATE_MANIFEST
  if Updater.fire_get(url, tmp.update_out, tmp.update_exit) then
    update.state = "checking"
    return true
  end
  return false
end

-- Start the manifest check. Called from loop() on the first idle->waiting
-- chat-send edge in the session, so PowerShell is already warm from the
-- chat's curl and this check's ExecProcess cost is ~200ms instead of
-- 1-3s cold. No 24h throttle: the session flag
-- `update._session_check_fired` already prevents multiple fires per
-- session, and gating the fetch itself would prevent repair detection
-- too; we NEED a fresh manifest every session to compute the local-
-- vs-remote SHA diff. The update-nag snooze is honored lower in the
-- pipeline (check_poll's available branch) so it only suppresses the
-- "Update Available" popup, never the repair flow. Stamp
-- update_last_check here so any future consumer that wants a "time of
-- most recent successful fetch" reading has one.
function Updater.check_start()
  if CFG.UPDATE_BASE_URL == "" then return end
  if not prefs.update_check then return end
  -- Busy guard: the chat-piggyback fires on the first idle->waiting
  -- transition of the session, but a user could already have launched
  -- a manual Check / Repair in the same window. Without this guard the
  -- piggyback would fire a second curl that shares tmp.update_out /
  -- tmp.update_exit with the in-flight one, racing the manifest check
  -- against a download and corrupting the read.
  if Updater.is_busy() then return end
  reaper.SetExtState(CFG.EXT_NS, "update_last_check",
    tostring(os.time()), true)
  local url = CFG.UPDATE_BASE_URL .. "/" .. CFG.UPDATE_MANIFEST
  if Updater.fire_get(url, tmp.update_out, tmp.update_exit) then
    update.state = "checking"
  end
end

-- User-initiated check, wired to the "Check for Updates" button in
-- Settings. Bypasses the 24h throttle and the snooze (user is explicitly
-- asking), but unlike force_reinstall does NOT set update.force = true:
-- if the server is on the same version and SHAs match, we want to show
-- a friendly "You're up to date" toast instead of misleadingly offering
-- a reinstall. Bumps the throttle timestamp so the chat-piggyback does
-- not immediately re-fire the check on the user's next send.
function Updater.manual_check()
  if CFG.UPDATE_BASE_URL == "" then
    UI.show_float_toast("Update URL not configured", "err")
    return false
  end
  if Updater.is_busy() then return false end
  reaper.SetExtState(CFG.EXT_NS, "update_last_check",
    tostring(os.time()), true)
  update._manual = true
  -- Reset popup_opened so the "Update Available" dialog re-fires when
  -- this manual check finds an update. Without this, a sequence of
  -- (auto-fire piggyback shows popup -> Later -> manual check) would
  -- silently re-set state = "available" but the auto-show guard
  -- (`not update.popup_opened`) would suppress the popup the user
  -- explicitly asked to re-trigger. Same pattern as force_reinstall.
  update.popup_opened = false
  -- Sticky "Checking..." toast appears instantly so the user's click
  -- has immediate visual feedback during the PowerShell + curl round
  -- trip. check_poll replaces or clears this toast on every non-
  -- waiting result (up-to-date -> "up to date" toast; update or repair
  -- available -> cleared so the popup carries the feedback alone;
  -- error -> replaced with a specific error toast).
  UI.show_float_toast("Checking for updates...", "ok", true)
  local url = CFG.UPDATE_BASE_URL .. "/" .. CFG.UPDATE_MANIFEST
  if Updater.fire_get(url, tmp.update_out, tmp.update_exit) then
    update.state = "checking"
    return true
  end
  update._manual = false
  UI.show_float_toast("Update check failed to start", "err")
  return false
end

-- =============================================================================
-- Incremental SHA verification (deferred across frames)
-- =============================================================================
-- The (former) synchronous compute_sha_diff hashed every manifest file in a
-- single call and blocked the main thread for several hundred ms when the
-- piggyback check fired after the first chat response: pure-Lua SHA-256
-- throughput on commodity hardware is ~1 MB/s, so the two ~700 KB Lua files
-- cost 600+ ms each. The functions below split the same work across many
-- frames at the 64-byte SHA block level, not the file level: each
-- tick_sha_diff() call compresses up to CFG.UPDATE_SHA_TIME_BUDGET seconds
-- of work and returns. The main loop pumps it once per frame while update.state ==
-- "verifying", identical pattern to how "checking" / "downloading" /
-- "rename_retry" are pumped. Total wall-clock time is roughly the same as
-- the synchronous version, but it is fully spread across frames so REAPER
-- stays responsive
-- throughout - no frame stalls more than ~11 ms of SHA work.
--
-- download_start (the post-Update-Now path) keeps its own per-file
-- file_sha256_hex calls inline -- it's fired by an explicit user click
-- and only takes the same hash hit once, so a brief stall before the
-- download progress UI takes over is acceptable there.

-- Begin incremental SHA verification. Caller passes the parsed manifest plus
-- the snapshotted manual / forced flags (so tick_sha_diff -> _complete can
-- branch on the same intent that check_poll captured). Sets state to
-- "verifying" so the main loop knows to pump tick_sha_diff each frame.
function Updater.start_sha_diff(manifest, manual)
  update._sha_diff = {
    manifest    = manifest,
    files       = manifest.files,
    idx         = 1,
    cur         = nil,  -- in-flight per-file SHA state (see tick_sha_diff)
    diff        = { missing = {}, mismatched = {} },
    manual      = manual,
    started_at  = time_precise(),
  }
  update.state = "verifying"
end

-- One tick of incremental SHA verification. Called by the main loop each
-- frame while update.state == "verifying". State machine:
--   * No current file (s.cur == nil): walk forward in the manifest looking
--     for the next entry whose local file exists. Missing files / unsafe
--     filenames / malformed entries are recorded or skipped without
--     consuming SHA budget. When a startable file is found, read it into
--     memory and create a chunked SHA state.
--   * Current file in flight: compress one tick's worth of blocks. When
--     the state is exhausted, finalize, compare to the manifest hash, and
--     clear s.cur so the next tick advances.
-- When idx walks past #files with no s.cur set, hand off to _complete.
function Updater.tick_sha_diff()
  local s = update._sha_diff
  if not s then return end
  local files = s.files

  -- No file in flight: scan forward until we find one we can hash, or
  -- exhaust the manifest. Missing / unsafe / malformed entries are
  -- handled inline and do not consume SHA budget.
  if not s.cur then
    while s.idx <= #files do
      local entry = files[s.idx]
      if type(entry) == "table" and type(entry.name) == "string"
          and type(entry.sha256) == "string"
          and Updater.is_safe_filename(entry.name) then
        local path = Updater.local_path_for(entry.name)
        local f, open_err = io.open(path, "rb")
        if not f then
          -- Distinguish missing vs locked (AV scanner, editor handle).
          -- Locked: skip from diff entirely (treat as intact). Listing
          -- locked files in diff.missing produces a false-positive
          -- "Repair Available" popup. The next check after the lock
          -- clears will catch a genuinely-corrupt file.
          if reaper.file_exists and reaper.file_exists(path) then
            Log.line("UPDATE", string.format(
              "tick_sha_diff: %s exists but open failed: %s "
              .. "(likely AV / editor lock; skipping from diff)",
              path, tostring(open_err)))
          else
            s.diff.missing[#s.diff.missing+1] = entry.name
          end
          s.idx = s.idx + 1
        else
          local content = f:read("*a")
          f:close()
          if content then
            s.cur = { entry = entry, state = _SHA.create(content) }
            break
          else
            -- Read failed mid-flight: same locked-vs-missing distinction.
            -- The file existed enough to open, so we already proved it's
            -- on disk; treat read-fail as locked.
            Log.line("UPDATE", string.format(
              "tick_sha_diff: %s opened but read returned nil "
              .. "(treating as locked; skipping from diff)", path))
            s.idx = s.idx + 1
          end
        end
      else
        -- Malformed manifest entry: skip silently (is_safe_filename
        -- also gates the same way in download_start's inline diff).
        s.idx = s.idx + 1
      end
    end
    if not s.cur then
      Updater._sha_diff_complete()
      return
    end
  end

  -- File in flight: compress as many 16-block chunks as fit inside the
  -- per-tick time budget. The chunk size is small enough that the budget
  -- check stays meaningful on slow hardware (one chunk ~= 1 ms on a
  -- commodity CPU; would-be 5+ ms on a very old CPU still stops after a
  -- single chunk, which is still better than the previous 192-block
  -- fixed budget would have been on the same hardware).
  local tick_start = time_precise()
  local budget = CFG.UPDATE_SHA_TIME_BUDGET
  local done
  repeat
    done = _SHA.step(s.cur.state, 16)
    if done then break end
  until (time_precise() - tick_start) >= budget
  if done then
    local local_hash = _SHA.finalize(s.cur.state)
    if local_hash ~= s.cur.entry.sha256:lower() then
      s.diff.mismatched[#s.diff.mismatched+1] = s.cur.entry.name
    end
    s.cur = nil
    s.idx = s.idx + 1
  end
end

-- Apply the result of a completed incremental SHA diff. Same branch logic as
-- the inline block that lived in check_poll before the refactor: a non-empty
-- diff transitions to "repair_available" with the popup, an empty diff
-- transitions to "idle" with the manual-check toast (or silence for the
-- piggyback). Clears update._sha_diff so a stale snapshot can never leak
-- into a later check.
function Updater._sha_diff_complete()
  local s = update._sha_diff
  if not s then return end
  local diff     = s.diff
  local manifest = s.manifest
  local manual   = s.manual
  local elapsed  = time_precise() - (s.started_at or time_precise())
  update._sha_diff = nil

  local repair_count = #diff.missing + #diff.mismatched
  if repair_count > 0 then
    update.state          = "repair_available"
    update.remote_version = manifest.version  -- same as CFG.VERSION; kept
                                              -- for consistent popup format
    update.manifest       = manifest
    update.repair_missing    = diff.missing
    update.repair_mismatched = diff.mismatched
    Log.line("UPDATE", string.format(
      "sha_diff complete in %.2fs: version matches (%s) but %d files "
      .. "need repair (%d missing, %d mismatched).",
      elapsed, manifest.version, repair_count,
      #diff.missing, #diff.mismatched))
    -- Match the "available" branch: clear the sticky "Checking..."
    -- toast so the repair popup is the sole visual feedback.
    if manual then S.float_toast = nil end
  else
    update.state = "idle"  -- already up to date and all files intact
    Log.line("UPDATE", string.format(
      "sha_diff complete in %.2fs: version matches (%s) and all files "
      .. "intact.", elapsed, manifest.version))
    -- Stamp the last-successful-check time so the footer's version-
    -- number tooltip can show "Up to date (checked X ago)" instead
    -- of the generic "Click to check for updates" copy. Applies to
    -- both manual checks (Settings button / footer link) and the
    -- auto-fired piggyback check after the first chat response.
    update._last_ok_at = os.time()
    -- Manual check (Settings button / version-number link) with no
    -- action needed -> give the user explicit feedback that their
    -- click did something. Auto-fired checks stay silent.
    if manual then
      UI.show_float_toast(
        "ReaAssist is up to date (v" .. CFG.VERSION .. ")", "ok")
    end
  end
end

function Updater.check_poll()
  local result = Updater.poll()
  if result == "waiting" then return end
  -- Snapshot-and-clear both one-shot flags before any return path so a
  -- single force_reinstall / manual_check call cannot leak into a
  -- later organic check. Without this, update.force stayed true after
  -- consumption, and subsequent startup checks were misclassified as
  -- "available" even when the user was already on the current version,
  -- feeding the wrong action_was_repair bool into download_start's
  -- completion copy. _manual follows the same snapshot pattern so the
  -- "You're up to date" toast only fires for the check the user just
  -- clicked, not any later one.
  local forced = update.force
  update.force = false
  local manual = update._manual
  update._manual = false
  if result == "error" then
    -- Network / curl failure. Only surface as a failure when the user
    -- explicitly forced this check (Repair button): organic startup
    -- checks fail silently so offline launches do not nag the user.
    if forced then
      Updater._set_failure("manifest_fetch",
        "Could not reach update server (network error or timeout).\n\n"
        .. "Please enable your network connection if it is disabled.")
    end
    -- Manual Settings button: replace the sticky "Checking..." toast
    -- with a transient error message so the user sees explicit failure
    -- feedback on their explicit action.
    if manual then
      UI.show_float_toast(
        "Could not reach update server\nCheck your network connection",
        "err")
    end
    update.state = "idle"
    return
  end
  -- Parse manifest.
  local manifest = Updater.read_response()
  if not manifest
    or type(manifest.version) ~= "string"
    or type(manifest.files) ~= "table" then
    -- Distinguish empty / near-empty response (connection dropped
    -- silently, typical of offline on Windows where DNS cache may let
    -- curl exit with status 0 even though no bytes were received) from
    -- a body that actually contained something but wasn't valid JSON.
    -- Empty body is surfaced as a connection error so the user's toast
    -- / Bootstrap error message points at the likely cause instead of
    -- blaming the server for "malformed" output.
    local body_size = 0
    local bf = io.open(tmp.update_out, "rb")
    if bf then
      bf:seek("end")
      body_size = bf:seek("cur")
      bf:close()
    end
    local empty = (body_size < 2)
    if forced then
      if empty then
        Updater._set_failure("manifest_fetch",
          "Could not reach update server (no response received).\n\n"
          .. "Please enable your network connection if it is disabled.")
      else
        Updater._set_failure("manifest_parse",
          "Update server returned a malformed manifest "
          .. "(missing version or files field).")
      end
    end
    if manual then
      if empty then
        UI.show_float_toast(
          "Could not reach update server\nCheck your network connection",
          "err")
      else
        UI.show_float_toast(
          "Update server returned a malformed response", "err")
      end
    end
    update.state = "idle"
    return
  end
  -- Three-way version compare so we never repair against an older manifest
  -- (which would effectively downgrade the install). Equality via the
  -- "neither newer" rule because is_newer parses numerically (so "1.0.0"
  -- and "1.0.0.0" compare equal even though string == would say false).
  local remote_newer = Updater.is_newer(manifest.version, CFG.VERSION)
  local remote_older = Updater.is_newer(CFG.VERSION, manifest.version)
  if remote_newer then
    -- A newer version is on the server. The update flow handles this case --
    -- the user sees "Update Available" and the download queue is built by
    -- comparing local SHA vs manifest SHA (Stage 3.1), so only files that
    -- actually changed between versions get downloaded.
    update.state = "available"
    update.remote_version = manifest.version
    update.manifest = manifest
    -- Manual check -> the popup carries the visual feedback from here.
    -- Clear the sticky "Checking..." toast so it doesn't overlap the
    -- dialog near the bottom of the window.
    if manual then S.float_toast = nil end
    -- Honor the "Later" snooze for auto-fire piggyback checks only.
    -- When active (user clicked Later within the last 7 days), we
    -- keep state = "available" so manual paths can still surface the
    -- update, but we pre-open popup_opened so the automatic popup
    -- trigger in Render.main_window treats it as "already shown" and
    -- leaves the user alone. Forced / manual paths bypass this so
    -- explicit user action always sees the popup.
    if not forced and not manual then
      local snooze = tonumber(
        reaper.GetExtState(CFG.EXT_NS, "update_snooze") or "")
      if snooze and os.time() < snooze then
        update.popup_opened = true
      end
    end
  elseif not remote_older then
    -- Versions match. But the local install may still have missing or
    -- corrupted files (user deleted something, disk error, partial copy).
    -- Run the per-file SHA diff to find them, deferred across frames so
    -- REAPER stays responsive. Synchronous diff would freeze the UI for
    -- ~100-500 ms hashing ~5-6 MB of fonts and large .lua files (more
    -- with AV scanning). See Updater.start_sha_diff / tick_sha_diff for
    -- the incremental machine; main loop pumps it via the "verifying"
    -- state branch, identical control-flow shape to "checking".
    Updater.start_sha_diff(manifest, manual)
  elseif forced then
    -- Remote manifest is older than installed AND user explicitly asked to
    -- reinstall. Repairing against an older manifest would effectively
    -- downgrade the install; refuse with a specific failure so the
    -- "Update Failed" dialog can surface the cause.
    Updater._set_failure("manifest_version", string.format(
      "Update server returned manifest v%s, older than installed v%s. "
      .. "Refusing to repair against an older manifest.",
      tostring(manifest.version), tostring(CFG.VERSION)))
    update.state = "failed"
  else
    -- Remote manifest is older than installed and the user didn't force a
    -- reinstall. Most likely a CDN propagation race or a stale branch.
    -- Skip silently for auto-fire piggyback checks; surface a brief toast
    -- for explicit manual checks so the user knows the click was processed.
    update.state = "idle"
    Log.line("UPDATE", string.format(
      "Remote manifest is older (v%s) than installed (v%s); "
      .. "skipping repair check.",
      tostring(manifest.version), tostring(CFG.VERSION)))
    if manual then
      UI.show_float_toast(
        "Update server returned an older manifest; try again later.",
        "err", true)
    end
  end
end

-- Validate a manifest filename: no path traversal, no absolute paths, safe extension.
-- Forward-slash subpaths are allowed (e.g. "Resources/ReaAssist_Help.md",
-- "Resources/ReEQ/Dependencies/svf_filter.jsfx-inc") so the manifest can mirror
-- the on-disk layout. Backslashes, leading slashes, drive letters, and any
-- ".." or hidden ("."-prefixed) path segments are rejected.
function Updater.is_safe_filename(name)
  if type(name) ~= "string" or name == "" then return false end
  -- Strict allowlist: only ASCII alphanumerics, underscore, hyphen, dot,
  -- and forward slash. Blocks shell-sensitive characters (spaces, $, `,
  -- &, ?, #, ;, parens, quotes, etc.) before they ever reach a curl
  -- command line or a local path. The remaining checks below run after
  -- the allowlist as defense-in-depth.
  if not name:match("^[A-Za-z0-9_./%-]+$") then return false end
  -- Reject backslashes, leading /, drive letters (absolute paths).
  if name:match("^/") or name:match("^%a:") then return false end
  if name:find("\\", 1, true) then return false end
  -- Validate each forward-slash-separated path segment.
  for segment in (name .. "/"):gmatch("([^/]*)/") do
    if segment == "" or segment == "." or segment == ".." then return false end
    if segment:sub(1, 1) == "." then return false end  -- hidden dotfiles/dirs
  end
  -- The final segment is the filename itself.
  local base_name = name:match("([^/]+)$") or name
  -- Reject Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9).
  local base = base_name:match("^([^%.]+)") or ""
  local reserved = {
    CON=true, PRN=true, AUX=true, NUL=true,
    COM1=true, COM2=true, COM3=true, COM4=true, COM5=true,
    COM6=true, COM7=true, COM8=true, COM9=true,
    LPT1=true, LPT2=true, LPT3=true, LPT4=true, LPT5=true,
    LPT6=true, LPT7=true, LPT8=true, LPT9=true,
  }
  if reserved[base:upper()] then return false end
  -- Allow only known safe extensions.
  local ext = base_name:match("%.([^%.]+)$")
  if not ext then return false end
  local safe = {
    lua=true, md=true, txt=true, jsfx=true, ["jsfx-inc"]=true,
    json=true, png=true, csv=true, pdf=true,
    -- .ttf added in Stage 3.4: Resources/fonts/*.ttf are part of the
    -- distributable install (the bootstrap critical-files check verifies
    -- them at launch), so the download pipeline has to accept them.
    ttf=true,
  }
  if not safe[ext:lower()] then return false end
  return true
end

-- Read a local file and return its SHA-256 hex digest (lowercase). Used
-- by Updater.download_start() to skip files whose local content already
-- matches the manifest SHA, and the open path is mirrored inline by
-- Updater.tick_sha_diff() (incremental verify) to classify files as
-- missing, mismatched, or intact.
--
-- Returns (hex, nil) on success, or (nil, kind) on failure where kind is:
--   "missing" - genuinely not on disk
--   "locked"  - exists on disk but couldn't be opened (AV scanner mid-
--               scan, editor open handle, permission flicker). The caller
--               should treat this as "intact" rather than triggering a
--               repair: rolling a download in over a perfectly good file
--               just because the AV scanner caught it for 50ms produces
--               a confusing "repair available" prompt out of nowhere.
function Updater.file_sha256_hex(path)
  local f, open_err = io.open(path, "rb")
  if not f then
    -- reaper.file_exists handles Windows path separators and long-path
    -- weirdness better than a pcall around a second open. Its result
    -- tells us whether this is a true "missing" or a transient lock.
    if reaper.file_exists and reaper.file_exists(path) then
      Log.line("UPDATE", string.format(
        "file_sha256_hex: %s exists but open failed: %s "
        .. "(likely AV / editor lock; treating as intact for this run)",
        path, tostring(open_err)))
      return nil, "locked"
    end
    return nil, "missing"
  end
  local content = f:read("*a")
  f:close()
  if not content then return nil, "locked" end
  return sha256_hash(content)
end

-- Resolve a manifest filename ("Resources/X.md") to an absolute local path
-- using the host OS separator. Centralized so download_start (the local-SHA
-- check) and download_poll (the write target) agree on the layout.
function Updater.local_path_for(filename)
  local rel = filename
  if RA.SEP ~= "/" then rel = rel:gsub("/", RA.SEP) end
  return RA.script_path .. rel
end

function Updater.download_start()
  -- Accept both triggers: "available" (new version on server) and
  -- "repair_available" (version matches but some files are missing or
  -- corrupted locally). The download pipeline and SHA-diff logic are
  -- identical for both; only the popup messaging differs.
  if (update.state ~= "available" and update.state ~= "repair_available")
      or not update.manifest then return end
  -- Remember which trigger started the session so the "done" view can
  -- say "Updated to vX" vs "Restored N files" accurately.
  update.action_was_repair = (update.state == "repair_available")
  update.download_queue = {}
  update.applied_files = {}  -- track successfully written files for rollback
  update.skipped_count  = 0  -- files whose local SHA already matches manifest
  -- When entering from repair_available, the SHA diff just finished and we
  -- already know which files are missing or mismatched. Reuse those lists
  -- instead of re-hashing the entire manifest synchronously, which freezes
  -- the UI for the full hash time on slower machines (~1 MB/s pure-Lua SHA
  -- means 5-6 MB of fonts plus two ~700 KB Lua files takes 5-7 seconds on
  -- a commodity CPU and longer on older hardware). Trade-off: a corruption
  -- introduced in the few seconds between the diff completing and the user
  -- clicking Repair Now wouldn't be caught here, but the next launch's SHA
  -- check would catch it.
  local repair_fileset = nil
  if update.action_was_repair
      and update.repair_missing
      and update.repair_mismatched then
    repair_fileset = {}
    for _, n in ipairs(update.repair_missing)    do repair_fileset[n] = true end
    for _, n in ipairs(update.repair_mismatched) do repair_fileset[n] = true end
  end
  for _, entry in ipairs(update.manifest.files) do
    local filename, expected_hash
    if type(entry) == "table" and entry.name and entry.sha256 then
      filename      = entry.name
      expected_hash = entry.sha256
    else
      -- Reject manifests without per-file SHA-256 hashes. All production
      -- manifests must use the {name, sha256} format for integrity
      -- verification. Route through _set_failure so the Update Failed
      -- dialog has a real reason to display instead of the generic
      -- "(unknown)" the empty fields would produce.
      Updater._set_failure("manifest_file",
        "Manifest entry missing required SHA-256 hash")
      update.state = "failed"
      return
    end
    if not Updater.is_safe_filename(filename) then
      Updater._set_failure("manifest_file",
        "Unsafe filename in manifest: " .. tostring(filename))
      update.state = "failed"
      return
    end
    if repair_fileset then
      -- Repair path: queue only files the SHA diff flagged. Everything else
      -- already matched per the diff and is safe to skip without re-hashing.
      if repair_fileset[filename] then
        update.download_queue[#update.download_queue+1] = {
          filename = filename,
          url      = CFG.UPDATE_BASE_URL .. "/" .. filename,
          sha256   = expected_hash,
        }
      else
        update.skipped_count = update.skipped_count + 1
      end
    else
      -- Version-bump path: hash each file synchronously to skip those whose
      -- local content already matches the manifest. This is unavoidable
      -- here -- we have no precomputed diff to lean on -- but it makes the
      -- download itself incremental (a point release that changes one
      -- markdown file only downloads that file, not the full manifest).
      local local_path = Updater.local_path_for(filename)
      local local_hash = Updater.file_sha256_hex(local_path)
      if local_hash and local_hash == expected_hash:lower() then
        update.skipped_count = update.skipped_count + 1
      else
        update.download_queue[#update.download_queue+1] = {
          filename = filename,
          url      = CFG.UPDATE_BASE_URL .. "/" .. filename,
          sha256   = expected_hash,
        }
      end
    end
  end
  -- If every file already matches (user manually swapped files, or re-invoked
  -- an update that already ran), close the popup silently and stay idle --
  -- the manifest version stamp is handled by the next startup check.
  if #update.download_queue == 0 then
    Log.line("UPDATE", string.format(
      "download_start: all %d manifest files already match local SHA; "
      .. "nothing to download.", update.skipped_count))
    update.show_dialog = false
    update.state       = "idle"
    return
  end
  Log.line("UPDATE", string.format(
    "download_start: %d files to download, %d already up to date.",
    #update.download_queue, update.skipped_count))
  update.download_idx = 1
  update.state = "downloading"
  local entry = update.download_queue[1]
  if not Updater.fire_get(entry.url, tmp.update_out, tmp.update_exit) then
    Updater._set_failure("download_start", string.format(
      "Could not start download for %s.", tostring(entry.filename)))
    update.state = "failed"
    return
  end
end

-- Rollback all successfully written files. For files that existed before
-- the update (bak_existed=true), restore the .bak. For fresh-install adds
-- (bak_existed=false), just delete the dest -- there is no prior version
-- to restore, and renaming a nonexistent .bak over dest silently deletes
-- it, leaving the user with neither a working file nor a recoverable
-- backup if the next update file fails.
function Updater.rollback()
  if not update.applied_files then return end
  -- Track restore failures so we can surface them via update.last_error.
  -- Rollback runs because some EARLIER step already failed, so last_step
  -- and last_error are typically already set at this point. We only
  -- overwrite them if a restore failure produces a worse situation than
  -- the original failure (i.e. a file the user had before the update is
  -- now gone with no .bak to recover from), which is the one rollback
  -- failure mode that genuinely requires manual attention.
  local restore_failures = {}
  for i = #update.applied_files, 1, -1 do
    local applied = update.applied_files[i]
    local dest = applied.path
    os.remove(dest)
    if applied.bak_existed then
      local bak_path = dest .. ".bak"
      local ok, err = os.rename(bak_path, dest)
      if not ok then
        Log.line("UPDATE", string.format(
          "rollback restore failed for %s: %s "
          .. "(.bak still on disk; manual recovery may be needed)",
          dest, tostring(err)))
        restore_failures[#restore_failures + 1] = dest
      end
    end
  end
  update.applied_files = {}
  if #restore_failures > 0 then
    -- Append a manual-attention note to the existing failure message so
    -- the Update Failed dialog surfaces both the original cause and the
    -- restore problem. Don't replace last_error/last_step -- the original
    -- failure step is the right pointer for the user; the restore note
    -- just adds urgency.
    local note = string.format(
      "\n\nNote: rollback could not restore %d previous file%s "
      .. "(.bak file%s left on disk for manual recovery): %s",
      #restore_failures,
      #restore_failures == 1 and "" or "s",
      #restore_failures == 1 and "" or "s",
      table.concat(restore_failures, ", "))
    update.last_error = (update.last_error or "(no prior error)") .. note
  end
end

-- Poll the current file download. Advances to next file or applies update.
function Updater.download_poll()
  local entry = update.download_queue[update.download_idx]
  local fname = entry and entry.filename or "?"
  local result = Updater.poll()
  if result == "waiting" then return end
  if result == "error" then
    Updater._set_failure("download",
      string.format("curl failed or timed out while fetching %s", fname))
    Updater.rollback()
    update.state = "failed"
    return
  end
  -- Read the downloaded file and save it.
  local f, f_err = io.open(tmp.update_out, "rb")
  if not f then
    Updater._set_failure("download_read",
      string.format("Could not open downloaded %s: %s",
                    fname, tostring(f_err)))
    Updater.rollback()
    update.state = "failed"
    return
  end
  local content = f:read("*a"); f:close()
  if not content or #content == 0 then
    Updater._set_failure("download_read",
      string.format("Downloaded %s is empty.", fname))
    Updater.rollback()
    update.state = "failed"
    return
  end
  -- Integrity checks.
  -- SHA-256 hash verification: if the manifest provided a hash, verify it.
  -- This is the primary integrity gate. A mismatch means the download was
  -- corrupted or tampered with; reject the entire update.
  if entry.sha256 then
    local actual_hash = sha256_hash(content)
    if actual_hash ~= entry.sha256:lower() then
      Updater._set_failure("sha_verify", string.format(
        "SHA-256 mismatch for %s: expected %s, got %s",
        fname, entry.sha256:lower(), actual_hash))
      Updater.rollback()
      update.state = "failed"
      return
    end
  end
  -- Secondary sanity check: the main Lua file must contain our version marker.
  if entry.filename:match("%.lua$") then
    if not content:find("CFG.VERSION", 1, true) then
      Updater._set_failure("sha_verify", string.format(
        "Downloaded %s is missing the CFG.VERSION marker "
        .. "(rejected as likely-corrupt).", fname))
      Updater.rollback()
      update.state = "failed"
      return
    end
  end
  -- Write to a .tmp file first, then rename. Manifest entries may include
  -- forward-slash subpaths (e.g. "Resources/ReaAssist_Help.md"); the path
  -- helper normalizes them to the platform separator. Ensure the parent
  -- directory exists so fresh installs can create the Resources/ tree on
  -- first update.
  local dest = Updater.local_path_for(entry.filename)
  local parent = dest:match("^(.*)[\\/][^\\/]+$")
  if parent and parent ~= "" then
    reaper.RecursiveCreateDirectory(parent, 0)
  end
  local tmp_path = dest .. ".tmp"
  local bak_path = dest .. ".bak"
  -- Write temp file. pcall-wrap the write/close so short writes, disk-
  -- full, and permission errors propagate as failure instead of silently
  -- shipping a truncated file.
  local wf, open_err = io.open(tmp_path, "wb")
  if not wf then
    Updater._set_failure("write_open", string.format(
      "Could not open temp file %s for write: %s",
      tmp_path, tostring(open_err)))
    Updater.rollback()
    update.state = "failed"
    return
  end
  local w_ok, w_err = pcall(function()
    local ok, perr = wf:write(content)
    if not ok then error(perr or "write returned nil", 0) end
  end)
  local c_ok, c_err = pcall(function()
    local ok, perr = wf:close()
    if not ok then error(perr or "close returned nil", 0) end
  end)
  if not w_ok or not c_ok then
    Updater._set_failure("write", string.format(
      "Write to %s failed: %s",
      tmp_path, tostring(w_err or c_err)))
    os.remove(tmp_path)
    Updater.rollback()
    update.state = "failed"
    return
  end
  -- Back up current file. We must distinguish "dest does not exist
  -- (fresh-install add)" from "dest exists but rename failed (lock,
  -- permissions, AV scan, cloud sync, editor handle)". `os.rename`
  -- returns nil for both, so probing existence first is the only way
  -- to disambiguate. Misclassifying an existing-but-locked file as
  -- fresh-install is dangerous: rollback's fresh-install branch deletes
  -- dest, which would destroy the only intact copy when no .bak was
  -- ever created. rename_bak_existed carries the truth into
  -- rename_retry_poll and rollback.
  os.remove(bak_path)
  local dest_existed = reaper.file_exists and reaper.file_exists(dest)
  if dest_existed then
    local ok_bak, bak_err = os.rename(dest, bak_path)
    if not ok_bak then
      os.remove(tmp_path)
      Updater._set_failure("backup", string.format(
        "Could not back up existing file %s: %s",
        dest, tostring(bak_err)))
      Updater.rollback()
      update.state = "failed"
      return
    end
    update.rename_bak_existed = true
  else
    update.rename_bak_existed = false
  end
  -- Move temp to final. On Windows, Defender / AV may hold a short-lived lock
  -- on the .tmp file immediately after close, causing rename to fail during
  -- the scan window (~20-50ms). Instead of busy-waiting, we attempt the rename
  -- once and defer to "rename_retry" state if it fails. The main loop will
  -- call Updater.rename_retry_poll() on subsequent frames (~30ms apart), which
  -- is a natural non-blocking delay that avoids stalling the UI thread.
  local ok_mv = os.rename(tmp_path, dest)
  if not ok_mv then
    -- Stash rename context and defer. The next frame will retry.
    update.rename_failures = 1
    update.rename_tmp      = tmp_path
    update.rename_dest     = dest
    update.rename_bak      = bak_path
    update.state           = "rename_retry"
    return
  end
  Updater.advance_after_rename(dest)
end

-- Fire auto-restart if the download pipeline is in "done" state, the
-- restart delay has elapsed, and we have not already fired. Called from
-- both the main loop and Bootstrap.loop so either flow auto-restarts
-- after a successful apply. Single-fire via update.restart_fired so we
-- only invoke Main_OnCommand once.
--
-- Fires the external relauncher action (registered at startup) and
-- closes ourselves. Firing Main_OnCommand on ReaAssist's own CMD_ID
-- from inside our still-running defer chain triggers REAPER's
-- re-entrance handling -- the action "is already running" -- and the
-- single-instance handshake interprets that as a toggle-off, exiting
-- the new instance immediately. The relauncher is a separate script
-- with its own action id, so invoking it from here does NOT hit that
-- re-entrance path. It waits for our "running" ExtState to clear,
-- re-registers ReaAssist via AddRemoveReaScript, and fires a fresh
-- Main_OnCommand on ReaAssist from its own context.
--
-- advance_after_rename only sets update.restart_after when the
-- relauncher file is present on disk, so by the time we reach this
-- function the on-demand AddRemoveReaScript call should succeed.
function Updater.try_auto_restart()
  if update.state ~= "done" then return end
  if not update.restart_after or update.restart_fired then return end
  if time_precise() < update.restart_after then return end
  update.restart_fired = true
  return Updater.fire_relauncher_now()
end

-- Shared helper: fires the relauncher script in its own Lua state, then
-- closes the current ReaAssist instance. Used by:
--   * try_auto_restart (post-update success)
--   * Render._factory_reset_execute (UI file -- relauncher path is
--     local to this file, so the UI can't fire it directly)
-- Returns true on success, false if the relauncher couldn't be
-- registered (caller can fall back to a "close and reopen" prompt).
function Updater.fire_relauncher_now()
  -- Lazy-register the relauncher action right before firing it. Keeps
  -- the Actions list uncluttered for sessions where no auto-restart
  -- ever happens. AddRemoveReaScript is synchronous and the returned
  -- cmd_id is immediately usable from Main_OnCommand. commit=false so
  -- the registration is session-only (vanishes when REAPER closes).
  local cmd_id = reaper.AddRemoveReaScript(true, 0, RELAUNCHER_PATH, false)
  if cmd_id and cmd_id ~= 0 then
    reaper.Main_OnCommand(cmd_id, 0)
    S.script_open = false
    return true
  end
  return false
end

-- Advance to the next file (or finish) after a successful rename.
function Updater.advance_after_rename(dest)
  -- Capture whether dest had a .bak before this apply. rollback uses the
  -- flag to skip restore for fresh-install adds (no prior .bak to restore;
  -- rolling back means simply deleting the newly-written dest, not renaming
  -- a nonexistent .bak over it which would silently delete the new file).
  update.applied_files[#update.applied_files+1] = {
    path = dest,
    bak_existed = (update.rename_bak_existed == true),
  }
  update.rename_failures = 0
  update.rename_tmp      = nil
  update.rename_dest     = nil
  update.rename_bak      = nil
  update.rename_bak_existed = false
  if update.download_idx < #update.download_queue then
    update.download_idx = update.download_idx + 1
    local next_entry = update.download_queue[update.download_idx]
    if not Updater.fire_get(next_entry.url, tmp.update_out, tmp.update_exit) then
      Updater._set_failure("download_start", string.format(
        "Could not start download for %s.", tostring(next_entry.filename)))
      Updater.rollback()
      update.state = "failed"
      return
    end
    update.state = "downloading"
  else
    for _, applied in ipairs(update.applied_files) do
      os.remove(applied.path .. ".bak")
    end
    update.state   = "done"
    update.applied = true
    -- Active stale-stock nudge for power-user prompt overrides. If this
    -- update modified the stock system prompt AND the user has a custom
    -- override file in place (which the loader prefers over the stock),
    -- set a persistent ExtState flag. The next-launch path reads it,
    -- clears it, and shows a one-time sticky toast inviting the user to
    -- diff the new stock prompt against their custom copy and merge any
    -- improvements worth keeping. Persistent (3rd arg true) so it
    -- survives the auto-restart that follows.
    do
      local stock_pp  = RA.RESOURCES_DIR .. "ReaAssist_System_Prompt.md"
      local custom_pp = RA.RESOURCES_DIR .. "ReaAssist_System_Prompt_Custom.md"
      local prompt_changed = false
      for _, applied in ipairs(update.applied_files) do
        if applied.path == stock_pp then prompt_changed = true; break end
      end
      if prompt_changed and reaper.file_exists(custom_pp) then
        reaper.SetExtState(CFG.EXT_NS, "prompt_review_pending", "1", true)
      end
    end
    -- Stage 3.4 auto-restart: schedule a short delay (so the user sees
    -- the "Applied" confirmation), then re-launch the script via the
    -- sidecar relauncher (ReaAssist_Relaunch.lua). The relauncher re-
    -- registers ReaAssist via AddRemoveReaScript and fires it from its
    -- own script context, so auto-restart works regardless of how this
    -- instance was launched. File-existence check (cheap, no action-
    -- registry side effects) gates the restart scheduling so the done-
    -- view message stays honest: falls back to "Close and reopen" if
    -- the relauncher file is missing, which only happens on a broken
    -- install. try_auto_restart does the actual AddRemoveReaScript
    -- registration on-demand when it fires.
    if reaper.file_exists(RELAUNCHER_PATH) then
      update.restart_after = time_precise() + 1.5
      update.restart_fired = false
    else
      update.restart_after = nil
    end
  end
end

-- Called from the main loop when state == "rename_retry". Each call is one
-- frame (~30ms apart), providing a natural non-blocking delay between
-- attempts without busy-waiting. Ceiling is 15 attempts (~450ms): the
-- previous 5-attempt limit (~150ms total) tripped false-fails on cold
-- Windows Defender scans, which can hold a just-closed file exclusively
-- for 300-500ms. 15 covers the tail of that distribution without
-- noticeably delaying success cases (a single retry is the median).
function Updater.rename_retry_poll()
  if not update.rename_tmp or not update.rename_dest then
    Updater._set_failure("rename",
      "rename_retry_poll entered with no pending paths.")
    update.state = "failed"
    return
  end
  local ok_mv = os.rename(update.rename_tmp, update.rename_dest)
  if ok_mv then
    Updater.advance_after_rename(update.rename_dest)
    return
  end
  update.rename_failures = update.rename_failures + 1
  if update.rename_failures >= 15 then
    -- Give up. Restore the backup only if one was actually created --
    -- otherwise the destination is a fresh-install add and there is
    -- nothing to restore. Skipping the restore in that case prevents
    -- an empty-rename clobber that leaves neither dest nor bak.
    if update.rename_bak_existed then
      local ok_restore, restore_err = os.rename(update.rename_bak,
                                                update.rename_dest)
      if not ok_restore then
        Log.line("UPDATE", string.format(
          "rollback restore failed for %s: %s",
          update.rename_dest, tostring(restore_err)))
      end
    else
      -- Fresh-install add: no bak exists. Remove any leftover dest.
      os.remove(update.rename_dest)
    end
    os.remove(update.rename_tmp)
    Updater._set_failure("rename", string.format(
      "Could not rename downloaded file into place after %d attempts "
      .. "(%s -> %s). Antivirus or file lock?",
      update.rename_failures, update.rename_tmp, update.rename_dest))
    update.rename_tmp  = nil
    update.rename_dest = nil
    update.rename_bak  = nil
    update.rename_bak_existed = false
    Updater.rollback()
    update.state = "failed"
  end
  -- Otherwise stay in "rename_retry" state; next frame will try again.
end

Net = {}

-- =============================================================================
-- Custom-LLM connection test helpers
-- =============================================================================
-- Supports the Test Connection button on the custom_llm page. Fires a single
-- GET /v1/models request against the currently entered endpoint (without
-- requiring Save) and stores pass/fail in api_keys.custom_conn_test.result.
--
-- The test is model-agnostic -- /v1/models is a server directory listing, so
-- it only verifies the server is reachable + auth works. This is the most
-- information we can extract without running inference (which would invoke
-- reasoning on models like deepseek-r1 and block the test).
--
-- Implementation temporarily registers a minimal custom provider, fires
-- Net.fire_key_test (which dispatches custom providers to GET /v1/models),
-- then restores the originally-saved config on finish.
-- Placed after `local Net = {}` so the closures capture Net as an upvalue
-- instead of resolving it as a (nil) global.

-- Synthetic id used exclusively for the in-flight connection-test provider.
-- Double-underscore prefix makes it impossible to collide with any id that
-- Custom.gen_id() produces ("custom_" + 8 hex). Never persisted: the test
-- flow only touches in-memory PROVIDERS + S.api_key_map, never Key.save.
CUSTOM_CONN_TEST_ID = "__cllm_conn_test__"

-- Build a throwaway record from cfg_base, append it to PROVIDERS under the
-- conn-test sentinel id, and select it as the active provider. The model id
-- is a placeholder -- the GET /v1/models test doesn't reference it. Returns
-- the new provider index, or nil on failure. cfg_base carries the advanced
-- fields (connect_timeout, allow_insecure, extra_headers, model_prefix) so
-- the test exercises the same curl options the real request will use.
local function custom_conn_test_register(cfg_base)
  local record = {
    id                   = CUSTOM_CONN_TEST_ID,
    endpoint             = cfg_base.endpoint,
    timeout_secs         = cfg_base.timeout_secs,
    connect_timeout_secs = cfg_base.connect_timeout_secs,
    allow_insecure       = cfg_base.allow_insecure,
    model_prefix         = cfg_base.model_prefix,
    extra_headers        = cfg_base.extra_headers,
    label                = cfg_base.label,
    models               = { {
      id             = "conn-test",  -- placeholder; not used by /v1/models
      price_in       = 0,
      price_out      = 0,
      context_window = CUSTOM_DEFAULT_CTX,
    } },
  }
  -- Defensive: if a prior test left the sentinel registered, drop it first.
  Custom.unregister_id(CUSTOM_CONN_TEST_ID)
  local cust_idx = Custom.register_one(record)
  if cust_idx then
    prefs.provider_idx = cust_idx
    MODELS.refresh()
  end
  return cust_idx
end

-- Validate current form values on the custom_llm edit screen and fire a
-- single connection test. Called by the "Test Connection" button. Writes
-- per-field errors on failure. Returns true if the test was fired, false
-- otherwise. Reads from api_keys.custom_edit, which is populated when the
-- user navigates into the edit screen (new record or existing record).
function CTX.custom_llm_start_conn_test()
  local edit = api_keys.custom_edit
  if not edit then return false end
  edit.errors = {}
  local has_format_error = false

  local endpoint_t  = (edit.endpoint        or ""):match("^%s*(.-)%s*$") or ""
  local timeout_t   = (edit.timeout         or ""):match("^%s*(.-)%s*$") or ""
  local ctimeout_t  = (edit.connect_timeout or ""):match("^%s*(.-)%s*$") or ""
  local label_t     = (edit.label           or ""):match("^%s*(.-)%s*$") or ""
  local key_t       = (edit.key             or ""):match("^%s*(.-)%s*$") or ""
  local prefix_t    = (edit.model_prefix    or ""):match("^%s*(.-)%s*$") or ""

  if label_t == "" then
    edit.errors.label = "Name is required."
    has_format_error = true
  end

  if not endpoint_t:match("^https?://") then
    edit.errors.endpoint = "Endpoint must start with http:// or https://."
    has_format_error = true
  elseif endpoint_t:find("[\"'`%c]") then
    -- Reject characters that would break (or escape out of) the
    -- powershell + cmd quoting in Net.fire_curl.
    edit.errors.endpoint = "Endpoint may not contain quotes, backticks, or control characters."
    has_format_error = true
  end

  local timeout_n = tonumber(timeout_t == "" and tostring(CUSTOM_DEFAULT_TIMEOUT) or timeout_t)
  if not timeout_n or timeout_n < CUSTOM_MIN_TIMEOUT then
    edit.errors.timeout = str_format(
      "Timeout must be a number >= %d seconds.", CUSTOM_MIN_TIMEOUT)
    has_format_error = true
  elseif timeout_n > CUSTOM_MAX_TIMEOUT then
    edit.errors.timeout = str_format(
      "Timeout must be <= %d seconds (1 hour).", CUSTOM_MAX_TIMEOUT)
    has_format_error = true
  end

  local ctimeout_n = tonumber(ctimeout_t == "" and tostring(Custom.DEFAULT_CONNECT) or ctimeout_t)
  if not ctimeout_n or ctimeout_n < Custom.MIN_CONNECT or ctimeout_n > Custom.MAX_CONNECT then
    edit.errors.connect_timeout = str_format(
      "Connect timeout must be a number between %d and %d seconds.",
      Custom.MIN_CONNECT, Custom.MAX_CONNECT)
    has_format_error = true
  end

  local headers_arr, headers_err = Custom.parse_headers_text(edit.headers_text or "")
  if headers_err then
    edit.errors.headers = headers_err
    has_format_error = true
  end

  if key_t ~= "" then
    local lk_valid, lk_reason = Key.validate_format(key_t,
      { is_custom = true, key_prefix = "", key_min_len = 0 })
    if not lk_valid then
      edit.errors.key = lk_reason
      has_format_error = true
    end
  end

  if has_format_error then return false end

  local cfg_base = {
    endpoint             = endpoint_t,
    timeout_secs         = timeout_n or CUSTOM_DEFAULT_TIMEOUT,
    connect_timeout_secs = ctimeout_n or Custom.DEFAULT_CONNECT,
    allow_insecure       = edit.allow_insecure and true or false,
    model_prefix         = prefix_t,
    extra_headers        = headers_arr,
    label                = label_t,
  }
  CTX.custom_conn_test_start(cfg_base, key_t)
  return true
end

-- Start the connection test. cfg_base carries shared config (endpoint,
-- timeout, label); api_key is the auth key (or "" for none). The test
-- registers a throwaway provider under CUSTOM_CONN_TEST_ID and stashes
-- the active provider's index so finish() can restore it.
function CTX.custom_conn_test_start(cfg_base, api_key)
  local state = api_keys.custom_conn_test
  state.active            = true
  state.started           = reaper.time_precise()
  state.timeout           = CUSTOM_DEFAULT_TEST_TIMEOUT
  state.result            = nil   -- cleared; filled by advance()
  state.orig_provider_idx = prefs.provider_idx
  S.api_key_map[CUSTOM_CONN_TEST_ID] = (api_key ~= "" and api_key) or nil

  local cust_idx = custom_conn_test_register(cfg_base)
  local cust_prov = cust_idx and PROVIDERS[cust_idx] or nil
  if not cust_prov then
    CTX.custom_conn_test_advance(false, "Could not register custom provider.")
    return
  end
  S.api_key = S.api_key_map[CUSTOM_CONN_TEST_ID]
  api_keys.key_validating     = true
  api_keys.key_validating_idx = cust_idx
  -- Publish the test timeout for Net.fire_curl to pick up.
  S.key_test_custom_timeout = state.timeout
  Net.fire_key_test(cust_prov)
end

-- Record the test's pass/fail result and finish. Called by Net.handle_key_test
-- and by the various error paths in Net.fire_curl / Net.try_finish_curl.
function CTX.custom_conn_test_advance(ok, err_msg)
  local state = api_keys.custom_conn_test
  state.result = { ok = ok, error = err_msg }
  S.key_test_pending  = false
  S.key_test_provider = nil
  S.curl_pid          = nil
  CTX.custom_conn_test_finish()
end

-- Cancel an in-flight connection test. Kills any active curl request, marks
-- the result as cancelled, and restores the original custom config via finish().
function CTX.custom_conn_test_cancel()
  local state = api_keys.custom_conn_test
  if not state or not state.active then return end
  if Net.kill_curl then pcall(Net.kill_curl) end
  state.result        = { ok = false, error = "Test cancelled." }
  S.key_test_pending  = false
  S.key_test_provider = nil
  S.curl_pid          = nil
  CTX.custom_conn_test_finish()
end

-- Drop the throwaway conn-test provider, restore the previous active
-- provider, and clear transient state. Leaves state.result in place so
-- the UI can render the pass/fail message until the user clicks Test
-- Connection again or leaves the page. Persisted records are never
-- touched -- register_all was called at startup and stays in effect.
-- Idempotent: if the test was already finished (watchdog + advance racing,
-- or Cancel double-click), the second call is a no-op.
function CTX.custom_conn_test_finish()
  local state = api_keys.custom_conn_test
  if not state or not state.active then return end
  state.active                = false
  state.started               = nil
  -- Remove the throwaway provider and its in-memory key. The sentinel id is
  -- reserved, so wiping the key unconditionally is safe -- nothing else
  -- ever writes to S.api_key_map[CUSTOM_CONN_TEST_ID].
  Custom.unregister_id(CUSTOM_CONN_TEST_ID)
  S.api_key_map[CUSTOM_CONN_TEST_ID] = nil
  -- Restore active provider index (clamp if out of range).
  local orig_idx = state.orig_provider_idx or 1
  if orig_idx < 1 or orig_idx > #PROVIDERS then orig_idx = 1 end
  prefs.provider_idx = orig_idx
  MODELS.refresh()
  S.api_key = S.api_key_map[PROVIDERS.active().id]
  -- Clear transient flags.
  api_keys.key_validating     = false
  api_keys.key_validating_idx = nil
  S.status                    = "idle"
  S.key_test_custom_timeout   = nil
end

-- =============================================================================
-- Net.system_prompt_text
-- =============================================================================
-- Return the SYSTEM_PROMPT string, optionally with a per-TEST-SESSION stamp
-- appended as a hidden comment when prefs.test_force_cold_cache is on.
--
-- The stamp is minted ONCE when the toggle transitions off -> on (held in
-- S.cold_cache_stamp) and reused on every subsequent send until the toggle
-- flips off or is re-minted. That way the FIRST send after toggling on
-- misses cache across all three providers (fresh prefix the server has
-- never seen), but subsequent sends within the same test run hit cache
-- normally -- so you can still observe caching behavior turn-over-turn
-- while starting from a guaranteed cold state.
--
-- Starting a fresh cold test: toggle off, then toggle on again -- that
-- mints a new stamp.
function Net.system_prompt_text()
  if prefs.test_force_cold_cache and S.cold_cache_stamp then
    return SYSTEM_PROMPT
      .. "\n\n<!-- test_force_cold_cache: "
      .. S.cold_cache_stamp
      .. " -->"
  end
  return SYSTEM_PROMPT
end

-- =============================================================================
-- Net.bundled_static_refs
-- =============================================================================
-- Concatenates the long-lived static references (api_ref, midi_ref, theme_ref)
-- into one blob so each provider can emit them as ONE pinned exchange instead
-- of three. Saves the per-ref "Understood." ack overhead and reduces the
-- number of message turns the providers' caches have to align on (matters
-- most for Gemini's cachedContents structure). Returns nil when no refs
-- are present. Order is stable: api_ref first (largest, most stable), then
-- midi_ref, then theme_ref.
function Net.bundled_static_refs()
  local parts = {}
  if S.api_ref_message   then parts[#parts+1] = S.api_ref_message   end
  if S.midi_ref_message  then parts[#parts+1] = S.midi_ref_message  end
  if S.theme_ref_message then parts[#parts+1] = S.theme_ref_message end
  if #parts == 0 then return nil end
  return tbl_concat(parts, "\n\n")
end

-- =============================================================================
-- Net.sticky_text
-- =============================================================================
-- Net.sticky_set / Net.sticky_unset: wrappers that maintain both
-- S.sticky_context (the key -> content map) AND S.sticky_context_order (the
-- insertion-order key list). Use these instead of assigning to
-- S.sticky_context[k] directly -- the order list drives sticky_parts() emit
-- order, which is critical for prefix-cache stability.
--
-- Why insertion order matters: providers (Anthropic, OpenAI, Gemini) cache on
-- exact byte-prefix match. The earlier alphabetical sort shuffled new refs
-- into the middle of the sticky blob (e.g. adding Pro-C 3 pushed it before
-- Pro-Q 4), invalidating the entire cached prefix on every plugin addition.
-- Observed cost: ~15-20K tokens of cache_write on every ref-addition turn,
-- ~50% of total chat cost in a plugin-heavy session. Insertion order keeps
-- appends truly appended -- the prefix through existing refs stays
-- byte-identical and remains cached. See Net.sticky_parts() for the
-- two-block split that also preserves Anthropic block-level caching.
-- Dedup helper: for a fresh plugin_ref:/pref: write, check whether an
-- existing bundled key (same prefix, slash-joined names) already covers
-- this name. If yes, the standalone write is redundant -- skip it and let
-- the caller's "injected" log entry still fire at the bucket-dispatch site.
-- Returns true when the write should be skipped.
local function _sticky_would_duplicate(key)
  local prefix, name = key:match("^([%a_]+:)(.+)$")
  if not prefix or not name then return false end
  if prefix ~= "plugin_ref:" and prefix ~= "pref:" then return false end
  if name:find("/", 1, true) then return false end  -- the new key IS a bundle
  for existing_key in pairs(S.sticky_context or {}) do
    if existing_key ~= key then
      local ex_prefix, ex_names = existing_key:match("^([%a_]+:)(.+)$")
      if ex_prefix == prefix and ex_names and ex_names:find("/", 1, true) then
        for chunk in ex_names:gmatch("[^/]+") do
          if chunk == name then return true end
        end
      end
    end
  end
  return false
end

-- Symmetrical dedup: when a FRESH bundle is added, any standalone entries
-- with the same prefix that name a member of the bundle are now redundant
-- and should be removed. Returns the list of keys that were cleared (caller
-- uses this for logging if it cares).
local function _sticky_evict_standalones_for_bundle(bundle_key)
  local prefix, names = bundle_key:match("^([%a_]+:)(.+)$")
  if not prefix or not names then return {} end
  if prefix ~= "plugin_ref:" and prefix ~= "pref:" then return {} end
  if not names:find("/", 1, true) then return {} end
  local covered = {}
  for chunk in names:gmatch("[^/]+") do covered[chunk] = true end
  local to_evict = {}
  for existing_key in pairs(S.sticky_context or {}) do
    if existing_key ~= bundle_key then
      local ex_prefix, ex_name = existing_key:match("^([%a_]+:)(.+)$")
      if ex_prefix == prefix and ex_name
         and not ex_name:find("/", 1, true)
         and covered[ex_name] then
        to_evict[#to_evict+1] = existing_key
      end
    end
  end
  for _, k in ipairs(to_evict) do Net.sticky_unset(k) end
  return to_evict
end

function Net.sticky_set(key, content)
  if not S.sticky_context_order then S.sticky_context_order = {} end
  local is_fresh = S.sticky_context[key] == nil
  -- First-time add of a singleton that's already covered by an existing
  -- bundle: skip. Every turn before this was paying to send the same
  -- plugin_ref/pref content twice (once inside the bundle, once standalone),
  -- which bloated the sticky blob and invalidated prefix caching further
  -- downstream every time a new standalone landed.
  if is_fresh and _sticky_would_duplicate(key) then
    Log.line("STICKY", "skip redundant " .. key
      .. " (already covered by existing bundle)")
    return
  end
  if is_fresh then
    S.sticky_context_order[#S.sticky_context_order+1] = key
    -- First-time add of a bundle: evict any singletons it now subsumes.
    -- One-time cache-miss cost on the immediate next turn (the blob's
    -- suffix bytes shift), then permanent savings from not resending the
    -- singleton content on every subsequent turn.
    local evicted = _sticky_evict_standalones_for_bundle(key)
    if #evicted > 0 then
      Log.line("STICKY", "evicted " .. tbl_concat(evicted, ", ")
        .. " (subsumed by new bundle " .. key .. ")")
    end
  end
  S.sticky_context[key] = content
end

function Net.sticky_unset(key)
  S.sticky_context[key] = nil
  if not S.sticky_context_order then return end
  for i, k in ipairs(S.sticky_context_order) do
    if k == key then
      table.remove(S.sticky_context_order, i)
      return
    end
  end
end

-- Pin prompt_bundle:plugin into sticky if it's not already there. Called from
-- every site that pins a plugin_ref / pref_plugin / preferred_plugins entry,
-- so that any plugin ADD/CONFIGURE task arrives at the model already holding
-- the plugin workflow rules (find_param / set_param_display etc) -- saves
-- the first-plugin-turn round-trip where the model would otherwise emit
-- <context_needed>prompt_bundle:plugin</context_needed> and wait a full
-- turn before writing the script. The optional out_list parameter, when
-- provided, gets the pb_key appended so the caller can surface the bundle
-- in ctx_label / fetched_to_sticky logs.
function Net.copin_plugin_bundle(out_list)
  local pb_key = "prompt_bundle:plugin"
  if S.sticky_context[pb_key] then return end
  if S.prompt_bundle_sent and S.prompt_bundle_sent["plugin"] then return end
  local pb_content, _ = CTX.prompt_bundle("plugin")
  if not pb_content then return end
  Net.sticky_set(pb_key, pb_content)
  if S.prompt_bundle_sent then S.prompt_bundle_sent["plugin"] = true end
  if out_list then out_list[#out_list+1] = pb_key end
end

-- Returns two text blobs, stable + growing, emitted in sticky_context_order.
--   stable : prompt_bundle:* payloads. Effectively never change once pinned
--            (a bundle is a chunk of system-prompt content for a task type,
--            not a per-plugin reference). Placed in a dedicated Anthropic
--            cache block so its cache rung stays hot across ref-addition
--            turns.
--   growing: everything else (plugin_ref, pref, preferred_plugins,
--            fx_params, fx_inspect, docs_extended). Grows as new plugins
--            are referenced; its cache rung invalidates when a new ref is
--            appended, but that only costs the new ref's tokens -- the
--            stable rung stays cached. A leading manifest line lists ALL
--            pinned keys (stable + growing) so weak models can string-scan
--            before emitting a redundant <context_needed>.
--
-- Both may be nil when their respective bucket set is empty. When only one
-- side has content, the other returns nil. sticky_text() concatenates both
-- for providers without multi-breakpoint caching.
function Net.sticky_parts()
  -- Static refs (docs / midi / theme) live in their own message slots, not in
  -- S.sticky_context, but they're equally "pinned above" from the model's POV.
  -- Include them in the manifest so the model's quick-scan sees them and
  -- doesn't emit a redundant <context_needed>docs</context_needed> (observed
  -- failure mode on weaker models).
  local static_keys = {}
  if S.api_ref_message   then static_keys[#static_keys+1] = "docs"  end
  if S.midi_ref_message  then static_keys[#static_keys+1] = "midi"  end
  if S.theme_ref_message then static_keys[#static_keys+1] = "theme" end

  local stable_keys, growing_keys = {}, {}
  if S.sticky_context_order then
    for _, k in ipairs(S.sticky_context_order) do
      if S.sticky_context[k] then
        if k:find("^prompt_bundle:") then
          stable_keys[#stable_keys+1] = k
        else
          growing_keys[#growing_keys+1] = k
        end
      end
    end
  end

  -- Nothing pinned anywhere: no sticky output.
  if #static_keys == 0 and #stable_keys == 0 and #growing_keys == 0 then
    return nil, nil
  end

  local stable_text
  if #stable_keys > 0 then
    local parts = {}
    for _, k in ipairs(stable_keys) do parts[#parts+1] = S.sticky_context[k] end
    stable_text = tbl_concat(parts, "\n\n")
  end

  -- Always emit the manifest when any pinned bucket exists (static or sticky).
  -- The manifest lists every pinned key so the model can short-circuit
  -- re-requests. Order: static refs first (stable slot), then stable sticky
  -- (prompt_bundle:*), then growing sticky (plugin_ref/pref/fx_*).
  --
  -- LAYOUT WITHIN growing_text (cache-stability-driven):
  --   1. Byte-stable preamble (fixed text -- never changes).
  --   2. Plugin content in insertion order (sticky_context_order). This
  --      block's prefix bytes are stable across additions because content
  --      only ever appends to the end.
  --   3. Manifest at the END.
  -- Why manifest-at-end: the manifest line gains a key every time a plugin
  -- is added. Putting it at the TOP made byte 0 of growing_text differ on
  -- every addition, invalidating the entire growing cache rung. With the
  -- manifest at the end, the plugin-content prefix stays byte-identical
  -- across additions, so Anthropic's cache hits up through the previous
  -- turn's content -- only the new plugin's content + new manifest +
  -- last_asst need fresh cache_write. ~10-15K cache_write savings per
  -- ref-addition turn.
  local all_keys = {}
  for _, k in ipairs(static_keys)  do all_keys[#all_keys+1] = k end
  for _, k in ipairs(stable_keys)  do all_keys[#all_keys+1] = k end
  for _, k in ipairs(growing_keys) do all_keys[#all_keys+1] = k end
  local growing_parts = {}
  if #growing_keys > 0 then
    -- Byte-stable preamble (no key list -- fixed text). Cues the model that
    -- a manifest exists at the bottom of this section without changing the
    -- byte content turn-to-turn.
    growing_parts[#growing_parts+1] =
      "PINNED REFERENCES section follows. Full manifest at the END of this section."
    -- Plugin content in insertion order. Append-only is critical for cache
    -- stability -- see Net.sticky_set / sticky_context_order.
    for _, k in ipairs(growing_keys) do
      growing_parts[#growing_parts+1] = S.sticky_context[k]
    end
  end
  growing_parts[#growing_parts+1] =
    "PINNED REFERENCES (already provided above; do NOT re-request via "
    .. "<context_needed>): " .. tbl_concat(all_keys, ", ")
  local growing_text = tbl_concat(growing_parts, "\n\n")

  return stable_text, growing_text
end

-- Legacy single-blob accessor for providers without multi-breakpoint caching
-- (or for logging / diagnostics). Concatenates stable + growing preserving
-- insertion order. Returns nil when both sides are empty.
function Net.sticky_text()
  local s, g = Net.sticky_parts()
  if not s and not g then return nil end
  if s and g then return s .. "\n\n" .. g end
  return s or g
end

-- =============================================================================
-- Net.sticky_evict
-- =============================================================================
-- Keeps S.sticky_context bounded over long sessions. Without this, every
-- plugin_ref / pref_plugins / fx_params bucket ever pinned in the session
-- stays in sticky forever, growing the prefix linearly and re-sending
-- 50-100K of irrelevant data on every turn for cinematic / 30+ turn sessions.
--
-- Strategy: each key has a "last touched" turn (sticky_context_age[k]).
--   - Unknown keys (just added) are treated as touched on the current turn.
--   - Keys whose payload identifier (the part after the colon) appears in
--     the current user prompt are refreshed to the current turn.
--   - Keys older than STICKY_MAX_AGE turns are evicted.
-- Conservative -- a re-mentioned plugin survives indefinitely; only truly
-- abandoned context gets pruned.
local STICKY_MAX_AGE = 10  -- turns

function Net.sticky_evict(user_text)
  if not S.sticky_context then return end
  S.turn_counter = (S.turn_counter or 0) + 1
  local now = S.turn_counter
  local age = S.sticky_context_age
  if not age then S.sticky_context_age = {}; age = S.sticky_context_age end
  local lower = (user_text or ""):lower()
  -- Initialize new keys, refresh keys whose identifier hits in the prompt.
  for k in pairs(S.sticky_context) do
    if not age[k] then age[k] = now end
    local ident = k:match("^[^:]+:(.+)$")
    if ident and lower ~= "" and lower:find(ident:lower(), 1, true) then
      age[k] = now
    end
  end
  -- Drop stale keys + clean up orphaned age entries.
  local evicted
  for k, t in pairs(age) do
    if not S.sticky_context[k] then
      age[k] = nil
    elseif (now - t) > STICKY_MAX_AGE then
      Net.sticky_unset(k)   -- also removes k from sticky_context_order
      age[k] = nil
      evicted = (evicted or {})
      evicted[#evicted+1] = k
    end
  end
  if evicted then
    Log.line("STICKY", "evicted (age > " .. STICKY_MAX_AGE
      .. " turns): " .. tbl_concat(evicted, ", "))
  end
end

-- =============================================================================
-- Net.build_body (provider dispatch)
-- =============================================================================
-- Constructs the complete API request JSON body. Dispatches to a provider-specific
-- builder based on the active provider. Each builder handles system prompt
-- packaging, message formatting, attachment encoding, and any provider-specific
-- features (e.g. Anthropic prompt caching).
function Net.build_body(msgs, snapshot, msg_attachments)
  local p = PROVIDERS.active()
  if p.id == "anthropic" then
    return Net.build_body_anthropic(msgs, snapshot, msg_attachments)
  elseif p.id == "openai" or p.is_custom then
    -- Custom providers always speak the OpenAI Chat Completions schema (the
    -- de-facto standard for OSS servers like Ollama, LM Studio, vLLM).
    return Net.build_body_openai(msgs, snapshot, msg_attachments)
  elseif p.id == "google" then
    return Net.build_body_google(msgs, snapshot, msg_attachments)
  end
end

-- =============================================================================
-- Net.build_body_anthropic
-- =============================================================================
-- Anthropic Messages API format. System prompt as top-level "system" field with
-- cache_control. Pinned API ref as first user message (stable cache position).
-- Snapshot injected as a separate content block in the last user message.
--
-- Cache breakpoints (max 4 allowed by Anthropic, we use up to 4):
--   1. System prompt           -- 1h TTL (never changes within a session)
--   2. API ref user message    -- 1h TTL (only present when api_ref loaded)
--   3. MIDI ref user message   -- 1h TTL (only present when midi_ref loaded)
--   4. Last assistant message  -- 1h TTL (moving breakpoint, prefix grows
--                                  one user/assistant pair per turn)
-- All use the extended 1-hour TTL via the extended-cache-ttl-2025-04-11
-- beta header. The 2x write cost is recouped after a single saved refresh,
-- which happens easily in typical ReaAssist sessions where the user reads
-- docs or tests generated code between sends.
local CACHE_1H = ',"cache_control":{"type":"ephemeral","ttl":"1h"}'
-- Fallback cache marker used when the extended-cache-ttl beta header has been
-- rejected by the API (see S.anthropic_beta_disabled). 5-minute ephemeral
-- caching is the default tier and requires no beta header.
local CACHE_5M = ',"cache_control":{"type":"ephemeral"}'

function Net.build_body_anthropic(msgs, snapshot, msg_attachments)
  -- Pick the cache marker based on whether the beta header is still accepted.
  -- If Anthropic ever deprecates extended-cache-ttl-2025-04-11, a single 400
  -- trip through the error handler flips the flag and all subsequent sends
  -- land in the 5-minute branch below.
  local cache_mark = S.anthropic_beta_disabled and CACHE_5M or CACHE_1H

  local system_json = str_format(
    '[{"type":"text","text":"%s"%s}]',
    JSON.escape(Net.system_prompt_text()), cache_mark)

  local msg_parts = {}

  -- Bundle the long-lived static refs (api_ref + midi_ref + theme_ref) into
  -- ONE pinned user message with a single trailing ack, instead of three
  -- separate user/ack pairs. Saves ~16-24 tokens per turn in ack overhead
  -- and reduces alignment churn for downstream caches when refs come in.
  -- Anthropic 4-breakpoint allocation:
  --   slot 1: system                                   (always)
  --   slot 2: end of static_blob + sticky_stable       (when sticky_stable
  --                                                     present; static_blob
  --                                                     piggybacks on this rung)
  --           OR static_blob                           (when sticky_stable
  --                                                     absent but static_blob
  --                                                     present)
  --           OR sticky_stable                         (when static_blob absent)
  --   slot 3: sticky_growing                           (when present)
  --   slot 4: last_asst                                (moving, when history
  --                                                     has >= 1 complete turn)
  -- Why static_blob loses its dedicated cache mark when sticky_stable is
  -- present: a single-rung cache covering "system + static_blob + sticky_stable"
  -- is functionally identical to two separate rungs (any change to static_blob
  -- invalidates sticky_stable's prefix anyway), but it FREES a breakpoint slot
  -- so sticky_growing can have its own rung. The win: when sticky_growing
  -- changes (every fx_inspect / plugin_ref / pref addition), sticky_stable
  -- (~14K plugin bundle) keeps reading from cache instead of being rewritten
  -- alongside the growing block. Observed cost before this change: ~10-15K
  -- cache_write per ref-addition turn.
  local sticky_stable, sticky_growing = Net.sticky_parts()
  local static_blob = Net.bundled_static_refs()
  if static_blob then
    -- Drop static_blob's own cache_mark when sticky_stable will absorb it
    -- into the next rung. Keep it when sticky_stable is absent (otherwise
    -- static_blob would only cache via sticky_growing's rung, which gets
    -- invalidated frequently).
    local static_cache_mark = sticky_stable and "" or cache_mark
    msg_parts[#msg_parts+1] = str_format(
      '{"role":"user","content":[{"type":"text","text":"%s"%s}]}',
      JSON.escape(static_blob), static_cache_mark)
    msg_parts[#msg_parts+1] = '{"role":"assistant","content":[{"type":"text","text":"Understood."}]}'
  end
  -- Pinned sticky with up to TWO cache_control breakpoints:
  --   - sticky_stable  : prompt_bundle:* payloads (big, effectively frozen
  --                      for the rest of the session). Own cache rung so it
  --                      stays hot even when the growing block invalidates.
  --   - sticky_growing : plugin_ref / pref / fx_params / fx_inspect, plus
  --                      a manifest line listing all pinned keys. Its cache
  --                      rung re-writes on each ref addition but the stable
  --                      rung's ~15K tokens no longer get re-written with it.
  -- The 2-block split now fires whenever both halves are populated -- the
  -- breakpoint budget is free because static_blob piggybacks on sticky_stable.
  local has_sticky = sticky_stable or sticky_growing
  if has_sticky then
    local can_split = sticky_stable and sticky_growing
    if can_split then
      -- Two content blocks in ONE user message, each with its own
      -- cache_control. Anthropic caches each block as its own prefix rung:
      -- adding a new plugin_ref changes the growing block but NOT the
      -- stable block, so the stable rung keeps reading on subsequent
      -- turns. Saves ~15K tokens of cache_write per ref-addition turn.
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"user","content":[{"type":"text","text":"%s"%s},{"type":"text","text":"%s"%s}]}',
        JSON.escape(sticky_stable), cache_mark,
        JSON.escape(sticky_growing), cache_mark)
    else
      -- Single-block fallback: only one of stable/growing is populated.
      -- Concatenate in stable-first order so byte-prefix caching still wins
      -- on OpenAI-style implicit cache if we're ever reused there.
      local blob = sticky_stable and sticky_growing
        and (sticky_stable .. "\n\n" .. sticky_growing)
        or  (sticky_stable or sticky_growing)
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"user","content":[{"type":"text","text":"%s"%s}]}',
        JSON.escape(blob), cache_mark)
    end
    msg_parts[#msg_parts+1] = '{"role":"assistant","content":[{"type":"text","text":"Understood."}]}'
  end

  for idx, m in ipairs(msgs) do
    local is_last_user = (m.role == "user" and idx == #msgs)

    if is_last_user then
      -- Build content blocks for the last user message: text + snapshot + attachments.
      local blocks = {}
      blocks[#blocks+1] = str_format('{"type":"text","text":"%s"}',
        JSON.escape(m.content))

      if snapshot then
        blocks[#blocks+1] = str_format('{"type":"text","text":"%s"}',
          JSON.escape(snapshot))
      end

      -- Append attachment content blocks (images, PDFs, text files).
      if msg_attachments then
        for _, att in ipairs(msg_attachments) do
          if att.kind == "image" then
            blocks[#blocks+1] = str_format(
              '{"type":"image","source":{"type":"base64","media_type":"%s","data":"%s"}}',
              att.media_type, att.b64)
          elseif att.kind == "pdf" then
            blocks[#blocks+1] = str_format(
              '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"%s"}}',
              att.b64)
          elseif att.kind == "text" then
            blocks[#blocks+1] = str_format(
              '{"type":"text","text":"[Attached file: %s]\\n%s"}',
              JSON.escape(att.name), JSON.escape(att.data))
          end
        end
      end

      msg_parts[#msg_parts+1] = str_format(
        '{"role":"user","content":[%s]}', tbl_concat(blocks, ","))
    else
      -- Non-final messages: single block. Mark the last assistant message as a
      -- moving cache breakpoint so the conversation prefix is cached for
      -- cheaper follow-up turns.
      local is_last_asst = (m.role == "assistant" and idx == #msgs - 1)
      local cache = is_last_asst and cache_mark or ""
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"%s","content":[{"type":"text","text":"%s"%s}]}',
        m.role, JSON.escape(m.content), cache)
    end
  end

  return str_format(
    '{"model":"%s","max_tokens":%d,"system":%s,"messages":[%s]}',
    MODELS.active_id(), CFG.MAX_TOKENS, system_json, tbl_concat(msg_parts, ","))
end

-- =============================================================================
-- Net.build_body_openai
-- =============================================================================
-- OpenAI Chat Completions API format. System prompt as a "system" role message.
-- All messages are simple {role, content} objects. Attachments: images as
-- image_url content parts, text files inline, PDFs as text note (unsupported).
function Net.build_body_openai(msgs, snapshot, msg_attachments)
  local msg_parts = {}

  -- System prompt as the first message.
  msg_parts[#msg_parts+1] = str_format(
    '{"role":"system","content":"%s"}', JSON.escape(Net.system_prompt_text()))

  -- Bundle the long-lived static refs (api_ref + midi_ref + theme_ref) into
  -- ONE pinned system message instead of three. OpenAI's implicit prefix
  -- caching aligns on byte-level prefix; fewer message boundaries mean a
  -- cleaner, more stable prefix. See Net.bundled_static_refs().
  local static_blob = Net.bundled_static_refs()
  if static_blob then
    msg_parts[#msg_parts+1] = str_format(
      '{"role":"system","content":"%s"}', JSON.escape(static_blob))
  end

  -- Prepend pinned sticky context (plugin_ref / pref_plugins / fx_params /
  -- fx_inspect) as a system message so OpenAI's implicit prefix caching can
  -- discover the stable common prefix across turns. See Net.sticky_text().
  local sticky_blob = Net.sticky_text()
  if sticky_blob then
    msg_parts[#msg_parts+1] = str_format(
      '{"role":"system","content":"%s"}', JSON.escape(sticky_blob))
  end

  for idx, m in ipairs(msgs) do
    local is_last_user = (m.role == "user" and idx == #msgs)

    if is_last_user then
      -- Last user message: may include snapshot and attachments as content array.
      local has_extras = snapshot or msg_attachments
      if has_extras then
        local blocks = {}
        blocks[#blocks+1] = str_format('{"type":"text","text":"%s"}',
          JSON.escape(m.content))
        if snapshot then
          blocks[#blocks+1] = str_format('{"type":"text","text":"%s"}',
            JSON.escape(snapshot))
        end
        if msg_attachments then
          for _, att in ipairs(msg_attachments) do
            if att.kind == "image" then
              blocks[#blocks+1] = str_format(
                '{"type":"image_url","image_url":{"url":"data:%s;base64,%s"}}',
                att.media_type, att.b64)
            elseif att.kind == "text" then
              blocks[#blocks+1] = str_format(
                '{"type":"text","text":"[Attached file: %s]\\n%s"}',
                JSON.escape(att.name), JSON.escape(att.data))
            elseif att.kind == "pdf" then
              blocks[#blocks+1] = str_format(
                '{"type":"text","text":"[Attached PDF: %s] (PDF content attached as document)"}',
                JSON.escape(att.name))
            end
          end
        end
        msg_parts[#msg_parts+1] = str_format(
          '{"role":"user","content":[%s]}', tbl_concat(blocks, ","))
      else
        msg_parts[#msg_parts+1] = str_format(
          '{"role":"user","content":"%s"}', JSON.escape(m.content))
      end
    else
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"%s","content":"%s"}', m.role, JSON.escape(m.content))
    end
  end

  local p = PROVIDERS.active()
  -- reasoning_effort: top-level string on the Chat Completions API.
  -- Valid values: "minimal" | "low" | "medium" | "high". The dropdown's "none"
  -- entry means "do not send the field" -- omitting it disables reasoning.
  local reasoning = ""
  if prefs.thinking_idx > 0 then
    if p.thinking_levels and p.thinking_levels[prefs.thinking_idx] then
      local val = p.thinking_levels[prefs.thinking_idx].value
      if val and val ~= "none" then
        reasoning = str_format(',"reasoning_effort":"%s"', val)
      end
    end
  end
  -- prompt_cache_key: stable per script-session identifier. OpenAI's automatic
  -- prefix caching auto-routes requests sharing this key to the same backend
  -- worker, raising cache-hit rate on long sessions. The key is opaque to us.
  -- Custom-provider model prefix: OpenRouter/LiteLLM/Ollama routing gateways
  -- often require a prefix ("openrouter/anthropic/...", "ollama/...") on the
  -- model id. Stored per-provider so users don't have to type it into every
  -- model row. Empty string = no-op, matching hosted OpenAI's behaviour.
  local model_id = MODELS.active_id()
  if p.is_custom and p.model_prefix and p.model_prefix ~= "" then
    model_id = p.model_prefix .. model_id
  end
  -- Custom-provider extra_body: merge provider-wide + per-model JSON objects
  -- into the outer request body. Per-model keys win over provider-wide keys
  -- via an in-order decode/merge/re-encode pass. Used for vendor-specific
  -- toggles that don't map to the OpenAI schema (Kimi thinking flag, Qwen
  -- enable_thinking, OpenRouter reasoning object, etc.). Runs through
  -- JSON.decode / JSON.encode so we don't brace-splice raw user input.
  local extra_suffix = ""
  if p.is_custom then
    local prov_body  = p.extra_body or ""
    local model_body = ""
    local active_m = MODELS[prefs.model_idx]
    if active_m and active_m.extra_body then model_body = active_m.extra_body end
    if prov_body ~= "" or model_body ~= "" then
      local merged = {}
      if prov_body ~= "" then
        local pobj = JSON.decode(prov_body)
        if type(pobj) == "table" then
          for k, v in pairs(pobj) do merged[k] = v end
        end
      end
      if model_body ~= "" then
        local mobj = JSON.decode(model_body)
        if type(mobj) == "table" then
          for k, v in pairs(mobj) do merged[k] = v end
        end
      end
      local encoded = JSON.encode(merged)
      if encoded and encoded ~= "{}" and encoded:sub(1, 1) == "{"
         and encoded:sub(-1) == "}" then
        local inner = encoded:sub(2, -2)
        if inner ~= "" then extra_suffix = "," .. inner end
      end
    end
  end
  return str_format(
    '{"model":"%s","max_completion_tokens":%d,"prompt_cache_key":"%s","messages":[%s]%s%s}',
    model_id, CFG.MAX_TOKENS, JSON.escape(S.INSTANCE_ID),
    tbl_concat(msg_parts, ","), reasoning, extra_suffix)
end

-- =============================================================================
-- Net.build_body_google
-- =============================================================================
-- Gemini generateContent API format. System prompt as systemInstruction.
-- Messages as contents[]. Role mapping: "assistant" -> "model".
-- Attachments: images and PDFs as inlineData parts, text files inline.
--
-- If a Gemini explicit context cache is active and valid for the current
-- model, the cached content (system_instruction + api_ref priming) is
-- referenced via cachedContent and omitted from the live request body.
function Net.build_body_google(msgs, snapshot, msg_attachments)
  local msg_parts = {}
  local use_cache = Net.gemini_cache_is_usable()

  -- Bundle the long-lived static refs (api_ref + midi_ref + theme_ref) into
  -- ONE pinned user+model exchange instead of three. Fewer turns inside
  -- contents[] is cleaner for Gemini's implicit prefix caching to align on.
  -- When the explicit context cache is active, it already covers api_ref +
  -- system_instruction, so we omit api_ref from the bundle in that case to
  -- avoid double-sending it.
  local static_parts = {}
  if S.api_ref_message and not use_cache then
    static_parts[#static_parts+1] = S.api_ref_message
  end
  if S.midi_ref_message  then static_parts[#static_parts+1] = S.midi_ref_message  end
  if S.theme_ref_message then static_parts[#static_parts+1] = S.theme_ref_message end
  if #static_parts > 0 then
    local static_blob = tbl_concat(static_parts, "\n\n")
    msg_parts[#msg_parts+1] = str_format(
      '{"role":"user","parts":[{"text":"%s"}]}', JSON.escape(static_blob))
    msg_parts[#msg_parts+1] = '{"role":"model","parts":[{"text":"Understood."}]}'
  end

  -- Prepend pinned sticky context (plugin_ref / pref_plugins / fx_params /
  -- fx_inspect) as a user+model exchange. Sits in a stable prefix position
  -- so Gemini's implicit caching (and explicit cache if it covers here) can
  -- match it across turns. See Net.sticky_text(). Deliberately NOT included
  -- in the Gemini explicit cache (that stays scoped to api_ref only), so
  -- sticky growth doesn't force cache recreation.
  local sticky_blob = Net.sticky_text()
  if sticky_blob then
    msg_parts[#msg_parts+1] = str_format(
      '{"role":"user","parts":[{"text":"%s"}]}', JSON.escape(sticky_blob))
    msg_parts[#msg_parts+1] = '{"role":"model","parts":[{"text":"Understood."}]}'
  end

  for idx, m in ipairs(msgs) do
    local is_last_user = (m.role == "user" and idx == #msgs)
    -- Gemini uses "model" instead of "assistant".
    local role = (m.role == "assistant") and "model" or m.role

    if is_last_user then
      local parts = {}
      parts[#parts+1] = str_format('{"text":"%s"}', JSON.escape(m.content))
      if snapshot then
        parts[#parts+1] = str_format('{"text":"%s"}', JSON.escape(snapshot))
      end
      if msg_attachments then
        for _, att in ipairs(msg_attachments) do
          if att.kind == "image" then
            parts[#parts+1] = str_format(
              '{"inlineData":{"mimeType":"%s","data":"%s"}}',
              att.media_type, att.b64)
          elseif att.kind == "pdf" then
            parts[#parts+1] = str_format(
              '{"inlineData":{"mimeType":"application/pdf","data":"%s"}}',
              att.b64)
          elseif att.kind == "text" then
            parts[#parts+1] = str_format(
              '{"text":"[Attached file: %s]\\n%s"}',
              JSON.escape(att.name), JSON.escape(att.data))
          end
        end
      end
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"user","parts":[%s]}', tbl_concat(parts, ","))
    else
      msg_parts[#msg_parts+1] = str_format(
        '{"role":"%s","parts":[{"text":"%s"}]}', role, JSON.escape(m.content))
    end
  end

  local thinking = ""
  if prefs.thinking_idx > 0 then
    local p = PROVIDERS.active()
    local m = MODELS[prefs.model_idx] or MODELS[1]
    if p.thinking_levels then
      -- If Pro model and MINIMAL selected, bump to LOW (MINIMAL is flash-only)
      local tidx = prefs.thinking_idx
      local tl = p.thinking_levels[tidx]
      if tl and tl.flash_only and not m.is_flash then
        tidx = math_min(tidx + 1, #p.thinking_levels)  -- next level (LOW)
        tl = p.thinking_levels[tidx]
      end
      if tl then
        thinking = str_format(',"thinkingConfig":{"thinkingLevel":"%s","includeThoughts":false}', tl.value)
      end
    end
  end
  if use_cache then
    -- system_instruction lives inside the cache; omit it from the live body.
    return str_format(
      '{"contents":[%s],"cachedContent":"%s","generationConfig":{"maxOutputTokens":%d%s}}',
      tbl_concat(msg_parts, ","), S.gemini_cache_name, CFG.MAX_TOKENS, thinking)
  end
  return str_format(
    '{"contents":[%s],"systemInstruction":{"parts":[{"text":"%s"}]},"generationConfig":{"maxOutputTokens":%d%s}}',
    tbl_concat(msg_parts, ","), JSON.escape(Net.system_prompt_text()), CFG.MAX_TOKENS, thinking)
end

-- =============================================================================
-- Net.trimmed_history
-- =============================================================================
-- Returns the last CFG.MAX_HISTORY_TURNS entries from S.history for the API call.
-- The full S.history table is preserved for display; only the slice is sent.
-- If the first entry in the slice is an assistant message (possible if an
-- odd number of entries were removed mid-conversation), it is dropped so
-- the API always receives a conversation starting with a user turn.
function Net.trimmed_history()
  if #S.history <= CFG.MAX_HISTORY_TURNS then return S.history end
  local trimmed = {}
  for i = #S.history - CFG.MAX_HISTORY_TURNS + 1, #S.history do
    trimmed[#trimmed+1] = S.history[i]
  end
  if #trimmed > 0 and trimmed[1].role == "assistant" then
    tbl_remove(trimmed, 1)
  end
  if #trimmed == 0 then
    -- Slice was a single assistant entry that we just dropped. Return
    -- just the most recent message rather than falling back to the
    -- FULL untrimmed S.history (latent overshoot of the trim budget;
    -- only triggerable at very low MAX_HISTORY_TURNS, but the previous
    -- behaviour silently sent every prior turn, defeating the trim).
    return { S.history[#S.history] }
  end
  return trimmed
end

-- =============================================================================
-- Net.fire_curl
-- =============================================================================
-- Writes the JSON body to a temp file and launches curl asynchronously.
-- Provider-aware: builds the endpoint URL, auth headers, and extra headers
-- dynamically from the active PROVIDERS entry.
--
-- Auth strategies:
--   header      (Claude, OpenAI, Gemini): key sent via -H @file so it never
--               appears on the command line. The auth file is cleaned up after
--               curl. Each provider specifies its own auth_header name.
--
-- Both platforms use an async pattern: curl runs in the background, writes
-- its response to tmp.out, and echoes its exit code to tmp.exit.
-- Net.try_finish_curl() polls both files each frame to detect completion.
--
-- Windows: the curl command is inlined directly into a PowerShell -Command
--   string launched via Start-Process -WindowStyle Hidden.
-- macOS/Linux: trailing "&" backgrounds the shell pipeline.
-- opts (optional table) lets the caller request a non-standard request shape:
--   opts.method            -- "GET" to send an empty GET instead of POST
--   opts.endpoint_override -- full URL to use instead of the provider's endpoint
-- Both are used by the custom-LLM connection test, which hits GET /v1/models
-- so no inference runs on the server. When method=="GET" we skip the body
-- write, the content-type header, and the -d flag; nil/POST behaves as before.
function Net.fire_curl(body, opts)
  -- TCP/TLS handshake timeout (seconds). Default 10 for cloud providers;
  -- per-record override for customs set below.
  local connect_timeout = 10
  -- Guard against double-send.
  if S.curl_pid then return false end

  local method   = (opts and opts.method) or "POST"
  local is_get   = (method == "GET")

  if not is_get then
    if not Code.safe_write(tmp.body, body) then return false end
  end

  local p = PROVIDERS.active()

  Log.request(p.label, is_get and ("[GET " .. (opts.endpoint_override or "?") .. "]") or body)

  -- Local LLMs (custom OpenAI-compatible endpoints) need a much longer timeout
  -- than cloud providers: prompt processing alone for a 15K-token context can
  -- take 1-2 minutes on consumer hardware before any tokens stream back. Cloud
  -- providers respond in seconds, so the snappy 30s ceiling stays for them.
  -- Custom providers expose a user-configurable per-provider timeout (set on
  -- the API Keys page); fall back to the 10-minute default if missing.
  local curl_timeout = (p.is_custom and (tonumber(p.request_timeout) or 600))
                       or CFG.CURL_TIMEOUT

  -- Custom-provider TCP/TLS handshake override. Cloud providers keep the
  -- fixed 10s default because every hosted endpoint is consistently reachable
  -- in under a second; customs can be behind slow CDNs or local servers that
  -- need more breathing room, so we expose a per-record knob.
  if p.is_custom and tonumber(p.connect_timeout) then
    connect_timeout = tonumber(p.connect_timeout)
  end

  -- Key-test override for custom providers. The curl --max-time is capped to
  -- the user-configured "Connection test timeout" (default 30s). Prevents a
  -- stalled/unresponsive model from blocking the row-test queue for the full
  -- request timeout (up to 1 hour). Also shortens the connect-timeout so a
  -- test against a dead port fails quickly instead of waiting the full
  -- per-provider handshake budget.
  if S.key_test_pending and p.is_custom then
    curl_timeout    = tonumber(S.key_test_custom_timeout)
                      or CUSTOM_DEFAULT_TEST_TIMEOUT
    connect_timeout = 3
  end

  -- --insecure: skip TLS verification when the custom provider has it set.
  -- Only ever applied to custom providers (cloud providers always validate).
  -- Emitted as a standalone flag in both Windows and POSIX branches below.
  local insecure_flag = (p.is_custom and p.allow_insecure) and " --insecure" or ""

  -- Build the endpoint URL.
  local endpoint
  if opts and opts.endpoint_override then
    endpoint = opts.endpoint_override
  elseif p.endpoint_tpl then
    endpoint = str_format(p.endpoint_tpl, MODELS.active_id())
  else
    endpoint = p.endpoint
  end
  -- Write the auth header file (header-based auth only). Custom providers may
  -- have no key at all -- in that case skip the auth file so we don't send a
  -- bare "Authorization: Bearer " header that some servers reject.
  local use_auth_file = (p.auth_style == "header")
    and S.api_key ~= nil and S.api_key ~= ""
  if use_auth_file then
    local auth_value = (p.auth_prefix or "") .. S.api_key
    if not Code.safe_write(tmp.auth, p.auth_header .. ": " .. auth_value) then return false end
  end

  -- Clear any stale exit code / pid / response file from a previous request.
  -- The pid file is rewritten by the launched process; clearing first ensures
  -- Net.kill_curl never sees a stale PID from a finished request. tmp.out
  -- MUST also be cleared -- Net.try_finish_curl reads it every poll tick and
  -- only short-circuits on empty (<2 bytes); leaving the previous response's
  -- bytes in place makes the poller latch onto the prior response (which
  -- will even JSON-parse) before the new curl has had a chance to overwrite
  -- it, producing a stale instant "response".
  os.remove(tmp.exit)
  os.remove(tmp.pid)
  Code.safe_write(tmp.out, "")

  -- Build the list of extra header flags. Skip the Anthropic extended-cache
  -- beta header if it has been rejected earlier this session -- paired with
  -- the 5-minute fallback in build_body_anthropic.
  local extra_h_parts = {}
  for _, h in ipairs(p.extra_headers) do
    if not (S.anthropic_beta_disabled
            and p.id == "anthropic"
            and h:find("extended%-cache%-ttl", 1, false)) then
      extra_h_parts[#extra_h_parts+1] = h
    end
  end

  if RA.IS_WINDOWS then
    -- Escape paths for embedding inside PowerShell single-quoted strings.
    local function ps_escape(path) return path:gsub("'", "''") end

    -- Build header flags for cmd.exe (triple-quoted for PowerShell).
    local h_flags = ""
    if use_auth_file then
      h_flags = h_flags .. ' -H @"""' .. tmp.auth .. '"""'
    end
    for _, h in ipairs(extra_h_parts) do
      h_flags = h_flags .. ' -H """' .. h .. '"""'
    end
    if not is_get then
      h_flags = h_flags .. ' -H """content-type: application/json"""'
    end

    -- Cleanup: delete auth file only if we wrote one.
    local cleanup = use_auth_file
      and (' & del """' .. tmp.auth .. '"""') or ""

    local body_flags = is_get and ""
      or (' -d @"""' .. tmp.body .. '"""')
    local cmd_line = str_format(
      'curl -s%s --connect-timeout %d --max-time %d'
      .. ' -X %s """%s"""'
      .. '%s'
      .. '%s -o """%s"""'
      .. ' & echo %%errorlevel%% > """%s"""'
      .. '%s',
      insecure_flag,
      connect_timeout, curl_timeout,
      method, endpoint,
      h_flags,
      body_flags, tmp.out,
      tmp.exit,
      cleanup)

    -- Use Start-Process -PassThru so PowerShell hands us back the launched
    -- cmd.exe process object. We persist its PID to tmp.pid so Net.kill_curl
    -- can later run `taskkill /F /T /PID <pid>` to terminate the entire
    -- cmd+curl process tree on Cancel.
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "$p = Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden -PassThru;'
      .. ' $p.Id | Out-File -Encoding ASCII -FilePath \'%s\'"',
      ps_escape(cmd_line), ps_escape(tmp.pid))
    reaper.ExecProcess(ps_cmd, 5000)
  else
    -- macOS / Linux: launch curl in the background via shell.
    local function sq(path)
      return "'" .. path:gsub("'", "'\\''") .. "'"
    end

    -- Build header flags for shell. Each header is wrapped with sq() so
    -- $VAR, backticks, "\", and " in a custom provider header are treated
    -- as literal bytes by the shell rather than expanded or parsed. The
    -- header_is_safe() validator already rejects newlines and nulls; sq()
    -- handles every other shell-meaningful character.
    local h_flags = ""
    if use_auth_file then
      h_flags = h_flags .. ' -H @' .. sq(tmp.auth)
    end
    for _, h in ipairs(extra_h_parts) do
      h_flags = h_flags .. ' -H ' .. sq(h)
    end
    if not is_get then
      h_flags = h_flags .. ' -H ' .. sq("content-type: application/json")
    end

    local cleanup = use_auth_file
      and (' ; rm -f ' .. sq(tmp.auth)) or ""

    local body_flags = is_get and "" or (' -d @' .. sq(tmp.body))

    -- Wrap entire pipeline in a subshell so & backgrounds curl+echo together.
    -- Background curl inside the subshell so we can capture its PID via $!,
    -- write it to tmp.pid (so Net.kill_curl can `kill -9 <pid>` on Cancel),
    -- then `wait` for curl and record its real exit code in tmp.exit.
    local unix_curl = str_format(
      '(curl -s%s --connect-timeout %d --max-time %d'
      .. ' -X %s %s'
      .. '%s'
      .. '%s -o %s & CURL_PID=$! ; echo $CURL_PID > %s ; wait $CURL_PID ; echo $? > %s%s) &',
      insecure_flag,
      connect_timeout, curl_timeout,
      method, sq(endpoint),
      h_flags,
      body_flags, sq(tmp.out),
      sq(tmp.pid),
      sq(tmp.exit),
      cleanup)
    os.execute(unix_curl)
  end

  S.curl_pid              = true
  S.curl_exited_clean     = false  -- reset partial-read guard for new request
  S.kill_pending          = false  -- a fresh request voids any stale Cancel watchdog
  S.send_time             = time_precise()
  S.retry_saved_body      = body  -- saved so a 529/overload retry can re-send
  S.pending_provider_idx  = prefs.provider_idx  -- snapshot for response parsing
  S.pending_model_idx     = prefs.model_idx
  return true
end

-- =============================================================================
-- Net.kill_curl
-- =============================================================================
-- Forcibly terminates the in-flight curl request launched by Net.fire_curl.
-- Reads the OS PID written to tmp.pid by the launcher and runs the platform's
-- kill command. Without this, pressing Cancel only resets ReaAssist's state --
-- the underlying curl process keeps running, holding bandwidth and possibly
-- writing a stale response into tmp.out that contaminates the next request.
--
-- Windows: PowerShell wrote cmd.exe's PID; taskkill /T tears down the entire
-- cmd+curl process tree.
-- Unix: the shell wrapper wrote curl's PID directly; kill -9 ends it, which
-- causes the parent subshell's `wait` to return non-zero into tmp.exit.
function Net.kill_curl()
  -- Tier-test path doesn't capture a PID (no Start-Process -PassThru / $!),
  -- so there is no process to kill. The tier-test curl runs to completion
  -- under its own --connect-timeout 10 / --max-time 30 budget. Bail early
  -- and clear the tier flag so the post-Cancel state stays consistent.
  if S.gemini_tier_pending then
    Log.line("CANCEL", "tier test in flight; nothing to kill (no PID captured)")
    S.gemini_tier_pending = false
    return
  end
  local f = io.open(tmp.pid, "r")
  if not f then
    -- The launcher (PowerShell on Windows, sh on Unix) hasn't written the pid
    -- file yet -- there is a several-hundred-ms gap between Start-Process and
    -- Out-File on Windows in particular. Arm the deferred-kill watchdog so
    -- the main loop keeps retrying until either the pid file shows up or the
    -- deadline elapses; without this, a rapid Send -> Cancel leaves the
    -- background curl alive holding bandwidth and writing into tmp.out.
    S.kill_pending       = true
    S.kill_pending_until = reaper.time_precise() + 2.0
    return
  end
  local pid_text = f:read("*a") or ""
  f:close()
  local pid = pid_text:match("(%d+)")
  if not pid then
    -- File exists but is still mid-write (very rare but possible). Same fix.
    S.kill_pending       = true
    S.kill_pending_until = reaper.time_precise() + 2.0
    return
  end
  if RA.IS_WINDOWS then
    -- /F = force, /T = include child process tree.
    reaper.ExecProcess('cmd /c taskkill /F /T /PID ' .. pid, 2000)
  else
    reaper.ExecProcess('/bin/sh -c "kill -9 ' .. pid .. ' 2>/dev/null"', 2000)
  end
  -- Remove the pid file so a stray Cancel after this call doesn't try to kill
  -- a now-finished or PID-recycled process.
  os.remove(tmp.pid)
  S.kill_pending = false
end

-- =============================================================================
-- Net.try_finish_kill_pending
-- =============================================================================
-- Polled from the main loop while S.kill_pending is true. Re-attempts kill_curl
-- once the pid file lands (or until the deadline elapses, after which we give
-- up to avoid burning CPU forever on a request whose launcher silently failed).
function Net.try_finish_kill_pending()
  if not S.kill_pending then return end
  if reaper.time_precise() > S.kill_pending_until then
    S.kill_pending = false
    return
  end
  local f = io.open(tmp.pid, "r")
  if not f then return end
  f:close()
  -- pid file now exists -- re-enter kill_curl which will read and act on it.
  Net.kill_curl()
end

-- =============================================================================
-- Net.custom_models_url
-- =============================================================================
-- Derive an OpenAI-compatible `GET /v1/models` URL from a chat/completions
-- endpoint. Covers the common shapes emitted by LM Studio, Ollama, llama.cpp,
-- vLLM, and OpenRouter. Falls back to appending /v1/models to the host if the
-- input URL is unrecognized.
function Net.custom_models_url(endpoint)
  if type(endpoint) ~= "string" or endpoint == "" then return nil end
  -- Strip trailing slash.
  local url = endpoint:gsub("/+$", "")
  -- Most common: ".../v1/chat/completions" -> ".../v1/models"
  local base = url:match("^(.-)/chat/completions$")
  if base then return base .. "/models" end
  -- Already a models URL.
  if url:match("/models$") then return url end
  -- URL ends at /v1 (no suffix): append /models.
  if url:match("/v1$") then return url .. "/models" end
  -- Unknown shape: try to strip to scheme+host and append /v1/models.
  local host = url:match("^(https?://[^/]+)")
  if host then return host .. "/v1/models" end
  return nil
end

-- =============================================================================
-- Net.fire_key_test
-- =============================================================================
-- Sends a minimal API request to validate the key. Cloud providers get a
-- 1-token chat/completions POST (cost negligible). Custom OpenAI-compatible
-- providers instead get a GET /v1/models request so no inference runs on the
-- server -- critical for reasoning models where `max_completion_tokens=1`
-- only caps output tokens, not the full thinking pass.
-- On completion, Net.try_finish_curl detects S.key_test_pending and routes to
-- Net.handle_key_test instead of the normal response flow.
-- provider_override: optional provider table to test (for multi-key intro screen).
function Net.fire_key_test(provider_override)
  local p = provider_override or PROVIDERS.active()
  -- Build a minimal test request. Cloud providers use a 1-token chat POST;
  -- custom providers use a GET /v1/models call (no inference -> no reasoning
  -- cost, no model load, instant response).
  local body
  local curl_opts = nil
  if p.is_custom then
    local url = Net.custom_models_url(p.endpoint)
    if not url then
      S.key_test_pending  = false
      S.key_test_provider = nil
      S.status            = "error"
      if api_keys.custom_conn_test and api_keys.custom_conn_test.active
         and api_keys.screen == "custom_llm" then
        CTX.custom_conn_test_advance(false,
          "Could not derive a /v1/models URL from the endpoint.")
        return
      end
      return
    end
    body      = nil
    curl_opts = { method = "GET", endpoint_override = url }
  elseif p.id == "anthropic" then
    body = str_format(
      '{"model":"%s","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}',
      p.models[1].id)
  elseif p.id == "openai" then
    body = str_format(
      '{"model":"%s","max_completion_tokens":1,"messages":[{"role":"user","content":"hi"}]}',
      p.models[1].id)
  elseif p.id == "google" then
    body = '{"contents":[{"role":"user","parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}'
  end
  S.key_test_pending  = true
  S.key_test_provider = p.id
  S.status            = "waiting"
  Code.safe_write(tmp.out, "")
  if not Net.fire_curl(body, curl_opts) then
    S.key_test_pending  = false
    S.key_test_provider = nil
    S.status            = "error"
    local label = p.label
    -- Custom-LLM row-test mode: record failure and advance the queue.
    if api_keys.custom_conn_test and api_keys.custom_conn_test.active
       and api_keys.screen == "custom_llm" and p.is_custom then
      CTX.custom_conn_test_advance(false,
        "Could not launch request to " .. label .. ".")
      return
    end
    -- Multi-key test mode: record failure and advance queue.
    if #api_keys.test_queue > 0 and (api_keys.screen == "first_run" or api_keys.screen == "settings") then
      Net.advance_key_test_queue(p.id, false,
        "Could not reach the " .. label .. " API. Check your internet connection.")
      return
    end
    if (api_keys.screen == "first_run" or api_keys.screen == "settings") then
      api_keys.key_validating = false
      api_keys.key_error      = "Could not reach the " .. label .. " API to "
        .. "validate your key. This usually means your internet connection "
        .. "is down. Check your connection and try again."
      -- Show error popup.
      api_keys.show_key_error_popup = true
      api_keys.key_error_provider   = label
      api_keys.key_error_detail     = "Could not reach the " .. label .. " API."
      api_keys.key_error_hint       = "Check your internet connection and try again. "
        .. "If you're behind a firewall or VPN, make sure it allows outbound HTTPS traffic."
      api_keys.key_error_url        = nil
      api_keys.key_error_url_label  = nil
    else
      -- Append rather than clobber: if the user somehow triggered a key test
      -- while a conversation was on screen, wiping S.display_messages would
      -- destroy their chat. Log.add_error is the shared append path.
      Log.add_error(
        "Could not reach the " .. label .. " API to validate your key. "
          .. "This usually means your internet connection is down or "
          .. "another request is still in progress.\n\n"
          .. "Check your connection and click the Settings button to try again.")
    end
  end
end

-- =============================================================================
-- Net.is_auth_error
-- =============================================================================
-- Returns true if the parsed response represents an authentication error
-- for the given provider. Each provider has a different error envelope
-- format. `prov` is the full provider table (from PROVIDERS) so we can
-- dispatch on id for hosted providers and on is_custom for any of the
-- user-configured OpenAI-compatible endpoints.
function Net.is_auth_error(resp, prov)
  if type(resp) ~= "table" then return false end
  if prov.id == "anthropic" then
    return resp.type == "error"
      and type(resp.error) == "table" and resp.error ~= JSON.NULL
      and resp.error.type == "authentication_error"
  elseif prov.id == "openai" or prov.is_custom then
    -- Custom OpenAI-compatible servers usually pass errors through unchanged.
    return type(resp.error) == "table" and resp.error ~= JSON.NULL
      and (resp.error.code == "invalid_api_key"
        or resp.error.type == "invalid_request_error"
           and type(resp.error.message) == "string"
           and resp.error.message:lower():find("api key"))
  elseif prov.id == "google" then
    return type(resp.error) == "table" and resp.error ~= JSON.NULL
      and (resp.error.status == "UNAUTHENTICATED"
        or resp.error.code == 401)
  end
  return false
end

-- =============================================================================
-- Net.advance_key_test_queue
-- =============================================================================
-- Records a result for the just-tested provider and fires the next test in
-- api_keys.test_queue. When the queue is exhausted, sets the flag to open the
-- results popup. Returns true if a next test was started, false if done.
function Net.advance_key_test_queue(prov_id, ok, error_msg)
  -- Record result.
  local p = PROVIDERS.get(prov_id)
  api_keys.test_results[prov_id] = {
    ok    = ok,
    label = p and p.label or prov_id,
    error = error_msg,
  }
  -- Remove the completed entry from the front of the queue.
  if #api_keys.test_queue > 0 then
    table.remove(api_keys.test_queue, 1)
  end
  -- Fire next test if any remain.
  if #api_keys.test_queue > 0 then
    local nxt = api_keys.test_queue[1]
    api_keys.key_validating_idx = nxt.idx
    S.api_key = S.api_key_map[nxt.prov.id]
    prefs.provider_idx = nxt.idx
    MODELS.refresh()
    Code.safe_write(tmp.out, "")
    Net.fire_key_test(nxt.prov)
    return true
  end
  -- Queue exhausted: stop validating, restore active provider, show results.
  api_keys.key_validating     = false
  api_keys.key_validating_idx = nil
  api_keys.show_test_results  = true
  S.status = "idle"
  -- Restore the active-provider snapshot taken when the queue was kicked
  -- off (UI: Test API Keys click handler). Each queued provider had to
  -- temporarily own prefs.provider_idx so fire_key_test would target it;
  -- restoring here puts the user back on whichever provider they had
  -- selected before clicking Test, instead of leaving them parked on
  -- the last queue entry.
  if api_keys._test_orig_provider_idx then
    prefs.provider_idx = api_keys._test_orig_provider_idx
    api_keys._test_orig_provider_idx = nil
    MODELS.refresh()
  end
  -- Restore active provider key.
  S.api_key = S.api_key_map[PROVIDERS.active().id]
  Code.safe_write(tmp.out, "")

  -- If a Google key test succeeded in this queue, kick off tier detection so
  -- the free-tier warning fires via the Test API Keys button path too (the
  -- single-key Save path in fire_key_test already handles this; the queue
  -- path returns early before reaching it).
  local gres = api_keys.test_results and api_keys.test_results.google
  if gres and gres.ok and S.api_key_map.google then
    S.gemini_paid_tier = nil
    Net.fire_gemini_tier_test()
  end

  return false
end

-- =============================================================================
-- Net.handle_key_test
-- =============================================================================
-- Called by Net.try_finish_curl when S.key_test_pending is true. Checks whether the
-- validation request succeeded or returned an auth error, and shows the
-- appropriate message. Provider-aware: uses S.key_test_provider to identify
-- the provider being tested and its console URL.
function Net.handle_key_test(raw)
  S.key_test_pending = false
  local prov_id = S.key_test_provider or PROVIDERS.active().id
  local p       = PROVIDERS.get(prov_id) or PROVIDERS.active()
  S.key_test_provider = nil

  -- Parse the response using the JSON decoder.
  local resp = JSON.decode(raw)
  -- Custom (local LLM) test uses a GET /v1/models call -- no inference is
  -- invoked, so we only need to verify:
  --   * the response parsed as JSON (endpoint is reachable and not a 404/HTML)
  --   * it does not carry a top-level error envelope
  --   * it has a `data` array (OpenAI-compatible models listing shape)
  local custom_unreachable = false
  if p.is_custom then
    if type(resp) ~= "table" then
      custom_unreachable = true
    elseif type(resp.error) == "table" and resp.error ~= JSON.NULL then
      custom_unreachable = true
    elseif type(resp.data) ~= "table" then
      -- Server responded but the body isn't a /v1/models listing -> not
      -- OpenAI-compatible, or we hit the wrong route.
      custom_unreachable = true
    end
  end
  -- ---------- Custom-LLM connection test mode (Test Connection button) ------
  -- When the custom_conn_test is active, record pass/fail and finish.
  if api_keys.custom_conn_test and api_keys.custom_conn_test.active
     and api_keys.screen == "custom_llm" and p.is_custom then
    local err_msg = nil
    if custom_unreachable then
      local emsg = (type(resp) == "table" and type(resp.error) == "table"
                    and resp.error ~= JSON.NULL and type(resp.error.message) == "string")
                   and resp.error.message or nil
      err_msg = "Endpoint reachable but /v1/models returned an unexpected response."
        .. (emsg and (" Server said: " .. emsg) or "")
    elseif Net.is_auth_error(resp, p) then
      err_msg = "Authentication failed."
    end
    CTX.custom_conn_test_advance(err_msg == nil, err_msg)
    Code.safe_write(tmp.out, "")
    return
  end

  -- ---------- Multi-key test mode (Test API Keys button) ----------
  -- When the test queue is active, record pass/fail and advance to the next
  -- provider instead of performing the normal single-key flow.
  if #api_keys.test_queue > 0 and (api_keys.screen == "first_run" or api_keys.screen == "settings") then
    local err_msg = nil
    if custom_unreachable then
      local emsg = (type(resp) == "table" and type(resp.error) == "table"
                    and resp.error ~= JSON.NULL and type(resp.error.message) == "string")
                   and resp.error.message or nil
      err_msg = "The endpoint responded but /v1/models returned an unexpected response."
        .. (emsg and (" Server said: " .. emsg) or "")
    elseif Net.is_auth_error(resp, p) then
      err_msg = "Authentication failed. The key may have expired or been revoked."
    end
    Net.advance_key_test_queue(p.id, err_msg == nil, err_msg)
    return
  end

  if custom_unreachable then
    S.status = "error"
    if (api_keys.screen == "first_run" or api_keys.screen == "settings") then
      api_keys.key_validating     = false
      api_keys.key_validating_idx = nil
      -- Same restore-on-failure pattern as the auth-error branch above.
      if api_keys._test_orig_provider_idx then
        local saved = api_keys._test_orig_provider_idx
        api_keys._test_orig_provider_idx = nil
        local saved_prov = PROVIDERS[saved]
        if saved_prov and S.api_key_map[saved_prov.id] then
          prefs.provider_idx = saved
          reaper.SetExtState(CFG.EXT_NS, "provider_idx", tostring(saved), true)
          MODELS.refresh()
          S.api_key = S.api_key_map[saved_prov.id]
        end
      end
      local emsg = (type(resp) == "table" and type(resp.error) == "table"
                    and resp.error ~= JSON.NULL and type(resp.error.message) == "string")
                   and resp.error.message or nil
      local detail = "The endpoint responded but the model test failed."
        .. (emsg and ("\n\nServer said: " .. emsg) or "")
      -- Show error popup.
      api_keys.show_key_error_popup = true
      api_keys.key_error_provider   = p.label or "Custom LLM"
      api_keys.key_error_detail     = detail
      api_keys.key_error_hint       = "Check that the server is running, the URL and port "
        .. "are correct, and the model identifier matches what the server expects."
      api_keys.key_error_url        = nil
      api_keys.key_error_url_label  = nil
    end
    Code.safe_write(tmp.out, "")
    return
  end

  if Net.is_auth_error(resp, p) then
    -- Key is invalid: clear it and prompt again.
    S.api_key = nil
    S.api_key_map[p.id] = nil
    if p.key_extstate then Key.clear(p.key_extstate) end
    -- Restore the active-provider snapshot taken when the Save handler
    -- flipped to test this key. If the original provider still has a
    -- working key, put the user back there so a failed OpenAI key test
    -- doesn't strand them on a broken OpenAI configuration when they
    -- were happily on Claude before. If the snapshotted provider lost
    -- its key (e.g. user wiped Claude before pasting OpenAI), leave
    -- prefs.provider_idx alone -- restoring would also break.
    if api_keys._test_orig_provider_idx then
      local saved = api_keys._test_orig_provider_idx
      api_keys._test_orig_provider_idx = nil
      local saved_prov = PROVIDERS[saved]
      if saved_prov and S.api_key_map[saved_prov.id] then
        prefs.provider_idx = saved
        reaper.SetExtState(CFG.EXT_NS, "provider_idx", tostring(saved), true)
        MODELS.refresh()
        S.api_key = S.api_key_map[saved_prov.id]
      end
    end
    S.status = "error"
    if (api_keys.screen == "first_run" or api_keys.screen == "settings") then
      api_keys.key_validating = false
      local idx = PROVIDERS._by_id[p.id]
      if idx and api_keys.key_errors then
        api_keys.key_errors[idx] = "That key didn't work. It may have expired "
          .. "or been entered incorrectly."
      end
      -- Clear the failed key out of the input buffer so the user can
      -- either paste a fresh key or just click Save and exit. Without
      -- this, the bad key stays in the field as password bullets and
      -- a no-edit Save would re-test (and re-fail) it.
      if idx and api_keys.key_bufs then
        api_keys.key_bufs[idx] = ""
      end
      api_keys.key_error = "That " .. p.label .. " key didn't work. It may have "
        .. "expired or been entered incorrectly. Please paste a valid key and try again."
      -- Show error popup.
      api_keys.show_key_error_popup = true
      api_keys.key_error_provider   = p.label
      api_keys.key_error_detail     = "The " .. p.label .. " API key failed authentication. "
        .. "The key may have expired, been revoked, or was entered incorrectly."
      api_keys.key_error_hint       = "Double-check the key for typos, or generate a new one at your provider's console."
      api_keys.key_error_url        = p.console_url
      api_keys.key_error_url_label  = p.console_label
    else
      -- Append rather than clobber: preserves any conversation state that
      -- happens to be on screen when a key test triggers.
      Log.add_error(
        "That " .. p.label .. " key didn't work. It may have expired or been "
          .. "entered incorrectly.\n\n"
          .. "Click the Settings button to try again.\n\n"
          .. "You can find or create a key here:",
        p.console_url, p.console_label)
    end
    return
  end

  -- If we got here, the key works (even a rate-limit means auth succeeded).
  -- Persist the tested key now that validation has confirmed it works. Custom
  -- providers may have no key at all -- skip the save in that case.
  if S.api_key and p.key_extstate then
    Key.save(S.api_key, p.key_extstate)
    S.api_key_map[p.id] = S.api_key
  end
  S.status = "idle"
  if (api_keys.screen == "first_run" or api_keys.screen == "settings") then
    -- Also persist any other newly entered keys that passed format validation
    -- (they were stored in S.api_key_map during submit but not yet saved to ExtState).
    for i, prov in ipairs(PROVIDERS) do
      if prov.id ~= p.id then
        local buf = api_keys.key_bufs[i] or ""
        local trimmed = buf:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" and S.api_key_map[prov.id] == trimmed then
          Key.save(trimmed, prov.key_extstate)
        end
      end
    end
    local was_reentry = api_keys.is_reentry
    -- Leave the key screen and enter the main UI.
    api_keys.screen         = nil
    api_keys.is_reentry     = false
    api_keys.key_validating = false
    api_keys.key_error      = nil
    api_keys.key_bufs       = {}
    api_keys.key_errors     = {}
    api_keys.key_focused    = false
    api_keys.custom_edit = nil
    UI.show_float_toast(was_reentry and "Settings saved" or "API key validated", "ok")
    if not was_reentry then
      -- First-run: set the active provider to the one just validated.
      -- Drop any test-snapshot since first-run is intentionally choosing
      -- the new provider as active; restoring would defeat the purpose.
      api_keys._test_orig_provider_idx = nil
      local prov_idx = PROVIDERS._by_id[p.id]
      if prov_idx then
        prefs.provider_idx = prov_idx
        reaper.SetExtState(CFG.EXT_NS, "provider_idx", tostring(prov_idx), true)
        MODELS.refresh()
      end
    elseif api_keys._test_orig_provider_idx then
      -- Settings re-entry: restore the active-provider snapshot taken
      -- when the Save handler flipped to test the new key, so testing
      -- e.g. a fresh OpenAI key while currently on Claude doesn't
      -- silently switch the active provider as a side effect of Save.
      -- If the snapshotted provider lost its key during this Save (user
      -- wiped it in the same submission), leave provider_idx pointing
      -- at the just-validated provider so the user retains a working
      -- configuration -- restoring would land them on a no-key slot.
      local saved = api_keys._test_orig_provider_idx
      api_keys._test_orig_provider_idx = nil
      local saved_prov = PROVIDERS[saved]
      if saved_prov and S.api_key_map[saved_prov.id] then
        prefs.provider_idx = saved
        reaper.SetExtState(CFG.EXT_NS, "provider_idx", tostring(saved), true)
        MODELS.refresh()
      end
    end
    S.api_key = S.api_key_map[PROVIDERS.active().id]
    S.refocus_prompt   = true
    S.display_messages = {}
    S.history          = {}
    S.scroll_to_bottom = true
  end

  -- Clear the response file so the next Net.send_to_api call doesn't pick up
  -- the stale key-test response before the new curl has written its output.
  Code.safe_write(tmp.out, "")

  -- Detect Gemini free vs paid tier by testing the Pro model. Fires whenever
  -- a Google key ended up persisted by this key-test flow -- not just when
  -- Google was the tested provider. On first-run / Settings, Save & Continue
  -- tests only the FIRST valid key and side-saves the rest (see the loop
  -- above). Without this broader trigger, a Gemini key pasted alongside
  -- another provider never gets its tier detected and the free-tier popup
  -- never fires. fire_gemini_tier_test guards against double-firing via
  -- the S.curl_pid check at its top.
  if S.api_key_map.google then
    S.gemini_paid_tier = nil
    Net.fire_gemini_tier_test()
  end
end

-- =============================================================================
-- Net.fire_gemini_tier_test
-- =============================================================================
-- Fires a 1-token request using the Pro model to detect free vs paid tier.
-- Free tier: response body contains "free_tier" in quota metrics (429, limit=0).
-- Paid tier: request succeeds (Pro accessible).
function Net.fire_gemini_tier_test()
  -- Don't fire while another request is in-flight.
  if S.curl_pid then return end
  local google_key = S.api_key_map.google
  if not google_key then return end

  -- Find the Pro model ID from the provider's full model list.
  local google_prov = PROVIDERS.get("google")
  if not google_prov then return end
  local pro_id
  for _, m in ipairs(google_prov.models) do
    if m.paid_only then pro_id = m.id; break end
  end
  if not pro_id then return end

  local body = '{"contents":[{"role":"user","parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}'
  if not Code.safe_write(tmp.body, body) then return end

  -- Write the Gemini auth header to a temp file so it stays off the command
  -- line (not visible in ps/Task Manager). Uses tmp.gemini_auth to avoid
  -- trampling the main request's tmp.auth.
  if not Code.safe_write(tmp.gemini_auth, "x-goog-api-key: " .. google_key) then return end

  local endpoint = str_format(google_prov.endpoint_tpl, pro_id)
  local CONNECT_TIMEOUT_SECS = 10

  os.remove(tmp.exit)
  -- Clear any stale tmp.pid from a previous real curl. This path does not
  -- launch curl with PID capture (no Start-Process -PassThru / $! plumbing),
  -- so leaving an old PID on disk would let Net.kill_curl `taskkill` an
  -- unrelated process if the user clicks Cancel during the tier test (or
  -- worse, a recycled PID owned by some other application).
  os.remove(tmp.pid)
  Code.safe_write(tmp.out, "")

  if RA.IS_WINDOWS then
    local function ps_escape(path) return path:gsub("'", "''") end
    local cmd_line = str_format(
      'curl -s --connect-timeout %d --max-time 30'
      .. ' -X POST %s'
      .. ' -H """content-type: application/json"""'
      .. ' -H @"""%s"""'
      .. ' -d @"""%s""" -o """%s"""'
      .. ' & del """%s""" & echo %%errorlevel%% > """%s"""',
      CONNECT_TIMEOUT_SECS, endpoint, tmp.gemini_auth, tmp.body, tmp.out,
      tmp.gemini_auth, tmp.exit)
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden"',
      ps_escape(cmd_line))
    reaper.ExecProcess(ps_cmd, 5000)
  else
    local function sq(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
    -- Wrap entire pipeline in a subshell so & backgrounds curl+echo together.
    local unix_curl = str_format(
      '(curl -s --connect-timeout %d --max-time 30'
      .. ' -X POST %s'
      .. ' -H "content-type: application/json"'
      .. ' -H @%s'
      .. ' -d @%s -o %s ; rm -f %s ; echo $? > %s) &',
      CONNECT_TIMEOUT_SECS, endpoint,
      sq(tmp.gemini_auth),
      sq(tmp.body), sq(tmp.out),
      sq(tmp.gemini_auth), sq(tmp.exit))
    os.execute(unix_curl)
  end

  S.gemini_tier_pending = true
  S.curl_pid            = true
  S.send_time           = time_precise()
end

-- =============================================================================
-- Net.handle_gemini_tier_test
-- =============================================================================
-- Parses the Pro model test response. Paid is set only on a positive signal
-- (successful generation); free is set on an explicit 429/403 error or the
-- legacy "free_tier" substring. Ambiguous responses default to free (with no
-- popup) so the Pro filter stays engaged without falsely accusing a paid
-- account after a transient network blip. Matches the timeout / curl-exit
-- branches in try_finish_curl which also default to free on ambiguity.
function Net.handle_gemini_tier_test(raw)
  S.gemini_tier_pending = false
  local is_paid, is_free
  if raw and #raw > 0 then
    local ok, resp = pcall(JSON.decode, raw)
    if ok and type(resp) == "table" and resp ~= JSON.NULL then
      if type(resp.error) == "table" and resp.error ~= JSON.NULL then
        local code   = tonumber(resp.error.code)
        local status = type(resp.error.status) == "string" and resp.error.status or ""
        if code == 429 or code == 403
           or status == "RESOURCE_EXHAUSTED" or status == "PERMISSION_DENIED" then
          is_free = true
        end
      elseif type(resp.candidates) == "table" and #resp.candidates > 0 then
        is_paid = true
      end
    end
    -- Legacy substring backstop: the older detection pre-dated the error-code
    -- path and caught a broader set of quota bodies. Retained so a response
    -- shape we haven't mapped still trips free detection.
    if not is_paid and not is_free and raw:find("free_tier") then
      is_free = true
    end
  end
  if is_paid then
    S.gemini_paid_tier = true
  else
    S.gemini_paid_tier = false
  end
  reaper.SetExtState(CFG.EXT_NS, "gemini_paid_tier", tostring(S.gemini_paid_tier), true)
  if PROVIDERS.active().id == "google" then MODELS.refresh() end
  if is_free then S.show_gemini_free_warn = true end
  Code.safe_write(tmp.out, "")  -- clear stale tier test response
end

-- =============================================================================
-- Gemini explicit context caching
-- =============================================================================
-- Explicit caching lets us pay a discounted rate on the tokens that make up
-- the system prompt + pinned API reference, instead of billing them as fresh
-- input tokens on every turn. The cache has a TTL (1h) and is bound to a
-- specific model id, so it must be recreated on model switch.
--
-- Lifecycle:
--   ensure()     - called at send time; fires an async create if eligible and
--                  we don't already have a live cache. Never blocks the send.
--   invalidate() - clears local state and fires a fire-and-forget DELETE so
--                  the cache stops accruing storage charges server-side.
--   is_usable()  - checked in build_body_google to decide whether to emit
--                  cachedContent and skip the inline api_ref + systemInstruction.
--
-- The first send after (re)creation goes out WITHOUT cache because creation
-- is async and completes in parallel. Subsequent sends benefit.
-- =============================================================================

-- Minimum input tokens to qualify for explicit caching on Gemini. Flash
-- family is 1024; Pro family is 4096. The API ref alone clears both, but
-- we include system_instruction in the cache too for a bigger discount.
local GEMINI_CACHE_TTL_SECS  = 3600  -- 1 hour
local GEMINI_CACHE_SAFETY    = 60    -- treat as expired if within 60s of TTL

-- =============================================================================
-- Net.gemini_cache_is_usable
-- =============================================================================
-- True when we have a live, non-expired cache that matches the current model.
function Net.gemini_cache_is_usable()
  if not S.gemini_cache_name then return false end
  if S.gemini_paid_tier ~= true then return false end
  local p = PROVIDERS.active()
  if p.id ~= "google" then return false end
  if S.gemini_cache_model ~= MODELS.active_id() then return false end
  if os.time() >= (S.gemini_cache_expires - GEMINI_CACHE_SAFETY) then
    return false
  end
  return true
end

-- =============================================================================
-- Net.gemini_cache_should_create
-- =============================================================================
-- True when the conditions for caching are met but no live cache exists yet.
local function gemini_cache_should_create()
  if S.gemini_cache_creating then return false end
  if S.gemini_paid_tier ~= true then return false end
  -- Treat empty string the same as nil. CTX.docs() normally returns nil on
  -- failure, but a partial-load failure path that produces "" would
  -- otherwise queue a Gemini cache create with a zero-token body, which
  -- the API rejects under its min-tokens limit -- wasted curl cycle.
  if not S.api_ref_message or S.api_ref_message == "" then return false end
  local p = PROVIDERS.active()
  if p.id ~= "google" then return false end
  if Net.gemini_cache_is_usable() then return false end
  return true
end

-- =============================================================================
-- Net.fire_gemini_cache_delete
-- =============================================================================
-- Fire-and-forget DELETE against cachedContents/NAME. We don't poll for
-- completion -- if it fails the cache will expire on its own via TTL.
function Net.fire_gemini_cache_delete(cache_name)
  if not cache_name or cache_name == "" then return end
  local google_key = S.api_key_map and S.api_key_map.google
  if not google_key then return end
  -- Write key to temp file so it stays off the command line.
  if not Code.safe_write(tmp.gemini_auth, "x-goog-api-key: " .. google_key) then return end
  local url = str_format(
    "https://generativelanguage.googleapis.com/v1beta/%s",
    cache_name)
  if RA.IS_WINDOWS then
    local cmd_line = str_format(
      'curl -s -X DELETE -H @"""%s""" %s & del """%s"""',
      tmp.gemini_auth, url, tmp.gemini_auth)
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden"',
      cmd_line:gsub("'", "''"))
    reaper.ExecProcess(ps_cmd, 2000)
  else
    local function sq(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
    os.execute(str_format(
      '(curl -s -X DELETE -H @%s %s > /dev/null 2>&1 ; rm -f %s) &',
      sq(tmp.gemini_auth), url, sq(tmp.gemini_auth)))
  end
end

-- atexit: persist the active Gemini context cache reference so the next
-- launch can reuse it instead of paying to recreate. Server-side TTL
-- (1h) cleans up orphans if the user never reopens.
reaper.atexit(function()
  if S.gemini_cache_name then
    local ok, err = pcall(Net.gemini_cache_persist)
    if not ok then
      Log.line("GEMINI", "cache_persist (atexit) failed: " .. tostring(err))
    end
  end
end)

-- =============================================================================
-- Net.gemini_cache_invalidate
-- =============================================================================
-- Clears local cache state and issues a server-side DELETE so the old cache
-- stops accruing storage charges. Safe to call when no cache exists.
function Net.gemini_cache_invalidate()
  local old_name = S.gemini_cache_name
  S.gemini_cache_name    = nil
  S.gemini_cache_model   = nil
  S.gemini_cache_expires = 0
  -- A create in-flight will land with a name we no longer want; mark the
  -- flight as aborted so the poll path discards the response.
  if S.gemini_cache_creating then
    S.gemini_cache_creating = false
  end
  Net.gemini_cache_clear_persisted()
  if old_name then
    Net.fire_gemini_cache_delete(old_name)
  end
end

-- =============================================================================
-- Net.gemini_cache_persist / restore / clear_persisted
-- =============================================================================
-- Survives the cache reference (name/model/expires) across script restarts via
-- ExtState. Without this, every restart re-creates a fresh cache while the
-- prior one continues billing storage server-side until its TTL expires --
-- typically ~$0.01 per restart on Gemini Pro and a 1-3s extra cold-start.
function Net.gemini_cache_persist()
  if not S.gemini_cache_name or S.gemini_cache_name == "" then return end
  reaper.SetExtState(CFG.EXT_NS, "gemini_cache_name",
    S.gemini_cache_name, true)
  reaper.SetExtState(CFG.EXT_NS, "gemini_cache_model",
    S.gemini_cache_model or "", true)
  reaper.SetExtState(CFG.EXT_NS, "gemini_cache_expires",
    tostring(S.gemini_cache_expires or 0), true)
end

function Net.gemini_cache_clear_persisted()
  reaper.DeleteExtState(CFG.EXT_NS, "gemini_cache_name",    true)
  reaper.DeleteExtState(CFG.EXT_NS, "gemini_cache_model",   true)
  reaper.DeleteExtState(CFG.EXT_NS, "gemini_cache_expires", true)
end

function Net.gemini_cache_restore()
  local name = reaper.GetExtState(CFG.EXT_NS, "gemini_cache_name")
  if not name or name == "" then return end
  local model = reaper.GetExtState(CFG.EXT_NS, "gemini_cache_model")
  local expires_str = reaper.GetExtState(CFG.EXT_NS, "gemini_cache_expires")
  local expires = tonumber(expires_str) or 0
  -- Discard expired caches (or those within the safety window). Server-side
  -- TTL has already collected them.
  if os.time() >= (expires - GEMINI_CACHE_SAFETY) then
    Net.gemini_cache_clear_persisted()
    return
  end
  S.gemini_cache_name    = name
  S.gemini_cache_model   = (model ~= "") and model or nil
  S.gemini_cache_expires = expires
  Log.line("GEMINI_CACHE", "restored " .. name
    .. " (model=" .. tostring(S.gemini_cache_model)
    .. ", expires_in=" .. tostring(expires - os.time()) .. "s)")
end

-- =============================================================================
-- Net.fire_gemini_cache_create
-- =============================================================================
-- Async POST /v1beta/cachedContents. Writes the body to tmp.cache_body and
-- launches curl in the background, with output going to tmp.cache_out and
-- exit code to tmp.cache_exit. The main loop polls completion via
-- Net.try_finish_gemini_cache_create.
--
-- Body contains: model id, systemInstruction, contents (the api_ref priming
-- exchange), and a TTL. Minimum token counts are naturally met since the api
-- ref alone is ~8k tokens.
function Net.fire_gemini_cache_create()
  if S.gemini_cache_creating then return end
  if not gemini_cache_should_create() then return end

  local google_key = S.api_key_map and S.api_key_map.google
  if not google_key then return end

  local model_id = MODELS.active_id()
  if not model_id then return end

  -- Build the create body: system_instruction + the same user/model priming
  -- exchange we'd otherwise inline into every request.
  local body = str_format(
    '{"model":"models/%s",'
    .. '"systemInstruction":{"parts":[{"text":"%s"}]},'
    .. '"contents":[{"role":"user","parts":[{"text":"%s"}]},'
    .. '{"role":"model","parts":[{"text":"Understood."}]}],'
    .. '"ttl":"%ds"}',
    model_id,
    JSON.escape(SYSTEM_PROMPT),
    JSON.escape(S.api_ref_message),
    GEMINI_CACHE_TTL_SECS)

  if not Code.safe_write(tmp.cache_body, body) then return end

  -- Write auth header to temp file (keeps key off command line).
  if not Code.safe_write(tmp.gemini_auth, "x-goog-api-key: " .. google_key) then return end

  local url = "https://generativelanguage.googleapis.com/v1beta/cachedContents"

  os.remove(tmp.cache_exit)
  Code.safe_write(tmp.cache_out, "")

  if RA.IS_WINDOWS then
    local cmd_line = str_format(
      'curl -s --connect-timeout 10 --max-time 30'
      .. ' -X POST %s'
      .. ' -H """content-type: application/json"""'
      .. ' -H @"""%s"""'
      .. ' -d @"""%s""" -o """%s"""'
      .. ' & del """%s""" & echo %%errorlevel%% > """%s"""',
      url, tmp.gemini_auth, tmp.cache_body, tmp.cache_out,
      tmp.gemini_auth, tmp.cache_exit)
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden"',
      cmd_line:gsub("'", "''"))
    reaper.ExecProcess(ps_cmd, 5000)
  else
    local function sq(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
    local unix_curl = str_format(
      '(curl -s --connect-timeout 10 --max-time 30'
      .. ' -X POST %s'
      .. ' -H "content-type: application/json"'
      .. ' -H @%s'
      .. ' -d @%s -o %s ; rm -f %s ; echo $? > %s) &',
      url, sq(tmp.gemini_auth),
      sq(tmp.cache_body), sq(tmp.cache_out),
      sq(tmp.gemini_auth), sq(tmp.cache_exit))
    os.execute(unix_curl)
  end

  S.gemini_cache_creating   = true
  S.gemini_cache_started_at = reaper.time_precise()
  S.gemini_cache_model      = model_id  -- remember intended model for poll
end

-- =============================================================================
-- Net.gemini_cache_ensure
-- =============================================================================
-- Called before building a Gemini request body. If we should have a cache but
-- don't (yet), fire an async create. Never blocks; the current send proceeds
-- with whatever state exists right now.
function Net.gemini_cache_ensure()
  if gemini_cache_should_create() then
    Net.fire_gemini_cache_create()
  elseif Net.gemini_cache_should_renew() then
    Net.fire_gemini_cache_renew()
  end
end

-- =============================================================================
-- Net.gemini_cache_should_renew / fire_gemini_cache_renew
-- =============================================================================
-- Bumps the server-side TTL of the active cache before it expires, instead of
-- waiting for expiry and paying to recreate. Without this, mid-session caches
-- silently expire after 1h and the next send rebuilds from scratch.
--
-- Renew threshold: remaining TTL < 15 min, no renew already in flight.
-- Fire-and-forget PATCH, optimistic local bump. If the server-side renew
-- fails for any reason, the next send will hit a 404 cache_miss and the
-- existing invalidate -> recreate path picks up cleanly.
local GEMINI_CACHE_RENEW_THRESHOLD = 15 * 60  -- 15 minutes
local GEMINI_CACHE_RENEW_DEDUPE    = 5 * 60   -- don't re-fire renew within 5 min

function Net.gemini_cache_should_renew()
  if not S.gemini_cache_name then return false end
  if S.gemini_cache_creating then return false end
  if not Net.gemini_cache_is_usable() then return false end
  -- Throttle: at most one renew attempt per dedupe window so a burst of sends
  -- doesn't fire 10 PATCHes back-to-back.
  local now = os.time()
  if (S.gemini_cache_last_renew or 0) > now - GEMINI_CACHE_RENEW_DEDUPE then
    return false
  end
  local remaining = (S.gemini_cache_expires or 0) - now
  return remaining > 0 and remaining < GEMINI_CACHE_RENEW_THRESHOLD
end

function Net.fire_gemini_cache_renew()
  local cache_name = S.gemini_cache_name
  if not cache_name or cache_name == "" then return end
  local google_key = S.api_key_map and S.api_key_map.google
  if not google_key then return end
  if not Code.safe_write(tmp.gemini_auth, "x-goog-api-key: " .. google_key) then return end
  local body = str_format('{"ttl":"%ds"}', GEMINI_CACHE_TTL_SECS)
  if not Code.safe_write(tmp.cache_body, body) then return end
  local url = str_format(
    "https://generativelanguage.googleapis.com/v1beta/%s",
    cache_name)
  if RA.IS_WINDOWS then
    local cmd_line = str_format(
      'curl -s -X PATCH %s'
      .. ' -H """content-type: application/json"""'
      .. ' -H @"""%s"""'
      .. ' -d @"""%s""" -o NUL'
      .. ' & del """%s""" & del """%s"""',
      url, tmp.gemini_auth, tmp.cache_body,
      tmp.gemini_auth, tmp.cache_body)
    local ps_cmd = str_format(
      'powershell -NoProfile -WindowStyle Hidden'
      .. ' -Command "Start-Process cmd -ArgumentList \'/c %s\''
      .. ' -WindowStyle Hidden"',
      cmd_line:gsub("'", "''"))
    reaper.ExecProcess(ps_cmd, 2000)
  else
    local function sq(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
    os.execute(str_format(
      '(curl -s -X PATCH -H "content-type: application/json"'
      .. ' -H @%s -d @%s %s > /dev/null 2>&1 ; rm -f %s %s) &',
      sq(tmp.gemini_auth), sq(tmp.cache_body), url,
      sq(tmp.gemini_auth), sq(tmp.cache_body)))
  end
  -- Optimistically bump local expiry. If the PATCH fails server-side, the
  -- next send hits 404 and Net.gemini_cache_invalidate clears state cleanly.
  S.gemini_cache_expires    = os.time() + GEMINI_CACHE_TTL_SECS
  S.gemini_cache_last_renew = os.time()
  Net.gemini_cache_persist()
  Log.line("GEMINI_CACHE", "renew fired for " .. cache_name
    .. " (new TTL " .. GEMINI_CACHE_TTL_SECS .. "s, optimistic)")
end

-- =============================================================================
-- Net.try_finish_gemini_cache_create
-- =============================================================================
-- Polled from the main loop while S.gemini_cache_creating is true. Reads the
-- response file, parses the cache name and expireTime, and stores them for
-- subsequent send_to_api calls to pick up via gemini_cache_is_usable.
function Net.try_finish_gemini_cache_create()
  if not S.gemini_cache_creating then return end

  -- Watchdog: if the cache-create curl hasn't resolved within 45 seconds
  -- (curl's own --max-time is 30s; we allow 15s of slack for PowerShell
  -- launch delay and fs lag), give up and unstick state so caching stays
  -- functional for the rest of the session.
  local started = S.gemini_cache_started_at or 0
  if started > 0 and (reaper.time_precise() - started) > 45 then
    S.gemini_cache_creating = false
    S.gemini_cache_model    = nil
    os.remove(tmp.cache_exit)
    Code.safe_write(tmp.cache_out, "")
    return
  end

  -- Exit code first (network error path). A nonzero code means curl failed
  -- outright; an exit code 0 means curl completed, so we must parse the
  -- response body even if it isn't JSON -- otherwise a proxy HTML page
  -- would silently pin us in the "creating" state forever.
  local curl_done = false
  do
    local ok_ef, ef = pcall(io.open, tmp.cache_exit, "r")
    if ok_ef and ef then
      local exit_str = ef:read("*a"); ef:close()
      local exit_code = tonumber(exit_str:match("(%d+)"))
      if exit_code and exit_code ~= 0 then
        S.gemini_cache_creating = false
        S.gemini_cache_model    = nil
        os.remove(tmp.cache_exit)
        return
      elseif exit_code == 0 then
        curl_done = true
        os.remove(tmp.cache_exit)
      end
    end
  end

  -- Response body. If curl hasn't exited yet, bail out partial -- we only
  -- commit to parsing once we know the write is complete.
  local ok_f, f = pcall(io.open, tmp.cache_out, "r")
  if not ok_f or not f then return end
  local raw = f:read("*a"); f:close()
  if not curl_done then
    if #raw < 10 then return end
    local last_char = raw:match("(%S)%s*$")
    if last_char ~= "}" then return end
  end

  S.gemini_cache_creating = false
  Code.safe_write(tmp.cache_out, "")

  local resp = JSON.decode(raw)
  if type(resp) ~= "table" then
    -- Non-JSON response (e.g. proxy HTML); caching stays unusable this turn
    -- but the "creating" flag is already cleared so future sends can retry.
    S.gemini_cache_model = nil
    return
  end

  -- Error envelope: {"error":{"code":N,"message":"...","status":"..."}}
  if type(resp.error) == "table" and resp.error ~= JSON.NULL then
    S.gemini_cache_model = nil
    return
  end

  -- Success: {"name":"cachedContents/abc","model":"models/...","expireTime":"..."}
  if type(resp.name) == "string" and resp.name ~= "" then
    S.gemini_cache_name = resp.name
    -- We set ttl=3600s in the create request, so expires = now + TTL is
    -- accurate. The server also returns expireTime (RFC3339 UTC) but parsing
    -- it via os.time() applies local-timezone offset and skews the result.
    S.gemini_cache_expires = os.time() + GEMINI_CACHE_TTL_SECS
    Net.gemini_cache_persist()  -- survive script restart
  else
    S.gemini_cache_model = nil
  end
end

-- =============================================================================
-- Net.send_to_api
-- =============================================================================
-- Entry point for every user-initiated send.
--
-- Flow:
--   1. Capture the active project tab (EnumProjects(-1)).
--   2. Build a fresh session snapshot if "Send snapshot" is on.
--   3. Load the API reference into the pinned message slot on first send of the
--      session if "Always include REAPER API reference" is on. The pinned message is prepended to every
--      API call by Net.build_body() outside the sliding window, keeping its cache
--      position stable.
--   4. Push the user text to S.history (snapshot and API ref are NOT stored here).
--   5. Preflight token estimation: abort with a friendly error if the request
--      would exceed the model's 200K context window (rough chars/4 heuristic).
--   6. Fire curl. The snapshot is injected by Net.build_body(), not stored in S.history.
function Net.send_to_api(user_text)
  S.status                = "waiting"
  S.request_start_time    = reaper.time_precise()
  S.pending_code          = nil
  S.docs_already_sent     = false
  S.docs_extended_already_sent = false
  S.session_already_sent  = false
  S.fx_params_already_sent = false
  S.plugin_ref_sent        = {}
  S.pending_resolves       = {}
  S.pending_plugin_ref_names = {}
  S.pending_pref_plugin_types = {}
  S.context_loop_retries   = 0
  S.api_validator_retries  = 0
  S._context_reuse_hint    = nil
  S._mixed_output_hint     = nil
  S.fx_list_already_sent   = false
  S.fx_chains_already_sent = false
  S.track_flags_already_sent = false
  S.midi_already_sent      = false
  S.pref_plugins_sent      = {}
  S.theme_already_sent     = false
  S.fx_inspect_already_sent = false
  -- Defensive: clear any leftover deferred-assemble or silent-inspect flag
  -- from a cancelled prior turn so this turn isn't poisoned.
  S._fx_params_pending_assemble  = nil
  S._fx_inspect_silent_for_fx_params = nil
  S.pending_orig_prompt   = user_text
  S.retry_count           = 0          -- reset retry counter for each new user send
  S.retry_scheduled       = false

  -- Capture current attachments and clear the queue before any early returns.
  local msg_attachments = #S.attachments > 0 and S.attachments or nil
  S.attachments = {}

  -- Warn if PDFs are attached to a provider that doesn't support them.
  if msg_attachments and PROVIDERS.active().id == "openai" then
    for _, att in ipairs(msg_attachments) do
      if att.kind == "pdf" then
        Log.add_error("ChatGPT does not support PDF attachments. "
          .. "The file name will be sent but its content cannot be read. "
          .. "Try Claude or Gemini for PDF support.")
        break
      end
    end
  end

  -- 1. Reset FX cache event tracking for this exchange.
  S._fx_cache_events = {}  -- keyed by type: { hit = {name, ...}, cached = {...}, annotated = {...} }

  -- 1b. Capture the active project.
  S.pending_project = reaper.EnumProjects(-1)

  -- 2. Build a fresh session snapshot if enabled.
  local snapshot = prefs.include_snapshot and CTX.build_snapshot(S.pending_project) or nil
  S.pending_snapshot    = snapshot        -- saved for potential docs follow-up
  S.pending_attachments = msg_attachments -- saved for beta-header fallback rebuild

  -- 3. Load the API reference into the pinned slot on first send of the session.
  local ref_injected = false
  if prefs.include_api_ref and not S.api_ref_message then
    local ref_content, ref_err = CTX.docs()
    if ref_content then
      S.api_ref_message = ref_content
      ref_injected    = true
    else
      Log.add_error(ref_err)
    end
  end
  if S.api_ref_message then ref_injected = true end

  -- 3a. MIDI auto-inject: if the user prompt contains the word "midi" as a
  -- standalone token (case-insensitive), pre-load the MIDI reference into the
  -- pinned slot. This avoids a context_needed round-trip when the prompt is
  -- clearly MIDI-related. The model can also request it explicitly via
  -- <context_needed>midi</context_needed> for prompts that imply MIDI without
  -- saying it (e.g. "transpose those notes"). Once loaded, it stays loaded
  -- for the rest of the session and is cached at the top of the prefix.
  local midi_injected = false
  if not S.midi_ref_message then
    -- Match "midi" with non-letter boundaries on both sides (Lua has no \b).
    local lower_text = user_text:lower()
    local has_midi = false
    if lower_text == "midi" or lower_text:match("^midi[^%a]")
       or lower_text:match("[^%a]midi$") or lower_text:match("[^%a]midi[^%a]") then
      has_midi = true
    end
    if has_midi then
      local mref_content, mref_err = CTX.midi()
      if mref_content then
        S.midi_ref_message = mref_content
        midi_injected = true
      else
        Log.add_error(mref_err)
      end
    end
  end
  if S.midi_ref_message then midi_injected = true end

  -- 3b. Gemini: kick off an async context cache create if eligible and no
  -- live cache exists yet. Non-blocking -- this send proceeds without the
  -- cache if it's not ready, and subsequent sends pick it up when it lands.
  if PROVIDERS.active().id == "google" then
    Net.gemini_cache_ensure()
  end

  -- 3c. Theme auto-inject: detect requests to change REAPER's UI appearance.
  -- Two paths:
  --   A) Prompt contains "theme" + any color/appearance word.
  --   B) Prompt contains a REAPER UI element name + a color/appearance action.
  -- This avoids a context_needed round-trip. The model can also request the
  -- bucket explicitly via <context_needed>theme</context_needed>.
  local theme_injected = false
  if not S.theme_already_sent then
    local lt = user_text:lower()
    -- Appearance action words.
    local has_appearance = lt:find("color") or lt:find("colour")
      or lt:find("background") or lt:find("darker") or lt:find("lighter")
      or lt:find("bright") or lt:find("appearance")
    -- Path A: "theme" as a standalone token + appearance word.
    local has_theme_word = lt:match("[^%a]theme[^%a]") or lt:match("^theme[^%a]")
      or lt:match("[^%a]theme$") or lt == "theme"
    -- Path B: REAPER UI element name + appearance action (covers "make the
    -- arrange darker", "change waveform color", "mixer background", etc.).
    local has_ui_element = lt:find("arrange") or lt:find("mixer")
      or lt:find("track panel") or lt:find("tcp") or lt:find("mcp")
      or lt:find("waveform") or lt:find("peaks") or lt:find("cursor")
      or lt:find("grid") or lt:find("meter") or lt:find("timeline")
      or lt:find("ruler") or lt:find("transport") or lt:find("marker")
      or lt:find("region") or lt:find("envelope") or lt:find("midi editor")
    if has_appearance and (has_theme_word or has_ui_element) then
      local th_content, th_err = CTX.theme()
      if th_content then
        S.theme_ref_message = th_content
          .. "\n\n(Theme reference is loaded above. Do NOT request "
          .. "<context_needed>theme</context_needed> or "
          .. "<context_needed>session</context_needed> -- you have "
          .. "everything needed. Proceed directly with the color change code.)"
        theme_injected = true
        S.theme_already_sent = true
      end
    end
  end
  if S.theme_ref_message then theme_injected = true end

  -- Preemptive bucket injection. If the user's prompt mentions a plugin
  -- type they have a saved preferred plugin for ("add a compressor",
  -- "change the eq band 2 freq"), inject the preferred_plugins content
  -- into sticky_context right here so the model sees it on the FIRST
  -- API call. Saves one <context_needed> round trip in the common case.
  -- No-op when the user has no preferred_types configured or when their
  -- prompt mentions no matching keyword. See CTX.preempt_buckets_for_prompt.
  --
  -- Bump the turn counter and prune stale sticky_context entries first, so
  -- preempt's relevance-driven re-touches happen against a fresh state and
  -- this turn's adds don't get accidentally evicted by their own arrival.
  Net.sticky_evict(user_text)
  CTX.preempt_buckets_for_prompt(user_text)

  -- 4. Build the history content: just "USER REQUEST:\n" + prompt.
  -- The API ref is no longer stored in history -- it lives in S.api_ref_message
  -- and is prepended by Net.build_body() on every call. Theme ref likewise
  -- lives in S.theme_ref_message.
  --
  -- Sticky context (plugin_ref, preferred_plugins, fx_params) is emitted by
  -- Net.build_body_* as a pinned user/assistant pair after the api_ref pin,
  -- rather than baked into each user message here. That way the content sits
  -- in a stable prefix position and the providers' caches treat it as part
  -- of the cached prefix, rather than re-writing it into every new turn's
  -- cache breakpoint.
  -- If the previous generated-code execution failed, prepend the error so
  -- the model can self-correct when the user types a follow-up like
  -- "fix that". Cleared after this send -- carrying it indefinitely would
  -- pollute unrelated subsequent prompts.
  -- Snapshot last_run_error before clearing so the two rollback blocks
  -- below can restore it. Without this, a token-budget overflow or
  -- fire_curl failure permanently loses the prior-run error context, so
  -- the next "fix that" retry would send the prompt with no error to fix.
  local _saved_last_run_error = S.last_run_error
  local history_text
  if S.last_run_error and S.last_run_error ~= "" then
    history_text = "PREVIOUS_RUN_ERROR (the code you generated last turn "
      .. "failed when executed):\n" .. S.last_run_error
      .. "\n\nUSER REQUEST:\n" .. user_text
    S.last_run_error = nil
  else
    history_text = "USER REQUEST:\n" .. user_text
  end

  -- Collect sticky labels for the Show Details display (the content itself
  -- is emitted downstream by build_body_*).
  local sticky_labels = {}
  for key, _ in pairs(S.sticky_context) do
    sticky_labels[#sticky_labels+1] = key
  end

  -- Context label for Show Details display.
  local ctx_parts = {}
  if prefs.include_snapshot then ctx_parts[#ctx_parts+1] = "snapshot" end
  if ref_injected   then ctx_parts[#ctx_parts+1] = "api_ref" end
  if midi_injected  then ctx_parts[#ctx_parts+1] = "midi"    end
  if theme_injected then ctx_parts[#ctx_parts+1] = "theme"   end
  if msg_attachments then
    for _, a in ipairs(msg_attachments) do ctx_parts[#ctx_parts+1] = a.name end
  end
  -- Append sticky context labels so Show Details reflects what was re-injected.
  table.sort(sticky_labels)
  for _, lbl in ipairs(sticky_labels) do ctx_parts[#ctx_parts+1] = lbl end
  local ctx_label = #ctx_parts > 0 and tbl_concat(ctx_parts, " + ") or "none"

  -- Push to history (without snapshot) and display (bare prompt).
  S.history[#S.history+1] = { role = "user", content = history_text }
  local disp_idx = #S.display_messages + 1
  -- Build a summary of attachments for display in the chat bubble.
  local attach_summary = nil
  if msg_attachments then
    local parts = {}
    for _, a in ipairs(msg_attachments) do
      parts[#parts+1] = a.name
    end
    attach_summary = parts
  end
  S.display_messages[disp_idx] = {
    role           = "user",
    content        = user_text,
    ctx_label      = ctx_label,
    model_label    = PROVIDERS.active().label .. " " .. (function()
      -- Fall back to MODELS[1] (or "?") when MODELS[prefs.model_idx] is
      -- nil. Indexing nil here used to throw on a custom provider whose
      -- models array was cleared mid-session, or briefly after a
      -- provider switch where prefs.model_idx temporarily points past
      -- the new provider's list before MODELS.refresh re-clamps it.
      local _m = MODELS[prefs.model_idx] or MODELS[1]
      return _m and _m.label or "?"
    end)(),
    provider_id    = PROVIDERS.active().id,
    thinking_label = (function()
      local p = PROVIDERS.active()
      if p.thinking_levels and prefs.thinking_idx > 0 then
        local tl = p.thinking_levels[prefs.thinking_idx]
        if tl then return tl.label end
      end
    end)(),
    attach_names   = attach_summary,
    from_card      = S.from_card or nil,
  }
  S.from_card = false
  S.pending_display_idx = disp_idx

  -- 5. Preflight token estimation: abort before sending if the request would
  -- exceed the model's context window. Uses a ~4 chars/token heuristic; false
  -- positives are acceptable -- better to warn than waste API time. For
  -- attachments, add their estimated token counts directly.
  --
  -- Cloud providers (Anthropic, OpenAI, Google) all expose at least 200K
  -- context on the models we ship, so a flat 200K ceiling is fine for them.
  -- Custom providers (LM Studio, Ollama, vLLM, OpenRouter, etc.) use the
  -- per-MODEL context_window value the user entered on the API Keys page,
  -- because their actual server-side limit is whatever they loaded the model
  -- with -- and exceeding it on a local llama.cpp server either truncates the
  -- prompt or starts evicting tokens from the front of the cache. Each row
  -- on the custom provider can have a different value, so we read it off the
  -- currently selected model entry rather than off the provider.
  local active_provider     = PROVIDERS.active()
  local active_model        = MODELS[prefs.model_idx] or MODELS[1]
  local MODEL_CONTEXT_LIMIT = (active_provider.is_custom
                               and active_model
                               and tonumber(active_model.context_window))
                              or 200000
  local CHARS_PER_TOKEN     = 4       -- ~4 for prose, ~3 for code, ~5 for JSON keys; 4 is a safe middle
  local body = Net.build_body(Net.trimmed_history(), snapshot, msg_attachments)
  local estimated_tokens = math_floor(#body / CHARS_PER_TOKEN)
  -- Base64 inflates size ~33%, so compensate: attachment tokens are more accurate
  -- than the chars/4 heuristic on the inflated base64. Subtract the base64 size
  -- contribution and add the pre-computed token estimates instead.
  --
  -- Text attachments are inlined into the body as raw UTF-8 (not base64), so
  -- they are ALREADY counted by the #body/4 heuristic above. Re-adding a.tokens
  -- for text attachments would double-count them and trigger false-positive
  -- context overflows for large pasted logs. Skip them here.
  --
  -- Read the contribution from a.b64 (the encoded string actually inlined into
  -- the body), NOT a.data: Attach.pump_encoding nils out a.data once encoding
  -- is complete to avoid carrying two copies of large attachments in memory.
  if msg_attachments then
    for _, a in ipairs(msg_attachments) do
      if a.kind ~= "text" and a.b64 then
        local b64_chars_est = math_floor(#a.b64 / CHARS_PER_TOKEN)
        estimated_tokens = estimated_tokens - b64_chars_est + a.tokens
      end
    end
  end
  -- Reserve output space inside the context window. Cloud providers have huge
  -- context (200K+) so reserving the full MAX_TOKENS (8192) is fine. Custom
  -- local LLMs often have tight windows (16K-32K) where reserving 8K leaves
  -- almost no room for the API ref + prompt. For custom providers the server
  -- enforces the real limit (finish_reason=length if output overflows), so we
  -- only need a small sanity reserve here -- enough to guarantee the model can
  -- emit at least a short reply, but not so much that it blocks valid requests.
  local output_reserve = active_provider.is_custom
    and math_min(CFG.MAX_TOKENS, math_floor(MODEL_CONTEXT_LIMIT * 0.1))
    or CFG.MAX_TOKENS
  local token_budget   = MODEL_CONTEXT_LIMIT - output_reserve

  if estimated_tokens > token_budget then
    -- Roll back the history and display entries we just pushed, AND restore the
    -- user's typed prompt + attachments to the input area so they don't lose
    -- their work. The user can trim attachments or clear and retry without
    -- re-typing.
    S.history[#S.history]          = nil
    S.display_messages[disp_idx] = nil
    S.pending_display_idx        = nil
    S.status    = "error"
    S.send_time = nil
    S.input_buf = user_text
    if msg_attachments then S.attachments = msg_attachments end
    -- Clear the pending_* / event-tracking state populated earlier in this
    -- function (lines 12181-12210) so a context-needed handler firing later
    -- doesn't pick up stale snapshot/project/prompt from a turn that never
    -- actually sent. The _already_sent resets at 12158-12176 are
    -- intentionally left applied; the next attempt should re-run those
    -- buckets fresh.
    S.pending_orig_prompt  = nil
    S.pending_project      = nil
    S.pending_snapshot     = nil
    S.pending_attachments  = nil
    S._fx_cache_events     = nil
    -- Restore last_run_error so a "fix that" retry still has the prior-run
    -- error context.
    S.last_run_error       = _saved_last_run_error
    Log.add_error(str_format(
      "Your message is too large to send (about %dk tokens, limit is ~%dk)."
      .. "\n\nYour message and attachments have been restored to the input box. "
      .. "To make it fit:\n"
      .. "- Remove large attachments\n"
      .. "- Turn off \"Always include REAPER API reference\" or Send snapshot to reduce size\n"
      .. "- Or click Clear to start fresh",
      math_floor(estimated_tokens / 1000),
      math_floor(token_budget / 1000)))
    S.scroll_to_bottom = true
    return
  end

  -- 6. Fire the API call (reuse the body already built by the preflight check).
  if not Net.fire_curl(body) then
    -- Roll back on failure and restore the user's input so they can retry.
    S.history[#S.history]          = nil
    S.display_messages[disp_idx] = nil
    S.pending_display_idx        = nil
    S.status    = "error"
    S.send_time = nil
    S.input_buf = user_text
    if msg_attachments then S.attachments = msg_attachments end
    -- Clear pending_* / event-tracking state and restore last_run_error;
    -- mirrors the token-budget rollback above.
    S.pending_orig_prompt  = nil
    S.pending_project      = nil
    S.pending_snapshot     = nil
    S.pending_attachments  = nil
    S._fx_cache_events     = nil
    S.last_run_error       = _saved_last_run_error
    Log.add_error(
      "Couldn't send. Another request may still be in progress. "
      .. "Wait a moment and try again.")
  end

  S.scroll_to_bottom = true
end

-- =============================================================================
-- Net.clear_conversation
-- =============================================================================
-- Resets all conversation, token, cost, and pending state. The API reference
-- file content cache is preserved (file doesn't change). S.api_ref_message is
-- cleared so it is re-pinned on the next send with a fresh cache entry.
function Net.clear_conversation()
  -- =========================================================================
  -- CLEAR CONVERSATION -- reset every conversation-scoped piece of S.* state.
  -- =========================================================================
  -- IMPORTANT: When you add a new conversation-scoped field to S (anything
  -- that grows with messages, tracks per-turn flags, holds pending follow-up
  -- data, or accumulates session totals like token/cost counters), add it
  -- below. Do NOT add app-scoped state here (UI prefs, model picks, cache
  -- warmth, network in-flight tracking) -- those should survive a chat clear.
  -- =========================================================================
  -- Conversation history + display
  S.history              = {}
  S.display_messages     = {}
  S.sticky_context       = {}
  S.sticky_context_age   = {}
  S.sticky_context_order = {}
  S.turn_counter         = 0
  S.last_run_error       = nil
  -- Pending follow-up state (mid-flight when clear is hit)
  S.pending_code         = nil
  S.pending_orig_prompt  = nil
  S.pending_snapshot     = nil
  S.pending_project      = nil
  S.pending_display_idx  = nil
  S.pending_resolves          = {}
  S.pending_plugin_ref_names  = {}
  S.pending_pref_plugin_types = {}
  S.pending_attachments       = nil
  S.pending_provider_idx      = nil
  S.pending_model_idx         = nil
  -- Per-turn one-shot guards
  S.docs_already_sent          = false
  S.docs_extended_already_sent = false
  S.session_already_sent       = false
  S.fx_params_already_sent     = false
  S.fx_list_already_sent       = false
  S.fx_chains_already_sent     = false
  S.track_flags_already_sent   = false
  S.midi_already_sent          = false
  S.theme_already_sent         = false
  S.fx_inspect_already_sent    = false
  S.plugin_ref_sent            = {}
  S.pref_plugins_sent          = {}
  S.context_loop_retries       = 0
  S.api_validator_retries      = 0
  S._context_reuse_hint        = nil
  S._mixed_output_hint         = nil
  -- Defensive clear of fx_inspect -> fx_params handoff state (also reset per
  -- send_to_api; mirroring here keeps mid-flow clears from poisoning the
  -- next conversation).
  S._fx_params_pending_assemble       = nil
  S._fx_inspect_silent_for_fx_params  = nil
  S._resolve_deep_scan_attempted      = nil
  -- Pinned ref slots -- force reload on next send if relevant prefs are on
  S.api_ref_message      = nil
  S.midi_ref_message     = nil
  S.theme_ref_message    = nil
  -- Session-level docs flag: cleared with the chat since history (where the
  -- inlined docs content lived) is about to be wiped. Next send will either
  -- re-pin via the pref or wait for the model to re-request docs.
  S.docs_fetched_session = false
  -- Resolve popup state (could be open mid-clear; close it cleanly)
  S.resolve_popup             = nil
  S.open_resolve_popup        = false
  S.resolve_popup_text        = ""
  S.resolve_popup_error       = nil
  S.resolve_popup_matches     = {}
  S.resolve_popup_sel         = 0
  S.resolve_popup_last_filter = nil
  S.resolve_popup_refocus     = false
  -- Drop any active Gemini context cache: clearing chat effectively resets
  -- the pinned api_ref, and a new cache will be created on the next send.
  Net.gemini_cache_invalidate()
  -- Session totals
  S.session_tok_in       = 0
  S.session_tok_out      = 0
  S.session_cost         = 0
  -- Retry / attachment state
  S.retry_count          = 0
  S.retry_scheduled      = false
  S.retry_saved_body     = nil
  S.attachments          = {}
  S.attach_error         = nil
  S.attach_error_time    = 0
  -- UI / status
  S.status               = "idle"
  S.scroll_to_bottom     = true
  S.wrap_cache           = {}  -- invalidate per-bubble text-wrap cache
  Code.safe_write(tmp.out, "")
end

-- =============================================================================
-- Code safety: risky-call scanner + execution gate
-- =============================================================================
-- Code.find_unknown_reaper_calls(lua_code) -> list of bad names, or nil
-- =============================================================================
-- Pre-flight validator that catches model-emitted reaper.X calls where X
-- isn't a real function on this user's machine. Complements the docs-gate
-- (which auto-fetches docs when the model wrote reaper.* without docs in
-- context); this fires AFTER the docs-gate, on the case where docs IS
-- pinned but the model still hallucinated a function name.
--
-- Source of truth is the live `reaper` table (introspected once per session
-- via _valid_reaper_fns), not the curated docs file -- the curated docs is
-- a small subset (~150 functions) of REAPER's full ~3000-function API plus
-- whatever extensions the user has installed (SWS, JS_ReaScriptAPI, BR_,
-- CF_, etc.). Validating against docs would flag tons of legitimate calls.
-- Validating against the live table flags exactly the calls that would
-- fail at runtime on this machine.
--
-- Common failure mode caught: weaker models (Gemini Flash 3, Kimi k2.6,
-- smaller Claude variants) sometimes emit plausible-sounding but
-- non-existent names like "GetProjectMarkerByIndex" (real function is
-- "EnumProjectMarkers") even when docs is pinned. The runtime sandbox
-- catches these as "attempt to call a nil value" but the user sees a
-- crash instead of a corrected reply.
local _valid_reaper_fns_cache = nil
local function _valid_reaper_fns()
  if _valid_reaper_fns_cache then return _valid_reaper_fns_cache end
  local t, count = {}, 0
  for k, v in pairs(reaper) do
    if type(v) == "function" then
      t[k] = true
      count = count + 1
    end
  end
  _valid_reaper_fns_cache = t
  -- One-shot proof-of-life log: confirms the validator was loaded and
  -- shows how many functions REAPER + installed extensions exposed on
  -- this user's machine. Only fires once per session (subsequent calls
  -- hit the cache and return immediately above).
  Log.line("API-VALIDATOR",
    "cache built: " .. count .. " reaper.* functions available")
  return t
end

function Code.find_unknown_reaper_calls(lua_code)
  if not lua_code or lua_code == "" then return nil, 0 end
  -- Strip line comments first so "-- reaper.Foo described below" can't
  -- false-positive. Block comments (--[[...]]) are rare in generated code
  -- and not worth the complexity to handle.
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local valid = _valid_reaper_fns()
  local seen, unknown = {}, {}
  local total = 0
  for name in stripped:gmatch("reaper%.([%w_]+)") do
    total = total + 1
    if not valid[name] and not seen[name] then
      seen[name] = true
      unknown[#unknown+1] = name
    end
  end
  if #unknown == 0 then return nil, total end
  table.sort(unknown)
  return unknown, total
end

-- For a hallucinated reaper.X name, return up to N real function names that
-- look similar (share a substring of >=4 chars, case-insensitive). Sorted
-- so the suggestions are stable across calls. Used by the API-validator
-- retry hint to give the model concrete candidates instead of just "you
-- got it wrong, try again."
function Code.suggest_reaper_alternatives(bad_name, max_results)
  max_results = max_results or 8
  local bad_lo = bad_name:lower()
  local needle = bad_lo:sub(1, math.min(8, #bad_lo))
  local valid = _valid_reaper_fns()
  local matches = {}
  for real in pairs(valid) do
    local real_lo = real:lower()
    -- Two-way prefix match: bad starts with real's prefix, or real starts
    -- with bad's prefix. Catches "GetProjectMarkerByIndex" -> "GetProjectMarker"
    -- (real shorter) and "GetTrack" -> "GetTrackInfo_Value" (real longer).
    if real_lo:find(needle, 1, true)
       or bad_lo:find(real_lo:sub(1, math.min(8, #real_lo)), 1, true) then
      matches[#matches+1] = real
    end
  end
  table.sort(matches)
  while #matches > max_results do matches[#matches] = nil end
  return matches
end

-- =============================================================================
-- Code.scan_risky(code) -> warning_string or nil
-- Scans a Lua code string for calls that could have side effects beyond the
-- REAPER project (file deletion, arbitrary shell commands, loading external
-- code, etc.). Returns a human-readable warning string listing what was found,
-- or nil if no risky patterns were detected.
--
-- This scanner GATES code execution: when it returns a non-nil warning, the
-- UI blocks the Run button behind a confirmation modal ("Review Before
-- Running") that the user must explicitly accept. Auto-run is also blocked.
-- This is a hard gate, not an advisory label.
--
-- Patterns are intentionally broad (matching "os.remove" anywhere in the
-- string, including inside comments or strings) to minimize false negatives.
-- A few false positives are acceptable for a safety feature.
-- RISKY_PATTERNS is hoisted out of Code.scan_risky into this do-block so it
-- isn't reallocated on every call. scan_risky runs from the render hot path
-- (once per visible Lua code block per frame), so the table allocation +
-- field assignments were measurable on long conversations.
--
-- Each entry is a list of patterns that all flag the same risk label.
-- Patterns cover both dot-notation (os.remove) and string-indexed access
-- (os["remove"], os['remove'], _G.os.remove) so the model cannot bypass the
-- warning by simply switching syntax. Catches the obvious bypass attempts;
-- determined obfuscation (loadstring with hex-encoded strings, etc.) is
-- still possible but at that point the model is actively trying to evade
-- the user's safety check, which is well outside our threat model -- the
-- user is opting in to running generated code in the first place.
do
  local RISKY_PATTERNS = {
    { label = "os.remove (deletes files)", patterns = {
      "os%.remove",
      'os%s*%[%s*["\']remove["\']%s*%]',
      "_G%.os%.remove",
      '_G%s*%[%s*["\']os["\']%s*%]',
    }},
    { label = "os.rename (moves/renames files)", patterns = {
      "os%.rename",
      'os%s*%[%s*["\']rename["\']%s*%]',
    }},
    { label = "os.execute (runs shell commands)", patterns = {
      "os%.execute",
      'os%s*%[%s*["\']execute["\']%s*%]',
      "_G%.os%.execute",
    }},
    { label = "io.popen (runs shell commands)", patterns = {
      "io%.popen",
      'io%s*%[%s*["\']popen["\']%s*%]',
    }},
    { label = "io.open in write/append mode", patterns = {
      -- Anchor the mode arg to the second positional ([^,]+ prevents the
      -- lazy match from walking across the path arg into a later string
      -- like print("welcome") that happens to start with "w" or "a"). The
      -- old lazy pattern flagged read-mode opens whenever any later quoted
      -- string in the snippet started with w or a (false-positive risky
      -- popup on perfectly safe read scripts).
      'io%.open%s*%([^,]+,%s*["\']w',
      'io%.open%s*%([^,]+,%s*["\']a',
      'io%s*%[%s*["\']open["\']%s*%]',
    }},
    { label = "shell/process launch via REAPER or SWS", patterns = {
      -- REAPER's built-in process launcher and the SWS / js_ReaScriptAPI
      -- shell helpers. Generated code can shell out via these APIs without
      -- touching os.execute or io.popen, so they need explicit coverage in
      -- the scanner -- otherwise a malicious or careless plugin call could
      -- run arbitrary commands while the auto-run gate stays silent.
      "reaper%.ExecProcess",
      "reaper%.CF_ShellExecute",
      "reaper%.BR_Win32_ShellExecute",
      'reaper%s*%[%s*["\']ExecProcess["\']%s*%]',
      'reaper%s*%[%s*["\']CF_ShellExecute["\']%s*%]',
      'reaper%s*%[%s*["\']BR_Win32_ShellExecute["\']%s*%]',
    }},
    { label = "require (loads external modules)", patterns = {
      "require%s*%(",
      "require%s*['\"]",
    }},
    { label = "dofile (executes external files)", patterns = {
      "dofile%s*%(",
      "dofile%s*['\"]",
    }},
    { label = "loadfile (loads external files)", patterns = {
      "loadfile%s*%(",
      "loadfile%s*['\"]",
    }},
    { label = "loadstring/load (executes runtime strings)", patterns = {
      "loadstring%s*%(",
      "[^%w_]load%s*%(",  -- bare load() but not e.g. fileloader(
    }},
    { label = "debug library access", patterns = {
      "debug%.",
      'debug%s*%[%s*["\']',
    }},
  }
  function Code.scan_risky(code)
    local found = {}
    for _, entry in ipairs(RISKY_PATTERNS) do
      for _, pat in ipairs(entry.patterns) do
        if code:find(pat) then
          found[#found+1] = entry.label
          break  -- one match per label is enough
        end
      end
    end
    if #found == 0 then return nil end
    return "Warning: " .. tbl_concat(found, ", ")
  end
end

-- =============================================================================
-- Code.run
-- =============================================================================
-- Compiles and executes a Lua string inside REAPER. Shows a message box on
-- compile or runtime error. Returns true on success, false on error.
--
-- Wraps execution in a plugin-level undo block as a safety net. The assistant
-- is instructed to include Undo_BeginBlock/EndBlock in its code, but if it
-- forgets, this outer wrapper ensures the user still gets undo protection.
-- Nested undo blocks are harmless in REAPER (inner ones are simply absorbed).

-- =============================================================================
-- Code.safety_backup
-- =============================================================================
-- Copies the current project file to a timestamped .rpp-bak file in the same
-- directory. Returns true on success, or false plus an error key on failure:
--   "unsaved"    - project has never been saved (no file on disk)
--   "read_error" - could not open the source file
--   "write_error"- could not write the backup file
function Code.safety_backup()
  local BACKUP_MAX = 10  -- maximum safety backups to keep per project
  local _, proj_path = reaper.EnumProjects(-1)
  if not proj_path or proj_path == "" then
    return false, "unsaved"
  end

  -- Extract directory and project name (without .rpp extension). Match the
  -- extension case-insensitively so projects saved as .RPP / .Rpp / etc. are
  -- not treated as unsaved.
  local dir  = proj_path:match("(.+)[/\\]")
  local name = proj_path:match("([^/\\]+)%.[rR][pP][pP]$")
  if not dir or not name then
    return false, "unsaved"
  end

  -- Diff-aware: skip if the project state hasn't changed since our last backup.
  -- GetProjectStateChangeCount increments on every change (fader moves, edits,
  -- FX adds, etc.) regardless of whether the user has saved.
  local cur_state = reaper.GetProjectStateChangeCount(0)
  if S.last_backup_path and S.last_backup_state == cur_state then
    return false, "unchanged"
  end

  local timestamp   = os.date("%Y%m%d-%H%M%S")
  local backup_path = dir .. RA.SEP .. name .. "-SafetyBackup-" .. timestamp .. ".rpp-bak"

  -- Save current project state (including unsaved changes) directly to the
  -- backup path without touching the main .rpp. Options=0 means no template
  -- flags and no project-path reassignment.
  reaper.Main_SaveProjectEx(0, backup_path, 0)

  -- Main_SaveProjectEx returns nothing, so verify the backup landed on disk
  -- before claiming success. Without this, a permission error or full-disk
  -- failure would silently let generated code run while the UI insists a
  -- safety backup exists.
  if not reaper.file_exists(backup_path) then
    return false, "write_error"
  end
  local probe = io.open(backup_path, "rb")
  if not probe then return false, "write_error" end
  local first = probe:read(1)
  probe:close()
  if not first then return false, "write_error" end

  -- Track last backup state for diff-aware skipping.
  S.last_backup_path  = backup_path
  S.last_backup_state = cur_state

  -- Enforce backup cap: collect all SafetyBackup files, delete oldest if over limit.
  -- Escape Lua magic characters in the project name so names like "Mix-v1.2"
  -- don't break the pattern and bypass the cap (causing infinite disk bloat).
  local safe_name = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
  local pattern = "^" .. safe_name .. "%-SafetyBackup%-%d+%-%d+%.rpp%-bak$"
  local backups = {}
  local idx = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, idx)
    if not fn then break end
    if fn:match(pattern) then
      backups[#backups + 1] = fn
    end
    idx = idx + 1
  end
  if #backups > BACKUP_MAX then
    table.sort(backups)  -- alphabetical = chronological (timestamp format)
    for k = 1, #backups - BACKUP_MAX do
      local victim = dir .. RA.SEP .. backups[k]
      local ok_rm, err_rm = os.remove(victim)
      if not ok_rm then
        Log.line("BACKUP", "Failed to prune old safety backup "
          .. backups[k] .. ": " .. tostring(err_rm))
      end
    end
  end

  return true
end

-- Redirects print() to reaper.ShowConsoleMsg so output from assistant-generated
-- code is visible in REAPER's console window rather than going to stdout
-- (which REAPER hides).
--
-- Sandboxed environment: generated code only sees a curated whitelist of Lua
-- builtins plus the reaper/gfx APIs. Dangerous modules (os, io, debug,
-- package) and meta-level primitives (load, loadfile, dofile, require,
-- rawset, rawget, getmetatable, setmetatable, _G) are excluded. This is a
-- defence-in-depth layer on top of the risky-code scanner and the system
-- prompt rules -- any one of the three may stop a bad generation, but all
-- three together make accidental damage extremely unlikely.
--
-- The sandbox is a flat table (no __index fallback to _G) so generated code
-- cannot reach anything not explicitly listed. Writes go into the sandbox
-- table itself and do not leak to script globals.

-- Build the sandbox once at load time. Rebuilding per-call would be wasteful
-- since the whitelist is static; only the `print` redirect needs the closure.

-- Shallow-copy a table's fields into a new table. Used to isolate sandbox
-- copies of `string`, `math`, and `table` from the host environment so that
-- generated code cannot corrupt the host's standard libraries by mutating
-- shared references (e.g. `string.format = function() return "pwned" end`).
local function sandbox_lib_copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local CODE_SANDBOX_BASE = {
  -- Lua core builtins (safe subset)
  assert     = assert,
  error      = error,
  ipairs     = ipairs,
  next       = next,
  pairs      = pairs,
  pcall      = pcall,
  select     = select,
  tonumber   = tonumber,
  tostring   = tostring,
  type       = type,
  unpack     = table.unpack or unpack,
  xpcall     = xpcall,
  -- Safe standard libraries (isolated copies -- mutations by generated code
  -- stay inside the sandbox and cannot corrupt host-side string/math/table).
  math       = sandbox_lib_copy(math),
  string     = sandbox_lib_copy(string),
  table      = sandbox_lib_copy(table),
  -- REAPER APIs (the whole point of running generated code)
  reaper     = reaper,
  gfx        = gfx,
}

function Code.run(code)
  -- Per-call sandbox: shallow copy the static base and add the print redirect.
  -- Built BEFORE load() so we can pass the env directly via the 4th argument,
  -- which is cleaner and stricter than retrofitting _ENV via debug.setupvalue.
  local code_env = {}
  for k, v in pairs(CODE_SANDBOX_BASE) do code_env[k] = v end
  code_env.print = function(...)
    -- Use select("#", ...) + select(i, ...) rather than {...}/#args: a table
    -- built with `{...}` has an undefined length when the varargs contain nil
    -- (e.g. print(1, nil, 3)), which silently drops trailing arguments.
    local n = select("#", ...)
    local buf = {}
    for i = 1, n do
      local v = tostring((select(i, ...)))
      if i > 1 then reaper.ShowConsoleMsg("\t"); buf[#buf+1] = "\t" end
      reaper.ShowConsoleMsg(v)
      buf[#buf+1] = v
    end
    reaper.ShowConsoleMsg("\n")
    Log.line("SCRIPT", "print: " .. table.concat(buf))
  end

  -- Undo capture state. The outer wrapper (below) is the ONLY real Begin/End
  -- pair against REAPER's undo stack; the shim intercepts the generated
  -- code's own Begin/End calls so a throw between them cannot unbalance the
  -- stack. We still capture the descriptive label the code passed to
  -- Undo_EndBlock and forward it to the outer End, so REAPER's undo history
  -- reads "ReaAssist: Create 10 tracks" rather than a generic "ReaAssist".
  -- Later captures overwrite earlier ones; generated code that issues
  -- multiple Begin/End pairs collapses into one outer entry with the last
  -- non-empty label (typical generations are one logical operation).
  local inner_undo_label = nil
  local inner_undo_flags = -1

  -- Wrap `reaper` so user-facing calls (dialogs, console output) are logged
  -- when debug logging is enabled. Every other reaper.* call falls through to
  -- the real API via __index with zero overhead when logging is off.
  local reaper_shim = setmetatable({
    ShowMessageBox = function(msg, title, btn_type)
      Log.line("SCRIPT", "ShowMessageBox [" .. tostring(title) .. "]: "
        .. tostring(msg):gsub("\n", " \\n "))
      return reaper.ShowMessageBox(msg, title, btn_type)
    end,
    ShowConsoleMsg = function(msg)
      Log.line("SCRIPT", "ShowConsoleMsg: " .. tostring(msg):gsub("\n$", ""):gsub("\n", " \\n "))
      return reaper.ShowConsoleMsg(msg)
    end,
    -- Undo shim: no-op on REAPER's side, capture the label on End so the
    -- outer wrapper can apply it. Return 0 from EndBlock to match REAPER's
    -- real signature (it returns 0 when there was nothing to undo, non-zero
    -- otherwise); generated code rarely checks this, and returning 0 is the
    -- safe default given we didn't actually open a real block here.
    Undo_BeginBlock  = function() end,
    Undo_BeginBlock2 = function(_proj) end,
    Undo_EndBlock = function(label, flags)
      if label and label ~= "" then
        inner_undo_label = label
        inner_undo_flags = flags or -1
      end
      return 0
    end,
    Undo_EndBlock2 = function(_proj, label, flags)
      if label and label ~= "" then
        inner_undo_label = label
        inner_undo_flags = flags or -1
      end
      return 0
    end,
  }, { __index = reaper })
  code_env.reaper = reaper_shim

  if Log.enabled() then
    Log.line("SCRIPT", "Running generated code (" .. #code .. " bytes)")
  end

  -- "t" enforces text-only chunks (no bytecode), and the 4th arg sets _ENV
  -- directly at compile time without needing debug.setupvalue.
  local fn, compile_err = load(code, "ReaAssist", "t", code_env)
  if not fn then
    local err_str = tostring(compile_err)
    Log.line("SCRIPT", "Compile error: " .. err_str)
    Diag.add_error(err_str, nil, code)
    -- Surface the failure as a chat-visible message instead of (only) a modal
    -- popup: the popup interrupts flow and hides the error the moment the
    -- user clicks OK, so they have nothing to reference when they type a
    -- follow-up. Inline lets them read the trace, copy parts, and keep going.
    Log.add_error("Lua compile error in generated code:\n\n" .. err_str)
    -- Stash so the next user prompt's send_to_api can include the error as
    -- model context -- when the user types "fix that" they expect the model
    -- to know what broke. Cleared after the next send.
    S.last_run_error = "compile error: " .. err_str
    return false
  end

  -- Plugin-level undo wrapper. The generated code's own Undo_Begin/EndBlock
  -- calls are intercepted by reaper_shim above (no-op + label capture), so
  -- this pair is the ONLY real interaction with REAPER's undo stack and a
  -- throw anywhere inside fn() cannot leave the stack unbalanced. The label
  -- the inner code passed to Undo_EndBlock ("ReaAssist: Create 10 tracks"
  -- etc.) is surfaced in REAPER's undo history via inner_undo_label.
  reaper.Undo_BeginBlock()
  local ok, run_err = xpcall(fn, debug and debug.traceback or tostring)
  reaper.Undo_EndBlock(inner_undo_label or "ReaAssist", inner_undo_flags)
  if not ok then
    local err_str = tostring(run_err)
    Log.line("SCRIPT", "Runtime error: " .. err_str:gsub("\n", " \\n "))
    Diag.add_error(err_str, nil, code)
    -- Trim the traceback to the first 6 lines so the chat bubble stays
    -- compact. The full trace is still in the debug log + Diag report.
    local short = err_str
    do
      local lines, n = {}, 0
      for line in err_str:gmatch("[^\n]+") do
        n = n + 1
        if n > 6 then lines[#lines+1] = "  ..."; break end
        lines[#lines+1] = line
      end
      short = tbl_concat(lines, "\n")
    end
    Log.add_error("Runtime error in generated code:\n\n" .. short)
    S.last_run_error = "runtime error: " .. err_str
    return false
  end
  Log.line("SCRIPT", "Script completed OK")
  reaper.UpdateArrange()
  return true
end

-- =============================================================================
-- Code.tokenize_lua  /  Code.tokenize_jsfx
-- =============================================================================
-- Lightweight syntax highlighter for the chat code blocks. Used by default
-- for every code block until the user clicks the per-block Edit button to
-- switch that block to a plain editable widget. The tokenizer walks the source
-- character by character (no PCRE/lpeg) and emits a flat list of {type, text} tokens that
-- the renderer then paints with TextColored + SameLine. Token text may span
-- newlines (long strings, block comments) -- the renderer slices on \n.
--
-- Token types: "kw" (keyword), "str" (string), "num", "com" (comment),
--              "api" (known library: reaper, ImGui, math, ...), "id", "ws",
--              "other" (operators / punctuation -- rendered in default color).
--
-- Limitations on purpose (keep the tokenizer ~120 lines):
--   * No nested long brackets [==[ ... ]==] -- only [[ ... ]] is recognised.
--   * No multi-character escape parsing inside strings; we just walk past \X.
--   * JSFX/EEL gets a separate, simpler tokenizer (//, /* */, # for hex).
local LUA_KEYWORDS = {
  ["and"]=1, ["break"]=1, ["do"]=1, ["else"]=1, ["elseif"]=1, ["end"]=1,
  ["false"]=1, ["for"]=1, ["function"]=1, ["goto"]=1, ["if"]=1, ["in"]=1,
  ["local"]=1, ["nil"]=1, ["not"]=1, ["or"]=1, ["repeat"]=1, ["return"]=1,
  ["then"]=1, ["true"]=1, ["until"]=1, ["while"]=1,
}
local LUA_API_NAMES = {
  reaper=1, ImGui=1, gfx=1, math=1, string=1, table=1, io=1, os=1,
  bit=1, debug=1, coroutine=1, package=1, _G=1, _ENV=1,
  ipairs=1, pairs=1, next=1, select=1, type=1, tostring=1, tonumber=1,
  pcall=1, xpcall=1, error=1, assert=1, print=1, require=1, setmetatable=1,
  getmetatable=1, rawget=1, rawset=1, rawequal=1, rawlen=1, unpack=1,
  load=1, loadstring=1, loadfile=1, dofile=1,
}

-- Detects a Lua long-bracket open at position i. Returns the level (number of
-- "=" between the brackets) if `[`, optional `=...`, `[` is present, else nil.
-- Used by the tokenizer to handle [[...]], [=[...]=], [==[...]==], etc.
local function _long_bracket_open_level(src, i)
  if src:sub(i, i) ~= "[" then return nil end
  local j = i + 1
  while src:sub(j, j) == "=" do j = j + 1 end
  if src:sub(j, j) ~= "[" then return nil end
  return j - i - 1
end

function Code.tokenize_lua(src)
  local tokens = {}
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    -- Whitespace run (preserve verbatim so indentation lines up).
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      local j = i + 1
      while j <= n do
        local cj = src:sub(j, j)
        if cj ~= " " and cj ~= "\t" and cj ~= "\n" and cj ~= "\r" then break end
        j = j + 1
      end
      tokens[#tokens+1] = { type = "ws", text = src:sub(i, j - 1) }
      i = j
    -- Block comment --[[ ... ]] (or --[=[ ... ]=], --[==[ ... ]==], etc.)
    elseif c == "-" and src:sub(i + 1, i + 1) == "-"
       and _long_bracket_open_level(src, i + 2) then
      local lvl   = _long_bracket_open_level(src, i + 2)
      local close = src:find("]" .. ("="):rep(lvl) .. "]",
        i + 2 + lvl + 1, true)
      local stop  = close and (close + lvl + 1) or n
      tokens[#tokens+1] = { type = "com", text = src:sub(i, stop) }
      i = stop + 1
    -- Line comment --
    elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
      local nl   = src:find("\n", i, true)
      local stop = nl and (nl - 1) or n
      tokens[#tokens+1] = { type = "com", text = src:sub(i, stop) }
      i = stop + 1
    -- Long-bracket string [[ ... ]] (or [=[ ... ]=], [==[ ... ]==], etc.)
    elseif c == "[" and _long_bracket_open_level(src, i) then
      local lvl   = _long_bracket_open_level(src, i)
      local close = src:find("]" .. ("="):rep(lvl) .. "]",
        i + lvl + 2, true)
      local stop  = close and (close + lvl + 1) or n
      tokens[#tokens+1] = { type = "str", text = src:sub(i, stop) }
      i = stop + 1
    -- Quoted string ('...' or "...")
    elseif c == '"' or c == "'" then
      local quote = c
      local j = i + 1
      while j <= n do
        local cj = src:sub(j, j)
        if cj == "\\" then
          j = j + 2
        elseif cj == quote then
          j = j + 1
          break
        elseif cj == "\n" then
          break  -- unterminated; stop at newline
        else
          j = j + 1
        end
      end
      tokens[#tokens+1] = { type = "str", text = src:sub(i, j - 1) }
      i = j
    -- Number (hex, decimal, optional fractional and exponent parts).
    elseif c:match("%d") then
      local rest = src:sub(i)
      local num  = rest:match("^0[xX][%dA-Fa-f]+") or
                   rest:match("^%d+%.?%d*[eE][%+%-]?%d+") or
                   rest:match("^%d+%.?%d*")
      if num and #num > 0 then
        tokens[#tokens+1] = { type = "num", text = num }
        i = i + #num
      else
        tokens[#tokens+1] = { type = "other", text = c }
        i = i + 1
      end
    -- Identifier or keyword.
    elseif c:match("[_%a]") then
      local rest  = src:sub(i)
      local ident = rest:match("^[_%a][_%w]*") or c
      local ttype
      if LUA_KEYWORDS[ident] then
        ttype = "kw"
      elseif LUA_API_NAMES[ident] then
        ttype = "api"
      else
        ttype = "id"
      end
      tokens[#tokens+1] = { type = ttype, text = ident }
      i = i + #ident
      -- Chain api highlight through dotted accesses so
      -- "reaper.InsertTrackAtIndex" renders the whole path in fn_amber,
      -- not just the module prefix. Tags the ".method" tail as api too.
      if ttype == "api" then
        while i <= n and src:sub(i, i) == "." do
          local next_ident = src:sub(i + 1):match("^[_%a][_%w]*")
          if not next_ident then break end
          tokens[#tokens+1] = { type = "api", text = "." }
          tokens[#tokens+1] = { type = "api", text = next_ident }
          i = i + 1 + #next_ident
        end
      end
    -- Anything else: single-char "other" token (operators, punctuation).
    else
      tokens[#tokens+1] = { type = "other", text = c }
      i = i + 1
    end
  end
  return tokens
end

local JSFX_KEYWORDS = {
  ["if"]=1, ["else"]=1, ["while"]=1, ["loop"]=1, ["function"]=1,
  ["local"]=1, ["global"]=1, ["instance"]=1, ["this"]=1,
}

function Code.tokenize_jsfx(src)
  local tokens = {}
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      local j = i + 1
      while j <= n do
        local cj = src:sub(j, j)
        if cj ~= " " and cj ~= "\t" and cj ~= "\n" and cj ~= "\r" then break end
        j = j + 1
      end
      tokens[#tokens+1] = { type = "ws", text = src:sub(i, j - 1) }
      i = j
    -- /* block comment */
    elseif c == "/" and src:sub(i + 1, i + 1) == "*" then
      local close = src:find("*/", i + 2, true)
      local stop  = close and (close + 1) or n
      tokens[#tokens+1] = { type = "com", text = src:sub(i, stop) }
      i = stop + 1
    -- // line comment
    elseif c == "/" and src:sub(i + 1, i + 1) == "/" then
      local nl   = src:find("\n", i, true)
      local stop = nl and (nl - 1) or n
      tokens[#tokens+1] = { type = "com", text = src:sub(i, stop) }
      i = stop + 1
    -- JSFX section headers (@init, @sample, @block, @slider, @serialize, @gfx)
    elseif c == "@" then
      local rest = src:sub(i)
      local sect = rest:match("^@%w+") or "@"
      tokens[#tokens+1] = { type = "kw", text = sect }
      i = i + #sect
    -- Quoted string ("...")
    elseif c == '"' or c == "'" then
      local quote = c
      local j = i + 1
      while j <= n do
        local cj = src:sub(j, j)
        if cj == "\\" then
          j = j + 2
        elseif cj == quote then
          j = j + 1
          break
        elseif cj == "\n" then
          break
        else
          j = j + 1
        end
      end
      tokens[#tokens+1] = { type = "str", text = src:sub(i, j - 1) }
      i = j
    elseif c:match("%d") then
      local rest = src:sub(i)
      local num  = rest:match("^0[xX][%dA-Fa-f]+") or
                   rest:match("^%d+%.?%d*[eE][%+%-]?%d+") or
                   rest:match("^%d+%.?%d*")
      if num and #num > 0 then
        tokens[#tokens+1] = { type = "num", text = num }
        i = i + #num
      else
        tokens[#tokens+1] = { type = "other", text = c }
        i = i + 1
      end
    elseif c:match("[_%a]") then
      local rest  = src:sub(i)
      local ident = rest:match("^[_%a][_%w]*") or c
      tokens[#tokens+1] = {
        type = JSFX_KEYWORDS[ident] and "kw" or "id",
        text = ident,
      }
      i = i + #ident
    else
      tokens[#tokens+1] = { type = "other", text = c }
      i = i + 1
    end
  end
  return tokens
end

-- =============================================================================
-- Net.process_response_buckets: handle <context_needed> on-demand buckets
-- =============================================================================
-- Parses any <context_needed>...</context_needed> tag in the model response and,
-- if fresh bucket data is needed, assembles the enriched history and fires a
-- follow-up curl request. Returns true when the follow-up was fired (caller
-- should bail); false when the normal final-response path should continue.
function Net.process_response_buckets(text)
  -- Handle <context_needed> on-demand buckets: session, docs, plugin_ref,
  -- fx_params:Name[, Name2]. Buckets can be combined in one tag (comma-separated).
  -- Each is guarded by a one-shot flag so the same bucket is never injected twice
  -- in one turn, preventing infinite follow-up loops.
  --
  -- Strip inline code spans and fenced code blocks BEFORE looking for
  -- <context_needed> tags. Models often quote the tag syntax in
  -- explanations ("your reply must be `<context_needed>docs</context_needed>`
  -- with no other content"), and those quoted tags are demonstrations,
  -- not real requests. Parsing them fires a wasted bucket-fetch round
  -- trip, which the loop detector then flags as duplicate context and
  -- aborts the turn with a user-facing error. A compliant model's real
  -- request emits the bare tag per the system-prompt rule "AND NOTHING
  -- ELSE," so the bare form will still match after scrubbing; only the
  -- demonstration-quoted form gets filtered out.
  local scrubbed = text
    :gsub("```.-```", "")     -- fenced code blocks (non-greedy)
    :gsub("`[^`]*`", "")      -- inline code spans
  -- Models occasionally emit two separate <context_needed> tags in one
  -- response instead of one comma-joined tag. Collect all of them and merge
  -- their payloads with a comma so the existing token parser handles them
  -- uniformly. Without this, only the first tag was processed and the rest
  -- vanished silently, leaving the model stuck waiting for context.
  local merged = {}
  for cap in scrubbed:gmatch("<context_needed>%s*(.-)%s*</context_needed>") do
    if cap ~= "" then merged[#merged+1] = cap end
  end
  local bucket_str = (#merged > 0) and tbl_concat(merged, ", ") or nil
  if not (bucket_str and S.pending_orig_prompt) then return false end

  -- Mixed-output detection. The system prompt requires a bare <context_needed>
  -- tag with no prose. Models violate this routinely with polite hedges like
  -- "I need to see which tracks have FX before I can act." + tag. Old behavior
  -- surfaced the prose and dropped the tag, forcing the user to nag the model
  -- two or three times before it complied with a bare tag. New behavior: fire
  -- the bucket fetch anyway (the prose is hidden because intermediate bucket-
  -- fetch turns aren't displayed) and append a reminder to the follow-up so
  -- the model self-corrects on subsequent turns. The CONTEXT_LOOP detector
  -- below catches the pathological case (model keeps re-requesting already-
  -- pinned data). Threshold: 40 non-whitespace characters of non-tag,
  -- non-code content -- short tags like "Fetching..." don't need the hint.
  do
    local non_tag = scrubbed:gsub("<context_needed>.-</context_needed>", "")
    local non_ws_count = 0
    for _ in non_tag:gmatch("%S") do
      non_ws_count = non_ws_count + 1
      if non_ws_count > 40 then break end
    end
    if non_ws_count > 40 then
      Log.line("CONTEXT_NEEDED",
        "tag emitted alongside prose; firing fetch with reminder (\""
        .. bucket_str .. "\")")
      S._mixed_output_hint = true
    end
  end

  local wants_docs        = false
  local wants_docs_extended = false
  local wants_session     = false
  local wants_fx_params   = false
  local wants_plugin_ref  = false
  local plugin_ref_names  = {}  -- plugin names for plugin_ref scoped bucket
  local wants_fx_list     = false
  local wants_fx_chains   = false
  local wants_track_flags = false
  local wants_midi        = false
  local wants_pref_plugins = false
  local wants_theme       = false
  local wants_fx_inspect  = false
  -- Sentinel: set when the model emits a <context_needed> for data already
  -- in sticky_context (typically from preempt injection or an earlier
  -- turn's fetch). We still need to fire a follow-up turn -- the model's
  -- response so far is just the context_needed tag, not code -- but we
  -- don't fetch anything new. The reinforcement hint tells the model the
  -- data is already available and nudges it to write code. Weak models
  -- (GPT-5 mini, Flash 3) hit this path routinely after preempt injection.
  local wants_preempt_hint = false
  local wants_prompt_bundle = false
  local pref_plugin_types = {}  -- type keys for preferred_plugins scoped bucket
  local fx_filter_names   = {}  -- plugin names to match; populated from the colon payload
  local fx_list_search    = {}  -- search terms for fx_list bucket
  local fx_inspect_names  = {}  -- search terms for fx_inspect bucket
  local prompt_bundle_names = {}  -- bundle names for prompt_bundle scoped bucket

  -- Parse comma-separated bucket tokens. Plain keywords ("session", "docs") are
  -- handled directly. Scoped keywords ("fx_params:VintageVerb") split on ":".
  -- Two-pass approach: pass 1 finds fx_params and its inline payload; pass 2
  -- collects subsequent non-keyword tokens as additional plugin name filters,
  -- so "fx_params:Plugin1, Plugin2" correctly builds filter = {Plugin1, Plugin2}.
  local recognised_keywords = { session=true, docs=true, docs_extended=true, fx_params=true, plugin_ref=true, fx_list=true, fx_chains=true, track_flags=true, midi=true, preferred_plugins=true, theme=true, fx_inspect=true, resolve=true, prompt_bundle=true }
  -- Hoisted out of the resolve branch so the pre-pass (just below) and the
  -- popup-bail scan-ahead can both reference it.
  local VALID_RESOLVE_TYPES = {
    eq=true, compressor=true, multiband_compressor=true, reverb=true,
    delay=true, saturation=true, limiter=true, gate=true, chorus=true,
    phaser=true, deesser=true, pitch_correction=true,
    pitch_shift=true, synth=true, custom=true,
  }
  local raw_tokens = {}
  for tok in bucket_str:gmatch("[^,]+") do
    raw_tokens[#raw_tokens+1] = tok:match("^%s*(.-)%s*$")
  end

  -- Expand resolve scoped-continuation. The system prompt teaches scoped
  -- continuation for plugin_ref/fx_list/preferred_plugins (e.g.
  -- "preferred_plugins:eq, compressor"), and the model occasionally applies
  -- the same shorthand to resolve ("resolve:compressor, eq"). The main
  -- parser's last_scoped path can't cover resolve because the resolve branch
  -- bails the loop on popup -- continuation tokens after that would be lost.
  -- Easiest fix: pre-rewrite "resolve:X, Y" into ["resolve:X", "resolve:Y"]
  -- here, so the rest of the parser sees explicit resolve tokens.
  local prev_was_resolve = false
  for i, tok in ipairs(raw_tokens) do
    local has_colon = tok:find(":", 1, true) ~= nil
    if has_colon then
      local hkw = (tok:match("^([^:]+)") or ""):match("^%s*(.-)%s*$"):lower()
      prev_was_resolve = (hkw == "resolve")
    elseif prev_was_resolve and VALID_RESOLVE_TYPES[tok:lower()] then
      raw_tokens[i] = "resolve:" .. tok
      -- prev_was_resolve stays true so a chain "resolve:a, b, c" all expand.
    else
      prev_was_resolve = false
    end
  end

  local last_scoped = nil  -- tracks which scoped keyword ("fx_params"/"fx_list") was last seen

  for tok_idx, tok in ipairs(raw_tokens) do
    local kw, payload = tok:match("^([^:]+):?(.*)$")
    kw = kw and kw:match("^%s*(.-)%s*$"):lower() or ""
    payload = payload and payload:match("^%s*(.-)%s*$") or ""

    if kw == "session" and not S.session_already_sent then
      wants_session = true
      last_scoped = nil
    elseif kw == "docs" and not S.docs_already_sent then
      wants_docs = true
      last_scoped = nil
    elseif kw == "docs_extended" and not S.docs_extended_already_sent then
      wants_docs_extended = true
      last_scoped = nil
    elseif kw == "plugin_ref" then
      last_scoped = "plugin_ref"
      if payload ~= "" and not S.plugin_ref_sent[payload] then
        wants_plugin_ref = true
        plugin_ref_names[#plugin_ref_names+1] = payload
      end
    elseif kw == "fx_list" and not S.fx_list_already_sent then
      wants_fx_list = true
      last_scoped = "fx_list"
      if payload ~= "" then
        fx_list_search[#fx_list_search+1] = payload
      end
    elseif kw == "fx_chains" and not S.fx_chains_already_sent then
      wants_fx_chains = true
      last_scoped = nil
    elseif kw == "track_flags" and not S.track_flags_already_sent then
      wants_track_flags = true
      last_scoped = nil
    elseif kw == "fx_params" and not S.fx_params_already_sent then
      wants_fx_params = true
      last_scoped = "fx_params"
      if payload ~= "" then
        fx_filter_names[#fx_filter_names+1] = payload
      end
    elseif kw == "midi" and not S.midi_already_sent then
      wants_midi = true
      last_scoped = nil
    elseif kw == "preferred_plugins" then
      last_scoped = "preferred_plugins"
      if payload ~= "" and not S.pref_plugins_sent[payload] then
        wants_pref_plugins = true
        pref_plugin_types[#pref_plugin_types+1] = payload
      end
    elseif kw == "theme" and not S.theme_already_sent then
      wants_theme = true
      last_scoped = nil
    elseif kw == "fx_inspect" and not S.fx_inspect_already_sent then
      wants_fx_inspect = true
      last_scoped = "fx_inspect"
      if payload ~= "" then
        fx_inspect_names[#fx_inspect_names+1] = payload
      end
    elseif kw == "prompt_bundle" then
      last_scoped = "prompt_bundle"
      if payload ~= "" and not S.prompt_bundle_sent[payload:lower()] then
        wants_prompt_bundle = true
        prompt_bundle_names[#prompt_bundle_names+1] = payload:lower()
      end
    elseif kw == "resolve" then
      -- resolve:<type> -- chokepoint for "give me a plugin of TYPE without
      -- specifying which". Translates the request into an underlying bucket
      -- based on what the user has installed/configured:
      --
      --   pref set for type     -> route through preferred_plugins:<type>
      --   eq + ReEQ installed   -> route through plugin_ref:ReEQ (EQ only)
      --   otherwise             -> block the round and raise the resolve
      --                            popup so the user can pick a plugin.
      --                            Returns immediately -- no follow-up curl
      --                            fires until the user clicks.
      --
      -- Supported types must match the set the system prompt is allowed to
      -- emit (see ReaAssist_System_Prompt.md "resolve:Type bucket").
      last_scoped = nil
      local rtype = payload:lower()
      if not VALID_RESOLVE_TYPES[rtype] then
        Log.line("RESOLVE", "unsupported type: " .. tostring(rtype))
      else
        -- Dedupe: if the data this resolve would fetch is already in
        -- sticky_context (from preempt injection or an earlier turn),
        -- skip the fetch and set a reinforcement hint. Covers the common
        -- case where preempt injected plugin_ref:ReEQ for "eq" but the
        -- model still emits <context_needed>resolve:eq</context_needed>
        -- anyway -- weak models (mini, flash) ignore pinned sticky data
        -- and re-request. Firing the follow-up with just the hint ("you
        -- already have this data above, use it now") nudges the model
        -- into writing code without another full bucket-fetch round trip.
        local already_covered = false
        if rtype == "eq" and S.plugin_ref_sent and S.plugin_ref_sent["ReEQ"] then
          already_covered = true
        elseif S.pref_plugins_sent and S.pref_plugins_sent[rtype] then
          already_covered = true
        end
        if already_covered then
          Log.line("RESOLVE", rtype
            .. " -> already covered by sticky (dedupe; no fetch)")
          wants_preempt_hint = true
          S._context_reuse_hint = true
        else
        local pref = FXCache.get_preferred_types()
        local pref_ident = pref and pref[rtype]
        -- Dev-only FabFilter hide: treat a matching pref as absent so the
        -- resolve path falls through to the popup branch below (same gate
        -- applied in CTX.preferred_plugins / load_pref_plugins / preempt).
        -- Without this, the resolve handler would still load the real
        -- pref content + mark pref_plugins_sent, and a second resolve
        -- request from the model would hit the dedupe branch and loop.
        if reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
           and _is_fabfilter_ident(pref_ident) then
          pref_ident = nil
        end
        if pref_ident and pref_ident ~= "" then
          Log.line("RESOLVE", rtype .. " -> user_pref ("
            .. tostring(pref_ident) .. ")")
          if not S.pref_plugins_sent[rtype] then
            wants_pref_plugins = true
            pref_plugin_types[#pref_plugin_types+1] = rtype
          end
        elseif rtype == "eq" and Code.is_reeq_installed() then
          -- Mid-session ReEQ catch. If the user just installed ReEQ via
          -- ReaPack while the script was already running, CTX._installed_fx_list
          -- is stale and Code.ensure_preferred_from_chains (which walks that
          -- cached list) won't find it. Code.is_reeq_installed() bypasses
          -- the cache via a direct filesystem check, so we catch it here.
          -- ReEQ is the only bundled/special-case plugin -- other types
          -- hit the resolve popup below if their chain came up empty.
          Log.line("RESOLVE", "eq -> reeq (mid-session filesystem check)")
          if not S.plugin_ref_sent["ReEQ"] then
            wants_plugin_ref = true
            plugin_ref_names[#plugin_ref_names+1] = "ReEQ"
          end
          -- Invalidate the cached FX list then rerun chains so pref_types.eq
          -- commits for future turns (no re-route through this branch).
          CTX._installed_fx_list = nil
          Code.ensure_preferred_from_chains()
        else
          -- Block the round: raise the modal and bail out without firing
          -- a follow-up. pending_orig_prompt / pending_snapshot stay intact
          -- so the popup's action buttons can resume the turn.
          -- Drop chat status to idle so the UI isn't stuck on "waiting";
          -- the popup itself is modal so the user can't send anything else.
          --
          -- Before bailing, scan the rest of raw_tokens for any OTHER
          -- resolve:Type tokens and stash their types in S.pending_resolves.
          -- After the popup resumes, resolve_popup_resume will append
          -- "resolve:<type>" for each queued type to its synthesized tag,
          -- so the model gets all originally-requested data in one round-trip
          -- instead of having to re-emit the dropped tokens itself.
          Log.line("RESOLVE", rtype .. " -> popup")
          S.pending_resolves = {}
          for ahead = tok_idx + 1, #raw_tokens do
            local at = raw_tokens[ahead]
            local akw, apayload = at:match("^([^:]+):?(.*)$")
            akw = akw and akw:match("^%s*(.-)%s*$"):lower() or ""
            apayload = apayload and apayload:match("^%s*(.-)%s*$"):lower() or ""
            if akw == "resolve" and apayload ~= "" and VALID_RESOLVE_TYPES[apayload] then
              S.pending_resolves[#S.pending_resolves+1] = apayload
            end
          end
          -- Stash any wants_* state already accumulated in this parse round
          -- (from tokens BEFORE this popup-triggering one). Without this, a
          -- plugin_ref:Name or preferred_plugins:type processed earlier in
          -- the same loop is silently lost when the function returns -- the
          -- locals plugin_ref_names / pref_plugin_types are discarded with
          -- the call frame. resolve_popup_resume re-emits these as buckets
          -- in its synthesized tag so the data is restored on the next pass.
          S.pending_plugin_ref_names = {}
          for _, n in ipairs(plugin_ref_names) do
            S.pending_plugin_ref_names[#S.pending_plugin_ref_names+1] = n
          end
          S.pending_pref_plugin_types = {}
          for _, t in ipairs(pref_plugin_types) do
            S.pending_pref_plugin_types[#S.pending_pref_plugin_types+1] = t
          end
          S.resolve_popup      = { type = rtype }
          S.open_resolve_popup = true
          S.status             = "idle"
          return true
        end
        end  -- if already_covered (dedupe)
      end
    elseif last_scoped and not recognised_keywords[kw] then
      -- Non-keyword token after a scoped keyword: additional name filter.
      -- e.g. "fx_list:Pro-Q, Valhalla" -> fx_list_search = {Pro-Q, Valhalla}
      local name = tok:match("^%s*(.-)%s*$")
      if last_scoped == "fx_params" then
        fx_filter_names[#fx_filter_names+1] = name
      elseif last_scoped == "fx_list" then
        fx_list_search[#fx_list_search+1] = name
      elseif last_scoped == "preferred_plugins" then
        if not S.pref_plugins_sent[name] then
          wants_pref_plugins = true
          pref_plugin_types[#pref_plugin_types+1] = name
        end
      elseif last_scoped == "plugin_ref" then
        if not S.plugin_ref_sent[name] then
          wants_plugin_ref = true
          plugin_ref_names[#plugin_ref_names+1] = name
        end
      elseif last_scoped == "fx_inspect" then
        fx_inspect_names[#fx_inspect_names+1] = name
      elseif last_scoped == "prompt_bundle" then
        local nlo = name:lower()
        if not S.prompt_bundle_sent[nlo] then
          wants_prompt_bundle = true
          prompt_bundle_names[#prompt_bundle_names+1] = nlo
        end
      end
    end
  end

  -- If fx_list was requested (now or earlier this turn), skip fx_params -
  -- the plugin likely isn't loaded yet, so fx_params will fail. The AI
  -- should use runtime helpers (find_param, set_param_display) instead.
  if wants_fx_params and (wants_fx_list or S.fx_list_already_sent) then
    wants_fx_params = false
    fx_filter_names = {}
  end
  -- fx_inspect supersedes fx_list (it includes the identifier in its output).
  if wants_fx_inspect and wants_fx_list then
    wants_fx_list = false
    fx_list_search = {}
  end

  if wants_docs or wants_docs_extended or wants_session or wants_fx_params or wants_plugin_ref or wants_fx_list or wants_fx_chains or wants_track_flags or wants_midi or wants_pref_plugins or wants_theme or wants_fx_inspect or wants_preempt_hint or wants_prompt_bundle then
    -- Build a fresh session snapshot if requested and not already present.
    if wants_session then
      S.session_already_sent = true
      S.pending_project  = S.pending_project or reaper.EnumProjects(-1)
      S.pending_snapshot = CTX.build_snapshot(S.pending_project)
    end

    -- Build the fx_params block for the requested plugins.
    -- Assembly is deferred into finalize_context so that any auto-inspect
    -- triggered below (to populate the cache for enum/range annotations)
    -- completes first.
    if wants_fx_params then
      S.fx_params_already_sent = true
      S.pending_project = S.pending_project or reaper.EnumProjects(-1)

      -- Auto-cache: if any matched FX has no cached param data, route the
      -- first uncached plugin through fx_inspect (silent: result populates
      -- the cache but is not appended to history_content, since fx_params
      -- already covers it with live values). Skip when the user explicitly
      -- requested fx_inspect this turn -- their inspect handles caching.
      -- The hidden temp track avoids touching the user's live FX, which
      -- would visibly cycle params and glitch audio.
      --
      -- INVARIANT: this `not wants_fx_inspect` guard is load-bearing for
      -- the silent-flag contract. If the auto-inspect ran alongside an
      -- explicit fx_inspect:X, S._fx_inspect_silent_for_fx_params (a
      -- single boolean) would silence both -- the user's explicit Foo
      -- inspection would never pin to sticky and the model would get no
      -- inspect data for it. If you ever remove this guard, you must
      -- replace the boolean with a per-name silent set (S._fx_inspect_
      -- silent_names = {name=true}) and gate every silent-flag read on
      -- per-name membership; the bool no longer captures the right
      -- granularity once mixed lists are possible.
      if not wants_fx_inspect then
        local _proj = S.pending_project
        local _tc = R_CountTracks(_proj)
        local found_search = nil
        for _ti = 0, _tc - 1 do
          if found_search then break end
          local _tr = R_GetTrack(_proj, _ti)
          local _fc = R_TrackFX_GetCount(_tr)
          for _fi = 0, _fc - 1 do
            local _, _fxnm = R_TrackFX_GetFXName(_tr, _fi, "")
            if CTX.fx_name_matches(_fxnm, fx_filter_names) then
              local _ck, _cp = FXCache.find_plugin(_fxnm)
              if not _cp then
                -- Use the user's filter term that matched as the search
                -- input for fx_inspect_load (cleaner than full bracketed
                -- VST3 identifier).
                for _, fn in ipairs(fx_filter_names) do
                  if _fxnm:lower():find(fn:lower(), 1, true) then
                    found_search = fn; break
                  end
                end
                found_search = found_search or _fxnm
                break
              end
            end
          end
        end
        if found_search then
          Log.line("FX_PARAMS",
            "uncached match -- auto-inspecting (silent): " .. found_search)
          fx_inspect_names[#fx_inspect_names+1] = found_search
          wants_fx_inspect = true
          S._fx_inspect_silent_for_fx_params = true
        end
      end

      -- Defer assembly into finalize_context (after any auto-inspect
      -- populates the cache).
      S._fx_params_pending_assemble = {
        proj   = S.pending_project,
        names  = fx_filter_names,
        fp_key = #fx_filter_names > 0
          and ("fx:" .. tbl_concat(fx_filter_names, "/")) or "fx_params",
      }
    end

    -- Assemble enriched history content: small inline-only buckets + USER
    -- REQUEST. Big sticky-backed buckets (plugin_ref / pref_plugins /
    -- fx_inspect / fx_params / docs_extended) write to S.sticky_context ONLY
    -- -- no inline duplication in history_content. On the follow-up build,
    -- Net.sticky_text() emits them as the pinned message, so the model sees
    -- each bucket exactly once per turn (in the well-cached pinned slot),
    -- not twice. Saves the bucket's size in input tokens per follow-up turn
    -- -- on a ~3K-token fx_inspect that's ~$0.02 of cache-write cost on
    -- Sonnet. See fetched_to_sticky below for the model-facing ack.
    -- CTX.docs/CTX.plugin_ref return nil + error on failure; show the error
    -- and proceed without the missing bucket rather than blocking the follow-up.
    local history_content = ""
    -- Collects bucket keys that were fetched-and-stickied this turn. Used to
    -- emit a brief model-facing pointer ("<context_needed> satisfied; data
    -- is in PINNED REFERENCES above") so the model doesn't re-request.
    local fetched_to_sticky = {}
    if wants_docs then
      S.docs_already_sent = true
      local ref_content, ref_err = CTX.docs()
      if ref_content then
        -- Pin docs to the persistent api_ref slot rather than inlining into
        -- this turn's history_content. Inlining was load-bearing on the
        -- bare /docs follow-up but fragile across multi-step turns: any
        -- subsequent <context_needed> in the same turn (e.g. session,
        -- fx_chains) rebuilds history_content from scratch and the docs
        -- inline disappears, forcing the model to re-emit
        -- <context_needed>docs</context_needed>. Since docs is already
        -- flagged sent, the second request loops and the turn aborts.
        -- Promoting to S.api_ref_message routes docs through the static
        -- pinned slot (same path as midi/theme refs and the docs-gate
        -- auto-retry), so it survives every follow-up build in this turn
        -- and stays pinned for the rest of the session.
        S.api_ref_message      = ref_content
        S.docs_fetched_session = true
        fetched_to_sticky[#fetched_to_sticky+1] = "docs"
      else
        Log.add_error(ref_err)
        wants_docs = false  -- clear flag so ctx_label is not updated below
      end
    end
    if wants_docs_extended then
      S.docs_extended_already_sent = true
      local ext_content, ext_err = CTX.docs_extended()
      if ext_content then
        -- Sticky only. Emitted by Net.sticky_text() on the follow-up build
        -- in the pinned slot; no duplicate inline copy in history_content.
        Net.sticky_set("docs_extended", ext_content)
        fetched_to_sticky[#fetched_to_sticky+1] = "docs_extended"
      else
        Log.add_error(ext_err)
        wants_docs_extended = false
      end
    end
    if wants_plugin_ref then
      local rp_content, rp_err = CTX.plugin_ref(plugin_ref_names)
      if rp_content then
        -- Mark each injected plugin name as sent this turn so later round-
        -- trips within the same user turn don't re-inject the same content,
        -- while still allowing plugin_ref for OTHER plugin names to fire.
        -- (Was a coarse boolean flag that blocked plugin_ref for ANY
        -- subsequent name once the first was sent -- caused resolve:eq ->
        -- ReEQ to silently drop when Pro-C 3 had been injected earlier in
        -- the same turn.) Marked only on fetch success: a disk error here
        -- used to lock the name out for the rest of the turn, so the next
        -- intra-turn retry would re-emit <context_needed>plugin_ref:Foo
        -- and get nothing back.
        for _, nm in ipairs(plugin_ref_names) do S.plugin_ref_sent[nm] = true end
        -- Sticky only -- emitted by Net.sticky_text() as the pinned message
        -- on the follow-up build.
        local rp_key = #plugin_ref_names > 0
          and ("plugin_ref:" .. tbl_concat(plugin_ref_names, "/")) or "plugin_ref"
        Net.sticky_set(rp_key, rp_content)
        fetched_to_sticky[#fetched_to_sticky+1] = rp_key
        -- Co-pin plugin bundle (same rationale as the preempt path).
        Net.copin_plugin_bundle(fetched_to_sticky)
      else
        Log.add_error(rp_err)
        wants_plugin_ref = false  -- clear flag so ctx_label is not updated below
      end
    end
    if wants_prompt_bundle then
      -- Per-name dedup like plugin_ref. Fetched content goes into
      -- sticky_context so it stays pinned for the rest of the conversation
      -- (subsequent turns see the bundle without re-fetching). Any bundles
      -- that fail to load are dropped with a user-visible error; successful
      -- ones still pin so the turn can proceed with partial coverage.
      local ok = 0
      for _, nm in ipairs(prompt_bundle_names) do
        local pb_content, pb_err = CTX.prompt_bundle(nm)
        if pb_content then
          S.prompt_bundle_sent[nm] = true
          local pb_key = "prompt_bundle:" .. nm
          Net.sticky_set(pb_key, pb_content)
          fetched_to_sticky[#fetched_to_sticky+1] = pb_key
          ok = ok + 1
        else
          Log.add_error(pb_err)
        end
      end
      if ok == 0 then wants_prompt_bundle = false end
    end
    if wants_fx_list then
      S.fx_list_already_sent = true
      local fl_content, fl_result = CTX.installed_fx(fx_list_search)
      if fl_content then
        history_content = history_content .. fl_content .. "\n"
          .. "Use the identifiers above with TrackFX_AddByName. Set parameters using find_param and set_param_display at runtime. Do NOT request fx_params.\n\n"
        -- Zero-match notice is embedded in fl_content so the assistant
        -- sees it and can self-correct. No user-facing error needed.
      else
        Log.add_error(fl_result)
        wants_fx_list = false
      end
    end
    if wants_fx_chains then
      S.fx_chains_already_sent = true
      local proj = S.pending_project or reaper.EnumProjects(-1)
      history_content = history_content .. CTX.fx(proj) .. "\n\n"
    end
    if wants_track_flags then
      S.track_flags_already_sent = true
      local proj = S.pending_project or reaper.EnumProjects(-1)
      history_content = history_content .. CTX.track_flags(proj) .. "\n\n"
    end
    -- MIDI ref is loaded into the persistent slot (S.midi_ref_message)
    -- rather than injected into history_content. The follow-up call's
    -- build_body_* will pick it up and prepend it as a synthetic
    -- user/assistant pair, just like the api_ref. From this turn forward
    -- it lives in the static cache prefix slot.
    if wants_midi then
      S.midi_already_sent = true
      local mref_content, mref_err = CTX.midi()
      if mref_content then
        S.midi_ref_message = mref_content
      else
        Log.add_error(mref_err)
        wants_midi = false  -- clear flag so ctx_label is not updated below
      end
    end
    -- Theme color reference: loaded into the persistent slot
    -- (S.theme_ref_message) rather than into history_content, matching the
    -- MIDI pattern. build_body_* will prepend it on every subsequent call.
    if wants_theme then
      S.theme_already_sent = true
      local th_content, th_err = CTX.theme()
      if th_content then
        S.theme_ref_message = th_content
          .. "\n\n(Theme reference is loaded above. Do NOT request "
          .. "<context_needed>theme</context_needed> or "
          .. "<context_needed>session</context_needed> -- you have "
          .. "everything needed. Proceed directly with the color change code.)"
      else
        Log.add_error(th_err)
        wants_theme = false
      end
    end
    -- Preferred plugins: load only the requested type sections.
    if wants_pref_plugins then
      local pp_content, pp_err = CTX.preferred_plugins(pref_plugin_types)
      if pp_content then
        -- Mark each injected type as sent this turn (per-type dedup, mirrors
        -- the plugin_ref_sent pattern). Was a coarse boolean that blocked
        -- preferred_plugins for ANY type once one had been sent in the turn
        -- -- caused the resolve:compressor follow-up to silently no-op
        -- after preferred_plugins:eq had fired in the same turn. Marked
        -- only on fetch success so an intra-turn retry can re-fetch a type
        -- that failed the first time.
        for _, t in ipairs(pref_plugin_types) do S.pref_plugins_sent[t] = true end
        -- Sticky only -- pinned-slot emission on follow-up build.
        local pp_key = #pref_plugin_types > 0
          and ("pref:" .. tbl_concat(pref_plugin_types, "/")) or "pref_plugins"
        Net.sticky_set(pp_key, pp_content)
        fetched_to_sticky[#fetched_to_sticky+1] = pp_key
        -- Co-pin plugin bundle (every pref-plugin pin drives a plugin task).
        Net.copin_plugin_bundle(fetched_to_sticky)
      else
        Log.add_error(pp_err)
        wants_pref_plugins = false
      end
    end
    -- (fx_params content is assembled in finalize_context, after any
    -- auto-inspect populates the cache.)

    -- fx_inspect: temporarily load a plugin to discover its parameters.
    -- Phase 1 runs here (add temp track + plugin); phase 2 (read params +
    -- cleanup) runs inside finalize_context after a one-frame defer.
    if wants_fx_inspect then
      S.fx_inspect_already_sent = true
      local tmp_tr, fx_idx, identifier, err, cached = CTX.fx_inspect_load(fx_inspect_names)
      if err then
        if S._fx_inspect_silent_for_fx_params then
          -- Silent auto-cache trigger from fx_params: don't surface the
          -- inspect error to the model. fx_params still emits live values
          -- (just without enum/range annotations).
          Log.line("FX_PARAMS",
            "silent auto-inspect failed (continuing): " .. err)
        else
          history_content = history_content .. "FX INSPECT ERROR: " .. err .. "\n\n"
        end
      elseif cached then
        -- Cache hit: format cached data directly, no temp track needed.
        if S._fx_cache_events then
          local t = S._fx_cache_events
          t.hit = t.hit or {}
          t.hit[#t.hit+1] = identifier
        end
        if not S._fx_inspect_silent_for_fx_params then
          local inspect_data = CTX.format_fx_params(
            identifier, cached.params, cached.max_group, fx_inspect_names, true)
          -- Sticky only -- pinned-slot emission on follow-up build.
          local fi_key = "fx_inspect:" .. tbl_concat(fx_inspect_names, "/")
          Net.sticky_set(fi_key, inspect_data)
          fetched_to_sticky[#fetched_to_sticky+1] = fi_key
        end
      else
        S._fx_inspect_tmp = {
          tr = tmp_tr, fx = fx_idx,
          id = identifier, names = fx_inspect_names,
        }
      end
    end

    -- Finalize: assemble remaining context, update labels, fire API.
    -- Wrapped in a function so it can be deferred one frame when fx_inspect
    -- needs REAPER to finish initialising the plugin before reading params.
    local finalize_context
    finalize_context = function()
      -- fx_inspect phase 2: read params from temp plugin, remove temp track.
      -- If the shallow scan detects readback lag (e.g. Soundtoys VST3),
      -- kick off a coroutine-paced deep scan and defer the rest of
      -- finalize_context until it completes (or is cancelled).
      if S._fx_inspect_tmp then
        local fi = S._fx_inspect_tmp
        -- ValidatePtr2: try_inspect_read already checks, but finalize_context
        -- can also be entered directly (np>0 path) with no validation gap, or
        -- after a deep scan where on_complete may have already deleted fi.tr.
        -- A stale handle here would crash scan_fx_params on the first
        -- TrackFX_* call.
        if not reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
          reaper.PreventUIRefresh(-1)
          reaper.Undo_EndBlock("ReaAssist: fx_inspect (invalid track)", 0)
          S._fx_inspect_tmp = nil
          if not S._fx_inspect_silent_for_fx_params then
            history_content = history_content
              .. "FX INSPECT ERROR: temporary track was invalidated before params could be read.\n\n"
          end
        else
        -- Wrap the shallow scan in xpcall so a thrown error (stale FX
        -- handle, REAPER returning nil from a probe, etc.) does not skip
        -- the cleanup at the end of this block, which would leave an
        -- orphaned hidden temp track + a stuck PreventUIRefresh(-1)
        -- imbalance + an unclosed Undo block.
        local _scan_ok, params_list, max_group, total_count, needs_deep =
          xpcall(function()
            return CTX.scan_fx_params(fi.tr, fi.fx)
          end, debug.traceback)
        if not _scan_ok then
          -- params_list holds the error+traceback string in the failure case.
          local err_msg = tostring(params_list or "scan threw")
          Log.line("FX_INSPECT", "shallow scan threw: " .. err_msg)
          if reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
            reaper.DeleteTrack(fi.tr)
          end
          reaper.PreventUIRefresh(-1)
          reaper.Undo_EndBlock("ReaAssist: fx_inspect (scan error)", 0)
          S._fx_inspect_tmp = nil
          if not S._fx_inspect_silent_for_fx_params then
            history_content = history_content
              .. "FX INSPECT ERROR: shallow scan failed unexpectedly.\n\n"
          end
          -- Fall through to fx_params assemble + rest of finalize. Use a
          -- dummy nil set so subsequent statements that read these locals
          -- don't reference the error string.
          params_list, max_group, total_count, needs_deep = nil, nil, nil, nil
          goto fx_inspect_done
        end

        if needs_deep and not S._deep_scan_started then
          S._deep_scan_started = true
          S._deep_scan_label   = fi.id
          Log.line("DEEP_SCAN", "chat: auto-triggering deep scan for " .. fi.id)
          local _started_ok = CTX.start_deep_scan({
            tr           = fi.tr,
            fx_idx       = fi.fx,
            identifier   = fi.id,
            search_names = fi.names,
            origin       = "chat",
            on_complete  = function(dparams, dmax, dcount)
              FXCache.put_plugin(fi.id, dparams, dcount, dmax, false)
              if S._fx_cache_events then
                local t = S._fx_cache_events
                t.cached = t.cached or {}
                t.cached[#t.cached+1] = fi.id
              end
              if not S._fx_inspect_silent_for_fx_params then
                local inspect_data = CTX.format_fx_params(
                  fi.id, dparams, dmax, fi.names, true)
                -- Sticky only -- pinned-slot emission on follow-up build.
                local fi_key = "fx_inspect:" .. tbl_concat(fi.names, "/")
                Net.sticky_set(fi_key, inspect_data)
                fetched_to_sticky[#fetched_to_sticky+1] = fi_key
              end
              if reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
                reaper.DeleteTrack(fi.tr)
              end
              -- PreventUIRefresh(-1) already done by scan_fx_params_deep_body;
              -- see comment there about avoiding double-release crashes.
              -- flags=0: discard the whole temp-track block rather than
              -- relying on Undo_DoUndo2 to walk it back (see preferred
              -- plugins scan for the rationale).
              reaper.Undo_EndBlock("ReaAssist: fx_inspect deep", 0)
              S._fx_inspect_tmp   = nil
              S._deep_scan_started = false
              S._deep_scan_label   = nil
              finalize_context()
            end,
            on_cancel    = function(reason)
              if reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
                reaper.DeleteTrack(fi.tr)
              end
              -- PreventUIRefresh(-1) already done by scan_fx_params_deep_body.
              reaper.Undo_EndBlock("ReaAssist: fx_inspect (cancelled)", 0)
              S._fx_inspect_tmp   = nil
              S._deep_scan_started = false
              S._deep_scan_label   = nil
              if reason == "cancelled" then
                -- User cancelled: abort the whole turn. The chat Cancel
                -- button already resets status/display; just bail.
                -- Clear leftover deferred-assemble + silent flag so they
                -- don't poison the next turn.
                S._fx_params_pending_assemble  = nil
                S._fx_inspect_silent_for_fx_params = nil
                return
              end
              if S._fx_inspect_silent_for_fx_params then
                Log.line("FX_PARAMS",
                  "silent auto-inspect deep scan failed (continuing): "
                  .. tostring(reason))
              else
                history_content = history_content
                  .. "FX INSPECT ERROR: Deep scan failed ("
                  .. tostring(reason) .. ").\n\n"
              end
              finalize_context()
            end,
          })
          if not _started_ok then
            -- start_deep_scan rejected the request (already active, missing
            -- opts, or _estimate_deep_probes threw). Neither on_complete nor
            -- on_cancel will fire, so unwind the resources fx_inspect_load
            -- set up: hidden temp track, PreventUIRefresh(+1), open Undo
            -- block. Without this the UI stops repainting and a stale undo
            -- block pairs with the next unrelated Undo_EndBlock in the
            -- session.
            Log.line("DEEP_SCAN", "chat: start_deep_scan returned false for "
              .. fi.id .. "; unwinding fx_inspect resources")
            if reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
              reaper.DeleteTrack(fi.tr)
            end
            reaper.PreventUIRefresh(-1)
            reaper.Undo_EndBlock("ReaAssist: fx_inspect (start_deep_scan failed)", 0)
            S._fx_inspect_tmp    = nil
            S._deep_scan_started = false
            S._deep_scan_label   = nil
            if not S._fx_inspect_silent_for_fx_params then
              history_content = history_content
                .. "FX INSPECT ERROR: deep scan could not start (see debug log).\n\n"
            end
            -- Bypass shallow-success path; continue with the rest of
            -- finalize_context (fx_params assemble, sticky build, etc.).
            params_list, max_group, total_count, needs_deep = nil, nil, nil, nil
            goto fx_inspect_done
          end
          return  -- coroutine runs; on_complete will re-call finalize_context
        end

        -- Shallow scan succeeded: cache, format, append inline.
        FXCache.put_plugin(fi.id, params_list, total_count, max_group, false)
        if S._fx_cache_events then
          local t = S._fx_cache_events
          t.cached = t.cached or {}
          t.cached[#t.cached+1] = fi.id
        end
        reaper.DeleteTrack(fi.tr)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("ReaAssist: fx_inspect", 0)
        if not S._fx_inspect_silent_for_fx_params then
          local inspect_data = CTX.format_fx_params(
            fi.id, params_list, max_group, fi.names, true)
          -- Sticky only -- pinned-slot emission on follow-up build.
          local fi_key = "fx_inspect:" .. tbl_concat(fi.names, "/")
          Net.sticky_set(fi_key, inspect_data)
          fetched_to_sticky[#fetched_to_sticky+1] = fi_key
        end
        S._fx_inspect_tmp = nil
        ::fx_inspect_done::
        end  -- end of ValidatePtr2 else
      end

      -- Assemble fx_params content now (any auto-inspect above has populated
      -- the cache, so enum/range annotations are picked up by CTX.fx_params).
      if S._fx_params_pending_assemble then
        local a = S._fx_params_pending_assemble
        local fx_str = CTX.fx_params(a.proj, a.names)
        -- Sticky only -- pinned-slot emission on follow-up build.
        Net.sticky_set(a.fp_key, fx_str)
        fetched_to_sticky[#fetched_to_sticky+1] = a.fp_key
        S._fx_params_pending_assemble = nil
      end

      -- Sticky context (plugin_ref, preferred_plugins, fx_params, fx_inspect)
      -- is emitted by Net.build_body_* as a pinned user/assistant pair after
      -- the api_ref pin -- no longer re-injected into per-turn history content.
      -- This keeps the moving cache breakpoint from having to re-write sticky
      -- bytes on every turn. See Net.sticky_text().
      -- Loop-recovery hint: prepended when the previous response from the
      -- model was a duplicate <context_needed> for already-provided data.
      -- See LOOP DETECTION in process_response_buckets.
      if S._context_reuse_hint then
        history_content = history_content
          .. "(NOTE: The reference data you requested is already present "
          .. "earlier in this conversation (pinned PLUGIN PARAMETER REFERENCE / "
          .. "PREFERRED PLUGINS blocks above). USE IT NOW to generate the code "
          .. "-- the identifiers and parameter indices/names you need are above. "
          .. "Do NOT emit another <context_needed> tag for this data.)\n\n"
        S._context_reuse_hint = nil  -- one-shot
      end
      if S._mixed_output_hint then
        history_content = history_content
          .. "(NOTE: Your previous reply emitted prose alongside the "
          .. "<context_needed> tag. The fetch was honored anyway, but the "
          .. "prose was hidden from the user. Per the system prompt, when "
          .. "you need data your entire reply must be the bare tag -- no "
          .. "prose before or after. On future turns, emit ONLY the tag.)\n\n"
        S._mixed_output_hint = nil  -- one-shot
      end
      -- Pointer to the pinned sticky slot. Each fetched bucket (plugin_ref /
      -- pref_plugins / fx_inspect / fx_params / docs_extended) lives ONLY
      -- in Net.sticky_text() now -- no inline duplication in this message.
      -- The pointer tells the model its <context_needed> was satisfied and
      -- to read the data above so it doesn't re-emit another context_needed.
      if #fetched_to_sticky > 0 then
        history_content = history_content
          .. "(<context_needed> satisfied this turn: "
          .. tbl_concat(fetched_to_sticky, ", ")
          .. ". The data is in PINNED REFERENCES above -- use it directly "
          .. "and do NOT re-request via another <context_needed>.)\n\n"
      end
      history_content = history_content .. "USER REQUEST:\n" .. S.pending_orig_prompt

      -- Update the Show Details context label to reflect all injected buckets.
      if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
        local dmsg = S.display_messages[S.pending_display_idx]
        -- Build updated label: start from existing, append newly injected buckets.
        local parts = {}
        local existing = dmsg.ctx_label or ""
        if existing ~= "" then parts[#parts+1] = existing end
        if wants_session and not existing:find("snapshot") then
          parts[#parts+1] = "snapshot"
        end
        -- "docs" and "api_ref" alias the same content; skip if either is
        -- already in the chip label so we don't render both.
        if wants_docs and not existing:find("api_ref", 1, true)
                      and not existing:find("docs",    1, true) then
          parts[#parts+1] = "docs"
        end
        if wants_docs_extended then parts[#parts+1] = "docs_extended" end
        if wants_plugin_ref then
          parts[#parts+1] = #plugin_ref_names > 0
            and ("plugin_ref:" .. tbl_concat(plugin_ref_names, "/")) or "plugin_ref"
        end
        if wants_fx_list then
          parts[#parts+1] = #fx_list_search > 0
            and ("fx_list:" .. tbl_concat(fx_list_search, "/")) or "fx_list"
        end
        if wants_fx_chains   then parts[#parts+1] = "fx_chains" end
        if wants_track_flags then parts[#parts+1] = "track_flags" end
        if wants_fx_params then
          parts[#parts+1] = #fx_filter_names > 0
            and ("fx:" .. tbl_concat(fx_filter_names, "/")) or "fx_params"
        end
        if wants_midi  then parts[#parts+1] = "midi" end
        if wants_theme then parts[#parts+1] = "theme" end
        if wants_pref_plugins then
          parts[#parts+1] = #pref_plugin_types > 0
            and ("pref:" .. tbl_concat(pref_plugin_types, "/")) or "pref_plugins"
        end
        if wants_fx_inspect and not S._fx_inspect_silent_for_fx_params then
          parts[#parts+1] = #fx_inspect_names > 0
            and ("fx_inspect:" .. tbl_concat(fx_inspect_names, "/")) or "fx_inspect"
        end
        -- Append sticky context labels not already covered by fresh buckets.
        local existing_joined = tbl_concat(parts, " + ")
        local sticky_keys = {}
        for skey in pairs(S.sticky_context) do sticky_keys[#sticky_keys+1] = skey end
        table.sort(sticky_keys)
        for _, skey in ipairs(sticky_keys) do
          if not existing_joined:find(skey, 1, true) then
            parts[#parts+1] = skey
          end
        end
        dmsg.ctx_label = #parts > 0 and tbl_concat(parts, " + ") or ""
      end

      -- Clear the silent-inspect flag now that all gating consumers
      -- (history append, sticky context, ctx_label) have read it.
      S._fx_inspect_silent_for_fx_params = nil

      -- Replace the last user history entry with the enriched content
      -- (snapshot is passed to Net.build_body(), never stored in history).
      if #S.history > 0 and S.history[#S.history].role == "user" then
        S.history[#S.history] = nil
      end
      S.history[#S.history+1] = {
        role    = "user",
        content = history_content,
      }
      -- Refresh the snapshot right before firing. finalize_context can run
      -- many seconds after the original send -- if fx_inspect triggered a
      -- deep scan, the user's cursor/selection/play state could have moved
      -- on. The snapshot rebuild is cheap next to the curl round trip, so
      -- always re-capture (when snapshots are enabled) rather than sending
      -- stale "at the cursor" / "to the selected item" context.
      if prefs.include_snapshot then
        S.pending_project  = S.pending_project or reaper.EnumProjects(-1)
        S.pending_snapshot = CTX.build_snapshot(S.pending_project)
      end
      S.status = "waiting"
      Code.safe_write(tmp.out, "")
      if not Net.fire_curl(Net.build_body(Net.trimmed_history(), S.pending_snapshot, S.pending_attachments)) then
        Log.add_error("Tried to load additional project info but the "
          .. "follow-up request didn't go through. Please try again.")
      end
      S.scroll_to_bottom = true
    end  -- finalize_context

    -- If fx_inspect loaded a plugin, poll until it's initialised (params
    -- readable) before finalizing. Heavy plugins (large sample libs, complex
    -- synths) may need more than one frame. Max ~1 second (30 retries).
    if S._fx_inspect_tmp then
      local inspect_retries = 0
      local function try_inspect_read()
        local fi = S._fx_inspect_tmp
        -- Guard: S._fx_inspect_tmp could have been cleared between defer
        -- cycles by another path (dev_signal cancel, project switch handler,
        -- etc.). Without this, the timeout branch's fi.tr / fi.names derefs
        -- below would crash 30 frames later.
        if not fi then
          S._fx_inspect_tmp = nil
          return
        end
        -- ValidatePtr2 before touching fi.tr: across up to 30 defer cycles
        -- (~1s) the user could switch projects or delete the track, leaving
        -- a dangling pointer that would crash TrackFX_GetNumParams.
        if not reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
          reaper.PreventUIRefresh(-1)
          reaper.Undo_EndBlock("ReaAssist: fx_inspect (invalid track)", 0)
          S._fx_inspect_tmp = nil
          -- Honor the silent-inspect contract: when this inspect was an
          -- auto-trigger from fx_params (not user-requested), do not leak
          -- "FX INSPECT ERROR" prose into history_content (which becomes
          -- the model prompt). Mirrors the timeout branch below.
          if not S._fx_inspect_silent_for_fx_params then
            history_content = history_content
              .. "FX INSPECT ERROR: temporary track was invalidated before params could be read.\n\n"
          end
          finalize_context()
          return
        end
        local np = R_TrackFX_GetNumParams(fi.tr, fi.fx) or 0
        if np > 0 then
          finalize_context()
        elseif inspect_retries < 30 then
          inspect_retries = inspect_retries + 1
          reaper.defer(try_inspect_read)
        else
          -- Timed out - clean up and report.
          if reaper.ValidatePtr2(0, fi.tr, "MediaTrack*") then
            reaper.DeleteTrack(fi.tr)
          end
          reaper.PreventUIRefresh(-1)
          reaper.Undo_EndBlock("ReaAssist: fx_inspect (timeout)", 0)
          S._fx_inspect_tmp = nil
          if S._fx_inspect_silent_for_fx_params then
            Log.line("FX_PARAMS",
              "silent auto-inspect timed out (continuing): "
              .. tbl_concat(fi.names, ", "))
          else
            history_content = history_content
              .. "FX INSPECT ERROR: Plugin did not initialise in time ("
              .. tbl_concat(fi.names, ", ") .. "). "
              .. "Try adding the plugin manually first, then use fx_params.\n\n"
          end
          finalize_context()
        end
      end
      reaper.defer(try_inspect_read)
    else
      finalize_context()
    end
    return true
  end

  -- LOOP DETECTION: tag was non-empty (#raw_tokens > 0) but produced no
  -- wants_* -- meaning every requested bucket was either gated by a *_sent
  -- flag or is an unknown name. The model is re-asking for context it
  -- already has (or inventing bucket names). One recovery attempt if a
  -- sticky sent-set was the blocker (clear it + retry with a "use it" hint);
  -- otherwise surface a clean error with recovery buttons instead of
  -- dumping the raw tag as the assistant reply.
  if #raw_tokens > 0 then
    -- "had_sticky" -> the previous turn or earlier in this turn injected
    -- some piece of pinned data, so the model's re-request is plausibly
    -- about that already-pinned data and worth one retry with a hint.
    -- Detection has to cover both the per-name dedup tables and the
    -- one-shot booleans -- the model could be re-asking for a single
    -- bucket (docs, session, midi, theme, fx_*) just as easily as a
    -- named one (plugin_ref:X, prompt_bundle:X, preferred_plugins:X).
    local had_sticky =
         next(S.plugin_ref_sent)
      or next(S.pref_plugins_sent)
      or next(S.prompt_bundle_sent)
      or S.docs_already_sent
      or S.docs_extended_already_sent
      or S.session_already_sent
      or S.fx_params_already_sent
      or S.fx_list_already_sent
      or S.fx_chains_already_sent
      or S.track_flags_already_sent
      or S.midi_already_sent
      or S.theme_already_sent
      or S.fx_inspect_already_sent
    if had_sticky and (S.context_loop_retries or 0) < 1 then
      S.context_loop_retries = (S.context_loop_retries or 0) + 1
      Log.line("CONTEXT_LOOP",
        "model re-requested already-provided context; clearing all sent flags + adding hint")
      -- Clear every gating flag that the per-token elseif chain checks,
      -- so whatever bucket the model re-emitted falls through ungated on
      -- the recursive pass and triggers a fresh fetch + follow-up call
      -- with the "use it" hint. Earlier versions only cleared the per-
      -- name dedup tables (plugin_ref_sent, pref_plugins_sent, eventually
      -- prompt_bundle_sent), which fixed plugin-shaped loops but missed
      -- the simpler one-shot booleans (docs / session / midi / theme /
      -- fx_*). Sonnet 4.6 has been observed re-emitting any of these
      -- under the right conditions, so we now clear the full set.
      S.plugin_ref_sent              = {}
      S.pref_plugins_sent            = {}
      S.prompt_bundle_sent           = {}
      S.docs_already_sent            = false
      S.docs_extended_already_sent   = false
      S.session_already_sent         = false
      S.fx_params_already_sent       = false
      S.fx_list_already_sent         = false
      S.fx_chains_already_sent       = false
      S.track_flags_already_sent     = false
      S.midi_already_sent            = false
      S.theme_already_sent           = false
      S.fx_inspect_already_sent      = false
      S._context_reuse_hint = true
      return Net.process_response_buckets(text)
    else
      Log.line("CONTEXT_LOOP",
        "unresolvable context loop; aborting turn with user error")
      Log.add_error("The model re-requested context that was already provided. "
        .. "Try rephrasing your request, or switch to a different model.",
        nil, nil, "token_limit")
      S.status = "idle"
      return true  -- treat as handled so caller doesn't display the raw tag
    end
  end
  return false
end

-- =============================================================================
-- Net.resolve_popup_resume: resume a turn blocked by the resolve-type popup
-- =============================================================================
-- Called by the popup's action buttons once the user picks a plugin. Synthesizes
-- a <context_needed>plugin_ref:<identifier>> tag and re-enters the dispatcher so
-- the follow-up API call fires with the correct plugin reference injected.
--
-- The caller is responsible for persisting the user's choice to preferred_types
-- if they want the next turn to resolve without a popup (see popup "Use this"
-- button handler).
-- Returns true iff `name` matches a section in the curated plugin_ref cache
-- (after alias resolution). Used by resolve_popup_resume to decide whether
-- to inject the picked plugin via plugin_ref:<identifier> (curated -- has
-- recipes/golden-ratios) or preferred_plugins:<type> (third-party -- live
-- params from the just-saved preference + FX cache scan).
local function _is_in_plugin_ref(name)
  if not name or name == "" then return false end
  -- Trigger lazy-load of the cache if not yet built. CTX.plugin_ref builds
  -- it on first call; the probe arg returns a no-match string but populates
  -- CTX._plugin_ref_cache as a side effect.
  if not CTX._plugin_ref_cache then
    local ok_probe, probe_err = pcall(CTX.plugin_ref, {"__probe__"})
    if not ok_probe then
      Log.line("PLUGIN_REF",
        "plugin_ref probe failed: " .. tostring(probe_err))
    end
  end
  if not CTX._plugin_ref_cache then return false end
  local k = name:lower():match("^%s*(.-)%s*$") or ""
  k = PLUGIN_REF_ALIASES[k] or k
  return CTX._plugin_ref_cache[k] ~= nil
end

function Net.resolve_popup_resume(identifier)
  -- Capture popup type, pending resolves, and any wants_* state stashed by a
  -- popup-bailed parse loop BEFORE clearing state. The popup may already
  -- have been cleared by the typed-pick handler (which clears it early so
  -- the chat status doesn't keep saying "Waiting for selection..." through
  -- a slow scan); in that case we read the type from S.resolve_pending_type
  -- which the typed-pick handler stashed for exactly this purpose.
  local resolve_type    = (S.resolve_popup and S.resolve_popup.type)
                       or S.resolve_pending_type
                       or nil
  S.resolve_pending_type = nil
  local pending         = S.pending_resolves or {}
  local pending_pr      = S.pending_plugin_ref_names or {}
  local pending_pp      = S.pending_pref_plugin_types or {}
  S.pending_resolves          = {}
  S.pending_plugin_ref_names  = {}
  S.pending_pref_plugin_types = {}

  -- Clear popup state. pending_orig_prompt / pending_snapshot / pending_display_idx
  -- stay intact -- the dispatcher re-enters finalize_context which uses them.
  S.resolve_popup        = nil
  S.resolve_popup_text   = ""
  S.resolve_popup_error  = nil
  S.resolve_popup_matches     = {}
  S.resolve_popup_sel         = 0
  S.resolve_popup_last_filter = nil
  S.resolve_popup_refocus     = false
  S.status               = "waiting"
  -- Clear the per-name sent set so the synthesized plugin_ref actually injects
  -- (a previous turn in this session may have sent plugin_ref for other names).
  S.plugin_ref_sent = {}

  -- Build the synthesized tag. For the picked plugin:
  --   * Curated (in plugin_ref.md, e.g. ReaEQ/ReaComp/ReEQ) -> plugin_ref:<id>
  --     gives the model recipes + verified normalized values.
  --   * Third-party (e.g. VST3: Pro-C 3) -> preferred_plugins:<type>
  --     surfaces live params from the just-completed FX cache scan. Falling
  --     back to plugin_ref here would inject "no reference data for: <id>" --
  --     a useless placeholder that wastes a round-trip.
  -- Then append any resolve:<type> tokens that were dropped when this popup
  -- bailed the parser loop, so the model gets all originally-requested data
  -- without having to re-emit them itself.
  local synth = {}
  -- 1) Any wants_* state that was lost when an earlier popup bailed the loop.
  -- Re-emit as explicit buckets so the data the user already picked is
  -- restored without another popup.
  for _, n in ipairs(pending_pr) do
    synth[#synth+1] = "plugin_ref:" .. n
  end
  for _, t in ipairs(pending_pp) do
    synth[#synth+1] = "preferred_plugins:" .. t
  end
  -- 2) The bucket for the plugin the user just picked in THIS popup.
  if resolve_type and not _is_in_plugin_ref(identifier) then
    synth[#synth+1] = "preferred_plugins:" .. resolve_type
  else
    synth[#synth+1] = "plugin_ref:" .. identifier
  end
  -- 3) Any resolve:Type tokens that were dropped when this popup bailed the
  -- loop. They go LAST so any popup they trigger re-stashes (1) and (2)'s
  -- buckets correctly via the bail-stash code in the resolve branch.
  for _, ptype in ipairs(pending) do
    synth[#synth+1] = "resolve:" .. ptype
  end

  local fake_text = "<context_needed>" .. tbl_concat(synth, ", ") .. "</context_needed>"
  local fired = Net.process_response_buckets(fake_text)
  if not fired then
    -- Dispatcher didn't fire the follow-up. Safety net: drop back to idle
    -- so the user isn't stuck watching "waiting" forever.
    Log.line("RESOLVE", "resume: dispatcher didn't fire for " .. identifier
      .. " -- aborting turn")
    S.status = "idle"
    Log.add_error("Couldn't resume the request after your selection. "
      .. "Please try sending the message again.")
  end
end

-- =============================================================================
-- Called by the main loop (throttled to CFG.POLL_THROTTLE) while waiting for
-- a curl response. Handles in order:
--   1. Watchdog timeout: fires an error if the per-provider timeout is exceeded.
--   2. Exit code file: detects curl network errors (codes 6, 7, 28, 35, 60).
--   3. Partial-read guard: waits for closing brace before parsing.
--   4. JSON decode and API error envelope detection (auth, rate-limit, overload).
--   5. Auto-retry on 529 (overloaded_error) with exponential backoff (2s, 4s, 8s).
--   6. <context_needed> detection: injects requested buckets and fires a follow-up.
--   7. Normal final response: updates display, S.history, token counters, and cost.
-- Watchdog timeout check. Returns true if the request has exceeded the
-- per-provider poll timeout and the timeout has been surfaced to the user
-- (via tier-test abort, key-test abort, or chat error). Caller should
-- return immediately on true.
--
-- Must stay above the curl --max-time set in Net.fire_curl so curl gets the
-- chance to write its exit code before the watchdog fires. Custom providers
-- use their user-configured request_timeout + 15s slack.
function Net._handle_watchdog_timeout()
  local p_active = PROVIDERS.active()
  local poll_timeout = (p_active.is_custom
    and ((tonumber(p_active.request_timeout) or 600) + 15))
    or (prefs.cloud_request_timeout or CFG.CLOUD_TIMEOUT_DEFAULT)
  if not S.send_time or (time_precise() - S.send_time) <= poll_timeout then
    return false
  end
  S.curl_pid  = nil
  S.send_time = nil
  if S.gemini_tier_pending then
    -- Tier test timed out - assume free to be safe.
    S.gemini_tier_pending = false
    S.gemini_paid_tier = false
    reaper.SetExtState(CFG.EXT_NS, "gemini_paid_tier", "false", true)
    if PROVIDERS.active().id == "google" then MODELS.refresh() end
    return true
  end
  if S.key_test_pending then
    local test_prov_id = S.key_test_provider
    S.key_test_pending  = false
    S.key_test_provider = nil
    S.status = "error"
    if api_keys.custom_conn_test and api_keys.custom_conn_test.active
       and api_keys.screen == "custom_llm" then
      CTX.custom_conn_test_advance(false, "Timed out waiting for response.")
      return true
    end
    if #api_keys.test_queue > 0 and (api_keys.screen == "first_run" or api_keys.screen == "settings") and test_prov_id then
      Net.advance_key_test_queue(test_prov_id, false,
        "The server took too long to respond.")
      return true
    end
    -- Append rather than clobber: preserves chat history if the key test
    -- somehow fires while a conversation is on screen.
    Log.add_error(
      "The server took too long to respond while checking your key. "
        .. "Your key is stored for this session but has not been permanently "
        .. "saved yet. Try sending a message to test it. Once verified, "
        .. "it will be saved automatically."
        .. "\n\nIf that doesn't work, click the Settings button to re-enter your key.")
    return true
  end
  if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
    S.display_messages[S.pending_display_idx].ctx_label = "timeout"
  end
  Log.add_error(
    "The request timed out. The server may be busy, or your internet "
    .. "connection may have dropped.\n\n"
    .. "Try sending your message again.")
  return true
end

-- Check curl's exit-code tmp file. Returns true if curl exited with a
-- non-zero code and the network error has been surfaced (tier abort, key-test
-- abort, or chat error). Caller should return on true. Exit code 0 sets
-- S.curl_exited_clean so the partial-read brace guard is bypassed, and
-- returns false so the caller continues parsing.
function Net._handle_curl_exit_failure()
  local ok_ef, ef = pcall(io.open, tmp.exit, "r")
  if not (ok_ef and ef) then return false end
  local exit_str = ef:read("*a"); ef:close()
  local exit_code = tonumber(exit_str:match("(%d+)"))
  if not exit_code then return false end
  if exit_code == 0 then
    -- curl finished cleanly. Bypass the partial-read brace guard so non-JSON
    -- responses (captive portals, proxy HTML) surface as a clear error
    -- instead of looping until the watchdog fires.
    S.curl_exited_clean = true
    os.remove(tmp.exit)
    return false
  end
  S.curl_pid  = nil
  S.send_time = nil
  os.remove(tmp.exit)
  local prov_label = PROVIDERS.active().label
  local curl_errors = {
    [6]  = "Can't reach the " .. prov_label .. " servers. Please check your "
           .. "internet connection and try again.",
    [7]  = "The server refused the connection. It may be temporarily "
           .. "down. Try again in a few minutes.",
    [28] = "The connection timed out. Please check your internet "
           .. "connection and try again.",
    [35] = "Couldn't establish a secure connection. A firewall or "
           .. "network setting may be blocking it.",
    [60] = "There's an issue with the server's security certificate. "
           .. "Please check that your computer's date and time are correct.",
  }
  local detail = curl_errors[exit_code]
    or "A network error occurred. Please check your internet "
       .. "connection and try again."
  if S.gemini_tier_pending then
    S.gemini_tier_pending = false
    S.gemini_paid_tier = false
    reaper.SetExtState(CFG.EXT_NS, "gemini_paid_tier", "false", true)
    if PROVIDERS.active().id == "google" then MODELS.refresh() end
    return true
  end
  if S.key_test_pending then
    local test_prov_id = S.key_test_provider
    local test_prov    = test_prov_id and PROVIDERS.get(test_prov_id) or nil
    local was_custom   = test_prov and test_prov.is_custom or false
    S.key_test_pending  = false
    S.key_test_provider = nil
    S.status = "error"
    if api_keys.custom_conn_test and api_keys.custom_conn_test.active
       and api_keys.screen == "custom_llm" then
      CTX.custom_conn_test_advance(false, detail)
      return true
    end
    if #api_keys.test_queue > 0 and (api_keys.screen == "first_run" or api_keys.screen == "settings") and test_prov_id then
      Net.advance_key_test_queue(test_prov_id, false, detail)
      return true
    end
    -- On the API key entry screen, surface the error inline (popup) instead
    -- of dumping it into the chat -- the user hasn't left the screen so a
    -- chat message would be invisible. Custom LLM path almost always lands
    -- here when a port is mistyped, so this is the common case.
    if (api_keys.screen == "first_run" or api_keys.screen == "settings") then
      api_keys.key_validating     = false
      api_keys.key_validating_idx = nil
      local key_prov_label = (test_prov and test_prov.label)
        or (was_custom and "Custom LLM")
        or "the provider"
      if not was_custom then
        api_keys.key_error = detail
      end
      api_keys.show_key_error_popup = true
      api_keys.key_error_provider   = key_prov_label
      api_keys.key_error_detail     = detail
      api_keys.key_error_hint       = was_custom
        and "Check that the server is running and the URL/port is correct."
        or "Check your internet connection and try again."
      api_keys.key_error_url        = nil
      api_keys.key_error_url_label  = nil
      return true
    end
    -- Append rather than clobber (see timeout branch above).
    Log.add_error(detail .. "\n\n"
      .. "Once you're back online, click the Settings button to try again.")
    return true
  end
  if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
    S.display_messages[S.pending_display_idx].ctx_label = "network error"
  end
  Log.add_error(detail)
  return true
end

-- JSON decode failed. Log raw body, tag the display entry, and show an
-- error. If the response looks like HTML, surface the proxy/captive-portal
-- explanation instead of a generic "unreadable JSON" message.
function Net._handle_json_decode_error(raw, decode_err)
  Code.safe_write(tmp.log, raw)
  if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
    S.display_messages[S.pending_display_idx].ctx_label = "error"
  end
  local raw_head = raw:sub(1, 256):lower()
  local looks_html = raw_head:find("<!doctype", 1, true)
                  or raw_head:find("<html",     1, true)
                  or raw_head:find("<head",     1, true)
                  or raw_head:find("502 bad",   1, true)
                  or raw_head:find("503 ",      1, true)
                  or raw_head:find("504 ",      1, true)
  if looks_html then
    Log.add_error(
      "The server returned an HTML page instead of a JSON response. This "
      .. "usually means a proxy, firewall, or captive portal (hotel/coffee "
      .. "shop Wi-Fi) is intercepting the request, or the API endpoint is "
      .. "temporarily down behind a 5xx gateway error.\n\n"
      .. "Try a different network, disable any VPN/proxy, or wait a few "
      .. "minutes and retry.")
  else
    Log.add_error(
      "Got an unreadable response from the server. This is usually "
      .. "a temporary glitch."
      .. (decode_err and ("\n\nTechnical detail: " .. decode_err) or "")
      .. "\n\nPlease try again.")
  end
end

-- Unified API error handler used by all providers. Maps error types to
-- user-facing messages; provider-specific billing/console links are pulled
-- from the `p` provider record so the same handler works for all three.
--
-- inner_type: provider-specific error code string (e.g. "rate_limit_error",
--   "insufficient_quota", "RESOURCE_EXHAUSTED"). is_overloaded triggers the
--   exponential-backoff auto-retry (up to CFG.MAX_RETRIES). is_auth wipes
--   the stored key and prompts re-entry.
function Net._handle_api_error(p, inner_type, api_err, is_overloaded, is_auth)
  -- Auto-retry on overload (Anthropic 529, or provider-specific equivalents).
  if is_overloaded and S.retry_count < CFG.MAX_RETRIES then
    S.retry_count = S.retry_count + 1
    local delay = CFG.RETRY_DELAY_BASE * (2 ^ (S.retry_count - 1))
    S.retry_scheduled = true
    S.retry_fire_time = time_precise() + delay
    S.status = "waiting"
    if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
      S.display_messages[S.pending_display_idx].ctx_label =
        str_format("retrying in %ds (%d/%d)", delay, S.retry_count, CFG.MAX_RETRIES)
    end
    return
  end

  if is_auth then
    S.api_key = nil
    S.api_key_map[p.id] = nil
    Key.clear(p.key_extstate)
    S.status = "error"
    if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
      S.display_messages[S.pending_display_idx].ctx_label = "auth error"
    end
    S.display_messages[#S.display_messages+1] = {
      role    = "assistant",
      content = "Your " .. p.label .. " API key isn't working. It may have expired or been "
        .. "entered incorrectly.\n\n"
        .. "Click the Settings button below to enter a new one.\n\n"
        .. "You can find or create a key here:",
      link_url   = p.console_url,
      link_label = p.console_label,
      storage_note = "Your key is obfuscated and locked to this REAPER install "
        .. "path. It will not work if copied to another machine.",
    }
    S.scroll_to_bottom = true
    return
  end

  -- Error map. Messages that reference provider name or billing URL are
  -- rebuilt with p fields; others are constant but kept together here so
  -- the table stays a single source of truth.
  local error_info = {
    -- Anthropic
    rate_limit_error      = { label = "rate limited",
      msg = "Slow down! You're sending messages too quickly. "
        .. "Wait about 30 seconds and try again.\n\n"
        .. "If this keeps happening, try switching models in the dropdown." },
    credit_balance_error  = { label = "out of credits",
      msg = "Your " .. p.label .. " account has run out of credits."
        .. "\n\nTo continue using ReaAssist, add funds to your account:",
      link_url = p.billing_url, link_label = p.billing_label },
    overloaded_error      = { label = "overloaded",
      msg = "The servers are busy right now. "
        .. "Wait a moment and try again; this usually clears up quickly." },
    invalid_request_error = { label = "invalid request",
      msg = "This conversation has gotten too long for the model to handle."
        .. "\n\nTo fix this:\n- Click Clear to start fresh\n"
        .. "- Try a shorter message\n"
        .. "- Turn off \"Always include REAPER API reference\" or Send snapshot to reduce size" },
    not_found_error       = { label = "model not found",
      msg = "That model doesn't seem to exist anymore. It may have been "
        .. "renamed or retired.\n\nTry picking a different one from the dropdown below." },
    permission_error      = { label = "permission denied",
      msg = "Your API key doesn't have access to this model. This usually "
        .. "means it requires a higher account tier.\n\nTry a different model, "
        .. "or check your plan here:",
      link_url = p.billing_url, link_label = p.billing_label },
    -- OpenAI
    rate_limit_exceeded   = { label = "rate limited",
      msg = "Slow down! You're sending messages too quickly. "
        .. "Wait about 30 seconds and try again." },
    insufficient_quota    = { label = "out of credits",
      msg = "Your " .. p.label .. " account has run out of credits."
        .. "\n\nTo continue using ReaAssist, add funds to your account:",
      link_url = p.billing_url, link_label = p.billing_label },
    model_not_found       = { label = "model not found",
      msg = "That model doesn't seem to exist anymore. It may have been "
        .. "renamed or retired.\n\nTry picking a different one from the dropdown below." },
    -- Google
    RESOURCE_EXHAUSTED    = { label = "rate limited",
      msg = "You've hit a rate limit. Wait a moment and try again." },
    RESOURCE_EXHAUSTED_BILLING = { label = "out of quota",
      msg = "Your Google account has exhausted its Gemini quota."
        .. "\n\nIf you're on the free tier, you may need to enable billing. "
        .. "If you're on a paid plan, add funds or check your usage limits:",
      link_url = p.billing_url, link_label = p.billing_label },
    NOT_FOUND             = { label = "model not found",
      msg = "That model doesn't seem to exist anymore. Try picking a different one." },
    PERMISSION_DENIED     = { label = "permission denied",
      msg = "Your API key doesn't have access to this model.",
      link_url = p.billing_url, link_label = p.billing_label },
  }

  -- Reclassify generic error types into funding errors when the message
  -- mentions credits/quota/billing -- gives the user actionable billing links
  -- instead of a misleading "try again later" or "conversation too long".
  -- Anthropic in particular returns invalid_request_error for both context-
  -- window overflow AND "Your credit balance is too low..."; without this
  -- the credits case shows the context-overflow copy.
  local effective_type = inner_type
  if api_err then
    local lmsg = api_err:lower()
    if inner_type == "rate_limit_error" and lmsg:find("credit") then
      effective_type = "credit_balance_error"
    elseif inner_type == "invalid_request_error"
       and (lmsg:find("credit") or lmsg:find("balance") or lmsg:find("billing")) then
      effective_type = "credit_balance_error"
    elseif inner_type == "rate_limit_exceeded"
       and (lmsg:find("quota") or lmsg:find("billing") or lmsg:find("exceeded your current")) then
      effective_type = "insufficient_quota"
    elseif inner_type == "RESOURCE_EXHAUSTED"
       and (lmsg:find("quota") or lmsg:find("billing") or lmsg:find("limit.*exceed")) then
      effective_type = "RESOURCE_EXHAUSTED_BILLING"
    end
  end

  local info  = error_info[effective_type]
  local label = info and info.label or "api error"
  local msg   = info and info.msg
    or ("Something went wrong. Please try again."
      .. (api_err and ("\n\nDetails: " .. api_err) or ""))
  if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
    S.display_messages[S.pending_display_idx].ctx_label = label
  end
  if api_err and not info then
    msg = msg .. "\n\nDetails: " .. api_err
  end
  Log.add_error(msg, info and info.link_url, info and info.link_label)
end

function Net.try_finish_curl()
  if not S.curl_pid then return end

  if Net._handle_watchdog_timeout() then return end

  if Net._handle_curl_exit_failure() then return end

  -- Read the response file (pcall handles transient AV scanner file locks).
  local ok_f, f = pcall(io.open, tmp.out, "r")
  if not ok_f or not f then return end
  local raw = f:read("*a"); f:close()
  if #raw < 2 then return end  -- truly empty response: wait for content
  -- Partial-read guard: while curl is still running, the body file may be
  -- mid-write. Wait for the closing brace before parsing. Once curl has exited
  -- (curl_exited_clean), the body is complete and we go straight to JSON.decode
  -- so non-JSON responses surface as a clear error instead of looping.
  if not S.curl_exited_clean then
    local last_char = raw:match("(%S)%s*$")
    if last_char ~= "}" then return end
  end

  local elapsed = S.send_time and (time_precise() - S.send_time) or nil
  S.curl_pid  = nil
  S.send_time = nil

  Log.response(raw, elapsed)

  if S.gemini_tier_pending then
    Net.handle_gemini_tier_test(raw)
    return
  end

  if S.key_test_pending then
    Net.handle_key_test(raw)
    return
  end

  local resp, decode_err = JSON.decode(raw)
  if not resp or type(resp) ~= "table" then
    Net._handle_json_decode_error(raw, decode_err)
    return
  end

  -- ==========================================================================
  -- Provider-specific error handling and response extraction.
  -- Each provider has different error envelope formats and response structures.
  -- The dispatch calls a provider-specific handler that either:
  --   (a) handles the error (shows UI feedback) and returns, or
  --   (b) extracts text and tokens and falls through to the common post-parse flow.
  -- Uses the provider/model snapshot from send time, not current UI state,
  -- so a mid-request provider switch doesn't corrupt parsing.
  -- ==========================================================================
  local p = PROVIDERS[S.pending_provider_idx] or PROVIDERS.active()


  -- ---------------------------------------------------------------------------
  -- Provider-specific error detection and response extraction.
  -- Each block either calls Net._handle_api_error + return, or sets text/tokens and
  -- falls through to the common post-parse flow below.
  -- ---------------------------------------------------------------------------
  -- empty_reason carries provider-specific context for the empty-text path so
  -- the post-parse error message can name the actual cause (length cap hit on
  -- reasoning tokens, content filter, refusal) instead of the generic fallback.
  local text, raw_tok_in, raw_tok_out, tok_in_read, tok_in_create
  local empty_reason, refusal_text, reasoning_only_tokens

  if p.id == "anthropic" then
    -- Anthropic error envelope: {"type":"error","error":{"type":"...","message":"..."}}
    if resp.type == "error" and type(resp.error) == "table" and resp.error ~= JSON.NULL then
      local it = resp.error.type
      local em = type(resp.error.message) == "string" and resp.error.message or ""
      -- Beta-header rejection guard. When Anthropic deprecates the
      -- extended-cache-ttl-2025-04-11 beta header, the API starts returning
      -- 400 invalid_request_error referencing the header name or "beta"
      -- + "ttl"/"cache". Strip the header session-wide, fall back to 5-min
      -- ephemeral caching, rebuild the body, and silently retry the same
      -- request so the user never sees the deprecation. Only attempt this
      -- once per session (anthropic_beta_disabled flag) so a genuinely bad
      -- request doesn't loop forever.
      if not S.anthropic_beta_disabled and it == "invalid_request_error" then
        local lm = em:lower()
        local mentions_beta = lm:find("extended-cache-ttl", 1, true)
                           or lm:find("anthropic-beta",     1, true)
                           or (lm:find("beta", 1, true)
                               and (lm:find("ttl", 1, true)
                                    or lm:find("cache_control", 1, true)
                                    or lm:find('"1h"', 1, true)))
        if mentions_beta then
          S.anthropic_beta_disabled = true
          -- Rebuild the body without 1h cache markers and re-fire on the
          -- normal retry timer (no backoff -- this isn't an overload).
          local rebuilt = Net.build_body(
            Net.trimmed_history(),
            S.pending_snapshot,
            S.pending_attachments)
          S.retry_saved_body = rebuilt
          S.retry_scheduled  = true
          S.retry_fire_time  = time_precise()  -- fire next loop tick
          S.status           = "waiting"
          if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
            S.display_messages[S.pending_display_idx].ctx_label = "retrying (5m cache)"
          end
          return
        end
      end
      Net._handle_api_error(p, it, em,
        it == "overloaded_error",
        it == "authentication_error")
      return
    end
    -- Validate structure.
    if resp.type ~= "message" or type(resp.content) ~= "table" then
      Code.safe_write(tmp.log, raw)
      if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
        S.display_messages[S.pending_display_idx].ctx_label = "error"
      end
      Log.add_error("Got an unexpected response from the server. This is likely a "
        .. "temporary issue.\n\nPlease try again.")
      return
    end
    -- Extract text. Also count thinking / redacted_thinking blocks so they
    -- aren't silently dropped if a future build enables extended thinking on
    -- Claude (today thinking_levels=nil for the Claude provider, so this path
    -- only activates if/when that changes -- but the count goes into the log
    -- so we'll know the moment it does, and tool-use turns won't break by
    -- surprise from missing-thinking-block 400s).
    local text_parts = {}
    local thinking_blocks = 0
    for _, block in ipairs(resp.content) do
      if type(block) == "table" then
        if block.type == "text" and type(block.text) == "string" then
          text_parts[#text_parts+1] = block.text
        elseif block.type == "thinking" or block.type == "redacted_thinking" then
          thinking_blocks = thinking_blocks + 1
        end
      end
    end
    if thinking_blocks > 0 then
      Log.line("ANTHROPIC", "received " .. thinking_blocks
        .. " thinking block(s) (not preserved in history; enable a thinking-aware "
        .. "history adapter before using extended thinking with tool use)")
    end
    -- "\n\n" between content blocks rather than a single "\n": a code
    -- fence at the end of one block plus prose at the start of the next
    -- would otherwise concatenate to "```\nLine of prose" and break the
    -- fence. Anthropic almost always returns a single text block today,
    -- but the join cost is identical and the multi-block case is safer.
    text = #text_parts > 0 and tbl_concat(text_parts, "\n\n") or nil
    -- Diagnostic fields for the empty-text branch. Anthropic uses
    --   stop_reason="max_tokens" -> output cap hit
    --   stop_reason="refusal"    -> model declined the request
    if resp.stop_reason == "max_tokens" then
      empty_reason = "length"
    elseif resp.stop_reason == "refusal" then
      empty_reason = "refusal"
    end
    -- Tokens: Anthropic includes cache breakdown.
    local usage     = type(resp.usage) == "table" and resp.usage or {}
    local base      = tonumber(usage.input_tokens)                or 0
    tok_in_create   = tonumber(usage.cache_creation_input_tokens) or 0
    tok_in_read     = tonumber(usage.cache_read_input_tokens)     or 0
    raw_tok_in      = base + tok_in_create + tok_in_read
    raw_tok_out     = tonumber(usage.output_tokens) or 0

  elseif p.id == "openai" or p.is_custom then
    -- OpenAI error envelope: {"error":{"type":"...","message":"...","code":"..."}}
    -- Custom OpenAI-compatible endpoints (Ollama, LM Studio, vLLM, OpenRouter,
    -- etc.) follow the same wire format, so they share this branch.
    if type(resp.error) == "table" and resp.error ~= JSON.NULL then
      local code = resp.error.code or resp.error.type or ""
      local is_auth = (code == "invalid_api_key")
        or (type(resp.error.message) == "string"
            and resp.error.message:lower():find("api key"))
      local is_overloaded = (code == "server_error" or code == "overloaded")
      Net._handle_api_error(p, code, resp.error.message, is_overloaded, is_auth)
      return
    end
    -- Validate structure: {"choices":[{"message":{"content":"..."}}]}
    if type(resp.choices) ~= "table" or #resp.choices == 0
       or type(resp.choices[1].message) ~= "table" then
      Code.safe_write(tmp.log, raw)
      if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
        S.display_messages[S.pending_display_idx].ctx_label = "error"
      end
      Log.add_error("Got an unexpected response from the server. This is likely a "
        .. "temporary issue.\n\nPlease try again.")
      return
    end
    local choice  = resp.choices[1]
    local message = choice.message
    text = message.content
    -- Capture diagnostic fields so the empty-text branch can name the cause:
    --   finish_reason="length"  -> reasoning/output budget exhausted
    --   finish_reason="content_filter" -> safety filter blocked output
    --   message.refusal (string) -> model declined the request
    if type(message.refusal) == "string" and message.refusal ~= "" then
      refusal_text = message.refusal
      empty_reason = "refusal"
    elseif choice.finish_reason == "length" then
      empty_reason = "length"
    elseif choice.finish_reason == "content_filter" then
      empty_reason = "content_filter"
    end
    -- Tokens: OpenAI usage. prompt_tokens is the TOTAL input (including cached),
    -- and prompt_tokens_details.cached_tokens is the portion served from the
    -- automatic prefix cache (billed at 10% of regular input). OpenAI's caching
    -- has no separate cache-write fee, so tok_in_create stays 0.
    local usage   = type(resp.usage) == "table" and resp.usage or {}
    raw_tok_in    = tonumber(usage.prompt_tokens)     or 0
    raw_tok_out   = tonumber(usage.completion_tokens) or 0
    local details = type(usage.prompt_tokens_details) == "table"
                    and usage.prompt_tokens_details or {}
    tok_in_read   = tonumber(details.cached_tokens) or 0
    tok_in_create = 0
    -- Reasoning-token count for the length-cap error path. Lets the user see
    -- exactly how much of the cap went to internal reasoning vs visible output.
    local cdet    = type(usage.completion_tokens_details) == "table"
                    and usage.completion_tokens_details or {}
    reasoning_only_tokens = tonumber(cdet.reasoning_tokens) or 0

  elseif p.id == "google" then
    -- Gemini error envelope: {"error":{"code":N,"message":"...","status":"..."}}
    if type(resp.error) == "table" and resp.error ~= JSON.NULL then
      local status = resp.error.status or ""
      local code   = resp.error.code or 0
      local msg    = resp.error.message or ""
      local is_auth = (status == "UNAUTHENTICATED" or code == 401)
      local is_overloaded = (code == 503 or status == "UNAVAILABLE")
      -- Cache miss: the cachedContent we referenced no longer exists server-
      -- side (TTL expired, or deleted out-of-band). Drop local cache state
      -- so the next send rebuilds without the stale reference. We don't
      -- auto-retry here because reconstructing the body would require
      -- re-plumbing attachments; a manual resend costs one click and is rare.
      local cache_miss = S.gemini_cache_name
        and (code == 404 or status == "NOT_FOUND"
             or (msg:find("[Cc]ached") and msg:find("[Nn]ot found")))
      if cache_miss then
        Net.gemini_cache_invalidate()
        if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
          S.display_messages[S.pending_display_idx].ctx_label = "cache expired"
        end
        Log.add_error(
          "The Gemini context cache expired between sends. "
          .. "Please send your message again; a fresh cache will be "
          .. "created automatically.")
        S.status = "error"
        return
      end
      -- Fallback free tier detection: 403/429 on a paid_only model.
      local cur_model = p.models[prefs.model_idx] or MODELS[prefs.model_idx]
      if (code == 403 or code == 429 or status == "PERMISSION_DENIED"
          or status == "RESOURCE_EXHAUSTED") and cur_model and cur_model.paid_only then
        S.gemini_paid_tier = false
        reaper.SetExtState(CFG.EXT_NS, "gemini_paid_tier", "false", true)
        MODELS.refresh()
        if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
          S.display_messages[S.pending_display_idx].ctx_label = "api error"
        end
        Log.add_error("Gemini Pro requires a paid Google account. "
          .. "Your account appears to be on the free tier.\n\n"
          .. "The model has been switched to Flash Lite. "
          .. "To use Pro, enable billing at aistudio.google.com/apikey.")
        return
      end
      Net._handle_api_error(p, status, resp.error.message, is_overloaded, is_auth)
      return
    end
    -- Validate structure: {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}
    -- Note: when finishReason is MAX_TOKENS/SAFETY/RECITATION, the candidate
    -- may be present without a `content` block, so we treat that as the
    -- empty-text case (with an explanatory empty_reason) rather than as a
    -- malformed response.
    if type(resp.candidates) ~= "table" or #resp.candidates == 0 then
      Code.safe_write(tmp.log, raw)
      if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
        S.display_messages[S.pending_display_idx].ctx_label = "error"
      end
      Log.add_error("Got an unexpected response from the server. This is likely a "
        .. "temporary issue.\n\nPlease try again.")
      return
    end
    local cand    = resp.candidates[1]
    local content = type(cand.content) == "table" and cand.content or nil
    -- Extract text from all parts (if a content block exists at all).
    if content and type(content.parts) == "table" then
      local text_parts = {}
      for _, part in ipairs(content.parts) do
        if type(part) == "table" and type(part.text) == "string" then
          text_parts[#text_parts+1] = part.text
        end
      end
      text = #text_parts > 0 and tbl_concat(text_parts, "\n") or nil
    end
    -- Diagnostic fields for the empty-text branch.
    if cand.finishReason == "MAX_TOKENS" then
      empty_reason = "length"
    elseif cand.finishReason == "SAFETY" or cand.finishReason == "RECITATION" then
      empty_reason = "content_filter"
    end
    -- Tokens: Gemini usageMetadata. promptTokenCount is the TOTAL input
    -- (including cached), and cachedContentTokenCount is the portion served
    -- from an explicit context cache (billed at a discounted rate).
    local usage   = type(resp.usageMetadata) == "table" and resp.usageMetadata or {}
    raw_tok_in    = tonumber(usage.promptTokenCount)     or 0
    raw_tok_out   = tonumber(usage.candidatesTokenCount) or 0
    tok_in_read   = tonumber(usage.cachedContentTokenCount) or 0
    tok_in_create = 0  -- Gemini has no per-turn cache-create token cost
    -- Gemini reports thinking tokens separately in thoughtsTokenCount.
    reasoning_only_tokens = tonumber(usage.thoughtsTokenCount) or 0
  end

  -- Common post-parse: clean up text.
  if text then
    text = text:gsub("\n\n\n+", "\n\n")
    -- Collapse double-newlines between consecutive list items to single newlines.
    text = text:gsub("(\n[%*%-][^\n]*)\n\n([%*%-])", "%1\n%2")
    text = text:match("^(.-)%s*$") or ""
  end

  if not text or text == "" then
    Code.safe_write(tmp.log, raw)

    -- Credit the failed call's tokens to the session totals. The user paid
    -- real money for the reasoning that produced no output, and hiding it
    -- from the running cost display would be misleading. We mirror the
    -- success path's accounting so the dollar figure matches the bill.
    -- Compute cost once; used for both session total and per-message stamp.
    local fail_cost = nil
    if (raw_tok_in or 0) > 0 or (raw_tok_out or 0) > 0 then
      S.session_tok_in  = S.session_tok_in  + (raw_tok_in  or 0)
      S.session_tok_out = S.session_tok_out + (raw_tok_out or 0)
      local mi = S.pending_model_idx or prefs.model_idx
      local mentry = MODELS[mi] or MODELS[1]
      if mentry then
        local base = (raw_tok_in or 0) - (tok_in_read or 0) - (tok_in_create or 0)
        fail_cost = MODELS.calc_cost(mentry, base, tok_in_read or 0, tok_in_create or 0, raw_tok_out or 0)
        S.session_cost = S.session_cost + fail_cost
      end
    end

    -- Pick a precise label and message based on what the parser captured.
    -- recovery_kind = "token_limit" tells Log.add_error to render inline
    -- bump/lower buttons so the user can fix the cause in one click.
    local label, msg, recovery_kind
    if empty_reason == "length" then
      label = "out of tokens"
      recovery_kind = "token_limit"
      local detail = ""
      if reasoning_only_tokens and reasoning_only_tokens > 0 then
        detail = str_format(
          " (%d of %d output tokens went to internal reasoning)",
          reasoning_only_tokens, raw_tok_out or 0)
      end
      local has_thinking = PROVIDERS.active().thinking_levels and prefs.thinking_idx > 0
      msg = "The model hit its output token limit before producing any "
        .. "visible response" .. detail .. ".\n"
        .. (has_thinking
          and "Try lowering the Thinking level or increasing the Max Output Tokens on the Settings page."
          or  "Try increasing the Max Output Tokens on the Settings page, or rephrase your message.")
    elseif empty_reason == "content_filter" then
      label = "filtered"
      msg = "The provider's safety filter blocked the response.\n\n"
        .. "Try rephrasing your message."
    elseif empty_reason == "refusal" then
      label = "refused"
      msg = "The model declined to answer this request."
        .. (refusal_text and ("\n\nDetails: " .. refusal_text) or "")
    else
      label = "error"
      recovery_kind = "token_limit"
      local has_thinking2 = PROVIDERS.active().thinking_levels and prefs.thinking_idx > 0
      msg = "The model's response was empty after processing. This can happen when "
        .. "the model uses all its output for internal reasoning.\n"
        .. (has_thinking2
          and "Try lowering the Thinking level or increasing the Max Output Tokens on the Settings page."
          or  "Try increasing the Max Output Tokens on the Settings page, or switching to a different model.")
    end

    if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
      local dmsg = S.display_messages[S.pending_display_idx]
      dmsg.ctx_label = label
      -- Write token info so the user can see what they were billed for.
      if (raw_tok_in or 0) > 0 or (raw_tok_out or 0) > 0 then
        dmsg.tok_in           = raw_tok_in  or 0
        dmsg.tok_out          = raw_tok_out or 0
        dmsg.tok_cache_read   = tok_in_read or 0
        dmsg.tok_cache_create = tok_in_create or 0
        dmsg.cost             = fail_cost
      end
      if S.request_start_time then
        dmsg.response_time = reaper.time_precise() - S.request_start_time
      end
    end
    -- request_start_time is cleared at end-of-turn (status -> idle), not
    -- here. The empty-text branch returns straight to idle below via
    -- Log.add_error so the next send_to_api overwrites it anyway, but
    -- keeping it set in the meantime keeps the in-flight timer logic
    -- consistent with the other early-return paths.
    S.request_start_time = nil
    Log.add_error(msg, nil, nil, recovery_kind)
    return
  end

  -- Dispatch any <context_needed> request to the bucket handler. Returns true
  -- if a follow-up was fired (we bail and wait for the next poll tick).
  if Net.process_response_buckets(text) then return end

  -- Strip any leftover <context_needed> tag. Reaches here only when the
  -- bucket handler returned false (no follow-up fired), which now also
  -- includes the mixed-output case where the model emitted both the tag and
  -- substantive prose. The tag is then noise in the visible reply -- pull it
  -- out (and any trailing whitespace it leaves behind) so the user sees the
  -- prose cleanly.
  text = text:gsub("<context_needed>.-</context_needed>%s*", "")
  text = text:match("^%s*(.-)%s*$") or ""

  -- Normal final response: update token counters, build display entry, extract code.

  -- Ensure ctx_label is set on the user display entry.
  if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
    local dmsg = S.display_messages[S.pending_display_idx]
    if not dmsg.ctx_label then dmsg.ctx_label = prefs.include_snapshot and "snapshot" or "" end
    if raw_tok_in > 0 or raw_tok_out > 0 then
      dmsg.tok_in           = raw_tok_in
      dmsg.tok_out          = raw_tok_out
      dmsg.tok_cache_read   = tok_in_read
      dmsg.tok_cache_create = tok_in_create
      S.session_tok_in        = S.session_tok_in  + dmsg.tok_in
      S.session_tok_out       = S.session_tok_out + dmsg.tok_out
      -- Cost estimation: look up model entry from the provider/model indices
      -- that were snapshotted at send time, with a fallback linear search.
      local tok_in_base = raw_tok_in - tok_in_read - tok_in_create
      local mentry = nil
      local pi = S.pending_provider_idx or prefs.provider_idx
      local mi = S.pending_model_idx or prefs.model_idx
      local prov = PROVIDERS[pi]
      if prov and prov.models[mi] then
        mentry = prov.models[mi]
      end
      if not mentry then
        mentry = MODELS[mi] or MODELS[1]
      end
      dmsg.cost = MODELS.calc_cost(mentry, tok_in_base, tok_in_read, tok_in_create, raw_tok_out)
      -- Gemini Free Tier stamp: every request on the free API tier costs
      -- the user nothing, but the token-math estimate reflects the paid
      -- per-million rates. Record the free-tier context on the message so
      -- downstream renderers (chat details, debug log) can frame the cost
      -- as "would have been ~$X" instead of misleading the user into
      -- thinking they're being billed.
      if prov and prov.id == "google" and S.gemini_paid_tier == false then
        dmsg.free_tier = true
      end
      -- Session total skips free-tier exchanges. Otherwise the session
      -- counter in the footer would climb as if the user were paying,
      -- undermining the "free tier" label everywhere else in the UI.
      if not dmsg.free_tier then
        S.session_cost = S.session_cost + dmsg.cost
      end
    end
    if S.request_start_time then
      dmsg.response_time = reaper.time_precise() - S.request_start_time
      -- DO NOT nil request_start_time here. The docs-gate auto-retry below
      -- (at line ~15806) re-fires a curl after this cleanup runs, and the
      -- in-flight "Thinking..." timer reads request_start_time to stay
      -- ticking across the silent retry. Nil-ing here would freeze the
      -- timer at 0:00 for the duration of the retry. The actual clear
      -- happens at end-of-turn (status -> idle) at the bottom of
      -- Net.process_response, after the docs-gate decision is made.
    end
    if S._fx_cache_events then
      local parts = {}
      local order = { "hit", "cached" }
      local labels = { hit = "Hit", cached = "Cached" }
      for _, key in ipairs(order) do
        local names = S._fx_cache_events[key]
        if names and #names > 0 then
          parts[#parts+1] = labels[key] .. " (" .. tbl_concat(names, ", ") .. ")"
        end
      end
      if #parts > 0 then
        dmsg.fx_cache_label = tbl_concat(parts, ", ")
      end
    end
    -- Mirror the details bubble into the debug log so users sharing the log
    -- see the same per-exchange metadata (cost, tokens, FX cache) as the UI.
    Log.exchange_summary(dmsg)
  end
  S._fx_cache_events = nil
  S.pending_display_idx = nil

  -- Before appending the assistant turn, strip any bucket content that was
  -- baked into the user history entry during mid-turn context fetches.
  -- Sticky data (plugin_ref / pref_plugins / fx_params / fx_inspect) lives
  -- in S.sticky_context and is emitted as a pinned prefix slot by
  -- build_body_*, so keeping it in history would duplicate those bytes on
  -- every subsequent turn's cache breakpoint. Restoring history[last] to
  -- just "USER REQUEST: <text>" keeps the moving cache prefix lean.
  if S.pending_orig_prompt
     and #S.history > 0
     and S.history[#S.history].role == "user" then
    S.history[#S.history].content = "USER REQUEST:\n" .. S.pending_orig_prompt
  end

  -- Store assistant turn in history.
  S.history[#S.history+1] = { role = "assistant", content = text }

  -- Extract fenced code blocks.
  -- A response may contain both a JSFX block and a Lua block (e.g. "create this
  -- effect and add it to track 5"). Extract them separately so JSFX can be
  -- auto-saved and the Lua companion script can be auto-run.
  local explanation = text

  -- 1. Extract JSFX blocks (```jsfx or ```eel fences).
  local jsfx_parts = {}
  for block in text:gmatch("```jsfx%s*\n(.-)\n%s*```") do
    jsfx_parts[#jsfx_parts+1] = block
  end
  if #jsfx_parts == 0 then
    for block in text:gmatch("```eel%s*\n(.-)\n%s*```") do
      jsfx_parts[#jsfx_parts+1] = block
    end
  end
  local jsfx_code = #jsfx_parts > 0 and tbl_concat(jsfx_parts, "\n\n") or nil

  -- 2. Extract Lua blocks (```lua or ```reascript fences).
  local lua_parts = {}
  for block in text:gmatch("```lua%s*\n(.-)\n%s*```") do
    lua_parts[#lua_parts+1] = block
  end
  if #lua_parts == 0 then
    for block in text:gmatch("```reascript%s*\n(.-)\n%s*```") do
      lua_parts[#lua_parts+1] = block
    end
  end
  local lua_code = #lua_parts > 0 and tbl_concat(lua_parts, "\n\n") or nil

  -- Preflight: does the extracted lua_code actually parse as Lua?
  -- Empty-env load() does a pure syntax check (the env is only touched
  -- at execution time, not during compilation). If it fails, the fence
  -- was either mis-tagged by the model (e.g. ```lua wrapping prose /
  -- pseudo-code / a rule list) or contains a genuine syntax error that
  -- would fail at runtime anyway. Either way, it should not reach the
  -- Run button, the Save-as-.lua button, the auto-run path, or the
  -- JSFX-companion slot. Dropping lua_code here lets the raw fence
  -- fall through to the explanation text so the user still SEES what
  -- the model wrote; they just can't execute it. Complements the
  -- fence-label filter above: that stops correctly-labeled ```text
  -- fences from being mis-extracted, this stops ```lua-labeled blocks
  -- that aren't actually Lua from being mis-executed.
  if lua_code then
    local _chunk, parse_err = load(lua_code, "preflight", "t", {})
    if not _chunk then
      Log.line("EXTRACT",
        "```lua block did not parse; dropping from extraction. err="
        .. tostring(parse_err))
      lua_code = nil
    end
  end

  -- If we have both JSFX and Lua, the display code block shows the JSFX
  -- (the Lua companion is a small helper that runs silently).
  local code, code_type
  if jsfx_code then
    code = jsfx_code
    code_type = "jsfx"
  elseif lua_code then
    code = lua_code
    code_type = "lua"
  end

  -- No unlabeled-fence fallback. Previously we extracted ANY ```<lang>
  -- fence as code and tagged it "lua" unless its first line was "desc:",
  -- which meant the model could return ```text (explanatory / pasteable
  -- rule text, per the system-prompt "Use ```text for non-runnable code"
  -- guidance) and we'd dutifully try to execute it as Lua -- producing
  -- "syntax error near 'safety'" and similar compile errors. Any response
  -- that wants to deliver runnable code MUST fence it as lua / reascript /
  -- jsfx / eel. Other fence labels are treated as illustration and stay
  -- in the explanation text.

  -- Strip all fences and unparsed context_needed tags from the explanation text.
  if code then
    explanation = text
      :gsub("```%w*%s*\n.-\n%s*```", "")
      :gsub("\n\n\n+", "\n\n")
      :match("^%s*(.-)%s*$")
  end
  explanation = explanation
    :gsub("<context_needed>.-</context_needed>%s*", "")
    :gsub("\n\n\n+", "\n\n")
    :match("^%s*(.-)%s*$")

  -- If explanation AND code are both empty after stripping (e.g. model replied
  -- with only a <context_needed> tag whose buckets were already sent), surface
  -- an error instead of a blank bubble.
  if (not explanation or explanation == "") and not code then
    Code.safe_write(tmp.log, raw)
    if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
      S.display_messages[S.pending_display_idx].ctx_label = "error"
    end
    Log.add_error(
      "The model's response was empty after processing. This can happen "
      .. "when the model uses all its output for internal reasoning.\n\n"
      .. "Try lowering the Thinking level or increasing the Max Output "
      .. "Tokens on the Settings page.")
    return
  end

  -- Docs gate: if the model emitted reaper.* code without the API reference
  -- ever being provided this session (via the "Always include API ref" pref,
  -- which populates S.api_ref_message, or a prior
  -- <context_needed>docs</context_needed> request, which inlines docs into
  -- history and flips S.docs_fetched_session), the function signatures are
  -- almost certainly guessed.
  --
  -- Recovery strategy: silently force-fetch docs and re-fire the same user
  -- prompt, exactly as if the model had emitted <context_needed>docs
  -- </context_needed> itself. The user never sees the bad response;
  -- instead they see a "docs" bucket appear in the Show Details chip and
  -- the (correct) regenerated reply lands on the next round-trip. This
  -- matches the existing context-bucket recovery flow in
  -- Net.process_response_buckets so the control flow is familiar.
  --
  -- Known failure mode on weaker models like Kimi k2.6: silently guess at
  -- reaper.* calls instead of asking for docs, then fabricate an excuse
  -- ("docs are pre-pinned in your preferences") when questioned. Auto-
  -- retry fixes it without the user having to notice or intervene.
  --
  -- Detection: bare `reaper.<ident>` anywhere in lua_code. JSFX code uses
  -- EEL2 syntax (no reaper.* namespace) so jsfx_code is exempt.
  --
  -- Fallback: if CTX.docs() itself fails (disk read error, missing file),
  -- fall back to the old behaviour -- block auto-run and surface a visible
  -- error so the user can investigate. Flag docs_gate_hit for chat-bubble
  -- banner rendering on that fallback path.
  local docs_gate_hit = false
  local docs_available = S.api_ref_message ~= nil or S.docs_fetched_session
  if lua_code and not docs_available
     and lua_code:find("reaper%.[%w_]") then
    local ref_content, ref_err = CTX.docs()
    if ref_content then
      Log.line("DOCS-GATE",
        "reaper.* calls detected with no docs available; auto-fetching "
        .. "docs, pinning for the rest of session, retrying (user-invisible)")
      S.docs_already_sent    = true
      S.docs_fetched_session = true
      -- Promote the fetched docs from a one-shot history inline into the
      -- persistent pinned-ref slot. From this send forward, every build
      -- includes docs in the PINNED REFERENCES manifest -- the model sees
      -- `docs` listed and complies on subsequent turns without triggering
      -- the gate again. Calibrates automatically per model: compliant
      -- models (Gemini, Claude) never trigger this; models that bias to
      -- action on "obvious" reaper.* calls (Kimi k2.6) take one retry
      -- hit per session, then get docs pinned permanently. Costs one
      -- round-trip once; saves it on every subsequent turn.
      S.api_ref_message = ref_content

      -- Build the replacement user history content: docs + a short,
      -- model-only nudge + the original user prompt. The nudge is
      -- phrased so the model treats this as its FIRST attempt from the
      -- user's perspective -- no meta-commentary about a retry, no
      -- apology, no mention that docs was previously missing. The user
      -- never saw the bad reply and shouldn't be confused by a reply
      -- that explains the invisible recovery.
      local history_content = ref_content .. "\n\n"
        .. "(INTERNAL NOTE TO THE MODEL -- DO NOT MENTION ANY OF THIS IN "
        .. "YOUR VISIBLE REPLY: Your previous reply wrote reaper.* calls "
        .. "without first requesting <context_needed>docs</context_needed>. "
        .. "The API reference is now pinned above. Regenerate the code "
        .. "using the documented function signatures. "
        .. "Respond as if this is your FIRST reply to the user's request. "
        .. "Do NOT apologize, do NOT say 'let me try again' or 'on second "
        .. "thought', do NOT mention that docs was missing, do NOT mention "
        .. "a retry, do NOT re-emit a <context_needed>docs</context_needed> "
        .. "tag. Just deliver the correct code with a normal brief "
        .. "description, as if you had gotten it right on the first try.)\n\n"
        .. "USER REQUEST:\n" .. (S.pending_orig_prompt or "")

      -- Scrub the bad turn from history before firing the retry. By the
      -- time the gate runs, the response handler has already appended
      -- the assistant entry, so S.history tail is:
      --    [..., user_original, assistant_bad]
      -- We pop BOTH so the retry sees a clean prefix, then append the
      -- enriched user message. Without popping the assistant, the retry
      -- body carries the guessed code as a prior assistant turn, which
      -- (a) poisons prefix caching across retries and (b) fights the
      -- "respond as if this is your first reply" nudge by leaving an
      -- earlier reply visible in history.
      if #S.history > 0 and S.history[#S.history].role == "assistant" then
        S.history[#S.history] = nil
      end
      if #S.history > 0 and S.history[#S.history].role == "user" then
        S.history[#S.history] = nil
      end
      S.history[#S.history+1] = { role = "user", content = history_content }

      -- Reflect the docs inject in the pending user bubble's Show
      -- Details chip so the user can see (if they look) that docs
      -- was added to this turn.
      if S.pending_display_idx
         and S.display_messages[S.pending_display_idx] then
        local dmsg = S.display_messages[S.pending_display_idx]
        local existing = dmsg.ctx_label or ""
        if not existing:find("docs", 1, true) then
          dmsg.ctx_label = existing ~= ""
            and (existing .. " + docs") or "docs"
        end
      end

      -- Match the bucket-recovery flow: refresh snapshot (cheap vs the
      -- curl round trip) and fire the follow-up. No UI error, no
      -- display_message append -- the next response produces the real
      -- assistant reply.
      if prefs.include_snapshot then
        S.pending_project  = S.pending_project or reaper.EnumProjects(-1)
        S.pending_snapshot = CTX.build_snapshot(S.pending_project)
      end
      S.status = "waiting"
      Code.safe_write(tmp.out, "")
      if not Net.fire_curl(Net.build_body(Net.trimmed_history(),
          S.pending_snapshot, S.pending_attachments)) then
        Log.add_error("Auto-retry with API reference did not go through. "
          .. "Please resend the last message.")
      end
      S.scroll_to_bottom = true
      return
    end
    -- Docs fetch failed: keep the old block-and-surface behaviour so the
    -- user knows something is wrong and can fix it manually.
    docs_gate_hit = true
    Log.line("DOCS-GATE",
      "reaper.* calls detected but CTX.docs() failed ("
      .. tostring(ref_err) .. "); auto-run blocked, message flagged")
    Log.add_error(
      "The model wrote reaper.* code without requesting the API "
      .. "reference, and ReaAssist could not auto-fetch the reference "
      .. "to retry (" .. tostring(ref_err) .. "). Auto-run is blocked; "
      .. "review the code carefully before clicking Run manually.")
  end

  -- API VALIDATOR: After the docs-gate, scan generated lua_code for
  -- reaper.X calls where X isn't a real function on this user's machine.
  -- Catches model hallucinations the docs-gate can't (docs-gate only
  -- fires when docs is missing; this fires when docs IS pinned but the
  -- model still emitted a fake function name -- "GetProjectMarkerByIndex"
  -- instead of "EnumProjectMarkers", etc.). Authoritative source is the
  -- live `reaper` table introspected by Code.find_unknown_reaper_calls,
  -- so the check covers core API + every extension actually installed
  -- on this machine.
  --
  -- Recovery: synthesize a retry hint listing the bad calls plus close-
  -- match suggestions, scrub the bad assistant turn from history, and
  -- fire a follow-up. Single retry per user prompt (S.api_validator_retries
  -- caps it). If the retry still produces bad calls, surface a visible
  -- error and block auto-run -- the user sees what was wrong instead of
  -- the script crashing at runtime with "attempt to call a nil value".
  -- Skipped when docs_gate_hit is already set: that path is already
  -- blocking auto-run and surfacing a fetch-failure error; no point
  -- retrying again.
  local validator_gate_hit = false
  if lua_code and not docs_gate_hit then
    local unknown, total_scanned = Code.find_unknown_reaper_calls(lua_code)
    if not unknown then
      -- Pass log: prove the validator actively ran on this response and
      -- found nothing wrong. Skipped when total_scanned == 0 (no reaper.*
      -- calls in the script -- e.g. pure math/string code) since there
      -- was nothing to validate.
      if total_scanned > 0 then
        Log.line("API-VALIDATOR",
          "scanned " .. total_scanned .. " reaper.* call(s), all valid")
      end
    end
    if unknown then
      if (S.api_validator_retries or 0) < 1 then
        S.api_validator_retries = (S.api_validator_retries or 0) + 1
        -- Build per-bad-name suggestion lines for the retry hint.
        local sug_lines = {}
        for _, bad in ipairs(unknown) do
          local matches = Code.suggest_reaper_alternatives(bad, 6)
          local prefixed = {}
          for _, m in ipairs(matches) do prefixed[#prefixed+1] = "reaper." .. m end
          sug_lines[#sug_lines+1] = "  - reaper." .. bad
            .. (#prefixed > 0
                and (" (closest real names: " .. tbl_concat(prefixed, ", ") .. ")")
                or " (no close matches in this user's installed REAPER + extensions)")
        end
        Log.line("API-VALIDATOR",
          "unknown reaper.* calls (" .. #unknown .. "): "
          .. tbl_concat(unknown, ", ")
          .. "; retrying with hint (user-invisible)")
        local history_content = "(INTERNAL NOTE TO THE MODEL -- DO NOT MENTION "
          .. "ANY OF THIS IN YOUR VISIBLE REPLY: Your previous reply called "
          .. "REAPER API functions that do not exist on this user's machine. "
          .. "These calls would crash at runtime:\n"
          .. tbl_concat(sug_lines, "\n") .. "\n\n"
          .. "Regenerate the code using only real reaper.* functions. "
          .. "Cross-check every reaper.* call against the documented "
          .. "signatures before emitting. Respond as if this is your FIRST "
          .. "reply to the user's request -- do NOT apologize, do NOT say "
          .. "'let me try again' or 'on second thought', do NOT mention "
          .. "that prior calls were wrong, do NOT mention a retry. Just "
          .. "deliver the correct code with a normal brief description.)\n\n"
          .. "USER REQUEST:\n" .. (S.pending_orig_prompt or "")
        -- Pop bad assistant + user turn (mirrors docs-gate scrub at line
        -- 15183). Without this, the retry body carries the broken code as
        -- a prior assistant turn, which both poisons prefix caching and
        -- contradicts the "respond as if this is your first reply" nudge.
        if #S.history > 0 and S.history[#S.history].role == "assistant" then
          S.history[#S.history] = nil
        end
        if #S.history > 0 and S.history[#S.history].role == "user" then
          S.history[#S.history] = nil
        end
        S.history[#S.history+1] = { role = "user", content = history_content }
        -- Reflect in the pending bubble's chip so the user can see (if
        -- they expand details) that an API retry was triggered.
        if S.pending_display_idx
           and S.display_messages[S.pending_display_idx] then
          local dmsg = S.display_messages[S.pending_display_idx]
          local existing = dmsg.ctx_label or ""
          if not existing:find("api_retry", 1, true) then
            dmsg.ctx_label = existing ~= ""
              and (existing .. " + api_retry") or "api_retry"
          end
        end
        if prefs.include_snapshot then
          S.pending_project  = S.pending_project or reaper.EnumProjects(-1)
          S.pending_snapshot = CTX.build_snapshot(S.pending_project)
        end
        S.status = "waiting"
        Code.safe_write(tmp.out, "")
        if not Net.fire_curl(Net.build_body(Net.trimmed_history(),
            S.pending_snapshot, S.pending_attachments)) then
          Log.add_error("Auto-retry for invalid reaper.* calls did not "
            .. "go through. Please resend the last message.")
        end
        S.scroll_to_bottom = true
        return
      end
      -- Retry already used and the model STILL produced bad calls. Block
      -- auto-run and surface the diagnostic so the user can review/edit
      -- before clicking Run manually.
      validator_gate_hit = true
      Log.line("API-VALIDATOR",
        "unknown reaper.* calls persist after retry: "
        .. tbl_concat(unknown, ", ") .. "; auto-run blocked")
      Log.add_error("The model emitted REAPER API calls that don't exist "
        .. "on your machine, even after a retry: reaper."
        .. tbl_concat(unknown, ", reaper.")
        .. ". Auto-run is blocked; review and edit the code before clicking "
        .. "Run manually, or retry with a stronger model.")
    end
  end

  -- Auto-run handling.
  local jsfx_auto_status = nil
  local jsfx_saved_path_for_msg = nil   -- saved path to carry on the message
  local jsfx_saved_fx_name_for_msg = nil -- FX ref name to carry on the message
  local auto_ran_ok = false             -- V5: flag for the AUTO-RAN pill below code
  if prefs.auto_run and not docs_gate_hit and not validator_gate_hit then
    -- JSFX: auto-save to Effects/ReaAssist/ folder ONLY when a Lua companion
    -- block is also present (meaning the user asked for it on a track).
    -- If the user just asked for an example, there is no Lua block and the
    -- JSFX is displayed but not saved.
    local jsfx_to_save = jsfx_code or (code_type == "jsfx" and code)
    if jsfx_to_save and lua_code then
      local saved_path, fx_name = Code.auto_save_jsfx(jsfx_to_save)
      if saved_path then
        jsfx_saved_path_for_msg = saved_path
        jsfx_saved_fx_name_for_msg = fx_name
        -- Patch the Lua companion to use the actual saved filename (may have a
        -- numeric suffix if a file with the original name already existed).
        if lua_code and fx_name then
          local orig_name = Code.derive_filename_jsfx(jsfx_to_save)
          local orig_ref  = "ReaAssist/" .. orig_name
          if fx_name ~= orig_ref then
            -- Escape every Lua pattern magic char in orig_ref (the previous
            -- escape covered only . - + and missed ( ) [ ] ^ $ * ? %), and
            -- escape % in fx_name (replacement string treats %% as literal).
            -- Without these, a JSFX desc: line containing one of those chars
            -- (which sanitize_filename does not strip) would either silently
            -- fail to match or throw "invalid use of '%' in replacement
            -- string" and the auto-run companion script would land with the
            -- stale pre-rename ReaAssist/<orig> path.
            local pat = orig_ref:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
            local rep = fx_name:gsub("%%", "%%%%")
            lua_code = lua_code:gsub(pat, rep)
          end
        end
        if lua_code then
          jsfx_auto_status = "Done."
        else
          jsfx_auto_status = "JSFX saved to " .. saved_path
        end
      end
    end
    -- Lua: auto-run (handles both standalone Lua and JSFX companion scripts).
    local run_lua = lua_code or (code_type == "lua" and code)
    if run_lua then
      S.pending_code = run_lua
      local skip_run = false
      -- Risky-code gate: if the scanner flags anything, require explicit
      -- confirmation before auto-executing. The modal index points to the
      -- message that will be appended just below this block.
      local auto_risk = Code.scan_risky(run_lua)
      if auto_risk then
        S.risky_warn_code   = run_lua
        S.risky_warn_idx    = #S.display_messages + 1
        S.risky_warn_detail = auto_risk
        S.open_risky_warn   = true
        skip_run = true
      elseif prefs.auto_backup then
        local bok, berr = Code.safety_backup()
        if berr == "unsaved" then
          S.backup_warn_code = run_lua
          S.backup_warn_idx  = #S.display_messages + 1
          S.open_backup_warn = true
          skip_run = true
        end
      end
      if not skip_run then
        Code.run(run_lua)
        S.pending_code = nil
        auto_ran_ok = true  -- V5: AUTO-RAN pill will render below code
      end
    end
  end
  if code and not S.pending_code then
    S.pending_code = code
  end

  -- Truncation: model hit MAX_TOKENS but still emitted visible text. Stamp
  -- the message so the chat bubble renders a "cut off" banner + the same
  -- recovery buttons as the empty-response case. provider_id is always set
  -- below, so the thinking-level button scopes to the right provider.
  local was_truncated = (empty_reason == "length")
  S.display_messages[#S.display_messages+1] = {
    role       = "assistant",
    content    = explanation,
    code_block = code,
    code_type  = code_type,
    provider_id     = PROVIDERS.active().id,
    model_label     = PROVIDERS.active().label .. " " .. (function()
      -- Same fallback as the user-bubble model_label build: a brief
      -- post-provider-switch race or a 0-model custom provider would
      -- make MODELS[prefs.model_idx] nil, and indexing .label on it
      -- would crash the response handler.
      local _m = MODELS[prefs.model_idx] or MODELS[1]
      return _m and _m.label or "?"
    end)(),
    lua_companion   = jsfx_code and lua_code or nil,  -- store companion for manual run
    jsfx_auto_saved = jsfx_auto_status,               -- status text from auto-save
    jsfx_saved_path = jsfx_saved_path_for_msg,        -- path if already saved (avoids re-save)
    jsfx_saved_fx_name = jsfx_saved_fx_name_for_msg,  -- FX ref name if already saved
    auto_ran        = auto_ran_ok,                    -- V5: show AUTO-RAN pill below code
    truncated       = was_truncated or nil,
    recovery        = was_truncated and "token_limit" or nil,
    -- True when the response tripped the docs-gate (reaper.* emitted with no
    -- api_ref in session). Chat bubble renderers can key off this to show a
    -- warning banner; auto-run was already suppressed above.
    docs_gate_hit   = docs_gate_hit or nil,
  }

  -- Prune oldest display messages beyond the soft cap to prevent unbounded
  -- memory growth. History is bounded by CFG.MAX_HISTORY_TURNS for the API;
  -- this caps the UI-only list. When we prune, also dump the wrap cache --
  -- it's keyed on raw segment text and would otherwise accumulate entries for
  -- every message ever rendered across a long session. The next frame rewrap
  -- is one-shot and imperceptible.
  if #S.display_messages > CFG.MAX_DISPLAY_MSGS then
    while #S.display_messages > CFG.MAX_DISPLAY_MSGS do
      tbl_remove(S.display_messages, 1)
    end
    S.wrap_cache = {}  -- invalidate per-bubble text-wrap cache
  end

  Code.safe_write(tmp.out, "")
  -- Turn completed successfully -- clear resume-state that's only meaningful
  -- during an in-flight turn (popup bail, context_needed follow-ups). Leaves
  -- S.pending_code alone since that carries the generated Lua the user may
  -- still want to Run manually.
  S.pending_orig_prompt = nil
  S.pending_snapshot    = nil
  S.pending_project     = nil
  S.pending_attachments = nil
  S.pending_display_idx = nil
  -- Final clear: this is the only spot in process_response that nils
  -- request_start_time. Earlier cleanup paths (empty-text error, normal
  -- cleanup at ~15636) deliberately leave it set so the docs-gate auto-
  -- retry can keep the in-flight "Thinking..." timer ticking across the
  -- silent retry curl. Once we reach here the turn is fully complete and
  -- the next send_to_api will overwrite anyway.
  S.request_start_time = nil
  S.status           = "idle"
  S.scroll_to_bottom = true
end

Render = {}

-- =============================================================================
-- Critical-files check + Render screen dofile
-- =============================================================================
-- Verify every critical file (UI chunk + every font the atlas expects) is
-- present before dofile()'ing the UI file. If anything is missing, flip
-- into bootstrap recovery: skip the dofile, set S.bootstrap_active, and
-- let the kick-off block at the bottom of the file register Bootstrap.loop
-- instead of the normal loop. Bootstrap uses default font / theme and
-- does not touch Render.* / UI.* / TK.* / FONT.* -- any of which may be
-- nil in recovery mode. CRITICAL_FILES is hardcoded (not manifest-driven)
-- because bootstrap has to run BEFORE any network activity.

S.bootstrap_active  = false
S.bootstrap_missing = {}

do
  -- Derive CRITICAL_FILES from FONT_FILES (the same table _mkfont calls
  -- consume) so the two lists cannot drift: add a font to FONT_FILES
  -- and the bootstrap check picks it up automatically.
  local CRITICAL_FILES = { "Resources/ReaAssist_UI.lua" }
  -- Sort font filenames so the bootstrap-missing list is presented in
  -- a stable order across launches. `pairs` order is hash-bucket-
  -- dependent; without sorting, the recovery screen's "first 6 missing"
  -- entries shuffle between launches for the same filesystem state.
  do
    local fnames = {}
    for _, fname in pairs(FONT_FILES) do fnames[#fnames + 1] = fname end
    table.sort(fnames)
    for _, fname in ipairs(fnames) do
      CRITICAL_FILES[#CRITICAL_FILES + 1] = "Resources/fonts/" .. fname
    end
  end
  for _, rel in ipairs(CRITICAL_FILES) do
    local path = RA.script_path
                 .. (RA.SEP == "/" and rel or rel:gsub("/", RA.SEP))
    local probe = io.open(path, "r")
    if probe then
      probe:close()
    else
      S.bootstrap_missing[#S.bootstrap_missing + 1] = rel
    end
  end
  -- Catch present-but-unloadable fonts: io.open succeeds (file exists), but
  -- ImGui_CreateFontFromFile may have rejected it (truncated, header damaged,
  -- partial download). _mkfont returns nil in that case, so any nil FONT[key]
  -- whose file we DIDN'T already flag as missing must be corrupt. Suffix with
  -- "(load error)" to distinguish from missing in the recovery screen.
  for key, fname in pairs(FONT_FILES) do
    if not FONT[key] then
      local rel = "Resources/fonts/" .. fname
      local already_listed = false
      for _, e in ipairs(S.bootstrap_missing) do
        if e == rel then already_listed = true; break end
      end
      if not already_listed then
        S.bootstrap_missing[#S.bootstrap_missing + 1] = rel .. " (load error)"
      end
    end
  end
end

if #S.bootstrap_missing > 0 then
  S.bootstrap_active = true
  Log.line("BOOTSTRAP", string.format(
    "%d critical file%s missing; entering recovery mode on this launch.",
    #S.bootstrap_missing,
    #S.bootstrap_missing == 1 and "" or "s"))
  for _, rel in ipairs(S.bootstrap_missing) do
    Log.line("BOOTSTRAP", "  missing: " .. rel)
  end
else
  -- All critical files present; dofile the UI file to populate Render.*
  -- before the main loop is registered below. Wrapped in pcall so a UI
  -- file that exists but is syntactically corrupt or throws a top-level
  -- runtime error routes into bootstrap recovery instead of crashing
  -- before the recovery screen can render.
  local ok_ui, err_ui = pcall(dofile, RA.RESOURCES_DIR .. "ReaAssist_UI.lua")
  if not ok_ui then
    S.bootstrap_active = true
    S.bootstrap_missing[#S.bootstrap_missing + 1] =
      "Resources/ReaAssist_UI.lua (load error)"
    Updater._set_failure("ui_load", tostring(err_ui))
    Log.line("BOOTSTRAP", string.format(
      "ReaAssist_UI.lua failed to load: %s", tostring(err_ui)))
  end
end

-- =============================================================================
-- Main loop
-- =============================================================================
-- Registered via reaper.defer() at the bottom of the file; runs every frame.
-- Handles close-signal handoff, curl polling, auto-retry on transient
-- errors, and dispatches the ImGui draw via Render.main_window (which
-- lives in Resources/ReaAssist_UI.lua).
local Loop = {}

-- Second-instance close signal. request_close carries the new instance's ID;
-- a non-empty value that isn't our own triggers a graceful close.
function Loop.handle_close_signal()
  local close_req = reaper.GetExtState(CFG.EXT_NS, "request_close")
  if close_req ~= "" and close_req ~= S.INSTANCE_ID then
    S.script_open = false
  end
end

-- Dispatch one-shot commands from Dev/ReaAssist_Debug_Helper.lua. The helper
-- writes short strings to this ExtState key for actions it can't reach on its
-- own (in-memory state mutations). Cleared immediately so each signal fires
-- once. Add new arms here as dev-helper buttons are wired up.
function Loop.handle_dev_signal()
  local dev_sig = reaper.GetExtState(CFG.EXT_NS, "dev_signal")
  if dev_sig == "" then return end
  reaper.DeleteExtState(CFG.EXT_NS, "dev_signal", false)
  Log.line("DEV_SIGNAL", "received " .. dev_sig)
  if dev_sig == "clear_chat" then
    Net.clear_conversation()
  elseif dev_sig == "reset_window" then
    reaper.DeleteExtState(CFG.EXT_NS, "win_x", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_y", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_w", true)
    reaper.DeleteExtState(CFG.EXT_NS, "win_h", true)
    S._reset_window_size = true
  elseif dev_sig == "refresh_debug_log" then
    -- Match the default-ON pattern at the prefs load site (~= "0").
    -- Otherwise an unset ExtState would refresh OFF, contradicting the
    -- early-release default the user actually has in memory.
    prefs.debug_logging =
      reaper.GetExtState(CFG.EXT_NS, "debug_logging") ~= "0"
  elseif dev_sig == "dump_manifest" then
    -- Dev helper asked for the current PINNED REFERENCES line. Grab the
    -- first line of growing_text (sticky_parts always puts the manifest
    -- there first) and stash it on ExtState for the helper to read back.
    local _, growing = Net.sticky_parts()
    local manifest = "(no pinned references)"
    if growing then
      manifest = growing:match("^([^\n]+)") or manifest
    end
    reaper.SetExtState(CFG.EXT_NS, "dev_manifest_dump", manifest, false)
  elseif dev_sig == "refresh_fx_filter" then
    -- Dev helper toggled the FabFilter-hide flag. Invalidate the cached
    -- installed-FX lists so populate_installed_fx re-walks REAPER with
    -- the new filter, and drop pref_plugins.initialized so the
    -- Preferred Plugins page reloads rows with the filtered view on
    -- next render. Cache mutation isn't needed -- load_pref_plugins
    -- and CTX.preferred_plugins apply _is_fabfilter_ident as a
    -- read-time filter, reading directly from ExtState, so the flag
    -- takes effect even if this signal never fires (e.g. at boot, when
    -- the flag is already "1" in ExtState).
    Log.line("DEV_FILTER", "refresh_fx_filter fired; hide_fabfilter="
      .. (reaper.GetExtState(CFG.EXT_NS, "dev_hide_fabfilter") == "1"
          and "true" or "false"))
    CTX._installed_fx_list         = nil
    CTX._installed_fx_list_deduped = nil
    pref_plugins.initialized = false
  end
end

-- Resolve-popup pending resume coordination. When the user picks a plugin in
-- the resolve popup we kick off fx_cache_rescan_start and stash the ident on
-- S.resolve_pending_resume. Once the scan drains, fire resolve_popup_resume so
-- the follow-up turn's preferred_plugins:<type> bucket has fresh params.
--
-- If needs_deep_scan is set and we haven't already tried a deep scan, kick one
-- off first -- some CLAP plugins have display-refresh lag and deliver bare
-- [norm:] data without enum/range annotations until a deep scan completes.
function Loop.handle_resolve_deep_scan()
  if S.resolve_pending_resume
     and not fx_cache_ui.rescan.active
     and not deep_scan.active
     and not S._resolve_deep_scan_attempted then
    local pdata = FXCache.get_plugin(S.resolve_pending_resume)
    if pdata and pdata.needs_deep_scan then
      S._resolve_deep_scan_attempted = true
      Log.line("DEEP_SCAN", "popup-resume: auto-triggering deep scan for "
        .. S.resolve_pending_resume)
      CTX.fx_cache_rescan_start(S.resolve_pending_resume, true)
      -- Start-of-deep-scan auto-scroll only fires when origin == "chat";
      -- fx_cache_rescan_start uses origin "fx_cache", so force scroll here.
      S.scroll_to_bottom = true
    end
  end
  if S.resolve_pending_resume
     and not fx_cache_ui.rescan.active
     and not deep_scan.active then
    local ident = S.resolve_pending_resume
    S.resolve_pending_resume = nil
    S._resolve_deep_scan_attempted = nil
    Log.line("RESOLVE", "scan finished; resuming for " .. ident)
    Net.resolve_popup_resume(ident)
  end
end

-- Dispatch one tick of the curl pump. If a 529 retry is scheduled and its
-- deadline has passed, re-fire the saved request body. Otherwise, when a
-- request is in flight, throttle-poll the response file (0.1s minimum).
function Loop.pump_curl_or_retry()
  if S.retry_scheduled then
    local now = time_precise()
    if now >= S.retry_fire_time then
      S.retry_scheduled = false
      Code.safe_write(tmp.out, "")
      if S.retry_saved_body and Net.fire_curl(S.retry_saved_body) then
        S.status = "waiting"
      else
        Log.add_error(
          "The servers are still busy and the automatic retry didn't "
          .. "go through. Please try again in a moment.")
        S.retry_count = 0
      end
    end
  elseif S.status == "waiting" or S.gemini_tier_pending then
    local now = time_precise()
    if now - S.last_poll_time >= CFG.POLL_THROTTLE then
      S.last_poll_time = now
      Net.try_finish_curl()
    end
  end
end

local function loop()
  if CFG._PRODUCT:lower() ~= CFG.EXT_NS then return end

  Loop.handle_close_signal()
  Loop.handle_dev_signal()

  -- Pump attachment base64 encoding one chunk per frame so large files
  -- don't block the UI thread when the user attaches them. The Send button
  -- stays disabled (via Attach.all_encoded()) until pumping completes.
  if #S.attachments > 0 then Attach.pump_encoding() end

  -- Preferred plugins parameter scan: phase 2 runs one frame after phase 1
  -- so that newly added FX have initialised their parameter lists.
  if pref_plugins.scan.active and pref_plugins.scan.phase == "reading" then
    CTX.pref_plugins_scan_read()
  end
  -- FX cache single-plugin rescan: same deferred pattern.
  if fx_cache_ui.rescan.active and fx_cache_ui.rescan.phase == "reading" then
    CTX.fx_cache_rescan_read()
  end
  Loop.handle_resolve_deep_scan()
  -- Deep FX param scan: resume one coroutine step per frame.
  if deep_scan.active then CTX.pump_deep_scan() end

  -- Refresh the running lock (instance_id|timestamp) once per second. The
  -- staleness detector's tolerance (STALE_LOCK_SECS = 15) makes per-frame
  -- writes redundant, and SetExtState allocates + formats a new string every
  -- call, so throttling drops ~60 unnecessary writes/sec during normal UI use.
  local now_hb = time_precise()
  if not S._last_heartbeat or now_hb - S._last_heartbeat >= 1.0 then
    S._last_heartbeat = now_hb
    reaper.SetExtState(CFG.EXT_NS, "running",
      S.INSTANCE_ID .. "|" .. tostring(now_hb), false)
  end

  Loop.pump_curl_or_retry()

  -- Gemini cache-create poll runs independently of the main send pipeline
  -- (separate tmp files), so a cache create can complete in parallel with a
  -- user send without interfering with the response parse path.
  if S.gemini_cache_creating then
    local now = time_precise()
    if now - S.last_cache_poll_time >= CFG.POLL_THROTTLE then
      S.last_cache_poll_time = now
      Net.try_finish_gemini_cache_create()
    end
  end

  -- Deferred-kill watchdog: if Cancel was clicked before the launcher finished
  -- writing tmp.pid, retry the kill on every loop tick until the file lands or
  -- the deadline elapses. Cheap (one io.open per frame for ~2s).
  if S.kill_pending then
    Net.try_finish_kill_pending()
  end

  -- Piggyback the once-per-session update check on the first chat-SEND in
  -- this session (transition idle -> waiting), not on the first chat
  -- completion. The reason is purely UX: the manifest fetch plus
  -- incremental SHA verification do real work (CFG.UPDATE_SHA_TIME_BUDGET
  -- per frame, spread across roughly 1-2 seconds total on commodity hardware,
  -- proportionally longer on slower CPUs but with no per-frame stutter). If
  -- that ran AFTER the response was shown, the user would feel subtle
  -- micro-stutters while typing their next message. Running it DURING the
  -- "Thinking..." phase absorbs it into time the user is already waiting,
  -- so by the time the response arrives the verify is usually complete
  -- and the post-response UI stays perfectly smooth.
  --
  -- PowerShell warm-up: the chat's own curl ExecProcess fires on the
  -- send frame and pays ~1-3 s cold-start. By the next frame (when
  -- this loop detects the idle->waiting edge), PS is warm, so
  -- check_start's ExecProcess pays only ~200 ms. Slight extra freeze
  -- on the frame right after Send, immediately following the much
  -- larger chat-curl freeze; the user perceives a single ~1.2-3.2 s
  -- "Send pressed, REAPER busy" moment rather than two separate
  -- freezes (one at Send, one after response).
  --
  -- _session_check_fired is a session-level guard: it ensures only ONE
  -- piggyback fires per ReaAssist launch. Users who never send a message
  -- can still trigger a check manually via Settings > Check for Updates.
  -- check_start itself has a busy guard (Updater.is_busy) so an in-flight
  -- manual check or repair cannot be raced by this trigger.
  if not update._session_check_fired
      and S._prev_status == "idle" and S.status == "waiting" then
    update._session_check_fired = true
    Updater.check_start()
  end
  S._prev_status = S.status

  -- One-time post-update nudge for power-user prompt overrides. Set by
  -- advance_after_rename when an update changed the stock system prompt
  -- while a custom override was active. Fired once per loop, gated so
  -- the toast appears immediately on launch (not after a chat). The
  -- ExtState is cleared the same frame we read it so the toast never
  -- repeats, even if the user closes the window before the toast fades.
  if not S._prompt_nudge_checked then
    S._prompt_nudge_checked = true
    if reaper.GetExtState(CFG.EXT_NS, "prompt_review_pending") == "1" then
      reaper.DeleteExtState(CFG.EXT_NS, "prompt_review_pending", true)
      UI.show_float_toast(
        "System prompt updated. Your custom override is unchanged; "
        .. "review the new stock prompt for changes worth merging.",
        "ok", true)  -- sticky: stays until replaced or window closes
    end
  end

  -- Auto-update polling (independent of main API pipeline).
  if update.state == "checking" then
    Updater.check_poll()
  elseif update.state == "verifying" then
    Updater.tick_sha_diff()
  elseif update.state == "downloading" then
    Updater.download_poll()
  elseif update.state == "rename_retry" then
    Updater.rename_retry_poll()
  end
  -- Stage 3.4 auto-restart: fires once after the apply completes and a
  -- short grace window elapses so the user sees the "Applied" message
  -- before the script relaunches itself.
  Updater.try_auto_restart()

  -- Main-window ImGui pipeline: style pushes, ImGui_Begin on the
  -- main window, full chat/settings/popup body (including the
  -- after_main_window first-frame boot-guard label), balancing
  -- PopStyleColor/PopStyleVar/PopFont, and the separate
  -- Update-Available / Repair dialog. Lives in
  -- Resources/ReaAssist_UI.lua as Render.main_window so the UI half
  -- owns the draw path. Returns `open` so we can still detect the
  -- window's X button below (outside the visible-block scope).
  local open = Render.main_window()

  -- The open bool (window X button) must be checked OUTSIDE the visible block.
  if not open then S.script_open = false end

  if S.script_open then
    reaper.defer(loop)
  else
    -- Save window geometry for next launch. Skipped after Factory Reset
    -- so freshly-cleared keys don't reappear before the user can verify.
    if update._main_x and not S._suppress_geometry_save then
      reaper.SetExtState(CFG.EXT_NS, "win_x", tostring(math.floor(update._main_x)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_y", tostring(math.floor(update._main_y)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_w", tostring(math.floor(update._main_w)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_h", tostring(math.floor(update._main_h)), true)
    end
    -- Intentional close: clean up ExtState (atexit handles crashes).
    set_toolbar(false)
    -- Only clear "running" if it still belongs to this instance. During
    -- auto-restart the new instance has already claimed the lock; we
    -- don't want to wipe its claim on our way out.
    local current = reaper.GetExtState(CFG.EXT_NS, "running")
    if current:match("^([^|]+)") == S.INSTANCE_ID then
      reaper.DeleteExtState(CFG.EXT_NS, "running", false)
    end
    reaper.DeleteExtState(CFG.EXT_NS, "request_close", false)
    -- Delete any hidden temp tracks still owned by in-flight scans so the
    -- user's project doesn't end with a stray hidden track if they close
    -- mid-scan or a second instance forces this one to exit.
    local _inflight = {}
    if pref_plugins.scan  and pref_plugins.scan.track  then _inflight[#_inflight+1] = pref_plugins.scan.track  end
    if fx_cache_ui.rescan and fx_cache_ui.rescan.track then _inflight[#_inflight+1] = fx_cache_ui.rescan.track end
    if S._fx_inspect_tmp  and S._fx_inspect_tmp.tr     then _inflight[#_inflight+1] = S._fx_inspect_tmp.tr     end
    if deep_scan.tr                                    then _inflight[#_inflight+1] = deep_scan.tr             end
    for _, _tr in ipairs(_inflight) do
      if reaper.ValidatePtr2(0, _tr, "MediaTrack*") then
        pcall(reaper.DeleteTrack, _tr)
      end
    end
    -- Close the Undo + PreventUIRefresh scopes those scans hold open.
    -- See the matching block in atexit (above) for the rationale.
    local _owners = 0
    if pref_plugins.scan  and pref_plugins.scan.track  then _owners = _owners + 1 end
    if fx_cache_ui.rescan and fx_cache_ui.rescan.track then _owners = _owners + 1 end
    if S._fx_inspect_tmp                               then _owners = _owners + 1 end
    local _refreshes = _owners
    if deep_scan._ui_refresh_released then _refreshes = _refreshes - 1 end
    if _refreshes < 0 then _refreshes = 0 end
    for _ = 1, _refreshes do pcall(reaper.PreventUIRefresh, -1) end
    for _ = 1, _owners do
      pcall(reaper.Undo_EndBlock, "ReaAssist: scan (closed at exit)", 0)
    end
  end
end

-- =============================================================================
-- Bootstrap: emergency recovery defer loop
-- =============================================================================
-- Runs in place of the normal loop when critical files are missing
-- (S.bootstrap_active). Uses default font and theme so it can draw
-- without touching Render.*, UI.*, TK.*, or FONT.* (any of which may
-- be nil in this mode) and drives Updater.force_reinstall to pull
-- the manifest files down. Once state reaches "available" or
-- "repair_available", Bootstrap auto-accepts without a user click.

Bootstrap = {}

-- Self-contained newline-aware TextWrapped used by Bootstrap.* render
-- functions. Bootstrap may run with Resources/ReaAssist_UI.lua missing
-- or unloadable, in which case UI.text_multiline does not exist; this
-- helper mirrors the no-newline rule (ImGui_TextWrapped corrupts window
-- state when fed a literal \n) without depending on the UI namespace.
local function bootstrap_text_multiline(text)
  local t = tostring(text or "")
  if #t == 0 then ImGui.ImGui_TextWrapped(RA.ctx, " "); return end
  local pos = 1
  while pos <= #t do
    local nl   = t:find("\n", pos, true)
    local line = nl and t:sub(pos, nl - 1) or t:sub(pos)
    if line == "" then
      ImGui.ImGui_Spacing(RA.ctx)
    else
      ImGui.ImGui_TextWrapped(RA.ctx, line)
    end
    if not nl then break end
    pos = nl + 1
  end
end

function Bootstrap.render_prompt()
  ImGui.ImGui_Text(RA.ctx, "ReaAssist is missing critical files.")
  ImGui.ImGui_Spacing(RA.ctx)
  -- List up to 6 missing files; if more, summarize the rest. This keeps the
  -- window a predictable size on fresh-install cases where many files are
  -- absent.
  local n = #S.bootstrap_missing
  local show_n = math.min(n, 6)
  for i = 1, show_n do
    ImGui.ImGui_Text(RA.ctx, "  - " .. S.bootstrap_missing[i])
  end
  if n > show_n then
    ImGui.ImGui_Text(RA.ctx,
      string.format("  ... and %d more", n - show_n))
  end
  ImGui.ImGui_Spacing(RA.ctx)
  ImGui.ImGui_Spacing(RA.ctx)
  if CFG.UPDATE_BASE_URL == "" then
    -- Auto-repair is not available yet (release URL not wired in). Tell the
    -- user they must reinstall manually and exit.
    ImGui.ImGui_Text(RA.ctx,
      "Automatic recovery is not available (update URL not configured).")
    ImGui.ImGui_Text(RA.ctx,
      "Please reinstall ReaAssist manually from the release.")
    ImGui.ImGui_Spacing(RA.ctx)
    if ImGui.ImGui_Button(RA.ctx, "Close", 100, 0) then
      S.script_open = false
    end
  else
    -- If a previous attempt failed (user is back on this prompt after a
    -- rejected check_poll or a rename/SHA failure), surface the reason
    -- so they know whether to retry, exit, or check their network --
    -- otherwise the same button click just silently fails again.
    if update.last_error then
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextColored(RA.ctx, 0xFF8080FF,
        string.format("Previous attempt failed (%s):",
                      tostring(update.last_step or "unknown")))
      -- Use the self-contained bootstrap helper instead of UI.text_multiline:
      -- if Resources/ReaAssist_UI.lua is missing/corrupt the UI namespace
      -- is empty, and TextWrapped corrupts window state when fed a literal \n.
      bootstrap_text_multiline(update.last_error)
      ImGui.ImGui_Spacing(RA.ctx)
    end
    ImGui.ImGui_Text(RA.ctx,
      "Download the missing files from the current ReaAssist release?")
    ImGui.ImGui_Spacing(RA.ctx)
    if ImGui.ImGui_Button(RA.ctx, "Repair", 100, 0) then
      -- Clear any stale failure so the prompt does not keep showing it
      -- while the new attempt is in flight. A fresh failure will re-set
      -- these via Updater._set_failure.
      update.last_error = nil
      update.last_step  = nil
      Updater.force_reinstall()
    end
    ImGui.ImGui_SameLine(RA.ctx, 0, 16)
    if ImGui.ImGui_Button(RA.ctx, "Exit", 80, 0) then
      S.script_open = false
    end
  end
end

function Bootstrap.render_progress()
  ImGui.ImGui_Text(RA.ctx, string.format(
    "Restoring files (%d/%d)...",
    update.download_idx or 0, #(update.download_queue or {})))
  ImGui.ImGui_Spacing(RA.ctx)
  local entry = update.download_queue
                  and update.download_queue[update.download_idx]
  if entry and entry.filename then
    ImGui.ImGui_Text(RA.ctx, entry.filename)
  end
end

-- Bootstrap-mode "checking..." / "verifying..." view. Without this branch
-- the dispatcher falls through to render_prompt, which still shows a
-- clickable Repair button while a check is mid-flight. The force_reinstall
-- busy guard makes a duplicate click harmless, but the visual is wrong:
-- nothing tells the user their first click is being processed. Render a
-- minimal "Checking..." line that mirrors the in-app footer feedback.
function Bootstrap.render_checking()
  if update.state == "verifying" then
    local s = update._sha_diff
    local total = (s and s.files) and #s.files or 0
    local idx   = (s and s.idx)   or 0
    if total > 0 then
      ImGui.ImGui_Text(RA.ctx, string.format(
        "Verifying files (%d/%d)...",
        math.min(idx, total), total))
    else
      ImGui.ImGui_Text(RA.ctx, "Verifying files...")
    end
  else
    ImGui.ImGui_Text(RA.ctx, "Checking for updates...")
  end
  ImGui.ImGui_Spacing(RA.ctx)
  ImGui.ImGui_TextDisabled(RA.ctx,
    "This usually takes a few seconds.")
end

function Bootstrap.render_done()
  local n = #(update.applied_files or {})
  ImGui.ImGui_Text(RA.ctx, string.format(
    "Restored %d file%s successfully.", n, n == 1 and "" or "s"))
  ImGui.ImGui_Spacing(RA.ctx)
  -- Mirror the normal-popup done view: say "Restarting..." when
  -- auto-restart is pending; otherwise tell the user to close and reopen.
  -- OK button always present so the user can close manually at any point.
  local auto_restart_pending = update.restart_after
                                 and not update.restart_fired
  if auto_restart_pending then
    ImGui.ImGui_Text(RA.ctx,
      "Restarting to load the restored files...")
  else
    ImGui.ImGui_Text(RA.ctx,
      "Close and reopen ReaAssist to finish the repair.")
  end
  ImGui.ImGui_Spacing(RA.ctx)
  if ImGui.ImGui_Button(RA.ctx, "OK", 80, 0) then
    S.script_open = false
  end
end

function Bootstrap.render_failed()
  ImGui.ImGui_Text(RA.ctx, "Repair failed.")
  if update.last_error then
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_TextColored(RA.ctx, 0xFF8080FF,
      string.format("Reason (%s):",
                    tostring(update.last_step or "unknown")))
    -- Self-contained helper: UI.text_multiline lives in ReaAssist_UI.lua,
    -- which may not be loaded in bootstrap mode.
    bootstrap_text_multiline(update.last_error)
  end
  ImGui.ImGui_Spacing(RA.ctx)
  ImGui.ImGui_Text(RA.ctx,
    "If the problem persists, reinstall ReaAssist manually.")
  ImGui.ImGui_Spacing(RA.ctx)
  -- Retry path. Most bootstrap failures here are transient (CDN propagation,
  -- AV scanner lock, network blip). force_reinstall clears the failure
  -- metadata and re-fetches the manifest, identical to the Retry button on
  -- the normal Update Failed dialog. Close still ends the session if the
  -- user prefers to bail manually.
  if ImGui.ImGui_Button(RA.ctx, "Retry Repair", 120, 0) then
    update.last_error = nil
    update.last_step  = nil
    Updater.force_reinstall()
  end
  ImGui.ImGui_SameLine(RA.ctx, 0, 16)
  if ImGui.ImGui_Button(RA.ctx, "Close", 80, 0) then
    S.script_open = false
  end
end

function Bootstrap.loop()
  -- Pump the Update state machine so check_poll / download_poll / retry
  -- all advance during bootstrap recovery. The normal main loop does this
  -- in its dev-signal handler; we do it inline here because the normal
  -- loop never runs in bootstrap mode.
  if update.state == "checking"      then Updater.check_poll()       end
  if update.state == "verifying"     then Updater.tick_sha_diff()    end
  if update.state == "downloading"   then Updater.download_poll()    end
  if update.state == "rename_retry"  then Updater.rename_retry_poll() end
  -- Auto-accept: in recovery we do not show an "Update Now" confirm step.
  -- Any transition into the "available" or "repair_available" prompt
  -- immediately fires the download. Single call is enough -- download_start
  -- transitions the state out of those values on the same frame.
  if update.state == "available"
      or update.state == "repair_available" then
    Updater.download_start()
  end
  -- Stage 3.4 auto-restart: once the apply finishes and the 1.5s grace
  -- window elapses, relaunch the script so the newly-downloaded files
  -- take effect without the user having to close/reopen manually.
  Updater.try_auto_restart()

  -- Minimal ImGui window, default font, default theme. Size is chosen
  -- generously so long file-path lines fit without wrapping.
  ImGui.ImGui_SetNextWindowSize(RA.ctx, 540, 300,
    ImGui.ImGui_Cond_Appearing())
  local flags = ImGui.ImGui_WindowFlags_NoCollapse()
              + ImGui.ImGui_WindowFlags_NoDocking()
  local visible, open = ImGui.ImGui_Begin(RA.ctx,
    "ReaAssist Recovery", true, flags)
  if visible then
    if update.state == "downloading"
        or update.state == "rename_retry" then
      Bootstrap.render_progress()
    elseif update.state == "checking"
        or update.state == "verifying" then
      Bootstrap.render_checking()
    elseif update.state == "done" then
      Bootstrap.render_done()
    elseif update.state == "failed" then
      Bootstrap.render_failed()
    else
      Bootstrap.render_prompt()
    end
  end
  -- ImGui_End is called outside the visible block per the Dear ImGui
  -- contract: Begin returns false when the window is collapsed or fully
  -- clipped, but End must still be called either way.
  ImGui.ImGui_End(RA.ctx)
  if not open then S.script_open = false end

  if S.script_open then
    reaper.defer(Bootstrap.loop)
  end
end

-- =============================================================================
-- Kick off
-- =============================================================================
-- Normal path runs full startup + registers loop(); recovery path
-- (S.bootstrap_active) registers Bootstrap.loop instead.
if not S.bootstrap_active then
  -- Defer system prompt load to here so a missing/corrupt stock prompt
  -- can route into bootstrap recovery instead of returning from the main
  -- chunk before recovery has a chance to render. A custom-override
  -- failure cannot be repaired (we don't ship the custom file); in that
  -- case load_system_prompt shows a message and we exit cleanly.
  if not load_system_prompt() and not S.bootstrap_active then
    return
  end
end
if S.bootstrap_active then
  -- Bootstrap skips chat/network/scan init - none of it is safe before
  -- the missing files are recovered.
  Bootstrap.loop()
else
  -- Clear any stale response file from a previous run, then start the defer loop.
  Code.safe_write(tmp.out, "")
  -- Auto-assign preferred_types from the fallback chains in Plugin_Ref.md.
  -- Runs at every launch; never overwrites existing user choices. Lets the
  -- Preferred Plugins page reflect the user's best installed plugin per type
  -- (e.g. Pro-Q 4 if installed, else ReEQ, else ReaEQ) and lets preempt
  -- injection fire for type keywords without any configuration.
  Code.ensure_preferred_from_chains()
  -- Restore any persisted Gemini explicit cache from a previous session. No-op
  -- if no cache was persisted, expired, or already nil; if valid, the next
  -- send to Gemini will skip the cache-create round trip.
  local ok_gcr, gcr_err = pcall(Net.gemini_cache_restore)
  if not ok_gcr then
    Log.line("GEMINI", "cache_restore (startup) failed: " .. tostring(gcr_err))
  end
  -- Do NOT fire the update check here. Updater.fire_get launches curl
  -- via PowerShell, and PowerShell's .NET cold start blocks the main
  -- thread for ~1-3s the first time it runs in a REAPER session. From
  -- startup that would paint a white window before the first ImGui
  -- frame renders. Instead loop() piggybacks the check on the first
  -- chat-response completion (see `update._session_check_fired`), by
  -- which point PowerShell is already warm from the chat's own curl
  -- launch and the check's ExecProcess cost is ~200ms (imperceptible).
  -- Users who never send a chat can trigger the check via Settings >
  -- Check for Updates, which routes to Updater.manual_check.
  loop()
end
