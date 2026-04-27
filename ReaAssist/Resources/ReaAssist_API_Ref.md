# REAPER ReaScript Lua API Reference

Source: reaper.fm/sdk/reascript/reascripthelp.html (REAPER v7.67)
Lua-only. All functions called as reaper.FunctionName().
Use proj=0 for active project. Track/item indices in the API are 0-based.

## MOST COMMON TASKS (quick reference)

```lua
-- Set volume of selected tracks to -6 dB:
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 0.5)  -- 0.5 = -6dB
end

-- Rename selected track:
local tr = reaper.GetSelectedTrack(0, 0)
if tr then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "New Name", true) end

-- Add FX to selected track:
local tr = reaper.GetSelectedTrack(0, 0)
if tr then reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1) end  -- -1 = find or add

-- Mute/unmute selected tracks:
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  local muted = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE")
  reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", muted == 1 and 0 or 1)
end

-- Delete all tracks:
for i = reaper.CountTracks(0) - 1, 0, -1 do  -- iterate backwards when deleting
  reaper.DeleteTrack(reaper.GetTrack(0, i))
end

-- Get/set time selection:
local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
reaper.GetSet_LoopTimeRange(true, false, 0.0, 4.0, false)  -- set 0-4s

-- Move edit cursor to bar 5:
local pos = reaper.TimeMap2_beatsToTime(0, 0, 5)  -- bar 5, beat 0
reaper.SetEditCurPos(pos, true, false)
```

## SCRIPTING PATTERNS

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

-- Iterate all items on a track:
for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
  local item = reaper.GetTrackMediaItem(tr, i)
end

-- Iterate all items in project:
for i = 0, reaper.CountMediaItems(0) - 1 do
  local item = reaper.GetMediaItem(0, i)
  local tr   = reaper.GetMediaItem_Track(item)
end

-- Always nil-check pointers before use:
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then return end

-- Script loop with defer (for persistent/UI scripts):
local function loop()
  -- work each frame
  reaper.defer(loop)
end
loop()

-- Single-instance guard using ExtState:
local EXT_NS = "my_script"
if reaper.GetExtState(EXT_NS, "running") ~= "" then
  reaper.SetExtState(EXT_NS, "request_close", "1", false)
  return
end
reaper.SetExtState(EXT_NS, "running", "1", false)
reaper.atexit(function()
  reaper.SetExtState(EXT_NS, "running", "", false)
end)

-- Run a REAPER action by command ID (see COMMON ACTION IDS section below for a full list):
reaper.Main_OnCommand(40029, 0)  -- Undo

-- Look up a named command (e.g. SWS):
local cmd = reaper.NamedCommandLookup("_SWS_AWCONSOL")
if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end

-- Standard nil-check + user error message pattern:
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then
  reaper.ShowMessageBox("No track selected.", "Error", 0)
  return
end

-- Safe FX operation: find FX index before using it:
local fx_idx = reaper.TrackFX_GetByName(tr, "ReaEQ", false)
if fx_idx == -1 then
  reaper.ShowMessageBox("ReaEQ not found on track.", "Error", 0)
  return
end
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
-- Read all razor edit areas on a track:
local _, razor = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
local areas = {}
-- Iterate triples: start, end, env_guid (env_guid may be quoted "{...}")
for s, e, g in razor:gmatch('([%d%.%-]+) ([%d%.%-]+) ("[^"]*"|[^%s]*)') do
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

```lua
  -- PITFALL: Do NOT use TrackFX_GetByName when you need to add an FX. GetByName never
  -- adds; it only finds. If the FX is not already on the track, GetByName returns -1
  -- and calling GetNumParams on that -1 index will crash with a nil error.
  -- Rule: if your script needs the FX to exist, always use TrackFX_AddByName with -1.
  -- PITFALL: After adding a new FX with AddByName, do NOT call GetNumParams or any
  -- param functions in the same execution frame. The FX may not be fully initialized.
  -- Always defer param access to the next cycle using reaper.defer().
  -- Pattern:
  --   local fx = reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
  --   reaper.defer(function()
  --     if fx == -1 then return end
  --     local n = reaper.TrackFX_GetNumParams(tr, fx)
  --     -- set params here
  --   end)
```

`boolean reaper.TrackFX_Delete(MediaTrack track, integer fx)`
  Remove FX from chain.

`integer reaper.TrackFX_GetNumParams(MediaTrack track, integer fx)`
  Count parameters on an FX.

```lua
  -- NOTE: there is NO TrackFX_GetParamCount. The correct function is TrackFX_GetNumParams.
  -- Common hallucination: do NOT call reaper.TrackFX_GetParamCount() -- it does not exist.
  -- PITFALL: Returns nil if called in the same frame as TrackFX_AddByName. Always defer.
```

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
  Find FX index by name. Returns -1 if not found. NEVER adds an FX.

