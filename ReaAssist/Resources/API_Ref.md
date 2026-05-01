<!-- API_Ref.md - REAPER Lua API + workflow reference, parsed into 9 buckets at runtime. -->
<!-- core: pinned by default (when "Always include REAPER API reference" is on; otherwise on-demand via the docs bucket). extended: docs_extended. items/envelopes/take_fx/routing/tempo: docs:NAME. -->
<!-- midi: midi bucket (auto-injected on midi prompts). theme: theme bucket (on-demand). -->
<!-- Each bucket delimited by SECTION:name / /SECTION:name comment markers. -->

<!-- SECTION:core -->
# REAPER ReaScript Lua API Reference

Source: reaper.fm/sdk/reascript/reascripthelp.html (REAPER v7.67)
Lua-only. All functions called as reaper.FunctionName().
Use proj=0 for active project. Track/item indices in the API are 0-based.

This is the CORE reference -- value scales, common patterns, tracks, track FX,
markers, transport, undo, performance tips, and common pitfalls. Less-common
surface lives in on-demand sections requested via `<context_needed>docs:NAME</context_needed>`:
  docs:items      -- media items, takes, item grouping, splits, fades, item properties, P_RAZOREDITS
  docs:take_fx    -- take FX (TakeFX_*); per-item / per-clip / per-take effects
  docs:routing    -- sends, receives, sidechain routing, hardware outputs, channel bit-packing, MIDI channel routing
  docs:envelopes  -- envelopes, automation, automation points, automation modes, envelope scaling, volume/pan envelopes
  docs:tempo      -- tempo, BPM, time signature, time map, beats, quarter notes (QN), measures, bar positions
Plus `docs_extended` for media sources, project metadata, file/system, ext
state, colors, UI & display, named-action calls (Main_OnCommand), misc
utilities. MIDI workflow (notes, CCs, PPQ, MIDI editor) lives in the `midi`
bucket (auto-injected on midi prompts); theme color reference (ini_keys,
SetThemeColor) lives in the `theme` bucket.

## VALUE SCALES (read first -- silent-wrong-value bugs come from these)

INDICES (0-based vs 1-based):
- API track/item indices are 0-based. GetTrack(0, 0) = Track 1.
- IP_TRACKNUMBER returns 1-based; subtract 1 when passing back to GetTrack.
- Context buckets report 1-based for readability; the API is 0-based.

VOLUME (D_VOL is LINEAR AMPLITUDE, not dB and not slider position):
  0=-inf, 0.5=-6dB, 1.0=+0dB, 2.0=+6dB.
- amp -> dB: `db = 20 * math.log(amp, 10)` (clamp `amp <= 0` to "-inf"
  or skip the log; passing 0 yields -inf).
- dB -> amp: `amp = 10 ^ (db / 20)`.
- DO NOT pass D_VOL through SLIDER2DB / DB2SLIDER -- those operate on
  REAPER's 0..1000 fader-position scale (where 540 = 0dB), not linear
  amplitude. Feeding D_VOL=1.0 (which is 0dB) into SLIDER2DB returns
  a deeply negative dB value (~ -150 to -1000). The same caveat applies
  to D_VOL on items, takes, and sends; envelope volumes have their own
  scaling -- see the envelopes bucket.

COLORS:
- I_CUSTOMCOLOR and track/item colors require ColorToNative(r,g,b)|0x1000000.
  Without the |0x1000000 high bit, REAPER reads the value as "no custom
  color" and shows the default.

## COMMON PATTERNS

```lua
-- Standard wrapper for any state-changing script:
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
-- ... do work ...
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Description of action", -1)

-- Iterate all tracks:
for i = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, i)
  local _, name = reaper.GetTrackName(tr)
end

-- Iterate selected tracks:
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
end

-- Iterate items on a track:
for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
  local item = reaper.GetTrackMediaItem(tr, i)
end

-- Iterate items in project:
for i = 0, reaper.CountMediaItems(0) - 1 do
  local item = reaper.GetMediaItem(0, i)
  local tr   = reaper.GetMediaItem_Track(item)
end

-- Iterate backwards when deleting (avoids index shift):
for i = reaper.CountTracks(0) - 1, 0, -1 do
  reaper.DeleteTrack(reaper.GetTrack(0, i))
end

-- Nil-check pattern with user error message:
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then
  reaper.ShowMessageBox("No track selected.", "Error", 0)
  return
end

-- Set volume / mute on selected tracks (D_VOL is linear amplitude -- see VALUE SCALES):
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 0.5)  -- -6dB
  local muted = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE")
  reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", muted == 1 and 0 or 1)
end

-- Rename a track:
local tr = reaper.GetSelectedTrack(0, 0)
if tr then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "New Name", true) end

-- Add FX to a track (use -1 to find existing OR add):
local tr = reaper.GetSelectedTrack(0, 0)
if tr then reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1) end

-- Get/set time selection:
local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
reaper.GetSet_LoopTimeRange(true, false, 0.0, 4.0, false)  -- set 0-4s

-- Persistent script loop (UI scripts, watchers):
local function loop()
  -- work each frame
  reaper.defer(loop)
end
loop()

-- Single-instance guard via ExtState:
local EXT_NS = "my_script"
if reaper.GetExtState(EXT_NS, "running") ~= "" then
  reaper.SetExtState(EXT_NS, "request_close", "1", false)
  return
end
reaper.SetExtState(EXT_NS, "running", "1", false)
reaper.atexit(function()
  reaper.SetExtState(EXT_NS, "running", "", false)
end)

-- Run a REAPER action (for COMMON ACTION IDs see docs_extended):
reaper.Main_OnCommand(40029, 0)  -- Undo

-- Look up a named/SWS command:
local cmd = reaper.NamedCommandLookup("_SWS_AWCONSOL")
if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
```

## RETURN VALUE UNPACKING

```lua
-- Many REAPER functions return multiple values. The first is often a boolean
-- "retval" indicating success. Always check it when it matters:

-- GetTrackName: retval is always true for valid tracks; the name is second:
local _, name = reaper.GetTrackName(tr)

-- TrackFX_GetFXName: retval=true if FX exists; name is second:
local ok, fx_name = reaper.TrackFX_GetFXName(tr, 0, "")
if ok then reaper.ShowConsoleMsg(fx_name .. "\n") end

-- TrackFX_GetParam: returns value, min, max:
local val, min_val, max_val = reaper.TrackFX_GetParam(tr, 0, 0)

-- GetEnvelopePoint: retval=true if point exists; remaining values follow:
local ok, time, value, shape, tension, selected = reaper.GetEnvelopePoint(env, 0)

-- GetSet_LoopTimeRange: returns start, end (even in get mode):
local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
-- ts==te means no time selection
```

## TRACKS

`integer reaper.CountTracks(ReaProject proj)`
  Count tracks in the project.

`MediaTrack reaper.GetTrack(ReaProject proj, integer trackidx)`
  Get track by zero-based index.

`boolean retval, string name reaper.GetTrackName(MediaTrack track, string buf)`
  Get track name.

`number reaper.GetMediaTrackInfo_Value(MediaTrack tr, string parmname)`
  Get track numerical attribute. Key parmnames:
  B_MUTE, B_PHASE, I_SOLO (0=not,1=solo,2=solo-in-place),
  I_FXEN (0=bypassed), I_RECARM, I_RECINPUT, I_RECMODE, I_RECMON,
  I_AUTOMODE (0=trim/off,1=read,2=touch,3=write,4=latch),
  I_NCHAN (2-128 even), I_SELECTED, I_FOLDERDEPTH, I_FOLDERCOMPACT,
  D_VOL (1=+0dB), D_PAN (-1..1), D_WIDTH (-1..1),
  I_CUSTOMCOLOR (ColorToNative(r,g,b)|0x1000000),
  I_HEIGHTOVERRIDE, B_SHOWINMIXER, B_SHOWINTCP, B_MAINSEND,
  IP_TRACKNUMBER (read-only: 1-based, -1=master), P_PARTRACK (read-only).

`boolean reaper.SetMediaTrackInfo_Value(MediaTrack tr, string parmname, number newvalue)`
  Set track numerical attribute.

`boolean retval, string str reaper.GetSetMediaTrackInfo_String(MediaTrack tr, string parmname, string str, boolean setNewValue)`
  Get/set track string: P_NAME, P_ICON, P_MCP_LAYOUT, P_TCP_LAYOUT, P_EXT:xyz, GUID,
  P_RAZOREDITS (razor edit areas -- see RAZOR EDITS subsection below).

`integer reaper.CountSelectedTracks(ReaProject proj)`
  Count selected tracks (excludes master).

`integer reaper.CountSelectedTracks2(ReaProject proj, boolean wantmaster)`
  Count selected tracks, optionally including master.

`MediaTrack reaper.GetSelectedTrack(ReaProject proj, integer seltrackidx)`
  Get selected track by zero-based index (excludes master).

`MediaTrack reaper.GetSelectedTrack2(ReaProject proj, integer seltrackidx, boolean wantmaster)`
  Get selected track by index, optionally including master.

`boolean reaper.IsTrackSelected(MediaTrack track)`
  Returns true if selected.

`boolean reaper.IsTrackVisible(MediaTrack track, boolean mixer)`
  Returns true if visible (mixer=true checks mixer, false checks TCP).

`reaper.InsertTrackAtIndex(integer idx, boolean wantDefaults)`
  Insert a track at zero-based index. wantDefaults=true applies default envs/FX.

`reaper.DeleteTrack(MediaTrack tr)`
  Delete a track.

`MediaTrack reaper.GetMasterTrack(ReaProject proj)`
  Get the master track.

`MediaTrack reaper.GetParentTrack(MediaTrack track)`
  Get parent track (nil if none).

`MediaTrack reaper.GetLastTouchedTrack()`
  Get the last track touched by the user.

`integer reaper.GetTrackColor(MediaTrack track)`
  Get track custom color (0=none).

`reaper.SetTrackColor(MediaTrack track, integer color)`
  Set track custom color. Use ColorToNative(r,g,b)|0x1000000.

`boolean reaper.MuteAllTracks(boolean mute)`
  Mute or unmute all tracks.

`boolean reaper.AnyTrackSolo(ReaProject proj)`
  Returns true if any track is soloed.

### RAZOR EDITS (P_RAZOREDITS)

Razor edit areas are stored on a track as a SPACE-separated string of triples:

```
"start1 end1 envguid1 start2 end2 envguid2 ..."

Each area = 3 tokens:
  start    -- area start time in seconds (number, decimal)
  end      -- area end time in seconds (number, decimal)
  envguid  -- "" for the track itself, or a quoted "{GUID}" for an envelope lane

Empty string = no razor edit areas on this track.
```

