<!-- WARNING: This file may be overwritten by ReaAssist updates.    -->
<!-- If you make custom edits, back up your version and restore it  -->
<!-- after updating.                                                -->

# REAPER Theme Color Reference

Runtime color manipulation via SetThemeColor/GetThemeColor.
Changes are live but temporary -- they reset when the user reloads their theme.
Always call ThemeLayout_RefreshAll() + UpdateArrange() after changing colors.

## QUICK USAGE

MANDATORY: ALWAYS save old colors to ExtState BEFORE changing them so the user
can undo/restore. Use the key prefix "ThemeBackup_" + ini_key under the
"ReaAssist" section. After saving all individual keys, ALWAYS write a manifest
entry listing ALL changed keys (comma-separated) so the Undo button can find
them:
  reaper.SetExtState("ReaAssist", "ThemeBackup__KEYS", "key1,key2,key3", false)

```lua
-- REQUIRED PATTERN: save old color, then set new one
local key = "col_arrangebg"
local old = reaper.GetThemeColor(key, 0)
reaper.SetExtState("ReaAssist", "ThemeBackup_" .. key, tostring(old), false)
reaper.SetExtState("ReaAssist", "ThemeBackup__KEYS", key, false)
reaper.SetThemeColor(key, reaper.ColorToNative(20, 25, 45) | 0x1000000, 0)
reaper.ThemeLayout_RefreshAll()
reaper.UpdateArrange()
```

```lua
-- REQUIRED PATTERN: save + set multiple colors
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

IMPORTANT: Do NOT include restore/undo code in your response. The Undo button
handles reverting theme changes automatically via the saved ExtState backups.
Only output the code that APPLIES the requested color changes.

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

- REAPER's built-in undo system does not track theme color changes, so the ExtState backup (see QUICK USAGE pattern) is the only way to revert. The Undo button uses these backups automatically; do not generate restore scripts yourself.
- SetThemeColor changes are TEMPORARY. After applying color changes, add this exact note: 'These changes are temporary and will reset if you reload your theme. Use the Undo button to revert, or click the "Save Theme" button under the code block above to make them permanent.'
- Always use ColorToNative(r,g,b) | 0x1000000 for the color value.
- Always call ThemeLayout_RefreshAll() after setting colors.
- Call UpdateArrange() to refresh the arrange view immediately.
- Wrap bulk changes in PreventUIRefresh(1) / PreventUIRefresh(-1) to avoid flicker.
- Keys ending in _drawmode are blend mode flags, not colors. Do not set RGB values on them.
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
