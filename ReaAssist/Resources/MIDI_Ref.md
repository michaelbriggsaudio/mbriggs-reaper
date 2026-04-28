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

`number reaper.MIDI_GetPPQPos_StartOfMeasure(MediaItem_Take take, number ppqpos)`
`number reaper.MIDI_GetPPQPos_EndOfMeasure(MediaItem_Take take, number ppqpos)`

  Snap a PPQ position to the nearest measure boundary.

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
  local item = reaper.GetMediaItemTake_Item(take)
  local item_t = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local _, bpm = reaper.GetProjectTimeSignature2(0)
  local sec_per_beat = 60 / bpm

  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  for _, note in ipairs(notes) do
    local t_start = item_t + note.beat * sec_per_beat
    local t_end   = t_start + note.dur * sec_per_beat
    local ppq_st  = reaper.MIDI_GetPPQPosFromProjTime(take, t_start)
    local ppq_en  = reaper.MIDI_GetPPQPosFromProjTime(take, t_end)
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
  -- grid_qn = 0.25 for 16th notes, 0.5 for 8ths, 1.0 for quarters
  local item = reaper.GetMediaItemTake_Item(take)
  local item_t = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local _, bpm = reaper.GetProjectTimeSignature2(0)
  local sec_per_beat = 60 / bpm
  local grid_secs = grid_qn * sec_per_beat

  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  local _, n_notes = reaper.MIDI_CountEvts(take)
  for i = 0, n_notes - 1 do
    local _, _, _, ppq_st, ppq_en = reaper.MIDI_GetNote(take, i)
    local t_st = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_st) - item_t
    local snap = math.floor(t_st / grid_secs + 0.5) * grid_secs
    local new_ppq_st = reaper.MIDI_GetPPQPosFromProjTime(take, item_t + snap)
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
  local _, bpm = reaper.GetProjectTimeSignature2(0)
  local cur    = reaper.GetCursorPosition()
  local len    = (60 / bpm) * 4 * 4  -- 4 bars at 4 beats/bar
  local item   = reaper.CreateNewMIDIItemInProj(track, cur, cur + len, false)
  local take   = reaper.GetActiveTake(item)
  -- now you can MIDI_InsertNote into `take`
```

## PITFALLS

- Seconds → PPQ always. Use MIDI_GetPPQPosFromProjTime; passing seconds to Insert/SetNote is silent corruption.
- Forgetting MIDI_Sort after a bulk op. Symptoms: editor looks right, playback is wrong, or subsequent reads return stale data.
- Iterating forward while deleting. Indices shift on each delete, you skip half the events. ALWAYS iterate backwards when deleting.
- Channel 1 vs 0. User says "channel 1"; API expects 0. Subtract 1 from user input.
- Pitch / velocity out of range. Clamp to 0..127; MIDI_InsertNote silently fails or wraps.
- Velocity 0 = note off in the MIDI spec. Use 1 as the practical minimum.
- Calling MIDI functions on a non-MIDI take. Check reaper.TakeIsMIDI(take) first when the source is uncertain.
- CC chanmsg confusion. Plain MIDI CCs are 0xB0, NOT 0xC0 (program change). Pitch bend is 0xE0.