```lua
-- Read all razor edit areas on a track. The third token is always quoted in
-- the storage format -- "" for the track itself, "{GUID}" for an envelope
-- lane -- so a single quoted-string capture handles both. (Lua patterns do
-- NOT support | alternation; do not write `("..."|...)`.)
local _, razor = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
local areas = {}
for s, e, g in razor:gmatch('([%d%.%-]+) ([%d%.%-]+) "([^"]*)"') do
  -- g is the inner GUID text without quotes ("" for track-level, GUID for env-lane)
  areas[#areas+1] = { start = tonumber(s), fin = tonumber(e), env = g }
end
-- Simpler version when you only care about track-level areas (env_guid = ""):
for s, e in razor:gmatch('([%d%.%-]+) ([%d%.%-]+) ""') do
  -- track-level razor area from s to e
end

-- Write a single track-level razor area from 4.0 to 8.0 seconds:
reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", '4.000000 8.000000 ""', true)

-- Append a new area without clobbering existing ones:
local _, current = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
local new = (current == "" and "" or current .. " ") .. '12.000000 16.000000 ""'
reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", new, true)

-- Clear all razor areas on a track:
reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true)
```

PITFALL: the envelope GUID token is either an empty quoted string `""` (for
the track itself) or a quoted `"{GUID-HERE}"` (for an envelope lane). The
quotes are part of the storage format -- do not strip them when writing.

PITFALL: P_RAZOREDITS_EXT exists in newer REAPER builds and stores additional
metadata (top/bottom y coords for partial-height razor areas). For most
scripts the plain P_RAZOREDITS field is what you want.

## TRACK FX

ADDBYNAME vs GETBYNAME (read first -- the most common FX-script bug):
- `TrackFX_AddByName(tr, name, false, -1)` finds OR adds. Use this when your
  script needs the FX to exist on the track.
- `TrackFX_GetByName(tr, name, false)` NEVER adds, only searches. Returns -1
  if not found. Reserve for read-only existence checks.
- After AddByName, defer param access to the next cycle -- the FX may not be
  fully initialized in the same execution frame, and GetNumParams returns nil.
- Function name is `GetNumParams`, NOT `GetParamCount` (common hallucination).

```lua
  local fx = reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
  reaper.defer(function()
    if fx < 0 then return end
    local n = reaper.TrackFX_GetNumParams(tr, fx)
    -- set params here
  end)
```

`integer reaper.TrackFX_GetCount(MediaTrack track)`
  Count FX on a track.

`boolean retval, string name reaper.TrackFX_GetFXName(MediaTrack track, integer fx, string name)`
  Get FX name by zero-based index.

`boolean reaper.TrackFX_GetEnabled(MediaTrack track, integer fx)`
  Returns true if FX is enabled.

`reaper.TrackFX_SetEnabled(MediaTrack track, integer fx, boolean enabled)`
  Enable or disable an FX.

`integer reaper.TrackFX_AddByName(MediaTrack track, string fxname, boolean recFX, integer instantiate)`
  Add or find FX by name. Returns zero-based FX index, or -1 on failure.
  instantiate values:
    -1 = find existing instance OR add if not present (PREFERRED -- use this in almost all scripts)
     0 = find existing only, never add
     1 = always add a new instance even if one exists (causes duplicates -- avoid)

`boolean reaper.TrackFX_Delete(MediaTrack track, integer fx)`
  Remove FX from chain.

`integer reaper.TrackFX_GetNumParams(MediaTrack track, integer fx)`
  Count parameters on an FX. (Returns nil in same frame as AddByName -- defer.)

`number retval, number minval, number maxval reaper.TrackFX_GetParam(MediaTrack track, integer fx, integer param)`
  Get FX parameter value and min/max range.

`boolean reaper.TrackFX_SetParam(MediaTrack track, integer fx, integer param, number val)`
  Set FX parameter value.

`boolean retval, string name reaper.TrackFX_GetParamName(MediaTrack track, integer fx, integer param, string buf)`
  Get FX parameter name.

`number reaper.TrackFX_GetParamNormalized(MediaTrack track, integer fx, integer param)`
  Get normalized parameter value (0..1).

`boolean reaper.TrackFX_SetParamNormalized(MediaTrack track, integer fx, integer param, number value)`
  Set normalized parameter value (0..1).

`boolean reaper.TrackFX_GetOpen(MediaTrack track, integer fx)`
  Returns true if FX UI is open.

`reaper.TrackFX_SetOpen(MediaTrack track, integer fx, boolean open)`
  Open or close FX UI.

`reaper.TrackFX_Show(MediaTrack track, integer fx, integer showFlag)`
  showFlag: 0=hide FX chain window, 1=show FX chain window, 2=hide floating window, 3=show floating window.

`integer reaper.TrackFX_GetByName(MediaTrack track, string fxname, boolean instantiate)`
  Find FX index by name. Returns -1 if not found. NEVER adds (see ADDBYNAME vs GETBYNAME above).

`boolean reaper.TrackFX_CopyToTrack(MediaTrack src_track, integer src_fx, MediaTrack dest_track, integer dest_fx, boolean is_move)`
  Copy or move FX to another track.

`integer reaper.TrackFX_GetInstrument(MediaTrack track)`
  Get index of first virtual instrument FX, or -1.

`TrackEnvelope reaper.GetFXEnvelope(MediaTrack track, integer fxindex, integer parameterindex, boolean create)`
  Get FX parameter envelope; create=true creates it if missing.

`integer reaper.TrackFX_GetRecCount(MediaTrack track)`
  Count record (input) FX on a track.

`boolean reaper.TrackFX_NavigatePresets(MediaTrack track, integer fx, integer presetmove)`
  Navigate FX presets: +1=next, -1=prev.

`boolean retval, string presetname reaper.TrackFX_GetPreset(MediaTrack track, integer fx, string presetname)`
  Get current preset name. retval=true if a named preset is active.

`boolean reaper.TrackFX_SetPreset(MediaTrack track, integer fx, string presetname)`
  Set FX preset by name. Returns true if preset was found and applied.

```lua
-- NOTE: Plugin-specific parameter layouts (ReaEQ, ReaComp, etc.) are documented
-- in Plugin_Ref.md. Do not guess param indices or value scales for curated
-- plugins -- always consult that reference.
```

## MARKERS & REGIONS

`integer reaper.GetNumRegionsOrMarkers(ReaProject proj)`
  Total count of markers and regions.

`ProjectMarker reaper.GetRegionOrMarker(ReaProject proj, integer index, string guidStr)`
  Get marker/region by internal index (or by GUID if index<0).

`integer reaper.AddProjectMarker(ReaProject proj, boolean isrgn, number pos, number rgnend, string name, integer wantidx)`
  Add marker/region. Returns index or -1 on failure.

`integer reaper.AddProjectMarker2(ReaProject proj, boolean isrgn, number pos, number rgnend, string name, integer wantidx, integer color)`
  Add marker/region with color (ColorToNative(r,g,b)|0x1000000, or 0 for default).

`boolean reaper.DeleteProjectMarker(ReaProject proj, integer markrgnindexnumber, boolean isrgn)`
  Delete marker/region by DISPLAYED number (the 1, 2, 3... shown in REAPER), NOT the internal index.

`boolean reaper.DeleteProjectMarkerByIndex(ReaProject proj, integer markrgnidx)`
  Delete marker/region by internal zero-based index.

PITFALL: AddProjectMarker returns the assigned INTERNAL index. To delete a
marker you just added, use DeleteProjectMarkerByIndex (NOT DeleteProjectMarker,
which expects the displayed number).

`integer markeridx, integer regionidx reaper.GetLastMarkerAndCurRegion(ReaProject proj, number time)`
  Get last marker before time and region containing time.

`reaper.GoToMarker(ReaProject proj, integer marker_index, boolean use_timeline_order)`
`reaper.GoToRegion(ReaProject proj, integer region_index, boolean use_timeline_order)`

## PLAYBACK & TRANSPORT

`integer reaper.GetPlayState()`
  &1=playing, &2=paused, &4=recording.

`number reaper.GetPlayPosition()`
  Latency-compensated playback position in seconds.

`number reaper.GetCursorPosition()`
  Edit cursor position in seconds.

`reaper.SetEditCurPos(number time, boolean moveview, boolean seekplay)`
  Set edit cursor position.

`number start, number end reaper.GetSet_LoopTimeRange(boolean isSet, boolean isLoop, number start, number end, boolean allowautoseek)`
  Get or set time selection / loop range.

## UNDO

`reaper.Undo_BeginBlock()`
  Begin undo block. Always pair with Undo_EndBlock.

`reaper.Undo_EndBlock(string descstring, integer extraflags)`
  End undo block. extraflags=-1 for default.

`reaper.Undo_DoUndo2(ReaProject proj)`
`reaper.Undo_DoRedo2(ReaProject proj)`

## PERFORMANCE TIPS

```lua
-- PreventUIRefresh: always wrap bulk track/item operations:
reaper.PreventUIRefresh(1)
-- ... hundreds of operations ...
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

-- TrackList_AdjustWindows: call after adding/removing tracks or changing visibility.
-- UpdateArrange: call after moving/resizing items or changing track properties.
-- Both are cheap; when in doubt call both at the end of your script.

-- Envelope bulk inserts: pass noSortIn=true, then call Envelope_SortPoints once:
reaper.InsertEnvelopePoint(env, 0.0, 1.0, 0, 0, false, true)
reaper.InsertEnvelopePoint(env, 1.0, 0.5, 0, 0, false, true)
reaper.Envelope_SortPoints(env)

-- Iterating backwards when deleting: always delete from end to avoid index shifts:
for i = reaper.CountTracks(0) - 1, 0, -1 do
  reaper.DeleteTrack(reaper.GetTrack(0, i))
end
```

## COMMON PITFALLS

```lua
-- PITFALL: Forgetting Undo_BeginBlock / Undo_EndBlock.
-- Without the pair, the action cannot be undone and may corrupt the undo
-- history. Always wrap even single-line state changes.

-- PITFALL: Using CountSelectedTracks inside a loop that changes selection.
-- Cache the count before the loop; changing selection mid-loop alters the
-- count and skips items.
local count = reaper.CountSelectedTracks(0)
for i = 0, count - 1 do
  -- ... your work here ...
end

-- PITFALL: Calling UpdateArrange / TrackList_AdjustWindows inside a loop.
-- Call them ONCE after all operations are complete. Same for
-- PreventUIRefresh(-1).
```
<!-- /SECTION:core -->

<!-- SECTION:extended -->
## MEDIA SOURCES

`string reaper.GetMediaSourceFileName(PCM_source source)`
  Get filename of media source.

`number retval, boolean lengthIsQN reaper.GetMediaSourceLength(PCM_source source)`
  Get length in seconds (or QN if beat-based).

`integer reaper.GetMediaSourceNumChannels(PCM_source source)`
  Get channel count.

`integer reaper.GetMediaSourceSampleRate(PCM_source source)`
  Get sample rate (0 for MIDI).