```lua
  -- PITFALL: Confused with TrackFX_AddByName. GetByName only searches; it will never
  -- instantiate an FX. Use TrackFX_AddByName(tr, name, false, -1) when you need the
  -- FX to exist on the track. Reserve GetByName for read-only checks only.
```

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
-- in ReaAssist_Plugin_Ref.md. Do not guess param indices or value scales for curated
-- plugins -- always consult that reference.
```

## TAKE FX

Take FX live on a MediaItem_Take, NOT a track. Use this section when the user
wants to apply an effect to a specific item rather than the whole track. The
TakeFX_* API mirrors TrackFX_* exactly -- same arguments, same return shapes,
same defer-after-add requirement -- but operates on a take. If you need to
work with the same FX types you already know from TrackFX, the only change is
swapping `tr` for `take` and the function prefix.

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
  UI open/close/show. showFlag: 0=hide, 1=show, 2=toggle, 3=show in chain.

`boolean reaper.TakeFX_CopyToTrack(MediaItem_Take src_take, integer src_fx, MediaTrack dest_track, integer dest_fx, boolean is_move)`
`boolean reaper.TakeFX_CopyToTake(MediaItem_Take src_take, integer src_fx, MediaItem_Take dest_take, integer dest_fx, boolean is_move)`
  Move or copy a take FX to a track or another take.

```lua
-- Pattern: add an EQ to the active take of the selected item
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then
  reaper.ShowMessageBox("No item selected.", "ReaAssist", 0)
  return
end
local take = reaper.GetActiveTake(item)
if not take then return end
reaper.Undo_BeginBlock()
local fx = reaper.TakeFX_AddByName(take, "ReaEQ", -1)
reaper.defer(function()
  if fx == -1 then return end
  -- set params here
  reaper.Undo_EndBlock("ReaAssist: Add ReaEQ to take", -1)
end)
```

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

### Channel bit-packing (I_SRCCHAN / I_DSTCHAN)

I_SRCCHAN and I_DSTCHAN are NOT plain channel numbers -- they are packed
integers encoding both the first channel and the channel count. Misreading
them is the most common send-routing bug.

```
Encoding (both fields use the same format):
  packed = first_chan | (((num_chans / 2) - 1) << 10)

  first_chan: 0-based first channel (0 = ch1, 2 = ch3, 4 = ch5, ...)
  num_chans:  channel count (must be EVEN: 2, 4, 6, ...). Mono = special.

Common values:
  0           = stereo, channels 1+2  (default for new sends)
  2           = stereo, channels 3+4
  4           = stereo, channels 5+6
  1024 | 0    = 4-channel, starting at ch1   ((4/2-1)=1, 1<<10 = 1024)
  1024 | 2    = 4-channel, starting at ch3
  2048 | 0    = 6-channel, starting at ch1
  -1          = audio routing disabled (no audio sent)

Mono routing (special case):
  packed = 1024 | first_chan, with the high bit set differently --
  mono pins are NOT representable via the same formula. For mono sends,
  the user usually wants stereo with both channels driven; if a true mono
  routing is required, ask the user to set it in the UI and operate on the
  existing send, since the encoding has REAPER-version-specific quirks.

I_MIDI_SRCCHAN / I_MIDI_DSTCHAN:
  Plain integers, NOT bit-packed. -1 = disabled. 0..15 = MIDI channel 1..16.
  Subtract 1 when converting from user input ("MIDI channel 5" -> 4).
```

```lua
-- Pattern: send selected track to track 1, channels 3+4
local src = reaper.GetSelectedTrack(0, 0)
local dst = reaper.GetTrack(0, 0)
if not src or not dst then return end
local sidx = reaper.CreateTrackSend(src, dst)
reaper.SetTrackSendInfo_Value(src, 0, sidx, "I_SRCCHAN", 0)    -- ch1+2 from source
reaper.SetTrackSendInfo_Value(src, 0, sidx, "I_DSTCHAN", 2)    -- to ch3+4 on dest
```

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

`number reaper.ScaleToEnvelopeMode(integer scaling_mode, number val)`
  Convert a real-world value (e.g. dB amplitude or pan position) to the
  envelope's internal scaled storage value. Pass the result to
  InsertEnvelopePoint.

`number reaper.ScaleFromEnvelopeMode(integer scaling_mode, number val)`
  Convert an envelope's internal scaled value back to the real-world value.
  Use this when reading points via GetEnvelopePoint.

```
CRITICAL: Volume envelope values are NOT the same as track D_VOL.
The "Volume (Pre-FX)" / "Volume" envelopes use a non-linear scaling that
depends on the envelope's scaling_mode. You MUST round-trip values through
ScaleToEnvelopeMode / ScaleFromEnvelopeMode or your points will land at the
wrong dB. Pan envelopes have a similar issue when "fader scaling" is on.

