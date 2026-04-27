<!-- ReaAssist_API_Ref_Extended.md - on-demand extended REAPER Lua API reference. -->
<!-- Served by CTX.docs_extended(); requested via <context_needed>docs_extended</context_needed>. -->
<!-- Kept separate from ReaAssist_API_Ref.md (core ref) so the default pinned payload stays small. -->

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
  Convert dB to fader position.

`number reaper.SLIDER2DB(number y)`
  Convert fader position to dB.

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