`string reaper.GetMediaSourceType(PCM_source source)`
  Get type string ("WAV", "MIDI", etc).

## PROJECT

`string reaper.GetProjectPath()`
  Get project recording path.

`string buf reaper.GetProjectName(ReaProject proj)`
  Get project filename.

`number reaper.GetProjectLength(ReaProject proj)`
  Get project length in seconds.

`integer reaper.GetProjectStateChangeCount(ReaProject proj)`
  Counter that increments on any project state change.

`string notes reaper.GetSetProjectNotes(ReaProject proj, boolean set, string notes)`
  Get or set project notes.

`integer retval, string val reaper.GetProjExtState(ReaProject proj, string extname, string key)`
  Get per-project persistent data (saved with project).

`integer reaper.SetProjExtState(ReaProject proj, string extname, string key, string value)`
  Set per-project persistent data.

`boolean reaper.IsProjectDirty(ReaProject proj)`
  Returns true if project has unsaved changes.

`reaper.Main_SaveProject(ReaProject proj, boolean forceSaveAs)`
  Save the project.

## FILE & SYSTEM

`string reaper.GetResourcePath()`
  Path where REAPER ini files are stored.

`string reaper.GetExePath()`
  Path of REAPER.exe directory.

`string reaper.GetOS()`
  "Win32", "Win64", "OSX32", "OSX64", "macOS-arm64", or "Other".

`string reaper.GetAppVersion()`
  REAPER version string (e.g. "7.67/x64").

`boolean reaper.file_exists(string path)`
  Returns true if file exists and is readable.

`string reaper.EnumerateFiles(string path, integer fileindex)`
  List files in directory. Returns nil when done. fileindex=-1 to invalidate cache.

`string reaper.EnumerateSubdirectories(string path, integer subdirindex)`
  List subdirectories. Returns nil when done.

`boolean reaper.RecursiveCreateDirectory(string path, integer ignored)`
  Create directory recursively.

## EXTENSION STATE

`reaper.SetExtState(string section, string key, string value, boolean persist)`
  Set script data. persist=true saves across REAPER restarts.

`string reaper.GetExtState(string section, string key)`
  Get script data.

`boolean reaper.HasExtState(string section, string key)`
  Returns true if key exists.

`reaper.DeleteExtState(string section, string key, boolean persist)`
  Delete script data.

## COLORS

`integer reaper.ColorToNative(integer r, integer g, integer b)`
  Make OS color from RGB (0..255). Use result|0x1000000 for REAPER color fields.

`integer r, integer g, integer b reaper.ColorFromNative(integer col)`
  Extract RGB from OS color.

`reaper.SetThemeColor(string ini_key, integer color, integer flags)`
  Set a theme color at runtime. ini_key = color key (e.g. "col_arrangebg").
  color = ColorToNative(r,g,b)|0x1000000. flags = 0. Changes are temporary
  (reset on theme reload). Call ThemeLayout_RefreshAll() + UpdateArrange() after.
  Request the "theme" context bucket for the full list of valid ini_key names.

`integer reaper.GetThemeColor(string ini_key, integer flags)`
  Get current theme color value. Returns OS-native color. flags = 0.
  Use ColorFromNative() to extract RGB.

`reaper.ThemeLayout_RefreshAll()`
  Refresh all theme layout elements. Call after SetThemeColor.

`string reaper.GetLastColorThemeFile()`
  Get file path of the currently loaded theme.

## UI & DISPLAY

`reaper.UpdateArrange()`
  Redraw arrange view.

`reaper.UpdateTimeline()`
  Redraw timeline/ruler.

`reaper.TrackList_AdjustWindows(boolean isMinor)`
  Rebuild arrange view track list. Call after visibility changes.

`reaper.PreventUIRefresh(integer prevent)`
  prevent>0 suspends UI updates, <=0 restores. Nestable.

`reaper.ShowConsoleMsg(string msg)`
  Print to ReaScript console.

`reaper.ClearConsole()`
  Clear ReaScript console.

`integer reaper.ShowMessageBox(string msg, string title, integer type)`
  type: 0=OK, 1=OK/Cancel, 4=Yes/No.
  Returns: 1=OK, 2=Cancel, 6=Yes, 7=No.

`boolean retval, string buf reaper.GetUserInputs(string title, integer num_inputs, string captions_csv, string vals_csv)`
  Show input dialog. captions and vals are comma-separated strings.

`HWND reaper.GetMainHwnd()`
  Get main REAPER window handle.

`integer reaper.GetGlobalAutomationOverride()`
  -1=no override, 0=trim/read, 1=read, 2=touch, 3=write, 4=latch, 5=bypass.

`reaper.SetGlobalAutomationOverride(integer mode)`
  Set global automation override.

`reaper.BypassFxAllTracks(integer bypass)`
  -1=bypass all if not all already bypassed, otherwise unbypass all.

## ACTIONS

`reaper.Main_OnCommand(integer command, integer flag)`
  Run a REAPER command. flag=0 for normal.

`reaper.Main_OnCommandEx(integer command, integer flag, ReaProject proj)`
  Run command in a specific project.

`integer reaper.NamedCommandLookup(string command_name)`
  Get command ID by name. Returns 0 if not found.

`string reaper.ReverseNamedCommandLookup(integer command_id)`
  Get command name by ID.

### COMMON ACTION IDS

Verified stable across REAPER 6.x and 7.x. Use these directly with
Main_OnCommand instead of guessing. For anything not listed here, look up the
actual command name in REAPER's Action List (`?` shortcut), or use
NamedCommandLookup for SWS/extension actions.

```
TRANSPORT
  1007    Transport: Play
  1008    Transport: Pause
  1013    Transport: Record
  1016    Transport: Stop
  40044   Transport: Play/stop
  40073   Transport: Play/pause

EDITING
  40029   Edit: Undo
  40030   Edit: Redo
  40026   File: Save project
  40012   Item: Split items at edit or play cursor
  40061   Item: Split items at time selection
  40362   Item: Glue items
  40548   Item: Heal splits in items
  40006   Item: Remove items (delete selected items)
  40057   Edit: Copy items/tracks/envelope points (depending on focus)
  40058   Item: Paste items/tracks
  40698   Edit: Copy items
  40434   Item: Group items
  40033   Item grouping: Remove items from group
  40123   Item properties: Mute
  40719   Item properties: Unmute

TRACKS
  40001   Track: Insert new track
  40005   Track: Remove tracks
  40062   Track: Duplicate tracks
  40297   Track: Unselect (clear selection of) all tracks
  40296   Track: Select all tracks

TIME / VIEW
  40020   Time selection: Remove (unselect) time selection and loop points
  40635   Time selection: Set start point to edit cursor
  40626   Time selection: Set end point to edit cursor
  40364   Options: Toggle metronome
  40769   View: Toggle show timeline ruler

MIDI EDITOR (use MIDIEditor_OnCommand, not Main_OnCommand, with these IDs)
  40003   Edit: Insert note at edit cursor
  40051   Edit: Quantize events
  40659   Edit: Glue notes
```

```lua
-- Pattern: split selected items at the edit cursor and group them
reaper.Main_OnCommand(40012, 0)  -- Split items at edit cursor
reaper.Main_OnCommand(40434, 0)  -- Group items
```

PITFALL: many "intuitive" actions have multiple variants ("Split items at
edit cursor", "Split items at time selection", "Split items at edit or play
cursor"). When in doubt, ask the user which behavior they want, or pick the
most general one (40012).

## MISC UTILITIES

`number reaper.DB2SLIDER(number x)`
  Convert dB to REAPER's 0..1000 fader-position scale (540 = 0dB,
  716 = +12dB). NOT for D_VOL -- D_VOL is linear amplitude, see NOTES.

`number reaper.SLIDER2DB(number y)`
  Convert REAPER's 0..1000 fader-position scale to dB. NOT for D_VOL --
  feeding linear amplitude here returns a misleading deeply-negative dB.
  For amplitude -> dB use `20 * math.log(amp, 10)`.

`string reaper.format_timestr_pos(number tpos, string buf, integer modeoverride)`
  Format time. modeoverride: -1=proj default, 0=time, 1=measures.beats+time,
  2=measures.beats, 3=seconds, 4=samples, 5=h:m:s:f.

`number reaper.parse_timestr(string timestr)`
  Parse time string to seconds.

`boolean reaper.APIExists(string function_name)`
  Returns true if the named function exists in this REAPER version.

`reaper.defer(function f)`
  Schedule f to run next defer cycle (use for persistent script loops).

`reaper.atexit(function f)`
  Register cleanup function to run on script exit.

`string reaper.get_action_context()`
  Returns: retval, filename, sectionID, commandID, mode, resolution, val.

`reaper.SetToggleCommandState(integer sectionID, integer commandID, integer state)`
  Set toolbar toggle state: 0=off, 1=on, -1=no state.

`reaper.RefreshToolbar2(integer sectionID, integer commandID)`
  Refresh toolbar button appearance.

`boolean retval, string name, string ident reaper.EnumInstalledFX(integer index)`
  Enumerate installed FX. index=-1 to refresh JSFX list (REAPER 7.42+).
<!-- /SECTION:extended -->

<!-- SECTION:items -->
## MEDIA ITEMS

`MediaItem reaper.AddMediaItemToTrack(MediaTrack tr)`
  Create a new media item on the track.

`MediaItem_Take reaper.AddTakeToMediaItem(MediaItem item)`
  Create a new take in an item.

`integer reaper.CountMediaItems(ReaProject proj)`
  Count items in the project.

`integer reaper.CountTrackMediaItems(MediaTrack track)`
  Count items on a track.

`MediaItem reaper.GetMediaItem(ReaProject proj, integer itemidx)`
  Get item by zero-based index.

`MediaItem reaper.GetTrackMediaItem(MediaTrack track, integer itemidx)`
  Get item on a track by zero-based index.

`MediaTrack reaper.GetMediaItem_Track(MediaItem item)`
  Get parent track of an item.

`number reaper.GetMediaItemInfo_Value(MediaItem item, string parmname)`
  Get item numerical attribute. Key parmnames:
  B_MUTE, B_LOOPSRC, B_UISEL, C_LOCK,
  D_VOL (0=-inf, 1=+0dB, 2=+6dB), D_POSITION, D_LENGTH, D_SNAPOFFSET,
  D_FADEINLEN, D_FADEOUTLEN, D_FADEINDIR, D_FADEOUTDIR,
  I_GROUPID (0=no group), I_CURTAKE,
  I_CUSTOMCOLOR (ColorToNative(r,g,b)|0x1000000),
  I_LASTY, I_LASTH (read-only px), P_TRACK (read-only).

`boolean reaper.SetMediaItemInfo_Value(MediaItem item, string parmname, number newvalue)`
  Set item numerical attribute.