Get the scaling mode for an envelope:
  local _, _, _, _, _, _, _, _, _, _, _, scaling_mode =
    reaper.BR_EnvGetProperties(env)   -- requires SWS
  -- OR parse the envelope chunk's "VOLTYPE" / "ACT" lines via GetSetEnvelopeStateChunk

Most modern projects use scaling_mode 0 (linear amplitude, 1.0 = 0dB) for
volume envelopes, so the conversion is identity. But NEVER assume -- always
call ScaleToEnvelopeMode before writing a point. The cost is one function
call; the cost of getting it wrong is silently broken automation.
```

```lua
-- Pattern: write a -6 dB volume envelope point at time 4.0.
-- BR_EnvGetProperties is part of SWS; if SWS is not present, fall back to
-- assuming scaling_mode 0 (the default for new volume envelopes).
local env = reaper.GetTrackEnvelopeByName(tr, "Volume")
if not env then return end
local mode = 0
if reaper.BR_EnvGetProperties then
  local _,_,_,_,_,_,_,_,_,_,_,m = reaper.BR_EnvGetProperties(env)
  mode = m or 0
end
local val    = reaper.DB2SLIDER(-6)              -- dB -> fader/slider value
local scaled = reaper.ScaleToEnvelopeMode(mode, val)
reaper.InsertEnvelopePoint(env, 4.0, scaled, 0, 0, false, false)
reaper.Envelope_SortPoints(env)
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
  Delete marker/region by displayed index.

`boolean reaper.DeleteProjectMarkerByIndex(ReaProject proj, integer markrgnidx)`
  Delete marker/region by internal zero-based index.

`integer markeridx, integer regionidx reaper.GetLastMarkerAndCurRegion(ReaProject proj, number time)`
  Get last marker before time and region containing time.

`reaper.GoToMarker(ReaProject proj, integer marker_index, boolean use_timeline_order)`
`reaper.GoToRegion(ReaProject proj, integer region_index, boolean use_timeline_order)`

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

## MIDI

MIDI functions live in a dedicated reference bucket to keep this file lean.
Request <context_needed>midi</context_needed> when working with MIDI items,
notes, CCs, the MIDI editor, or any MIDI_* / MIDIEditor_* function. The midi
bucket includes function signatures, the PPQ explainer, value ranges, the
bulk-ops rule, and worked examples for transpose/quantize/insert/delete.

The bucket is auto-injected when the user prompt contains the word "midi";
request it explicitly for prompts that imply MIDI without saying it (e.g.
"transpose those notes", "quantize the take").

## NOTES
- All API calls use reaper.* prefix.
- API track/item indices are 0-based. Context buckets report 1-based for readability.
- D_VOL scale: 0=-inf, 0.5=-6dB, 1=+0dB, 2=+6dB.
- I_CUSTOMCOLOR and track colors require ColorToNative(r,g,b)|0x1000000.
- See COMMON PITFALLS below for undo, nil-check, and index guidance.

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
-- PITFALL: 0-based API vs 1-based display.
-- GetTrack(0, 0) = Track 1. GetTrack(0, 9) = Track 10.
-- IP_TRACKNUMBER returns 1-based; subtract 1 when passing back to GetTrack.

-- PITFALL: Forgetting Undo_BeginBlock / Undo_EndBlock.
-- Without the pair, the action cannot be undone and may corrupt the undo history.
-- Always wrap even single-line state changes.

-- PITFALL: Not nil-checking pointer returns.
-- GetSelectedTrack returns nil if nothing is selected.
-- GetTrack returns nil if index is out of range.
-- GetActiveTake returns nil if item has no takes.
-- Passing nil to any API function causes a silent error or crash.

-- PITFALL: Calling UpdateArrange inside a loop.
-- Call it ONCE after all operations are complete, not inside the loop.
-- Same for PreventUIRefresh(-1) and TrackList_AdjustWindows.

-- PITFALL: GetTrackName ignoring the first return value.
-- Wrong:  local name = reaper.GetTrackName(tr)  -- gets retval (true), not name
-- Right:  local _, name = reaper.GetTrackName(tr)

-- PITFALL: Using CountSelectedTracks inside a loop that changes selection.
-- Cache the count before the loop; changing selection mid-loop alters the count.
local count = reaper.CountSelectedTracks(0)
for i = 0, count - 1 do ... end

-- PITFALL: AddProjectMarker index vs displayed number.
-- wantidx=-1 lets REAPER assign; the return value is the assigned internal index.
-- DeleteProjectMarker takes the DISPLAYED number, not the internal index.
-- Use DeleteProjectMarkerByIndex for the internal index.
```
