# Recent REAPER Changes

Source: official Cockos changelog, https://www.reaper.fm/whatsnew.txt
Scope: curated user-visible changes likely to affect ReaAssist answers after
model training cutoffs. This is not the full changelog.

If a user asks outside this slice, do not invent details. Say the installed
REAPER changelog is authoritative, or ask for the relevant changelog lines.

## REAPER 7.73 - May 2026

- Actions: REAPER added main Action List commands to move selected media items
  and envelope points left or right to the grid. For MIDI, the MIDI editor also
  added actions to move/resize notes and move CC events left/right to grid.
- Razor edits: Preferences can now choose whether creating a razor edit clears
  or preserves existing media item/envelope selection, right-click no longer
  clears razor edits, and the minimum razor edit length is much smaller.
- Sample editing: sample edit actions now include setting samples to a straight
  line or interpolated curve, support razor edit bounds, and can auto-activate
  sample edits when zoomed in far enough.
- Track grouping: REAPER can automatically group folder/child tracks or folder
  sibling tracks, and grouped razor edits can include hidden tracks.
- JSFX: REAPER added a built-in MIDI Choke Group processor.

## REAPER 7.72 - May 2026

- Render: WAV and WavPack renders can optionally embed hidden regions/markers.
  Look in the Render to File metadata / marker-cue options for WAV/WavPack
  marker and region embedding. Hidden here means REAPER regions/markers whose
  hidden state is set in REAPER; do not confuse this with old "# marker" cue
  naming conventions.

## REAPER 7.70 - April 2026

- Sample editing: REAPER added per-take sample edit envelopes. Enable them from
  the item/take right-click menu under Take Settings.
- Sample editing: REAPER added a dedicated sample-editing mouse modifier
  context.
- Sample editing: the right-click sample-editing menu includes actions to delete
  sample edits and to set sample values to zero within the time selection.
- Sample editing: sample edits can be scaled within the time selection.
- Preferences: General / Advanced settings includes a global font-size scaling
  option for theme fonts, ruler text, and item-label font sizes.

## REAPER 7.65-7.67 - March/April 2026

- Mouse modifiers: REAPER added region/marker left-click and double-click
  contexts.
- Mouse modifiers: REAPER added a ruler lane header double-click context, for
  example to select all regions/markers in a lane.
- Mouse modifiers: REAPER added separate marker left-drag and region-edge
  left-drag contexts.
- Mouse modifiers: REAPER added region/marker actions to move with no lane
  change, copy between lanes only, and copy with no lane change.
- Mouse modifiers: ruler lane mouse modifiers can draw a new region or add a
  new marker.