`boolean retval, string str reaper.GetSetMediaItemInfo_String(MediaItem item, string parmname, string str, boolean setNewValue)`
  Get/set item string: P_NOTES, P_EXT:xyz, GUID.

`boolean reaper.SetMediaItemLength(MediaItem item, number length, boolean refreshUI)`
  Set item length in seconds.

`boolean reaper.SetMediaItemPosition(MediaItem item, number pos, boolean refreshUI)`
  Set item position in seconds.

`boolean reaper.SetMediaItemSelected(MediaItem item, boolean sel)`
  Select or deselect an item.

`boolean reaper.IsMediaItemSelected(MediaItem item)`
  Returns true if selected.

`boolean reaper.DeleteTrackMediaItem(MediaTrack tr, MediaItem it)`
  Delete an item from a track.

`integer reaper.CountSelectedMediaItems(ReaProject proj)`
  Count selected items.

`MediaItem reaper.GetSelectedMediaItem(ReaProject proj, integer selitem)`
  Get selected item by index. Prefer CountMediaItems/GetMediaItem/IsMediaItemSelected for iteration.

`MediaItem reaper.CreateNewMIDIItemInProj(MediaTrack track, number starttime, number endtime, optional boolean qnIn)`
  Create a new empty MIDI item. Time in seconds unless qnIn=true.

`boolean reaper.MoveMediaItemToTrack(MediaItem item, MediaTrack desttr)`
  Move item to another track.

`boolean reaper.SelectAllMediaItems(ReaProject proj, boolean selected)`
  Select or deselect all items.

`MediaItem_Take reaper.GetActiveTake(MediaItem item)`
  Get the active take.

`integer reaper.CountTakes(MediaItem item)`
  Count takes in an item.

`MediaItem_Take reaper.GetMediaItemTake(MediaItem item, integer tk)`
  Get take by zero-based index.

`integer reaper.GetMediaItemNumTakes(MediaItem item)`
  Return number of takes.

`MediaItem reaper.GetMediaItemTake_Item(MediaItem_Take take)`
  Get parent item of a take.

`MediaTrack reaper.GetMediaItemTake_Track(MediaItem_Take take)`
  Get parent track of a take.

`PCM_source reaper.GetMediaItemTake_Source(MediaItem_Take take)`
  Get media source of a take.

`number reaper.GetMediaItemTakeInfo_Value(MediaItem_Take take, string parmname)`
  Get take numerical attribute. Key parmnames:
  D_STARTOFFS, D_VOL, D_PAN, D_PANLAW, D_PLAYRATE, D_PITCH,
  B_PPITCH, I_CHANMODE, I_PITCHMODE, I_CUSTOMCOLOR.

`boolean reaper.SetMediaItemTakeInfo_Value(MediaItem_Take take, string parmname, number newvalue)`
  Set take numerical attribute.

`boolean retval, string str reaper.GetSetMediaItemTakeInfo_String(MediaItem_Take tk, string parmname, string str, boolean setNewValue)`
  Get/set take string: P_NAME, P_EXT:xyz, GUID.

`boolean reaper.SetActiveTake(MediaItem_Take take)`
  Set the active take.

### ITEM GROUPING (I_GROUPID)

Items in the same group share an integer group ID stored in the I_GROUPID
attribute. 0 means "not grouped". REAPER assigns group IDs sequentially as
new groups are created; the actual number is opaque -- only equality
matters.

```
GROUPING RULES:
  I_GROUPID == 0   -> not in any group
  I_GROUPID == N   -> in group N (along with all other items where I_GROUPID == N)

There is no "create group" function -- you assign the same I_GROUPID to all
items you want grouped. To find an unused ID, scan all items in the project
and pick max(I_GROUPID) + 1.
```

```lua
-- Pattern: group all selected items into a new group
local function next_group_id()
  local max_id = 0
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local g = reaper.GetMediaItemInfo_Value(it, "I_GROUPID")
    if g > max_id then max_id = g end
  end
  return max_id + 1
end

local n = reaper.CountSelectedMediaItems(0)
if n < 2 then
  reaper.ShowMessageBox("Select at least 2 items to group.", "ReaAssist", 0)
  return
end
reaper.Undo_BeginBlock()
local gid = next_group_id()
for i = 0, n - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  reaper.SetMediaItemInfo_Value(it, "I_GROUPID", gid)
end
reaper.UpdateArrange()
reaper.Undo_EndBlock("ReaAssist: Group selected items", -1)

-- Pattern: ungroup selected items (set I_GROUPID = 0):
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  reaper.SetMediaItemInfo_Value(it, "I_GROUPID", 0)
end

-- Pattern: select all items in the same group as the first selected item:
local first = reaper.GetSelectedMediaItem(0, 0)
if first then
  local target_gid = reaper.GetMediaItemInfo_Value(first, "I_GROUPID")
  if target_gid > 0 then
    for i = 0, reaper.CountMediaItems(0) - 1 do
      local it = reaper.GetMediaItem(0, i)
      if reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == target_gid then
        reaper.SetMediaItemSelected(it, true)
      end
    end
  end
end
```

NOTE: action 40434 ("Item: Group items") does the same thing as the grouping
pattern above and is shorter. Prefer the action when you just need to group
the current selection; use the manual I_GROUPID approach when you need to
inspect, filter, or programmatically pick which items go in which group.
<!-- /SECTION:items -->

<!-- SECTION:envelopes -->
## ENVELOPES

`integer reaper.CountTrackEnvelopes(MediaTrack track)`
  Count track envelopes.

`TrackEnvelope reaper.GetTrackEnvelope(MediaTrack track, integer envidx)`
  Get envelope by index.

`TrackEnvelope reaper.GetTrackEnvelopeByName(MediaTrack track, string envname)`
  Get envelope by name.

`TrackEnvelope reaper.GetTrackEnvelopeByChunkName(MediaTrack track, string chunkname)`
  Get envelope by chunk name (e.g. "<VOLENV", "<PANENV").

`boolean retval, string buf reaper.GetEnvelopeName(TrackEnvelope env)`
  Get envelope name.

`boolean reaper.InsertEnvelopePoint(TrackEnvelope envelope, number time, number value, integer shape, number tension, boolean selected, optional boolean noSortIn)`
  Insert envelope point. shape: 0=linear,1=square,2=slow start/end,3=fast start,4=fast end,5=bezier.
  Call Envelope_SortPoints after bulk inserts.

`boolean retval, number time, number value, integer shape, number tension, boolean selected reaper.GetEnvelopePoint(TrackEnvelope envelope, integer ptidx)`
  Get envelope point attributes.

`boolean reaper.SetEnvelopePoint(TrackEnvelope envelope, integer ptidx, optional number timeIn, optional number valueIn, optional integer shapeIn, optional number tensionIn, optional boolean selectedIn, optional boolean noSortIn)`
  Set envelope point attributes.

`boolean reaper.DeleteEnvelopePointRange(TrackEnvelope envelope, number time_start, number time_end)`
  Delete points in a time range.

`boolean reaper.Envelope_SortPoints(TrackEnvelope envelope)`
  Sort points by time. Call after bulk insert/modify.

`integer retval, number value reaper.Envelope_Evaluate(TrackEnvelope envelope, number time, number samplerate, integer samplesRequested)`
  Get effective envelope value at a time position.

`TrackEnvelope reaper.GetSelectedEnvelope(ReaProject proj)`
  Get currently selected envelope (nil if none).

`integer reaper.GetEnvelopeScalingMode(TrackEnvelope env)`
  Get the envelope's scaling mode. Native API (no SWS required).
  0 = no scaling (linear amplitude for Volume envelopes; raw value otherwise).
  1 = fader scaling (used by some Volume / Pan envelopes when "fader scaling" is on).

`number reaper.ScaleToEnvelopeMode(integer scaling_mode, number val)`
  Convert a real-world value (e.g. dB amplitude or pan position) to the
  envelope's internal scaled storage value. Pass the result to
  InsertEnvelopePoint.

`number reaper.ScaleFromEnvelopeMode(integer scaling_mode, number val)`
  Convert an envelope's internal scaled value back to the real-world value.
  Use this when reading points via GetEnvelopePoint.

```
CRITICAL: Volume envelope values are NOT the same as track D_VOL.
The "Volume (Pre-FX)" / "Volume" envelopes use a scaling that depends on
the envelope's scaling_mode. You MUST round-trip values through
ScaleToEnvelopeMode / ScaleFromEnvelopeMode or your points will land at the
wrong dB. Pan envelopes have a similar issue when "fader scaling" is on.

Always read the scaling mode with the native GetEnvelopeScalingMode(env)
before writing a point. NEVER assume mode 0 -- the cost is one function
call; the cost of getting it wrong is silently broken automation.
```

```lua
-- Pattern: write a -6 dB volume envelope point at time 4.0.
local env = reaper.GetTrackEnvelopeByName(tr, "Volume")
if not env then return end
local mode = reaper.GetEnvelopeScalingMode(env)
-- Volume envelopes (scaling_mode 0) store LINEAR AMPLITUDE, same as D_VOL.
-- Convert dB -> amplitude with `10 ^ (db / 20)`. ScaleToEnvelopeMode then
-- handles any non-default scaling mode the envelope is set to. Do NOT
-- use DB2SLIDER here -- that's the 0..1000 fader-position scale, not the
-- amplitude scale envelope points are stored in.
local val    = 10 ^ (-6 / 20)                    -- -6 dB -> linear amplitude
local scaled = reaper.ScaleToEnvelopeMode(mode, val)
reaper.InsertEnvelopePoint(env, 4.0, scaled, 0, 0, false, false)
reaper.Envelope_SortPoints(env)
```
<!-- /SECTION:envelopes -->

<!-- SECTION:take_fx -->
## TAKE FX

Take FX live on a MediaItem_Take, NOT a track. Use this section when the user
wants to apply an effect to a specific item rather than the whole track. The
TakeFX_* API parallels TrackFX_* in semantics (same defer-after-add rule,
same param/preset/UI surface), but it is NOT identical: in particular,
TakeFX_AddByName takes 3 args (take, fxname, instantiate) while TrackFX_AddByName
takes 4 (track, fxname, recFX, instantiate). Always use the take-prefixed
function and the take-shaped argument list documented below.

Choosing track FX vs take FX:
- "Add an EQ to the track" / "to the bass track" -> TrackFX_*
- "Add an EQ to this item" / "to the selected clip" / "just this take" -> TakeFX_*
- Ambiguous ("add an EQ to the bass") -> ask which they want.

`integer reaper.TakeFX_GetCount(MediaItem_Take take)`
  Count FX on a take.

`integer reaper.TakeFX_AddByName(MediaItem_Take take, string fxname, integer instantiate)`
  Add or find FX on a take. instantiate: -1 = find or add (PREFERRED), 0 = find only, 1 = always new.
  NOTE: TakeFX_AddByName has NO recFX argument (unlike TrackFX_AddByName, which has 4 args).
  Same MANDATORY DEFER RULE applies: do not query or set params in the same execution frame.

