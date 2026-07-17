# ReaClock - Custom Studio Clock for REAPER

ReaClock is a scalable studio clock and session display for REAPER. It is designed to remain readable across a room while letting each user choose anything from a minimal position display to a detailed session dashboard.

Provided free by [Michael Briggs Mastering](https://michaelbriggsmastering.com).

## Requirements

- REAPER on Windows, macOS, or Linux
- ReaImGui 0.10 or newer, installed through ReaPack

ReaClock verifies ReaImGui before opening. A missing install, a version older than 0.10, or an incomplete API stops startup with a specific dialog that explains how to install or update ReaImGui through ReaPack, synchronize repositories if needed, restart REAPER, and try again. Missing bundled fonts are nonfatal: ReaClock falls back to an available generic or system font and reports the fallback in Settings. SWS and js_ReaScriptAPI are not required.

## License

ReaClock's original Lua source and assets are provided free to download, install, and use through distribution channels authorized by Michael Briggs. They are not open source: redistribution, resale, sublicensing, repackaging, or presenting modified or unmodified copies as your own requires prior written permission. The bundled `Resources/ReaClock_Meter.jsfx` companion is a separately licensed Cockos-derived work distributed under GNU LGPLv3 only. The bundled Roboto and Chivo fonts remain under the SIL Open Font License; the subsetted Lucide icon font remains under Lucide's ISC license and the included Feather MIT terms. `Resources/LICENSE.txt` contains the applicable terms, attribution, copyright notices, and complete license texts in one place.

## Features

- Project-, current-region-, or time-selection-relative position
- Time, bars/beats, SMPTE timecode, absolute frames, seconds, or samples
- Whole-second display with no distracting tenths
- Current region plus separate next-region and next-marker cards
- Upcoming-item countdown and configurable warning threshold
- Region-mode blank, next-countdown, and overtime behavior between regions
- Zero- to twenty-row card grid with one to six cards per row
- Per-card Auto or one-to-six-unit widths inside each row's six-unit grid
- Small, Medium, Large, or Huge primary-clock sizing per Clock Face
- Drag-to-reorder Edit mode with card controls, live visualizations, and bottom-row add/remove actions
- Optional per-card auto-scroll for long text that would otherwise be ellipsized
- Built-in and user-created Clock Faces for instant layout switching
- Local system time, date, project name, transport, tempo, meters, Action Buttons, and custom templates
- Audio-system, project-statistics, and application/system information cards
- Scope length, signed remaining time, and progress
- Adaptive phase-accurate Visual Click card plus an optional perimeter pulse
- Persistent positive or negative calibration in milliseconds or samples
- Nine hand-tuned built-in styles, a custom palette editor, and an adjustable background gradient
- Bundled fonts plus an on-demand installed-font chooser
- Optional fixed-proportion or independent width/height resizing from approximately 360 × 250 through presentation size
- Floating, always-on-top, REAPER Docker, and true full-monitor borderless Presentation modes
- Independent resizable pop-out cards plus per-visualization fullscreen viewing
- Human-readable JSON settings with automatic backup and corruption recovery
- Optional idle fade for interface controls, with a quieter unfocused utility bar and immediate focus/hover recovery
- Factory Reset with confirmation

## Installation

### Via ReaPack (recommended)

ReaClock uses the same repository URL as ReaAssist and the other Michael Briggs REAPER tools:

1. Install [ReaPack](https://reapack.com) if it is not already installed.
2. In REAPER, open **Extensions > ReaPack > Import repositories...**.
3. Paste this URL and choose **OK**:

   ```text
   https://raw.githubusercontent.com/michaelbriggsaudio/mbriggs-reaper/main/index.xml
   ```

4. Open **Extensions > ReaPack > Browse packages...**.
5. Find **ReaClock**, right-click it, and choose **Install**.
6. Run **Script: ReaClock.lua** from REAPER's Action List.

With the default repository name, ReaPack installs the managed package source at the first path below. The first ReaClock launch automatically creates the active companion at the second:

```text
<REAPER resource path>/Scripts/mbriggs-reaper/ReaClock/
<REAPER resource path>/Effects/ReaClock/ReaClock_Meter.jsfx
```

### Manual

1. Keep the entire `ReaClock` folder together, including its `Resources` subfolder.
2. Place it inside the `Scripts` folder in your REAPER resource path.
3. Optionally copy `Resources/ReaClock_Meter.jsfx` to `<REAPER resource path>/Effects/ReaClock/ReaClock_Meter.jsfx`; otherwise ReaClock creates that active copy automatically on first launch.
4. In REAPER, open **Actions > Show action list**.
5. Choose **New action > Load ReaScript** and select `ReaClock.lua`.

The script header includes ReaPack `@provides` metadata for the README and every packaged support file under `Resources`, including the changelog, consolidated license, bundled fonts, and ReaClock Meter companion. ReaPack installs and updates that organized package layout; ReaClock silently deploys and repairs the active meter copy in REAPER's `Effects/ReaClock` folder. The small JSON settings codec is embedded directly in `ReaClock.lua` to keep the package compact.

## Main controls

- The clean bottom-right utility bar contains matching icons for **Presentation**, **Edit**, and **Settings**, leaving the visual focus at the top on the clock itself. Hovering an icon identifies it. Scope, base, Face, and Style controls appear at the top only when **Edit** is active; the pencil becomes a selected checkmark while editing.
- **Project / Region / Select** chooses the position origin. Region mode is completely blank outside regions by default. Select refers to the active time selection.
- **Time / Beats** switches the primary units. Right-click the large clock for every available time format or Beats.
- The **fullscreen icon** fills the current monitor with a borderless Presentation canvas and centers the complete undistorted face within it. Press it again, or press **Escape**, to return.
- The **Face** menu switches layouts instantly. It includes the built-in faces, the protected Custom scratch face, and any user-created faces. The active face is checked. **Save Current Face As…** creates and names a new face without leaving the clock.
- The **Style** menu previews each palette with live color swatches and applies it immediately. **Custom…** opens Settings directly to the Style page.
- **Edit** reveals every configured card without freezing or blanking live visualizations. Drag a card onto another to swap positions, press its small trash icon to remove it, or press the large **+** at the end of a row to append a card. Drag the left row grip to reorder whole rows. The explicit **Row N Size** control changes every card in the selected row; **Card N Width** assigns Auto or one to six grid units to the selected card. Default Auto widths stay visually quiet on the cards, while deliberate fixed widths display a small badge. The paired **+ ROW / − ROW** controls at the bottom add a new bottom row or remove the current bottom row; drag a different row to the bottom first when needed. Edit mode is intentionally off on every launch.
- In normal or Edit mode, double-click any card to open **Card Details**, its complete customization workspace. The searchable Type picker filters the entire content library as you type, including every numeric meter and visualization; source selection, custom text and tokens, font, discrete Height and Width controls, icon Alignment, title/scroll behavior, and reset all live in the same window. Reopening an existing editor raises it above the clock instead of leaving it hidden behind the main window.
- Right-click a card for the compact path to common changes. **Change Content** keeps its categorized library, while **Show card title**, **Auto-scroll long text**, **Alignment**, **Row Height**, and **Card Width** remain directly reachable. **Row** contains **Add New Row Above**, **Add New Row Below**, and **Remove Row**. **Pop-Out** can move the card out of the face or create a separate independent card. Visualization cards also offer **Fullscreen Visualization**. Meter cards add contextual **Meter Actions**.
- **Settings** opens the full configuration window. Press the same button again to close it. Settings and Card Details remain above the clock while open so clicking the main face cannot hide an auxiliary window behind it.
- Right-click unused clock background for the same Clock Face switcher without aiming for the Face control.
- Resize the floating window from either side or from a corner. **Automatically fit height to content** is enabled by default, so width drives height smoothly and every element scales uniformly. Turn it off in **Settings > Face > Window** to size width and height independently; ReaClock centers the complete undistorted face in the available space.
- The floating window automatically refits its height when the primary-clock size or visible rows change, so compact faces do not retain unused space. It also stays slightly smaller than the current monitor's work area: oversized saved windows and windows moved to a smaller monitor are reduced automatically without clipping the face. While playback, pause, or recording is active, enabled rows keep their footprint even if a live value becomes temporarily empty, preventing the wall clock from jumping at region boundaries.
- **Escape** first dismisses Presentation, a popup, an editor, Settings, or Edit mode. With none of those active, it closes ReaClock itself. **Alt+F4** remains the native window fallback.

When the main ReaClock window has focus, unmodified single-key shortcuts provide fast access: **E** toggles Edit, **P** selects Project scope, **R** selects Region scope, **S** selects the time selection, **T** selects Time, and **B** selects Beats. They are enabled by default and can be disabled in **Settings > Face** if they conflict with another workflow. Shortcuts are suspended while Settings, a card editor, a dialog, or a popup is active, so typing never changes the clock unexpectedly.

Markers are point cues rather than spans. A marker can appear only while it is ahead of the playhead. Regions can additionally provide current-region position, length, remaining time, and progress.

## Information cards

The default layout has three rows. Row 1 is a large **Current Region** card. Row 2 contains **Length**, **Remaining**, **Tempo**, and **Time Signature**. Row 3 gives **4/6** of its width to **Next Region** for longer song titles, with **Next Region Countdown** using the remaining **2/6**. Marker cards are available separately; Region is the fresh-install default.

Choose zero to twenty rows and one to six configured cards per row. Each row can use Small, Medium, Large, Huge, or Visualizer sizing, applied to every card in that row. The built-in Default face uses Large for its title row and Medium for its supporting rows. Hidden cards disappear completely in normal mode, remaining Auto cards reflow through the available width, fixed-width cards retain their chosen proportion, and a fully hidden row collapses out of the floating face while transport is stopped. During playback, pause, or recording, enabled cards retain their subtle surface and label while an unavailable live value stays blank, so region gaps and completed countdowns cannot resize the display mid-take. Edit mode temporarily shows every configured slot and row so it can always be reordered or removed. Removing the final card in a row removes that row from the face.

Every row is also a six-unit width grid. **Auto** cards divide all units left after fixed widths; a fixed card can reserve **1/6** through **6/6** when the other cards still have at least one unit each. For example, two cards set to **4/6** and **2/6** produce a wide title card and a narrower supporting card. Fixed cards intentionally leave unused space when their total is below six and no Auto card is present. ReaClock disables unavailable widths and the add-card control when the row's six units are fully assigned, so changing one card can never silently resize or delete another.

Long regular-text values use an ellipsis by default. Enable **Auto-scroll long text** from that card's right-click menu or detail editor to keep the full value readable: the card pauses at each end and travels across its overflow in no more than about 12 seconds. Numeric and mono cards continue to use stable shrink-to-fit behavior.

Direct card choices include:

- None
- Length, Remaining, or Current Position
- Tempo or Time Signature
- Current Region
- Next Region, Next Region Countdown, Next Marker, or Next Marker Countdown
- Transport Status, Project Name, or Project Title
- 12-hour system time, 24-hour system time, or system date
- Visual Click
- Action Button
- Sample rate, buffer size, bit depth, input/output/total latency, audio driver, and input/output device
- Available audio channels, connected MIDI devices, and the most recent audio/media underrun
- Track, media-item, selected-track, selected-item, marker, and region counts
- Open project tabs, project save status, and recording-disk free space
- Loudness, Peak, RMS, level, waveform, spectrum, spectrogram, vectorscope, and phase-correlation metering
- Custom Template

### Action Button cards

An **Action Button** runs one installed REAPER Main-section action or script per deliberate click, giving a Clock Face the same practical role as a custom toolbar in the main face, an independent pop-out, or full-monitor Presentation. Card Details accepts a numeric command ID or stable named command ID, and its searchable **Find action** field scans REAPER's installed native actions, custom actions, extension actions, and scripts. The button shows REAPER's current action name by default; **Button text** can replace it with a shorter label. Actions that publish a toggle state use ReaClock's selected-button treatment while on and return to their normal surface while off, updating live when their state changes anywhere in REAPER. Momentary actions retain ordinary click feedback.

Only the inset button surface runs the action. The first click used merely to focus an inactive ReaClock is ignored, dragging does not fire it, and a double-click cancels the pending action and opens Card Details instead. MIDI-editor-specific actions are intentionally excluded because they require a different section and editor context.

Custom templates can combine literal text with these tokens:

```text
{position} {length} {remaining} {region}
{next_region} {next_region_countdown} {next_marker} {next_marker_countdown}
{tempo} {timesig} {transport} {project} {project_title} {author}
{time12} {time24} {date} {scope} {units}
{sample_rate} {buffer_size} {bit_depth}
{input_latency} {output_latency} {roundtrip_latency}
{audio_mode} {input_device} {output_device}
{audio_inputs} {audio_outputs} {midi_inputs} {midi_outputs}
{audio_xrun} {media_xrun}
{track_count} {item_count} {selected_tracks} {selected_items}
{marker_count} {region_count} {project_tabs} {project_status}
{record_disk_free}
{lufs_m} {lufs_m_max} {lufs_s} {lufs_s_max} {lufs_i} {lufs_i_max}
{rms_m} {rms_m_max} {rms_i} {rms_i_max}
{sample_peak} {sample_peak_max} {true_peak} {true_peak_max}
{lra} {lra_max}
```

Unknown tokens remain visible as typed, making template mistakes easy to spot. Every card can follow the global alignment or override it with Left, Center, or Right for both its title and value, and can use Auto or a fixed six-unit width. A custom card can use the regular or mono font role. Selecting **Custom Template** opens a focused editor with a live preview, full-width label and template fields, a categorized token browser, display options, explanatory tooltips, and a clearly separated reset action. Adding any meter token reveals the same source workspace used by meter cards; the custom card then requests only the readings its template actually uses.

REAPER's public ReaScript API does not expose the Performance Meter's CPU and RAM readings in a portable way. ReaClock does not launch platform-specific commands or background pollers to synthesize those continuous readings; use REAPER's Performance Meter for CPU and RAM.

## Audio metering cards

Search the Card Details **Type** field for any numeric LUFS, RMS, Peak, or Loudness Range reading, or for Level Meters, Loudness History, Waveform, Spectrum Analyzer, Spectrogram, Vectorscope, or Phase Correlation. Every result is a direct choice rather than a generic Metering placeholder. The right-click **Change Content** menu offers the same library in compact **Metering** and **Visualizations** categories. Card Details keeps source setup and Display together in its left column, with Meter View, Meter Controls, and Project Cleanup in the right column; ordinary numeric and even full Spectrogram configurations fit without a scrollbar at their authored window sizes. Choosing a meter from the context menu opens source setup immediately. Choose the recommended entire-mix destination in Monitoring FX or the track currently selected in REAPER. That one choice verifies the companion, reuses an existing compatible instance when available, inserts the meter when needed, and binds the card automatically. If setup is dismissed, the card says **Choose a Source** and remains clickable. The card's right-click **Meter Actions** submenu provides **Change Meter Source…** and reset controls; **Customize Details…** remains at the root. ReaClock deploys and maintains the active companion at:

```text
<REAPER resource path>/Effects/ReaClock/ReaClock_Meter.jsfx
```

It does not modify REAPER's stock Loudness Meter. The companion is an input-only analyzer with no audio output pins: audio passes through the FX unchanged while the companion receives the source signal for analysis without producing or routing audio of its own. Its interface identifies it as a ReaClock companion and follows ReaClock's current background, text, and highlight colors while ReaClock is open. A Monitoring FX instance is intentionally persistent: REAPER keeps it across projects and restarts, and ReaClock reuses it rather than adding duplicates. It is safe to leave there. If ReaClock is no longer used, that Monitoring FX instance can be removed manually.

The companion's **Channels** selector defaults to **Auto**, which analyzes every channel the FX currently receives. Choose an explicit count to analyze only the first N channels. For example, choose **2** to monitor channels 1–2 while leaving an eight-channel Monitoring FX path available for unrelated routing. The menu never offers more than the host channel count reported to that FX instance, and the choice is saved with the FX.

ReaClock validates the active JSFX against the exact API, build, and content checksum required by that Lua release whenever ReaClock starts and before it adds a meter source. If the Effects copy is missing, older, or damaged, ReaClock silently restores it from the packaged `Resources/ReaClock_Meter.jsfx` copy; the existing source chooser remains the only setup prompt. Every online ReaClock Meter using an older build is then reloaded in place, including Monitoring FX, track, master, and input FX across all open project tabs. The reload preserves the FX identity, chain position, enabled state, saved settings, open-window state, and ReaClock card bindings. It resets that meter's integrated history and maxima so the updated DSP begins a fresh measurement, while audio continues to pass unchanged.

Reloading a project FX can cause REAPER to mark the affected project tab as modified, including a background tab. ReaClock never saves those projects automatically. A compatible same-API meter continues showing readings while its reload is pending or if the reload cannot be completed; **Meter Update Required** is reserved for a genuinely incompatible bridge. An instance that was already offline remains untouched, then ReaClock detects and reloads it after it is enabled. A newer valid companion is never downgraded. Instead, ReaClock reports inline that the Lua package must be updated through ReaPack. If the packaged repair copy is also unavailable or invalid, ReaClock leaves the existing file untouched and reports that ReaClock should be reinstalled or updated through ReaPack. This fallback also supports complete manually copied ReaClock folders, although ReaPack remains the recommended installation method.

Ordinary track meters are project FX. **Review Unused Track Meters…** in **Settings > Metering** or a Metering card editor opens a confirmation that removes only compatible track/master instances not referenced by the current layout, an independent pop-out, or any saved Clock Face. The action is undoable. It never removes Monitoring FX meters, and ReaClock never silently deletes project FX when a card is removed. The Metering Settings page remains available even when the current face contains no Metering cards.

Numeric choices include current/session and maximum readings for LUFS momentary, short-term, and integrated; loudness range; RMS momentary and integrated; sample Peak; and True Peak. LUFS-I, integrated/session readings, and maximum readings reset automatically when transport playback or recording starts by default. A card that supports manual reset shows a small circular-arrow icon in its upper-right corner; a single left-click anywhere on that card starts a fresh measurement period, while a double-click opens Customize without resetting it. The first click used only to focus an inactive ReaClock window is ignored. Reset is source-wide, so every card using that same meter begins the new period together.

Live display choices are **Level Meters**, **Loudness History**, **Waveform**, **Spectrum Analyzer**, **Spectrogram**, **Vectorscope**, and **Phase Correlation**. Each meter source can publish up to four distinct live visual views through the current companion API. Compatible cards share a view: ReaClock compares only settings that materially affect each demand, so a Waveform time span does not unnecessarily split a Spectrum card and an FFT size does not unnecessarily split a Waveform card. If a fifth distinct view is requested, the affected card shows **4 OF 4 VISUAL VIEWS** and its editor explains which channel, timing, FFT, or quality settings can be matched to an existing card. Numeric readings and Loudness History do not consume this four-view source budget.

**Auto** quality is the recommended default: one distinct live visual view runs at High, two run at Standard, and three or four run at Low. Quality changes analysis detail and source responsiveness: High respects the selected 1024–8192 FFT size with 512 source bins and 30 source updates per second, Standard caps analysis at 2048 points, and Low uses 1024-point analysis with reduced point counts and 10–20 updates per second. The explicit **Maximum - CPU intensive** option respects the selected FFT size while raising a single view to 1024 bins and 240 real overlapping FFT columns per second; its Spectrogram history can use a native 4096-column by 1024-row texture and it is intentionally never selected by Auto. At 8192 points this mode can consume much of one CPU core on some systems, while the fresh 4096 default is lighter. Fresh cards request 1024 Spectrogram bins, so Auto can apply its normal quality cap while switching to Maximum exposes the full vertical detail without another setting change.

Spectrogram cards expose the same primary controls shown in the supplied MiniMeters settings: **FFT Size** (1024, 2048, 4096, or 8192), **Frequency Scale** (Mel, Log, or Linear), **Mode** (Sharper, Sharp, or Classic), and **Tilt** (-12.00 to +12.00 dB). Fresh cards default to the supplied 4096 / Mel / Sharper / +4.50 dB configuration; 8192 remains available for extra frequency resolution. Maximum retains the companion's real overlapped FFT columns in an atomic history ring instead of inventing in-between frames, while fractional scrolling keeps motion smooth between display refreshes. Hidden cards, inactive project tabs, closed independent pop-outs, and closed ReaClock windows stop requesting visual frames, so the companion does no unnecessary FFT or waveform work. Lua draws already-prepared, bounded frames and never performs sample-rate DSP or FFT processing.

ReaClock is always bound to the currently selected project tab. Track and master meters in other open tabs are ignored even if those projects continue playing in the background. A card bound to another tab says **Source in Another Project** until that tab becomes active. Monitoring FX represents REAPER's global hardware-output path and is labeled separately from project tracks. If the selected tab is stopped while another tab plays, Output cards remain visibly in place but blank so they never present the background project's audio as data for the selected tab. Those readings remain associated with their source project if playback stops instead of leaking into another stopped tab. If the selected tab and another tab play together, Output cards instead report **Multiple Projects Playing** because the global hardware output contains both projects.

For multichannel sources, aggregate loudness, RMS, Peak, and True Peak readings consider every channel enabled by the companion's **Channels** selector; **Auto** retains the previous all-channel behavior. Loudness keeps the standard surround weighting and LFE treatment inherited from the Cockos meter. Level Meters can show every enabled channel as **CH 1**, **CH 2**, and so on. Pair-shaped views such as Vectorscope and stereo Correlation use the exact chosen channel pair. Spectrum Analyzer and other energy views can use either a named pair or an all-enabled-channel energy view. ReaClock does not guess speaker names, and it omits higher channels only when the companion has been explicitly limited.

### Removing ReaClock and its meter

Uninstalling ReaClock through ReaPack removes the script, its Action List entry, and the packaged `Resources` files. The active `Effects/ReaClock/ReaClock_Meter.jsfx` copy remains intentionally so existing Monitoring FX and saved project FX chains do not immediately break. If ReaClock and its meters are no longer needed, remove those FX instances and then delete the active companion file manually after closing REAPER.

For a manual installation, remove the script folder and the companion file yourself after closing REAPER. The optional `Data/ReaClock` folder contains only ReaClock settings and may also be deleted after REAPER is closed.

By default, direct Tempo and Time Signature cards disappear when REAPER grid lines are off. Disable **Hide Tempo and Time Signature cards when grid lines are off** in **Settings > Clock** to keep them visible. Explicit custom templates are never hidden by this automatic behavior.

## Settings

- **Clock** - grid-aware tempo cards, between-region behavior, warning threshold, and Factory Reset
- **Face** - main-clock/progress visibility, zero-to-twenty-row structure, per-row card count and size, docking, always-on-top behavior, and focused-window keyboard shortcuts
- **Metering** - ReaPack companion status, active-project/global-source summary, and unused ordinary-track cleanup even when no Metering card exists
- **Click** - perimeter click, activation rule, pulse decay, and flash intensity
- **Style** - nine built-in palettes, 0-100% canvas/card gradient strength (100% by default), 0-100% card opacity (50% by default), an optional local background image with opacity, global fallback alignment, custom colors, contrast readout, installed fonts, weights, and global font sizes
- **Calibration** - signed offset in milliseconds or samples

Factory Reset deletes ReaClock's complete owned settings container and automatically reopens the script through the same initialization path as a fresh install. This clears every preference, Clock Face, card, font, color, offset, docking choice, window position and size, recovery backup, and any future saved setting without relying on a hand-maintained reset list. It requires a second confirmation. Meter FX instances remain in REAPER because they belong to project or Monitoring FX chains rather than ReaClock's preference data.

## Clock Faces

ReaClock includes **Default**, **Minimal**, **Metering**, **Visualizations**, and **Visual Click** faces. **Metering** gives LUFS-I the dominant position, adds LUFS-I Max, LUFS-S, True Peak Max, and Loudness Range, then supports them with Loudness History and Level Meters. **Visualizations** combines Spectrum, Level Meters, Waveform, Vectorscope, Spectrogram, and Loudness History with compact LUFS-I and LUFS-S readings. The visualization cards in that face share compatible source streams so the richer layout does not request duplicate audio data unnecessarily.

The first time either audio-focused face is selected, ReaClock asks for one source and connects every card in that face to it. That preferred source is remembered for both built-in audio faces; if it belongs to a different project tab later, ReaClock asks again rather than polling the inactive project. **Custom** is a protected scratch layout that is always available. Changing a built-in face automatically moves the edited result to Custom, leaving the built-in canonical layout untouched; choosing that built-in again restores its original layout. Use **Save Current Face As…** in the main Face menu to create a named user face; the same menu renames or deletes the selected user face.

A face stores main-clock visibility and size, row sizes, card order and widths, and progress visibility. Clock basis, colors, fonts, calibration, docking, and window geometry remain global so switching faces never unexpectedly changes timing or the monitoring setup. Changes to the active face save automatically.

## Styles

The built-in styles are **Dark**, **Light**, **Sunny**, **Cool**, **Rainbow**, **Forest**, **Midnight**, **Rose**, and **Pitch Black**. **Midnight is the first-run and factory-default style.** Each has its own coordinated canvas, cards, controls, labels, progress track, and rotating card accents rather than changing only three colors. Pitch Black uses a true black background and deliberately subdued monochrome text for late-night work. Custom styles derive the supporting interface colors from the background, text, and highlight anchors edited in Settings.

**Background Gradient** controls the depth of both the canvas and cards from flat at 0% to pronounced at 100%; the default is 100%. **Card Background Opacity** runs from text-only at 0% to solid at 100%, with a photo-friendly 50% default. Double-click either slider to restore its default.

ReaClock can display a local PNG or JPEG behind the interface. It saves only the file path, center-crops the image to cover the current face, and falls back to the normal style background if the file is unavailable. The Default Face design canvas is **918 × 564 px** when all three default rows are visible; other faces and hidden rows can change the height. Image opacity defaults to 12%, is capped at 50% for legibility, and also resets on double-click. ReaClock ships with no background photos.

## Visual click and calibration

The Visual Click card is derived from REAPER's current musical phase on each rendered frame, so dropped graphics frames cannot make it drift. At narrow widths it shows a large beat number and pulse. Wider cards add the current place in the bar: individual segments for practical meters and a continuous rail for very large numerators. It follows arbitrary time signatures rather than imposing a fixed beat limit.

An optional perimeter pulse uses the same phase source without covering the clock. Downbeats are brighter and stronger. Click animation can activate whenever transport plays, only while grid lines are visible, or only while REAPER's metronome is enabled; the card continues to identify the current beat when animation is inactive.

A positive calibration offset advances the display; a negative value delays it. The same offset is applied to the primary clock, region transitions, countdowns, and visual click. Sample-based offsets use the active project/device sample rate.

## Window modes

- **Floating** remembers its last size and screen position. Automatic height fitting preserves the authored landscape proportion; disabling it allows independent width and height while keeping the complete face undistorted and centered.
- **Always on top** keeps the floating clock above other windows.
- **REAPER Docker 1-16** places ReaClock in a selected docker. The face centers and uses the largest landscape rectangle that fits; enlarge a shallow docker to make the clock readable.
- **Presentation** removes window chrome, covers the current monitor edge-to-edge, and stays on top. The complete face remains undistorted and is centered over a continuous styled background, including the selected gradient and optional background image. When vertical room remains, drag anywhere outside the three utility controls and any Action Button to place the face from top to bottom; ReaClock remembers that relative position across monitors. Use the fullscreen icon or **Escape** to leave Presentation.
- **Independent pop-outs** are first-class cards with their own saved position, size, content, source, and formatting. **Move to Pop-Out** removes the face copy; **New Pop-Out Card…** creates one without adding anything to the face; **Return to Face** uses an empty slot first and otherwise appends to the first row with room. Closing a pop-out preserves it in the clock's **Pop-Out Cards** menu, while Remove deletes it. ReaClock disables moves at the 32-card limit and shows a visible notice if a queued pop-out action cannot be completed or a full face has no room for a returning card.
- A visualization's small maximize button opens the same live card fullscreen on its current monitor; it does not create or persist a duplicate. Press the button again or **Escape** to return.

## Fonts and portability

Roboto Regular/Bold and Chivo Mono Regular 400 are bundled so the default face remains consistent without an internet connection or system font installation. A small subsetted Lucide font supplies ReaClock's interface icons; it is fixed UI infrastructure and does not appear in the user font chooser.

The font choosers scan standard Windows, macOS, and Linux font folders only when a chooser is opened. Results stay in memory until **Rescan** or restart and are never written to disk. Each `.ttf`, `.otf`, or `.ttc` face is listed separately, allowing installed Light, Medium, Semibold, and other faces to be selected directly. An advanced family/file field remains available for unusual installations.

An installed font name or absolute file path is local to that computer. Use the bundled defaults or generic families when sharing settings across operating systems.

## Saved settings

ReaClock stores persistent choices in:

```text
<REAPER resource path>/Data/ReaClock/settings.json
```

The file is formatted, structured JSON so Clock Faces and future options remain maintainable. The codec is embedded in `ReaClock.lua`; no separate JSON library is installed. On first run, or after the settings file is deleted, ReaClock immediately creates a fresh file from the current defaults. Later writes are debounced and use `settings.json.bak` as an automatic recovery copy. If the primary file is malformed, ReaClock loads the backup when possible, preserves the invalid source as `settings.json.corrupt`, and reports the recovery in Settings. ReaClock starts with its current settings schema and does not import settings from other clock scripts.

Saved values include clock modes, cue behavior, every Clock Face and card template, click behavior, calibration, theme, fonts, docking, and floating-window geometry. Edit mode and installed-font scan results are memory-only. ExtState is retained only for the running-instance guard and private deterministic test override.

## Bundled third-party licenses

- `Resources/LICENSE.txt` contains ReaClock's original-software terms; the ReaClock Meter attribution and source lineage; the complete LGPLv3 and GPLv3 texts; the Roboto and Chivo copyright notices and complete SIL Open Font License version 1.1; and Lucide's complete ISC and Feather MIT notices.
- `Resources/Roboto-Regular.ttf` and `Resources/Roboto-Bold.ttf` remain under the SIL Open Font License version 1.1 with the Roboto Project's copyright notice.
- `Resources/ChivoMono-Regular.ttf` remains under the SIL Open Font License version 1.1 with the Chivo Project's copyright notice.
- `Resources/lucide.ttf` is subsetted from `lucide-static` 1.24.0 and remains under Lucide's ISC license plus the included MIT terms for Feather-derived icons.
