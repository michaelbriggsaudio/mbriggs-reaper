# Recent REAPER Changes

Source: official Cockos changelog, https://www.reaper.fm/whatsnew.txt
Scope: curated user-visible changes likely to affect ReaAssist answers after
model training cutoffs. This is not the full changelog.

If a user asks outside this slice, do not invent details. Say the installed
REAPER changelog is authoritative, or ask for the relevant changelog lines.

## REAPER 7.77 - July 2026

- ReaScript: REAPER fixed the 7.75-regression behavior for UI-ordered send
  access and removal. Category-based Get/Set/Remove calls now use category
  `0x10000000` with the plain sparse UI slot index; older one-index UI helpers
  such as `GetTrackSendName()` are different, and the caller must still add
  the flag to their single send-index argument.
- ReaScript UI: `gfx.setcursor()` can accept a `base64:...` cursor containing a
  Windows `.cur` file up to 8 KiB, with a named/built-in fallback advisable for
  older REAPER versions.
- Sends and mixer workflow: drag/drop sidechain send creation now disables the
  MIDI send automatically. Modifier-clicking a mixer FX/send slot can also
  toggle that slot across all selected or all visible tracks.

## REAPER 7.76 - June 2026

- ReaScript: automation items can be muted/read via
  `GetSetAutomationItemInfo(env, autoitem_idx, "D_MUTE", value, is_set)`.
  REAPER also fixed `GetSetTrackSendInfo()` and `GetTrackSendName()` behavior
  for the new UI-ordered send/hardware-output slots from 7.75, and fixed the
  official `AddRegionOrMarker()` documentation.
- FX and send-slot polish: REAPER fixed FX reordering quirks around empty FX
  slots and includes slot information in floating FX window title bars and the
  Project Bay when the displayed slot differs from the dense chain index.
- Sample edits: first-selected-item sample edit actions also work with razor
  edits, new actions can delete all sample edits, mono downmix channel mode is
  supported for delete-all actions, and very long sample edits warn but can run
  up to the new larger limit.
- UI/workflow fixes: the Envelope Manager correctly displays send envelopes
  after empty send slots, mixer scroll offset survives project-tab switches,
  click source paths entered as relative paths are converted to absolute paths,
  and spectral repair uses a smaller analysis window for very short repairs.

## REAPER 7.75 - June 2026

- FX and sends: REAPER can show empty slots in TCP/MCP FX lists and send/
  hardware-output lists, and users can move FX or sends to particular visible
  slots. New actions can toggle selected tracks' FX bypass for slots 1-10.
- Sample editing: REAPER added spectral repair actions for replacing a time
  selection with extrapolated surrounding audio, plus bias/scale/balance/DC/
  fade controls and versions that apply to the first selected item in the time
  selection. The scale and spectral repair windows also have better initial
  focus and keyboard accessibility.
- ReaScript: `TrackFX_GetNamedConfigParm` can map between FX chain indices and
  displayed FX slots, `GetSetProjectInfo(..., "DIRTY", ...)` can query or clear
  project modified state, TrackSend APIs can access UI-ordered send/hardware
  output slots, and `GetThingFromPoint()` can identify TCP/MCP send-list hits.
- Navigator and visual spacers: Navigator can display envelope lanes and visual
  spacers, and Preferences/Appearance can avoid constraining TCP visual spacer
  size to track lane height.

## REAPER 7.74 - June 2026

- FX: REAPER added multi-mono and multi-stereo FX containers, shows linked
  non-primary instances as linked, and exposes parameter sections more clearly
  in TCP controls menus.
- Projects: projects can be opened read-only from the open dialog or file
  attribute, and read-only projects show that state in the title bar. Scripts
  can also open projects with FX offline via `Main_openProject("fxoffline:...")`.
- ReaScript: REAPER added `set_config_var_string`, added a temporary
  `GetSetProjectInfo(..., "READONLY", ...)` project state, extended
  `Main_openProject` with the `fxoffline:` prefix, and fixed Lua
  `TrackFX_FormatParamValueNormalized` / `TakeFX_FormatParamValueNormalized`
  formatting and signatures.
- Sample editing: REAPER added vertical sample-edit drawing modifiers, all-
  channel sample edit actions, better medium-zoom display, and clearer failure
  messages/tooltips for sample editing.
- Render/wildcards: `$seltrack` now resolves to the first selected track, even
  when that track is not being rendered.

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