`integer reaper.TakeFX_GetByName(MediaItem_Take take, string fxname, boolean instantiate)`
  Find FX index by name. Returns -1 if not found. Never adds.

`boolean reaper.TakeFX_Delete(MediaItem_Take take, integer fx)`
  Remove FX from take chain.

`boolean retval, string name reaper.TakeFX_GetFXName(MediaItem_Take take, integer fx, string name)`
  Get FX name by zero-based index.

`boolean reaper.TakeFX_GetEnabled(MediaItem_Take take, integer fx)`
`reaper.TakeFX_SetEnabled(MediaItem_Take take, integer fx, boolean enabled)`
  Enable / disable a take FX.

`integer reaper.TakeFX_GetNumParams(MediaItem_Take take, integer fx)`
  Count parameters on a take FX. Returns nil in same frame as AddByName -- defer.

`number retval, number minval, number maxval reaper.TakeFX_GetParam(MediaItem_Take take, integer fx, integer param)`
`boolean reaper.TakeFX_SetParam(MediaItem_Take take, integer fx, integer param, number val)`
`number reaper.TakeFX_GetParamNormalized(MediaItem_Take take, integer fx, integer param)`
`boolean reaper.TakeFX_SetParamNormalized(MediaItem_Take take, integer fx, integer param, number value)`
`boolean retval, string name reaper.TakeFX_GetParamName(MediaItem_Take take, integer fx, integer param, string buf)`
`boolean retval, string buf reaper.TakeFX_GetFormattedParamValue(MediaItem_Take take, integer fx, integer param, string buf)`
  Param read/write functions. Identical semantics to the TrackFX_* equivalents.

`boolean reaper.TakeFX_GetOpen(MediaItem_Take take, integer fx)`
`reaper.TakeFX_SetOpen(MediaItem_Take take, integer fx, boolean open)`
`reaper.TakeFX_Show(MediaItem_Take take, integer fx, integer showFlag)`
  Show/hide FX UI. showFlag: 0=hide chain window, 1=show chain window, 2=hide floating window, 3=show floating window. (Same flags as TrackFX_Show.)

`boolean reaper.TakeFX_CopyToTrack(MediaItem_Take src_take, integer src_fx, MediaTrack dest_track, integer dest_fx, boolean is_move)`
`boolean reaper.TakeFX_CopyToTake(MediaItem_Take src_take, integer src_fx, MediaItem_Take dest_take, integer dest_fx, boolean is_move)`
  Move or copy a take FX to a track or another take.

```lua
-- Pattern: add an EQ to the active take of the selected item.
-- SINGLE UNDO BLOCK: Begin/End BOTH inside the deferred frame so the
-- async TakeFX_AddByName step is captured under one undo entry. Wrapping
-- the synchronous add separately produces a stray empty undo step.
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then
  reaper.ShowMessageBox("No item selected.", "ReaAssist", 0)
  return
end
local take = reaper.GetActiveTake(item)
if not take then return end
local fx = reaper.TakeFX_AddByName(take, "ReaEQ", -1)
reaper.defer(function()
  if fx == -1 then return end
  reaper.Undo_BeginBlock()
  -- set params here
  reaper.Undo_EndBlock("ReaAssist: Add ReaEQ to take", -1)
end)
```
<!-- /SECTION:take_fx -->

<!-- SECTION:routing -->
## SENDS / RECEIVES

`integer reaper.CreateTrackSend(MediaTrack tr, MediaTrack desttrIn)`
  Create a send to desttrIn (nil=hardware output). Returns new send index.

`boolean reaper.RemoveTrackSend(MediaTrack tr, integer category, integer sendidx)`
  Remove send (0), receive (-1), or hardware output (1).

`integer reaper.GetTrackNumSends(MediaTrack tr, integer category)`
  Count sends (0), receives (-1), or hardware outputs (1).

`number reaper.GetTrackSendInfo_Value(MediaTrack tr, integer category, integer sendidx, string parmname)`
  Get send/receive attribute. Key parmnames:
  D_VOL, D_PAN, D_PANLAW, B_MUTE, B_PHASE, B_MONO, I_SENDMODE,
  I_SRCCHAN, I_DSTCHAN, I_MIDI_SRCCHAN, I_MIDI_DSTCHAN,
  P_DESTTRACK (read-only), P_SRCTRACK (read-only).

`boolean reaper.SetTrackSendInfo_Value(MediaTrack tr, integer category, integer sendidx, string parmname, number newvalue)`
  Set send/receive attribute.

### CHANNEL BIT-PACKING (I_SRCCHAN / I_DSTCHAN)

I_SRCCHAN and I_DSTCHAN are NOT plain channel numbers -- they are packed
integers. Misreading them is the most common send-routing bug.

```
Verified-safe stereo cases (both fields, low 10 bits = first 0-based channel):
  0           = stereo, channels 1+2  (default for new sends)
  2           = stereo, channels 3+4
  4           = stereo, channels 5+6
  -1          = audio routing disabled (no audio sent)

The high bits (bit 10 = 1024 and above) encode mono mix and channel-count
hints, but the EXACT encoding differs between I_SRCCHAN and I_DSTCHAN and has
varied between REAPER versions. For ANY routing that isn't plain stereo
(multi-channel sends, mono mix, mono pin routing), do NOT compute the packed
value yourself -- ask the user to set it in the REAPER UI and operate on the
existing send. The few extra cents of UI friction are cheaper than silently
landing audio on the wrong channels.

I_MIDI_SRCCHAN / I_MIDI_DSTCHAN:
  Plain integers, NOT bit-packed. -1 = disabled. 0..15 = MIDI channel 1..16.
  Subtract 1 when converting from user input ("MIDI channel 5" -> 4).
  (Newer REAPER builds also expose I_MIDIFLAGS as a unified bit-packed
  replacement; if the script needs MIDI channel routing and these older
  attributes return -1 unexpectedly, fall back to reading I_MIDIFLAGS.)
```

```lua
-- Pattern: send selected track to track 1, stereo to channels 3+4
local src = reaper.GetSelectedTrack(0, 0)
local dst = reaper.GetTrack(0, 0)
if not src or not dst then return end
local sidx = reaper.CreateTrackSend(src, dst)
reaper.SetTrackSendInfo_Value(src, 0, sidx, "I_SRCCHAN", 0)    -- stereo from ch1+2
reaper.SetTrackSendInfo_Value(src, 0, sidx, "I_DSTCHAN", 2)    -- to ch3+4 on dest
```
<!-- /SECTION:routing -->

<!-- SECTION:tempo -->
## TEMPO & TIME

`number bpm, number bpi reaper.GetProjectTimeSignature2(ReaProject proj)`
  Get project BPM and time signature numerator (not envelope-aware).

`number reaper.Master_GetTempo()`
  Get current project tempo in BPM.

`reaper.SetCurrentBPM(ReaProject proj, number bpm, boolean wantUndo)`
  Set project tempo.

`boolean reaper.SetTempoTimeSigMarker(ReaProject proj, integer ptidx, number timepos, integer measurepos, number beatpos, number bpm, integer timesig_num, integer timesig_denom, boolean lineartempochange)`
  Set a tempo marker. ptidx=-1 to add new.

`integer reaper.FindTempoTimeSigMarker(ReaProject proj, number time)`
  Find tempo marker at or before a time position.

`number reaper.TimeMap2_beatsToTime(ReaProject proj, number tpos, optional integer measuresIn)`
  Convert a beat position to a time position in seconds.
  If measuresIn is provided, tpos is interpreted as beats WITHIN that measure
  (i.e. measure number + beat offset). If measuresIn is nil, tpos is the
  total beat count from project start.
  ARG ORDER PITFALL: proj first, tpos second, measuresIn LAST and OPTIONAL.
  Common mistake: passing (proj, measure, beat) -- that's wrong, beat is the
  second arg and measure is the third.

`number reaper.TimeMap2_timeToBeats(ReaProject proj, number tpos, optional integer measuresOutOptional, optional integer cmlOutOptional, optional number fullbeatsOutOptional, optional integer cdenomOutOptional)`
  Convert a time position in seconds to beats. Returns the beat position
  WITHIN the current measure (not total beats from project start). The
  optional out-args fill in: measuresOut = measure number, cmlOut = measure
  length in beats, fullbeatsOut = total beats from start, cdenomOut = current
  time signature denominator.
  Most common usage: `local beat, measure = reaper.TimeMap2_timeToBeats(0, t)`

`number reaper.TimeMap2_QNToTime(ReaProject proj, number qn)`
  Convert quarter notes (from project start) to time in seconds.

`number reaper.TimeMap2_timeToQN(ReaProject proj, number tpos)`
  Convert time in seconds to quarter notes (from project start).

`number reaper.TimeMap_GetDividedBpmAtTime(number time)`
  Get BPM at a specific time position (envelope-aware).

```lua
-- Pattern: move edit cursor to bar 5, beat 1
-- TimeMap2_beatsToTime: beats first, measure second (and 0-based measure!)
local pos = reaper.TimeMap2_beatsToTime(0, 0, 4)  -- beat 0, measure 4 = bar 5
reaper.SetEditCurPos(pos, true, false)
```
<!-- /SECTION:tempo -->

<!-- SECTION:midi -->
# REAPER MIDI Workflow Reference

Function signatures, value ranges, gotchas, and worked examples for working with
MIDI items, notes, CCs, and the MIDI editor in REAPER Lua scripts.

All MIDI functions operate on a MediaItem_Take. Get the take from an item via
reaper.GetActiveTake(item) or reaper.GetMediaItemTake(item, 0).

## VALUE RANGES (memorize these)

```
pitch     0..127     60 = middle C (C4 in REAPER), 69 = A4 (440 Hz)
velocity  0..127     127 = max, 0 = note off
channel   0..15      API uses 0-15, REAPER UI shows 1-16. Always subtract 1.
ppqpos    number     project quarter-note ticks (see PPQ section below)
```

CC chanmsg values (the chanmsg arg to MIDI_InsertCC / MIDI_GetCC):
```
  0x80  Note Off          0xC0  Program Change
  0x90  Note On           0xD0  Channel Pressure (aftertouch)
  0xA0  Poly Aftertouch   0xE0  Pitch Bend
  0xB0  Control Change    0xF0  System (sysex)
```

For a normal MIDI CC: chanmsg=0xB0, msg2=CC number (0-127), msg3=value (0-127).
For pitch bend: chanmsg=0xE0, msg2=LSB, msg3=MSB. 14-bit value = (msg3 << 7) | msg2.
For program change: chanmsg=0xC0, msg2=program (0-127), msg3=0.

## PPQ (PROJECT QUARTER-NOTE TICKS)

PPQ is the time unit for ALL MIDI position arguments. It is NOT seconds and NOT
beats. PPQ is "ticks since the start of the item, where one quarter note is N
ticks". The N (resolution) is item-dependent but typically 960.

NEVER pass seconds to MIDI_InsertNote/SetNote; convert first:
```lua
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, project_time_in_seconds)
```

To go the other way:
```lua
  local secs = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
```

For musical positions (e.g. "place a note on beat 2"), get the PPQ at the item
start, then offset by multiples of one quarter note in PPQ:
```lua
  local item       = reaper.GetMediaItemTake_Item(take)
  local item_t     = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local ppq_st     = reaper.MIDI_GetPPQPosFromProjTime(take, item_t)
  local ppq_per_qn = reaper.MIDI_GetPPQPosFromProjTime(take, item_t + 60/bpm) - ppq_st
```

## BULK-OPS RULE (CRITICAL, ALWAYS APPLY)

When inserting/setting/deleting MORE THAN ONE event, you MUST disable sorting
during the loop and sort once at the end. Failing to do this is O(n^2) and can
hang REAPER on hundreds of notes. Pass noSortIn=true to every Insert/Set call.

```lua
  reaper.MIDI_DisableSort(take)
  for i = 1, n do
    reaper.MIDI_InsertNote(take, false, false, ppq, ppq_end, 0, pitch, vel, true)
  end
  reaper.MIDI_Sort(take)
```

This applies to MIDI_InsertNote, MIDI_InsertCC, MIDI_SetNote, MIDI_SetCC,
MIDI_DeleteNote, MIDI_DeleteCC. Single-event calls do not need it.

For VERY large operations (>1000 events, e.g. importing a whole MIDI file or
generating dense CC streams), even the DisableSort+InsertNote loop can feel
slow. The fast-path is `MIDI_GetAllEvts` / `MIDI_SetAllEvts`, which read/write
the take's entire event list as one binary string of MIDI bytes
(deltatime-encoded). It's ~10x faster than per-event calls but requires
parsing/building the raw byte format yourself. Reach for it only when the
DisableSort loop is actually the bottleneck; the simple loop is fine for
typical user requests.

## FUNCTION SIGNATURES

`MediaItem reaper.CreateNewMIDIItemInProj(MediaTrack track, number starttime, number endtime, optional boolean qnIn)`

  Create a new empty MIDI item on track. starttime/endtime in seconds unless qnIn=true.

`integer reaper.MIDI_CountEvts(MediaItem_Take take)`

  Returns retval, notes, ccs, sysex (4 values). Use this to bound iteration.

`boolean retval, boolean selected, boolean muted, number ppqpos, integer pitch, integer vel reaper.MIDI_GetNote(MediaItem_Take take, integer noteidx)`

  Get note attributes. Note index is 0-based.

`boolean reaper.MIDI_InsertNote(MediaItem_Take take, boolean selected, boolean muted, number ppqpos, number ppqpos_end, integer chan, integer pitch, integer vel, optional boolean noSortIn)`

  Insert a note. Pass noSortIn=true inside bulk loops.

`boolean reaper.MIDI_SetNote(MediaItem_Take take, integer noteidx, optional boolean selectedIn, optional boolean mutedIn, optional number ppqposIn, optional number ppqpos_endIn, optional integer chanIn, optional integer pitchIn, optional integer velIn, optional boolean noSortIn)`

  Modify a note. Pass nil for fields you do not want to change.

`boolean reaper.MIDI_DeleteNote(MediaItem_Take take, integer noteidx)`

  Delete a note. After deletion, indices SHIFT; iterate backwards when bulk-deleting.

`boolean retval, boolean selected, boolean muted, number ppqpos, integer chanmsg, integer chan, integer msg2, integer msg3 reaper.MIDI_GetCC(MediaItem_Take take, integer ccidx)`

  Get a CC/event. chanmsg tells you what kind (see CC values above).

`boolean reaper.MIDI_InsertCC(MediaItem_Take take, boolean selected, boolean muted, number ppqpos, integer chanmsg, integer chan, integer msg2, integer msg3)`

  Insert a CC/event. Use 0xB0 for normal CC, 0xE0 for pitch bend, etc.

`boolean reaper.MIDI_SetCC(MediaItem_Take take, integer ccidx, optional boolean selectedIn, optional boolean mutedIn, optional number ppqposIn, optional integer chanmsgIn, optional integer chanIn, optional integer msg2In, optional integer msg3In, optional boolean noSortIn)`

  Modify a CC. Pass nil for unchanged fields.

`boolean reaper.MIDI_DeleteCC(MediaItem_Take take, integer ccidx)`

  Delete a CC. Indices shift; iterate backwards.

`boolean reaper.MIDI_SelectAll(MediaItem_Take take, boolean selected)`

  Select or deselect all events.

`reaper.MIDI_Sort(MediaItem_Take take)`

  Sort events. MUST be called after any bulk operation.

`reaper.MIDI_DisableSort(MediaItem_Take take)`

  Disable sort. MUST be called before any bulk operation.

`number reaper.MIDI_GetPPQPosFromProjTime(MediaItem_Take take, number projtime)`

  Convert seconds (project time) to PPQ.

`number reaper.MIDI_GetProjTimeFromPPQPos(MediaItem_Take take, number ppqpos)`

  Convert PPQ to seconds (project time).

`number reaper.MIDI_GetPPQPosFromProjQN(MediaItem_Take take, number projqn)`

  Convert quarter notes (project QN, from project start) to PPQ. PREFERRED
  over the time-based path for musical positions -- tempo-map-correct without
  any `60/bpm` math.

`number reaper.MIDI_GetProjQNFromPPQPos(MediaItem_Take take, number ppqpos)`

  Convert PPQ to project QN.

`number reaper.MIDI_GetPPQPos_StartOfMeasure(MediaItem_Take take, number ppqpos)`
`number reaper.MIDI_GetPPQPos_EndOfMeasure(MediaItem_Take take, number ppqpos)`

  Snap a PPQ position to the nearest measure boundary.

`number swing, number note_len_qn reaper.MIDI_GetGrid(MediaItem_Take take)`

  Get the MIDI editor grid for this take. Returns swing amount (-1..1) and
  grid resolution in QN (0.25 = 16th note, 0.5 = 8th, 1.0 = quarter).
  Use for snapping/quantizing to the user's chosen grid instead of hard-coding.

`HWND reaper.MIDIEditor_GetActive()`

  Get the active MIDI editor window. Returns nil if no editor is open.

`MediaItem_Take reaper.MIDIEditor_GetTake(HWND midieditor)`

  Get the take currently being edited.

`boolean reaper.TakeIsMIDI(MediaItem_Take take)`

  Returns true if the take is a MIDI take. Guard any MIDI_* call with this when the take source is uncertain.

## COMMON WORKFLOWS

### WORKFLOW 1: Get the take being edited in the MIDI editor

```lua
  local hwnd = reaper.MIDIEditor_GetActive()
  if not hwnd then
    reaper.ShowMessageBox("No MIDI editor is open.", "ReaAssist", 0)
    return
  end
  local take = reaper.MIDIEditor_GetTake(hwnd)
  if not take or not reaper.TakeIsMIDI(take) then return end
```

### WORKFLOW 2: Iterate every note in a take (read-only)

```lua
  local _, n_notes = reaper.MIDI_CountEvts(take)
  for i = 0, n_notes - 1 do
    local _, sel, mute, ppq, ppq_end, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    -- ... do something with the note
  end
```

### WORKFLOW 3: Transpose all selected notes by N semitones

```lua
  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  local _, n_notes = reaper.MIDI_CountEvts(take)
  for i = 0, n_notes - 1 do
    local _, sel, _, _, _, _, pitch = reaper.MIDI_GetNote(take, i)
    if sel then
      local new_pitch = math.max(0, math.min(127, pitch + semitones))
      reaper.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, new_pitch, nil, true)
    end
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("ReaAssist: Transpose notes", -1)
```

### WORKFLOW 4: Insert a melody from a note list

```lua
  -- notes = {{pitch=60, beat=0, dur=1}, {pitch=62, beat=1, dur=1}, ...}
  -- "beat" here = quarter notes from item start. Tempo-map-correct (no 60/bpm math).
  local item = reaper.GetMediaItemTake_Item(take)
  local item_t = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_qn = reaper.TimeMap2_timeToQN(0, item_t)

  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  for _, note in ipairs(notes) do
    local qn_start = item_qn + note.beat
    local qn_end   = qn_start + note.dur
    local ppq_st   = reaper.MIDI_GetPPQPosFromProjQN(take, qn_start)
    local ppq_en   = reaper.MIDI_GetPPQPosFromProjQN(take, qn_end)
    reaper.MIDI_InsertNote(take, false, false, ppq_st, ppq_en, 0, note.pitch, 100, true)
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("ReaAssist: Insert melody", -1)
```

### WORKFLOW 5: Delete all notes below a given pitch (iterate BACKWARDS)

```lua
  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  local _, n_notes = reaper.MIDI_CountEvts(take)
  for i = n_notes - 1, 0, -1 do
    local _, _, _, _, _, _, pitch = reaper.MIDI_GetNote(take, i)
    if pitch < min_pitch then
      reaper.MIDI_DeleteNote(take, i)
    end
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("ReaAssist: Delete low notes", -1)
```

### WORKFLOW 6: Quantize all notes to the nearest grid division

```lua
  -- grid_qn = 0.25 for 16th notes, 0.5 for 8ths, 1.0 for quarters.
  -- Or read the user's MIDI editor grid: local _, grid_qn = reaper.MIDI_GetGrid(take)
  -- QN-based math is tempo-map-correct without 60/bpm.
  local item = reaper.GetMediaItemTake_Item(take)
  local item_t = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_qn = reaper.TimeMap2_timeToQN(0, item_t)

  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  local _, n_notes = reaper.MIDI_CountEvts(take)
  for i = 0, n_notes - 1 do
    local _, _, _, ppq_st, ppq_en = reaper.MIDI_GetNote(take, i)
    local qn_st = reaper.MIDI_GetProjQNFromPPQPos(take, ppq_st) - item_qn
    local snap_qn = math.floor(qn_st / grid_qn + 0.5) * grid_qn
    local new_ppq_st = reaper.MIDI_GetPPQPosFromProjQN(take, item_qn + snap_qn)
    local len = ppq_en - ppq_st
    reaper.MIDI_SetNote(take, i, nil, nil, new_ppq_st, new_ppq_st + len, nil, nil, nil, true)
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("ReaAssist: Quantize notes", -1)
```

### WORKFLOW 7: Insert a CC envelope (e.g. a volume sweep on CC 7)

```lua
  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  for i = 0, steps do
    local frac = i / steps
    local ppq  = ppq_start + (ppq_end - ppq_start) * frac
    local val  = math.floor(start_val + (end_val - start_val) * frac + 0.5)
    reaper.MIDI_InsertCC(take, false, false, ppq, 0xB0, 0, 7, val)
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("ReaAssist: Insert CC sweep", -1)
```

### WORKFLOW 8: Create a brand-new empty MIDI item, 4 bars long

```lua
  -- Use qnIn=true so REAPER respects the project's tempo map. Length below
  -- assumes 4/4; for other time signatures multiply 4 by the actual bpi.
  local cur_qn = reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition())
  local len_qn = 4 * 4  -- 4 bars * 4 quarter-notes per bar (4/4)
  local item   = reaper.CreateNewMIDIItemInProj(track, cur_qn, cur_qn + len_qn, true)
  local take   = reaper.GetActiveTake(item)
  -- now you can MIDI_InsertNote into `take`
```

## PITFALLS

- Iterating forward while deleting. Indices shift on each delete; you skip half the events. ALWAYS iterate backwards when deleting.
- Pitch / velocity out of range. Clamp to 0..127; MIDI_InsertNote silently fails or wraps.
- Velocity 0 = note off in the MIDI spec. Use 1 as the practical minimum.
- Calling MIDI functions on a non-MIDI take. Check `reaper.TakeIsMIDI(take)` first when the source is uncertain.
- CC chanmsg confusion. Plain MIDI CCs are 0xB0, NOT 0xC0 (program change). Pitch bend is 0xE0.
<!-- /SECTION:midi -->

<!-- SECTION:theme -->
# REAPER Theme Color Reference

Runtime color manipulation via SetThemeColor/GetThemeColor.
Changes are live but temporary -- they reset when the user reloads their theme.
Always call ThemeLayout_RefreshAll() + UpdateArrange() after changing colors.

## QUICK USAGE

MANDATORY: save old colors to ExtState BEFORE changing them so the Undo button
can revert. The pattern below shows the required schema (per-key
`ThemeBackup_<key>` values + a `ThemeBackup__KEYS` manifest entry listing every
changed key, comma-separated).

```lua
-- Single color: save old, then set new.
local key = "col_arrangebg"
local old = reaper.GetThemeColor(key, 0)
reaper.SetExtState("ReaAssist", "ThemeBackup_" .. key, tostring(old), false)
reaper.SetExtState("ReaAssist", "ThemeBackup__KEYS", key, false)
reaper.SetThemeColor(key, reaper.ColorToNative(20, 25, 45) | 0x1000000, 0)
reaper.ThemeLayout_RefreshAll()
reaper.UpdateArrange()
```

```lua
-- Multiple colors: per-key save, then ONE manifest write at the end.
local keys_and_colors = {
  {"col_main_bg2",   {30, 30, 35}},
  {"col_main_text",  {220, 220, 220}},
  {"col_arrangebg",  {25, 28, 38}},
}
local changed_keys = {}
reaper.PreventUIRefresh(1)
for _, entry in ipairs(keys_and_colors) do
  local key, rgb = entry[1], entry[2]
  local old = reaper.GetThemeColor(key, 0)
  reaper.SetExtState("ReaAssist", "ThemeBackup_" .. key, tostring(old), false)
  changed_keys[#changed_keys+1] = key
  reaper.SetThemeColor(key, reaper.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000, 0)
end
reaper.SetExtState("ReaAssist", "ThemeBackup__KEYS", table.concat(changed_keys, ","), false)
reaper.PreventUIRefresh(-1)
reaper.ThemeLayout_RefreshAll()
reaper.UpdateArrange()
```

```lua
-- Read current track panel text color
local native = reaper.GetThemeColor("col_tcp_text", 0)
local r, g, b = reaper.ColorFromNative(native)
```

## API FUNCTIONS

`reaper.SetThemeColor(string ini_key, integer color, integer flags)`
  Set a theme color. ini_key = color key from list below. color = ColorToNative(r,g,b)|0x1000000. flags = 0.

`integer reaper.GetThemeColor(string ini_key, integer flags)`
  Get current theme color value. Returns OS-native color. Use ColorFromNative() to extract RGB. flags = 0.

`reaper.ThemeLayout_RefreshAll()`
  Refresh all theme elements. Call after SetThemeColor to apply changes visually.

`integer reaper.ColorToNative(integer r, integer g, integer b)`
  Convert RGB (0-255) to OS-native color. OR result with 0x1000000 for REAPER color fields.

`integer r, integer g, integer b reaper.ColorFromNative(integer col)`
  Extract RGB components from OS-native color value.

`reaper.UpdateArrange()`
  Force arrange view redraw. Call after theme color changes.

`reaper.UpdateTimeline()`
  Force timeline/ruler redraw.

`string reaper.GetLastColorThemeFile()`
  Get the file path of the currently loaded theme.

## IMPORTANT NOTES

- SetThemeColor changes are TEMPORARY. After applying color changes, add this exact note: 'These changes are temporary and will reset if you reload your theme. Use the Undo button to revert, or click the "Save Theme" button under the code block above to make them permanent.'
- Do NOT include restore/undo code in your response. REAPER's built-in undo doesn't track theme changes; the Undo button reads the ExtState backups automatically. Only output the code that APPLIES the requested changes.
- Keys ending in `_drawmode` are blend mode flags, not colors. Do not set RGB values on them.
- Some keys have no visible effect depending on the active theme's image assets.

## COLOR KEYS

### General UI
col_main_bg          - Main window background
col_main_bg2         - Main window background (alternate)
col_main_text        - Main window text
col_main_text2       - Main window text (inactive/secondary)
col_main_textshadow  - Main window text shadow
col_main_3dhl        - Main window 3D highlight
col_main_3dsh        - Main window 3D shadow
col_main_resize2     - Main window resize grip
col_main_editbk      - Main window edit field background
col_buttonbg         - Button background (0 = use theme default)
col_nodarkmodemiscwnd - Disable dark mode on misc windows (1 = yes)

### Toolbar
col_toolbar_text     - Toolbar button text
col_toolbar_text_on  - Toolbar button text (active/pressed)
col_toolbar_frame    - Toolbar button frame
toolbararmed_color   - Toolbar armed indicator color
toolbararmed_drawmode - Toolbar armed draw mode

### Track Control Panel (TCP)
col_tcp_text         - TCP track name text
col_tcp_textsel      - TCP track name text (selected track)
col_seltrack         - Selected track highlight
col_seltrack2        - Selected track highlight (alternate/unfocused)
col_tracklistbg      - Track list background
tcplocked_color      - TCP locked track overlay color
tcplocked_drawmode   - TCP locked track draw mode

### TCP Scrollbar
tcp_list_scrollbar               - TCP list scrollbar color
tcp_list_scrollbar_mode          - TCP list scrollbar draw mode
tcp_list_scrollbar_mouseover     - TCP list scrollbar (hovered)
tcp_list_scrollbar_mouseover_mode - TCP list scrollbar (hovered) draw mode

### Mixer (MCP)
col_mixerbg          - Mixer panel background

### MCP Scrollbar
mcp_list_scrollbar               - MCP list scrollbar color
mcp_list_scrollbar_mode          - MCP list scrollbar draw mode
mcp_list_scrollbar_mouseover     - MCP list scrollbar (hovered)
mcp_list_scrollbar_mouseover_mode - MCP list scrollbar (hovered) draw mode

### MCP FX / Sends Lists
mcp_sends_normal     - MCP send list text (normal)
mcp_sends_muted      - MCP send list text (muted)
mcp_send_midihw      - MCP send list MIDI/hardware text
mcp_sends_levels     - MCP send level text
mcp_fx_normal        - MCP FX list text (normal)
mcp_fx_bypassed      - MCP FX list text (bypassed)
mcp_fx_offlined      - MCP FX list text (offlined)
mcp_fxparm_normal    - MCP FX parameter text (normal)
mcp_fxparm_bypassed  - MCP FX parameter text (bypassed)
mcp_fxparm_offlined  - MCP FX parameter text (offlined)

### Arrange View
col_arrangebg        - Arrange view background
arrange_vgrid        - Arrange vertical grid lines

### Arrange Track Backgrounds
col_tr1_bg           - Track background (odd tracks)
col_tr2_bg           - Track background (even tracks)
selcol_tr1_bg        - Selected track background (odd)
selcol_tr2_bg        - Selected track background (even)
col_tr1_divline      - Track divider line (odd tracks)
col_tr2_divline      - Track divider line (even tracks)

### Track Lanes
track_lane_tabcol    - Track lane tab color
track_lanesolo_tabcol - Track lane soloed tab color
track_lanesolo_text  - Track lane soloed tab text
track_lane_gutter    - Track lane gutter color
track_lane_gutter_drawmode - Track lane gutter draw mode

### Envelope Lane Dividers
col_envlane1_divline - Envelope lane divider (odd)
col_envlane2_divline - Envelope lane divider (even)

### Media Items
col_mi_bg            - Media item background
col_mi_bg2           - Media item background (alternate)
col_tr1_itembgsel    - Selected item background (odd tracks)
col_tr2_itembgsel    - Selected item background (even tracks)
itembg_drawmode      - Item background draw mode

### Media Item Labels
col_mi_label         - Item label text
col_mi_label_sel     - Item label text (selected)
col_mi_label_float   - Item floating label text
col_mi_label_float_sel - Item floating label text (selected)

### Waveform Peaks
col_tr1_peaks        - Waveform peaks (odd tracks)
col_tr2_peaks        - Waveform peaks (even tracks)
col_tr1_ps2          - Waveform peaks secondary (odd tracks)
col_tr2_ps2          - Waveform peaks secondary (even tracks)
col_peaksedge        - Waveform peak edges
col_peaksedge2       - Waveform peak edges (alternate)
col_peaksedgesel     - Waveform peak edges (selected)
col_peaksedgesel2    - Waveform peak edges (selected alternate)
col_peaksfade        - Waveform peaks faded
col_peaksfade2       - Waveform peaks faded (alternate)

### Fades & Crossfades
col_fadearm           - Fade arm handle color
col_fadearm2          - Fade arm handle color (alternate)
col_fadearm3          - Fade arm handle color (third style)
col_mi_fades          - Media item fade line
col_mi_fade2          - Media item crossfade overlay
col_mi_fade2_drawmode - Crossfade overlay draw mode
fadezone_color        - Fade zone color
fadezone_drawmode     - Fade zone draw mode
fadearea_color        - Fade area color
fadearea_drawmode     - Fade area draw mode

### Stretch Markers
col_stretchmarker     - Stretch marker color
col_stretchmarker_h0  - Stretch marker color (no change)
col_stretchmarker_h1  - Stretch marker color (stretched)
col_stretchmarker_h2  - Stretch marker color (compressed)
col_stretchmarker_b   - Stretch marker border
col_stretchmarkerm    - Stretch marker color (multiple)
col_stretchmarker_text - Stretch marker text
col_stretchmarker_tm  - Stretch marker text (multiple)

### Take Markers & Tags
take_marker          - Take marker color
take_marker_sel      - Take marker color (selected)
selitem_tag          - Selected item tag color
selitem_dot          - Selected item indicator dot
activetake_tag       - Active take tag color
auto_item_unsel      - Auto item (unselected) color

### Item Groups
item_grouphl         - Item group highlight color
autogroup            - Auto-group color

### Offline Items
col_offlinetext      - Offline item text color

### Overlays
mute_overlay_col     - Muted item overlay color
mute_overlay_mode    - Muted item overlay draw mode
inactive_take_overlay_col  - Inactive take overlay color
inactive_take_overlay_mode - Inactive take overlay draw mode
locked_overlay_col   - Locked item overlay color
locked_overlay_mode  - Locked item overlay draw mode

### Timeline & Ruler
col_tl_fg            - Timeline foreground (text/ticks)
col_tl_fg2           - Timeline foreground (secondary)
col_tl_bg            - Timeline background
col_tl_bgsel         - Timeline background (time selection)
col_tl_bgsel2        - Timeline background (time selection alternate)
timesel_drawmode     - Time selection draw mode

### Transport
col_trans_bg         - Transport bar background
col_trans_fg         - Transport bar text
col_transport_editbk - Transport edit field background
playrate_edited      - Playback rate indicator (when edited)

### Cursors
col_cursor           - Edit cursor color
col_cursor2          - Edit cursor color (alternate)
playcursor_color     - Play cursor color
playcursor_drawmode  - Play cursor draw mode

### Grid Lines
col_gridlines        - Grid lines (primary)
col_gridlines1dm     - Grid lines draw mode (primary)
col_gridlines2       - Grid lines (secondary)
col_gridlines2dm     - Grid lines draw mode (secondary)
col_gridlines3       - Grid lines (tertiary)
col_gridlines3dm     - Grid lines draw mode (tertiary)
guideline_color      - Guide line color (snap indicator)
guideline_drawmode   - Guide line draw mode

### Markers
marker               - Marker color
marker_lane_bg       - Marker lane background
marker_lane_text     - Marker lane text
marker_edge          - Marker edge line
marker_edge_sel      - Marker edge line (selected)

### Regions
region               - Region color
region_lane_bg       - Region lane background
region_lane_text     - Region lane text
region_edge          - Region edge line
region_edge_sel      - Region edge line (selected)

### Time Signature Markers
col_tsigmark         - Time signature marker color
ts_lane_bg           - Time signature lane background
ts_lane_text         - Time signature lane text
timesig_sel_bg       - Time signature selection background

### Selection & Marquee
marquee_fill         - Marquee selection fill
marquee_drawmode     - Marquee selection draw mode
marquee_outline      - Marquee selection outline
marqueezoom_fill     - Marquee zoom fill
marqueezoom_drawmode - Marquee zoom draw mode
marqueezoom_outline  - Marquee zoom outline
areasel_fill         - Area selection fill
areasel_drawmode     - Area selection draw mode
areasel_outline      - Area selection outline
areasel_outlinemode  - Area selection outline draw mode

### Linked Lanes
linkedlane_fill          - Linked lane fill
linkedlane_fillmode      - Linked lane fill draw mode
linkedlane_outline       - Linked lane outline
linkedlane_outlinemode   - Linked lane outline draw mode
linkedlane_unsynced      - Linked lane unsynced color
linkedlane_unsynced_mode - Linked lane unsynced draw mode

### Routing & Wiring
col_routinghl1       - Routing highlight 1
col_routinghl2       - Routing highlight 2
col_routingact       - Routing activity indicator
wiring_border        - Routing matrix border
wiring_grid          - Routing matrix grid
wiring_grid2         - Routing matrix grid (alternate)
wiring_fader         - Routing matrix fader
wiring_hwout         - Routing matrix hardware output
wiring_hwoutwire     - Routing matrix hardware output wire
wiring_send          - Routing matrix send
wiring_recv          - Routing matrix receive
wiring_sendwire      - Routing matrix send wire
wiring_parent        - Routing matrix parent
wiring_parentwire_master  - Routing matrix parent wire (master)
wiring_parentwire_folder  - Routing matrix parent wire (folder)
wiring_parentwire_border  - Routing matrix parent wire border
wiring_pin_normal         - Routing matrix pin (normal)
wiring_pin_connected      - Routing matrix pin (connected)
wiring_pin_disconnected   - Routing matrix pin (disconnected)
wiring_media         - Routing matrix media
wiring_recinput      - Routing matrix record input
wiring_recinputwire  - Routing matrix record input wire
wiring_recbg         - Routing matrix record background
wiring_recitem       - Routing matrix record item
wiring_tbg           - Routing matrix track background
wiring_ticon         - Routing matrix track icon
wiring_horz_col      - Routing matrix horizontal color
wiring_activity      - Routing matrix activity

### VU Meters
col_vudoint          - VU meter dots (inactive)
col_vuclip           - VU meter clip indicator
col_vutop            - VU meter top (high level)
col_vumid            - VU meter middle
col_vubot            - VU meter bottom (low level)
col_vuintcol         - VU meter internal color
col_vumidi           - VU meter MIDI activity
col_vuind1           - VU meter indicator 1 (background)
col_vuind2           - VU meter indicator 2
col_vuind3           - VU meter indicator 3
col_vuind4           - VU meter indicator 4
vu_gr_bgcol          - Gain reduction meter background
vu_gr_fgcol          - Gain reduction meter foreground

### I/O Dialog
io_text              - I/O dialog text
io_3dhl              - I/O dialog 3D highlight
io_3dsh              - I/O dialog 3D shadow

### Docker
docker_bg            - Docker background
docker_selface       - Docker selected tab face
docker_unselface     - Docker unselected tab face
docker_text          - Docker tab text
docker_text_sel      - Docker tab text (selected)
docker_shadow        - Docker shadow
windowtab_bg         - Window tab background

### Generic Lists (e.g. FX browser, media explorer)
genlist_bg           - List background
genlist_fg           - List text
genlist_grid         - List grid lines
genlist_selbg        - List selected item background
genlist_selfg        - List selected item text
genlist_seliabg      - List selected item background (inactive)
genlist_seliafg      - List selected item text (inactive)
genlist_hilite       - List highlight
genlist_hilite_sel   - List highlight (selected)

### Media Explorer
col_explorer_sel     - Explorer selected item
col_explorer_seldm   - Explorer selected item draw mode
col_explorer_seledge - Explorer selected item edge
explorer_grid        - Explorer grid lines
explorer_pitchtext   - Explorer pitch text

### Envelope Colors
col_env1  through col_env16 - Envelope lane colors (16 slots)

### Envelope Auto-Colors (for specific envelope types)
env_trim_vol         - Trim volume envelope
env_sends_mute       - Send mute envelope
env_track_mute       - Track mute envelope
env_item_vol         - Item volume envelope
env_item_pan         - Item pan envelope
env_item_mute        - Item mute envelope
env_item_pitch       - Item pitch envelope

### MIDI Editor
midi_rulerbg         - MIDI editor ruler background
midi_rulerfg         - MIDI editor ruler foreground
midi_grid1           - MIDI grid lines (primary)
midi_griddm1         - MIDI grid draw mode (primary)
midi_grid2           - MIDI grid lines (secondary)
midi_griddm2         - MIDI grid draw mode (secondary)
midi_grid3           - MIDI grid lines (tertiary)
midi_griddm3         - MIDI grid draw mode (tertiary)
midi_gridh           - MIDI horizontal grid
midi_gridhdm         - MIDI horizontal grid draw mode
midi_gridhc          - MIDI horizontal grid (center)
midi_gridhcdm        - MIDI horizontal grid (center) draw mode
midi_trackbg1        - MIDI track background (odd rows)
midi_trackbg2        - MIDI track background (even rows)
midi_trackbg_outer1  - MIDI track background outer (odd)
midi_trackbg_outer2  - MIDI track background outer (even)
midi_inline_trackbg1 - MIDI inline editor background (odd)
midi_inline_trackbg2 - MIDI inline editor background (even)
midi_notebg          - MIDI note background (unselected)
midi_notefg          - MIDI note foreground (selected)
midi_notemute        - MIDI note (muted)
midi_notemute_sel    - MIDI note (muted, selected)
midi_noteon_flash    - MIDI note-on flash color
midi_ofsn            - MIDI off-screen note indicator
midi_ofsnsel         - MIDI off-screen note indicator (selected)
midi_editcurs        - MIDI editor edit cursor
midi_endpt           - MIDI note endpoint marker
midi_selbg           - MIDI editor selection background
midi_selbg_drawmode  - MIDI editor selection draw mode
midi_pkey1           - MIDI piano key (white)
midi_pkey2           - MIDI piano key (black)
midi_pkey3           - MIDI piano key (highlight)
midi_selpitch1       - MIDI selected pitch highlight
midi_selpitch2       - MIDI selected pitch highlight (alternate)
midi_itemctl         - MIDI item control
midi_leftbg          - MIDI editor left panel background
midi_ccbut           - MIDI CC lane button background
midi_ccbut_text      - MIDI CC lane button text
midi_ccbut_arrow     - MIDI CC lane button arrow

### MIDI Editor Lists
midieditorlist_bg        - MIDI editor list background
midieditorlist_bg2       - MIDI editor list background (alternate)
midieditorlist_fg        - MIDI editor list text
midieditorlist_fg2       - MIDI editor list text (alternate)
midieditorlist_grid      - MIDI editor list grid
midieditorlist_selbg     - MIDI editor list selected background
midieditorlist_selbg2    - MIDI editor list selected background (alt)
midieditorlist_selfg     - MIDI editor list selected text
midieditorlist_selfg2    - MIDI editor list selected text (alternate)
midieditorlist_seliabg   - MIDI editor list selected (inactive) bg
midieditorlist_seliafg   - MIDI editor list selected (inactive) text

### MIDI Fonts & Note Text
midifont_col_dark        - MIDI note text (dark background)
midifont_col_dark_unsel  - MIDI note text (dark bg, unselected)
midifont_col_light       - MIDI note text (light background)
midifont_col_light_unsel - MIDI note text (light bg, unselected)
midifont_mode            - MIDI note text draw mode
midifont_mode_unsel      - MIDI note text draw mode (unselected)
midioct                  - MIDI octave line color
midioct_inline           - MIDI octave line color (inline editor)

### Score Editor
score_bg             - Score editor background
score_fg             - Score editor foreground
score_sel            - Score editor selection
score_timesel        - Score editor time selection
score_loop           - Score editor loop indicator

### Track Groups (64 group colors)
group_0 through group_63 - Track group colors (64 slots)
<!-- /SECTION:theme -->
