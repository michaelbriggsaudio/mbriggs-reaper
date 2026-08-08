<!-- REAASSIST_PLUGIN_PACK_FORMAT:2 -->
<!-- GENERATED FILE. Edit private Dev/Plugin Profiles sources, then rebuild. -->
<!-- metadata_layout:split-route-validate -->
<!-- profile_schema:2 -->
<!-- builder_version:2 -->
<!-- builder_script_sha256:826244e628ed2129115bb5c6b7320cbe77c63f17a50ffb87b50f1c2292608818 -->
<!-- section_count:66 -->
<!-- source_set_sha256:b09e29742a799f06433c45275ff1d2bc9e393ec13edf369b40fbe90b2824de63 -->
<!-- stoplist_version:1 -->
<!-- aggregate_injected_limit_bytes:98304 -->
<!-- pack_revision:fd5bedc2e019034f8a7e974fe6d7a445dde031d9d41faba72141e4bf0ccc655d -->
<!-- Plugin_Pack.md - markers are PLUGIN:Name (NOT SECTION:) because each block -->
<!-- is a typed, addressable plugin entry served as plugin_ref:Name. SECTION: -->
<!-- is reserved for generic on-demand buckets in API_Ref.md / Prompts.md.    -->
<!-- The two markers are deliberately distinct so the parser can tell plugin -->
<!-- entries apart from the ## sub-headings inside each plugin's body.       -->

# Plug-in Parameter Reference

This pack supplies optional Model guidance for preferred-product routing,
exact identities, verified controls, value conversions, product constraints,
musical intent and concise standard Lua examples.

Use the exact installed plug-in identity and standard REAPER APIs. Prefer live
control names and formatted values from the current instance. Certified
positions, normalized values and formulas may guide the generated Lua for the
matching product and format. They do not authorize a different product or
version, and missing or changed guidance must not block ordinary Lua using live
discovery.

## ENUM VALUES: LIVE DATA OVERRIDES CURATED TABLES

Curated enum tables and recipe literals are stamped against a specific plug-in
version. Vendors can reorder choices across updates, so the same normalized
value may select a different label in another version.

When setting an enum control:

1. Prefer the exact live labels reported by the current plug-in instance.
2. Use the matching certified table only when live enum data is unavailable.
3. Treat recipe literals as examples whose named intent must remain clear.

Name the intended enum label in a nearby Lua comment so the setting remains
reviewable if the plug-in changes later.

## FALLBACK CHAINS

This block is the **single source of truth** for plugin preference routing.
One line per type with two halves separated by `||`:

- **Left of `||` (auto-assign chain):** Candidates walked at script load
  (and after bundled installs). First installed wins, gets written to the
  user's preferred plugins, appears on the Preferred Plugins page. Only
  high-quality third-party picks belong here -- entries here silently
  commit the user without asking.

- **Right of `||` (stock fallback):** Offered by the resolve popup as a
  one-click "Use X instead" button when no chain entry is installed and
  the model asks for a generic plugin. **Never auto-assigned, never saved
  to the user's preferences.** Uses this turn only; the popup fires again
  next time. Users who want a stock plugin permanent must set it on the
  Preferred Plugins page themselves.

Each entry may have an optional display alias in `[brackets]` -- used as
the button label for stock fallbacks (e.g. `JS: Liteon/deesser [JSFX De-esser]`
shows as "Use JSFX De-esser instead").

Entries are format-agnostic (no `VST3:` / `VST:` / `AU:` / `CLAP:` prefix).
The resolver tries formats in order `VST3 > VSTi > VST > AU > CLAP`. JSFX
entries use the full relative path (e.g. `ReJJ/ReEQ/ReEQ.jsfx`, or `JS:` prefix
for stock JSFX under `Effects/`).

Fallback-chain entries are not automatically certified parameter references.
Use a `PLUGIN:Name` section only for the exact matching product and format. If
an installed fallback has no matching marker, use its resolved identity and
ordinary live discovery. Never borrow another version's stored positions,
normalized values or formulas.

Edit chains freely to add other preferred plugins. Plugin type keys match
ReaAssist's preferred-plugins types (lowercase, underscored). Types may
have an empty chain (`type: || stock`) for stock-only types.

```chains
# Format: type: chain1 | chain2 | ... || stock-fallback [optional alias]

eq:                   Pro-Q 4 | Pro-Q 3 | Pro-Q 2 | ReJJ/ReEQ/ReEQ.jsfx || ReaEQ
compressor:           Pro-C 3 | Pro-C 2 | Pro-C || ReaComp
multiband_compressor: Pro-MB || ReaXcomp
limiter:              Pro-L 2 | Pro-L || ReaLimit
reverb:               Pro-R 2 | Pro-R || ReaVerbate
delay:                Timeless 3 | Timeless 2 || ReaDelay
gate:                 Pro-G || ReaGate
synth:                Twin 3 | Twin 2 || ReaSynth
deesser:              Pro-DS || JS: Liteon/deesser [JSFX De-esser]
saturation:           Saturn 2 | Saturn || JS: LOSER/Saturation [JSFX Saturation]
chorus:               || JS: SStillwell/chorus_stereo [JSFX Chorus]
phaser:               || JS: Guitar/phaser [JSFX Phaser]
pitch_correction:     || ReaTune
pitch_shift:          || ReaPitch
```

---

<!-- NOTE: this FabFilter intro sits OUTSIDE the PLUGIN blocks, so it is     -->
<!-- never served to the model (Context.lua slices PLUGIN blocks only).      -->

# FabFilter third-party plugins

FabFilter's Pro series is a high-quality commercial plugin suite. ReaAssist
auto-prefers installed FabFilter plugins over stock equivalents (see
FALLBACK CHAINS). The identity guidance was verified against the formats named
inside each profile. Do not assume VST3, VST2, AU and CLAP identities are
interchangeable. When preferred_plugins or a preempt header provides an exact
format-prefixed AddByName identifier (for
example "VST3: Pro-G"), use that exact identifier. Do not strip the prefix and
do not add a vendor suffix. Bare names are reference labels only and may fail
on some installs. Use the matching guidance as an optional generation aid, and
prefer exact live control names and formatted values when they are available.

<!-- PLUGIN:Auto-Key 2 -->
<!-- SECTION-REVISION:2eb70d4dc13d5a6cc2eb5a6bec8fdb77a2799d9fa9be03de5b64e0e9cc69d926 -->
## Auto-Key 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"auto-key-2","display_name":"Auto-Key 2","vendor":"Antares","product_class":"ordinary","preference_type":"key_detection","identifiers":{"add_by_name":["VST3: Auto-Key","VST3: Auto-Key (Antares)"],"aliases":["Auto-Key","AutoKey","Auto-Key 2","AutoKey 2"],"curated":["Auto-Key 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["autokey"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"auto-key-2","safety":{"settle_ms":250,"heavy_selectors":["Key/Scale"],"unsafe_to_sweep":["Send","Key/Scale"],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Auto-Key","loaded_name":"VST3: Auto-Key (Antares)","parameter_count":{"mode":"exact","value":6},"required_parameters":[{"index":0,"name":"Master Bypass","section":"","section_required":false},{"index":1,"name":"Send","section":"","section_required":false},{"index":2,"name":"Key/Scale","section":"","section_required":false},{"index":3,"name":"Bypass","section":"","section_required":false},{"index":4,"name":"Wet","section":"","section_required":false},{"index":5,"name":"Delta","section":"","section_required":false}],"observed_fingerprint_sha256":"eb4f145f69ed061de472e29609ae8ef6a431378afd869dfcac653b24297fa5d5"}],"status":"pilot","provenance":{"source":"Auto-Key 2 isolated live campaign","migrated_at":"2026-07-29","body_sha256":"c21ce2e73894681aefbe8c1a17113fe9515c5c7214f263d83a9a781ba00e485a","verified_at":"2026-07-29","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"82ff612e91d34bbbbf85c8a575a31b824df63b252fdc6ab804edf1c56f426251","binary_sha256":"18ee9bf73520c37ed6c02aa697bda2d5dc3da89c9130e2f6785d876b9e086ab3"}}
```

<!-- CHUNK:control -->
AddByName string: `VST3: Auto-Key`

The fingerprinted Auto-Key 2 VST3 build exposes six parameters:

```
idx  Name           Default     Automation policy
---  -------------  ----------  ---------------------------------------------
0    Master Bypass  Off         preserve
1    Send           Off         guarded momentary action only
2    Key/Scale      Chromatic   manual-mode selector; never detection readback
3    Bypass         normal      preserve
4    Wet            100         preserve
5    Delta          normal      preserve
```

Resolve every target by index, exact live name and explicit empty section before
any write. `Send` is the only Auto-Key parameter that ReaAssist may automate.
Never write or sweep `Key/Scale`: the host parameter can remain `Chromatic`
while Auto-Key's interface shows a finalized detected result. Never write
Master Bypass, Bypass, Wet or Delta during key detection or transfer.

Use Auto-Key on the master only after explicit approval to add or reuse it,
start playback and move the transport. Before playback, identify vocal-only
tracks that feed the master and temporarily mute them so uncorrected singing
cannot bias detection. Record every prior mute state and restore it exactly on
success, failure or cancellation. Do not mute a mixed track that also contains
useful harmonic music without explaining that consequence and asking how to
proceed. Preserve and restore the prior transport state and position.

Auto-Key 2 provides Listen, File and Manual detection modes. Listen is the
default. Use Listen on a representative, harmonically stable music section for
30 seconds by default. Never stop before 5 seconds unless the user cancels.
Tempo detection may need the full 30-second window. Analyze another 30-second
stable section when the song modulates, the result is uncertain or the primary
and relative major or minor choices are both plausible. Stop Listen to finalize
the result.

File mode analyzes an entire user-selected `.mp3`, `.flac`, `.wav` or `.aiff`
file and may run from Auto-Key on any track. Offer File mode when the user has a
clean music file and wants whole-file analysis. Manual mode is appropriate only
when the user already knows the key and scale. ReaAssist must not automate
Auto-Key interface clicks, file selection, drag and drop or relative-key swap.
Ask the user to confirm the finalized Key/Scale in the Central Display,
including the relative alternative, before any Send. Treat Reference Frequency
and tempo as display information; Send transfers Key and Scale only.

`Send` is project-wide broadcast behavior, not a one-instance target. Before a
scripted Send, enumerate every top-level normal and input AutoTune FX instance
across every open project tab. Disclose the receiver count, locations and the
confirmed key and scale, then obtain explicit approval for that exact scope. If
the user intends one receiver while another AutoTune instance exists, do not
use Send. Apply the confirmed Key and Scale directly to the chosen validated
AutoTune instance under its own profile instead. Use the same direct fallback
when an FX container could hide a receiver, any receiver lacks a validated
AutoTune profile receipt or an AutoTune instance exists in another project tab.

Auto-Key Send is internal Antares plug-in communication. It is not a REAPER
track send and does not require audio routing, MIDI routing or a new REAPER
send. Never create or change REAPER track sends for this operation. Once the
user has confirmed Key/Scale and explicitly approved the disclosed receiver
scope, generate and run the guarded Lua action in the current response. Do not
ask an audio-versus-MIDI routing question, refer to a previous script without
including executable code or stop at a prose description.

For an approved automatic Send request, the response must contain a fenced
`lua` block with the complete customized action. Put that executable block
before any explanatory prose. A prose-only response is incomplete.

AutoTune must have its Auto-Key Key/Scale reception setting enabled. ReaAssist
does not change that preference. If transfer verification fails, leave Send
Off, report that the receiver may not be enabled and offer the validated direct
Key and Scale fallback after approval.

The installed Auto-Key build ignores an immediate On/Off pair. A reliable Send
holds On for 500 ms and then returns Off. Never implement this with a busy wait,
a pasted sleep loop, nested generated `reaper.defer` calls or a persistent
watcher. Use the guarded runtime helper
`reaassist_schedule_autokey_send_reset`. It schedules the 500 ms reset, keeps
the action pending, turns Send On, verifies the pulse, returns Send Off and
verifies every disclosed AutoTune receiver reached the user-confirmed Key and
Scale. It also rejects changed receiver counts, receivers in another project
tab, FX containers and unvalidated receiver mappings. Never write Send On
separately after calling the helper.

For one already-disclosed and approved AutoTune receiver, use this exact shape.
Replace only the track and FX lookup details plus the confirmed key and scale.
Resolve the Auto-Key Send mapping and every receiver's AutoTune Key and Scale
mapping before scheduling the reset or writing Send:

```lua
local project = reaper.EnumProjects(-1)
local master = reaper.GetMasterTrack(project)
local auto_key_fx = reaper.TrackFX_GetByName(
  master, "VST3: Auto-Key", false)
local vocal = reaper.GetTrack(project, 0) -- previously disclosed receiver track
local auto_tune_fx = reaper.TrackFX_GetByName(
  vocal, "VST3: AutoTune", false)
if not master or auto_key_fx < 0 or not vocal or auto_tune_fx < 0 then
  error("The approved Auto-Key or AutoTune receiver is unavailable")
end

reaper.defer(function()
  local send_map, send_err = reaassist_resolve_profile_params(
    master, auto_key_fx, {
      { index = 1, name = "Send", section = "" },
    })
  if not send_map then error(send_err) end
  local tune_map, tune_err = reaassist_resolve_profile_params(
    vocal, auto_tune_fx, {
      { index = 5, name = "Key", section = "" },
      { index = 6, name = "Scale", section = "" },
    })
  if not tune_map then error(tune_err) end

  local scheduled, schedule_err = reaassist_schedule_autokey_send_reset(
    master, auto_key_fx, send_map[1], 500, 1, {
      {
        track = vocal,
        fx = auto_tune_fx,
        key_index = tune_map[1],
        scale_index = tune_map[2],
        expected_key = "C",
        expected_scale = "Major",
      },
    })
  if not scheduled then error(schedule_err) end
end)
```

For multiple approved receivers, add one receiver record per instance, resolve
each Key and Scale mapping first and pass the exact approved receiver count.
Never pass a subset. Do not combine Send with correction-style parameter
changes in the same action. After a verified transfer, apply natural or hard
correction settings as a separate AutoTune-profile action so scope and Undo
behavior remain clear.

Tell the user when ReaAssist added Auto-Key and offer to bypass or remove that
new instance after detection. Never remove, bypass or alter a pre-existing
Auto-Key instance without separate approval.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Choose stable harmonic material rather than isolated vocals, drums or
percussion. Treat one short result as advisory because Auto-Key can identify a
locally dominant or relative key that does not describe the whole song. Confirm
the final key and scale with the user before sending it to AutoTune. If the
result remains uncertain, ask for the song key again and use Chromatic only
when the user says they do not know.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Auto-Key 2 -->

<!-- PLUGIN:AutoTune -->
<!-- SECTION-REVISION:d89a8cc069524dad933de142f18254f14cb2841cb769d00291138a48a4f35993 -->
## AutoTune

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"autotune","display_name":"AutoTune","vendor":"Antares","product_class":"ordinary","preference_type":"pitch_correction","identifiers":{"add_by_name":["VST3: AutoTune","VST3: AutoTune (Antares)"],"aliases":["AutoTune","Auto-Tune"],"curated":["AutoTune"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["autotune"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"autotune","safety":{"settle_ms":250,"heavy_selectors":["Key","Scale","Vocal Range"],"unsafe_to_sweep":["AutoKey Listen","Note C through Note B"],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: AutoTune","loaded_name":"VST3: AutoTune (Antares)","parameter_count":{"mode":"exact","value":27},"required_parameters":[{"index":0,"name":"Master Bypass","section":"","section_required":false},{"index":2,"name":"Retune Speed","section":"","section_required":false},{"index":5,"name":"Key","section":"","section_required":false},{"index":6,"name":"Scale","section":"","section_required":false},{"index":19,"name":"Detune","section":"","section_required":false},{"index":23,"name":"Pitch Tracking","section":"","section_required":false}],"observed_fingerprint_sha256":"28cee950d98c47b9aacd4a5d8b29fa025e33e5db87bf30bc5a1d867ee9e07bb4"}],"status":"pilot","provenance":{"source":"AutoTune 1.1.0.1244 isolated campaign","migrated_at":"2026-07-29","body_sha256":"1af3e32bab2e58d68275e6d52298eca37f7de66c3caa5b2051f3ecb4579d79f7","verified_at":"2026-07-29","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"8825000ed916db5a86560b88e08ff4f8c3bd3474fa77125170b2aad23686b3f1","binary_version":"1.1.0.1244","binary_sha256":"9307502d768873a9f8bb86b7f0bba90cb85b751d389b46ed0e0bb77a83abd79e"}}
```

<!-- CHUNK:control -->
AddByName string: `VST3: AutoTune`

The fingerprinted AutoTune 1.1.0.1244 VST3 build exposes 27 parameters. Use
the stored indices only as fingerprint anchors and resolver hints. Resolve every
target by index, exact live name and explicit empty section before any write.

Primary controls:

```
idx  Name            Default       Type and safe write strategy
---  --------------  ------------  -------------------------------------------
2    Retune Speed    20            numeric display; set_param_display
3    Humanize        0             numeric display; set_param_display
4    Flex Tune       0             numeric display; set_param_display
5    Key             C             enum; set_param_enum
6    Scale           Chromatic     enum; set_param_enum
19   Detune          440.0         numeric display; set_param_display
20   Latency Mode    Low Latency   enum; set_param_enum
21   Algorithm       Modern        enum; set_param_enum
22   Vocal Range     Alto/Tenor    enum; set_param_enum
23   Pitch Tracking  50            numeric display; set_param_display
```

Retune Speed has a descending normalized-to-display relationship in this build.
Never derive or guess a normalized formula. For an arbitrary displayed target,
use the canonical direction-aware `set_param_display` helper and verify the
final host-formatted display. The same rule applies to Humanize, Flex Tune,
Detune and Pitch Tracking.

The exact natural-correction recipe below uses fingerprinted normalized
literals that were verified against their final host displays. Do not reuse
those literals on another AutoTune fingerprint.

Correction intent uses the displayed AutoTune values below. Never interpret
these as normalized positions or reverse their meaning:

- Natural correction: Retune Speed `100`, Humanize `20`, Flex Tune `20`.
- Hard tuning: Retune Speed `0`, Humanize `0`, Flex Tune `0`.

The natural triplet is the default for requests such as natural, transparent,
polished or subtle correction. The hard-tuning triplet is the default for
requests such as hard tune, robotic, obvious or stylized correction. Vocal
Range defaults to `Alto/Tenor` unless the user explicitly requests another
range. Every AutoTune correction must keep Latency Mode at `Low Latency`.

A musical key is required before tonal correction. If the user did not specify
the key, ask for the song key, including major or minor when applicable, before
making any project change. Do not guess the key from the track name, session or
audio. If the user says they do not know the key, use Scale `Chromatic`, preserve
all twelve individual note enables and continue with the requested natural or
hard correction triplet.

Before falling back to Chromatic, request `fx_list:Auto-Key` to check whether
Auto-Key 2 is installed. If the installed list contains Auto-Key, offer to add
or reuse it temporarily on the master track for detection. This is an offer,
not permission: wait for explicit user approval before adding an effect,
starting playback or changing transport position. Use only the exact
format-prefixed AddByName identifier returned by `fx_list`; never assume the
local Windows identifier on another system.

After approval, reuse an existing master-track Auto-Key instance when present.
Otherwise add it to the master track with the exact installed identifier and
check the AddByName result immediately. Before playback, identify vocal-only
tracks that would feed the master during detection. Temporarily mute them so
uncorrected or out-of-key singing cannot bias Auto-Key. Record each track's
prior mute state and restore every state exactly when detection ends, including
failure or cancellation. Do not mute a mixed track that also contains useful
harmonic music without telling the user that the music would be removed from
the analysis and asking how to proceed. Preserve the prior transport state and
position, then restore both on success, failure or cancellation.

Open Auto-Key's interface and use Listen on a representative, harmonically
stable section rather than an isolated vocal, drums or percussion. Run Listen
for 30 seconds by default. Never stop before 5 seconds unless the user cancels.
Analyze at least one additional 30-second stable section when the song
modulates, the result is uncertain or the primary and relative major or minor
choices are both plausible. Treat one short result as advisory. Auto-Key can
identify a locally dominant or relative key that does not describe the whole
song.

Stop Listen to finalize the result and ask the user to confirm the key and
scale shown in Auto-Key, including its relative major or minor alternative.
The verified Auto-Key 2 host `Key/Scale` parameter can remain `Chromatic` while
the interface shows a finalized detected result. That parameter is the Manual
mode selector, so never treat it as detection readback. The normal ReaAssist
flow must not automate clicks in Auto-Key's interface.

The live certification dependency had loaded name `VST3: Auto-Key (Antares)`,
six parameters and exact parameter names `Master Bypass`, `Send`, `Key/Scale`,
`Bypass`, `Wet` and `Delta` at indices 0 through 5. The AutoTune profile receipt
does not authorize an Auto-Key parameter write. Script Send only when the
separately validated Auto-Key 2 profile receipt is present, after following its
project-wide receiver disclosure, approval, timing and verification rules.

After the user confirms the result, apply the confirmed Key and Scale directly
to a chosen fingerprint-validated AutoTune instance when the intended scope is
smaller than every compatible receiver in the project. Use the guarded
Auto-Key 2 Send action only after the user approves its disclosed project-wide
scope. Verify both receiver displays before applying correction settings as a
separate AutoTune action. One Undo for that correction action must restore its
complete pre-action AutoTune state and Redo must restore the correction. Never
claim that ReaAssist can Undo a user's manual Auto-Key click. If detection
produces no convincing result, ask the user for the key again and use Chromatic
only when the user says they do not know.

Tell the user that Auto-Key was added to the master and offer to bypass or
remove a newly added instance after detection. Never delete, bypass or alter an
Auto-Key instance that was already in the project without separate approval.

Key, Scale and Vocal Range are discrete selectors. For arbitrary targets, use
`set_param_enum` with the exact live API label. Never infer a normalized
position from a list or write a raw normalized guess. AutoTune reports `A#`
during the Key sweep but settles to the host-formatted display `Bb`. Use the
verified direct Key mapping below for B-flat to avoid that readback timing
difference. Use `set_param_enum(..., "Minor")` for the Scale selector.

Critical B-flat rule: do not call `set_param_enum` for the Key with `"Bb"`.
The immediate API list contains `A#` and no `Bb`, even though the settled host
display is `Bb`. For this fingerprint, the direct `mapped[4]` write in the
recipe is preferred. If a generic repair still uses the enum helper for Key,
its target must be `"A#"`, followed by the verified direct `mapped[4]` write.

For a natural, transparent B-flat minor request, use this exact recipe after
locating the track and existing AutoTune instance. Resolve all twelve
targets before the first write:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 2, name = "Retune Speed", section = "" },
  { index = 3, name = "Humanize", section = "" },
  { index = 4, name = "Flex Tune", section = "" },
  { index = 5, name = "Key", section = "" },
  { index = 6, name = "Scale", section = "" },
  { index = 20, name = "Latency Mode", section = "" },
  { index = 22, name = "Vocal Range", section = "" },
  { index = 9, name = "Note D", section = "" },
  { index = 11, name = "Note E", section = "" },
  { index = 14, name = "Note G", section = "" },
  { index = 16, name = "Note A", section = "" },
  { index = 18, name = "Note B", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.341796875) -- 100
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.203125) -- 20
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.203125) -- 20
reaper.TrackFX_SetParamNormalized(
  tr, fx, mapped[4], 0.8650000095367432) -- Bb
local ok, err = set_param_enum(tr, fx, mapped[5], "Minor")
if not ok then error(err) end
reaper.TrackFX_SetParamNormalized(
  tr, fx, mapped[5], 0.10999999940395355) -- commit settled Minor state
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0) -- Low Latency
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.25) -- Alto/Tenor
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.0) -- derived Note D
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0) -- derived Note E
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.0) -- derived Note G
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0) -- derived Note A
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.0) -- derived Note B
```

The final Scale write repeats the verified Minor value after the enum helper.
Only `mapped[5]` is the Scale helper target in this recipe. Never replace the
direct `mapped[4]` Key write with `set_param_enum(..., "Bb")`.
AutoTune can delay its derived note-state update after the helper sweep until
undo, redo or reload. The five exact note writes commit only the states that the
Bb natural-minor scale derives: D, E, G, A and B are Removed. Do not use this
derived-note recipe for another key or scale. The settled host displays for
this recipe must be Retune Speed `100`, Humanize
`20`, Flex Tune `20`, Key `Bb`, Scale `Minor`, Latency Mode `Low Latency` and
Vocal Range `Alto/Tenor`. For any different target,
resolve every requested parameter first and use the general display or enum
helper rules above. Check every helper result and stop on failure. Preserve
every unrequested control.

AutoKey Listen, Detune, Algorithm, Master Bypass, host Bypass, Wet, Delta and
individual note enables stay unchanged unless the user explicitly requests them
or the exact fingerprinted B-flat natural-minor recipe above is being applied.
Every correction keeps Latency Mode at `Low Latency`. Vocal Range defaults to
`Alto/Tenor` when the user does not name a different range. For every other
normal major or minor scale request, use the Scale selector and preserve the
individual note enables.

For hard tuning with a Chromatic fallback on this exact fingerprint, resolve
all six targets before the first write and use this direct recipe:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 2, name = "Retune Speed", section = "" },
  { index = 3, name = "Humanize", section = "" },
  { index = 4, name = "Flex Tune", section = "" },
  { index = 6, name = "Scale", section = "" },
  { index = 20, name = "Latency Mode", section = "" },
  { index = 22, name = "Vocal Range", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 1.0) -- Retune Speed 0
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.0) -- Humanize 0
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0) -- Flex Tune 0
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0) -- Chromatic
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 1.0) -- Low Latency
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.25) -- Alto/Tenor
```

The settled host displays must be Retune Speed `0`, Humanize `0`, Flex Tune
`0`, Scale `Chromatic`, Latency Mode `Low Latency` and Vocal Range
`Alto/Tenor`. Preserve the Key selector and all twelve note enables while the
Scale is Chromatic. Do not reuse these normalized literals on another
fingerprint.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For natural, transparent, polished or subtle vocal correction, use displayed
values Retune Speed `100`, Humanize `20` and Flex Tune `20`. Default Vocal Range
to `Alto/Tenor` unless the user names another range. Keep Latency Mode at
`Low Latency`. If the user did not provide a key, ask before making changes. If
the user says they do not know it, use Scale `Chromatic` and preserve every
individual note enable.

For hard, robotic, obvious or stylized tuning, use displayed values Retune Speed
`0`, Humanize `0` and Flex Tune `0`. Keep Latency Mode at `Low Latency` and use
the same Vocal Range default. Parameter settings provide a defined starting
point; they do not prove the audible result without listening.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:AutoTune -->

<!-- PLUGIN:Chorus -->
<!-- SECTION-REVISION:96b5a1ed596d48662bca99614c5e174a37cc74f1cdee21b53bf8b862bf44d6ef -->
## Chorus

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"chorus","display_name":"Chorus","vendor":"Cockos","product_class":"ordinary","preference_type":"chorus","identifiers":{"add_by_name":["JS: SStillwell/chorus_stereo"],"aliases":["chorus_stereo","sstillwell/chorus_stereo","JS: SStillwell/chorus_stereo"],"curated":[]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["chorus"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"chorus","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"JSFX","identifier":"JS: SStillwell/chorus_stereo","loaded_name":"JS: Chorus (Stereo)","parameter_count":{"mode":"exact","value":11},"required_parameters":[{"index":0,"name":"Chorus Length (ms)","section":"","section_required":false},{"index":1,"name":"Number Of Voices","section":"","section_required":false},{"index":2,"name":"Rate (Hz) (0=tempo sync)","section":"","section_required":false},{"index":3,"name":"Pitch Fudge Factor","section":"","section_required":false},{"index":4,"name":"Wet Mix (dB)","section":"","section_required":false},{"index":5,"name":"Dry Mix (dB)","section":"","section_required":false},{"index":6,"name":"Channel Rate Offset (Hz)","section":"","section_required":false},{"index":7,"name":"Tempo Sync (fraction of whole note)","section":"","section_required":false}],"observed_fingerprint_sha256":"7dfa6aca96a80d37ea2cc89225b301028c229f2ac3e7750f81447451f62b5f3a"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"9e14c3e437df2723d7cd3a5e672818ced27643b7240e6cd3a01445c09409604d","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
Stock JSFX by Stillwell (chorus_stereo). True stereo chorus with tempo-sync option.
Bundled with REAPER; available in all installs.

AddByName string: "JS: SStillwell/chorus_stereo"  (also accepts "SStillwell/chorus_stereo")
Total params: 11 (8 sliders + Bypass/Wet/Delta meta)

### WRITE CONTRACT

Indices 0-7 use raw slider values. Call `TrackFX_SetParam`, never
`TrackFX_SetParamNormalized`, for those eight controls. Do not convert a raw
target through the displayed minimum and maximum.

`Wet Mix (dB)` is index 4. `Dry Mix (dB)` is index 5. Both are distinct from
the host `Wet` control at index 9. If a request names only Wet Mix, write only
index 4 and leave indices 5 and 9 unchanged. The exact -6 dB Wet Mix write is:

```lua
  reaper.TrackFX_SetParam(tr, fx, 4, -6)      -- Wet Mix: -6 dB
```

### PARAM INDEX TABLE (verified from JSFX source)

```
idx  Name                        Default   Min     Max    Notes
---  --------------------------  --------  ------  -----  ----------------------------
0    Chorus Length (ms)          15        1       500    Delay line length
1    Number Of Voices            1         1       8      Voice count
2    Rate (Hz) (0=tempo sync)    0.5       0       16     LFO rate; 0 = tempo sync mode
3    Pitch Fudge Factor          0.7       0       1      Modulation depth
4    Wet Mix (dB)                -6        -100    12     Wet level in dB (-100 = off)
5    Dry Mix (dB)                -6        -100    12     Dry level in dB (-100 = off)
6    Channel Rate Offset (Hz)    0.0       -1      1      L/R rate detune for stereo width
7    Tempo Sync (fraction of whole note) 0.25      0.0625  4  Active when Rate=0 (1=whole, 0.25=quarter)
8    Bypass                      0.0       0.0     1.0    1=bypassed (meta)
9    Wet                         1.0       0.0     1.0    Wet level (meta)
10   Delta                       0.0       0.0     1.0    Delta monitoring (meta)
```

### VALUE SEMANTICS

Raw values on `TrackFX_SetParam`. For tempo-sync mode, set Rate (idx 2) to 0 and
use Tempo Sync (idx 7) to pick the note fraction:

```lua
  reaper.TrackFX_SetParam(tr, fx, 2, 0)       -- Rate = 0 enables tempo sync
  reaper.TrackFX_SetParam(tr, fx, 7, 0.5)     -- Sync to half note
```

### COMMON RECIPES

**"Classic stereo chorus":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 20)      -- Length: 20 ms
  reaper.TrackFX_SetParam(tr, fx, 1, 2)       -- 2 voices
  reaper.TrackFX_SetParam(tr, fx, 2, 0.6)     -- Rate: 0.6 Hz
  reaper.TrackFX_SetParam(tr, fx, 3, 0.6)     -- Depth: 0.6
  reaper.TrackFX_SetParam(tr, fx, 4, -6)      -- Wet: -6 dB
  reaper.TrackFX_SetParam(tr, fx, 6, 0.1)     -- Stereo offset
```

**"Lush pad chorus":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 40)      -- Length: 40 ms
  reaper.TrackFX_SetParam(tr, fx, 1, 4)       -- 4 voices
  reaper.TrackFX_SetParam(tr, fx, 2, 0.3)     -- Rate: 0.3 Hz (slow)
  reaper.TrackFX_SetParam(tr, fx, 3, 0.8)     -- Depth: 0.8
  reaper.TrackFX_SetParam(tr, fx, 4, -3)      -- Wet: -3 dB
  reaper.TrackFX_SetParam(tr, fx, 6, 0.2)     -- Stereo offset
```

---
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Chorus -->

<!-- PLUGIN:Deesser -->
<!-- SECTION-REVISION:38e05365d7f10e8cb80a70716b9a2f094a9ed23f66d2b26dfab8f96fc9f0380d -->
## Deesser

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"deesser","display_name":"Deesser","vendor":"Cockos","product_class":"ordinary","preference_type":"deesser","identifiers":{"add_by_name":["JS: Liteon/deesser"],"aliases":["de-esser","liteon/deesser","JS: Liteon/deesser"],"curated":[]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["deesser"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"deesser","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"JSFX","identifier":"JS: Liteon/deesser","loaded_name":"JS: De-esser","parameter_count":{"mode":"exact","value":12},"required_parameters":[{"index":0,"name":"Processing","section":"","section_required":false},{"index":2,"name":"Monitor","section":"","section_required":false},{"index":4,"name":"Bandwidth (Oct)","section":"","section_required":false},{"index":6,"name":"Ratio","section":"","section_required":false},{"index":8,"name":"Gain (-inf/+24dB)","section":"","section_required":false}],"observed_fingerprint_sha256":"635273fdac9321f18e5eae13a6b6638349f2cb4cfb778c5423bb85ab92bac2ae"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"91c9bfa1666f0301df7258ff28e061ecbf6e62b75d047ee17c6b90f09e0464a5","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
Stock JSFX by Liteon. Single-band de-esser with bandpass or hipass detection.
Bundled with REAPER; available in all installs.

AddByName string: "JS: Liteon/deesser"  (also accepts "Liteon/deesser")
Total params: 12 (9 sliders + Bypass/Wet/Delta meta)

### PARAM INDEX TABLE (verified from JSFX source)

```
idx  Name              Default   Min      Max       Notes
---  ----------------  --------  -------  --------  ----------------------------
0    Processing        1         0        1         Enum: 0=Stereo, 1=Mono
1    Target Type       1         0        1         Enum: 0=Bandpass, 1=Hipass
2    Monitor           0         0        1         Enum: 0=Off, 1=On (solo detection)
3    Frequency (Hz)    4000      1500     12000     Hz (display value)
4    Bandwidth (Oct)   1.5       0.1      3.1       Octaves
5    Threshold (dB)    -25       -80      0         dB (display value)
6    Ratio             4         1        20        N:1 compression ratio
7    Time Constants    0         0        2         Enum: 0=A 3us/R 50ms, 1=A 30us/R 100ms, 2=A 100us/R 300ms
8    Gain (dB)         0         -24      24        Makeup gain
9    Bypass            0.0       0.0      1.0       1=bypassed (meta param)
10   Wet               1.0       0.0      1.0       Wet level (meta param)
11   Delta             0.0       0.0      1.0       Delta monitoring toggle (meta)
```

### VALUE SEMANTICS

All slider params use their native display values with `TrackFX_SetParam`. JS
plugins do NOT use the normalized 0-1 scale that VST plugins often require:

```lua
  reaper.TrackFX_SetParam(tr, fx, 5, -30)      -- Threshold = -30 dB (raw)
  reaper.TrackFX_SetParam(tr, fx, 3, 6000)     -- Frequency = 6 kHz
```

For enum params (indices 0, 1, 2, 7), pass the integer index from the Notes column.

### COMMON RECIPES

**"Gentle vocal de-ess":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 3, 6500)   -- Frequency: 6.5 kHz
  reaper.TrackFX_SetParam(tr, fx, 4, 1.5)    -- Bandwidth: 1.5 oct
  reaper.TrackFX_SetParam(tr, fx, 5, -28)    -- Threshold: -28 dB
  reaper.TrackFX_SetParam(tr, fx, 6, 4)      -- Ratio: 4:1
```

**"Aggressive de-ess":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 1, 1)      -- Target Type: Hipass
  reaper.TrackFX_SetParam(tr, fx, 3, 5500)   -- Frequency: 5.5 kHz
  reaper.TrackFX_SetParam(tr, fx, 5, -35)    -- Threshold: -35 dB
  reaper.TrackFX_SetParam(tr, fx, 6, 8)      -- Ratio: 8:1
```

---
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Deesser -->

<!-- PLUGIN:Pro-C 2 -->
<!-- SECTION-REVISION:946956bd783684692c631e5082e01e778ad328fc5401e6929ec5df04355890ed -->
## Pro-C 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-c-2","display_name":"Pro-C 2","vendor":"FabFilter","product_class":"ordinary","preference_type":"compressor","identifiers":{"add_by_name":["VST3: Pro-C 2","VST3: Pro-C 2 (FabFilter)"],"aliases":["pro-c 2","pro c 2","fabfilter pro-c 2","VST3: Pro-C 2","VST3: Pro-C 2 (FabFilter)"],"curated":["Pro-C 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-c-2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-C 2","loaded_name":"VST3: Pro-C 2 (FabFilter)","parameter_count":{"mode":"exact","value":186},"required_parameters":[{"index":0,"name":"Style","section":"","section_required":false},{"index":34,"name":"Mix","section":"","section_required":false},{"index":37,"name":"Output Level","section":"","section_required":false},{"index":40,"name":"Oversampling","section":"","section_required":false}],"observed_fingerprint_sha256":"08adc04959525c972b0af3c69ca08841eff0d98ae97725ae0a2f6fd1b75d2030"}],"status":"pilot","provenance":{"source":"https://www.fabfilter.com/downloads/pdf/help/ffproc2-manual.pdf","migrated_at":"2026-07-30","body_sha256":"f3d7a199cd08385a174037ccc842c4eb063a77ac5b3197354da9ae61d63344dc","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"08adc04959525c972b0af3c69ca08841eff0d98ae97725ae0a2f6fd1b75d2030"}}
```

<!-- CHUNK:control -->
FabFilter Pro-C 2 is a compressor with eight styles, lookahead, hold, sidechain
filtering, parallel mix and oversampling. This profile is separate from Pro-C
3. The installed Pro-C 2 VST3 fingerprint has 186 parameters and must match
before using these indices.

### PRIMARY CONTROLS

```
0 Style       1 Threshold     2 Ratio       3 Knee
4 Range       5 Attack        6 Release     7 Auto Release
8 Lookahead   9 Hold         14 Auto Gain  18 Stereo Link
19 Link Mode 34 Mix          37 Output Level 40 Oversampling
41 Lookahead Enabled
```

Indices 47 through 182 are MIDI CC and internal host rows. Do not use them for
compressor settings. Do not write the plug-in Bypass at 39 or host controls at
183 through 185 unless explicitly requested.

Resolve all requested controls before writing. Use `set_param_enum` for Style,
Auto Release, Auto Gain, Stereo Link Mode, Oversampling and Lookahead Enabled.
Use `set_param_display` for Threshold, Ratio, Knee, Range, Attack, Release,
Lookahead, Hold, Stereo Link, Mix and Output Level.

When the request says the selected track already has Pro-C 2, reuse exactly
that existing instance. Do not call `TrackFX_AddByName` and do not add a second
Pro-C 2. If more than one existing instance matches, stop and ask which one.

For honest level comparison, set Auto Gain Off and Output Level 0.00 dB. Do
this as explicit verified writes when the user says level matched, honest or
without a loudness boost. For natural vocal compression, start with Vocal
style, 2.00:1 Ratio, +12.00 dB Knee, 10 to 20 ms Attack, 80 to 150 ms Release,
Auto Release Off, Auto Gain Off, 100.0% Mix and 0.00 dB Output. Threshold must
be adjusted to the source by ear. When no audio analysis is available, an
exact threshold is only a starting point.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Style" },
  { index = 1, name = "Threshold" },
  { index = 2, name = "Ratio" },
  { index = 3, name = "Knee" },
  { index = 5, name = "Attack" },
  { index = 6, name = "Release" },
  { index = 7, name = "Auto Release" },
  { index = 14, name = "Auto Gain" },
  { index = 34, name = "Mix" },
  { index = 37, name = "Output Level" },
})
if not mapped then error(guard_err) end
local targets = {
  { mapped[1], "Vocal", true }, { mapped[2], "-15.00 dB", false },
  { mapped[3], "2.00:1", false }, { mapped[4], "+12.00 dB", false },
  { mapped[5], "10.00 ms", false }, { mapped[6], "100.0 ms", false },
  { mapped[7], "Off", true }, { mapped[8], "Off", true },
  { mapped[9], "100.0%", false }, { mapped[10], "0.00 dB", false },
}
for _, target in ipairs(targets) do
  local ok, err
  if target[3] then
    ok, err = set_param_enum(tr, fx, target[1], target[2])
  else
    ok, err = set_param_display(tr, fx, target[1], target[2])
  end
  if not ok then error(err) end
end
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use Vocal for a direct lead vocal start, Bus for glue and Clean for transparent
control. Avoid pumping by using a moderate release and checking gain reduction
against the source. Preserve a reasonable existing threshold when refining an
instance. State final settings without claiming a heard amount of reduction.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-C 2 -->

<!-- PLUGIN:Pro-C 3 -->
<!-- SECTION-REVISION:e31d84650614670382cb57a0e660df438fb72809b6c6aaf42039abdd8bf6090d -->
## Pro-C 3

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-c-3","display_name":"Pro-C 3","vendor":"FabFilter","product_class":"ordinary","preference_type":"compressor","identifiers":{"add_by_name":["VST3: Pro-C 3","VST3: Pro-C 3 (FabFilter)"],"aliases":["pro-c 3","pro-c","fabfilter pro-c 3","VST3: Pro-C 3","VST3: Pro-C 3 (FabFilter)"],"curated":["Pro-C 3"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro c"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-c-3","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-C 3","loaded_name":"VST3: Pro-C 3 (FabFilter)","parameter_count":{"mode":"exact","value":240},"required_parameters":[{"index":0,"name":"Style","section":"","section_required":false},{"index":24,"name":"Host Trigger Offset","section":"","section_required":false},{"index":49,"name":"Side Chain EQ Band 2 Speakers","section":"Side Chain EQ Band 2","section_required":true},{"index":73,"name":"Side Chain EQ Band 5 Shape","section":"Side Chain EQ Band 5","section_required":true},{"index":99,"name":"Show Input Level Meter","section":"","section_required":false}],"observed_fingerprint_sha256":"e22bc8283626bbae7a3e5748e68200d6ca8c5d8b95dbb6aa2f88fd6214d1c34c"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"1ac6c01ae2651cef4c19c5a9f2cd2806a73da68560a4384321b24298385051f0","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
### QUICK DIRECT MAP FOR GENERATED LUA

Use these facts before any longer reference below. Indices are zero-based.

```
0 Style: Clean=0/13, Versatile=1/13, Punch=3/13, Vocal=10/13,
         Mastering=11/13, Bus=12/13
1 Threshold: normalized=(requested_dB+60)/60
4 Ratio: 1.5:1=0.30078125, 2:1=0.400390625,
         3:1=0.52001953125, 4:1=0.599609375
7 Attack: normalized=(requested_ms/250)^(1/3)
8 Release: 100ms=0.2779541015625, 120ms=0.30712890625,
           150ms=0.345947265625, 250ms=0.45001220703125
19 Auto Gain: Off=0, On=1
88 Mix: 100 percent=0.5
```

Keep the minus sign when converting a negative Threshold. For `-20 dB`, use
exactly `(-20 + 60) / 60 = 0.6666666666666666`. For `-18 dB`, use exactly
`(-18 + 60) / 60 = 0.7`. Never use `(20 + 60) / 60` for `-20 dB`; that
clamps to `1.0` and displays `0.00 dB`.

Keep each Ratio label and literal together. For a requested `3:1` ratio, use
exactly `0.52001953125`. Never substitute the neighboring `2:1` literal
`0.400390625`.

Compute Attack from the requested number. Do not copy a neighboring table row.

FabFilter Pro-C 3 is a transparent / character compressor with 14 styles,
auto-threshold, auto-release, auto-gain, character saturation, internal
sidechain EQ, and mid/side stereo link. The go-to compressor for most work.

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-C 3"
Total params (default instance): 67 useful

### PARAM INDEX TABLE (verified, main controls)

```
idx  Name                  Default val   Type        Notes
---  --------------------  -----------   ----------  ---------------------------
0    Style                 0             enum        14 styles (see Style enum)
1    Threshold             1.0           continuous  dB -60..0 linear: dB=-60+slider*60
2    Auto Threshold        0             toggle      0=Off, 1=On (slider >= 0.5 = On)
3    Lock Auto Threshold   0             toggle      0=Off, 1=On
4    Ratio                 0.56          continuous  Ratio (see Ratio scale)
5    Knee                  0.102         continuous  dB 0..72 linear: dB=slider*72
6    Range                 1.0           continuous  Max GR dB 0..60 linear
7    Attack                0.142         continuous  ms 0..250 cubic: ms=250*slider^3
8    Release               0.278         continuous  ms (see Release anchors)
9    Auto Release          0             toggle      0=Off, 1=On
10   Lookahead             0             continuous  ms 0..20 (linear)
11   Hold                  0             continuous  ms 0..500
12   Character             0             toggle      0=Off, 1=On (harmonic saturation)
14   Character Drive       0.5           continuous  dB (0.5=0dB)
15   Wet Gain              0.5           continuous  dB (0.5=0dB)
17   Dry Gain              0             continuous  dB (-INF..0; 0=silence, parallel)
19   Auto Gain             0             toggle      0=Off, 1=On (auto make-up)
26   Stereo Link           0.402         continuous  % 0..200 (default 80%)
27   Stereo Link Mode      0             enum        0=Mid, 1=Side, 2=L/R
88   Mix                   0.5           continuous  % dry/wet, 0.5=100% wet (see below)
89   Input Level           0.5           continuous  dB (0.5=0dB)
91   Output Level          0.5           continuous  dB (0.5=0dB)
93   Bypass                0             toggle      1=bypassed
94   Oversampling          0             enum        0=Off, 1=2x, 2=4x
```

Side Chain EQ params (idx 32-49, two bands) are for internal SC filtering;
leave at defaults unless explicitly tuning sidechain response.

### STYLE ENUM (idx 0, 14 values)

FabFilter style selector. Each value = 1/13 slider step. Order verified
from live `[enum:]` annotation on a current Pro-C 3 install -- if your
version reports a different order or count and an `fx_params:Pro-C 3`
bucket is pinned for this exact instance, trust that live `[enum:]` list
over this static table.

```
Value  Name          Slider target    Character
-----  ------------  ---------------  -------------------------------
0      Clean         0.000 *          Transparent, default
1      Versatile     0.077            General-purpose all-rounder
2      Smooth        0.154            Gentle program compression
3      Punch         0.231            Fast, transient-forward
4      Upward        0.308            Upward compression
5      TTM           0.385            Tape/tube/mu-modeled character
6      Op-El         0.462            Optical-electrical feel
7      Vari-Mu       0.538            Variable-mu, glue
8      Classic       0.615            Analog-style
9      Opto          0.692            Opto-compressor feel, slow
10     Vocal         0.769            Optimized for voice
11     Mastering     0.846            Subtle, mastering-suited
12     Bus           0.923            Glue compression
13     Pumping       1.000            Aggressive, sidechain-like

Formula: target = value / 13.
```

### THRESHOLD SCALE (-60..0 dB linear)

Formula: dB = -60 + slider * 60. Slider = (dB + 60) / 60.

```
-60 dB = 0.000    -30 dB = 0.500    -9 dB = 0.850
-48 dB = 0.200    -24 dB = 0.600    -6 dB = 0.900
-36 dB = 0.400    -18 dB = 0.700    -3 dB = 0.950
                  -12 dB = 0.800     0 dB = 1.000 * (default)
```

### RATIO SCALE (1:1..100:1)

Non-uniform taper -- more resolution at low/medium ratios.

```
slider   ratio       slider   ratio
-------  -------     -------  -------
0.00     1.00:1      0.50     2.75:1
0.10     1.10:1      0.56     3.50:1 *
0.20     1.25:1      0.60     4.00:1
0.30     1.50:1      0.70     6.00:1
0.40     2.00:1      0.80     8.00:1
0.45     2.38:1      0.90     10.00:1
                     0.95     24.40:1
                     1.00     100.00:1

* = default. Useful targets:
1.5:1 = 0.30078125    3:1   = 0.52001953125   10:1 = 0.90
2:1   = 0.400390625   4:1   = 0.599609375     20:1 = 0.94
2.5:1 = 0.475   6:1   = 0.70    inf:1 treat as 100:1 = 1.00
```

### KNEE SCALE (0..72 dB linear)

Formula: dB = slider * 72. Default 7.35 dB = slider 0.102. Most use 0..18 dB.

```
0 dB   = 0.000    12 dB  = 0.167    24 dB  = 0.333
3 dB   = 0.042    15 dB  = 0.208    36 dB  = 0.500
6 dB   = 0.083    18 dB  = 0.250    72 dB  = 1.000 (very wide)
```

### ATTACK SCALE (0..250 ms, cubic -- ms = 250 * slider^3)

```
Formula: ms = 250 * slider^3. Slider = (ms / 250)^(1/3).

0.005 ms = 0.000   5 ms   = 0.271    50 ms  = 0.585
0.1 ms   = 0.074   10 ms  = 0.342   100 ms  = 0.737
0.5 ms   = 0.126   20 ms  = 0.431   150 ms  = 0.843
1 ms     = 0.159   30 ms  = 0.493   250 ms  = 1.000
```

Default 0.725 ms = slider 0.142 (≈ 0.725^(1/3) / 250^(1/3)).

### RELEASE ANCHORS (10 ms..several sec, non-linear)

```
10 ms   = 0.000    100 ms = 0.278 *    1 sec  = ~0.55
20 ms   = ~0.05    200 ms = ~0.38      2 sec  = ~0.70
50 ms   = ~0.18    500 ms = ~0.48      5 sec  = ~1.00
```

Exact live anchors used by maintained complex-chain cases:

```
100.0 ms = 0.277954101562500
120.0 ms = 0.307128906250000
150.0 ms = 0.345947265625000
250.0 ms = 0.450012207031250
```

### MIX PARAM (idx 88, parallel compression)

Counter-intuitive scale: 0.5 = 100% wet (default). Reducing below 0.5
blends in dry signal for parallel compression.

```
0%   wet = 0.0 (bypass-ish)
50%  wet = 0.25 (heavy parallel)
100% wet = 0.5 (default, standard serial compression)
```

Alternative: idx 17 (Dry Gain) adds dry signal at unity without reducing
wet. For classic NY compression use idx 17 raised (~0.8) with hot wet settings.

### MUSICAL DECISION RULES

- For a natural lead vocal, prefer Vocal, Smooth or Opto style with a moderate
  ratio around 1.5:1..2.5:1, a soft knee, attack around 8..25 ms and a manual
  release around 80..200 ms. Use Auto Release for a new starting point only
  when the user explicitly asks for automatic or program-dependent timing.
  Never enable it merely because the request says to avoid pumping. When the
  user asks to keep consonants or life, use at least 8 ms and normally 10..20
  ms attack; do not choose 5 ms or faster unless the user explicitly wants
  aggressive peak control.
- Phrases such as "do not make it falsely louder", "honest comparison",
  "level matched" or "without a loudness boost" explicitly require Auto Gain
  off. Leave Output Level at 0 dB unless the user asks for manual compensation.
  This rule overrides a ready-to-hear recipe or an existing Auto Gain state,
  but an explicit user instruction to enable Auto Gain still wins.
- Treat that honest-loudness rule as a required guarded write, not a prose
  assumption. Include Auto Gain (idx 19) and Output Level (idx 91) in
  `reaassist_resolve_profile_params`, then explicitly write Auto Gain `0.0` and
  Output Level `0.5` (0 dB). Do this even if either control is believed to
  already be at the target. Never say Auto Gain "is off" or "stays off" unless
  the runnable script targets and verifies it.
- When refining an existing instance, change only the controls needed for the
  requested musical result. A Vocal/Smooth/Opto instance already using about
  1.5:1..2.5:1, a soft knee, 8..25 ms attack and 80..200 ms release is already
  a valid natural-vocal starting point; preserve those controls instead of
  changing them merely to produce activity. Do not reset a reasonable existing
  threshold merely because a recipe provides one.
- "Avoid pumping" alone does not justify replacing a valid 80..200 ms manual
  release with Auto Release. Preserve the existing release mode and value
  unless the user explicitly asks for automatic or program-dependent timing.
  If the existing natural-vocal settings are valid but Auto Gain is on, the
  minimum sufficient honest refinement is Auto Gain off with Output Level at
  0 dB.
- For an existing natural-vocal instance with a valid 80..200 ms manual
  release and Auto Release off, resolve indices 9, 19 and 91. Explicitly write
  idx 9 to `0.0`, idx 19 to `0.0` and idx 91 to `0.5`. This locks the valid
  manual release mode, disables Auto Gain and keeps Output Level at 0 dB.
  Preserve Style, Threshold, Ratio, Knee, Attack and Release. In this case,
  enabling Auto Release is a failed refinement even if the response calls it
  program-dependent.
- The response summary must describe the final plug-in state. If Auto Release
  is enabled, call the release program-dependent or automatic rather than
  claiming a fixed millisecond value.
- When the request refines or otherwise reuses an existing Pro-C 3 instance,
  the response summary must say it refines, adjusts or uses that existing
  instance. Never say it adds Pro-C 3 unless the runnable script actually adds
  a new instance.

### COMMON RECIPES

Style values below resolve via the STYLE ENUM table. If an
`fx_params:Pro-C 3` bucket is pinned for this exact instance, recompute
from its live `[enum:]` list instead; live instance data wins.

**"Existing natural vocal, preserve manual release and honest level:"**

When the current manual release is already 80..200 ms and Auto Release is off,
make these guarded writes and preserve every other compressor control:

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 9, 0.0)   -- Auto Release OFF
reaper.TrackFX_SetParamNormalized(tr, fx, 19, 0.0)  -- Auto Gain OFF
reaper.TrackFX_SetParamNormalized(tr, fx, 91, 0.5)  -- Output Level: 0 dB
```

**"Gentle vocal compression, ready-to-hear (Vocal style, ~3 dB GR):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 10/13)   -- Style: "Vocal" (idx 10/14)
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.75)    -- Threshold: -15 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.40)    -- Ratio: 2:1
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 10/72)   -- Knee: 10 dB (soft)
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.342)   -- Attack: 10 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 8, 0.278)   -- Release: 100 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 19, 1.0)    -- Auto Gain ON
```

Use Auto Gain in this recipe only when the user asks for compensation or a
ready-to-hear starting point. For an honest comparison, set idx 19 to `0.0`.

**"Drum bus glue (Bus style, slow attack, program-dependent):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 12/13)   -- Style: "Bus" (idx 12/14)
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.667)   -- Threshold: -20 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.30)    -- Ratio: 1.5:1
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.585)   -- Attack: 50 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 9, 1.0)     -- Auto Release ON
reaper.TrackFX_SetParamNormalized(tr, fx, 19, 1.0)    -- Auto Gain ON
```

**"Aggressive sidechain-style pumping (Pumping style, fast release):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)     -- Style: "Pumping" (idx 13/14)
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.6)     -- Threshold: -24 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.80)    -- Ratio: 8:1
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.0)     -- Attack: fastest
reaper.TrackFX_SetParamNormalized(tr, fx, 8, 0.15)    -- Release: ~30 ms
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-C 3 -->

<!-- PLUGIN:Pro-DS -->
<!-- SECTION-REVISION:13acdc56de9e6565a7a808c0558734a0990d869d182cf9073cdb4620d1b65f73 -->
## Pro-DS

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-ds","display_name":"Pro-DS","vendor":"FabFilter","product_class":"ordinary","preference_type":"deesser","identifiers":{"add_by_name":["VST3: Pro-DS","VST3: Pro-DS (FabFilter)"],"aliases":["pro-ds","fabfilter pro-ds","VST3: Pro-DS","VST3: Pro-DS (FabFilter)"],"curated":["Pro-DS"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-ds","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-DS","loaded_name":"VST3: Pro-DS (FabFilter)","parameter_count":{"mode":"exact","value":160},"required_parameters":[{"index":0,"name":"Mode","section":"","section_required":false},{"index":4,"name":"Stereo Link","section":"","section_required":false},{"index":9,"name":"Side Chain Input Signal","section":"","section_required":false},{"index":13,"name":"Midi State","section":"","section_required":false},{"index":18,"name":"Output Pan","section":"","section_required":false}],"observed_fingerprint_sha256":"d6c3c6fdca38ac5a143cfe3d016c6e1e9027e01ec1b902bc4adf33b34ee32389"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"715c5bb747efa5b903a8c7f7e37c7a3b968a7718b4d670b61fb6a2aa8369fe70","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
FabFilter Pro-DS is a single-band de-esser with automatic range detection
and sidechain HP/LP filtering. Works well for dialogue, vocals, and general
sibilance reduction without user threshold hunting.

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-DS"
Documented useful params: 21 (indices 0-20). REAPER also exposes MIDI-CC
routing params that scripts should ignore.

### CRITICAL CONSTRAINTS

1. **Single band, fixed design.** Pro-DS detects sibilance automatically via
   the Mode + HP/LP sidechain. No user compression controls (attack/release/
   knee/ratio) are exposed -- just Threshold and Range.

2. **Threshold is non-linear below slider 0.2.** Slider 0 collapses to -INF
   (silence). From slider 0.2 to 1.0 it's linear at 60 dB/unit: slider 0.2 =
   -48 dB, slider 1.0 = 0 dB. Most real use is slider 0.3..0.5.

3. **HP and LP use the same frequency scale** (2000..20000 Hz, log base 10).
   Formula: Hz = 2000 * 10^slider.

4. **Describe add versus reuse honestly.** When the request targets an
   existing Pro-DS instance, find and refine that instance. The visible
   summary must begin with "Refines", "Adjusts", or "Uses the existing
   Pro-DS"; do not begin it with "Adds", even in a phrase such as "Adds gentle
   de-essing using the existing Pro-DS". Never say the result "Adds Pro-DS"
   unless the runnable script actually adds a new instance. `Single Vocal` is
   the exact mode name; do not rename it `Mono` or `Single Vocal/Mono`.

5. **Gentle de-essing needs a conservative maximum reduction.** Without
   listening or gain-reduction meter feedback, words such as "gentle",
   "subtle", "natural", "not lispy", or "not dark" require the verified
   4 dB Range recipe below, not the 6 dB default. Start at -30 dB Threshold
   and do not go below -33 dB merely because the source is described as
   harsh. Use Split Band when preserving vocal brightness is an explicit
   concern.

6. **Preserve means do not write.** Keep the existing HP/LP detection band
   unless the user supplies source-specific frequency information. For a
   request with no such frequency information, omit indices 10 and 11 from
   the resolver specifications, omit them from guarded target tables, and
   make no `TrackFX_SetParam*` call for either one. Never rewrite nominal
   defaults as a way to preserve them: normalized conversions can turn an
   exact displayed 7000 or 14000 Hz value into a nearby but different value.

7. **Use a strictly user-facing summary.** For the gentle existing-vocal
   request above, use exactly: "Adjusts the existing Pro-DS to conservative
   starting settings: Single Vocal mode, -30 dB Threshold, 4 dB Range and
   Split Band." Never mention a profile, reference, prompt bundle, preference,
   session, context acquisition or internal instructions. Do not state that
   the unheard result now reduces sibilance, prevents lisping, or preserves
   brightness as an accomplished fact.

### PARAM INDEX TABLE (verified)

```
idx  Name                      Default val   Type       Notes
---  ------------------------  -----------   ---------  ---------------------------
0    Mode                      0             enum       0=Single Vocal, 1=Allround
1    Threshold                 0.4           continuous dB (see Threshold scale)
2    Range                     0.25          continuous dB 0..24 linear: dB=slider*24
3    Band Processing           0             enum       0=Wide Band, 1=Split Band
4    Stereo Link               0.5           continuous % (see Stereo Link scale)
5    Stereo Link Mode          0             enum       0=Mid, 1=Side
6    Lookahead                 0.8           continuous ms 0..15 linear: ms=slider*15
7    Lookahead Enabled         1             toggle     0=Disabled, 1=Enabled
8    Audition Triggering       0             toggle     0=Off, 1=On
9    Side Chain Input Signal   0             enum       0=Normal, 1=External
10   High-Pass Frequency       0.544         continuous Hz (see Freq scale)
11   Low-Pass Frequency        0.845         continuous Hz (see Freq scale)
12   Audition Side Chain       0             toggle     0=Off, 1=On
13   Midi State                0             toggle     0=Enabled, 1=Disabled
14   Oversampling              0             toggle     0=Off, 1=On
15   Input Level               0.5           continuous dB: 0.5=0dB
16   Input Pan                 0.5           continuous 0.5=center
17   Output Level              0.5           continuous dB: 0.5=0dB
18   Output Pan                0.5           continuous 0.5=center
19   Bypass                    0             toggle     Plugin's own bypass
20   Host Bypass               0             toggle     REAPER-side bypass (redundant)
```

Enum slider thresholds for 2-value toggles: <0.5 = first value, >=0.5 = second.
e.g. `SetParamNormalized(tr, fx, 3, 1.0)` sets Band Processing to "Split Band".

### THRESHOLD SCALE (-INF..0 dB)

```
slider   dB            slider   dB            slider   dB
-------  ---------     -------  ---------     -------  ---------
0.00     -INF          0.35     -39.00        0.70     -18.00
0.05     -83.25        0.40     -36.00 *      0.75     -15.00
0.10     -72.00        0.45     -33.00        0.80     -12.00
0.15     -60.00        0.50     -30.00        0.85      -9.00
0.20     -48.00        0.55     -27.00        0.90      -6.00
0.25     -45.00        0.60     -24.00        0.95      -3.00
0.30     -42.00        0.65     -21.00        1.00       0.00

* = default (-36 dB)
```

Above slider 0.2 the scale is linear at 60 dB/unit.
Formula (above 0.2): dB = (slider - 1.0) * 60, or slider = 1 + dB/60.
Below slider 0.2, use the verified table exactly; do not extrapolate a linear
formula. In particular, -60 dB is slider 0.15, not 0.083.

### RANGE SCALE (0..24 dB linear)

Range sets the maximum gain reduction Pro-DS will apply when the threshold
is exceeded. The 6 dB default is a moderate general start, but use the verified
4 dB recipe for a request that explicitly asks for gentle, natural, non-lispy
vocal de-essing when no gain-reduction meter feedback is available.

Formula: dB = slider * 24. Or: slider = dB / 24.

```
3 dB   = 0.125    12 dB  = 0.500
6 dB   = 0.250    18 dB  = 0.750  (heavy)
9 dB   = 0.375    24 dB  = 1.000  (extreme)
```

### HP / LP FREQUENCY SCALE (2000..20000 Hz, log base 10)

Both idx 10 (High-Pass Frequency) and idx 11 (Low-Pass Frequency) use this
same scale. HP defines the lower edge of the sibilance detection band; LP
defines the upper edge.

Formula: Hz = 2000 * 10^slider. In Lua, use
`slider = math.log(hz / 2000) / math.log(10)`; `math.log10` does not exist.
Defaults: HP 7000 Hz = slider 0.544; LP 14000 Hz = slider 0.845.

Useful frequency targets:

```
3 kHz   = 0.176     6 kHz   = 0.477     10 kHz  = 0.699
4 kHz   = 0.301     7 kHz   = 0.544     12 kHz  = 0.778
5 kHz   = 0.398     8 kHz   = 0.602     15 kHz  = 0.875
```

### STEREO LINK SCALE (special hybrid)

Hybrid scale: 0..0.5 is linear % (0..100%); above 0.5 the link stays at 100%
but adds a Mid-only blend that increases with slider. Most use cases just set
slider 0.5 (default: fully linked stereo, no Mid-only) or lower for more
independent L/R de-essing.

```
slider 0.0  = 0%                slider 0.5  = 100% (default)
slider 0.25 = 50%               slider 0.75 = 100% + 50% Mid-only
slider 0.5  = 100%              slider 1.0  = 100% + 100% Mid-only
```

### COMMON RECIPES

**"Gentle vocal de-essing (restrained and brightness-preserving):"**

```lua
-- A conservative unheard-audio starting point. Split Band helps preserve
-- brightness when the user specifically says not to make the vocal dark.
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.0)    -- Mode: Single Vocal
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.5)    -- Threshold: -30 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.1667) -- Range: 4 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 3, 1.0)    -- Band Processing: Split Band
```

**"Aggressive sibilance control (harsh vocals, 10 dB max reduction):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.0)    -- Mode: Single Vocal
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.4)    -- Threshold: -36 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.42)   -- Range: ~10 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 3, 1.0)    -- Band Processing: Split Band
```

**"Broadband de-essing (dialogue, full-range source, no sibilance focus):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)    -- Mode: Allround
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.45)   -- Threshold: -33 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.25)   -- Range: 6 dB
```

### FULL PATTERN (add Pro-DS, vocal de-essing)

This is an add-only example. For a request about an existing de-esser, resolve
the existing instance, do not call AddByName, preserve its identity, and use
existing-instance language in the visible summary.

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "Pro-DS", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.0)    -- Mode: Single Vocal
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.5)    -- Threshold: -30 dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.25)   -- Range: 6 dB
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add Pro-DS: vocal de-essing", -1)
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-DS -->

<!-- PLUGIN:Pro-G -->
<!-- SECTION-REVISION:0626b40d632dca93a85e06e75380b06c9e50a27810a98d39b23e00358d16ecd3 -->
## Pro-G

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-g","display_name":"Pro-G","vendor":"FabFilter","product_class":"ordinary","preference_type":"gate","identifiers":{"add_by_name":["VST3: Pro-G","VST3: Pro-G (FabFilter)"],"aliases":["pro-g","fabfilter pro-g","VST3: Pro-G","VST3: Pro-G (FabFilter)"],"curated":["Pro-G"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro g"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-g","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-G","loaded_name":"VST3: Pro-G (FabFilter)","parameter_count":{"mode":"exact","value":175},"required_parameters":[{"index":0,"name":"Threshold","section":"","section_required":false},{"index":8,"name":"Hold","section":"","section_required":false},{"index":16,"name":"Side Chain Input Signal","section":"","section_required":false},{"index":24,"name":"Midi State","section":"","section_required":false},{"index":34,"name":"Ex Style","section":"","section_required":false}],"observed_fingerprint_sha256":"06be5f6a23d50266cd8ab70bf4662efdea2a49f5cf82fb2ba0450f3a8e356e27"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"1bfad79bf2b78f2569ee88e7f426c913dcb44f0e1fe8de4271f6ccc9f96f3964","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
### QUICK DIRECT MAP FOR GENERATED LUA

Use these literal Pro-G values before any longer reference below. Indices are
zero-based. Do not borrow Pro-C values.

```
0 Threshold: normalized=(requested_dB+60)/60; -36dB=0.4; -30dB=0.5
2 Ratio: 2:1=0.400390625; 4:1=0.599609375
4 Range: 16dB=0.5; 24dB=0.5799560546875
5 Style: Clean=0.25
6 Attack: 0.5ms=0.1495361328125; 1ms=0.177825927734375
7 Release: 80ms=0.285736083984375; 100ms=0.30780029296875
8 Hold: 20ms=0.31817626953125
```

Use the exact requested Attack anchor. For 1 ms, use
`0.177825927734375`; never substitute the 0.5 ms value
`0.1495361328125`.

Keep Threshold and Style literals on their own controls. For `-36 dB`, write
exactly `0.4` to Threshold index 0. The `0.25` literal belongs only to Clean
Style index 5 and must never be written to Threshold.

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.25) -- Style: Clean
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.4)  -- Threshold: -36 dB
```

Never write both requested controls to the same parameter index.

FabFilter Pro-G is a gate and downward/upward expander. Its primary musical
controls are Threshold, Ratio, Range, Style, Attack, Release, Hold and Knee.
It also supports lookahead and sidechain high-pass/low-pass filtering.

AddByName identifier: use the exact preferred identifier, normally
`VST3: Pro-G`.

Total parameters on the verified VST3 build: 175. Indices 36 through 170 are
host routing entries and not normal audio controls.

### PARAMETER INDEX TABLE

```
idx  Name                      Type
---  ------------------------  -------------------------------------------
0    Threshold                 numeric display, dB
1    Threshold (Upward)        numeric display, dB
2    Ratio                     numeric display, ratio
3    Ratio (Upward)            numeric display, ratio
4    Range                     numeric display, dB
5    Style                     enum: Classic, Clean, Vocal
6    Attack                    numeric display, time
7    Release                   numeric display, time
8    Hold                      numeric display, time
9    Knee                      numeric display, dB
10   Lookahead                 numeric display, time
11   Lookahead Enabled         toggle
16   Side Chain Input Signal   enum
17   Low Pass Frequency        numeric display, frequency
18   High Pass Frequency       numeric display, frequency
19   Audition Side Chain       toggle
25   Oversampling              toggle
26   Expert Mode               toggle
27   Channel Mode              enum
```

Utility I/O controls normally stay unchanged unless the user explicitly asks
for them:

```
idx  Name            Verified neutral display
---  --------------  ------------------------
20   Wet Level       0.00 dB
21   Wet Pan         0.000
22   Dry Level       -INF dB
23   Dry Pan         0.000
28   Input Level     0.00 dB
29   Input Pan       0.000
30   Output Level    0.00 dB
31   Output Pan      0.000
32   Bypass          Not Bypassed
```

### DISPLAY-TARGETING REQUIREMENT

The previously migrated normalized tables for Threshold, Ratio and Range were
wrong for this installed build. A live exact-control case proved:

```
Parameter   Normalized value   Actual plug-in display
----------  -----------------  -----------------------
Threshold   0.400000000000000  -36.00 dB
Ratio       0.400390625000000  2.00:1
Range       0.500000000000000  16.00 dB
Attack      0.177825927734375  1.000 ms
Release     0.307800292968750  100.0 ms
```

Additional live exact-control anchors for the standard Lua path:

```
Parameter   Requested display   Normalized value
----------  ------------------  -----------------
Style       Clean               0.250000000000000
Ratio       4.00:1              0.599609375000000
Range       24.00 dB            0.579956054687500
Attack      0.500 ms            0.149536132812500
Release     80.00 ms            0.285736083984375
Hold        20.00 ms            0.318176269531250
```

Keep these Pro-G anchors scoped to Pro-G. Never compute its 16 dB Range as
`16/24`, and never reuse Pro-C attack or release values for Pro-G.

Therefore:

- Threshold uses `dB = -60 + normalized * 60`; `-18 dB = 0.700000`.
- Do not use the old claim that Threshold spans only `-30..0 dB`.
- Do not infer Ratio or Range from the old tables. Their displays are curved.
- For every user-specified numeric Threshold, Ratio, Range, Attack, Release,
  Hold, Knee, Lookahead or sidechain-frequency target, include the canonical
  `set_param_display` helper from `prompt_bundle:plugin_helpers` and target the
  requested display text through the guarded `mapped[N]` index.
- Use unit-bearing target strings for time and frequency values.
- Check every helper result. On failure, stop the staged action. On a
  nearest-value success note, tell the user the achieved display instead of
  claiming the requested value exactly.
- Use `set_param_enum` for Style or another text enum. Never guess enum
  spacing.

For example, an exact request for `-18 dB`, `2.5:1`, `24 dB`, `1 ms` and
`100 ms` must resolve all five names before the first write, then use:

```lua
local ok, note
ok, note = set_param_display(tr, fx, mapped[1], "-18 dB")
if not ok then error("Threshold: " .. tostring(note)) end
ok, note = set_param_display(tr, fx, mapped[2], "2.5:1")
if not ok then error("Ratio: " .. tostring(note)) end
ok, note = set_param_display(tr, fx, mapped[3], "24 dB")
if not ok then error("Range: " .. tostring(note)) end
ok, note = set_param_display(tr, fx, mapped[4], "1 ms")
if not ok then error("Attack: " .. tostring(note)) end
ok, note = set_param_display(tr, fx, mapped[5], "100 ms")
if not ok then error("Release: " .. tostring(note)) end
```

Do not substitute hardcoded normalized Ratio or Range values for those helper
calls. Do not claim exact values unless the helper or settled host readback
confirms them.

### MUSICAL GUIDANCE

Threshold is signal-dependent. Without audio analysis, describe any threshold
as a conservative starting point rather than claiming that room noise is now
removed. Range limits how far the signal can be attenuated; a lower Range,
moderate Ratio, soft Knee and adequate Hold/Release make expansion less likely
to clip consonants, breaths or word endings.

For a vague request such as `reduce quiet dialogue-room noise without
hard-gating breaths or word endings`, use this conservative starting point:

```
Style       Vocal
Threshold   -36 dB
Ratio       2.00:1
Range       12 dB
Attack      5 ms
Hold        50 ms
Release     200 ms
Knee        6 dB
```

This is eight targets total: one enum and seven numeric displays. Resolve all
eight in one literal resolver table before the first parameter write. Do not
store that table in a `specs` variable because the static safety validator must
be able to inspect the literal entries at the resolver call:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 5, name = "Style" },
  { index = 0, name = "Threshold" },
  { index = 2, name = "Ratio" },
  { index = 4, name = "Range" },
  { index = 6, name = "Attack" },
  { index = 8, name = "Hold" },
  { index = 7, name = "Release" },
  { index = 9, name = "Knee" },
})
if not mapped then error(guard_err) end
```

Then use `mapped[1]` with `set_param_enum(..., "Vocal")`. Use
`mapped[2]` through `mapped[8]`, in the same order shown above, with
`set_param_display` for `"-36 dB"`, `"2.00:1"`, `"12 dB"`, `"5 ms"`,
`"50 ms"`, `"200 ms"` and `"6 dB"`. Reference every mapped entry exactly
once; do not shift the ordinals to match the plug-in's raw indices.

Because this example explicitly says `existing Pro-G`, use
`TrackFX_GetByName`, show a clear message and return if the result is below
zero. Do not add a replacement Pro-G when the existing instance cannot be
found.

Preserve lookahead, sidechain filters, Expert Mode, input/output levels,
wet/dry controls and every other parameter unless the user asks for them.

For drums, hard gating is appropriate only when the user clearly requests a
tight or hard-close effect. Even then, do not invent a threshold without
signal information. You may use a high Ratio, larger Range, fast Attack and
shorter Hold/Release as a starting point while explaining that Threshold
requires listening.

### USER-FACING RESPONSE CONTRACT

- Say whether Pro-G was added or an existing instance was adjusted.
- Summarize the achieved plug-in displays, not intended normalized values.
- For an unheard musical starting point, say what the settings are intended
  to do. Do not state that noise, breaths or word endings were successfully
  controlled as an accomplished fact.
- Never mention profiles, references, prompt bundles, validation retries,
  parameter indices, normalized values or internal instructions.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-G -->

<!-- PLUGIN:Pro-L 2 -->
<!-- SECTION-REVISION:a4699ed46000cc515168a7533a473579425a7867160ae4309ddce4d213a6f4b2 -->
## Pro-L 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-l-2","display_name":"Pro-L 2","vendor":"FabFilter","product_class":"ordinary","preference_type":"limiter","identifiers":{"add_by_name":["VST3: Pro-L 2","VST3: Pro-L 2 (FabFilter)"],"aliases":["pro-l 2","pro-l","fabfilter pro-l 2","VST3: Pro-L 2","VST3: Pro-L 2 (FabFilter)"],"curated":["Pro-L 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro l"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-l-2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-L 2","loaded_name":"VST3: Pro-L 2 (FabFilter)","parameter_count":{"mode":"exact","value":172},"required_parameters":[{"index":0,"name":"Gain","section":"","section_required":false},{"index":7,"name":"Channel Link Center","section":"","section_required":false},{"index":15,"name":"Unity Gain","section":"","section_required":false},{"index":23,"name":"Display Mode","section":"","section_required":false},{"index":31,"name":"Loudness Auto-Reset","section":"","section_required":false}],"observed_fingerprint_sha256":"e8d76e3fc0d616f68c1dabcfb5888514479dbd5ad41a957e7378fe55509e05d1"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"3dda96870965bea45f66916af527c04aacc6ae8ebfb5772d1fd3971f4d9673bb","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
### QUICK DIRECT MAP FOR GENERATED LUA

Use these facts before any longer reference below. Indices are zero-based.

```
0 Gain: normalized=requested_dB/30
1 Style: Transparent=0; Modern=5/7
10 True Peak Limiting: Off=0, On=1
11 Dithering: Off=0, On=1
18 Output Level: normalized=(requested_dBTP+30)/30; -1dBTP=29/30
19 Lock Output: Unlocked=0, Locked=1
```

FabFilter Pro-L 2 is a true peak limiter with 8 character styles, true-peak
metering, dither / noise shaping, and loudness monitoring. Used as the final
stage of mastering chains.

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-L 2"
Total params (default instance): 35 useful

### PARAM INDEX TABLE (verified, main controls)

```
idx  Name                      Default val   Type        Notes
---  ------------------------  -----------   ----------  ---------------------------
0    Gain                      0             continuous  dB 0..+30 linear: dB=slider*30
1    Style                     0.714         enum        8 styles (see Style enum)
2    Lookahead                 0.036         continuous  ms 0..5 quartic (default 0.18ms)
3    Attack                    0.407         continuous  ms (see Attack scale)
4    Release                   0.388         continuous  ms (non-standard, default 400ms)
5    Channel Link Transients   0.375         continuous  % 0..200 (default 75%)
6    Channel Link Release      0.5           continuous  % 0..200 (default 100%)
7    Channel Link Center       0             toggle      0=Excluded, 1=Included
8    Channel Link LFE          0             toggle      0=Excluded, 1=Included
9    Oversampling              0             enum        0=Off, up to 16x
10   True Peak Limiting        1             toggle      0=Off, 1=On (keep ON)
11   Dithering                 0             toggle      0=Off, 1=On
12   Noise Shaping             0.667         enum        0=Off, 1=Weighted, 2=Optimized
13   Filter DC Offset          0             toggle      0=Off, 1=On
14   Side Chain Triggering     0             toggle      0=Off, 1=On
15   Unity Gain                0             toggle      0=Off, 1=On (auto make-up A/B)
16   Audition Limiting         0             toggle      0=Off, 1=On (hear only GR)
17   Bypass                    0             toggle      1=bypassed
18   Output Level              1.0           continuous  dBTP ceiling (1.0 = 0 dBTP)
19   Lock Output               1             toggle      0=Unlocked, 1=Locked (safety)
```

Loudness / metering UI params (idx 20-31) are display-only; leave at defaults.
Idx 32 (Host Bypass) and VST3 tail params are redundant.

### STYLE ENUM (idx 1, 8 values)

Each style gets 1/7 of the slider range.

```
Value  Name          Slider target    Character
-----  ------------  ---------------  -------------------------------
0      Transparent   0.000            Cleanest; minimal coloration
1      Punchy        0.143            Fast, preserves transients
2      Dynamic       0.286            Adaptive release per transient
3      Allround      0.429            General-purpose balanced
4      Aggressive    0.571            Loud, saturated
5      Modern        0.714 *          Default -- loud and clean
6      Bus           0.857            Gentle bus compression feel
7      Safe          1.000            Most conservative, safest
```

Use 1/7 ≈ 0.143 as the step. Slider formula: target = value / 7.

### GAIN SCALE (0..+30 dB linear)

Pre-limiter input gain. Louder gain into the limiter = more limiting.

```
Formula: dB = slider * 30. Slider = dB / 30.

 0 dB = 0.000 *     +9 dB = 0.300     +18 dB = 0.600
+3 dB = 0.100       +12 dB = 0.400    +24 dB = 0.800
+6 dB = 0.200       +15 dB = 0.500    +30 dB = 1.000
```

Use the exact division expression for non-integer slider targets. For a 2 dB
request, write `2/30`, not the rounded decimal `0.067`. The rounded value can
display `+2.01 dB` on the verified build, while `2/30` displays the requested
`+2.00 dB`. Do not accept or report `+2.01 dB` as an exact 2 dB result.

### ATTACK SCALE (0..10 sec, quartic -- ms = 10000 * slider^4)

```
Formula: ms = 10000 * slider^4. Slider = (ms / 10000)^0.25.

 1 ms = 0.100    100 ms = 0.316    500 ms = 0.473
 5 ms = 0.150    275 ms = 0.407 *  1 sec  = 0.562
16 ms = 0.200    400 ms = 0.447    2 sec  = 0.669
39 ms = 0.250                      5 sec  = 0.841
```

### RELEASE SCALE (0..1+ sec, non-standard)

Use anchors; formula not clean. Default 400 ms at slider 0.388.

```
slider   ms          slider   ms
-------  ------      -------  ------
0.00     0           0.40     ~240
0.20     ~80         0.50     ~450
0.30     ~150        0.75     ~1200
0.388    400 *       1.00     5000+
```

### OUTPUT LEVEL / CEILING (idx 18)

Sets the maximum output level (dBTP). Default slider 1.0 = 0 dBTP ceiling.

Formula: `dBTP = -30 + normalized * 30`, so
`normalized = (dBTP + 30) / 30`.

```
0 dBTP    = 1.000 (default)    -1 dBTP  = 29/30
-0.1 dBTP = ~0.997             -3 dBTP  = ~0.900
-0.3 dBTP = ~0.990             -6 dBTP  = ~0.800
```

Common choice for streaming: -1.0 dBTP. Write the exact expression `29/30`,
not the rounded decimal `0.967`, which displays `-0.99 dBTP` on the verified
build. A pre-existing `-1.50 dBTP` ceiling is also a restrained streaming
choice and may be preserved. For an existing Transparent instance with 2 dB
Gain, True Peak Limiting on and either exact ceiling, preserve every other
control. Do not change timing, oversampling, dither or output-lock settings
merely to produce activity.

### GUARDED WRITE ORDER

For a request that controls Gain, Style, Output Level and True Peak Limiting,
resolve all four names in this exact order before the first write:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Gain" },
  { index = 1, name = "Style" },
  { index = 18, name = "Output Level" },
  { index = 10, name = "True Peak Limiting" },
})
if not mapped then error(guard_err) end
```

Then keep the same ordinal order. For the exact 2 dB, Transparent,
-1.5 dBTP and True Peak On request, use exactly:

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 2/30) -- Gain: +2.00 dB
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.0)  -- Style: Transparent
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.95) -- Output: -1.50 dBTP
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 1.0)  -- True Peak: On
```

Never resolve in one order and write in another. Do not put Style before Gain
or True Peak Limiting before Output Level in the resolver shown above. A
resolver/write mismatch can leave Gain and Output Level unchanged while making
the unchanged toggles appear successful. For the natural streaming refinement,
the only permitted substitution is `mapped[3], 29/30` for exact -1.00 dBTP.

The visible response must state whether Pro-L 2 was added or an existing
instance was adjusted, followed by the achieved Gain, Style, Output Level and
True Peak Limiting state. Never return only the generic parameter-precision
tip.

When an existing Pro-L 2 already satisfies the restrained natural request,
report that state in the normal Assistant response and use a harmless no-op
runnable block:

```lua
reaper.defer(function() end)
```

Never call `reaper.ShowMessageBox`, `reaper.MB` or another modal dialog to
announce that no changes are needed or that the existing settings are good.
Do not create an Undo block or rewrite already-correct parameters merely to
avoid a no-op. A success or no-change dialog is a failed response.

### COMMON RECIPES

**"Master bus limiter (streaming target, ~-14 LUFS integrated):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.167)  -- Gain: +5 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 1,  0.714)  -- Style: Modern
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 1.0)    -- True Peak Limiting ON
reaper.TrackFX_SetParamNormalized(tr, fx, 18, 29/30)  -- Ceiling: -1.00 dBTP
```

**"Transparent peak catch (small gain, minimal character):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  2/30)   -- Gain: +2.00 dB exactly
reaper.TrackFX_SetParamNormalized(tr, fx, 1,  0.0)    -- Style: Transparent
reaper.TrackFX_SetParamNormalized(tr, fx, 18, 0.950)  -- Ceiling: -1.5 dBTP
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-L 2 -->

<!-- PLUGIN:Pro-MB -->
<!-- SECTION-REVISION:c3a1d472c4aa40888ba39094dc2955dade2f09beeb26b393ec17d5a22fcb0705 -->
## Pro-MB

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-mb","display_name":"Pro-MB","vendor":"FabFilter","product_class":"dynamic","preference_type":"multiband_compressor","identifiers":{"add_by_name":["VST3: Pro-MB","VST3: Pro-MB (FabFilter)"],"aliases":["pro-mb","fabfilter pro-mb","VST3: Pro-MB","VST3: Pro-MB (FabFilter)"],"curated":["Pro-MB"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-mb","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-MB","loaded_name":"VST3: Pro-MB (FabFilter)","parameter_count":{"mode":"exact","value":291},"required_parameters":[{"index":0,"name":"Band 1 State","section":"Band 1","section_required":true},{"index":37,"name":"Band 2 Side Chain Filtering","section":"Band 2","section_required":true},{"index":74,"name":"Band 4 Ratio","section":"Band 4","section_required":true},{"index":111,"name":"Band 6 Low Crossover","section":"Band 6","section_required":true},{"index":150,"name":"Analyzer Side Chain","section":"Analyzer","section_required":true}],"observed_fingerprint_sha256":"22e947cc14ad15600f0a160c26ff1b40077d47c3ee112c506798180728fbbd12"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"cc4743325f639063fa823173b5989acfb61a44cfffdddf129d96790304c2c85c","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
FabFilter Pro-MB is a dynamic-range processor that can compress OR expand
any number of frequency bands independently. Up to 6 user-defined bands,
each with its own crossovers, dynamics mode, threshold, ratio, and sidechain
filtering. Primary tool for surgical multiband problems (resonances,
de-honking, mud cleanup, band-specific de-essing).

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-MB"
Total params: 151 useful in the currently tested VST3 build (six 22-parameter
bands plus global and analyzer controls). This reference shows Bands 1-2 as
representative; Bands 3-6 follow the same 22-parameter stride.

### CRITICAL CONSTRAINTS

1. **All bands start "Unused" by default.** Fresh Pro-MB has no active
   processing. Set `Band N State` to normalized `0.0` before any other band
   params. In the tested VST3 host readback this active state formats as
   `Disabled`, while normalized `1.0` formats as `Unused`; the wording is
   counterintuitive, so verify activation by the visible band and its
   crossovers rather than inventing a third state.

2. **Each band has BOTH compression and expansion modes** via `Dynamics Mode`.
   Compression reduces signal above threshold; expansion reduces below.

3. **Attack and Release are percentages (0..100%), not ms.** Pro-MB uses an
   auto-detected per-band time base; the % scale is relative to that.
   Default 20% is moderate for both.

4. **Use the complete live parameter names in the mandatory mapped-write
   guard.** For Band 1 the exact names are `Band 1 State`,
   `Band 1 Low Crossover`, `Band 1 High Crossover`,
   `Band 1 Dynamics Mode`, `Band 1 Threshold`, `Band 1 Range`,
   `Band 1 Ratio`, `Band 1 Attack`, and `Band 1 Release`, all in section
   `Band 1`. Do not shorten these to `1 State`, `1 Low Crossover`, and so on.
   Other bands use the same `Band N ...` naming and section `Band N`.

5. **Crossover slopes are independent controls, not activation requirements.**
   Do not write Low Slope or High Slope unless the user explicitly asks for a
   slope. On a fresh instance, leave their plug-in defaults alone. On an
   existing instance, preserve their current values. This remains true when
   the user specifies both crossover frequencies.

### BAND LAYOUT (per-band structure, 22 params each)

```
Formula: base = (N - 1) * 22  (for bands 1-2; bands 3-6 follow same stride)

Offset  Exact live name               Type        Notes
------  ----------------------------  ----------  --------------------------
+0      Band N State                  enum        Unused / In Use (see enum)
+1      Band N Low Crossover          continuous  Hz (30..30000, log)
+2      Band N Low Slope              enum        dB/oct (see Slope enum)
+3      Band N High Crossover         continuous  Hz (30..30000, log)
+4      Band N High Slope             enum        dB/oct (see Slope enum)
+5      Band N Dynamics Mode          enum        0=Compression, 1=Expansion
+6      Band N Threshold              continuous  dB -60..0 linear
+7      Band N Range                  continuous  dB (-60..+60; 0.5=0dB)
+8      Band N Ratio                  continuous  Ratio (see Ratio scale)
+9      Band N Attack                 continuous  % 0..100 linear: slider=%/100
+10     Band N Release                continuous  % 0..100 linear: slider=%/100
+11     Band N Knee                   continuous  dB 0..72: dB=slider*72 approx
+12     Band N Lookahead              continuous  ms (0..20 linear)
+13     Band N Level                  continuous  dB band output trim (0.5=0dB)
+14     Band N Pan                    continuous  Mid/Side or L/R pan
+15     Band N Side Chain Filtering   enum        Band-only / External / ...
+16     Band N Side Chain Low Frequency continuous SC HPF (shares Crossover scale)
+17     Band N Side Chain High Frequency continuous SC LPF (shares Crossover scale)
+18     Band N Side Chain Input       enum        Plug-in Input / External
+19     Band N Stereo Link            continuous  % 0..200 (default 100%)
+20     Band N Stereo Link Mode       enum        0=Mid, 1=Side, 2=L/R
+21     Band N Solo/Mute State        enum        Normal / Solo / Mute

Band 1: indices 0-21
Band 2: indices 22-43
```

### GLOBAL PARAMS

```
idx  Name                      Default     Notes
---  ------------------------  ----------  ---------------------------------
132  Audition Side Chain       0           Off / On
133  Mix                       0.5         % dry/wet, 0.5=100% wet
134  Input Level               0.5         dB
136  Output Level              0.5         dB
138  Bypass                    0           1=bypassed
139  Processing Mode           0.5         Dynamic Phase / Linear Phase / Classic
140  Oversampling              0           Off / 2x / 4x
141  Lookahead Enabled         1           0=Off, 1=On
```

### STATE ENUM (per-band, offset +0)

Default slider 1.0 = "Unused". To activate a band, set slider to 0.0.

```
slider  Host display  Meaning
------  ------------  -----------------------------------------------
0.0     Disabled      Band is allocated and processes audio
1.0     Unused        No active band (default)
```

### CROSSOVER FREQUENCY SCALE (30..30000 Hz, log)

Used by idx +1, +3, +16, +17 within each band.

Formula: Hz = 30 * 1000^slider (approx). In Lua, use
`slider = math.log(hz / 30) / math.log(1000)` (equivalently,
`math.log(hz / 30, 10) / 3`); `math.log10` does not exist.
For a user-specified frequency, calculate this expression at write time. Do
not copy a rounded table anchor into runnable code. On the verified build,
rounded `0.275` and `0.408` display `200.50 Hz` and `502.48 Hz`; the exact
expressions below display the requested 200 and 500 Hz targets. Do not report
the rounded landings as exact values.

```
30 Hz   = 0.000    500 Hz   = 0.408     5000 Hz   = 0.742
100 Hz  = 0.174    1000 Hz  = 0.508     10000 Hz  = 0.842
200 Hz  = 0.275    2000 Hz  = 0.608     20000 Hz  = 0.942
                                         30000 Hz  = 1.000 (off)
```

### SLOPE ENUM (per-band, offsets +2 and +4)

Crossover steepness. 5 values evenly spaced.

```
Value  dB/oct    Slider target
-----  --------  -------------
0      6         0.000
1      12        0.250
2      24        0.500 *
3      48        0.750
4      96        1.000
```

### RATIO SCALE (offset +8)

Similar to Pro-C 3 ratio; non-uniform.

```
slider   ratio       slider   ratio
-------  -------     -------  -------
0.00     1.00:1      0.60     4.00:1 *
0.30     1.50:1      0.80     8.00:1
0.40     2.00:1      0.90     10:1
0.50     2.75:1      1.00     inf:1
```

### THRESHOLD / RANGE SCALES

- **Threshold (offset +6):** dB -60..0 linear. dB = -60 + slider*60.
- **Range (offset +7):** dB -30..+30 linear in the tested VST3 build,
  `dB = (slider - 0.5) * 60`. Therefore `0.40 = -6.00 dB` and
  `0.35 = -9.00 dB`. Negative is the maximum compression gain reduction;
  positive is expansion. Default `0.50 = 0 dB` disables dynamics within the
  band. Never substitute a Range value from a different recipe.

### COMMON RECIPES

**"De-mud the low-mids (cut 200-500 Hz when signal exceeds threshold):"**

```lua
-- Activate Band 1 as a dynamic EQ cut
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.0)     -- Band 1 State: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 1,
  math.log(200 / 30) / math.log(1000))                 -- Low: 200 Hz exact
reaper.TrackFX_SetParamNormalized(tr, fx, 3,
  math.log(500 / 30) / math.log(1000))                 -- High: 500 Hz exact
reaper.TrackFX_SetParamNormalized(tr, fx, 5,  0.0)     -- Mode: Compression
reaper.TrackFX_SetParamNormalized(tr, fx, 6,  0.7)     -- Threshold: -18 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 7,  0.4)     -- Range: -6 dB (max GR)
reaper.TrackFX_SetParamNormalized(tr, fx, 8,  0.5)     -- Ratio: ~2.75:1
reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.15)    -- Attack: 15%
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.30)    -- Release: 30%
```

For this exact 200-500 Hz de-mud recipe, Range must be normalized `0.40`.
Normalized `0.35` is `-9.00 dB` and is not an acceptable approximation of
`-6.00 dB`.

**"Gently refine an existing focused 200-500 Hz de-mud band:"**

This is a distinct existing-instance recipe. When the request says to use the
existing Pro-MB, do not copy or combine any write from the preceding de-mud
recipe. The only permitted `TrackFX_SetParamNormalized` calls are the four
shown in this recipe. In particular, do not write Band 1 indices 0 through 6,
even to restate or preserve their current values. Read those controls as
context and leave their normalized values byte-for-byte unchanged.

When Band 1 already spans 200-500 Hz in Compression mode, keep it as the only
active band. Preserve both crossovers, both slopes, Dynamics Mode and the
existing Threshold because a threshold choice requires signal evidence. For a
focused, gentle refinement that should not thin the track, use exactly -3 dB
Range, 2.00:1 Ratio, 20% Attack and 40% Release. Resolve only these four names
in this exact order:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 7, name = "Band 1 Range", section = "Band 1" },
  { index = 8, name = "Band 1 Ratio", section = "Band 1" },
  { index = 9, name = "Band 1 Attack", section = "Band 1" },
  { index = 10, name = "Band 1 Release", section = "Band 1" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.45) -- Range: -3.00 dB
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.40) -- Ratio: 2.00:1
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.20) -- Attack: 20.0%
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.40) -- Release: 40.0%
```

Do not activate another band, widen the crossovers or move Threshold merely
because the request describes mud. Do not substitute another gentle recipe.
For this exact natural request, `-6 dB` Range and `2.75:1` are the input state,
not the finished gentle refinement.

**"De-ess via Band 2 (tight 5-8 kHz, hard ratio):"**

```lua
-- Use Band 2 so Band 1 can stay configured for other purposes
reaper.TrackFX_SetParamNormalized(tr, fx, 22, 0.0)     -- Band 2 State: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 23,
  math.log(5000 / 30) / math.log(1000))                -- Low: 5000 Hz exact
reaper.TrackFX_SetParamNormalized(tr, fx, 25,
  math.log(8000 / 30) / math.log(1000))                -- High: 8000 Hz exact
reaper.TrackFX_SetParamNormalized(tr, fx, 27, 0.0)     -- Mode: Compression
reaper.TrackFX_SetParamNormalized(tr, fx, 28, 0.75)    -- Threshold: -15 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 29, 0.35)    -- Range: -9 dB max
reaper.TrackFX_SetParamNormalized(tr, fx, 30, 0.80)    -- Ratio: 8:1
reaper.TrackFX_SetParamNormalized(tr, fx, 31, 0.05)    -- Attack: 5% (fast)
reaper.TrackFX_SetParamNormalized(tr, fx, 32, 0.10)    -- Release: 10%
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-MB -->

<!-- PLUGIN:Pro-Q 4 -->
<!-- SECTION-REVISION:131f5cf894fc99e4f24771b435b1ffa89aa66fe5663e57740727632683553a67 -->
## Pro-Q 4

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-q-4","display_name":"Pro-Q 4","vendor":"FabFilter","product_class":"dynamic","preference_type":"eq","identifiers":{"add_by_name":["VST3: Pro-Q 4","VST3: Pro-Q 4 (FabFilter)"],"aliases":["pro-q 4","pro-q","fabfilter pro-q 4","VST3: Pro-Q 4","VST3: Pro-Q 4 (FabFilter)"],"curated":["Pro-Q 4"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro q"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-q-4","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-Q 4","loaded_name":"VST3: Pro-Q 4 (FabFilter)","parameter_count":{"mode":"exact","value":740},"required_parameters":[{"index":0,"name":"Band 1 Used","section":"Band 1","section_required":true},{"index":149,"name":"Band 7 Dynamics Auto","section":"Band 7","section_required":true},{"index":299,"name":"Band 14 Used","section":"Band 14","section_required":true},{"index":448,"name":"Band 20 Dynamics Auto","section":"Band 20","section_required":true},{"index":599,"name":"Band 24 Spectral Tilt","section":"Band 24","section_required":true}],"observed_fingerprint_sha256":"b90f26794dbf05ba04b652c813c932f02ec066c6996988a722d94d35449eb5ce"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"58364f66e62ceded7798a0543182596c84b79cc10e975182831879627daa6f87","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
### QUICK DIRECT MAP FOR GENERATED LUA

Use these formulas before any table of examples below. Indices are zero-based.
For Band N, `base=(N-1)*23`. Write Used at `base+0`, Enabled at `base+1`,
Frequency at `base+2`, Gain at `base+3`, Q at `base+4`, Shape at `base+5`, and
Slope at `base+6`.

```lua
local function proq_freq_norm(hz)
  return math.log(hz / 10) / math.log(3000)
end
local function proq_gain_norm(db) return (db + 30) / 60 end
local function proq_q_norm(q) return math.log(q / 0.025) / math.log(1600) end
```

For every requested band, set Used=1, Enabled=1, the exact computed Frequency,
Gain and Q, Bell Shape=0, and Bell Slope=0.2. Compute each requested frequency
from the formula. Do not substitute a neighboring frequency-table literal.

FabFilter Pro-Q 4 is a surgical / musical parametric EQ with up to 24 bands,
dynamic EQ per band, spectral processing, per-band mid/side/surround routing,
and multiple processing modes (Zero Latency / Natural Phase / Linear Phase).
The most-used FabFilter plugin -- this section is the most important for
typical EQ scripting.

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-Q 4"
Total host params on the fingerprint-verified VST3 build: 740. This reference
covers the musical band controls and commonly used globals. Bands 1-24 follow
the same 23-param stride.

### CRITICAL CONSTRAINTS

1. **Bands default to "Unused".** Set `Band N Used` (offset +0) to "In Use"
   (slider 1.0) before any other band params take effect. "Enabled" (offset
   +1) is a separate toggle that temporarily bypasses an in-use band.

2. **Setting a band's `Used` to In Use creates a point at default Freq/Gain.**
   Always follow with Frequency + Gain + Shape + Q to position it. For Bell
   boosts/cuts, also set Slope to 12 dB/oct unless the user specifies a
   different slope.

3. **Shape defaults to Bell.** For HPF / LPF, set Shape accordingly and use
   Slope (offset +6) for the cut steepness. For Bell boost/cut bands, Slope
   still matters: use 12 dB/oct by default to match Pro-Q 4's GUI default and
   avoid the host/default-state 48 dB/oct behavior.

4. **Dynamics per band is OFF by default via `Dynamic Range = 0 dB`.**
   To activate dynamic EQ, set offset +9 to non-0.5 (negative=downward
   dynamic, positive=upward). Then tune Threshold/Attack/Release.

5. **Pro-Q 4 supports 24 bands.** Band N indices run 0..22 for N=1, then stride
   23 per band. Band 24 last param = 551. Params at 552+ are globals.

6. **Keep requested display values in the data table and convert exactly at
   write time.** For Frequency, Gain, and Q, use the exact formulas below (or
   `set_param_display`) for every requested value. Do not copy a nearby rounded
   probe or store a three-decimal normalized approximation as the target. For
   example, 250 Hz is about 0.4020, not 0.417; 0.417 displays about 282 Hz.
   Resolver specs must use the exact live parameter names and sections, not
   the abbreviated labels in the layout table below. For Band N, use
   `"Band N Used"`, `"Band N Frequency"`, `"Band N Gain"`, `"Band N Q"`,
   `"Band N Shape"`, and `"Band N Slope"`, each with section `"Band N"`.
   For a table containing several requested bands, store `freq_hz`, `gain_db`,
   and display Q, then convert in the deferred write loop:

```lua
local function proq_freq_norm(hz) return math.log(hz / 10) / math.log(3000) end
local function proq_gain_norm(db) return (db + 30) / 60 end
local function proq_q_norm(q) return math.log(q / 0.025) / math.log(1600) end

-- Human-unit row: readable and immune to adjacent-row copy mistakes.
local band = { freq_hz = 250, gain_db = -2, q = 1.2 }

-- Inside the one deferred parameter-write phase, after the mandatory
-- resolver call has returned these exact Band 1 targets:
reaper.TrackFX_SetParamNormalized(
  tr, fx, mapped[2], proq_freq_norm(band.freq_hz))
reaper.TrackFX_SetParamNormalized(
  tr, fx, mapped[3], proq_gain_norm(band.gain_db))
reaper.TrackFX_SetParamNormalized(
  tr, fx, mapped[4], proq_q_norm(band.q))
```

   Prefer the formulas in runnable scripts. If a verified normalized literal
   is unavoidable, copy each display/value pair atomically. In particular,
   80 Hz is 0.2597, 120 Hz is 0.3104, and 250 Hz is 0.4020. Never use 0.266
   for 80 Hz; it displays approximately 84 Hz.

### BAND LAYOUT (23 params per band)

```
Formula: base = (N - 1) * 23

Offset  Name                          Type        Notes
------  ----------------------------  ----------  --------------------------
+0      N Used                        enum        0=Unused, 1=In Use
+1      N Enabled                     toggle      1=Enabled (default)
+2      N Frequency                   continuous  Hz 10..30000 (see Freq scale)
+3      N Gain                        continuous  dB -30..+30 linear
+4      N Q                           continuous  0.025..40 (see Q scale)
+5      N Shape                       enum        10 shapes (see Shape enum)
+6      N Slope                       numeric     dB/oct (see Slope param -- typed input, NOT a strict enum)
+7      N Stereo Placement            enum        Stereo / L / R / Mid / Side
+8      N Speakers                    enum        Speaker routing selection
+9      N Dynamic Range               continuous  dB -30..+30 bipolar (0=off)
+10     N Dynamics Enabled            toggle      1=Enabled
+11     N Dynamics Auto               enum        0=Auto, 1=Manual
+12     N Threshold                   enum/cont   Auto or manual dB
+13     N Attack                      continuous  % 0..100 (default 50%)
+14     N Release                     continuous  % 0..100 (default 50%)
+15     N External Side Chain         toggle      0=Off, 1=On
+16     N Side Chain Filtering        enum        Band / External
+17     N Side Chain Low Frequency    continuous  Hz (shares Freq scale)
+18     N Side Chain High Frequency   continuous  Hz (shares Freq scale)
+19     N Side Chain Audition         toggle
+20     N Spectral Enabled            toggle      Spectral processing for band
+21     N Spectral Density            continuous  % spectral depth
+22     N Solo                        toggle      Isolate this band only

Band 1: indices 0-22       Band 13: indices 276-298
Band 2: indices 23-45      ...
Band 3: indices 46-68      Band 24: indices 529-551
```

### GLOBAL PARAMS

```
idx  Name                  Default val  Notes
---  --------------------  -----------  ---------------------------------
552  Processing Mode       0            0=Zero Latency, 1=Natural Phase, 2=Linear Phase
553  Processing Resolution 0.25         Medium / Low / High / Max
554  Character             0            Clean / etc.
555  Gain Scale            0.5          % scales all band gains (100% default)
556  Output Level          0.5          dB output trim (0.5=0dB)
559  Bypass                0            1=bypassed
560  Output Invert Phase   0            0=Normal, 1=Inverted
561  Auto Gain             0            0=Off, 1=On
```

### FREQUENCY SCALE (10 Hz..30000 Hz, log)

Formula: Hz = 10 * 3000^slider. Slider = log(Hz / 10) / log(3000).

Common target frequencies:

```
20 Hz   = 0.0866    250 Hz   = 0.4020    2 kHz   = 0.6618
30 Hz   = 0.1372    500 Hz   = 0.4884    3 kHz   = 0.7124
50 Hz   = 0.2010    800 Hz   = 0.5474    4 kHz   = 0.7484
80 Hz   = 0.2597    1 kHz    = 0.5752    5 kHz   = 0.7761
100 Hz  = 0.2876    1.5 kHz  = 0.6257    8 kHz   = 0.8349
120 Hz  = 0.3102                         10 kHz  = 0.8627
150 Hz  = 0.3382                         12 kHz  = 0.8855
200 Hz  = 0.3742                         16 kHz  = 0.9213
                                         20 kHz  = 0.9494
                                         24 kHz  = 0.9721
```

The formula is exact; compute arbitrary Hz directly.

### GAIN SCALE (-30..+30 dB linear)

Formula: dB = -30 + slider * 60. Slider = (dB + 30) / 60.

```
-30 dB = 0.000     -6 dB = 0.400     +3 dB = 0.550
-18 dB = 0.200     -3 dB = 0.450     +6 dB = 0.600
-12 dB = 0.300      0 dB = 0.500     +12 dB = 0.700
 -9 dB = 0.350      +1 dB = 0.517    +18 dB = 0.800
                    +2 dB = 0.533    +24 dB = 0.900
                                     +30 dB = 1.000
```

Band 1 default: -2.7 dB (slider 0.455).

### Q SCALE (0.025..40, log)

Formula: Q = 0.025 * 1600^slider. Slider = log(Q / 0.025) / log(1600).

Useful Q targets:

```
0.5 (wide)          = 0.4060    0.707 (Butterworth) = 0.4528
0.8                 = 0.4698    0.9                 = 0.4857
1.0 (medium)        = 0.5000 *  1.1                 = 0.5129
1.2                 = 0.5247    1.41 (Linkwitz)     = 0.5465
2.0 (narrow)        = 0.5940    4.0 (very narrow)   = 0.6882
10.0 (surgical)     = 0.8120
```

### SHAPE ENUM (offset +5, 10 shapes)

Formula: slider = shape_value / 9.

```
Value  Shape         Slider target    Uses Gain?   Uses Q?   Uses Slope?
-----  ------------  --------------   ----------   -------   -----------
0      Bell          0.000 *          yes          yes       yes, default 12 dB/oct for boosts/cuts
1      Low Shelf     0.111            yes          yes       no
2      Low Cut       0.222            no           optional  yes
3      High Shelf    0.333            yes          yes       no
4      High Cut      0.444            no           optional  yes
5      Notch         0.556            no           yes       no
6      Band Pass     0.667            no           yes       no
7      Tilt Shelf    0.778            yes          yes       no
8      Flat Tilt     0.889            yes          no        no
9      All Pass      1.000            no           yes       no
```

### SLOPE PARAM (offset +6, fingerprint-verified direct mapping)

Applies to Low Cut and High Cut shapes (Shape values 2 and 4; see Shape enum
above) and to Bell bands. For any Bell boost/cut, set Slope to **12 dB/oct**
unless the user specifies another slope. That matches the Pro-Q 4 default and
is preferable to leaving the fresh band at the host-reported/default-state
value, which has produced 48 dB/oct.

Slope is **NOT** a strict enum: Pro-Q 4 exposes a dropdown of preset values and
accepts arbitrary fractional values (e.g. 27 dB/oct). Treat it as a continuous
numeric parameter, not a fixed enum.

The dropdown presets observed on a current Pro-Q 4 install (subject to
change across versions):

```
0 dB/oct  6 dB/oct  12 dB/oct  18 dB/oct  24 dB/oct  30 dB/oct
36 dB/oct  48 dB/oct  72 dB/oct  96 dB/oct  Brickwall
```

This profile body is injected only after ReaAssist has matched the exact
installed VST3 identifier, parameter count, required parameter anchors and
full observed fingerprint. For that validated build, the host scale was
calibrated against the actual Pro-Q 4 GUI:

```lua
local function proq4_slope_norm(db_per_oct)
  if db_per_oct <= 36 then return db_per_oct / 60 end
  if db_per_oct <= 48 then return 0.6 + (db_per_oct - 36) / 120 end
  return 0.7 + (db_per_oct - 48) / 240
end

reaper.TrackFX_SetParamNormalized(tr, fx, slope_idx, 0.2)  -- 12 dB/oct
reaper.TrackFX_SetParamNormalized(tr, fx, slope_idx, 0.4)  -- 24 dB/oct
reaper.TrackFX_SetParamNormalized(
  tr, fx, slope_idx, proq4_slope_norm(27))                 -- 27 dB/oct
```

The verified anchors are the authority that makes these direct values safe.
If the installed build drifts, this body is not injected and ReaAssist must
fall back to fresh live discovery. Never reuse this scale from a rejected or
generic-only Pro-Q instance. Valid numeric range is 0 to 96 dB/oct; Brickwall
is the nonnumeric top state and is valid only for Low Cut or High Cut. The
minimum for Bell and Notch is 12 dB/oct, for shelves it is 6 dB/oct and for
Low Cut, High Cut and Band Pass it is 0 dB/oct. Reject an out-of-range or
shape-incompatible request instead of silently clamping it.

### MUSICAL INTENT GUIDANCE

For open-ended requests, prefer the fewest bands that express the user's
intent. A clean, musical starting point is usually one or two conservative
corrections, not a busy curve. Do not add a presence or air boost merely
because a track is named "vocal" when the user asked only to remove rumble or
mud.

Normal user language and conservative starting regions:

```
Intent                         Shape       Frequency       Gain        Q          Slope
remove vocal rumble            Low Cut     60..110 Hz      n/a         0.71       12..24 dB/oct
remove guitar/room rumble      Low Cut     50..100 Hz      n/a         0.71       12..24 dB/oct
reduce boom/wool               Bell        70..180 Hz      -1..-3 dB   0.7..1.5   12 dB/oct
reduce mud/boxiness            Bell        180..500 Hz     -1..-4 dB   0.7..2.0   12 dB/oct
tame broad harshness           Bell        2.5..6 kHz      -1..-3 dB   0.7..1.8   12 dB/oct
add broad presence             Bell/Shelf  2.5..6 kHz      +0.5..2 dB  0.5..1.2   12 dB/oct
add air/sheen                  High Shelf  8..16 kHz       +0.5..2 dB  0.4..1.0   6..12 dB/oct
```

These are starting regions, not automatic mix decisions:

- "Subtle," "natural" or "without making it thin" means use one broad, modest
  Bell move when that can express the intent. Do not add a Low Cut merely as
  routine cleanup, and do not stack several narrow cuts.
- "Remove rumble" calls for a Low Cut, not a low-shelf boost/cut. Choose the
  lower end of the range for bass-heavy sources and the higher end only when
  the source clearly permits it.
- "Mud" or "boxiness" usually calls for a broad Bell cut in the low mids. It
  does not authorize a high-frequency boost.
- "Muddy and boomy" are often overlapping descriptions, not two independent
  problems. For a simple, gentle request, especially one that says not to make
  the source thin, prefer one broad Bell cut around 150..350 Hz at about
  -1..-3 dB and Q 0.7..1.5. Do not add a Low Cut unless the user explicitly
  mentions rumble, subsonic energy or unwanted content below the musical
  range, or trustworthy source context clearly requires one.
- "Harshness" is source-dependent. A small broad static cut is a safe starting
  point; dynamic or spectral processing should be used only when the user asks
  for it or the available audio/context supports that choice.
- Leave Processing Mode, Character, Auto Gain, output controls, analyzer
  settings, instance controls and unused bands unchanged unless the request
  specifically needs them.
- For a fresh ordinary corrective band, use Stereo placement and do not create
  Mid/Side or channel-specific processing unless requested.

When the request combines genuinely distinct intentions such as explicit
rumble plus boxiness, use one band per intention and stop. Do not treat nearby
descriptions such as boom, wool, mud and boxiness as automatically distinct.
When the wording is too vague to choose a responsible frequency area from the
track/source context, ask one short question rather than applying a generic
smile curve.

### COMMON RECIPES

### TRACK-TYPE STARTER EQS

Use these only for open-ended requests such as "apply generic EQ settings",
"general EQ for each track type", or "type-appropriate EQ". They are conservative
starting points, not mix decisions. For multi-track generic EQ, use one
human-unit table and one loop. Convert Frequency, Gain and Q with the exact
formulas above inside the deferred write phase. Each runnable script still
needs one complete profile-resolver table and literal `mapped[N]` references;
do not turn the stored band offsets below into raw write indices or a local
setter wrapper.

```lua
local proq4_track_type_starters = {
  vox = {
    { band = 1, freq_hz = 100, shape = "Low Cut",
      slope_db_per_oct = 24 },
    { band = 2, freq_hz = 350, shape = "Bell",
      gain_db = -3, q = 1.0, slope_db_per_oct = 12 },
    { band = 3, freq_hz = 5000, shape = "High Shelf",
      gain_db = 2, q = 0.48 },
  },
  guitar = {
    { band = 1, freq_hz = 120, shape = "Low Cut",
      slope_db_per_oct = 24 },
    { band = 2, freq_hz = 250, shape = "Bell",
      gain_db = -2, q = 1.0, slope_db_per_oct = 12 },
    { band = 3, freq_hz = 4000, shape = "High Shelf",
      gain_db = 1, q = 0.48 },
  },
  kick = {
    { band = 1, freq_hz = 80, shape = "Bell",
      gain_db = 3, q = 1.0, slope_db_per_oct = 12 },
    { band = 2, freq_hz = 350, shape = "Bell",
      gain_db = -4, q = 1.0, slope_db_per_oct = 12 },
    { band = 3, freq_hz = 4000, shape = "Bell",
      gain_db = 3, q = 1.0, slope_db_per_oct = 12 },
  },
}

local proq4_track_type_aliases = {
  vocal = "vox",
  vocals = "vox",
  kick_drum = "kick",
}
```

When the track name has a clear alias, map it before lookup: "vox" and
"vocal" use the same starter; "kick drum" uses `kick`. If no starter matches,
use the closest conservative recipe from the user's named source type or ask
one short question.

**"Explicit rumble cleanup: Low Cut at 80 Hz, 24 dB/oct:"**

```lua
local band = {
  band = 1, freq_hz = 80, shape = "Low Cut", slope_db_per_oct = 24
}
```

**"Vocal de-mud (pull -3 dB around 350 Hz with Q=1):"**

```lua
local band = {
  band = 1, freq_hz = 350, shape = "Bell",
  gain_db = -3, q = 1.0, slope_db_per_oct = 12
}
```

**"Presence shelf (boost +2 dB shelf from 5 kHz up):"**

```lua
local band = {
  band = 1, freq_hz = 5000, shape = "High Shelf",
  gain_db = 2, q = 0.48
}
```

**"Dynamic de-ess at 7 kHz (band 1 with dynamic -6 dB when excited):"**

```lua
local band = {
  band = 1, freq_hz = 7000, shape = "Bell",
  gain_db = 0, q = 4.4, slope_db_per_oct = 12,
  dynamic_range_db = -6, dynamics_enabled = true,
  dynamics_threshold = "Auto"
}
```

**"Full vocal chain EQ (HPF + cut mud + boost presence + roll top):"**

This is intentionally a human-unit recipe, not raw runnable index code. Build
one resolver table containing every exact Band 1-4 target, verify it in full,
then make all writes through its returned `mapped[N]` indices.

```lua
local bands = {
  { band = 1, freq_hz = 80, shape = "Low Cut",
    slope_db_per_oct = 24 },
  { band = 2, freq_hz = 350, shape = "Bell",
    gain_db = -3, q = 1.0, slope_db_per_oct = 12 },
  { band = 3, freq_hz = 5000, shape = "High Shelf",
    gain_db = 2, q = 0.48 },
  { band = 4, freq_hz = 16000, shape = "High Cut",
    slope_db_per_oct = 12 },
}
```

### FINAL MUSICAL INTENT CHECK

This final check has priority over the starter tables and examples above.
Before returning code, remove every band that is not clearly authorized by
the user's words and available trustworthy context.

- If the request says the sound is muddy and/or boomy while also asking for a
  simple, gentle result that does not become thin, create exactly one broad
  Bell cut in the overlapping 150..350 Hz region. A conservative default is
  about -2 dB with Q near 1.0 and the required 12 dB/oct Bell slope.
- In that situation, do not create a Low Cut, High Cut, shelf, boost, dynamic
  band or second corrective band.
- The word "boomy" by itself does not authorize a Low Cut. A Low Cut requires
  an explicit request for rumble, subsonic cleanup, a high-pass/Low Cut, or
  unwanted energy below the musical range, or unambiguous trustworthy source
  context that calls for it.
- If any proposed move risks contradicting "without making it thin," omit that
  move. Minimal, musically coherent work is better than routine cleanup.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-Q 4 -->

<!-- PLUGIN:Pro-R 2 -->
<!-- SECTION-REVISION:3845ba52e20d608a00a3a5cfe12c17e04334e05a170481f11d165bbd302e2a2a -->
## Pro-R 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-r-2","display_name":"Pro-R 2","vendor":"FabFilter","product_class":"ordinary","preference_type":"reverb","identifiers":{"add_by_name":["VST3: Pro-R 2","VST3: Pro-R 2 (FabFilter)"],"aliases":["pro-r 2","pro-r","fabfilter pro-r 2","VST3: Pro-R 2","VST3: Pro-R 2 (FabFilter)"],"curated":["Pro-R 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro r"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-r-2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-R 2","loaded_name":"VST3: Pro-R 2 (FabFilter)","parameter_count":{"mode":"exact","value":276},"required_parameters":[{"index":0,"name":"Space","section":"","section_required":false},{"index":33,"name":"Decay EQ Band 3 Used","section":"Decay EQ Band 3","section_required":true},{"index":67,"name":"Post EQ Band 1 Slope","section":"Post EQ Band 1","section_required":true},{"index":100,"name":"Post EQ Band 5 Gain","section":"Post EQ Band 5","section_required":true},{"index":135,"name":"Midi State","section":"","section_required":false}],"observed_fingerprint_sha256":"144a87c5108b77e92fa48febcf4d34cdf101768c02c07bc3a7bd36f292e5322f"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"1cf564a63d2b77f8ad5f44fd53d8fa54f8443f8a1afd20c60559ca0d1d7af3d3","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
FabFilter Pro-R 2 is a natural-sounding reverb with macro-style controls
(Space, Decay Rate, Distance, Brightness, Character, Thickness) and
post-EQ. Designed for quick tonal shaping without managing individual
reflections.

AddByName identifier: use the exact preferred identifier, normally "VST3: Pro-R 2"
Total params (current VST3 instance): 276 exposed. This reference documents the
audible/useful macro controls and representative internal EQ params; leave
utility, modulation, and host-routing params outside the tables at defaults.

### PARAM INDEX TABLE (macro controls, idx 0-18)

```
idx  Name                  Default val   Type        Notes
---  --------------------  -----------   ----------  ---------------------------
0    Space                 0.5           continuous  Room size / decay time (see scale)
1    Decay Rate            0.5           continuous  % of base decay (0.5 = 100%)
2    Distance              0.5           continuous  % 0..100 (0.5 = 50% front/back)
3    Brightness            0.5           continuous  Bipolar: 0.5 = neutral
4    Style                 0             enum        Modern / Vintage / Plate (see enum)
5    Character             0.3           continuous  Amount of coloration (0..100%)
6    Thickness             0.5           continuous  Bipolar: 0.5 = neutral
7    Stereo Width          0.583         continuous  % 0..120 (0.5 = 100%, default 70%)
8    Ducking               0             continuous  dB auto-ducking (0 = off)
9    Mix                   0.225         continuous  % 0..100 dry/wet (default ~22.5%)
10   Lock Mix              0             toggle      1 = preserve Mix when switching presets
11   Freeze                0             toggle      1 = infinite hold
12   Auto Gate             0.25          continuous  ms reverb-decay threshold (0..1000)
13   Auto Gate Enabled     0             toggle      0=Off, 1=On
16   Predelay              0.0645        continuous  ms 0..500 (log-ish scale)
17   Predelay Offset       0.5           continuous  % offset 0..200
18   Predelay Sync         0             enum        Free / various note values
```

Idx 19-32 = Decay EQ (two internal bands shaping reverb tail per-frequency).

### POST EQ BAND LAYOUT (zero-based idx 61-78)

The first two documented Post EQ bands shape the reverb output. Each band
uses nine consecutive parameters:

```
Band   Base   +0       +1        +2         +3    +4   +5     +6      +7                 +8
-----  -----  -------  ---------  ---------  ----  ---  -----  ------  -----------------  --------
1      61     Used     Enabled    Frequency  Gain  Q    Shape  Slope   Stereo Placement   Speakers
2      70     Used     Enabled    Frequency  Gain  Q    Shape  Slope   Stereo Placement   Speakers
```

For Post EQ Band 1, the exact zero-based indices are: Used 61, Enabled 62,
Frequency 63, Gain 64, Q 65, Shape 66. Q is offset +4 and Shape is +5;
do not shift them to +5/+6. Use the exact index list above rather than adapting
another plugin's surrounding parameter layout.

When activating an unused band, set both `Used` and `Enabled` to 1 before
writing its requested values. Frequency, Gain, and Q are numeric: use a
verified normalized target below or `set_param_display`. Shape is a text enum:
use a verified normalized target or `set_param_enum`; never pass a numeric
target to `set_param_display` for Shape. If an `fx_params:Pro-R 2` bucket is
pinned for this exact instance, its live names, enums, and order override this
static layout. Usually leave Post EQ at defaults unless the user explicitly
asks to tune the reverb tone.

Verified Post EQ Band 1 targets (REAPER 7.77, Pro-R 2 VST3):

```
Control       Display target   Normalized
------------  ---------------  ----------
Frequency     2000 Hz          0.66176
Gain          -3.00 dB         0.44992
Q             1.000            0.50003
Shape         Bell             0.00000
```

For this exact target combination, use these direct values; do not derive or
linearly interpolate them. Other numeric targets should use
`set_param_display`, and other Shape targets should use `set_param_enum`.

This Post EQ layout is self-contained for the documented controls. When the
request only uses these controls, do not request Pro-Q 4 or `fx_inspect`:
Pro-R 2's Post EQ is part of Pro-R 2, not a separate EQ plugin.

Idx 115-123 = "Tilt" params for macro-to-band response (advanced; default
0.5 = balanced). Leave at defaults.

### BRIGHTNESS SCALE (idx 3)

Brightness is bipolar from -100% to +100% with neutral at normalized 0.50:

```lua
local brightness_normalized = (display_percent + 100) / 200
```

Therefore +20% is exactly normalized `0.60`. Do not use `0.70` for +20%;
`0.70` displays +40%. For an exact requested percentage, calculate it with
this formula or copy the verified literal and confirm the formatted value.

### SPACE SCALE (200 ms..10 sec, log-like)

Overall reverb time / character. Smaller values = small rooms; larger = halls.

```
slider   Decay time     slider   Decay time
-------  -----------    -------  -----------
0.00     200 ms         0.50     2.5 sec *
0.10     400 ms         0.60     3.2 sec
0.20     750 ms         0.70     4.0 sec
0.25     1.0 sec        0.80     5.2 sec
0.30     1.25 sec       0.90     7.0 sec
0.40     1.85 sec       1.00     10.0 sec
```

Useful room targets:

```
Small room    ~ 0.10     Medium hall  ~ 0.50 (default)
Vocal booth   ~ 0.15     Large hall   ~ 0.70
Live room     ~ 0.25     Cathedral    ~ 0.90+
```

### STYLE ENUM (idx 4)

Current probe found exactly 3 values.

```
Slider    Display      Feel
-------   -----------  ----------------------------
0.00      Modern       Clean, neutral (default)
0.25      Vintage      Warm, analog-flavored
0.75      Plate        Metallic, bright, dense
```

### PREDELAY SYNC ENUM (idx 18)

```
Slider    Display
-------   ------------
0.000     Free
0.125     1/4 Note
0.375     1/8 Note
0.625     1/16 Note
0.875     1/32 Note
```

### MIX SCALE (idx 9, dry/wet)

Linear, 0..100%. Default ~22.5% for send-bus-style usage.

```
 0% = 0.000          25%  = 0.250           100% = 1.000
10% = 0.100          50%  = 0.500 (equal mix)
20% = 0.200 *        75%  = 0.750
```

Most uses: 15-30% (send-bus reverb) or 100% (wet-only on a send track).

### PREDELAY SCALE (idx 16)

Log-like scale, 0..500 ms. Default 0.645 ms (essentially zero).

```
slider   ms              slider   ms
-------  -----           -------  -----
0.00     0               0.40     ~30
0.065    0.645 *         0.60     ~90
0.10     ~1.5            0.80     ~250
0.20     ~6              1.00     500
0.30     ~15
```

Useful targets: 20 ms ≈ slider 0.34, 50 ms ≈ 0.49, 100 ms ≈ 0.63.

### DUCKING SCALE (idx 8)

0..24 dB of auto-ducking when input signal is present. 0 = off.

```
0 dB  = 0.000 (off, default)     -6 dB  = 0.500
-3 dB = 0.250                     -12 dB = 0.750
                                  -24 dB = 1.000
```

### COMMON RECIPES

**"Vocal plate (quick bright plate for vocals):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.20)   -- Space: 750 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 3,  0.60)   -- Brightness: +20%
reaper.TrackFX_SetParamNormalized(tr, fx, 4,  0.85)   -- Style: Plate
reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.25)   -- Mix: 25%
reaper.TrackFX_SetParamNormalized(tr, fx, 16, 0.40)   -- Predelay: ~30 ms
```

For the exact +20% vocal-plate request, the Brightness write must remain
normalized `0.60`. Normalized `0.70` is a failed target because it displays
+40.0%. Resolve the five exact live names and write them once in this order:
Space, Brightness, Style, Mix, Predelay.

**"Refine an existing short bright vocal plate so it stays behind the dry vocal:"**

When the existing Pro-R 2 already shows Space 750 ms, Brightness +20%, Plate
style, Mix 25% and Predelay 30 ms, preserve those five controls. Set only
Distance to 70% so the modeled source sits farther back. Do not rewrite the
five already-correct controls or add EQ, Ducking, Width, Character, Thickness,
Decay Rate or Decay EQ changes.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 2, name = "Distance", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.70) -- Distance: 70.0%
```

**"Drum room (short, tight, punchy):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.10)    -- Space: 400 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.30)    -- Distance: closer
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.33)    -- Style: Vintage
reaper.TrackFX_SetParamNormalized(tr, fx, 8, 0.40)    -- Ducking: ~-5 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 9, 0.15)    -- Mix: 15%
```

**"Hall / large ambient (lush wide tail):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.70)    -- Space: 4 sec
reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.45)    -- Brightness: slight dark
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.0)     -- Style: Modern
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.75)    -- Stereo Width: wide
reaper.TrackFX_SetParamNormalized(tr, fx, 9, 0.30)    -- Mix: 30%
reaper.TrackFX_SetParamNormalized(tr, fx, 16, 0.49)   -- Predelay: ~50 ms
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Pro-R 2 -->

<!-- PLUGIN:Saturn 2 -->
<!-- SECTION-REVISION:4233cd3d50f75b3168e216259295b2baa0cf728820f621d155818bc343795cc7 -->
## Saturn 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-saturn-2","display_name":"Saturn 2","vendor":"FabFilter","product_class":"dynamic","preference_type":"saturation","identifiers":{"add_by_name":["VST3: Saturn 2","VST3: Saturn 2 (FabFilter)"],"aliases":["saturn 2","saturn","fabfilter saturn 2","VST3: Saturn 2","VST3: Saturn 2 (FabFilter)"],"curated":["Saturn 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["saturn"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-saturn-2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Saturn 2","loaded_name":"VST3: Saturn 2 (FabFilter)","parameter_count":{"mode":"exact","value":1091},"required_parameters":[{"index":0,"name":"Input Gain","section":"","section_required":false},{"index":238,"name":"XLFO 2 Step 6 Glide","section":"XLFO 2","section_required":true},{"index":475,"name":"XLFO 5 Step 10 Random","section":"XLFO 5","section_required":true},{"index":712,"name":"Slot 3 Level","section":"Slot 3","section_required":true},{"index":950,"name":"Slot 50 Target","section":"Slot 50","section_required":true}],"observed_fingerprint_sha256":"b41513a14dd3a4a05e3dce6422c07013dbddd667d17a96f11ff88cbf414b2a8e"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"bef1b4ae622b22ab0ed2182db9d6dfe14b60f3a05c35de429b2e37fae63928f3","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
FabFilter Saturn 2 is a multiband saturation/distortion processor with 21+
character styles (tube, tape, amp, transformer, etc.), per-band tone shaping
(Bass/Mid/Treble/Presence), modulation, feedback, and up to 6 user bands.

AddByName identifier: use the exact preferred identifier, normally "VST3: Saturn 2"
The host exposes 1091 parameters. Primary global and six-band controls occupy
indices 0-108. This reference spells out Bands 1-2 as representative; Bands
3-6 follow the same 17-parameter stride. Indices 109 and above include
modulation, routing, MIDI and internal controls that are outside these recipes.

### CRITICAL CONSTRAINTS

1. **Start with `Num Active Bands` (idx 6)** set to the number of bands you
   want (1..6). Default is 1 active band. Setting >1 activates subsequent
   bands' params.

2. **Drive is the main processing parameter** at idx 11 (Band 1 Drive).
   Default 20% is modest; 40-60% is typical; 80%+ is aggressive.

3. **Bass / Mid / Treble / Presence (offsets +6..+9)** are per-band post-
   saturation tone shaping. Default 0 dB (slider 0.5). Range is bipolar.

4. **Heavy modulation params (XLFO, EG, XY controllers)** at idx 109+ are
   intentionally not documented here because they are rarely script-set. Use the
   UI. Main-chain controls below are what scripts should touch.

5. **Resolve exact names and sections before writing.** Every band parameter
   name begins with `Band N`, and its section is also exactly `Band N`. Never
   use shorthand such as `1 Style`, `N Style` or a blank section. Resolve all
   requested targets in one literal table before the first write. The static
   safety validator must be able to inspect the literal entries at the resolver
   call:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 6,  name = "Num Active Bands" },
  { index = 10, name = "Band 1 Style",
    section = "Band 1", section_required = true },
  { index = 11, name = "Band 1 Drive",
    section = "Band 1", section_required = true },
  { index = 13, name = "Band 1 Bass",
    section = "Band 1", section_required = true },
  { index = 18, name = "Band 1 Level",
    section = "Band 1", section_required = true },
})
if not mapped then error(guard_err) end
```

6. **Keep parameter units literal.** `Band N Dynamics` is index 9 for Band 1
   and uses a unitless `-1.000` to `1.000` display with `0.000` neutral.
   `Band N Drive Pan` is index 12 for Band 1 and uses the same unitless
   display. Never send percentage targets such as `"20.0%"` to either
   parameter. Percentage displays belong to controls such as Drive and Mix.
   For a plain warm-tape bass request, leave Dynamics and Drive Pan unchanged
   unless the user explicitly asks for dynamics or stereo-drive changes.

Use `mapped[1]` through `mapped[5]` in that order. For a one-band Clean Tape
request with 30% Drive, +2 dB Bass and 0 dB Level, this validated 1091-parameter
fingerprint has direct normalized values: `0.0`, `0.17`, `0.30`,
`0.541748046875` and `0.49995118379592896`. They produce formatted displays
`"1"`, `"Clean Tape"`, `"30.0%"`, `"+2.00 dB"` and `"0.00 dB"` respectively.
Use direct `TrackFX_SetParamNormalized` calls for this recipe and verify all
five formatted displays. Do not call or define `set_param_display`,
`set_param_enum` or another probing helper for these five known mappings.

For a natural request to give bass gentle warm tape character without obvious
distortion or excess level, use that same canonical one-band recipe exactly:
one active band, `Clean Tape`, `30.0%` Drive, `+2.00 dB` Bass and `0.00 dB`
Level. This wording does not ask for the default 20% Drive. Do not substitute
20%, 25% or another conservative estimate. On an existing instance, change
only those five controls. Preserve Dynamics, Drive Pan, Mid, Treble, Presence,
Mix, crossover and all other controls unless the user names them.

Use the complete direct-write recipe below for this natural request. It needs no
parameter helper definitions and must retain the exact verified values.

For a request that adds Saturn 2 and configures it, perform the existence check,
`TrackFX_AddByName`, parameter resolution and every parameter write inside the
same outer `reaper.defer()` and exactly one `Undo_BeginBlock` / `Undo_EndBlock`
pair. Begin the undo block before adding the plug-in and end it only after the
last verified write. Never add Saturn 2 synchronously and defer only the
parameter work. One Undo must remove the new Saturn 2 instance and restore the
original FX count.

### GLOBAL PARAMS

```
idx  Name                Default val   Type        Notes
---  ------------------  -----------   ----------  ---------------------------
0    Input Gain          0.5           continuous  dB, 0.5=0dB
2    Output Gain         0.486         continuous  dB, 0.5=0dB (default -1 dB)
4    Bypass              0             toggle      1=bypassed
5    Mix                 1.0           continuous  % dry/wet, 1.0=100% wet
6    Num Active Bands    0             int         0=1 band, up to 5=6 bands
```

### BAND LAYOUT (17 params per band)

```
Formula: base = 7 + (N - 1) * 17  (Band 1: idx 7-23; Band 2: idx 24-40)

Offset  Name                        Type        Notes
------  --------------------------  ----------  ---------------------------
+0      Band N Feedback Amount      continuous  % 0..100 (default 0)
+1      Band N Feedback Frequency   continuous  Hz (see Crossover scale)
+2      Band N Dynamics             continuous  Unitless -1..1 (0.000 neutral)
+3      Band N Style                enum        21+ styles (see Style enum)
+4      Band N Drive                continuous  % 0..100 linear (default 20%)
+5      Band N Drive Pan            continuous  Unitless -1..1 (0.000 center)
+6      Band N Bass                 continuous  dB tone (0.5=0dB)
+7      Band N Mid                  continuous  dB tone (0.5=0dB)
+8      Band N Treble               continuous  dB tone (0.5=0dB)
+9      Band N Presence             continuous  dB tone (0.5=0dB)
+10     Band N Mix                  continuous  Per-band wet (1.0=100%)
+11     Band N Level                continuous  Band output trim (0.5=0dB)
+12     Band N Pan                  continuous  Mid/Side or L/R pan
+13     Band N Enabled              toggle      1=enabled
+14     Band N State                enum        Normal / Solo / Mute
+15     Band N Crossover Frequency  continuous  Hz (log, see scale)
+16     Band N Crossover Slope      enum        dB/oct (see slope enum)

Band 1: indices 7-23
Band 2: indices 24-40
Every row for Band N has section `Band N`.
```

### STYLE ENUM (per-band, offset +3)

21+ saturation models, indexed by probe. Each value spans ~1/20 slider width.

```
slider  Display                slider  Display
------  ---------------------  ------  ---------------------
0.00    Subtle Tube            0.55    Screaming Amp
0.05    Clean Tube             0.60    Power Amp
0.10    Broken Tube            0.65    Gentle Saturation
0.15    Subtle Tape            0.70    Heavy Saturation
0.20    Clean Tape             0.75    Subtle Transformer
0.25    Old Tape               0.80    Warm Transformer *
0.30    American Tweed Amp     0.85    Smudge
0.35    American Plexi Amp     0.90    Breakdown
0.40    British Pop Amp        0.95    Rectify
0.45    Smooth Amp             1.00    Destroy
0.50    Lead Amp

* Band 1 default "Warm Tape" lands between probes -- plugin has ~24 styles
  total (more resolution than 21 probes can sample). Use the UI to find exact
  slider for a specific named style.
```

### DRIVE SCALE (offset +4)

Linear 0..100%. Formula: slider = %/100.

```
 0% = 0.000 (dry)      40% = 0.40           80% = 0.80 (aggressive)
10% = 0.10             50% = 0.50           90% = 0.90
20% = 0.20 * default   60% = 0.60          100% = 1.00 (max)
30% = 0.30             70% = 0.70
```

### TONE SHAPING (offsets +6..+9)

Post-saturation per-band tilt. Four bands of fixed-frequency shelf/bell EQ:
Bass, Mid, Treble, Presence. All use the same bipolar dB scale.

```
slider   dB             slider   dB
-------  ----           -------  ----
0.00     ~-12 dB        0.50     0 dB (default)
0.25     ~-6 dB         0.75     ~+6 dB
                        1.00     ~+12 dB
```

### CROSSOVER FREQUENCY SCALE (40..20000 Hz, log)

For offset +15 (crossover between bands) and offset +1 (feedback freq).

```
40 Hz   = 0.000      500 Hz   = 0.406      5000 Hz   = 0.812
100 Hz  = 0.151      1000 Hz  = 0.527      10000 Hz  = 0.912
200 Hz  = 0.255      2000 Hz  = 0.660      20000 Hz  = 1.000
250 Hz  = 0.290 *    2500 Hz  = 0.694
                     3000 Hz  = 0.729
```

### COMMON RECIPES

**"Warm tape on bass (gentle, 30% drive):"**

This recipe changes only the active-band count, style, Drive, Bass and Level.
Leave Dynamics, Drive Pan, Mid, Treble, Presence and Mix at their existing
values unless the request names them.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 6,  name = "Num Active Bands" },
  { index = 10, name = "Band 1 Style",
    section = "Band 1", section_required = true },
  { index = 11, name = "Band 1 Drive",
    section = "Band 1", section_required = true },
  { index = 13, name = "Band 1 Bass",
    section = "Band 1", section_required = true },
  { index = 18, name = "Band 1 Level",
    section = "Band 1", section_required = true },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.17)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.30)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.541748046875)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.49995118379592896)

local _, actual = reaper.TrackFX_GetFormattedParamValue(
  tr, fx, mapped[1], "")
if actual ~= "1" then error("Num Active Bands settled at " .. actual) end
_, actual = reaper.TrackFX_GetFormattedParamValue(tr, fx, mapped[2], "")
if actual ~= "Clean Tape" then
  error("Band 1 Style settled at " .. actual)
end
_, actual = reaper.TrackFX_GetFormattedParamValue(tr, fx, mapped[3], "")
if actual ~= "30.0%" then
  error("Band 1 Drive settled at " .. actual)
end
_, actual = reaper.TrackFX_GetFormattedParamValue(tr, fx, mapped[4], "")
if actual ~= "+2.00 dB" then
  error("Band 1 Bass settled at " .. actual)
end
_, actual = reaper.TrackFX_GetFormattedParamValue(tr, fx, mapped[5], "")
if actual ~= "0.00 dB" then
  error("Band 1 Level settled at " .. actual)
end
```

**"Aggressive amp on guitar (Lead Amp, heavy drive):"**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 10, name = "Band 1 Style",
    section = "Band 1", section_required = true },
  { index = 11, name = "Band 1 Drive",
    section = "Band 1", section_required = true },
  { index = 15, name = "Band 1 Treble",
    section = "Band 1", section_required = true },
  { index = 16, name = "Band 1 Presence",
    section = "Band 1", section_required = true },
})
if not mapped then error(guard_err) end
local ok, err = set_param_enum(tr, fx, mapped[1], "Lead Amp")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[2], "70.0%")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[3], "-3.00 dB")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[4], "+2.00 dB")
if not ok then error(err) end
```

**"Subtle tube warmth (master bus, 15% mix):"**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 5,  name = "Mix" },
  { index = 10, name = "Band 1 Style",
    section = "Band 1", section_required = true },
  { index = 11, name = "Band 1 Drive",
    section = "Band 1", section_required = true },
})
if not mapped then error(guard_err) end
local ok, err = set_param_display(tr, fx, mapped[1], "15.0%")
if not ok then error(err) end
ok, err = set_param_enum(tr, fx, mapped[2], "Clean Tube")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[3], "25.0%")
if not ok then error(err) end
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Saturn 2 -->

<!-- PLUGIN:Timeless 3 -->
<!-- SECTION-REVISION:d34a50dc1c1446024bdaa8104e97afb1b8cf994e4d69b4ae0478d46252111136 -->
## Timeless 3

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-timeless-3","display_name":"Timeless 3","vendor":"FabFilter","product_class":"dynamic","preference_type":"delay","identifiers":{"add_by_name":["VST3: Timeless 3","VST3: Timeless 3 (FabFilter)"],"aliases":["timeless 3","timeless","fabfilter timeless 3","VST3: Timeless 3","VST3: Timeless 3 (FabFilter)"],"curated":["Timeless 3"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["timeless"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-timeless-3","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Timeless 3","loaded_name":"VST3: Timeless 3 (FabFilter)","parameter_count":{"mode":"exact","value":1147},"required_parameters":[{"index":0,"name":"Delay Time","section":"","section_required":false},{"index":251,"name":"XLFO 1 Step 14 Glide function","section":"XLFO 1","section_required":true},{"index":502,"name":"XLFO 5 Step 4 Glide","section":"XLFO 5","section_required":true},{"index":754,"name":"Auto Mute Self-Osc","section":"","section_required":false},{"index":1006,"name":"Slot 50 Target","section":"Slot 50","section_required":true}],"observed_fingerprint_sha256":"8cf71e1b255ce2b697b436ec2fbd7ea2651691272863ac5d90409fc2349890c8"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"648ae333ff15516cd1e7435bfac82b97397550c4b7be8a1eade5ff7164383d46","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
FabFilter Timeless 3 is a creative delay with tape / digital / extreme read
modes, multi-tap support, per-feedback-path filters, and feedback effects
(drive, lo-fi, diffuse, dynamics, pitch shift). The host exposes 1147
parameters. Primary delay, filter, feedback-effect and mix controls occupy
indices 0-161. Typical scripts should leave the modulation system at indices
162 and above untouched unless the user explicitly asks for modulation.

AddByName identifier: use the exact preferred identifier, normally "VST3: Timeless 3"

### SAFE PARAMETER TARGETING

Resolve every requested parameter in one literal guard table before the first
write. `Filter 2 Freq` and `Filter 2 Shape` both use section `Filter 2`.
Never use `Freq Source 2`, another inferred section name or a blank section for
either control.

When the user asks for one free delay time without describing a stereo
difference, both channels must display that same time. Include `Delay Time Pan`
in the guard and match its exact compound display
`Left: 100% / Right: 100%`. Leave it alone only when the user explicitly asks
for different left/right times, a stereo offset or a panned delay time.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 3,   name = "Delay Sync" },
  { index = 0,   name = "Delay Time" },
  { index = 1,   name = "Delay Time Pan" },
  { index = 4,   name = "Delay Read Mode" },
  { index = 85,  name = "Feedback" },
  { index = 99,  name = "Filter 2 Freq",
    section = "Filter 2", section_required = true },
  { index = 104, name = "Filter 2 Shape",
    section = "Filter 2", section_required = true },
  { index = 160, name = "Mix" },
})
if not mapped then error(guard_err) end
```

Use `mapped[1]` through `mapped[8]` in that order. For exact user values, use
the canonical `set_param_display` helper for delay time, feedback, filter
frequency and mix. Use `set_param_enum` for Delay Sync, Delay Read Mode and
Filter 2 Shape, plus the exact compound Delay Time Pan display even though
that control is continuous. The compound display is not safe for numeric-only
search because its left and right percentages must both match. These helpers
verify the settled host-formatted display. Do not replace exact targets such
as `"300 ms"`, `"Left: 100% / Right: 100%"`, `"35%"`, `"3 kHz"` or `"25%"`
with assumed normalized values. The normalized scale notes below are useful
for orientation and open-ended musical choices, but the real plug-in GUI is
the user-facing authority.

For open-ended musical requests, interpret `behind`, `subtle`, `restrained`,
`tucked`, `supportive` or `without clutter` as a wet Mix of 10-25%. Never
raise an existing Mix above 25% for those descriptions. If the current Mix is
already within that range, preserve it unless a lower value is needed. A dark
tape echo behind guitar is a useful starting envelope: Tape mode, 300-450 ms,
20-40% Feedback, a Filter 2 Low Pass at 1.5-3 kHz and 10-25% Mix. Preserve
equal left/right timing unless the user asks for stereo movement. Do not add
Ping Pong, Drive, Lo-Fi, Diffuse, Dynamics or Pitch Shift unless the request
calls for that effect.

For the natural request to put a dark tape echo behind guitar without clutter,
use one exact canonical point inside that envelope: `Free`, `300 ms`,
`Left: 100% / Right: 100%`, `Tape`, `35%` Feedback, Filter 2 `Low Pass` at
`2 kHz`, and `20%` Mix. On an existing instance, change only those eight
controls. Preserve Ping Pong, Drive, Lo-Fi, Diffuse, Dynamics, Pitch Shift,
Filter 1, modulation and every other control unless the user names it. Use the
same literal guard and verified helper pattern shown in the first common recipe
below, substituting only the `2 kHz` and `20%` display targets.

For a request that adds Timeless 3 and configures it, perform the existence
check, `TrackFX_AddByName`, parameter resolution and every parameter write
inside the same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding the plug-in and end it
only after the last verified write. One Undo must remove the new Timeless 3
instance and restore the original FX count.

### PARAM INDEX TABLE (main controls)

```
idx  Name                  Default val   Type        Notes
---  --------------------  -----------   ----------  ---------------------------
0    Delay Time            0.293         continuous  ms (see Delay Time scale)
1    Delay Time Pan        0.500         compound    center shows 100% / 100%
2    Delay Offset          0.792         continuous  % stereo offset (150% default)
3    Delay Sync            0             enum        Free / various note values
4    Delay Read Mode       0             enum        Tape / Digital / Extreme
5    Delay Freeze          0             toggle      1=infinite hold
6    Ping Pong             0             toggle      0=Off, 1=On
85   Feedback              0.175         continuous  % 0..100+ (default 35%)
87   Feedback Cross Mix    0             continuous  % cross-channel feedback
90   Filter 1 Freq         0.386         continuous  Hz (see Crossover scale)
91   Filter 1 Gain         0.5           continuous  dB bipolar (0.5=0dB)
94   Filter 1 Style        1.0           enum        Clean / Character styles
95   Filter 1 Shape        0.167         enum        Low Pass / High Pass / Bell / etc.
96   Filter 1 Slope        0.333         enum        dB/oct (see Slope enum)
97   Filter 1 Enabled      1             toggle      1=enabled
99   Filter 2 Freq         0.719         continuous  Hz (Filter 1 shares scale)
103  Filter 2 Style        1.0           enum        Same as Filter 1
104  Filter 2 Shape        0             enum        0=Low Pass default
105  Filter 2 Slope        0.667         enum        Same as Filter 1
106  Filter 2 Enabled      1             toggle      1=enabled
144  Filter Routing        0             enum        0=Serial, 1=Parallel
145  Drive                 0             continuous  % feedback saturation (0..100)
146  Drive Enabled         1             toggle      0=Off, 1=On
147  Lo-Fi                 0             continuous  % bitcrush (0..100)
148  Lo-Fi Enabled         0             toggle      0=Off, 1=On
149  Diffuse               0             continuous  % spread (0..100)
150  Diffuse Enabled       0             toggle
151  Dynamics              0.5           continuous  Bipolar (0.5=neutral)
152  Dynamics Enabled      0             toggle
153  Pitch Shift           0.5           continuous  Semitones -12..+12 (0.5=0)
154  Pitch Shift Enabled   0             toggle
157  Stereo Width          1.0           continuous  % 0..200 (1.0 = 100%)
158  Wet Level             1.0           continuous  dB (1.0 = 0 dB)
160  Mix                   0.3           continuous  % 0..100 dry/wet (default 30%)
```

Multi-tap params (idx 7-16 for Tap 1/2) are for rhythmic multi-tap effects;
default "Unused" -- leave at defaults for standard single-delay use.

### DELAY TIME SCALE (5 ms..5 sec, piecewise non-linear)

Non-uniform taper with jumps -- use lookup, not formula.

```
slider   ms / sec       slider   ms / sec
-------  -----------    -------  -----------
0.00     5.0 ms         0.50     804 ms
0.05     10.0 ms        0.55     1.05 sec
0.10     15.0 ms        0.60     1.30 sec
0.15     95 ms          0.70     1.80 sec
0.20     175 ms         0.75     2.49 sec
0.25     255 ms         0.80     3.18 sec
0.293    350 ms *       0.90     4.55 sec
0.30     365 ms         1.00     5.00 sec
0.35     475 ms
0.40     584 ms
0.45     694 ms
```

Useful targets (approximate):

```
100 ms  ~ 0.155    300 ms  ~ 0.275    750 ms  ~ 0.485
150 ms  ~ 0.188    400 ms  ~ 0.315    1 sec   ~ 0.545
200 ms  ~ 0.210    500 ms  ~ 0.362    2 sec   ~ 0.718
250 ms  ~ 0.248    600 ms  ~ 0.408
```

### DELAY SYNC (idx 3, tempo-locked delay)

Enum; default Free. Slider thresholds tag musical note values (1/2, 1/4, 1/8,
dotted, triplet variants). Use `Free` (0) when setting absolute ms; use sync
values for tempo-locked delays. Exact slider values per note require UI
auditioning.

### DELAY READ MODE (idx 4)

Three values, roughly:

```
0.00  = Tape       (pitch-bending on time changes, tape feel)
0.33  = Digital    (clean, no artifacts)
0.67  = Extreme    (exaggerated pitch-bend / artifacts)
```

### FEEDBACK SCALE (idx 85, 0..200%)

Feedback amount. Default 35% at slider 0.175. 100% at slider 0.5. Above 0.5
is "runaway" feedback (self-oscillating). Watch output volume above 0.5.

```
Formula: slider = % / 200. Or: % = slider * 200.

 0%   = 0.000      50%   = 0.250     100% = 0.500 (unity feedback, careful)
10%   = 0.050      75%   = 0.375     150% = 0.750 (runaway)
25%   = 0.125      90%   = 0.450     200% = 1.000 (oscillation)
35%   = 0.175 *    95%   = 0.475
```

### FILTER SHAPE ENUM (idx 95, 104)

Six filter shapes for Filter 1/2 (used in the feedback path to darken/color
the delay as it repeats).

```
Value  Shape          Slider target
-----  -------------  -------------
0      Low Pass       0.000
1      High Pass      0.167
2      Band Pass      0.333
3      Notch          0.500
4      All Pass       0.667
5      Bell           0.833
```

Defaults: Filter 1 = High Pass (0.167), Filter 2 = Low Pass (0).

### FILTER SLOPE ENUM (idx 96, 105)

Four slopes for filters. Values at 0, 0.33, 0.67, 1.0.

```
Value  dB/oct    Slider target
-----  --------  -------------
0      6         0.000
1      12        0.333 *
2      24        0.667
3      48        1.000
```

### MIX SCALE (idx 160, dry/wet)

Linear, 0..100%. Default 30%.

```
 0% = 0.000      25% = 0.250      75%  = 0.750
10% = 0.100      50% = 0.500      100% = 1.000
30% = 0.300 *
```

### COMMON RECIPES

**"Classic 1/8-note tape echo on guitar:"**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 3,   name = "Delay Sync" },
  { index = 0,   name = "Delay Time" },
  { index = 1,   name = "Delay Time Pan" },
  { index = 4,   name = "Delay Read Mode" },
  { index = 85,  name = "Feedback" },
  { index = 99,  name = "Filter 2 Freq",
    section = "Filter 2", section_required = true },
  { index = 104, name = "Filter 2 Shape",
    section = "Filter 2", section_required = true },
  { index = 160, name = "Mix" },
})
if not mapped then error(guard_err) end
local ok, err = set_param_enum(tr, fx, mapped[1], "Free")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[2], "300 ms")
if not ok then error(err) end
ok, err = set_param_enum(
  tr, fx, mapped[3], "Left: 100% / Right: 100%")
if not ok then error(err) end
ok, err = set_param_enum(tr, fx, mapped[4], "Tape")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[5], "35%")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[6], "3 kHz")
if not ok then error(err) end
ok, err = set_param_enum(tr, fx, mapped[7], "Low Pass")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[8], "25%")
if not ok then error(err) end
```

**"Dark ping-pong delay (ambient pads):"**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0,   name = "Delay Time" },
  { index = 1,   name = "Delay Time Pan" },
  { index = 6,   name = "Ping Pong" },
  { index = 85,  name = "Feedback" },
  { index = 99,  name = "Filter 2 Freq",
    section = "Filter 2", section_required = true },
  { index = 104, name = "Filter 2 Shape",
    section = "Filter 2", section_required = true },
  { index = 160, name = "Mix" },
})
if not mapped then error(guard_err) end
local ok, err = set_param_display(tr, fx, mapped[1], "500 ms")
if not ok then error(err) end
ok, err = set_param_enum(
  tr, fx, mapped[2], "Left: 100% / Right: 100%")
if not ok then error(err) end
ok, err = set_param_enum(tr, fx, mapped[3], "On")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[4], "60%")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[5], "1.5 kHz")
if not ok then error(err) end
ok, err = set_param_enum(tr, fx, mapped[6], "Low Pass")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[7], "35%")
if not ok then error(err) end
```

**"Short slapback echo:"**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0,   name = "Delay Time" },
  { index = 1,   name = "Delay Time Pan" },
  { index = 85,  name = "Feedback" },
  { index = 160, name = "Mix" },
})
if not mapped then error(guard_err) end
local ok, err = set_param_display(tr, fx, mapped[1], "50 ms")
if not ok then error(err) end
ok, err = set_param_enum(
  tr, fx, mapped[2], "Left: 100% / Right: 100%")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[3], "10%")
if not ok then error(err) end
ok, err = set_param_display(tr, fx, mapped[4], "20%")
if not ok then error(err) end
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Timeless 3 -->

<!-- PLUGIN:Ozone 12 Clarity -->
<!-- SECTION-REVISION:1786ffe2049468f7ccdc64613837f8e00b719f12b3a5e13f394f3281fd5b5423 -->
## Ozone 12 Clarity

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-clarity","display_name":"Ozone 12 Clarity","vendor":"iZotope","product_class":"ordinary","preference_type":"mastering","identifiers":{"add_by_name":["VST3: Ozone 12 Clarity","VST3: Ozone 12 Clarity (iZotope)"],"aliases":["VST3: Ozone 12 Clarity (iZotope)"],"curated":["Ozone 12 Clarity"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-clarity","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Clarity","loaded_name":"VST3: Ozone 12 Clarity (iZotope)","parameter_count":{"mode":"exact","value":21},"required_parameters":[{"index":7,"name":"CLA: Bypass","section":"","section_required":false},{"index":8,"name":"CLA: Stereo/Main Amount","section":"","section_required":false},{"index":9,"name":"CLA: Stereo/Main Tilt","section":"","section_required":false},{"index":10,"name":"CLA: Stereo/Main Attack","section":"","section_required":false},{"index":17,"name":"CLA: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"d87b3670654af548e31c51f5fda0f78eed4cb410b320ca10725cabdf9dc60195"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/clarity.html","migrated_at":"2026-07-30","body_sha256":"3f5af89681469fc3400f639703c883e9d911f150b2d289f9126e538e54007163","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"d87b3670654af548e31c51f5fda0f78eed4cb410b320ca10725cabdf9dc60195"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Clarity VST3 component. The
installed component exposes 21 parameters. Indices 7 through 17 are its
module controls. Indices 0 through 6 are component I/O and global bypass.
Indices 18 through 20 are host Bypass, Wet and Delta. Preserve the two outer
groups unless the user explicitly requests a host-level change.

The Ozone 12 Clarity guide defines Amount as the processing strength, Tilt as
the frequency weighting, and Attack and Release as the response timing. The
action region shown in the plug-in window is not available through this host
surface. Preserve the current action region and never claim to set it.

Reuse exactly one existing instance when the user says it is already present.
Resolve every exact index and name before the first write. Keep both module
bypasses Off. Preserve every Aux control.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. A prose-only answer
is incomplete.

For the certified exact case, use Amount 30%, Tilt +1.20 dB/oct, Attack 50 ms
and Release 200 ms. For a restrained unheard-audio start, use Amount 15%,
neutral Tilt, Attack 100 ms and Release 200 ms. Describe either recipe as a
starting point because the useful amount depends on the source.

The normalized tuple in parameter order is
`{0.0, 0.30, 0.60, 0.05, 0.20, 0.0}` for the exact case and
`{0.0, 0.15, 0.50, 0.10, 0.20, 0.0}` for the natural case. Exact user values
override the natural recipe. Use this complete template and select the tuple
that matches the request:

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "CLA: Bypass" },
    { index = 8, name = "CLA: Stereo/Main Amount" },
    { index = 9, name = "CLA: Stereo/Main Tilt" },
    { index = 10, name = "CLA: Stereo/Main Attack" },
    { index = 11, name = "CLA: Stereo/Main Release" },
    { index = 12, name = "CLA: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.15)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.10)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.20)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.0)
  reaper.Undo_EndBlock("ReaAssist: set restrained Ozone 12 Clarity", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Start with a low Amount on unheard material. Keep Tilt neutral unless the user
asks for brighter or darker emphasis. Increase Amount only after listening for
brittleness, softened transients or an unnatural steady texture.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Clarity -->

<!-- PLUGIN:Ozone 12 Dynamic EQ -->
<!-- SECTION-REVISION:3408aa527833a4dd9e52a3b77613137f40786aa4c0db292046539fd39e97b5b1 -->
## Ozone 12 Dynamic EQ

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-dynamic-eq","display_name":"Ozone 12 Dynamic EQ","vendor":"iZotope","product_class":"dynamic","preference_type":"eq","identifiers":{"add_by_name":["VST3: Ozone 12 Dynamic EQ","VST3: Ozone 12 Dynamic EQ (iZotope)"],"aliases":["VST3: Ozone 12 Dynamic EQ (iZotope)"],"curated":["Ozone 12 Dynamic EQ"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-dynamic-eq","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Dynamic EQ","loaded_name":"VST3: Ozone 12 Dynamic EQ (iZotope)","parameter_count":{"mode":"exact","value":169},"required_parameters":[{"index":7,"name":"DYNEQ: Bypass","section":"","section_required":false},{"index":47,"name":"DYNEQ: Stereo/Main Frequency 4","section":"","section_required":false},{"index":48,"name":"DYNEQ: Stereo/Main Gain 4","section":"","section_required":false},{"index":52,"name":"DYNEQ: Stereo/Main Enable 4","section":"","section_required":false},{"index":86,"name":"DYNEQ: Stereo/Main Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"64cf8ebf30537a785c091f6c053f553b1ce690e7e8dc398fd7e54b26803060d1"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/dynamic-eq.html","migrated_at":"2026-07-30","body_sha256":"8553f8ee5a534b40b15decac404762a2ba1dbf2bc3f723bd34212710e7635bd5","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"64cf8ebf30537a785c091f6c053f553b1ce690e7e8dc398fd7e54b26803060d1"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Dynamic EQ VST3 component. Its 169
parameters expose six Stereo/Main nodes at indices 8 through 85, the
Stereo/Main bypass at 86, six Aux nodes at 87 through 164 and the Aux bypass
at 165. Preserve indices 0 through 6 and host indices 166 through 168.

The first-party guide confirms that each node has static Gain, dynamic Offset
Gain, Threshold, direction, timing, shape and Q. Global filter and channel
mode controls in the plug-in window are not exposed through this installed
host surface. Preserve those controls and every node the user did not name.

The certified cases use Stereo/Main node 4 only. They keep static Gain at 0 dB
and use negative Offset Gain for downward dynamic control. The exact case uses
2000 Hz, -3.00 dB Offset Gain, Q 2.00, -30.00 dB Threshold, Proportional Q,
dynamic trigger On and automatic attack/release On. The natural case uses
-1.50 dB Offset Gain with the same center, Q and threshold. Threshold and the
resulting reduction remain source-dependent starting points.

The natural recipe is still dynamic processing. Keep Dyn Trigger Mode On and
Auto Attack/Release On. Gentle wording changes only Offset Gain to -1.50 dB;
it does not authorize disabling the dynamic trigger.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. The exact normalized
tuple differs from the natural tuple only at Offset Gain: use `0.60` for the
certified -3.00 dB request and `0.6333333333333333` for the natural -1.50 dB
start. Exact user values override the natural recipe. Never change another
node or the Aux surface.

Write Shape before Enable, then write Dyn Trigger Mode and Auto Attack/Release
before the numeric node controls so selector changes cannot reset those values. Keep the
resolver entries and 13 explicit setters in the exact order shown. For the
certified exact case, change only `mapped[8]` from `0.6333333333333333` to
`0.60`; every other setter stays identical.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "DYNEQ: Bypass" },
    { index = 53, name = "DYNEQ: Stereo/Main Shape 4" },
    { index = 52, name = "DYNEQ: Stereo/Main Enable 4" },
    { index = 54, name = "DYNEQ: Stereo/Main Dyn Trigger Mode 4" },
    { index = 59, name = "DYNEQ: Stereo/Main Auto Attack/Release 4" },
    { index = 47, name = "DYNEQ: Stereo/Main Frequency 4" },
    { index = 48, name = "DYNEQ: Stereo/Main Gain 4" },
    { index = 49, name = "DYNEQ: Stereo/Main Offset Gain 4" },
    { index = 50, name = "DYNEQ: Stereo/Main Q 4" },
    { index = 51, name = "DYNEQ: Stereo/Main Threshold 4" },
    { index = 55, name = "DYNEQ: Stereo/Main Attack 4" },
    { index = 56, name = "DYNEQ: Stereo/Main Release 4" },
    { index = 86, name = "DYNEQ: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.25)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 1.0)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[6], 0.7666072845458984)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[7], 0.6666666865348816)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[8], 0.6333333333333333)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[9], 0.1596638709306717)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[10], 0.7692307829856873)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.15)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.10)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 0.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set gentle Ozone 12 Dynamic EQ node 4", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use small dynamic offsets on unheard material. Treat the threshold as a
starting point and state that the user must listen for the actual amount of
reduction. Preserve existing node positions whenever the request does not name
a specific band.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Dynamic EQ -->

<!-- PLUGIN:Ozone 12 Dynamics -->
<!-- SECTION-REVISION:d584e4a03e6861489e4bd722c750264f2cf8fe06d8e47bcec227ed07a479a5ad -->
## Ozone 12 Dynamics

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-dynamics","display_name":"Ozone 12 Dynamics","vendor":"iZotope","product_class":"dynamic","preference_type":"multiband_compressor","identifiers":{"add_by_name":["VST3: Ozone 12 Dynamics","VST3: Ozone 12 Dynamics (iZotope)"],"aliases":["VST3: Ozone 12 Dynamics (iZotope)"],"curated":["Ozone 12 Dynamics"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-dynamics","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Dynamics","loaded_name":"VST3: Ozone 12 Dynamics (iZotope)","parameter_count":{"mode":"exact","value":121},"required_parameters":[{"index":7,"name":"DYN: Bypass","section":"","section_required":false},{"index":8,"name":"DYN: Stereo/Main Global Gain","section":"","section_required":false},{"index":11,"name":"DYN: Stereo/Main Band 1 Comp Threshold","section":"","section_required":false},{"index":57,"name":"DYN: Stereo/Main Level Detection Method","section":"","section_required":false},{"index":62,"name":"DYN: Stereo/Main Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"ae29f0659f1dacc456af4d188be417cd4c76161071bcfa227be6d89ecd02415a"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/dynamics.html","migrated_at":"2026-07-30","body_sha256":"b65a73c7546888c505a0bd75a36ad8e605375fc4b9ba01cbe325c68bbee7363f","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"ae29f0659f1dacc456af4d188be417cd4c76161071bcfa227be6d89ecd02415a"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Dynamics VST3 component. It
exposes four Stereo/Main compressor and limiter bands, one Stereo/Main global
section, four Aux bands and one Aux global section. Indices 0 through 6 are
component I/O and global bypass. Indices 118 through 120 are host controls.

The plug-in window contains crossover, Auto Gain, Adaptive Release and Learn
controls that are absent from this installed host parameter surface. Preserve
the current crossover structure and never claim to set those controls.
Preserve every band except the one the user names.

The certified recipe uses Stereo/Main Band 1 as the current full-band or
lowest-band start: 0 dB Band Gain, 100% Mix, -13 dB compression Threshold,
2.00 Ratio, 20 ms Attack, 125 ms Release, 6 dB Knee and Peak detection. It
does not change limiter controls. The threshold is a starting point that must
be adjusted to the signal.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. Use the same
certified recipe for the exact and restrained natural cases, and state that
actual gain reduction was not measured.

For the certified exact request, copy all 11 setters below unchanged. These
are calibrated nonlinear Ozone normalizations, not direct percentages. In
particular, Threshold uses `0.90`, Ratio uses `0.0635451525449753`, Release
uses `0.025` and Knee uses `0.60`. Never recalculate or substitute those
values from the displayed units. Do not use loops, helper tables or compressed
setters.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "DYN: Bypass" },
    { index = 8, name = "DYN: Stereo/Main Global Gain" },
    { index = 9, name = "DYN: Stereo/Main Band 1 Gain" },
    { index = 10, name = "DYN: Stereo/Main Band 1 Mix" },
    { index = 11, name = "DYN: Stereo/Main Band 1 Comp Threshold" },
    { index = 12, name = "DYN: Stereo/Main Band 1 Comp Ratio" },
    { index = 13, name = "DYN: Stereo/Main Band 1 Comp Attack" },
    { index = 14, name = "DYN: Stereo/Main Band 1 Comp Release" },
    { index = 15, name = "DYN: Stereo/Main Band 1 Comp Knee" },
    { index = 57, name = "DYN: Stereo/Main Level Detection Method" },
    { index = 62, name = "DYN: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.5)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.5)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.9)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[6], 0.0635451525449753)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.04)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.025)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.60)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set restrained Ozone 12 Dynamics Band 1", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Keep ratios and knee moderate for a transparent start. Avoid automatic makeup
gain on unheard material. A fixed threshold cannot prove a specific amount of
compression, so ask the user to listen and adjust it after the first pass.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Dynamics -->

<!-- PLUGIN:Ozone 12 Equalizer -->
<!-- SECTION-REVISION:0eea61d3acf0cfd6eb7134aea950ca06ce4f1ea5057efb7d9bb96f9b67ac7438 -->
## Ozone 12 Equalizer

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-equalizer","display_name":"Ozone 12 Equalizer","vendor":"iZotope","product_class":"dynamic","preference_type":"eq","identifiers":{"add_by_name":["VST3: Ozone 12 Equalizer","VST3: Ozone 12 Equalizer (iZotope)"],"aliases":["VST3: Ozone 12 Equalizer (iZotope)"],"curated":["Ozone 12 Equalizer"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-equalizer","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Equalizer","loaded_name":"VST3: Ozone 12 Equalizer (iZotope)","parameter_count":{"mode":"exact","value":110},"required_parameters":[{"index":7,"name":"EQ: Bypass","section":"","section_required":false},{"index":8,"name":"EQ: Global Amount","section":"","section_required":false},{"index":13,"name":"EQ: Stereo/Main Frequency 5","section":"","section_required":false},{"index":45,"name":"EQ: Stereo/Main Enable 5","section":"","section_required":false},{"index":57,"name":"EQ: Stereo/Main Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"4f2176f2c334d3ce94fe20d5d1ed941b6b9ebdd28b34c559dfcca27b02068147"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/equalizer.html","migrated_at":"2026-07-30","body_sha256":"69f1eed6f41e2be2916728038cd2a7dc285ee90ad46a17b2504550cb554fdea5","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"4f2176f2c334d3ce94fe20d5d1ed941b6b9ebdd28b34c559dfcca27b02068147"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Equalizer VST3 component. It
exposes eight Stereo/Main nodes, eight Aux nodes and a global Amount control.
Indices 0 through 6 are component I/O and global bypass. Indices 107 through
109 are host controls. Preserve every node the user did not name.

The certified cases use Stereo/Main band 5 as a Bell at 2700 Hz, +1.50 dB,
Q 0.71, phase 0 and Global Amount 100%. The plug-in window also contains
global filter and channel mode controls that are absent from this installed
host surface. Preserve them and never claim to change them.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. Use the same
certified recipe for the exact and gentle presence-lift cases. Call it a
starting point and preserve all other Stereo/Main and Aux nodes.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "EQ: Bypass" },
    { index = 8, name = "EQ: Global Amount" },
    { index = 13, name = "EQ: Stereo/Main Frequency 5" },
    { index = 21, name = "EQ: Stereo/Main Gain 5" },
    { index = 29, name = "EQ: Stereo/Main Q 5" },
    { index = 37, name = "EQ: Stereo/Main Phase 5" },
    { index = 45, name = "EQ: Stereo/Main Enable 5" },
    { index = 53, name = "EQ: Stereo/Main Shape 5" },
    { index = 57, name = "EQ: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.5)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[3], 0.1341341286897659)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.70)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[5], 0.0429661050438881)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set gentle Ozone 12 Equalizer band 5", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use broad, low-gain moves on unheard material. Prefer changing one existing
node over rebuilding a curve. Ask the user to listen for harshness before
adding more presence.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Equalizer -->

<!-- PLUGIN:Ozone 12 Exciter -->
<!-- SECTION-REVISION:fe778ada4d7dd8c28415c410d258d1e039fd0632b01161e0f5d2f899d126ca33 -->
## Ozone 12 Exciter

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-exciter","display_name":"Ozone 12 Exciter","vendor":"iZotope","product_class":"dynamic","preference_type":"saturation","identifiers":{"add_by_name":["VST3: Ozone 12 Exciter","VST3: Ozone 12 Exciter (iZotope)"],"aliases":["VST3: Ozone 12 Exciter (iZotope)"],"curated":["Ozone 12 Exciter"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-exciter","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Exciter","loaded_name":"VST3: Ozone 12 Exciter (iZotope)","parameter_count":{"mode":"exact","value":41},"required_parameters":[{"index":7,"name":"EXC: Bypass","section":"","section_required":false},{"index":8,"name":"EXC: Stereo/Main Band 1 Amount","section":"","section_required":false},{"index":10,"name":"EXC: Stereo/Main Band 1 Mode","section":"","section_required":false},{"index":22,"name":"EXC: Stereo/Main Bypass","section":"","section_required":false},{"index":37,"name":"EXC: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"20dd5873d25b119e035b37564e0e08179004bf2b5fbb07014d275ac63ef9d0b5"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/exciter.html","migrated_at":"2026-07-30","body_sha256":"0fa7ed0515b54726715f3981b89a7a320c24d8622dbbec7cc9970ae098f75a48","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"20dd5873d25b119e035b37564e0e08179004bf2b5fbb07014d275ac63ef9d0b5"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Exciter VST3 component. It exposes
Amount, Mix and Mode for four Stereo/Main bands and four Aux bands. The
crossover, oversampling and band-link controls shown in the plug-in window are
not exposed through this installed host surface. Preserve the current
crossover structure, filter controls and Aux surface.

The exact case uses Triode, Amount 1.50 and Mix 100% on all four current
Stereo/Main bands. The restrained natural case uses Triode, Amount 0.75 and
Mix 100%. Applying equal low amounts across the current bands avoids inventing
unavailable crossover positions.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. Use normalized
Amount `0.10` for an explicit 1.50 request and `0.05` for the natural 0.75
recipe. Exact user values override the natural recipe. Preserve every Mix at
100% and each Mode at Triode.

The mapped-write guard must see each literal `mapped[N]` index at its setter
call. Use the 14 explicit setter calls exactly as shown. Do not replace them
with a loop, target table, wrapper or helper.

Changing a band Mode can reset that band's Amount. Write all four Mode
controls first, then write the four Amount controls, then the four Mix
controls. Preserve this ordering.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "EXC: Bypass" },
    { index = 8, name = "EXC: Stereo/Main Band 1 Amount" },
    { index = 9, name = "EXC: Stereo/Main Band 1 Mix" },
    { index = 10, name = "EXC: Stereo/Main Band 1 Mode" },
    { index = 11, name = "EXC: Stereo/Main Band 2 Amount" },
    { index = 12, name = "EXC: Stereo/Main Band 2 Mix" },
    { index = 13, name = "EXC: Stereo/Main Band 2 Mode" },
    { index = 14, name = "EXC: Stereo/Main Band 3 Amount" },
    { index = 15, name = "EXC: Stereo/Main Band 3 Mix" },
    { index = 16, name = "EXC: Stereo/Main Band 3 Mode" },
    { index = 17, name = "EXC: Stereo/Main Band 4 Amount" },
    { index = 18, name = "EXC: Stereo/Main Band 4 Mix" },
    { index = 19, name = "EXC: Stereo/Main Band 4 Mode" },
    { index = 22, name = "EXC: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[4], 0.8333333134651184)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[7], 0.8333333134651184)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[10], 0.8333333134651184)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[13], 0.8333333134651184)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[14], 0.0)
  reaper.Undo_EndBlock("ReaAssist: set subtle Ozone 12 Exciter", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Keep Amount low on unheard material and compare at matched loudness. Use more
color only when the user explicitly asks for obvious saturation. Preserve the
existing crossover structure.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Exciter -->

<!-- PLUGIN:Ozone 12 Imager -->
<!-- SECTION-REVISION:5afe80afe3a3cae8988d551cfafde408fae9c77227ffcc997ab156fd711bdc24 -->
## Ozone 12 Imager

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-imager","display_name":"Ozone 12 Imager","vendor":"iZotope","product_class":"dynamic","preference_type":"mastering","identifiers":{"add_by_name":["VST3: Ozone 12 Imager","VST3: Ozone 12 Imager (iZotope)"],"aliases":["VST3: Ozone 12 Imager (iZotope)"],"curated":["Ozone 12 Imager"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-imager","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Imager","loaded_name":"VST3: Ozone 12 Imager (iZotope)","parameter_count":{"mode":"exact","value":28},"required_parameters":[{"index":7,"name":"IMG: Bypass","section":"","section_required":false},{"index":8,"name":"IMG: Global Amount","section":"","section_required":false},{"index":9,"name":"IMG: Stereo/Main Enable Stereoizer","section":"","section_required":false},{"index":11,"name":"IMG: Stereo/Main Band 1 Width Percent","section":"","section_required":false},{"index":24,"name":"IMG: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"e5dd5a14c9f0c8880f7a7f923302e3291a02fd239a7340d8997ada55f4dc8e00"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/imager.html","migrated_at":"2026-07-30","body_sha256":"0e43d6356b8a86ade022f50deb6f08a35606521be2b8ea927c10086fa73a1cbb","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"e5dd5a14c9f0c8880f7a7f923302e3291a02fd239a7340d8997ada55f4dc8e00"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Imager VST3 component. The
installed host surface exposes Global Amount, Stereoizer, four widths and
Recover Sides for Stereo/Main and Aux. The crossover points shown in the
plug-in window are not host-exposed. Preserve the current crossover structure
and Aux controls.

The certified exact and natural cases use Global Amount 100%, Stereoizer Off,
Band 1 Width -20, Band 2 Width 0, Bands 3 and 4 Width +20, Recover Sides Gain
0 dB and both module bypasses Off. This is a restrained mastering-width start.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. Use the same
certified recipe for the exact and restrained natural cases.

Before the deferred callback, resolve `tr` as the existing track's MediaTrack
object and `fx` as that track's existing integer FX index. Pass them to
`reaassist_resolve_profile_params` in exactly that order: `tr, fx`.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "IMG: Bypass" },
    { index = 8, name = "IMG: Global Amount" },
    { index = 9, name = "IMG: Stereo/Main Enable Stereoizer" },
    { index = 11, name = "IMG: Stereo/Main Band 1 Width Percent" },
    { index = 12, name = "IMG: Stereo/Main Band 2 Width Percent" },
    { index = 13, name = "IMG: Stereo/Main Band 3 Width Percent" },
    { index = 14, name = "IMG: Stereo/Main Band 4 Width Percent" },
    { index = 15, name = "IMG: Stereo/Main Recover Sides Gain" },
    { index = 16, name = "IMG: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.40)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.60)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.60)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[8], 0.9581429958343506)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0)
  reaper.Undo_EndBlock("ReaAssist: set Ozone 12 Imager widths", -1)
  reaper.UpdateArrange()
end)
```

For a restrained mastering-width request, return the executable Lua above.
Never respond with only a description of the width settings.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Keep the lowest current band narrower than the upper bands. Avoid Stereoizer
on unheard material. Ask the user to check mono compatibility and reduce
upper-band width if the center image weakens.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Imager -->

<!-- PLUGIN:Ozone 12 Maximizer -->
<!-- SECTION-REVISION:2f81e75cc48a13169d1cc538645a80cb704bc592419d82295995de864039b7e0 -->
## Ozone 12 Maximizer

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-maximizer","display_name":"Ozone 12 Maximizer","vendor":"iZotope","product_class":"container","preference_type":"mastering","identifiers":{"add_by_name":["VST3: Ozone 12 Maximizer","VST3: Ozone 12 Maximizer (iZotope)"],"aliases":["ozone 12 maximizer","ozone maximizer","izotope ozone 12 maximizer","VST3: Ozone 12 Maximizer","VST3: Ozone 12 Maximizer (iZotope)"],"curated":["Ozone 12 Maximizer"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-maximizer","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Maximizer","loaded_name":"VST3: Ozone 12 Maximizer (iZotope)","parameter_count":{"mode":"exact","value":23},"required_parameters":[{"index":7,"name":"MAX: Bypass","section":"","section_required":false},{"index":8,"name":"MAX: Input Gain","section":"","section_required":false},{"index":9,"name":"MAX: Output Level","section":"","section_required":false},{"index":11,"name":"MAX: Character","section":"","section_required":false},{"index":19,"name":"MAX: Link Stereo Amounts","section":"","section_required":false}],"observed_fingerprint_sha256":"92fc3da273469f5b48834e7660b13a56ba5af7b35a841c4aa94856d4551963b3"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/maximizer.html","migrated_at":"2026-07-30","body_sha256":"c5fce70f5de672aeea4960abf2b544b44fe9461c208568c7f8d4964570cca798","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"92fc3da273469f5b48834e7660b13a56ba5af7b35a841c4aa94856d4551963b3"}}
```

<!-- CHUNK:control -->
This profile covers the installed Ozone 12 Maximizer VST3 component from Ozone
12 Advanced 12.0.2.1331. It does not claim automatic control of the 876-
parameter Ozone 12 mothership. The mothership has a customizable signal chain,
and REAPER does not expose a dependable host parameter that proves Maximizer
is present in that chain. For a new scripted mastering-limiter action, use the
fixed Maximizer component. If the user targets an existing mothership
instance, do not use this component mapping. Explain the boundary and offer to
add the component instead.

The current first-party reference is the `Ozone 12 user guide`, Maximizer
chapter, accessed 2026-07-30 at
`https://docs.izotope.com/ozone12/en/maximizer.html`. It confirms that Input
Gain drives the signal into limiting, Output Level sets the maximum output,
Character controls response time, Upward Compress and Soft Clip occur before
the IRC limiter, and Stereo Independence changes how transient and sustained
material are linked across channels.

The installed component exposes 23 host parameters. Only indices 7 through 19
are the Maximizer module surface. Indices 0 through 6 are component I/O and
global bypass controls. Indices 20 through 22 are host Bypass, Wet and Delta.
Preserve both groups unless the user explicitly asks for a host-level change.

The Maximizer algorithm Mode and True Peak controls appear in the product
interface and manual, but they are absent from this installed VST3 host
surface. Never claim to read or set them through REAPER parameters. Preserve
their current state and tell the user to verify them in the plug-in window when
they matter.

### SAFE MAXIMIZER SURFACE

```
7  MAX: Bypass
8  MAX: Input Gain
9  MAX: Output Level
10 MAX: Link Input Gain and Output Level
11 MAX: Character
12 MAX: Upward Compression Amt
13 MAX: Soft Clip On/Off
14 MAX: Soft Clip Mix
15 MAX: Soft Clip Mode
16 MAX: Transient Shaping Amt
17 MAX: Stereo Ind. Sustain Amt
18 MAX: Stereo Ind. Transient Amt
19 MAX: Link Stereo Amounts
```

Ozone does not settle reliably during same-frame formatted-display searches.
Resolve every requested index and exact name before the first write. Use one
`reaper.defer` callback and explicit guarded normalized writes. Do not use
`set_param_display` or `set_param_enum` for this profile. ReaAssist stages the
FX change and verifies delayed live readback before it commits the edit.

For the certified exact recipe, use Input Gain +2.00 dB, Output Level -1.00 dB,
Character 3.00, Upward Compression 1.00 dB, Soft Clip On at 10.00 in Light
mode, Transient Shaping 10.00, both Stereo Independence amounts at 0.00 and
their link On. Turn the Input Gain and Output Level link Off before setting
those two controls independently.

For a conservative unheard-audio starting point, use Input Gain +1.00 dB,
Output Level -1.00 dB and Character 3.00. Keep Upward Compression, Soft Clip
and Transient Shaping at zero or Off. Keep both Stereo Independence amounts at
0.00 and linked. Use normalized values `0.05`, `0.95`, `0.30`, `0.00`, `0.00`,
`0.00`, `0.00`, `0.00`, `0.00` and `1.00` for indices 8, 9, 11, 12, 13,
14, 16, 17, 18 and 19 respectively. Keep index 7 Off and index 10 Off.
Preserve index 15 because Soft Clip is Off. Call this a starting point. The
user must listen and adjust Input Gain for the source.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "MAX: Bypass" },
    { index = 8, name = "MAX: Input Gain" },
    { index = 9, name = "MAX: Output Level" },
    { index = 10, name = "MAX: Link Input Gain and Output Level" },
    { index = 11, name = "MAX: Character" },
    { index = 12, name = "MAX: Upward Compression Amt" },
    { index = 13, name = "MAX: Soft Clip On/Off" },
    { index = 14, name = "MAX: Soft Clip Mix" },
    { index = 15, name = "MAX: Soft Clip Mode" },
    { index = 16, name = "MAX: Transient Shaping Amt" },
    { index = 17, name = "MAX: Stereo Ind. Sustain Amt" },
    { index = 18, name = "MAX: Stereo Ind. Transient Amt" },
    { index = 19, name = "MAX: Link Stereo Amounts" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0) -- MAX active
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0) -- Gain link Off
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.1) -- Input +2.00 dB
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.95) -- Output -1.00 dB
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.3) -- Character 3.00
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.1) -- Upward 1.00 dB
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0) -- Soft Clip Light
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.1) -- Soft Clip 10.00
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 1.0) -- Soft Clip On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.05) -- Transient 10.00
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 1.0) -- Stereo link On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0) -- Sustain 0.00
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.0) -- Transient 0.00
  reaper.Undo_EndBlock("ReaAssist: set Ozone 12 Maximizer controls", -1)
  reaper.UpdateArrange()
end)
```

For a conservative natural-intent request, generate executable Lua from this
recipe. Do not return only a description.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "MAX: Bypass" },
    { index = 8, name = "MAX: Input Gain" },
    { index = 9, name = "MAX: Output Level" },
    { index = 10, name = "MAX: Link Input Gain and Output Level" },
    { index = 11, name = "MAX: Character" },
    { index = 12, name = "MAX: Upward Compression Amt" },
    { index = 13, name = "MAX: Soft Clip On/Off" },
    { index = 14, name = "MAX: Soft Clip Mix" },
    { index = 16, name = "MAX: Transient Shaping Amt" },
    { index = 17, name = "MAX: Stereo Ind. Sustain Amt" },
    { index = 18, name = "MAX: Stereo Ind. Transient Amt" },
    { index = 19, name = "MAX: Link Stereo Amounts" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.95)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.30)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 1.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set transparent Ozone 12 Maximizer start", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use restrained gain for transparent peak control on unheard material. Increase
Input Gain only when the user asks for more loudness or control, and describe
it as a starting value because the actual gain reduction depends on the audio.
Leave Soft Clip and Upward Compression off for a transparent default. Use them
only when the user explicitly asks for more density, loudness or clipping
character. Preserve algorithm Mode and True Peak because this host surface
cannot control them.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Maximizer -->

<!-- PLUGIN:Ozone 12 Spectral Shaper -->
<!-- SECTION-REVISION:86c3d5af496121d7cc03a0a1ac7a8779abfeaa463c9df92eb6f211ada54f703e -->
## Ozone 12 Spectral Shaper

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-spectral-shaper","display_name":"Ozone 12 Spectral Shaper","vendor":"iZotope","product_class":"ordinary","preference_type":"mastering","identifiers":{"add_by_name":["VST3: Ozone 12 Spectral Shaper","VST3: Ozone 12 Spectral Shaper (iZotope)"],"aliases":["VST3: Ozone 12 Spectral Shaper (iZotope)"],"curated":["Ozone 12 Spectral Shaper"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-spectral-shaper","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Spectral Shaper","loaded_name":"VST3: Ozone 12 Spectral Shaper (iZotope)","parameter_count":{"mode":"exact","value":23},"required_parameters":[{"index":7,"name":"SPSHPR: Bypass","section":"","section_required":false},{"index":8,"name":"SPSHPR: Stereo/Main Amount","section":"","section_required":false},{"index":9,"name":"SPSHPR: Stereo/Main Compression Mode","section":"","section_required":false},{"index":13,"name":"SPSHPR: Stereo/Main Bypass","section":"","section_required":false},{"index":19,"name":"SPSHPR: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"a8e7b8f90098dadb22834521741ca08d7a4f0e38e1a8c2c70bbe4cf8e966b8fa"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/spectral-shaper.html","migrated_at":"2026-07-30","body_sha256":"a8380cd66179573547851e02effb20edcb0b176e2dc4d912fb6cbe5a888cd19d","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"a8e7b8f90098dadb22834521741ca08d7a4f0e38e1a8c2c70bbe4cf8e966b8fa"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Spectral Shaper VST3 component.
The installed host surface exposes Amount, Light/Medium/Heavy mode, Attack,
Release, Tone and bypass for Stereo/Main and Aux. The action region and Learn
controls shown in the plug-in window are absent from the host surface.
Preserve the current action region, Learn state and every Aux control.

The exact case uses Amount 20, Medium, Attack 1.00, Release 30.00 and neutral
Tone. The restrained natural case uses Amount 10 and Light with the same timing
and Tone. Both are starting points on unheard material.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. For an explicit
Amount 20 Medium request, use normalized Amount `0.20` and Mode `0.50`.
For the natural recipe, use Amount `0.10` and Light Mode `0.0`. Exact user
values override the natural recipe.

Write Compression Mode before Amount and timing so a mode change cannot reset
the requested result.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "SPSHPR: Bypass" },
    { index = 8, name = "SPSHPR: Stereo/Main Amount" },
    { index = 9, name = "SPSHPR: Stereo/Main Compression Mode" },
    { index = 10, name = "SPSHPR: Stereo/Main Attack" },
    { index = 11, name = "SPSHPR: Stereo/Main Release" },
    { index = 12, name = "SPSHPR: Stereo/Main Tone" },
    { index = 13, name = "SPSHPR: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.10)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[4], 0.009009008295834064)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[5], 0.29929929971694946)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set gentle Ozone 12 Spectral Shaper", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use low Amount and Light mode for a first pass. Keep Tone neutral unless the
user names a bright or dark problem. Ask the user to set or confirm the action
region in the plug-in window when frequency targeting matters.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Spectral Shaper -->

<!-- PLUGIN:Ozone 12 Vintage Compressor -->
<!-- SECTION-REVISION:5c0a241655c3834ba6615c0a55d312911b87023c58eb0cf55f4b921208989560 -->
## Ozone 12 Vintage Compressor

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-vintage-compressor","display_name":"Ozone 12 Vintage Compressor","vendor":"iZotope","product_class":"ordinary","preference_type":"compressor","identifiers":{"add_by_name":["VST3: Ozone 12 Vintage Compressor","VST3: Ozone 12 Vintage Compressor (iZotope)"],"aliases":["VST3: Ozone 12 Vintage Compressor (iZotope)"],"curated":["Ozone 12 Vintage Compressor"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-vintage-compressor","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Vintage Compressor","loaded_name":"VST3: Ozone 12 Vintage Compressor (iZotope)","parameter_count":{"mode":"exact","value":37},"required_parameters":[{"index":7,"name":"VCOMP: Bypass","section":"","section_required":false},{"index":8,"name":"VCOMP: Stereo/Main Threshold","section":"","section_required":false},{"index":12,"name":"VCOMP: Stereo/Main Mode","section":"","section_required":false},{"index":20,"name":"VCOMP: Stereo/Main Bypass","section":"","section_required":false},{"index":33,"name":"VCOMP: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"2827db4662688d21cebf2e2db6c507d9175a4876ad9f7f478e9018190e54fbe5"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/vintage-compressor.html","migrated_at":"2026-07-30","body_sha256":"fa8839d53dc37e15498cd0210e255dba8c8ee2c0a7c38ff2b409c0d606a746f8","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"2827db4662688d21cebf2e2db6c507d9175a4876ad9f7f478e9018190e54fbe5"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Vintage Compressor VST3
component. The installed surface provides threshold, ratio, timing, mode,
output gain, auto gain and detector filters for Stereo/Main and Aux. Preserve
the Aux surface and detector filters unless the user names them.

The certified exact and natural cases use Stereo/Main Threshold -18 dB, Ratio
1.50, Attack 20 ms, Release 120 ms, Balanced mode, Output Gain 0 dB and Auto
Gain Off. Threshold and actual gain reduction depend on the signal. Never
claim a measured amount of compression when no audio analysis was performed.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. Use the same
certified recipe for the exact and restrained natural cases.

Write Mode and Auto Gain before Threshold, Ratio, timing and Output Gain so
selector changes cannot reset the requested result.

The mapped-write guard must see each literal `mapped[N]` index at its setter
call. Keep the resolver entries and nine explicit setter calls in the exact
order shown. Do not reorder the resolver list or use a loop, table or helper.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "VCOMP: Bypass" },
    { index = 12, name = "VCOMP: Stereo/Main Mode" },
    { index = 14, name = "VCOMP: Stereo/Main Auto Gain" },
    { index = 8, name = "VCOMP: Stereo/Main Threshold" },
    { index = 9, name = "VCOMP: Stereo/Main Ratio" },
    { index = 10, name = "VCOMP: Stereo/Main Attack" },
    { index = 11, name = "VCOMP: Stereo/Main Release" },
    { index = 13, name = "VCOMP: Stereo/Main Output Gain" },
    { index = 20, name = "VCOMP: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.70)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[5], 0.02631578966975212)
  reaper.TrackFX_SetParamNormalized(
    tr, fx, mapped[6], 0.19919919967651367)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.75)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0)
  reaper.Undo_EndBlock(
    "ReaAssist: set Ozone 12 Vintage Compressor", -1)
  reaper.UpdateArrange()
end)
```

For a restrained mastering-glue request, return the executable Lua above.
Never respond with only a description of the compressor settings.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use Balanced mode, a low ratio and Auto Gain Off for an honest starting point.
Ask the user to adjust Threshold while listening for movement and level
change. Preserve detector filtering unless the source problem is known.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Vintage Compressor -->

<!-- PLUGIN:Ozone 12 Vintage EQ -->
<!-- SECTION-REVISION:47e430c1da878eaeec70a943d937b8142f796a56f86de2aca94d9663a2721206 -->
## Ozone 12 Vintage EQ

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-vintage-eq","display_name":"Ozone 12 Vintage EQ","vendor":"iZotope","product_class":"ordinary","preference_type":"eq","identifiers":{"add_by_name":["VST3: Ozone 12 Vintage EQ","VST3: Ozone 12 Vintage EQ (iZotope)"],"aliases":["VST3: Ozone 12 Vintage EQ (iZotope)"],"curated":["Ozone 12 Vintage EQ"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-vintage-eq","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Vintage EQ","loaded_name":"VST3: Ozone 12 Vintage EQ (iZotope)","parameter_count":{"mode":"exact","value":41},"required_parameters":[{"index":7,"name":"VEQ: Bypass","section":"","section_required":false},{"index":8,"name":"VEQ: Stereo/Main Low Frequency","section":"","section_required":false},{"index":11,"name":"VEQ: Stereo/Main High Boost Frequency","section":"","section_required":false},{"index":22,"name":"VEQ: Stereo/Main Bypass","section":"","section_required":false},{"index":37,"name":"VEQ: Aux Bypass","section":"","section_required":false}],"observed_fingerprint_sha256":"f20c367f66cd98fbe58c3a63bf4b46cf740fb5fd9b489b17873ca61cf3d91fdf"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/vintage-eq.html","migrated_at":"2026-07-30","body_sha256":"9617ee0ef477fc4ff0e3c71e9a4a4112d300061c2be63f3a8840332bf603a38d","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"f20c367f66cd98fbe58c3a63bf4b46cf740fb5fd9b489b17873ca61cf3d91fdf"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Vintage EQ VST3 component. The
frequency controls are stepped selectors. Use only the calibrated normalized
anchors. Preserve the Aux surface and every control the request does not name.

The exact case uses 45 Hz Low with Boost 1.00 and Cut 0, 8 kHz High Boost 1.00
with Q 0, 10 kHz High Cut at 0, 500 Hz Low-Mid Boost 0, 1500 Hz Mid Cut 0 and
3 kHz High-Mid Boost 0.50. The natural broad-lift case uses 0.50 at 45 Hz and
8 kHz, with every cut and mid amount at zero.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. For the certified
exact request, use normalized Low and High Boost `0.10` and High-Mid Boost
`0.05`. For the natural recipe, use Low and High Boost `0.05` and High-Mid
Boost `0.0`. Exact user values override the natural recipe.

`tr` must be the existing REAPER `MediaTrack` and `fx` must be its integer FX
index. Pass `tr, fx` in that order to the resolver and every TrackFX call.
Never swap the track and FX arguments.

The mapped-write guard must see each literal `mapped[N]` index at its setter
call. Use the 16 explicit setter calls exactly as shown. Do not replace them
with a loop, target table, wrapper or helper. Never use `find_param`,
`set_param_display` or any formatted-value search. This stepped host surface
is not numerically monotonic. Copy the guarded normalized block and change
only the three documented boost literals between exact and natural cases.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "VEQ: Bypass" },
    { index = 8, name = "VEQ: Stereo/Main Low Frequency" },
    { index = 9, name = "VEQ: Stereo/Main Low Boost Amount" },
    { index = 10, name = "VEQ: Stereo/Main Low Cut Amount" },
    { index = 11, name = "VEQ: Stereo/Main High Boost Frequency" },
    { index = 12, name = "VEQ: Stereo/Main High Boost Amount" },
    { index = 13, name = "VEQ: Stereo/Main High Q" },
    { index = 14, name = "VEQ: Stereo/Main High Cut Frequency" },
    { index = 15, name = "VEQ: Stereo/Main High Cut Amount" },
    { index = 16, name = "VEQ: Stereo/Main Low-Mid Frequency" },
    { index = 17, name = "VEQ: Stereo/Main Low-Mid Boost Amount" },
    { index = 18, name = "VEQ: Stereo/Main Mid Frequency" },
    { index = 19, name = "VEQ: Stereo/Main Mid Cut Amount" },
    { index = 20, name = "VEQ: Stereo/Main High-Mid Frequency" },
    { index = 21, name = "VEQ: Stereo/Main High-Mid Boost Amount" },
    { index = 22, name = "VEQ: Stereo/Main Bypass" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.05)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[14], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[15], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[16], 0.0)
  reaper.Undo_EndBlock("ReaAssist: set gentle Ozone 12 Vintage EQ", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Keep broad boosts below 1.00 on unheard material. Avoid combined boost and cut
recipes unless the user asks for that vintage curve. Check level and tonal
balance after each move.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Vintage EQ -->

<!-- PLUGIN:Ozone 12 Vintage Limiter -->
<!-- SECTION-REVISION:ec375ec8affaa3fa185eaeee52ae81cfbc1d99f30bf6d126c2e9dbefbf759b1d -->
## Ozone 12 Vintage Limiter

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-vintage-limiter","display_name":"Ozone 12 Vintage Limiter","vendor":"iZotope","product_class":"ordinary","preference_type":"limiter","identifiers":{"add_by_name":["VST3: Ozone 12 Vintage Limiter","VST3: Ozone 12 Vintage Limiter (iZotope)"],"aliases":["VST3: Ozone 12 Vintage Limiter (iZotope)"],"curated":["Ozone 12 Vintage Limiter"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-vintage-limiter","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Vintage Limiter","loaded_name":"VST3: Ozone 12 Vintage Limiter (iZotope)","parameter_count":{"mode":"exact","value":16},"required_parameters":[{"index":7,"name":"VLIM: Bypass","section":"","section_required":false},{"index":8,"name":"VLIM: Tube Type","section":"","section_required":false},{"index":9,"name":"VLIM: Threshold","section":"","section_required":false},{"index":10,"name":"VLIM: Ceiling","section":"","section_required":false},{"index":12,"name":"VLIM: Character","section":"","section_required":false}],"observed_fingerprint_sha256":"7fe250fc65b7793be856901787b88926b1c7b16efbd45c6fbad097748a8c3db9"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/vintage-limiter.html","migrated_at":"2026-07-30","body_sha256":"f00222ca476b79de4a2365842f72fea796461f8080479513185c2a716e8b6464","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"7fe250fc65b7793be856901787b88926b1c7b16efbd45c6fbad097748a8c3db9"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Vintage Limiter VST3 component.
Its safe product surface is indices 7 through 12. Indices 0 through 6 are
component I/O and global bypass. Indices 13 through 15 are host controls.

True Peak appears in the plug-in window and guide but is not present on this
installed host surface. Preserve it and tell the user to verify it manually
when delivery specifications require true-peak limiting.

The exact case uses Tube, Threshold -4.00, Ceiling -1.00, Character 3.00 and
Threshold/Ceiling Link Off. The restrained natural case uses Tube, Threshold
-2.00, Ceiling -1.00, Character 2.00 and Link Off.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. For the certified
exact request, use normalized Threshold `0.80` and Character `0.30`. For the
natural recipe, use Threshold `0.90` and Character `0.20`. Exact user values
override the natural recipe.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "VLIM: Bypass" },
    { index = 8, name = "VLIM: Tube Type" },
    { index = 9, name = "VLIM: Threshold" },
    { index = 10, name = "VLIM: Ceiling" },
    { index = 11, name = "VLIM: Link Threshold and Ceiling" },
    { index = 12, name = "VLIM: Character" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.90)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.95)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.20)
  reaper.Undo_EndBlock(
    "ReaAssist: set restrained Ozone 12 Vintage Limiter", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use a conservative threshold and safe ceiling on unheard material. State that
actual limiting depends on the input level. Keep True Peak unchanged and
disclose its manual verification boundary.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Vintage Limiter -->

<!-- PLUGIN:Ozone 12 Vintage Tape -->
<!-- SECTION-REVISION:35756455bb91d81137ffb7e081cb73b8c708f29b4b0cd3c76e0c7cda17713c64 -->
## Ozone 12 Vintage Tape

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"izotope-ozone-12-vintage-tape","display_name":"Ozone 12 Vintage Tape","vendor":"iZotope","product_class":"ordinary","preference_type":"saturation","identifiers":{"add_by_name":["VST3: Ozone 12 Vintage Tape","VST3: Ozone 12 Vintage Tape (iZotope)"],"aliases":["VST3: Ozone 12 Vintage Tape (iZotope)"],"curated":["Ozone 12 Vintage Tape"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"izotope-ozone-12-vintage-tape","safety":{"settle_ms":250,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Ozone 12 Vintage Tape","loaded_name":"VST3: Ozone 12 Vintage Tape (iZotope)","parameter_count":{"mode":"exact","value":17},"required_parameters":[{"index":7,"name":"VTAPE: Bypass","section":"","section_required":false},{"index":8,"name":"VTAPE: Input Drive","section":"","section_required":false},{"index":10,"name":"VTAPE: Speed","section":"","section_required":false},{"index":11,"name":"VTAPE: Harmonics","section":"","section_required":false},{"index":13,"name":"VTAPE: High Emphasis","section":"","section_required":false}],"observed_fingerprint_sha256":"20798073075c8ea7bef326114521aa6ecbc080b56f0a0b3f07ba978cc52e5b68"}],"status":"pilot","provenance":{"source":"https://docs.izotope.com/ozone12/en/vintage-tape.html","migrated_at":"2026-07-30","body_sha256":"07d197c3c79d1f478c19eeab7c7ee06c6660b71b451d29d19c7d89efee0e1e40","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"20798073075c8ea7bef326114521aa6ecbc080b56f0a0b3f07ba978cc52e5b68"}}
```

<!-- CHUNK:control -->
This profile covers only the fixed Ozone 12 Vintage Tape VST3 component. Its
safe product surface is Bypass, Input Drive, Bias, Speed, Harmonics, Low
Emphasis and High Emphasis at indices 7 through 13. Preserve component I/O,
global bypass and host controls.

The exact case uses Input Drive +6.00, Bias 0, Speed 30 ips, Harmonics 1.00,
Low Emphasis 2.00 and High Emphasis 4.00. The restrained natural case uses
Input Drive +3.00 with the same neutral Bias, 30 ips, Harmonics and emphasis
values.

Every request to set, use, apply or refine this existing component is an
executable action. Return exactly one complete Lua block. For the certified
exact request, use normalized Input Drive `0.60`. For the natural recipe, use
Input Drive `0.55`. Exact user values override the natural recipe.

Before the guarded block, resolve the user-target track into `tr` as a REAPER
`MediaTrack`, then resolve its existing
`VST3: Ozone 12 Vintage Tape (iZotope)` instance into `fx` as an integer.
Use that exact identifier with instantiate set to false. Never use a short
plug-in name or add another instance. Pass `tr, fx` in that order everywhere.

Write Speed before Input Drive, Bias, Harmonics and emphasis so a speed change
cannot reset the requested result. The calibrated 30 ips value is literal
normalized `0.0` at `mapped[4]`, never `0.1`. Do not infer it from a selector
position. Keep all seven explicit setters in the order shown, with no loop,
target table or helper. The immutable normalized tail is `mapped[3]=0.50`,
`mapped[4]=0.0`, `mapped[5]=0.10`, `mapped[6]=0.20` and `mapped[7]=0.40`.
Never copy High Emphasis into Low Emphasis. Only `mapped[2]` changes between
the exact `0.60` and natural `0.55` cases.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 7, name = "VTAPE: Bypass" },
    { index = 8, name = "VTAPE: Input Drive" },
    { index = 9, name = "VTAPE: Bias" },
    { index = 10, name = "VTAPE: Speed" },
    { index = 11, name = "VTAPE: Harmonics" },
    { index = 12, name = "VTAPE: Low Emphasis" },
    { index = 13, name = "VTAPE: High Emphasis" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.55)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.50)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.10)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.20)
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.40)
  reaper.Undo_EndBlock(
    "ReaAssist: set subtle Ozone 12 Vintage Tape", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use 30 ips and modest drive for cleaner tape color. Raise Harmonics or Bias
only when the user asks for a stronger effect. Compare level after processing
and avoid claiming saturation intensity without listening.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Ozone 12 Vintage Tape -->

<!-- PLUGIN:soothe2 -->
<!-- SECTION-REVISION:0b1a434feaf3e534905468e8142a98b658ec8f20fcd561badf50a1461bbe81b7 -->
## soothe2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"oeksound-soothe2","display_name":"soothe2","vendor":"oeksound","product_class":"dynamic","preference_type":"deesser","identifiers":{"add_by_name":["VST3: soothe2","VST3: soothe2 (oeksound)"],"aliases":["soothe2","soothe 2","oeksound soothe2","VST3: soothe2","VST3: soothe2 (oeksound)"],"curated":["soothe2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["soothe2"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"oeksound-soothe2","safety":{"settle_ms":150,"heavy_selectors":[46,47,48,49],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: soothe2","loaded_name":"VST3: soothe2 (oeksound)","parameter_count":{"mode":"exact","value":60},"required_parameters":[{"index":3,"name":"mode","section":"","section_required":false},{"index":20,"name":"band2 on","section":"eq band2 ","section_required":true},{"index":50,"name":"mix","section":"output","section_required":true},{"index":51,"name":"trim","section":"output","section_required":true}],"observed_fingerprint_sha256":"a223a442882e85a1fc9ef99c8dcc48dbf08a8310d2a886020c7c1db008128e89"}],"status":"pilot","provenance":{"source":"https://oeksound.com/manuals/soothe2/","migrated_at":"2026-07-30","body_sha256":"5523a603306503b06e21a74c3f8f9a07cdc1971ba07cdd3eb150d8eb1bc10643","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"a223a442882e85a1fc9ef99c8dcc48dbf08a8310d2a886020c7c1db008128e89"}}
```

<!-- CHUNK:control -->
soothe2 is a dynamic resonance suppressor. Its installed VST3 exposes 60
parameters. Parameter names and sections are lower-case and section whitespace
is significant. Use the exact names and sections below in resolver guards.

### PRIMARY CONTROLS

```
3 mode          4 depth          5 sharpness      6 selectivity
7 attack        8 release       26 band3 on      27 band3 freq
28 band3 sens  29 band3 q       31 band3 mode    43 stereo mode
44 stereo link 48 oversample    49 resolution    50 mix
51 trim        52 delta         53 bypass
```

Oversample and resolution are heavy selectors. Preserve them unless the user
asks for a quality change. Keep delta and bypass off for normal processing.
Soft mode is the transparent starting mode. Hard mode can be easier to overuse
and should require an explicit request for stronger resonance control.

For a gentle unheard vocal start, use soft mode, depth 3.0, sharpness 4.0,
selectivity 3.0, attack 2.0, release 4.0, Band 3 on at 5k with sensitivity 4.0
and q 1.0, mix 100.0 and trim 0.0. Describe it as a starting point.

Resolve the full target table before the first write. Use the reviewed
normalized anchors below for this certified recipe. The provenance validator
must see every literal `mapped[N]` index at its setter call, so do not place
mapped indices in a target table, loop or wrapper. Use exactly one
`reaper.defer` callback and do not add a follow-up verification callback.
Generated code for this recipe must use the exact normalized setter structure
below. Do not define or call `set_param_display` or `set_param_enum`, and do not
show an error dialog. Let a resolver or runtime error stop the action safely.
When the request says the selected track already has soothe2, reuse that exact
instance and do not call `TrackFX_AddByName`.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 3, name = "mode" }, { index = 4, name = "depth" },
    { index = 5, name = "sharpness" }, { index = 6, name = "selectivity" },
    { index = 7, name = "attack", section = "speed", section_required = true },
    { index = 8, name = "release", section = "speed", section_required = true },
    { index = 26, name = "band3 on", section = "eq band3 ", section_required = true },
    { index = 27, name = "band3 freq", section = "eq band3 ", section_required = true },
    { index = 28, name = "band3 sens", section = "eq band3 ", section_required = true },
    { index = 29, name = "band3 q", section = "eq band3 ", section_required = true },
    { index = 50, name = "mix", section = "output", section_required = true },
    { index = 51, name = "trim", section = "output", section_required = true },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0) -- soft
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2],
    0.5833333134651184) -- depth 3.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.4) -- sharpness 4.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.3) -- selectivity 3.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.2) -- attack 2.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6],
    0.39583334326744) -- release 4.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 1.0) -- Band 3 on
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8],
    0.7993133664131165) -- 5k
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9],
    0.6666666865348816) -- sensitivity 4.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10],
    0.4999999701976776) -- q 1.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 1.0) -- mix 100.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.0) -- trim 0.0
  reaper.Undo_EndBlock("ReaAssist: set soothe2 controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Adjust depth against the source and use the graph bands to focus processing.
Preserve bands that the user did not mention. Avoid strong sharpness and hard
mode as unattended defaults.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:soothe2 -->

<!-- PLUGIN:soothe3 -->
<!-- SECTION-REVISION:8b00be5203851ea8db544b43e5f5c3fe2125933af15b5ce23f72a9ea638bc13b -->
## soothe3

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"oeksound-soothe3","display_name":"soothe3","vendor":"oeksound","product_class":"dynamic","preference_type":"deesser","identifiers":{"add_by_name":["VST3: soothe3","VST3: soothe3 (oeksound)"],"aliases":["soothe3","soothe 3","oeksound soothe3","VST3: soothe3","VST3: soothe3 (oeksound)"],"curated":["soothe3"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["soothe3"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"oeksound-soothe3","safety":{"settle_ms":150,"heavy_selectors":[3,4],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: soothe3","loaded_name":"VST3: soothe3 (oeksound)","parameter_count":{"mode":"exact","value":147},"required_parameters":[{"index":0,"name":"Depth","section":"","section_required":false},{"index":19,"name":"Band 1 used","section":"","section_required":false},{"index":94,"name":"Mix","section":"","section_required":false},{"index":95,"name":"Out trim","section":"","section_required":false}],"observed_fingerprint_sha256":"97536abef94d25698771fa32411af55866e1c80d00a1e68f5a30a181e76e7988"}],"status":"pilot","provenance":{"source":"https://oeksound.com/manuals/soothe3/","migrated_at":"2026-07-30","body_sha256":"fd37d366e604b84d9bb0443c911048c5f45424a17e2f5e88e74e914ff2208ce7","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"97536abef94d25698771fa32411af55866e1c80d00a1e68f5a30a181e76e7988"}}
```

<!-- CHUNK:control -->
soothe3 is a dynamic resonance suppressor. The installed VST3 exposes 147
parameters. Use a compact musical surface and preserve multichannel rows 98
through 142. Keep Delta and Bypass off unless the user explicitly requests
monitoring or bypass.

### PRIMARY CONTROLS

```
0 Depth        1 Low latency   2 Mode          3 Quality
4 Linear phase 5 Detail        6 Attack        7 Release
16 Stereo mode 17 Stereo link 18 Stereo focus 28 Band 2 used
29 Band 2 enabled 30 Band 2 frequency 31 Band 2 depth 32 Band 2 q
36 Band 2 shape 92 Max cut    94 Mix          95 Out trim
```

Quality and Linear phase are heavy selectors. Preserve them unless the user
asks for a quality or latency change. Low latency should also remain unchanged
unless requested. For ordinary tracking or mixing setup, use the current
quality state.

Soft mode is the conservative default. For an unheard vocal harshness request,
start with Depth 3.0, Detail 4.0, Attack 5.0, Release 4.0, Band 2 at 4.0 kHz
with 2.5 depth and Bell shape, Mix 100 % and Out trim 0.0 dB. These are safe
starting settings. Do not claim that harshness was removed without listening
or reduction evidence.

Resolve exact names and indices before writing. Use the reviewed normalized
anchors below for this certified recipe. The provenance validator must see
every literal `mapped[N]` index at its setter call, so do not place mapped
indices in a target table, loop or wrapper. Use exactly one `reaper.defer`
callback and do not add a follow-up verification callback.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 0, name = "Depth" }, { index = 2, name = "Mode" },
    { index = 5, name = "Detail" }, { index = 6, name = "Attack" },
    { index = 7, name = "Release" }, { index = 28, name = "Band 2 used" },
    { index = 29, name = "Band 2 enabled" },
    { index = 30, name = "Band 2 frequency" },
    { index = 31, name = "Band 2 depth" },
    { index = 36, name = "Band 2 shape" },
    { index = 94, name = "Mix" }, { index = 95, name = "Out trim" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.3) -- Depth 3.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.0) -- soft
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.4) -- Detail 4.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.5) -- Attack 5.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.4) -- Release 4.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0) -- Band used on
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 1.0) -- enabled on
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8],
    0.6691009998321533) -- 4.0 kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.625) -- depth 2.5
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10],
    0.2857142984867096) -- Bell
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 1.0) -- Mix 100 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.5) -- trim 0.0 dB
  reaper.Undo_EndBlock("ReaAssist: set soothe3 controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Increase Depth only after checking the source. Use lower Detail for broad
frequency buildup and higher Detail for narrow resonances. Focus the existing
bands before creating new bands. Preserve all unrelated bands on an existing
instance.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:soothe3 -->

<!-- PLUGIN:Phaser -->
<!-- SECTION-REVISION:a6e7645e2c629de84d1e931e3d60a7922c5808feb3aa2768de97a95732450052 -->
## Phaser

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"phaser","display_name":"Phaser","vendor":"Cockos","product_class":"ordinary","preference_type":"phaser","identifiers":{"add_by_name":["JS: Guitar/phaser"],"aliases":["guitar/phaser","JS: Guitar/phaser"],"curated":[]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["phaser"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"phaser","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"JSFX","identifier":"JS: Guitar/phaser","loaded_name":"JS: 4-Tap Phaser","parameter_count":{"mode":"exact","value":8},"required_parameters":[{"index":0,"name":"Rate (Hz)","section":"","section_required":false},{"index":1,"name":"Range Min (Hz)","section":"","section_required":false},{"index":2,"name":"Range Max (Hz)","section":"","section_required":false},{"index":3,"name":"Feedback (dB)","section":"","section_required":false},{"index":4,"name":"Wet Mix (dB)","section":"","section_required":false}],"observed_fingerprint_sha256":"ab99a69d4c132cc789c13e5489e78b5658362722ce3d164ee77cb1e05816b412"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"777f96f0a4dffbd5359f8cfed18d6af689c8e099cf0a9de7da977d5a2fd787e1","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
Stock JSFX: "4-Tap Phaser" (Guitar/phaser). 4-stage analog-style phaser with
feedback and adjustable sweep range. Bundled with REAPER; available in all
installs.

AddByName string: "JS: Guitar/phaser"  (also accepts "Guitar/phaser")
Total params: 8 (5 sliders + Bypass/Wet/Delta meta)

### PARAM INDEX TABLE (verified from JSFX source)

```
idx  Name             Default   Min    Max     Notes
---  ---------------  --------  -----  ------  ----------------------------
0    Rate (Hz)        0.5       0      10      LFO speed
1    Range Min (Hz)   440       40     20000   Sweep low bound
2    Range Max (Hz)   1600      40     20000   Sweep high bound
3    Feedback (dB)    -3        -120   -1      -120=off; closer to -1 = more resonance
4    Wet Mix (dB)     0         -120   12      Wet level in dB (-120 = fully dry)
5    Bypass           0.0       0.0    1.0     1=bypassed (meta)
6    Wet              1.0       0.0    1.0     Wet level (meta)
7    Delta            0.0       0.0    1.0     Delta monitoring (meta)
```

### VALUE SEMANTICS

Raw values on `TrackFX_SetParam`. Feedback is negative-dB attenuation on the
feedback path (closer to -1 = more resonance). Wet Mix = 0 dB is unity; -120
is fully dry.

### SAFE PARAMETER TARGETING

Resolve every requested control in one literal guard table before the first
write. Use the exact names below and do not replace them with inferred aliases.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Rate (Hz)" },
  { index = 1, name = "Range Min (Hz)" },
  { index = 2, name = "Range Max (Hz)" },
  { index = 3, name = "Feedback (dB)" },
  { index = 4, name = "Wet Mix (dB)" },
})
if not mapped then error(guard_err) end
```

Use `mapped[1]` through `mapped[5]` in that order. These JSFX controls use raw
units, so write them with `TrackFX_SetParam`, never
`TrackFX_SetParamNormalized`. For an exact slow sweep, the verified raw values
are `0.3`, `300`, `2500`, `-6` and `-3`.

For the natural request to give clean guitar a slow, subtle sweep without
overwhelming the dry tone, use that exact slow-sweep recipe. On an existing
instance, change only those five controls. Preserve Bypass, the host Wet and
Delta controls, track routing and every other setting unless the user names it.
Do not add another phaser when the request says to use the existing one.

For a request that adds Phaser and configures it, perform the existence check,
`TrackFX_AddByName`, parameter resolution and every parameter write inside the
same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding the JSFX and end it
only after the last write. One Undo must remove the new Phaser instance and
restore the original FX count.

### COMMON RECIPES

**"Slow sweeping phaser":**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Rate (Hz)" },
  { index = 1, name = "Range Min (Hz)" },
  { index = 2, name = "Range Max (Hz)" },
  { index = 3, name = "Feedback (dB)" },
  { index = 4, name = "Wet Mix (dB)" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 0.3)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 300)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 2500)
reaper.TrackFX_SetParam(tr, fx, mapped[4], -6)
reaper.TrackFX_SetParam(tr, fx, mapped[5], -3)
```

**"Fast resonant phaser":**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Rate (Hz)" },
  { index = 1, name = "Range Min (Hz)" },
  { index = 2, name = "Range Max (Hz)" },
  { index = 3, name = "Feedback (dB)" },
  { index = 4, name = "Wet Mix (dB)" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 3.5)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 500)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 3500)
reaper.TrackFX_SetParam(tr, fx, mapped[4], -3)
reaper.TrackFX_SetParam(tr, fx, mapped[5], 0)
```

---
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Phaser -->

<!-- PLUGIN:ReaComp -->
<!-- SECTION-REVISION:c43143bd45d5b3f1f5dd7a3618bada82c7e45788f5bd064f3cfab9874c0988ee -->
## ReaComp

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reacomp","display_name":"ReaComp","vendor":"Cockos","product_class":"ordinary","preference_type":"compressor","identifiers":{"add_by_name":["ReaComp"],"aliases":["comp","compressor"],"curated":["ReaComp"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reacomp"],"context_required":["comp","compressor"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reacomp","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaComp","loaded_name":"VST: ReaComp (Cockos)","parameter_count":{"mode":"exact","value":24},"required_parameters":[{"index":0,"name":"Threshold","section":"","section_required":false},{"index":4,"name":"Pre-comp","section":"","section_required":false},{"index":9,"name":"AudIn","section":"","section_required":false},{"index":15,"name":"Auto Make Up Gain","section":"","section_required":false},{"index":20,"name":"Metering Index","section":"","section_required":false}],"observed_fingerprint_sha256":"5fc6105e8653fde715d5bbe11ad9b206706f5c89703fd067ea821d19ff4c33b0"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"b5f9bfe646fa6560bb67b74d9059c42e054143b966d2715a0fd24a324bdb8fca","verified_at":"2026-07-25","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaComp"
Total params (default instance): 24 (indices 0-23)

### PARAM INDEX TABLE (verified)

```
idx  Name                          Default val   Min    Max    Notes
---  ----------------------------  -----------   -----  -----  ----------------------------
0    Threshold                     1.0           0.0    2.0    Linear amp (see scale below)
1    Ratio                         0.0303        0.0    1.0    Normalized (see scale below)
2    Attack                        0.006         0.0    1.0    Normalized seconds
3    Release                       0.020         0.0    1.0    Normalized seconds
4    Pre-comp                      0.0           0.0    1.0    Lookahead: 0=off, 1=max
5    resvd                         0.0           0.0    1.0    Reserved -- do not touch
6    Lowpass                       1.0           0.0    1.0    SC lowpass freq normalized
7    Hipass                        0.0           0.0    1.0    SC hipass freq normalized
8    SignIn                        0.0           0.0    1.0    Sidechain input toggle
9    AudIn                         0.0           0.0    1.0    Audition sidechain toggle
10   Dry                           ~0.0          0.0    2.0    Dry level (see Wet/Dry below)
11   Wet                           1.0           0.0    2.0    Wet level (see Wet/Dry below)
12   Filter Preview                0.0           0.0    1.0    Preview SC filter toggle
13   RMS size                      0.05          0.0    10.0   RMS window in seconds
14   Knee                          0.0           0.0    1.0    0=hard knee, 1=soft knee
15   Auto Make Up Gain             0.0           0.0    1.0    Toggle: 1=enabled
16   Auto Release                  0.0           0.0    1.0    Toggle: 1=enabled
17   Legacy Attack/Knee Options    0.25          0.0    1.0    Leave at default 0.25
18   Deprecated Broken Anti-Alias  0.0           0.0    1.0    Leave at 0
19   Multichannel Mode             0.0           0.0    1.0    0=stereo linked
20   Metering Index                0.0           0.0    1.0    Display only
21   Bypass                        0.0           0.0    1.0    1=bypassed
22   Wet                           1.0           0.0    1.0    Normalized duplicate of 11
23   Delta                         0.0           0.0    1.0    Delta monitoring toggle
```

### THRESHOLD SCALE

Param 0 (Threshold) is linear amplitude, range 0..2. Use TrackFX_SetParam (not normalized).
For dB targets, convert with: `value = 10^(dB / 20)`.

```
  2.0   = +6 dBFS
  1.0   = 0 dBFS   (default, no compression triggered)
  0.5   = -6 dBFS
  0.25  = -12 dBFS
  0.125 = -18 dBFS
  0.063 = -24 dBFS
```

Most user prompts name Threshold in dB. Param 0 uses direct linear amplitude,
not normalized position. Match the requested dB target to the direct value
below. Do NOT use 0.5 for -18 dB; 0.5 displays about -6 dB.

Common direct SetParam requests:

```lua
  local threshold = 10 ^ (-18 / 20)                  -- -18 dB -> ~0.1259
  reaper.TrackFX_SetParam(tr, fx, 0, threshold)      -- "set Threshold to -18 dB"
  reaper.TrackFX_SetParam(tr, fx, 0, 0.25)   -- "set Threshold to -12 dB"
  reaper.TrackFX_SetParam(tr, fx, 0, 0.5)    -- "set Threshold to -6 dB"
```

### RATIO SCALE

Param 1 (Ratio) normalized 0..1. Use TrackFX_SetParamNormalized.
For every finite ratio below the endpoint, use:

```
  normalized = (ratio - 1) / 99
  ratio      = 1 + (99 * normalized)
```

```
  0.000000 = 1:1
  0.010101 = 2:1
  0.020202 = 3:1
  0.030303 = 4:1
  0.050505 = 6:1
  0.070707 = 8:1
  0.191919 = 20:1
  1.000000 = inf:1
```

Do not estimate moderate ratios from broad rounded values. A change of 0.01 is
almost one full ratio point in the normal compression range, so calculate the
normalized value and verify the displayed ratio.

### ATTACK / RELEASE SCALE

Both normalized 0..1. Use TrackFX_SetParamNormalized.

```
  Attack:   0.0=0ms  0.01=5ms   0.02=10ms  0.10=50ms  0.24=120ms  1.0=500ms
  Release:  0.0=0ms  0.02=100ms 0.024=120ms 0.05=250ms 0.10=500ms  1.0=5000ms
```

### KNEE SCALE

Param 14 (Knee) is linear from 0 to 24 dB. Use
`TrackFX_SetParamNormalized` with `normalized = knee_dB / 24`.

```
  0.000 = 0 dB   hard knee
  0.125 = 3 dB   medium knee
  0.250 = 6 dB   typical soft knee
  0.400 = 9.6 dB very soft, broad transition
  0.500 = 12 dB  extra-soft transition
  1.000 = 24 dB  maximum knee
```

When the user asks only for a soft knee, use about 6 dB. Reserve 9 to 12 dB
for an explicitly very soft or extra-gentle transition.

### WET / DRY SCALE

Params 10 (Dry) and 11 (Wet) have range 0..2. Use TrackFX_SetParam (not normalized).

```
  0.0 = silence    1.0 = 0dB (unity)    2.0 = +6dB
```

Default: Dry=0 (off), Wet=1.0 (full wet). Leave at defaults for normal use.

### MUSICAL INTENT GUIDANCE

ReaComp settings are source- and level-dependent. Without audio analysis or a
known current gain-reduction reading, treat any open-ended result as a
conservative starting point, not a claim that a specific amount of compression
is occurring.

Normal user language:

- "Gentle," "natural" or "transparent" means moderate ratio, a nonzero attack
  that preserves some articulation, a release long enough to avoid obvious
  pumping and a soft knee. Avoid limiter-like ratios, zero attack, very short
  release and unnecessary detector or parallel controls.
- "More controlled" or "more even" means lower the threshold enough to engage
  compression and use a moderate ratio. Do not equate control with flattening
  all transients.
- "Punchy" means a slower attack than the gentle/transparent case so the front
  edge passes before gain reduction, with a release that recovers before the
  next strong hit. It does not mean the shortest attack.
- "Dense" or "aggressive" may use a higher ratio and faster timing, but should
  still avoid the brick-wall recipe unless the user explicitly asks for
  limiting.

Conservative starting regions when the user delegates the values:

```
Intent                    Threshold      Ratio       Attack       Release      Knee
gentle/natural vocal      -12..-6 dB     2:1..4:1    8..30 ms     80..200 ms   3..6 dB
general level control     -15..-6 dB     2:1..4:1    5..25 ms     60..250 ms   3..9 dB
punchy drum or bus        -12..-6 dB     3:1..6:1    15..50 ms    40..150 ms   1.5..6 dB
dense/aggressive          -18..-8 dB     4:1..10:1   1..15 ms     30..120 ms   0..6 dB
```

Prefer Auto Make Up Gain off for honest level comparison unless the user asks
for compensation or the task explicitly calls for a ready-to-hear starter.
Never turn on sidechain audition, filter preview, delta monitoring, legacy
options or multichannel modes for an ordinary compression request. Leave
Dry/Wet at the full-wet default unless the user asks for parallel compression.

### COMMON RECIPES

**"Gentle vocal/instrument compression":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 10 ^ (-9 / 20))    -- Threshold: -9 dBFS starting point
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.0202020202) -- Ratio: 3:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.03)    -- Attack: ~15 ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.024)   -- Release: ~120 ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.25)   -- Knee: 6 dB, soft
  -- Leave Auto Make Up Gain off for honest level comparison.
```

**"Drum bus / transient punch":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.35)              -- Threshold: ~-9dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.0303030303) -- Ratio: 4:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.05)    -- Attack: ~25ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.02)    -- Release: ~100ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.125)  -- Knee: 3 dB
  -- Leave Auto Make Up Gain off for honest level comparison.
```

**"Brick wall limiter":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.9)               -- Threshold: just under 0dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 1.0)     -- Ratio: inf:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.0)     -- Attack: 0ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.004)   -- Release: ~20ms
```

### FULL PATTERN (add ReaComp, gentle compression)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "ReaComp", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  reaper.TrackFX_SetParam(tr, fx, 0, 0.5)               -- Threshold: -6dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.0303030303) -- Ratio: 4:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.01)    -- Attack: ~5ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.02)    -- Release: ~100ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.25)   -- Knee: 6 dB, soft
  reaper.TrackFX_SetParamNormalized(tr, fx, 15, 0.0)    -- Auto make-up gain off
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReaComp: gentle compression", -1)
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaComp -->

<!-- PLUGIN:ReaDelay -->
<!-- SECTION-REVISION:2d1505761e84723a1c31653eb2ecaaa027231e7ca884df9483e26c5923698314 -->
## ReaDelay

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"readelay","display_name":"ReaDelay","vendor":"Cockos","product_class":"ordinary","preference_type":"delay","identifiers":{"add_by_name":["ReaDelay"],"aliases":["delay","echo"],"curated":["ReaDelay"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["readelay"],"context_required":["delay","echo"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"readelay","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaDelay","loaded_name":"VST: ReaDelay (Cockos)","parameter_count":{"mode":"exact","value":15},"required_parameters":[{"index":1,"name":"Dry","section":"","section_required":false},{"index":3,"name":"1: Length (time)","section":"","section_required":false},{"index":6,"name":"1: Lowpass","section":"","section_required":false},{"index":8,"name":"1: Resolution","section":"","section_required":false},{"index":11,"name":"1: Pan","section":"","section_required":false}],"observed_fingerprint_sha256":"848477142e5111653874aff0ab9fdb729bb8b0dad7babd74646e123aa1d8ac4d"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"d122578ae663f206bd14c10c130e0609e8d408874e6ea78790a49ec23b36b7b2","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaDelay"
Total params (1-tap default): 15 (indices 0-14)

IMPORTANT: ReaDelay uses a per-tap structure. Default instance has 1 tap.
Adding taps in the UI adds params dynamically. All tap params are prefixed "N: "
where N is the tap number. Tap 1 params start at index 2.

### PARAM INDEX TABLE (verified, 1-tap instance)

```
idx  Name                  Default val   Min    Max    Notes
---  --------------------  -----------   -----  -----  ----------------------------
0    Wet                   0.5           0.0    2.0    Effect wet level: 0.5=-6dB; duplicate-name guard below
1    Dry                   1.0           0.0    2.0    Dry level: 1.0=0dB
2    1: Enabled            1.0           0.0    1.0    Tap 1 on/off
3    1: Length (time)       0.0           0.0    1.0    Delay in seconds (0=off)
4    1: Length (musical)    0.0078        0.0    1.0    Whole notes; raw = display/256 (default 0.0078 -> 2.00)
5    1: Feedback           0.0           0.0    2.0    Feedback: 0=off, 1.0=0dB
6    1: Lowpass            1.0           0.0    1.0    Filter normalized (20000Hz)
7    1: Hipass             0.0           0.0    1.0    Filter normalized (0Hz)
8    1: Resolution         1.0           0.0    1.0    Bit depth (display: 24)
9    1: Stereo width       1.0           0.0    1.0    1.0=full stereo
10   1: Volume             1.0           0.0    2.0    Tap volume: 1.0=0dB
11   1: Pan                0.5           0.0    1.0    Center=0.5
12   Bypass                0.0           0.0    1.0    1=bypassed
13   Wet                   1.0           0.0    1.0    REAPER host wet control; leave unchanged
14   Delta                 0.0           0.0    1.0    Delta monitoring toggle
```

### DELAY TIME

There are two length params per tap. Use "Length (musical)" for tempo-synced delay,
"Length (time)" for free time in seconds. To set a specific delay in ms, use
set_param_display on "Length (time)".
Length (musical) is in whole notes and its raw value is display/256 (verified on
REAPER 7.76: raw 0.25/256 = 0.000977 displays 0.25 = quarter note; the DEFAULT raw
0.0078 displays 2.00 = TWO WHOLE NOTES). A tempo-synced recipe that does not set
Length (musical) ships a 2-measure delay, not the echo the user asked for.

### DUPLICATE WET NAME

Parameter 0 and REAPER's host parameter 13 are both named `Wet`, and both have
an empty section. A mapped write to the effect Wet control must use
`{ index = 0, name = "Wet", section = "" }`. The explicit empty section keeps
the resolver on the fingerprint-validated stored index and prevents ambiguous
name fallback. Never resolve this control as only `{ index = 0, name = "Wet" }`.
Leave host Wet at index 13 unchanged unless the user explicitly requests the
host control.

### COMMON RECIPE

**"Simple quarter-note echo":**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Wet", section = "" },
  { index = 3, name = "1: Length (time)" },
  { index = 4, name = "1: Length (musical)" },
  { index = 5, name = "1: Feedback" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.125) -- Effect Wet: -12.0 dB
reaper.TrackFX_SetParam(tr, fx, mapped[2], 0.0) -- Free-time length off
reaper.TrackFX_SetParam(tr, fx, mapped[3], 0.25 / 256) -- Quarter note
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.125) -- Feedback: -12.0 dB
```

For any request combining quarter-note sync, zero free-time length and about
-12 dB Wet/Feedback, all four writes above are mandatory. Copy the setter
types and numeric expressions exactly. Do not omit Length (musical), use its
default, substitute `2.00`, or use `TrackFX_SetParamNormalized` for that
control. Do not use raw `TrackFX_SetParam(..., 0.125)` for Wet or Feedback;
that displays about -18 dB.

The accepted GUI displays are effect Wet `-12.0`, Length (time) `0.0`, Length
(musical) `0.25` and Feedback `-12.0`. If a write does not produce those
displays, the recipe did not succeed.

For the natural request to give guitar a subtle quarter-note echo without
washing out the dry sound, use that exact four-write recipe. On an existing
instance, change only effect Wet, Tap 1 Length (time), Tap 1 Length (musical)
and Tap 1 Feedback. Preserve Dry, tap Enabled, Lowpass, Hipass, Resolution,
Stereo width, Volume, Pan, Bypass, host Wet, Delta and every other control
unless the user names it. Do not add another ReaDelay when the request says to
use the existing one.

For a request that adds ReaDelay and configures it, perform the existence
check, `TrackFX_AddByName`, parameter resolution and all four writes inside the
same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding ReaDelay and end it
only after the last verified write. One Undo must remove the new ReaDelay
instance and restore the original FX count.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaDelay -->

<!-- PLUGIN:ReaEQ -->
<!-- SECTION-REVISION:aeb321159f7ef93932ad6bf1d7614ec62adbc54dfbb66bd70451ad7c7bfc2f12 -->
## ReaEQ

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reaeq","display_name":"ReaEQ","vendor":"Cockos","product_class":"ordinary","preference_type":"eq","identifiers":{"add_by_name":["ReaEQ"],"aliases":["eq","equalizer","equaliser"],"curated":["ReaEQ"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reaeq"],"context_required":["eq","equaliser","equalizer"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reaeq","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaEQ","loaded_name":"VST: ReaEQ (Cockos)","parameter_count":{"mode":"exact","value":19},"required_parameters":[{"index":0,"name":"Freq-Low Shelf","section":"","section_required":false},{"index":3,"name":"Freq-Band 2","section":"","section_required":false},{"index":7,"name":"Gain-Band 3","section":"","section_required":false},{"index":11,"name":"BW-High Shelf 4","section":"","section_required":false},{"index":15,"name":"Global Gain","section":"","section_required":false}],"observed_fingerprint_sha256":"951f12a3d9ab96d5da7650286cfa8e3ff6881be67b32a8a334bc5661f2ed9bee"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"cec106afadee7ca0e6a559de86f81e23a3c3f99b99d0761deade759f2b69b56f","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaEQ"
Total params (default instance): 19 (indices 0-18)

### BAND LAYOUT

Default instance has 5 bands. Each band has 3 scriptable params: Freq, Gain, BW.
Param names reflect the default band type (e.g. "Freq-Low Shelf") but these are
labels only -- any band can be set to any type via the UI Type dropdown.

CRITICAL: Band Type is NOT exposed as a scriptable parameter. There is no Type
param index. Type can only be changed by the user in the UI. Scripts must work
with whatever type the band currently is, or instruct the user to set the type
manually. Never attempt to set band type via TrackFX_SetParam or SetParamNormalized.

DEFAULT BAND STATES (new instance):
  Band 1 (Low Shelf):  ENABLED  -- default gain 0dB / flat (normalized 0.50)
  Band 2 (Band):       ENABLED  -- default gain 0dB / flat (normalized 0.50)
  Band 3 (Band):       ENABLED  -- default gain 0dB / flat (normalized 0.50)
  Band 4 (High Shelf): ENABLED  -- default gain 0dB / flat (normalized 0.50)
  Band 5 (High Pass):  DISABLED by default -- setting params has no audible effect
Verified on REAPER 7.76: a fresh ReaEQ reads normalized 0.50 / formatted 0.0 dB
on every band gain. TrackFX_GetParam returns RAW 0.25 for that same flat state --
raw is a linear-amplitude scale (raw 0.25 = 0dB, raw 0.5 = +6dB, raw 1.0 = +12dB).
Never read a raw value through the normalized table below: normalized 0.25 is
-6dB, but raw 0.25 is flat.
Band enable/disable is stored in ReaEQ's internal chunk data, NOT as a scriptable
parameter. There is no enable param index among the 19 exposed params.
A disabled band ignores all param changes until the user enables it in the UI.
NEVER use Band 5 in generated code for a freshly added ReaEQ. Instead:
  - For low-cut / high-pass: set Band 1's frequency and tell the user to change
    its type from Low Shelf to High Pass in the ReaEQ UI.
  - For any filter needing Band 5: tell the user to enable Band 5 in the UI first,
    then set its params via script on a follow-up request.

Available band types (UI only, not scriptable):
  Low Shelf, High Shelf, Band, Low Pass, High Pass, All Pass,
  Notch, Band Pass, Parallel Band Pass, Band (alt), Band (alt 2)

### PARAM INDEX TABLE (verified, default 5-band instance)

```
idx  Name               Default val   Min   Max   Notes
---  -----------------  -----------   ----  ----  --------------------------------
0    Freq-Low Shelf     0.1414        0.0   1.0   Normalized freq (~100Hz default)
1    Gain-Low Shelf     0.50          0.0   1.0   Normalized: 0.50 = 0dB (default; flat)
2    BW-Low Shelf       0.20          0.0   1.0   Bandwidth normalized

3    Freq-Band 2        0.2895        0.0   1.0   ~300Hz default
4    Gain-Band 2        0.50          0.0   1.0   0.50 = 0dB (default; flat)
5    BW-Band 2          0.50          0.0   1.0

6    Freq-Band 3        0.4760        0.0   1.0   ~1kHz default
7    Gain-Band 3        0.50          0.0   1.0   0.50 = 0dB (default; flat)
8    BW-Band 3          0.50          0.0   1.0

9    Freq-High Shelf 4  0.7394        0.0   1.0   ~5kHz default
10   Gain-High Shelf 4  0.50          0.0   1.0   0.50 = 0dB (default; flat)
11   BW-High Shelf 4    0.20          0.0   1.0

12   Freq-High Pass 5   0.1414        0.0   1.0   ~100Hz default
13   Gain-High Pass 5   0.50          0.0   1.0   0.50 = 0dB (default; flat)
14   BW-High Pass 5     0.50          0.0   1.0

15   Global Gain        1.0           0.0   4.0   Linear: 1.0=0dB, 2.0=+6dB
16   Bypass             0.0           0.0   1.0   1.0 = bypassed
17   Wet                1.0           0.0   1.0   1.0 = fully wet
18   Delta              0.0           0.0   1.0   Delta monitoring toggle
```

### GAIN SCALE (verified with TrackFX_GetFormattedParamValue)

All per-band Gain params are normalized 0..1. Verified dB values (exact):

```
  0.0000 = -inf dB  (silence)
  0.1250 = -12.0 dB
  0.1582 = -10.0 dB
  0.1992 = -8.0 dB
  0.2500 = -6.0 dB
  0.2813 = -5.0 dB
  0.3164 = -4.0 dB
  0.3555 = -3.0 dB
  0.3984 = -2.0 dB
  0.4453 = -1.0 dB
  0.5000 = 0.0 dB   (FLAT/UNITY -- the fresh-instance default; use for no gain change)
  0.5195 = +1.0 dB
  0.5430 = +2.0 dB
  0.5684 = +3.0 dB
  0.5977 = +4.0 dB
  0.6289 = +5.0 dB
  0.6641 = +6.0 dB
  0.7070 = +7.0 dB
  0.7500 = +8.0 dB
  0.8047 = +9.0 dB
  0.8594 = +10.0 dB
  0.9219 = +11.0 dB
  0.9961 = +12.0 dB
```

CRITICAL: 0.50 = 0dB (flat) and IS the fresh-instance default. Normalized 0.25
= -6dB. If a live raw dump (TrackFX_GetParam) shows 0.25 on a band gain, that is
the flat default in raw linear-amplitude units, NOT -6dB -- use normalized
values with this table only.
Always use TrackFX_SetParamNormalized for Gain.
Do NOT use TrackFX_SetParam with raw dB values -- min/max are 0..1, not dB.
Use ONLY the verified values above. Do NOT invent your own gain formula, do NOT
use set_param_display or binary search. For +3 dB, use 0.5684. For -3 dB, use 0.3555. Etc.

### FREQUENCY SCALE

All Freq params are normalized 0..1 (log scale). Verified values:

```
  0.0078 ~ 20 Hz       0.0625 ~ 50 Hz       0.1094 ~ 80 Hz
  0.1406 ~ 100 Hz      0.1953 ~ 150 Hz      0.2344 ~ 200 Hz
  0.2656 ~ 250 Hz      0.2891 ~ 300 Hz      0.3320 ~ 400 Hz
  0.3672 ~ 500 Hz      0.3945 ~ 600 Hz      0.4199 ~ 700 Hz
  0.4414 ~ 800 Hz      0.4590 ~ 900 Hz      0.4766 ~ 1 kHz
  0.5059 ~ 1.2 kHz     0.5410 ~ 1.5 kHz     0.5884 ~ 2 kHz
  0.6250 ~ 2.5 kHz     0.6553 ~ 3 kHz       0.6802 ~ 3.5 kHz
  0.7026 ~ 4 kHz       0.7393 ~ 5 kHz       0.7695 ~ 6 kHz
  0.7952 ~ 7 kHz       0.8173 ~ 8 kHz       0.8542 ~ 10 kHz
  0.8846 ~ 12 kHz      0.9103 ~ 14 kHz      0.9325 ~ 16 kHz
  0.9521 ~ 18 kHz      0.9696 ~ 20 kHz      1.0000 ~ 24 kHz
```

Always use TrackFX_SetParamNormalized for Freq. Never pass raw Hz values.
Use ONLY the verified values above. Do NOT invent your own Hz-to-normalized
formula. For 4 kHz, use 0.7026. For 1 kHz, use 0.4766. Etc.
For frequencies between landmarks, linearly interpolate between the two nearest entries.

### BAND INDEX SHORTHAND

```
Band 1: params 0,1,2    (Freq, Gain, BW)
Band 2: params 3,4,5
Band 3: params 6,7,8
Band 4: params 9,10,11
Band 5: params 12,13,14
```

Formula: band N (1-based) -> Freq=(N-1)*3, Gain=(N-1)*3+1, BW=(N-1)*3+2

### COMMON RECIPES

All values use `TrackFX_SetParamNormalized`. Resolve every target by its
fingerprint-validated index and exact name before writing. Never copy a bare
index into a setter.

```
Job                 Parameters                         Normalized targets
------------------  ---------------------------------  ----------------------------
Make it darker      Freq-High Shelf 4, Gain-High       0.7393 (5 kHz), 0.3555 (-3 dB)
Make it brighter    Freq-High Shelf 4, Gain-High       0.7393 (5 kHz), 0.5684 (+3 dB)
Add warmth          Freq-Low Shelf, Gain-Low Shelf     0.2344 (200 Hz), 0.5684 (+3 dB)
Remove muddiness    Freq-Low Shelf, Gain-Low Shelf     0.2344 (200 Hz), 0.3984 (-2 dB)
Prepare rumble cut  Freq-Low Shelf, Gain-Low Shelf     0.1094 (80 Hz), 0.5000 (0 dB)
```

For vague requests such as "a little darker," prefer a broad High Shelf cut
of about 2 to 3 dB around 5 to 7 kHz. Preserve the low bands, bandwidth,
Global Gain, bypass, Wet and Delta unless the user asks for them. A source-free
request does not justify a steep cut or several new moves.

For the natural request to make guitar a little darker without changing its
level, use exactly the `5 kHz`, `-3 dB` High Shelf 4 recipe above. Change only
`Freq-High Shelf 4` and `Gain-High Shelf 4`. Preserve every other band,
bandwidth, Global Gain, Bypass, Wet, Delta and every other control unless the
user names it. Do not add another ReaEQ when the request says to use the
existing one. Do not substitute another frequency, gain amount or additional
EQ move.

For an exact request that adds ReaEQ and sets High Shelf 4 to `5 kHz` and
`-3 dB`, use the same two guarded normalized writes shown in the full pattern.
Resolve both targets by index and exact name before either write, then verify
that both formatted displays settled at the requested values. Do not change a
band type because band type is not scriptable.

For a request that adds ReaEQ and configures it, perform the existence check,
`TrackFX_AddByName`, parameter resolution and both writes inside the same outer
`reaper.defer()` and exactly one `Undo_BeginBlock` / `Undo_EndBlock` pair.
Begin the undo block before adding ReaEQ and end it only after the last verified
write. One Undo must remove the new ReaEQ instance and restore the original FX
count.

Then tell the user to change Band 1's type from Low Shelf to High Pass in
the ReaEQ UI. Do not write Band 5 params on a freshly added ReaEQ; Band 5 is
disabled by default and will ignore parameter changes until enabled manually.

### FULL PATTERN (add ReaEQ and darken)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 9, name = "Freq-High Shelf 4" },
    { index = 10, name = "Gain-High Shelf 4" },
  })
  if not mapped then error(guard_err) end
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.7393) -- 5 kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.3555) -- -3 dB
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReaEQ: darken", -1)
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaEQ -->

<!-- PLUGIN:ReaGate -->
<!-- SECTION-REVISION:a39e098cfbe293bb3ace76bcd4aa8414b6616468e5070a9902b28ac9feea0d45 -->
## ReaGate

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reagate","display_name":"ReaGate","vendor":"Cockos","product_class":"ordinary","preference_type":"gate","identifiers":{"add_by_name":["ReaGate"],"aliases":["gate","expander"],"curated":["ReaGate"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reagate"],"context_required":["expander","gate"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reagate","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaGate","loaded_name":"VST: ReaGate (Cockos)","parameter_count":{"mode":"exact","value":24},"required_parameters":[{"index":0,"name":"Threshold","section":"","section_required":false},{"index":4,"name":"Hold","section":"","section_required":false},{"index":9,"name":"Dry","section":"","section_required":false},{"index":15,"name":"Send MIDI","section":"","section_required":false},{"index":20,"name":"Metering Index","section":"","section_required":false}],"observed_fingerprint_sha256":"d0153f3ae675b084f3107947b8948d10cb9f9ca652cbd45499fe3cea5485e3d3"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"5291bb6699105bab967f91ad3cc724df52e40d934eeebc2d4cae4fa7e244caaa","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaGate"
Total params: 24 (indices 0-23)

### PARAM INDEX TABLE (verified)

```
idx  Name               Default val   Min    Max    Notes
---  -----------------  -----------   -----  -----  ----------------------------
0    Threshold          0.0           0.0    2.0    Linear amp (same scale as ReaComp)
1    Attack             0.006         0.0    1.0    Normalized seconds (display: 3ms)
2    Release            0.020         0.0    1.0    Normalized seconds (display: 100ms)
3    Pre-open           0.0           0.0    1.0    Lookahead: 0=off
4    Hold               0.0           0.0    1.0    Hold time: 0=off
5    Lowpass            1.0           0.0    1.0    SC lowpass normalized (20000Hz)
6    Hipass             0.0           0.0    1.0    SC hipass normalized (0Hz)
7    SignIn             0.0           0.0    1.0    Sidechain input toggle
8    AudIn              0.0           0.0    1.0    Audition sidechain toggle
9    Dry                0.0           0.0    2.0    Dry level: 0=off
10   Wet                1.0           0.0    2.0    Wet level: 1.0=0dB
11   Noise level        0.0           0.0    2.0    Mix noise under gate: 0=off
12   Hysteresis         1.0           0.0    2.0    Close threshold offset: 1.0=0dB
13   Preview Filter     0.0           0.0    1.0    Preview SC filter toggle
14   RMS size           0.0           0.0    10.0   RMS window: 0=peak mode
15   Send MIDI          0.0           0.0    1.0    MIDI note trigger toggle
16   Midi Note          0.5433        0.0    1.0    MIDI note number (display: 69=A4)
17   Midi Channel       0.0           0.0    1.0    MIDI channel (display: 1)
18   Invert Wet         0.0           0.0    2.0    0=disabled, invert gated signal
19   Multichannel Mode  0.0           0.0    1.0    0=stereo linked
20   Metering Index     0.0           0.0    1.0    Display only
21   Bypass             0.0           0.0    1.0    1=bypassed
22   Wet                1.0           0.0    1.0    Normalized duplicate of 10
23   Delta              0.0           0.0    1.0    Delta monitoring toggle
```

### THRESHOLD SCALE

Same linear amplitude scale as ReaComp param 0. Use `TrackFX_SetParam`, not
the normalized setter. Convert a requested dB value with
`value = 10 ^ (dB / 20)`.
Default is 0.0 (-inf dB), meaning the gate is fully open by default.

```
  0.0   = -inf dB  (gate always open, default)
  0.063 = -24 dBFS
  0.125 = -18 dBFS
  0.25  = -12 dBFS
  0.5   = -6 dBFS
  1.0   = 0 dBFS
```

### ATTACK / RELEASE / HOLD SCALE

Use TrackFX_SetParamNormalized.

```
  Attack:  0.0=0ms  0.01=5ms   0.02=10ms  0.10=50ms  0.24=120ms  1.0=500ms
  Release: 0.0=0ms  0.02=100ms 0.024=120ms 0.05=250ms 0.10=500ms  1.0=5000ms
  Hold:    0.0=0ms  0.005=5ms  0.01=10ms  0.05=50ms  0.10=100ms  1.0=1000ms
```

### COMMON RECIPES

Resolve every target by its fingerprint-validated index and exact name before
writing. Never copy a bare index into a setter.

```
Job                         Threshold       Attack   Release   Hold
--------------------------  --------------  -------  --------  ------
Exact standard gate         -18 dBFS        1 ms     50 ms     10 ms
Gentle voice cleanup start  -24 dBFS        3 ms     250 ms    80 ms
Tight drum gate start       -12 dBFS        0.25 ms  20 ms     5 ms
```

For the exact standard gate, use these calibrated values:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Threshold" },
  { index = 1, name = "Attack" },
  { index = 2, name = "Release" },
  { index = 4, name = "Hold" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 10 ^ (-18 / 20))
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.002) -- 1 ms
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.010) -- 50 ms
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.010) -- 10 ms
```

### MUSICAL RESTRAINT

For the natural request to clean up room noise on a vocal without clipping
breaths or word endings, use exactly the gentle voice cleanup recipe: Threshold
`-24.0 dB`, Attack `3 ms`, Release `250 ms` and Hold `80 ms`. Resolve these four
targets in the literal order below and use exactly these writes:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Threshold" },
  { index = 1, name = "Attack" },
  { index = 2, name = "Release" },
  { index = 4, name = "Hold" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 10 ^ (-24 / 20))
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.006) -- 3 ms
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.050) -- 250 ms
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.080) -- 80 ms
```

On an existing instance, change only Threshold, Attack, Release and Hold.
Preserve Pre-open, both detector filters, sidechain input, audition, Dry, both
Wet controls, Noise level, Hysteresis, Preview Filter, RMS size, MIDI controls,
Invert Wet, Multichannel Mode, Bypass, Delta and every other control unless the
user names it. Do not add another ReaGate when the request says to use the
existing one. Do not substitute another conservative recipe.

For a request that adds ReaGate and configures the exact standard gate, perform
the existence check, `TrackFX_AddByName`, parameter resolution and all four
writes inside the same outer `reaper.defer()` and exactly one
`Undo_BeginBlock` / `Undo_EndBlock` pair. Begin the undo block before adding
ReaGate and end it only after the last verified write. One Undo must remove the
new ReaGate instance and restore the original FX count.

A useful threshold depends on the source level and the noise floor. Parameter
control alone cannot prove that speech, breaths or decay tails survive. For a
vague voice or room-noise request, start conservatively around -24 dBFS with
about 3 ms attack, 80 ms hold and 250 ms release. Tell the user to listen to
word endings and quiet breaths, then lower the threshold or lengthen hold and
release if anything is clipped.

Do not use the tight drum timing for voice. Do not change detector filters,
sidechain input, preview, RMS mode, MIDI output, noise mix, dry/wet balance,
polarity, multichannel mode, bypass or Delta unless the user asks. ReaGate's
effect Wet at index 10 and host Wet at index 22 share the same name; any request
for Wet must bind the fingerprint-validated index explicitly.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaGate -->

<!-- PLUGIN:ReaLimit -->
<!-- SECTION-REVISION:01a7229647962d0a7a48ea75abee3737e02124c4779a0018a1e50dcbe326204f -->
## ReaLimit

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"realimit","display_name":"ReaLimit","vendor":"Cockos","product_class":"ordinary","preference_type":"limiter","identifiers":{"add_by_name":["ReaLimit"],"aliases":["limiter","limit"],"curated":["ReaLimit"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["realimit"],"context_required":["limit","limiter"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"realimit","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaLimit","loaded_name":"VST: ReaLimit (Cockos)","parameter_count":{"mode":"exact","value":6},"required_parameters":[{"index":0,"name":"Threshold","section":"","section_required":false},{"index":1,"name":"Ceiling","section":"","section_required":false},{"index":2,"name":"Release","section":"","section_required":false}],"observed_fingerprint_sha256":"cd52df455d42709111b34239120fca66082ecac1f32ebd8dbbc1cf413e43408e"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"9ae2d89710bf183c8fb3a059010fdbb015bf28842e351d6094730fdfe8cd0523","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaLimit"
Total params: 6 (indices 0-5)

### PARAM INDEX TABLE (verified)

```
idx  Name        Default val   Min    Max    Notes
---  ----------  -----------   -----  -----  ----------------------------
0    Threshold   0.8333        0.0    1.0    Normalized (display: +0.00 dB)
1    Ceiling     1.0           0.0    1.0    Normalized (display: +0.00 dB)
2    Release     0.3548        0.0    1.0    Normalized (display: 15.0 dB/sec)
3    Bypass      0.0           0.0    1.0    1=bypassed
4    Wet         1.0           0.0    1.0    1.0=fully wet
5    Delta       0.0           0.0    1.0    Delta monitoring toggle
```

### THRESHOLD / CEILING SCALE

Both are normalized 0..1. Use `set_param_display` for arbitrary user-specified
values that are not covered by a verified direct mapping. For the certified
recipes below, use only the literal normalized values shown. Do not call or
define `set_param_display` for either certified recipe. Those direct values were
verified through the settled formatted displays and avoid a large helper body.
Threshold default 0.8333 = 0 dB. Lower values = more limiting.
Ceiling default 1.0 = 0dB. Sets the output ceiling.

Threshold is source-dependent. A fixed threshold cannot guarantee transparent
limiting because the useful target is modest gain reduction on the loudest
peaks. For a vague request to catch peaks while preserving dynamics, begin in
the -1 to -4 dB region and avoid pushing lower without audio or gain-reduction
evidence. A -1 dB ceiling is a conservative delivery starting point when the
user explicitly asks for safe headroom.

Release is displayed as a recovery rate in dB/sec, with an observed endpoint
span of `32.0` to `6.0 dB/sec`. Lower rates recover more gradually and can sound
smoother, but may hold the level down or pump. Higher rates recover faster and
can sound edgy or distort low-frequency material. The default `15.0 dB/sec` is
a restrained unknown-source starting point. A slightly slower `12.0 dB/sec`
can suit a request for transparent peak control while staying well away from
the slowest endpoint. Adjust by ear for pumping, transient damage and recovery.

Leave Bypass, host Wet and Delta unchanged unless the user names them.

### EXACT CONTROL RECIPE

**"Threshold -6 dB and ceiling -1 dB":**

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Threshold" },
  { index = 1, name = "Ceiling" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.75) -- -6.00 dB
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.958333313465118) -- -1.00 dB
```

The accepted GUI displays are Threshold `-6.00` and Ceiling `-1.00`. Preserve
Release and every unrelated control.

For a request that adds ReaLimit and applies this exact recipe, perform the
existence check, `TrackFX_AddByName`, parameter resolution and both writes
inside the same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding ReaLimit and end it
only after both formatted displays are verified. One Undo must remove the new
ReaLimit instance and restore the original FX count. Do not add a replacement
instance if the requested add fails.

### NATURAL PEAK-CONTROL START

For "catch peaks transparently, keep it dynamic and leave a safe -1 dB
ceiling," a conservative unknown-source starting point is Threshold `-3.0 dB`,
Ceiling `-1.0 dB` and Release `12.0 dB/sec`:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Threshold" },
  { index = 1, name = "Ceiling" },
  { index = 2, name = "Release" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.7916259765625) -- -3.00 dB
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.958333313465118) -- -1.00 dB
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.502734363079071) -- 12.0 dB/sec
```

For that natural request, use exactly this three-write recipe. On an existing
instance, change only Threshold, Ceiling and Release. Preserve Bypass, Wet,
Delta and every other control unless the user names it. Do not add another
ReaLimit when the request says to use the existing one. Do not substitute a
different threshold, ceiling, release rate or additional limiting control.
Verify the settled formatted displays are `-3.00`, `-1.00` and `12.0` before
reporting success.

Treat this as a starting point. If gain reduction is more than modest or the
source loses punch, raise the threshold. If it pumps or stays reduced between
peaks, shorten or lengthen Release by ear according to the material.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaLimit -->

<!-- PLUGIN:ReaPitch -->
<!-- SECTION-REVISION:94fd95d7bfbae2b0833da20b993e615d1db08829f42e39b3821868d2aa05ad6e -->
## ReaPitch

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reapitch","display_name":"ReaPitch","vendor":"Cockos","product_class":"ordinary","preference_type":"pitch_shift","identifiers":{"add_by_name":["ReaPitch"],"aliases":["pitch","pitch shift"],"curated":["ReaPitch"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reapitch"],"context_required":["pitch"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reapitch","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaPitch","loaded_name":"VST: ReaPitch (Cockos)","parameter_count":{"mode":"exact","value":15},"required_parameters":[{"index":0,"name":"Wet","section":"","section_required":true},{"index":1,"name":"Dry","section":"","section_required":true},{"index":4,"name":"1: Shift (cents)","section":"","section_required":true},{"index":11,"name":"1: Pan","section":"","section_required":true}],"observed_fingerprint_sha256":"1246f568585863d754e1e6acb522d42f47f3a719c7515327d6319a774814093e"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"8854e4e6e2fbdb85c7d98c829bb0fb8646ef5f27b9e7bb7f82fc3e224a4d7035","verified_at":"2026-07-26","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaPitch"
Total params (1-shift default): 15 (indices 0-14)

IMPORTANT: ReaPitch uses a per-shift structure like ReaDelay. Default has 1 shift.
Adding shifts in the UI adds params dynamically. All shift params prefixed "N: ".

### PARAM INDEX TABLE (verified, 1-shift instance)

```
idx  Name                        Default   Min    Max    Notes
---  --------------------------  -------   -----  -----  ----------------------------
0    Wet                         1.0       0.0    2.0    Wet level: 1.0=0dB
1    Dry                         0.0       0.0    2.0    Dry level: 0=off
2    1: Enabled                  1.0       0.0    1.0    Shift 1 on/off
3    1: Shift (full range)       0.5       0.0    1.0    Full pitch range: 0.5=no shift
4    1: Shift (cents)            0.5       0.0    1.0    Fine tune: 0.5=0 cents
5    1: Shift (semitones)        0.5       0.0    1.0    Semitone shift: 0.5=0
6    1: Shift (oct)              0.5       0.0    1.0    Octave shift: 0.5=0
7    1: Formant adjust (full range) 0.5    0.0    1.0    Formant: 0.5=no adjust
8    1: Formant adjust (cents)   0.5       0.0    1.0    Formant fine: 0.5=0
9    1: Formant adjust (semitones) 0.5     0.0    1.0    Formant semitone: 0.5=0
10   1: Volume                   1.0       0.0    2.0    Shift volume: 1.0=0dB
11   1: Pan                      0.5       0.0    1.0    Center=0.5
12   Bypass                      0.0       0.0    1.0    1=bypassed
13   Wet                         1.0       0.0    1.0    Normalized duplicate of 0
14   Delta                       0.0       0.0    1.0    Delta monitoring toggle
```

### CONTROL AND MUSICAL GUIDANCE

Use `Shift (cents)` for fine detuning and `Shift (semitones)` or `Shift (oct)`
for intentional musical transposition. ReaPitch adds the full-range, cents,
semitone and octave shift controls together. For one requested shift, change
only the matching control and leave the other three at zero. Small detuning
does not normally need a formant adjustment.

Indices 0 and 13 are both named Wet. Index 0 is ReaPitch's processed-signal
level; index 13 is the host Wet control. Resolve index 0 with its exact name and
an explicit empty section. Do the same for Dry, Shift 1 cents and Shift 1 Pan.
Never use a bare index or assume the duplicate Wet parameter from its name.

For a subtle detuned layer, keep Shift 1 between about 8 and 15 cents. Make the
original signal dominant: a useful starting region is Dry `0 to -3 dB` and Wet
`-12 to -6 dB`. Equal Wet and Dry near `-6 dB` is a more obvious balanced
blend. If the user asks for widening, pan the quieter shifted layer about 20 to
40 percent to one side while the dry signal stays centered. Check mono because
fine detuning can create combing. One shifter gives an asymmetric layer; do not
claim that it creates a symmetrical plus/minus detune pair.

Leave Shift 1 Enabled on, Shift 1 Volume at `0 dB`, all formant controls at
zero, Bypass off, host Wet at 100 percent and Delta off unless the user asks for
one of those controls.

### VERIFIED NORMALIZED ANCHORS

These values were confirmed through parameter readback and the visible ReaPitch
GUI in the fingerprinted 15-parameter VST build above. Use them only after the
profile fingerprint validates. Keep the formatted-value readback after writing.

```
Control             Musical value   Normalized value
------------------  --------------  ------------------
Wet                 -6.0 dB         0.2503906190395355
Dry                 -6.0 dB         0.2503906190395355
Shift 1 cents       +15 cents       0.537109375
Wet                 -9.0 dB         0.17802734673023224
Dry                 -1.0 dB         0.443359375
Shift 1 cents       +10 cents       0.525390625
Shift 1 pan         30% R           0.6499999761581421
```

### EXACT CONTROL RECIPE

For `Shift 1 +15 cents, Wet -6 dB and Dry -6 dB`:

The `tr` and `fx` names below are placeholders for the exact MediaTrack and FX
index already resolved by the script. If the track variable is named `track_1`,
pass `track_1` to the resolver. Never copy an undefined `tr` from the recipe.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Wet", section = "" },
  { index = 1, name = "Dry", section = "" },
  { index = 4, name = "1: Shift (cents)", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.2503906190395355)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.2503906190395355)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.537109375)
```

Preserve the other 12 controls. In particular, do not write the full-range,
semitone or octave shift controls for this cents-only request.

For a request that adds ReaPitch and applies this exact recipe, perform the
existence check, `TrackFX_AddByName`, parameter resolution and all three writes
inside the same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding ReaPitch and end it
only after the accepted displays `-6.0`, `-6.0` and `15` are verified. One Undo
must remove the new ReaPitch instance and restore the original FX count. Do not
add a replacement instance if the requested add fails.

### NATURAL SUBTLE-WIDENING START

For `subtle widening detune, not an obvious pitch-shift effect`, begin with
Shift 1 at `+10 cents`, Wet `-9 dB`, Dry `-1 dB` and Shift 1 Pan at `30% R`:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Wet", section = "" },
  { index = 1, name = "Dry", section = "" },
  { index = 4, name = "1: Shift (cents)", section = "" },
  { index = 11, name = "1: Pan", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.17802734673023224)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.443359375)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.525390625)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.6499999761581421)
```

For the natural request to give an existing ReaPitch a little
more width while keeping the vocal subtle and not obviously pitch-shifted, use
exactly this four-write recipe. Resolve the existing ReaPitch with
`TrackFX_GetByName(..., false)` and fail closed if it is missing. Never add a
second ReaPitch for this existing-instance request.

Change only effect Wet, Dry, Shift 1 cents and Shift 1 Pan. Preserve Shift 1
Enabled, full-range shift, semitone shift, octave shift, all formant controls,
Shift 1 Volume, Bypass, host Wet, Delta and every other control unless the user
names it. Do not substitute another detune, balance, pan or extra shift.

The dry-dominant balance limits the level increase and keeps the pitch-shifted
layer secondary. Reduce Wet or narrow the pan if the effect pulls the image to
one side. Reduce the cents offset if pitch beating becomes obvious.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaPitch -->

<!-- PLUGIN:ReaSynth -->
<!-- SECTION-REVISION:ab96c94e1ae1adaaafd5f2186acaf4993c6163b4f050f9338d4225e283971ebb -->
## ReaSynth

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reasynth","display_name":"ReaSynth","vendor":"Cockos","product_class":"ordinary","preference_type":"synth","identifiers":{"add_by_name":["ReaSynth"],"aliases":["synth","synthesizer"],"curated":["ReaSynth"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reasynth"],"context_required":["synth","synthesizer"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reasynth","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaSynth","loaded_name":"VSTi: ReaSynth (Cockos)","parameter_count":{"mode":"exact","value":18},"required_parameters":[{"index":0,"name":"Attack","section":"","section_required":true},{"index":1,"name":"Release","section":"","section_required":true},{"index":3,"name":"Saw mix","section":"","section_required":true},{"index":6,"name":"Decay","section":"","section_required":true},{"index":7,"name":"Extra sine mix","section":"","section_required":true},{"index":9,"name":"Sustain","section":"","section_required":true},{"index":10,"name":"Pulse Width","section":"","section_required":true},{"index":14,"name":"Broken portamento extra sine oscillator","section":"","section_required":true}],"observed_fingerprint_sha256":"31ccc6068a2617a56b058309627378695ed249bfcbd42d39e5eb278d798a486f"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"b36458606b5943e09528c0ca6b0a4d54c0f3cea6f3622c9ada36b0047fb406bd","verified_at":"2026-07-26","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaSynth"
Total params: 18 (indices 0-17)

ReaSynth is a VST instrument. Use
`TrackFX_AddByName(track, "ReaSynth", false, -1)` when the user asks to add it.
It generates audio from MIDI notes. A request to configure its sound does not
also authorize creating MIDI items, notes or downstream effects.

### PARAM INDEX TABLE (verified on the 18-parameter VST build)

```
idx  Name                                    Default normalized  GUI default  Notes
---  --------------------------------------  ------------------  -----------  ------------------------
0    Attack                                  0.0006000000        3.0 ms       amplitude envelope
1    Release                                 0.0016000000        8 ms         amplitude envelope
2    Square mix                              0                   0.00          additive waveform level
3    Saw mix                                 0                   0.00          additive waveform level
4    Triangle mix                            0                   0.00          additive waveform level
5    Volume                                  0.2505936027        -6.00 dB     output level
6    Decay                                   0.0666044429        1000 ms      amplitude envelope
7    Extra sine mix                          0                   0.00          additive oscillator level
8    Extra sine tuning                       0.5                 0 cent        extra oscillator tuning
9    Sustain                                 0.5                 +0.00 dB     envelope sustain level
10   Pulse Width                             1                   0.50          affects square oscillator
11   Global detune                           0.5                 0 cent        master tuning offset
12   Legacy oscillator mode                  0                   0             leave off
13   Portamento                              0                   0 ms          glide time
14   Broken portamento extra sine oscillator 0                   0             leave off
15   Bypass                                  0                   normal        host bypass
16   Wet                                     1                   100           host wet
17   Delta                                   0                   normal        host delta monitor
```

### CONTROL AND MUSICAL GUIDANCE

ReaSynth's base sine remains present while Square, Saw, Triangle and Extra sine
are added. The waveform controls are additive levels rather than an exclusive
selector. Raising several to high values can make the sound louder and denser.
For one requested basic waveform, change only that mix control. Pulse Width is
relevant only when Square mix is audible.

For a soft pad, use a nonzero Attack and a Release long enough to avoid a hard
cutoff. Keep some sustain and avoid high Saw or Square additions because
ReaSynth has no built-in filter to tame their upper harmonics. A saw addition
around `0.4` to `0.65` over the base sine is a useful starting region. Attack
around `100` to `300 ms`, Decay around `800` to `1800 ms`, Sustain around
`-6` to `-3 dB` and Release around `400` to `1200 ms` form a conservative pad
envelope. Treat these as starting values because the MIDI part and downstream
processing determine the final musical result.

For a clicky or plucked sound, shorter Attack and Release may be intentional.
Do not interpret "soft" as simply lowering Volume. Do not enable the legacy or
broken-portamento controls. Leave Global detune, Portamento, output Volume,
host Wet, Bypass and Delta unchanged unless the user asks for them.

### VERIFIED SCALE AND VALUE ANCHORS

The current VST build exposes these linear normalized timing relationships:

```
Attack normalized  = milliseconds / 5000
Release normalized = milliseconds / 5000
Decay normalized   = milliseconds / 15015
```

Use only the fixed GUI-confirmed anchors below for a recipe. For another exact
numeric request, prefer `set_param_display`, then verify the formatted value.
Sustain and Volume are amplitude-based dB controls. Normalized `0.5` displays
`+0.00 dB`, so it must not be used for a requested `-6 dB` Sustain value.

```
Control       Musical value  Normalized value
------------  -------------  ------------------
Saw mix       0.80           0.800000011920929
Attack        100.0 ms       0.020000000298023225
Decay         500 ms         0.0333000011742115
Sustain       -6.00 dB       0.2505936026573181
Release       100 ms         0.019999999552965164
```

### EXACT CONTROL RECIPE

For `Saw mix 80%, Attack 100 ms, Decay 500 ms, Sustain -6 dB and Release
100 ms`:

The `tr` and `fx` names below are placeholders. Pass the actual MediaTrack and
FX-index variables already resolved by the script.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 3, name = "Saw mix", section = "" },
  { index = 0, name = "Attack", section = "" },
  { index = 6, name = "Decay", section = "" },
  { index = 9, name = "Sustain", section = "" },
  { index = 1, name = "Release", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.800000011920929)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.020000000298023225)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0333000011742115)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.2505936026573181)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.019999999552965164)
```

Preserve the other 13 controls. The accepted GUI displays are Saw mix `0.80`,
Attack `100.0`, Decay `500`, Sustain `-6.00` and Release `100`.

For a request that adds ReaSynth and applies this exact recipe, perform the
existence check, `TrackFX_AddByName`, parameter resolution and all five writes
inside the same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding ReaSynth and end it
only after all five accepted displays are verified. One Undo must remove the
new ReaSynth instance and restore the original FX count. Do not add a
replacement instance if the requested add fails. Do not create MIDI items or
notes as part of this sound-configuration request.

### NATURAL SOFT-PAD START

For `soft basic saw pad with a gentle entrance and release, not a clicky lead`,
begin with Saw mix `0.55`, Attack `180 ms`, Decay `1200 ms`, Sustain `-4 dB`
and Release `700 ms`. These values retain the sine foundation, add saw color
without the unfiltered maximum and give notes a clear pad-like shape.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 3, name = "Saw mix", section = "" },
  { index = 0, name = "Attack", section = "" },
  { index = 6, name = "Decay", section = "" },
  { index = 9, name = "Sustain", section = "" },
  { index = 1, name = "Release", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.55)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.036)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.07992007992007992)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.3154786722400966)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.14)
```

For that natural request, use exactly this five-write recipe. Resolve the
existing ReaSynth with `TrackFX_GetByName(..., false)` and fail closed if it is
missing. Never add a second ReaSynth for an existing-instance request. Change
only Saw mix, Attack, Decay, Sustain and Release. Preserve Square mix, Triangle
mix, Volume, Extra sine controls, Pulse Width, Global detune, legacy mode,
Portamento, the broken-portamento control, Bypass, Wet, Delta and every other
control unless the user names it. Do not create MIDI, downstream effects or a
different synth patch. The accepted displays are `0.55`, `180.0`, `1200`,
`-4.00` and `700`.

Reduce Saw mix if the timbre is too bright. Shorten Release if notes overlap
too much, or lengthen it if releases still feel abrupt. ReaSynth alone cannot
provide filtered movement, modulation or stereo width, so do not claim those
qualities unless the user also requests suitable downstream processing.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaSynth -->

<!-- PLUGIN:ReaTune -->
<!-- SECTION-REVISION:ba2be4e0a1b9c5891810d574e85f730e75ffff6c283f18d532353617bf1d4dc2 -->
## ReaTune

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reatune","display_name":"ReaTune","vendor":"Cockos","product_class":"ordinary","preference_type":"pitch_correction","identifiers":{"add_by_name":["ReaTune"],"aliases":["tune","tuner","pitch correction"],"curated":["ReaTune"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reatune"],"context_required":["tune","tuner"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reatune","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaTune","loaded_name":"VST: ReaTune (Cockos)","parameter_count":{"mode":"exact","value":3},"required_parameters":[{"index":0,"name":"Bypass","section":"","section_required":false},{"index":1,"name":"Wet","section":"","section_required":false},{"index":2,"name":"Delta","section":"","section_required":false}],"observed_fingerprint_sha256":"cf4a891dffffbb856e151579b9e4c2be826c35af0f3b6c887830897dfb42fdcf"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"66df678f8152b5ea884c084d706d4780d571ebfc3f93ab49e764f728b6221282","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaTune"
Total params: 3 (indices 0-2)

NOTE: ReaTune's tuning/correction parameters are NOT exposed to the scripting API.
Only Bypass, Wet, and Delta are available. To use ReaTune, add it to the track and
instruct the user to configure correction speed and other settings in the plugin UI.

```
idx  Name        Default   Min    Max    Notes
---  ----------  -------   -----  -----  ----------------------------
0    Bypass      0.0       0.0    1.0    1=bypassed
1    Wet         1.0       0.0    1.0    1.0=fully wet
2    Delta       0.0       0.0    1.0    Delta monitoring toggle
```

---
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaTune -->

<!-- PLUGIN:ReaVerbate -->
<!-- SECTION-REVISION:bb9eafc4eefb54c86e3281d40aba2897e757df288417116930afbecc89f2abc6 -->
## ReaVerbate

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reaverbate","display_name":"ReaVerbate","vendor":"Cockos","product_class":"ordinary","preference_type":"reverb","identifiers":{"add_by_name":["ReaVerbate"],"aliases":["reverb","verb"],"curated":["ReaVerbate"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reaverbate"],"context_required":["reverb","verb"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reaverbate","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaVerbate","loaded_name":"VST: ReaVerbate (Cockos)","parameter_count":{"mode":"exact","value":11},"required_parameters":[{"index":0,"name":"Wet","section":"","section_required":true},{"index":1,"name":"Dry","section":"","section_required":true},{"index":2,"name":"Room size","section":"","section_required":true},{"index":3,"name":"Dampening","section":"","section_required":true},{"index":4,"name":"Width","section":"","section_required":true},{"index":5,"name":"Delay","section":"","section_required":true},{"index":6,"name":"Lowpass","section":"","section_required":true},{"index":7,"name":"Hipass","section":"","section_required":true}],"observed_fingerprint_sha256":"7dd690fb0aa873dd3042b1c216612edeac621d5c9400b6b225c97c6ce2361bc2"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"3aa4351eea79f3c6777b4f9a0e1e9f282b06aba09a3991d0e6ae39b2849643b6","verified_at":"2026-07-26","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
AddByName string: "ReaVerbate"
Total params: 11 (indices 0-10)

### PARAM INDEX TABLE (verified)

```
idx  Name        Default val   Min    Max    Notes
---  ----------  -----------   -----  -----  ----------------------------
0    Wet         0.5           0.0    2.0    Wet level: 0.5=-6dB
1    Dry         1.0           0.0    2.0    Dry level: 1.0=0dB
2    Room size   0.2941        0.0    1.0    Normalized (display: 50)
3    Dampening   0.5           0.0    1.0    HF damping (display: 50)
4    Width       1.0           0.0    1.0    Stereo width: 1.0=full
5    Delay       0.0           0.0    1.0    Pre-delay: 0=none
6    Lowpass     1.0           0.0    1.0    Filter normalized (20000Hz)
7    Hipass      0.0           0.0    1.0    Filter normalized (0Hz)
8    Bypass      0.0           0.0    1.0    1=bypassed
9    Wet         1.0           0.0    1.0    REAPER host wet control; leave unchanged
10   Delta       0.0           0.0    1.0    Delta monitoring toggle
```

### CONTROL AND MUSICAL GUIDANCE

Indices 0 and 9 are both named Wet and both have an empty section. Index 0 is
ReaVerbate's processed-signal level. Index 9 is REAPER's host wet control.
Resolve the effect Wet control with `{ index = 0, name = "Wet", section = "" }`.
The explicit empty section keeps the resolver on the fingerprint-validated
stored index. Never resolve it by name alone or use a bare index. Leave host Wet
at `100` unless the user explicitly asks for the host control.

For ReaVerbate inserted directly on a source track, keep Dry at `+0.0 dB` and
use effect Wet to set the ambience level. A useful restrained region is about
`-18 to -12 dB` Wet, Room size `30 to 45`, Dampening `60 to 80`, Delay `5 to
20`, Lowpass `8000 to 14000` and Hipass `80 to 200`. Higher Dampening removes
more high-frequency reverb energy. The filters apply to the reverberated
signal, so a moderate high-pass reduces low-frequency buildup and a moderate
low-pass keeps the tail behind the source.

On a dedicated reverb send or auxiliary track, use Dry off and Wet at unity.
Only change that routing balance when the user clearly identifies a send,
return or auxiliary track. Do not silently apply send routing to an insert.

Room size controls the perceived space. Delay is pre-delay: a little separation
can protect the source attack, while too much becomes a distinct echo. Width
`0.75 to 1.00` is a safe stereo starting region. Check mono when width matters.
Leave Bypass off and Delta off unless the user asks for those monitoring
controls.

Use the normalized anchors below only after the fingerprint validates. They are
version-specific control positions, so keep formatted-value readback after the
writes. A normalized value alone is not proof of the displayed result.

### NORMALIZED ANCHORS

```text
Control      Visible value   Normalized value
-----------  --------------  -------------------
Wet          -12.0           0.12607422471046448
Room size    40              0.140625
Dampening    70              0.703125
Width        0.80            0.8984375
Delay        15              0.029296875
Lowpass      12000           0.5999755859375
Hipass       150             0.00750732421875
Wet          -15.0           0.08891397050194615
Room size    35              0.07352941176470588
Width        0.85            0.925
Delay        8               0.016
Lowpass      9000            0.45
Hipass       120             0.006
```

### EXACT PRIMARY-CONTROL RECIPE

For `Wet -12.0 dB, Room size 40, Dampening 70, Width 0.80, Delay 15, Lowpass
12000 and Hipass 150` on an insert:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Wet", section = "" },
  { index = 2, name = "Room size", section = "" },
  { index = 3, name = "Dampening", section = "" },
  { index = 4, name = "Width", section = "" },
  { index = 5, name = "Delay", section = "" },
  { index = 6, name = "Lowpass", section = "" },
  { index = 7, name = "Hipass", section = "" },
})
if not mapped then error(guard_err) end

reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.12607422471046448)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.140625)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.703125)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.8984375)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.029296875)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.5999755859375)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.00750732421875)
```

Preserve Dry at `+0.0`, host Wet at `100`, Bypass at `normal` and Delta at
`normal`. The accepted visible values are the seven targets above.

For a request that adds ReaVerbate and applies this exact insert recipe,
perform the existence check, `TrackFX_AddByName`, parameter resolution and all
seven writes inside the same outer `reaper.defer()` and exactly one
`Undo_BeginBlock` / `Undo_EndBlock` pair. Begin the undo block before adding
ReaVerbate and end it only after all seven displays are verified. One Undo must
remove the new ReaVerbate instance and restore the original FX count. Do not
add a replacement instance if the requested add fails, and do not create or
change sends for this insert request.

### NATURAL SMALL-ROOM START

For a request such as `Give this a little believable room around it without
washing it out`, use this restrained insert starting point: Wet `-15.0`, Room
size `35`, Dampening `70`, Width `0.85`, Delay `8`, Lowpass `9000` and Hipass
`120`.

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Wet", section = "" },
  { index = 2, name = "Room size", section = "" },
  { index = 3, name = "Dampening", section = "" },
  { index = 4, name = "Width", section = "" },
  { index = 5, name = "Delay", section = "" },
  { index = 6, name = "Lowpass", section = "" },
  { index = 7, name = "Hipass", section = "" },
})
if not mapped then error(guard_err) end

reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.08891397050194615)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.07352941176470588)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.703125)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.925)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.016)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.45)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.006)
```

For that natural request, use exactly this seven-write recipe. Resolve the
existing ReaVerbate with `TrackFX_GetByName(..., false)` and fail closed if it
is missing. Never add a second ReaVerbate for an existing-instance request.
Change only effect Wet, Room size, Dampening, Width, Delay, Lowpass and Hipass.
Preserve Dry, host Wet, Bypass, Delta and every other control unless the user
names it. Do not create a send, alter routing or substitute a different room
recipe. The accepted displays are `-15.0`, `35`, `70`, `0.85`, `8`, `9000`
and `120`.

This starting point keeps the direct sound unchanged and places a darker,
filtered room underneath it. Adjust from there using the source and the mix.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaVerbate -->

<!-- PLUGIN:ReaXcomp -->
<!-- SECTION-REVISION:e09b241058376370577eb0be7947d6759914fd9384b500d5602bce91971b6796 -->
## ReaXcomp

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reaxcomp","display_name":"ReaXcomp","vendor":"Cockos","product_class":"ordinary","preference_type":"multiband_compressor","identifiers":{"add_by_name":["ReaXcomp"],"aliases":["multiband_compressor","multiband compressor","multiband comp","multi-band compressor","mbcomp"],"curated":["ReaXcomp"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":["reaxcomp"],"context_required":["mbcomp"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reaxcomp","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST","identifier":"ReaXcomp","loaded_name":"VST: ReaXcomp (Cockos)","parameter_count":{"mode":"exact","value":51},"required_parameters":[{"index":0,"name":"1-Band top frequency","section":"","section_required":true},{"index":11,"name":"1-Active","section":"","section_required":true},{"index":23,"name":"2-Active","section":"","section_required":true},{"index":35,"name":"3-Active","section":"","section_required":true},{"index":47,"name":"4-Active","section":"","section_required":true}],"observed_fingerprint_sha256":"73cea8b339e65ef0403f84936cb10aef67405a94ed524e42aeca7eefc694ea8a"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"6cf60931263d83d39b04c5addec8dfdf2ae5a0e815356274109d180b42931bfd","verified_at":"2026-07-26","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
REAPER's stock multiband compressor. The script-visible processing layout is
four bands, each with threshold, ratio, attack, release, knee, RMS, make-up
gain, and crossover top frequency. Use for multiband mastering, targeted
frequency ducking, or narrowband de-essing.

AddByName string: "ReaXcomp"
Total params (default instance): 51 (indices 0-50). Script-useful processing
params are indices 0-49; idx 50 is REAPER's Delta utility param.

### CRITICAL CONSTRAINTS

1. **4 script-visible processing bands.** Current REAPER exposes Bands 1-4 as
   a fixed 12-param stride; there is no band-count parameter in the script map.
   Use each band's `Active` param (offset +11) to bypass unused bands.

2. **Crossovers set by `N-Band top frequency`.** Band N covers from the top of
   band N-1 up to its own top freq. Band 4's top (default 24 kHz) is the
   overall upper limit.

3. **Gain and Threshold share the same dB scale** (-150..+12 dB, 0.5 = 0 dB).

4. **Attack and RMS share the same linear ms scale** (0..250 ms).

5. **All params use TrackFX_SetParamNormalized** (values 0..1). Do not use
   TrackFX_SetParam because the raw ranges vary by parameter.

6. **Use guarded Lua for mapped ReaXcomp edits.** The structured typed-action
   lane does not support ReaXcomp. Resolve every target through
   `reaassist_resolve_profile_params` before the first write. Do not use a bare
   index, a computed band stride, or a loop over `base + offset` in generated
   code. The fingerprint and resolver must prove all concrete band targets.

7. **Gain reduction is signal-dependent.** A stored Threshold cannot guarantee
   a requested amount of reduction. Ratio, knee and timing can define a safe
   starting character, but Threshold must be checked against each band's meter
   during playback. Never claim that a static recipe achieved 1 dB of gain
   reduction without meter or audio evidence.

### BAND LAYOUT

4 bands × 12 params = 48 band params, plus 3 utility/global params
(Bypass, Wet, Delta).

```
Formula: base = (N - 1) * 12

Offset  Name                    Type        Scale
------  ----------------------  ----------  -------------------------
+0      N-Band top frequency    continuous  Freq (log-like, see below)
+1      N-Gain                  continuous  dB (see Gain/Threshold scale)
+2      N-Threshold             continuous  dB (see Gain/Threshold scale)
+3      N-Ratio                 continuous  0.10..100.0 (see Ratio scale)
+4      N-Knee                  continuous  dB 0..24 (see Knee scale)
+5      N-Attack                continuous  ms 0..250 linear
+6      N-Release               continuous  ms 0..2000 (see Release scale)
+7      N-RMS                   continuous  ms 0..250 linear
+8      N-Make Up Gain          toggle      0=OFF, 1=ON
+9      N-Auto Release          toggle      0=OFF, 1=ON
+10     N-FeedBack Detector     toggle      0=OFF, 1=ON
+11     N-Active                toggle      0=OFF, 1=ON

Band 1: indices 0-11
Band 2: indices 12-23
Band 3: indices 24-35
Band 4: indices 36-47
```

### GLOBAL PARAMS

```
idx  Name    Default  Notes
---  ------  -------  ---------------------------------
48   Bypass  0        1 = bypassed
49   Wet     1.0      Wet mix. 1 = full wet, 0 = dry only.
50   Delta   0        REAPER utility audition mode; leave at default.
```

### DEFAULTS PER BAND

All bands default to: Gain=0dB, Threshold=0dB, Ratio=2:1, Knee=0dB,
Attack=15ms, Release=150ms, RMS=5ms, Make Up Gain=ON, Auto Release=OFF,
FeedBack Detector=OFF, Active=ON.

Default crossover frequencies:

```
Band 1 top: 200 Hz    (slider 0.231)   -- sub / low bass
Band 2 top: 1000 Hz   (slider 0.476)   -- low-mid / body
Band 3 top: 5000 Hz   (slider 0.739)   -- high-mid / presence
Band 4 top: 24000 Hz  (slider 1.000)   -- air / upper limit
```

### BAND TOP FREQUENCY SCALE (log-like, 20 Hz..24000 Hz)

```
slider   Hz          slider   Hz          slider   Hz
-------  --------    -------  --------    -------  --------
0.00     20.0        0.35     448.6       0.70     3941.0
0.05     40.9        0.40     619.3       0.75     5332.2
0.10     69.2        0.45     849.7       0.80     7209.5
0.15     107.4       0.50     1160.5      0.85     9742.8
0.20     158.9       0.55     1580.1      0.90     13161.4
0.25     228.3       0.60     2146.2      0.95     17774.7
0.30     322.1       0.65     2910.1      1.00     24000.0
```

Common target frequencies (interpolated):

```
100 Hz  ~ 0.140     500 Hz  ~ 0.365     2 kHz   ~ 0.587
200 Hz  ~ 0.231     800 Hz  ~ 0.439     5 kHz   ~ 0.739
250 Hz  ~ 0.272     1 kHz   ~ 0.476     10 kHz  ~ 0.854
```

### GAIN / THRESHOLD SCALE (shared, -150..+12 dB)

Both per-band Gain (offset +1) and Threshold (offset +2) use this scale.
0.5 = 0 dB is neutral; 0 collapses to -150 dB (silence).

```
slider   dB          slider   dB          slider   dB
-------  ------      -------  ------      -------  ------
0.00     -150.0      0.35     -3.1        0.70     6.8
0.05     -20.0       0.40     -1.9        0.75     8.0
0.10     -14.0       0.45     -0.9        0.80     8.9
0.15     -10.5       0.50     0.0         0.85     9.8
0.20     -8.0        0.55     2.3         0.90     10.6
0.25     -6.0        0.60     4.1         0.95     11.4
0.30     -4.4        0.65     5.6         1.00     12.0
```

CRITICAL: 0.5 = 0 dB (unity / neutral). Slider 0 is -150 dB (silence) with a
huge jump to -20 dB at 0.05 -- avoid slider values below 0.05 unless silencing
is intended.

### RATIO SCALE (0.10..100.0)

Values < 1 are upward expansion; values > 1 are compression.

```
slider   ratio       slider   ratio       slider   ratio
-------  -------     -------  -------     -------  -------
0.00     0.10        0.35     2.76        0.70     36.64
0.05     0.28        0.40     4.96        0.75     45.00
0.10     0.46        0.45     8.04        0.80     54.24
0.15     0.64        0.50     12.00       0.85     64.36
0.20     0.82        0.55     16.84       0.90     75.36
0.25     1.00        0.60     22.56       0.95     87.24
0.30     1.44        0.65     29.16       1.00     100.00
```

Key points: 0.25 = 1:1 (no compression), 0.325 = 2:1 (default), 0.5 = 12:1
(heavy), 1.0 = 100:1 (near brick-wall). Between 1:1 and 12:1, the verified
curve follows `ratio = 1 + 176 * (slider - 0.25)^2`. Useful targets:

```
1.1:1  ~ 0.27384   1.2:1 ~ 0.28371   1.5:1  ~ 0.30330
2:1    ~ 0.32538   4:1   ~ 0.38056   10:1   ~ 0.47613
6:1    ~ 0.41855   8:1   ~ 0.44944   20:1   ~ 0.57855
```

### KNEE SCALE (0..24 dB)

Piecewise: slider 0..0.5 linear to 0..6 dB; slider 0.5..1 linear to 6..24 dB.

```
if dB <= 6:  slider = dB / 12
if dB > 6:   slider = 0.5 + ((dB - 6) / 36)

0 dB = 0.000    3 dB = 0.250    6 dB = 0.500
12 dB = 0.667   18 dB = 0.833   24 dB = 1.000
```

### ATTACK / RMS SCALE (shared, 0..250 ms linear)

Attack (offset +5) and RMS (offset +7) share a simple linear scale.

```
Formula: slider = ms / 250.

5 ms = 0.020    15 ms = 0.060 *    50 ms = 0.200
100 ms = 0.400  150 ms = 0.600     250 ms = 1.000
```

Defaults: Attack=15 ms (slider 0.060), RMS=5 ms (0.020).

### RELEASE SCALE (0..2000 ms, parabolic)

Quadratic taper -- more resolution at short release times.

```
Formula: ms = 2000 * slider^2. Slider = sqrt(ms / 2000).

20 ms = 0.100    50 ms = 0.158    100 ms = 0.224
150 ms = 0.274 * 250 ms = 0.354    500 ms = 0.500
1 sec = 0.707    2 sec = 1.000
```

Default 150 ms = slider ~0.274.

For the current verified ReaXcomp build, use the canonicalized direct anchors
`0.200 = 80 ms`, `0.224 = 100 ms`, `0.245 = 120 ms`, `0.300 = 180 ms` and
`0.354 = 250 ms`. The plug-in resolves the surrounding mathematical values to
adjacent integer displays, so use these observed anchors for exact targets.

### EXACT FOUR-BAND CONTROL RECIPE

For all four bands at Threshold `-0.9 dB`, Ratio `1.10:1`, Attack `10 ms`,
Release `100 ms`, Make Up Gain on and Active on:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 2, name = "1-Threshold", section = "" },
  { index = 3, name = "1-Ratio", section = "" },
  { index = 5, name = "1-Attack", section = "" },
  { index = 6, name = "1-Release", section = "" },
  { index = 8, name = "1-Make Up Gain", section = "" },
  { index = 11, name = "1-Active", section = "" },
  { index = 14, name = "2-Threshold", section = "" },
  { index = 15, name = "2-Ratio", section = "" },
  { index = 17, name = "2-Attack", section = "" },
  { index = 18, name = "2-Release", section = "" },
  { index = 20, name = "2-Make Up Gain", section = "" },
  { index = 23, name = "2-Active", section = "" },
  { index = 26, name = "3-Threshold", section = "" },
  { index = 27, name = "3-Ratio", section = "" },
  { index = 29, name = "3-Attack", section = "" },
  { index = 30, name = "3-Release", section = "" },
  { index = 32, name = "3-Make Up Gain", section = "" },
  { index = 35, name = "3-Active", section = "" },
  { index = 38, name = "4-Threshold", section = "" },
  { index = 39, name = "4-Ratio", section = "" },
  { index = 41, name = "4-Attack", section = "" },
  { index = 42, name = "4-Release", section = "" },
  { index = 44, name = "4-Make Up Gain", section = "" },
  { index = 47, name = "4-Active", section = "" },
})
if not mapped then error(guard_err) end

reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.45)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.27383656473114)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.04)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.224)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.45)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.27383656473114)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.04)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.224)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 0.45)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[14], 0.27383656473114)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[15], 0.04)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[16], 0.224)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[17], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[18], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[19], 0.45)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[20], 0.27383656473114)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[21], 0.04)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[22], 0.224)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[23], 1.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[24], 1.0)
```

The accepted visible values for every band are Threshold `-0.9`, Ratio `1.10`,
Attack `10`, Release `100`, Make Up Gain `ON` and Active `ON`. Preserve Gain,
Knee, RMS, Auto Release, FeedBack Detector, all crossovers and all host controls.

For a request that adds ReaXcomp and applies this exact four-band recipe,
perform the existence check, `TrackFX_AddByName`, one literal 24-entry resolver
call and all 24 writes inside the same outer `reaper.defer()` and exactly one
`Undo_BeginBlock` / `Undo_EndBlock` pair. Begin the undo block before adding
ReaXcomp and end it only after every accepted display is verified. One Undo
must remove the new ReaXcomp instance and restore the original FX count. Do not
add a replacement instance if the requested add fails. Do not compress this
recipe into computed indices, a stride loop or an incomplete subset of bands.

### NATURAL TRANSPARENT-GLUE START

For a conservative four-band mastering start, preserve the default crossovers,
keep all four bands active, turn Make Up Gain off, and use Threshold `-12.0 dB`,
Ratio `1.20:1` and Knee `6.00 dB` on each band. Use slower low-band timing and
progressively faster timing toward the high band:

```text
Band   Attack   Release
----   ------   -------
1      30 ms    250 ms
2      20 ms    180 ms
3      10 ms    120 ms
4       5 ms     80 ms
```

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 2, name = "1-Threshold", section = "" },
  { index = 3, name = "1-Ratio", section = "" },
  { index = 4, name = "1-Knee", section = "" },
  { index = 5, name = "1-Attack", section = "" },
  { index = 6, name = "1-Release", section = "" },
  { index = 8, name = "1-Make Up Gain", section = "" },
  { index = 14, name = "2-Threshold", section = "" },
  { index = 15, name = "2-Ratio", section = "" },
  { index = 16, name = "2-Knee", section = "" },
  { index = 17, name = "2-Attack", section = "" },
  { index = 18, name = "2-Release", section = "" },
  { index = 20, name = "2-Make Up Gain", section = "" },
  { index = 26, name = "3-Threshold", section = "" },
  { index = 27, name = "3-Ratio", section = "" },
  { index = 28, name = "3-Knee", section = "" },
  { index = 29, name = "3-Attack", section = "" },
  { index = 30, name = "3-Release", section = "" },
  { index = 32, name = "3-Make Up Gain", section = "" },
  { index = 38, name = "4-Threshold", section = "" },
  { index = 39, name = "4-Ratio", section = "" },
  { index = 40, name = "4-Knee", section = "" },
  { index = 41, name = "4-Attack", section = "" },
  { index = 42, name = "4-Release", section = "" },
  { index = 44, name = "4-Make Up Gain", section = "" },
})
if not mapped then error(guard_err) end

reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.125594321575479)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.283709993123162)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.5)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.12)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.354)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.125594321575479)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.283709993123162)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.5)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.08)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.3)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 0.125594321575479)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[14], 0.283709993123162)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[15], 0.5)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[16], 0.04)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[17], 0.245)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[18], 0.0)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[19], 0.125594321575479)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[20], 0.283709993123162)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[21], 0.5)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[22], 0.02)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[23], 0.2)
reaper.TrackFX_SetParamNormalized(tr, fx, mapped[24], 0.0)
```

For the natural request to give an existing ReaXcomp conservative transparent
four-band glue without changing the tonal balance, use exactly this 24-write
recipe. Resolve the existing ReaXcomp with `TrackFX_GetByName(..., false)` and
fail closed if it is missing. Never add a second ReaXcomp for an
existing-instance request. Change only each band's Threshold, Ratio, Knee,
Attack, Release and Make Up Gain. Preserve all crossover frequencies, Gain,
RMS, Auto Release, FeedBack Detector, Active state, Bypass, Wet, Delta and every
other control unless the user names it. Do not substitute another timing plan,
change thresholds from the documented starting point or claim measured gain
reduction without meter evidence. Keep the resolver and writes literal for all
four bands.

This low-ratio, soft-knee start limits how hard each band can work and avoids
automatic level compensation changing the tonal balance. During playback,
adjust each Threshold separately until its meter shows only the desired modest
reduction. If a band is already balanced, leave its Threshold higher rather
than forcing it to compress. Level-match the result before deciding it sounds
better.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReaXcomp -->

<!-- PLUGIN:ReEQ -->
<!-- SECTION-REVISION:ceae87a2bfc5aa454686bcadb1c9ee69c013e16b8710547db77075f577cd0221 -->
## ReEQ

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"reeq","display_name":"ReEQ","vendor":"ReJJ","product_class":"dynamic","preference_type":"eq","identifiers":{"add_by_name":["ReJJ/ReEQ/ReEQ.jsfx","JS: ReJJ/ReEQ/ReEQ.jsfx","ReEQ - Parametric Graphic Equalizer","JS: ReEQ - Parametric Graphic Equalizer"],"aliases":[],"curated":["ReJJ/ReEQ/ReEQ.jsfx","JS: ReJJ/ReEQ/ReEQ.jsfx","ReEQ - Parametric Graphic Equalizer","JS: ReEQ - Parametric Graphic Equalizer"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["reeq"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"reeq","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"JSFX","identifier":"JS: ReJJ/ReEQ/ReEQ.jsfx","loaded_name":"JS: ReEQ - Parametric Graphic Equalizer","parameter_count":{"mode":"exact","value":60},"required_parameters":[{"index":0,"name":"Stereo Mode","section":"","section_required":false},{"index":14,"name":"Show Peaks","section":"","section_required":false},{"index":28,"name":"Filter2 Gain","section":"","section_required":false},{"index":42,"name":"Filter4 Gain","section":"","section_required":false},{"index":56,"name":"Panel Enabled","section":"","section_required":false}],"observed_fingerprint_sha256":"ce6e1f4dfd0ee372c10e611f7bc54029d933cb31212841154dd5d08e2fc6d655"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"6b35a3f47621eaaa999016938c938d3164104a6ca75bcf577d7e900bb620a33b","verified_at":"2026-07-26","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
Third-party JSFX EQ by Justin Johnson, version 1.2.0, under the MIT license.
ReaAssist ships a bundled copy and can install it when no preferred EQ is
available. ReEQ offers five script-visible bands with selectable 6 to 96
dB/oct cut slopes. It is especially useful for deliberate high-pass and
low-pass work.

Preferred AddByName identifier: `ReJJ/ReEQ/ReEQ.jsfx`

Observed loaded name: `JS: ReEQ - Parametric Graphic Equalizer`

Observed parameter count: 60, consisting of 57 JSFX sliders plus REAPER's
Bypass, Wet and Delta controls.

### CRITICAL CONTROL RULES

1. Use `TrackFX_SetParam` with ReEQ's native slider values. Do not use
   `TrackFX_SetParamNormalized` for the mapped ReEQ controls below.

2. Resolve every target through `reaassist_resolve_profile_params` before the
   first write. Every resolver entry must use one concrete index and the exact
   live parameter name from the tables below. Never write a bare index, derive
   an index with `base + offset`, or put unresolved indices into a loop.

3. Only bands 1 through 5 are exposed as parameters. Bands 6 through 16 can be
   edited only in ReEQ's own interface. Explain that limitation when a user
   asks ReaAssist to control more than five bands.

4. A fresh band's Mode is `Off`. Set Mode to native value `2` (`Enabled`) for
   an audible band. Value `1` is `Disabled`, which preserves the band while
   bypassing it.

5. Filter Type accepts values 0 through 10. The interface also lists All Pass,
   Low Cut Analog and High Cut Analog, but the exposed slider clamps before
   those choices. Do not claim that script control reached types 11 through 13.

6. Filter Group accepts native values 0 through 2: Stereo, Mid and Side. The
   JSFX text also lists Left and Right, but its exposed slider clamps at 2.
   Do not claim that script control reached Left or Right.

7. REAPER's formatted readback exposes ReEQ's native Frequency, Q and Slope
   slider numbers. It does not display their musical units. For example, the
   certified 80 Hz and 48 dB/oct settings read back as Frequency `27.01` and
   Slope `7.0`. Convert with the formulas below and confirm the semantic result
   in ReEQ's own interface when exact musical units matter.

### EXACT BAND PARAMETER MAP

Use these exact names in resolver entries.

```text
Band  Index  Exact live name      Meaning
----  -----  -------------------  ---------------------------------------
1     17     Filter1 Mode         0 Off, 1 Disabled, 2 Enabled
1     18     Filter1 Group        0 Stereo, 1 Mid, 2 Side
1     19     Filter1 Type         Filter type 0 through 10
1     20     Filter1 Frequency    Raw logarithmic position 0 through 100
1     21     Filter1 Gain         Direct dB, -18 through +18
1     22     Filter1 Q            Raw logarithmic position 0 through 100
1     23     Filter1 Slope        0 through 15
2     24     Filter2 Mode         0 Off, 1 Disabled, 2 Enabled
2     25     Filter2 Group        0 Stereo, 1 Mid, 2 Side
2     26     Filter2 Type         Filter type 0 through 10
2     27     Filter2 Frequency    Raw logarithmic position 0 through 100
2     28     Filter2 Gain         Direct dB, -18 through +18
2     29     Filter2 Q            Raw logarithmic position 0 through 100
2     30     Filter2 Slope        0 through 15
3     31     Filter3 Mode         0 Off, 1 Disabled, 2 Enabled
3     32     Filter3 Group        0 Stereo, 1 Mid, 2 Side
3     33     Filter3 Type         Filter type 0 through 10
3     34     Filter3 Frequency    Raw logarithmic position 0 through 100
3     35     Filter3 Gain         Direct dB, -18 through +18
3     36     Filter3 Q            Raw logarithmic position 0 through 100
3     37     Filter3 Slope        0 through 15
4     38     Filter4 Mode         0 Off, 1 Disabled, 2 Enabled
4     39     Filter4 Group        0 Stereo, 1 Mid, 2 Side
4     40     Filter4 Type         Filter type 0 through 10
4     41     Filter4 Frequency    Raw logarithmic position 0 through 100
4     42     Filter4 Gain         Direct dB, -18 through +18
4     43     Filter4 Q            Raw logarithmic position 0 through 100
4     44     Filter4 Slope        0 through 15
5     45     Filter5 Mode         0 Off, 1 Disabled, 2 Enabled
5     46     Filter5 Group        0 Stereo, 1 Mid, 2 Side
5     47     Filter5 Type         Filter type 0 through 10
5     48     Filter5 Frequency    Raw logarithmic position 0 through 100
5     49     Filter5 Gain         Direct dB, -18 through +18
5     50     Filter5 Q            Raw logarithmic position 0 through 100
5     51     Filter5 Slope        0 through 15
```

### FILTER TYPES

```text
Value  Type                    Musical use
-----  ----------------------  ------------------------------------------
0      Peak                    Bell boost or cut using Gain and Q
1      Low Cut                 Resonant high-pass using Q and Slope
2      Low Cut (Butterworth)   Flat-passband high-pass using Slope
3      Low Shelf               Broad low-frequency boost or cut
4      High Shelf              Broad high-frequency boost or cut
5      High Cut                Resonant low-pass using Q and Slope
6      High Cut (Butterworth)  Flat-passband low-pass using Slope
7      Notch                   Narrow rejection using Q
8      Band Pass               Isolated range using Q
9      Tilt Shelf              Opposing low and high tonal balance
10     Pultec Low Shelf        Broad Pultec-style low shelf
```

Peak, Shelf, Tilt and Pultec types use Gain. Peak, Shelf, Notch and Band Pass
use Q for shape or width. The Butterworth cut types ignore the stored Gain and
Q values. Slope affects the four cut types only.

### FREQUENCY CONVERSION

The exposed Frequency slider is logarithmic from 10 Hz through 22050 Hz.
Compute the native value, round it to the slider's 0.01 step, write that value,
then verify the result. Use `ln(2205) = 7.6984827878809465`.

```text
native = 100 * ln(target_hz / 10) / 7.6984827878809465
hz     = 10 * exp(7.6984827878809465 * native / 100)
```

Clamp target frequency to 10 through 22050 Hz. Certified anchors:

```text
Target     Native      Target     Native      Target     Native
---------  ----------  ---------  ----------  ---------  ----------
20 Hz      9.00        250 Hz     41.81       2 kHz      68.82
50 Hz      20.91       300 Hz     44.18       5 kHz      80.73
80 Hz      27.01       500 Hz     50.82       10 kHz     89.73
100 Hz     29.91       1 kHz      59.82       12 kHz     92.10
15 kHz     95.00       16 kHz     95.83       20 kHz     98.73
```

`27.00` is about 79.9 Hz in ReEQ's interface. Use `27.01` for the certified
visible 80.0 Hz result.

### Q CONVERSION

The exposed Q slider is logarithmic from Q 0.1 through 40. Compute the native
value, round it to the slider step, write that value, then verify the result.
Use `ln(400) = 5.991464547107982`.

```text
native = 100 * ln(target_q / 0.1) / 5.991464547107982
q      = 0.1 * exp(5.991464547107982 * native / 100)
```

Useful anchors: Q 0.5 = 26.86, Q 0.707 = 32.65, Q 1.0 = 38.43,
Q 2.0 = 50.00, Q 4.0 = 61.58 and Q 10.0 = 76.86.

### SLOPE CONVERSION

For Low Cut, Low Cut (Butterworth), High Cut and High Cut (Butterworth):

```text
native_slope = requested_dB_per_octave / 6 - 1

Native  Slope      Native  Slope      Native  Slope      Native  Slope
------  ---------  ------  ---------  ------  ---------  ------  ---------
0       6 dB/oct   4       30 dB/oct  8       54 dB/oct  12      78 dB/oct
1       12 dB/oct  5       36 dB/oct  9       60 dB/oct  13      84 dB/oct
2       18 dB/oct  6       42 dB/oct  10      66 dB/oct  14      90 dB/oct
3       24 dB/oct  7       48 dB/oct  11      72 dB/oct  15      96 dB/oct
```

ReEQ supports only these 6 dB increments. If the user gives another value,
ask for a supported slope or state the nearest value before applying it.

### GLOBAL AND HOST CONTROLS

Resolve any requested global or host control by its concrete index and exact
name. Preserve these controls for ordinary band edits.

```text
Index  Exact live name   Native range and use
-----  ----------------  -----------------------------------------------
0      Stereo Mode       0 Mid/Side, 1 Left/Right operating mode
1      Quality           0 Eco, 1 HQ
2      Gain              Master output gain, -136 through +30 dB
3      Mid/Left Gain     Channel gain, -136 through +30 dB
4      Side/Right Gain   Channel gain, -136 through +30 dB
5      Scale             Interface scale, 0 through 200
6      Spectrum          Analyzer source, 0 through 5
7      Display           Analyzer display style, 0 through 2
8      Ceiling           Analyzer ceiling, 0 through 2
9      Floor             Analyzer floor, 0 through 2
10     Tilt              Analyzer tilt compensation, 0 through 5
11     Type              Analyzer window function, 0 through 3
12     Block Size        Analyzer FFT size, 0 through 3
13     Show Piano        Interface toggle
14     Show Peaks        Interface toggle
15     Show Pre-EQ       Interface toggle
16     dB Range          Interface range, 0 through 4
52     Mid Polarity      Polarity toggle
53     Side Polarity     Polarity toggle
54     Limit Output      Output limiter toggle
55     AGC Enabled       Automatic gain compensation toggle
56     Panel Enabled     ReEQ detail-panel toggle
57     Bypass            REAPER host bypass
58     Wet               REAPER host wet mix
59     Delta             REAPER host delta audition
```

Leave Quality at HQ, master and channel gains at 0.0 dB, Limit Output off, AGC
off, Bypass normal, host Wet at 100 and Delta normal unless the user requests a
different setting. Analyzer and interface controls do not change the EQ curve.

### MUSICAL DEFAULTS

When a user asks for a low cut, high-pass filter or rumble removal without a
filter family, use Low Cut (Butterworth). A 48 dB/oct slope cleanly removes
subsonic energy while keeping the transition close to the requested cutoff.
Choose the cutoff from the source and the musical intent. Around 60 to 80 Hz
can suit speech, guitar or a non-bass source. Bass instruments and kick drums
usually need a lower cutoff chosen while listening. Do not assume 80 Hz for a
bass-focused source.

When a user asks for a high cut or low-pass filter without a family, use High
Cut (Butterworth). Choose the cutoff from the source and the mix. Avoid removing
audible brightness merely because a generic recipe suggests it.

For broad tonal changes, begin with about 1 to 3 dB and a broad Q. For a
resonance or narrow problem, use a narrower Q and audition in context. Static
EQ cannot prove that a frequency is problematic without audio or spectrum
evidence. Describe profile recipes as safe starting points.

### CERTIFIED 80 HZ RUMBLE-REMOVAL RECIPE

For Band 1 enabled as a Butterworth low cut at 80 Hz and 48 dB/oct, preserve
every other parameter and use this exact guarded write block:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 17, name = "Filter1 Mode", section = "" },
  { index = 19, name = "Filter1 Type", section = "" },
  { index = 20, name = "Filter1 Frequency", section = "" },
  { index = 23, name = "Filter1 Slope", section = "" },
})
if not mapped then error(guard_err) end

reaper.TrackFX_SetParam(tr, fx, mapped[1], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 27.01)
reaper.TrackFX_SetParam(tr, fx, mapped[4], 7)
```

The REAPER readback contract is `Enabled`, `Low Cut (Butterworth)`, `27.01`
and `7.0`. ReEQ's native point detail must show `80.0 Hz` and `S: 48 dB` for
semantic visual confirmation. Keep Bands 2 through 5 at `Off` for a fresh
single-band request.

For a request that adds ReEQ and applies this certified recipe, perform the
existence check, `TrackFX_AddByName`, parameter resolution and all four writes
inside the same outer `reaper.defer()` and exactly one `Undo_BeginBlock` /
`Undo_EndBlock` pair. Begin the undo block before adding ReEQ and end it only
after all four readbacks are verified. One Undo must remove the new ReEQ
instance and restore the original FX count. Do not add a replacement instance
if the requested add fails.

For the natural request to use an existing ReEQ to remove low rumble cleanly
while leaving the musical low end and everything else alone, use exactly the
same four-write 80 Hz Butterworth recipe. Resolve the existing ReEQ with
`TrackFX_GetByName(..., false)` and fail closed if it is missing. Never add a
second ReEQ for this existing-instance request. Wrap the four writes in exactly
one `Undo_BeginBlock` / `Undo_EndBlock` pair so one Undo restores the prior
curve.

Change only Filter1 Mode, Type, Frequency and Slope. Preserve Filter1 Group,
Gain and Q, Bands 2 through 5, every global/analyzer/interface control, Bypass,
Wet, Delta and every other control unless the user names it. Do not substitute
another cutoff, slope or extra EQ band.

### GUARDED COMMON RECIPES

For a 10 kHz, 48 dB/oct Butterworth high cut on Band 5:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 45, name = "Filter5 Mode", section = "" },
  { index = 47, name = "Filter5 Type", section = "" },
  { index = 48, name = "Filter5 Frequency", section = "" },
  { index = 51, name = "Filter5 Slope", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 6)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 89.73)
reaper.TrackFX_SetParam(tr, fx, mapped[4], 7)
```

For a 300 Hz, -3.0 dB, Q 2.0 peak cut on Band 2:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 24, name = "Filter2 Mode", section = "" },
  { index = 26, name = "Filter2 Type", section = "" },
  { index = 27, name = "Filter2 Frequency", section = "" },
  { index = 28, name = "Filter2 Gain", section = "" },
  { index = 29, name = "Filter2 Q", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 0)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 44.18)
reaper.TrackFX_SetParam(tr, fx, mapped[4], -3.0)
reaper.TrackFX_SetParam(tr, fx, mapped[5], 50.00)
```

For a 12 kHz, +3.0 dB, Q 0.707 high shelf on Band 4:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 38, name = "Filter4 Mode", section = "" },
  { index = 40, name = "Filter4 Type", section = "" },
  { index = 41, name = "Filter4 Frequency", section = "" },
  { index = 42, name = "Filter4 Gain", section = "" },
  { index = 43, name = "Filter4 Q", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 4)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 92.10)
reaper.TrackFX_SetParam(tr, fx, mapped[4], 3.0)
reaper.TrackFX_SetParam(tr, fx, mapped[5], 32.65)
```

For a 200 Hz, +2.5 dB, Q 0.707 low shelf on Band 1:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 17, name = "Filter1 Mode", section = "" },
  { index = 19, name = "Filter1 Type", section = "" },
  { index = 20, name = "Filter1 Frequency", section = "" },
  { index = 21, name = "Filter1 Gain", section = "" },
  { index = 22, name = "Filter1 Q", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 2)
reaper.TrackFX_SetParam(tr, fx, mapped[2], 3)
reaper.TrackFX_SetParam(tr, fx, mapped[3], 38.91)
reaper.TrackFX_SetParam(tr, fx, mapped[4], 2.5)
reaper.TrackFX_SetParam(tr, fx, mapped[5], 32.65)
```

When a request needs several bands, create one resolver table containing every
concrete target from every affected band, verify the entire table, then perform
the writes through the returned `mapped[N]` indices. Preserve all unrelated
bands and global controls.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:ReEQ -->

<!-- PLUGIN:Saturation -->
<!-- SECTION-REVISION:755f61b2cb1b6e437d0e2f4e51b00fd82e8c5dc508e27163172d312a0a16e95e -->
## Saturation

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"saturation","display_name":"Saturation","vendor":"Cockos","product_class":"ordinary","preference_type":"saturation","identifiers":{"add_by_name":["JS: LOSER/Saturation"],"aliases":["saturator","loser/saturation","JS: LOSER/Saturation"],"curated":[]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["saturation","saturator"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"saturation","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"JSFX","identifier":"JS: LOSER/Saturation","loaded_name":"JS: Saturation","parameter_count":{"mode":"exact","value":4},"required_parameters":[{"index":0,"name":"Amount (%)","section":"","section_required":false}],"observed_fingerprint_sha256":"b0f7effc94570c897c7b7b35750d5eb9b3ef3ba38ec27cf042232c02df2f17b6"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"6a6e3a0f65e4e1024bc110482a16b8754587c6e18effdf2e28aaed8e95b3f8c9","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
Stock JSFX by LOSER. Simple single-knob saturation (tape/tube-ish soft clipping).
Bundled with REAPER; available in all installs.

AddByName string: "JS: LOSER/Saturation"  (also accepts "LOSER/Saturation")
Total params: 4 (1 slider + Bypass/Wet/Delta meta)

### PARAM INDEX TABLE (verified from JSFX source)

```
idx  Name         Default   Min    Max    Notes
---  -----------  --------  -----  -----  ----------------------------
0    Amount (%)   0         0      100    Saturation percentage (display value)
1    Bypass       0.0       0.0    1.0    1=bypassed (meta)
2    Wet          1.0       0.0    1.0    Wet level (meta)
3    Delta        0.0       0.0    1.0    Delta monitoring (meta)
```

### VALUE SEMANTICS

Amount is the raw percentage passed to `TrackFX_SetParam`:

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 35)     -- 35% saturation
```

### COMMON RECIPES

- **Subtle warmth:**     `TrackFX_SetParam(tr, fx, 0, 15)`   -- 15%
- **Medium grit:**       `TrackFX_SetParam(tr, fx, 0, 40)`   -- 40%
- **Heavy saturation:**  `TrackFX_SetParam(tr, fx, 0, 70)`   -- 70%

### CONTROL AND MUSICAL GUIDANCE

Amount is an integer percentage from `0` through `100`. Use
`TrackFX_SetParam`, which accepts that raw slider value for this JSFX. Do not
pass the percentage to `TrackFX_SetParamNormalized`. Moderate settings add
harmonic density while leaving more of the original transient shape. Higher
settings flatten peaks more strongly and can become obvious distortion.

### EXACT 40 PERCENT RECIPE

For `Add Saturation to the selected track and set Amount to 40%`, add exactly
one `JS: LOSER/Saturation` instance and use exactly this one-write recipe:

```lua
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Amount (%)", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 40)
```

The accepted Amount display is `40`. Preserve Bypass at `normal`, host Wet at
`100` and Delta at `normal`.

Perform the existence check, `TrackFX_AddByName`, parameter resolution and
write inside the same outer `reaper.defer()` and exactly one
`Undo_BeginBlock` / `Undo_EndBlock` pair. Begin the undo block before adding
Saturation and end it only after the `40` display is verified. One Undo must
remove the new Saturation instance and restore the original FX count. Do not
add a second instance if the requested add fails.

### NATURAL SUBTLE-WARMTH START

For the natural request `Give the existing Saturation a little warm harmonic
color without making it sound obviously distorted`, use exactly this
one-write `18%` recipe:

This is an edit request. Locating the effect, describing its current state or
reporting that it exists does not satisfy the request. The runnable response
must resolve Amount and execute the raw-value setter below. Do not stop after
`TrackFX_GetByName`.

```lua
local fx = reaper.TrackFX_GetByName(tr, "JS: Saturation", false)
if fx < 0 then error("Existing Saturation instance not found") end
local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
  { index = 0, name = "Amount (%)", section = "" },
})
if not mapped then error(guard_err) end
reaper.TrackFX_SetParam(tr, fx, mapped[1], 18)
```

Resolve the existing instance with
`TrackFX_GetByName(tr, "JS: Saturation", false)` and fail closed if it is
missing. The loaded-name query avoids colliding with other installed effects
whose names contain Saturation. Never add another instance for this
existing-instance request. Change only Amount. Preserve Bypass, host Wet, Delta and every other
track or project setting unless the user names it. Do not change gain, routing
or any other effect. The accepted Amount display is `18`.

A lookup-only script or a success message that does not execute
`TrackFX_SetParam(tr, fx, mapped[1], 18)` is a failed response.

Wrap the lookup, resolution and one write in the same outer `reaper.defer()`
and exactly one `Undo_BeginBlock` / `Undo_EndBlock` pair. One Undo must restore
the previous Amount value without removing the existing instance.

---
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->

<!-- /CHUNK:musical -->
<!-- /PLUGIN:Saturation -->

<!-- PLUGIN:Crystallizer -->
<!-- SECTION-REVISION:36c2dd3897f3e1495e2d568154413c17e022b030d3ee0831b73f22be940d60d7 -->
## Crystallizer

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-crystallizer","display_name":"Crystallizer","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys crystallizer","identifiers":{"add_by_name":["VST3: Crystallizer","VST3: Crystallizer (Soundtoys)"],"aliases":["crystallizer","soundtoys crystallizer","VST3: Crystallizer","VST3: Crystallizer (Soundtoys)"],"curated":["Crystallizer"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["crystallizer"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-crystallizer","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[5],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Crystallizer","loaded_name":"VST3: Crystallizer (Soundtoys)","parameter_count":{"mode":"exact","value":27},"required_parameters":[{"index":3,"name":"Mix","section":"","section_required":false},{"index":5,"name":"Regenerate","section":"","section_required":false},{"index":10,"name":"SyncMode","section":"","section_required":false},{"index":14,"name":"Pitch","section":"","section_required":false},{"index":16,"name":"SpliceValue","section":"","section_required":false},{"index":18,"name":"DelayValue","section":"","section_required":false}],"observed_fingerprint_sha256":"07059f7424388071c8c1958c5c4bf1b55ee1769d0d1ad706db399081169f1dab"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/Crystallizer-Manual.pdf","document_title":"Crystallizer User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"07059f7424388071c8c1958c5c4bf1b55ee1769d0d1ad706db399081169f1dab","body_sha256":"51f93c49134d394c537c601bfa9689ea3d5a5c8fd8402a9c8ab12bd39b38436f"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:755a47ba33529639284184f3560aa22fa2ffb29b252668953ecb8a0f7f13c01e -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 9, name = "Direction" }`
  - `forward` = `0`
  - `reverse` = `1`

- `{ index = 10, name = "SyncMode" }`
  - `FreeRun` = `0`
  - `MIDI` = `1`

- `{ index = 11, name = "FBMode" }`
  - `Mixed` = `0`
  - `Dual` = `0.5`
  - `PingPong` = `1`

- `{ index = 12, name = "DuckMode" }`
  - `Output` = `0`
  - `Regen` = `0.5`
  - `Both` = `1`

- `{ index = 16, name = "SpliceValue" }`
  - `6` = `0`
  - `5` = `0.1666666716337204`
  - `4` = `0.3333333432674408`
  - `3` = `0.5`
  - `2` = `0.66666668653488159`
  - `1` = `0.83333331346511841`
  - `0` = `1`

- `{ index = 18, name = "DelayValue" }`
  - `7` = `0`
  - `6` = `0.1428571492433548`
  - `5` = `0.28571429848670959`
  - `4` = `0.4285714328289032`
  - `3` = `0.57142859697341919`
  - `2` = `0.71428573131561279`
  - `1` = `0.8571428656578064`
  - `0` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 4, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 5, name = "Regenerate" }`: `0.250` = `0.25`
- `{ index = 9, name = "Direction" }`: `reverse` = `1`
- `{ index = 10, name = "SyncMode" }`: `MIDI` = `1`
- `{ index = 11, name = "FBMode" }`: `PingPong` = `1`
- `{ index = 12, name = "DuckMode" }`: `Both` = `1`
- `{ index = 14, name = "Pitch" }`: `1200` = `0.66666668653488159`
- `{ index = 16, name = "SpliceValue" }`: `3` = `0.5`
- `{ index = 18, name = "DelayValue" }`: `3` = `0.57142859697341919`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 5, name = "Regenerate" }`
  - natural alternative: `0.200` = `0.20000000298023224`
  - exact anchor: `0.250` = `0.25`
  - natural alternative: `0.300` = `0.30000001192092896`

- `{ index = 14, name = "Pitch" }`
  - natural alternative: `900` = `0.625`
  - exact anchor: `1200` = `0.66666668653488159`
  - natural alternative: `1440` = `0.69999998807907104`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:7ecd7a8fb332a653f67150425c07f696ad7e94517d418dd185f28f9f82f5bd31 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Crystallizer exposes product controls 1 through 23. Do not write Bypass 0 or
host controls 24 through 26. Use the complete automatable menu map above.

Regenerate can create sustained feedback. Keep it at or below 0.40 for unheard
audio unless the user explicitly requests a runaway effect. Resolve all
targets first, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve offsets, filters, dynamics
and every unrelated control.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Crystallizer combines pitch shifting, granular splicing and delay. A restrained
shimmer start uses a one-octave shift, modest Mix and Regenerate, tempo sync and
reverse direction. Ducking can keep regeneration out of the way of the source.
Describe these as starting settings because audio was not judged.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Crystallizer -->

<!-- PLUGIN:Decapitator -->
<!-- SECTION-REVISION:faea6f8877ff4831b572f05192249ee3f9a1ba76d2917aca7c7aa322627b4a6a -->
## Decapitator

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-decapitator","display_name":"Decapitator","vendor":"Soundtoys","product_class":"ordinary","preference_type":"saturation","identifiers":{"add_by_name":["VST3: Decapitator","VST3: Decapitator (Soundtoys)"],"aliases":["decapitator","soundtoys decapitator","VST3: Decapitator","VST3: Decapitator (Soundtoys)"],"curated":["Decapitator"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["decapitator"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-decapitator","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Decapitator","loaded_name":"VST3: Decapitator (Soundtoys)","parameter_count":{"mode":"exact","value":15},"required_parameters":[{"index":2,"name":"Drive","section":"","section_required":false},{"index":7,"name":"Mix","section":"","section_required":false},{"index":8,"name":"AutoGain","section":"","section_required":false},{"index":11,"name":"OutputTrim","section":"","section_required":false}],"observed_fingerprint_sha256":"3be117b87e84e189d3afe30d344fee1e5987157e21a5f437b753b7224fb32244"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/Decapitator-Manual.pdf","product_version":"5.5.5 64 bit","migrated_at":"2026-07-30","body_sha256":"8806ae2280326ba4402e55f6adb4e82d354d6c95b272a439483a502f635b149e","verified_at":"2026-08-01","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"3be117b87e84e189d3afe30d344fee1e5987157e21a5f437b753b7224fb32244"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- followup_evidence_sha256:a70a7bdde6e2cc83b913ff94f80b2666bed0717fe4ba041b30dac9b38d365c2f -->
### CERTIFIED STORED VALUES

These values passed repeated live storage, fixed-point readback and exact state
restoration in Soundtoys 5.5.5. Use the literal normalized values. Do not
interpolate them.

Complete menu map:

- `1 Style`: `A` = `0`, `E` = `0.25`, `N` = `0.5`, `T` = `0.75`, `P` = `1`
- `3 Punish`: `Off` = `0`, `On` = `1`
- `8 AutoGain`: `Off` = `0`, `On` = `1`
- `9 LowThump`: `Off` = `0`, `On` = `1`
- `10 HighSlope`: `Gentle` = `0`, `Steep` = `1`

Exact recipe anchors:

- `1 Style`: `A` = `0`
- `2 Drive`: `3.0` = `0.30000001192092896`
- `3 Punish`: `Off` = `0`
- `4 LowCut`: `53.2` = `0.25008189678192139`
- `5 Tone`: `0.0` = `0.5`
- `6 HighCut`: `9457.4` = `0.74999940395355225`
- `7 Mix`: `30.0` = `0.30000001192092896`
- `8 AutoGain`: `On` = `1`
- `9 LowThump`: `Off` = `0`
- `10 HighSlope`: `Gentle` = `0`
- `11 OutputTrim`: `0.0` = `1`

Calibrated continuous ladders:

- `2 Drive`: `2.0` = `0.20000000298023224`; `3.0` = `0.30000001192092896`; `4.0` = `0.40000000596046448`; `5.0` = `0.5`
- `4 LowCut`: `36.0` = `0.15025132894515991`; `53.2` = `0.25008189678192139`; `78.6` = `0.34985464811325073`
- `5 Tone`: `-2.4` = `0.40000000596046448`; `0.0` = `0.5`; `2.4` = `0.60000002384185791`
- `6 HighCut`: `7009.2` = `0.64999920129776001`; `9457.4` = `0.74999940395355225`; `12760.7` = `0.84999924898147583`
- `7 Mix`: `20.0` = `0.20000000298023224`; `30.0` = `0.30000001192092896`; `40.0` = `0.40000000596046448`; `100.0` = `1`
- `11 OutputTrim`: `-2.4` = `0.89999997615814209`; `-1.2` = `0.94999998807907104`; `0.0` = `1`

Natural-intent rule: choose only from the exact ladder and menu values above.
Change at least one anchor so the natural result differs from the exact recipe.
Preserve unrequested controls and describe unheard-audio settings as a starting
point.
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Decapitator is a character saturation and distortion effect. The installed
VST3 exposes 15 parameters. The useful musical surface is indices 1 through
11. Do not write the plug-in Bypass at index 0, host Bypass at index 12, Wet
at index 13 or Delta at index 14 unless the user explicitly asks for that
host-level operation.

AddByName identifier: use `VST3: Decapitator`.

### SAFE CONTROL MAP

```
idx  name        role
---  ----------  -----------------------------------------
1    Style       Soundtoys analog-model style A, E, N, T or P
2    Drive       Saturation amount
3    Punish      Extra aggressive gain stage
4    LowCut      Input low-cut frequency
5    Tone        Darker or brighter tilt
6    HighCut     Output high-cut frequency
7    Mix         Dry/wet mix
8    AutoGain    Automatic output compensation
9    LowThump    Low-frequency emphasis
10   HighSlope   High-cut slope character
11   OutputTrim  Output trim
```

Resolve every requested control before the first write. Use exact names and
indices in one `reaassist_resolve_profile_params` call. This Soundtoys build
does not expose a usable monotonic raw range for the generic display-search
helper. Use the guarded normalized anchors below for the certified recipe,
then verify every formatted readback. Do not use `set_param_display` for these
Soundtoys numeric controls.

The shipping provenance validator must see each literal `mapped[N]` index at
the setter call. Do not hide mapped indices inside a target table, loop or
wrapper. Use eleven explicit `TrackFX_SetParamNormalized` calls for the full
exact recipe.

Current live probes confirm that Decapitator stores these VST3 writes when they
are issued synchronously. Keep insertion, every requested parameter write and
`Undo_EndBlock` in one synchronous action. Do not use `reaper.defer` for an
ordinary Decapitator edit. Call `reaper.UpdateArrange()` after ending the Undo
block.

For a newly requested Decapitator instance, begin the normal Undo and
`PreventUIRefresh` scope first, add it with exactly
`TrackFX_AddByName(tr, "VST3: Decapitator", false, -1)`, and configure it
immediately after insertion. Do not use a positive instantiate mode or insert
the full chain before returning to configure Decapitator. This ordering avoids
the plug-in's startup preset restoring Drive and Mix to their defaults.

For subtle or natural warmth, keep Punish Off, leave LowThump Off unless the
user requests low-end emphasis, keep AutoGain On for a convenient starting
level and use restrained Drive and Mix. A safe unheard-audio starting point is
Style A, Drive 3.0, Tone 0.0, Mix 30.0 and OutputTrim 0.0. Describe these as
starting settings because no listening judgment has been made.

Punish can create a large level and distortion jump. Enable it only when the
user explicitly requests Punish, extreme distortion or an aggressive smashed
effect. Do not infer Punish from words such as warm, analog or saturated.

```lua
do
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 1, name = "Style" },
    { index = 2, name = "Drive" },
    { index = 3, name = "Punish" },
    { index = 4, name = "LowCut" },
    { index = 5, name = "Tone" },
    { index = 6, name = "HighCut" },
    { index = 7, name = "Mix" },
    { index = 8, name = "AutoGain" },
    { index = 9, name = "LowThump" },
    { index = 10, name = "HighSlope" },
    { index = 11, name = "OutputTrim" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.0) -- Style A
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2],
    0.30000001192092896) -- Drive 3.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.0) -- Punish Off
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4],
    0.25008189678192139) -- LowCut 53.2
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.5) -- Tone 0.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6],
    0.74999940395355225) -- HighCut 9457.4
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7],
    0.30000001192092896) -- Mix 30.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 1.0) -- AutoGain On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0) -- LowThump Off
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.0) -- HighSlope Gentle
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 1.0) -- OutputTrim 0.0
  reaper.Undo_EndBlock("ReaAssist: set Decapitator controls", -1)
  reaper.UpdateArrange()
end
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For subtle natural warmth, use the certified natural alternative: Style N,
Drive 2.0, Punish Off, LowCut 36.0, Tone -2.4, HighCut 7009.2, Mix 20.0,
AutoGain On, LowThump Off, HighSlope Gentle and OutputTrim -1.2. For bass,
vocals, drums or a mix bus, adjust Drive first and use Mix for parallel
character. Preserve every unrequested control on an existing instance.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Decapitator -->

<!-- PLUGIN:Devil-Loc -->
<!-- SECTION-REVISION:493770989a5462aec9dcc79af6bd580a2812a9c2de39c7ff60995812872a6c83 -->
## Devil-Loc

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-devil-loc","display_name":"Devil-Loc","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys devil loc","identifiers":{"add_by_name":["VST3: Devil-Loc","VST3: Devil-Loc (Soundtoys)"],"aliases":["devil-loc","devil loc","soundtoys devil-loc","VST3: Devil-Loc","VST3: Devil-Loc (Soundtoys)"],"curated":["Devil-Loc"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-devil-loc","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Devil-Loc","loaded_name":"VST3: Devil-Loc (Soundtoys)","parameter_count":{"mode":"exact","value":6},"required_parameters":[{"index":1,"name":"Crush","section":"","section_required":false},{"index":2,"name":"Crunch","section":"","section_required":false}],"observed_fingerprint_sha256":"98c6fd0f8cc384e3289d5f08aaa0c09e8000716191d636f7da42e68041fa190d"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/devil-loc/","document_title":"Devil-Loc Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"98c6fd0f8cc384e3289d5f08aaa0c09e8000716191d636f7da42e68041fa190d","body_sha256":"266db0b3977194723461bd21a488fbead0fdcac4c5f79443325c6a2c3dbddd0c"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:f42411a6d98fa621d0d4b312898266cc0b67f06482c891bf222d3e699689d3b5 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Crush" }`: `2.5` = `0.25`
- `{ index = 2, name = "Crunch" }`: `2.5` = `0.25`

Calibrated natural value ladders:

- `{ index = 1, name = "Crush" }`
  - natural alternative: `2.0` = `0.20000000298023224`
  - exact anchor: `2.5` = `0.25`
  - natural alternative: `3.0` = `0.30000001192092896`

- `{ index = 2, name = "Crunch" }`
  - natural alternative: `2.0` = `0.20000000298023224`
  - exact anchor: `2.5` = `0.25`
  - natural alternative: `3.0` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:cef87e6bb289d5cbcecb2d95cf5929dddd5ef50f9378a3348c2327d0d2231696 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

The installed VST3 exposes Crush 1 and Crunch 2. Do not write plug-in Bypass 0
or host controls 3 through 5.
Devil-Loc is intentionally extreme at high settings. For unheard audio, keep
both controls restrained. Resolve both exact names first, use literal
`mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback.
Verify next-frame readback and preserve host controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Crush controls compression and Crunch controls distortion. A restrained drum
room start uses both below 4.0. Higher settings can pump, gate and distort
aggressively, so use them only when the user asks for a destroyed sound.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Devil-Loc -->

<!-- PLUGIN:Devil-Loc Deluxe -->
<!-- SECTION-REVISION:c9957dd4f6dc03814f95cb2097938b34f08ffadf4f046589c8fdb7e40bf56840 -->
## Devil-Loc Deluxe

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-devil-loc-deluxe","display_name":"Devil-Loc Deluxe","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys devil loc deluxe","identifiers":{"add_by_name":["VST3: Devil-Loc Deluxe","VST3: Devil-Loc Deluxe (Soundtoys)"],"aliases":["devil-loc deluxe","devil loc deluxe","soundtoys devil-loc deluxe","VST3: Devil-Loc Deluxe","VST3: Devil-Loc Deluxe (Soundtoys)"],"curated":["Devil-Loc Deluxe"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-devil-loc-deluxe","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Devil-Loc Deluxe","loaded_name":"VST3: Devil-Loc Deluxe (Soundtoys)","parameter_count":{"mode":"exact","value":9},"required_parameters":[{"index":1,"name":"Crush","section":"","section_required":false},{"index":2,"name":"Crunch","section":"","section_required":false},{"index":3,"name":"Mix","section":"","section_required":false},{"index":5,"name":"Release","section":"","section_required":false}],"observed_fingerprint_sha256":"6a9c44259e78ef02dcdae5836ff2a4ad13b4bfd101dbac1dd174d7569c79388f"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/Devil-Loc-Deluxe-Manual.pdf","document_title":"Devil-Loc Deluxe User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"6a9c44259e78ef02dcdae5836ff2a4ad13b4bfd101dbac1dd174d7569c79388f","body_sha256":"2878486025d91d1fe705d876ede9fe2d69ba5c5c911cd6c1be1e65e011ef2de3"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:d5f6376a0fc295478abc819cafeab952a9aea9a3ba8bc5013b1fd0fb8b044e39 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 5, name = "Release" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Crush" }`: `2.5` = `0.25`
- `{ index = 2, name = "Crunch" }`: `2.5` = `0.25`
- `{ index = 3, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 4, name = "Darkness" }`: `7952.7` = `0.2500002384185791`
- `{ index = 5, name = "Release" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 1, name = "Crush" }`
  - natural alternative: `2.0` = `0.20000000298023224`
  - exact anchor: `2.5` = `0.25`
  - natural alternative: `3.0` = `0.30000001192092896`

- `{ index = 2, name = "Crunch" }`
  - natural alternative: `2.0` = `0.20000000298023224`
  - exact anchor: `2.5` = `0.25`
  - natural alternative: `3.0` = `0.30000001192092896`

- `{ index = 3, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 4, name = "Darkness" }`
  - natural alternative: `9563.5` = `0.20000070333480835`
  - exact anchor: `7952.7` = `0.2500002384185791`
  - natural alternative: `6613.2` = `0.30000022053718567`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:bba20bbdb0a814f36eb3f58cad13ffe22ed284168e9b5cfe4ca9676c13e0e94a -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Product controls are Crush 1, Crunch 2, Mix 3, Darkness 4 and Release 5. Do
not write Bypass 0 or host controls 6 through 8. Use the complete automatable
menu map above for Release.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Preserve every unrequested
control and verify delayed formatted readback.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use Mix for restrained parallel processing and Darkness to reduce harsh upper
distortion. Keep Crush and Crunch low for a conservative drum-room start.
Release changes the compressor recovery behavior; preserve it unless requested.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Devil-Loc Deluxe -->

<!-- PLUGIN:EchoBoy -->
<!-- SECTION-REVISION:84883bb49ea05fa38a28eb0a005df7e2859ef876abcf47b82d6c40c3d3377bc9 -->
## EchoBoy

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-echoboy","display_name":"EchoBoy","vendor":"Soundtoys","product_class":"ordinary","preference_type":"delay","identifiers":{"add_by_name":["VST3: EchoBoy","VST3: EchoBoy (Soundtoys)"],"aliases":["echoboy","echo boy","soundtoys echoboy","VST3: EchoBoy","VST3: EchoBoy (Soundtoys)"],"curated":["EchoBoy"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["echoboy"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-echoboy","safety":{"settle_ms":100,"heavy_selectors":[23],"unsafe_to_sweep":[11],"volatile_parameters":[24]},"fingerprints":[{"format":"VST3","identifier":"VST3: EchoBoy","loaded_name":"VST3: EchoBoy (Soundtoys)","parameter_count":{"mode":"exact","value":28},"required_parameters":[{"index":1,"name":"InputGain","section":"","section_required":false},{"index":3,"name":"Mix","section":"","section_required":false},{"index":11,"name":"Feedback","section":"","section_required":false},{"index":23,"name":"Style","section":"","section_required":false}],"observed_fingerprint_sha256":"025fc93303fd567151d8af4e4f204ae7583d63f24ee62cad1804b02b47f1c41c"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/EchoBoy-Manual.pdf","product_version":"5.5.5 64 bit","migrated_at":"2026-07-30","body_sha256":"210f792e88b63659b6e50fecc86c0b1bf0a881083349c998c2c0b0c3066a0b03","verified_at":"2026-08-01","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"025fc93303fd567151d8af4e4f204ae7583d63f24ee62cad1804b02b47f1c41c"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- followup_evidence_sha256:a70a7bdde6e2cc83b913ff94f80b2666bed0717fe4ba041b30dac9b38d365c2f -->
### CERTIFIED STORED VALUES

These values passed repeated live storage, fixed-point readback and exact state
restoration in Soundtoys 5.5.5. Use literal normalized values. Do not compute,
round or interpolate them.

Complete live menu maps:

- `4 Mode`: `Single` = `0`, `Dual` = `0.3333333432674408`, `Ping-Pong` = `0.66666668653488159`, `Rhythm` = `1`
- `5 Echo1Mode` and `8 Echo2Mode`: `Time` = `0`, `Note` = `0.25`, `Dotted` = `0.5`, `Triplet` = `0.75`, `Beats` = `1`
- `6 Echo1Note` and `9 Echo2Note`: `1/1 note` = `0`, `1/2 note` = `0.05000000074505806`, `1/4 note` = `0.10000000149011612`, `1/8th` = `0.15000000596046448`, `1/16th` = `0.20000000298023224`, `1/32nd` = `0.25`, `1/64th` = `0.30000001192092896`, `1/1 trip` = `0.34999999403953552`, `1/2 trip` = `0.40000000596046448`, `1/4 trip` = `0.44999998807907104`, `1/8 trip` = `0.5`, `1/16 trip` = `0.55000001192092896`, `1/32 trip` = `0.60000002384185791`, `1/64 trip` = `0.64999997615814209`, `1/1 dot` = `0.69999998807907104`, `1/2 dot` = `0.75`, `1/4 dot` = `0.80000001192092896`, `1/8 dot` = `0.85000002384185791`, `1/16 dot` = `0.89999997615814209`, `1/32 dot` = `0.94999998807907104`, `1/64 dot` = `1`
- `12 PrimeNumbers`: `Off` = `0`, `On` = `1`
- `18 RhythmMode`: `Time` = `0`, `Note` = `0.1666666716337204`, `Dotted` = `0.3333333432674408`, `Triplet` = `0.5`, `Pattern` = `0.66666668653488159`, `CustomTime` = `0.83333331346511841`, `CustomBeats` = `1`
- `19 RhythmNote`: `1/2 note` = `0`, `1/4 note` = `0.058823529630899429`, `1/8th` = `0.11764705926179886`, `1/16th` = `0.17647059261798859`, `1/32nd` = `0.23529411852359772`, `1/64th` = `0.29411765933036804`, `1/2 trip` = `0.35294118523597717`, `1/4 trip` = `0.4117647111415863`, `1/8 trip` = `0.47058823704719543`, `1/16 trip` = `0.52941179275512695`, `1/32 trip` = `0.58823531866073608`, `1/64 trip` = `0.64705884456634521`, `1/2 dot` = `0.70588237047195435`, `1/4 dot` = `0.76470589637756348`, `1/8 dot` = `0.82352942228317261`, `1/16 dot` = `0.88235294818878174`, `1/32 dot` = `0.94117647409439087`, `1/64 dot` = `1`
- `21 RhythmRepeats`: `1` = `0`, `2` = `0.066666670143604279`, `3` = `0.13333334028720856`, `4` = `0.20000000298023224`, `5` = `0.26666668057441711`, `6` = `0.3333333432674408`, `7` = `0.40000000596046448`, `8` = `0.46666666865348816`, `9` = `0.53333336114883423`, `10` = `0.60000002384185791`, `11` = `0.66666668653488159`, `12` = `0.73333334922790527`, `13` = `0.80000001192092896`, `14` = `0.86666667461395264`, `15` = `0.93333333730697632`, `16` = `1`

Full zero-write Style formatter map:

- `Master Tape` = `0`; `Studio Tape` = `0.032258064`; `EchoPlex` = `0.06451613`; `Space Echo` = `0.09677419`
- `Tube Tape` = `0.12903225`; `Cheap Tape` = `0.16129032`; `Memory Man` = `0.19354838`; `DM-2` = `0.22580644`
- `TelRay` = `0.2580645`; `Binsonette` = `0.29032257`; `Telephone` = `0.32258064`; `AM Radio` = `0.3548387`
- `FM Radio` = `0.38709676`; `Shortwave` = `0.41935483`; `Transmitter` = `0.4516129`; `Digital Delay` = `0.48387095`
- `Analog Delay` = `0.516129`; `DigitalChorus` = `0.5483871`; `Analog Chorus` = `0.58064514`; `CE-1 Chorus` = `0.61290324`
- `Vibrato` = `0.6451613`; `Saturated` = `0.67741936`; `Fat` = `0.7096774`; `Distressed` = `0.7419355`
- `Limited` = `0.7741935`; `Distorted` = `0.8064516`; `Queeked` = `0.83870965`; `Ambient` = `0.87096775`
- `Diffused` = `0.9032258`; `Splattered` = `0.9354839`; `Verbed` = `0.9677419`; `Edited Style` = `1`

The 1,001-point Style grid is read-only. `Master Tape` = `0`, `Analog Delay` =
`0.5161290168762207` and `Verbed` = `0.96774190664291382` also passed paced
live storage. Style swaps modeled assets. Write one requested Style value and
allow stable pacing. Never sweep Style or enumerate it with live writes.

Exact recipe anchors:

- `1 InputGain`: `0.0` = `0.5`; `2 OutputGain`: `0.0` = `0.5`; `3 Mix`: `20.0` = `0.20000000298023224`
- `4 Mode`: `Single` = `0`; `5 Echo1Mode`: `Note` = `0.25`; `6 Echo1Note`: `1/8th` = `0.15000000596046448`; `7 Echo1Time`: `231.4` = `0.65001732110977173`
- `8 Echo2Mode`: `Note` = `0.25`; `9 Echo2Note`: `1/8th` = `0.15000000596046448`; `10 Echo2Time`: `231.4` = `0.65001732110977173`
- `11 Feedback`: `0.25` = `0.20000000298023224`; `12 PrimeNumbers`: `Off` = `0`; `13 Groove`: `0.000` = `0.5`; `14 Feel`: `0.000` = `0.5`
- `15 Saturation`: `9.98` = `0.41583332419395447`; `16 LowCut`: `0.00` = `0`; `17 HighCut`: `0.00` = `0`
- `18 RhythmMode`: `Note` = `0.1666666716337204`; `19 RhythmNote`: `1/8th` = `0.11764705926179886`; `20 RhythmTime`: `102.8` = `0.54999959468841553`
- `21 RhythmRepeats`: `8` = `0.46666666865348816`; `22 RhythmDecay`: `8.0` = `0.20000000298023224`; `23 Style`: `Master Tape` = `0`

Calibrated continuous ladders:

- `1 InputGain` and `2 OutputGain`: `-2.4` = `0.44999998807907104`; `0.0` = `0.5`; `2.4` = `0.55000001192092896`
- `3 Mix`: `15.0` = `0.15000000596046448`; `20.0` = `0.20000000298023224`; `25.0` = `0.25`
- `7 Echo1Time` and `10 Echo2Time`: `127.4` = `0.5999717116355896`; `231.4` = `0.65001732110977173`; `419.9` = `0.69999676942825317`
- `11 Feedback`: `0.19` = `0.15199999511241913`; `0.25` = `0.20000000298023224`; `0.31` = `0.24799999594688416`
- `13 Groove` and `14 Feel`: `-0.050` = `0.40000000596046448`; `0.000` = `0.5`; `0.050` = `0.60000002384185791`
- `15 Saturation`: `8.40` = `0.34999999403953552`; `9.98` = `0.41583332419395447`; `12.00` = `0.5`
- `16 LowCut` and `17 HighCut`: `0.00` = `0`; `0.10` = `0.10000000149011612`; `0.20` = `0.20000000298023224`
- `20 RhythmTime`: `54.7` = `0.50003999471664429`; `102.8` = `0.54999959468841553`; `193.2` = `0.59999239444732666`
- `22 RhythmDecay`: `4.0` = `0.10000000149011612`; `8.0` = `0.20000000298023224`; `12.0` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder and menu values above.
Change at least one requested target so the natural result differs from the
exact recipe. Preserve unrequested controls and describe unheard-audio
settings as a starting point.
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

EchoBoy is a delay and echo effect with multiple timing modes and modeled echo
styles. The installed VST3 exposes 28 parameters. Product controls are indices
1 through 23. Do not write index 0, host-supplied Tempo at index 24 or host
indices 25 through 27. Tempo follows the REAPER project and rejected live
parameter writes during calibration.

### PRIMARY CONTROLS

```
1 InputGain     2 OutputGain    3 Mix            4 Mode
5 Echo1Mode     6 Echo1Note     7 Echo1Time       8 Echo2Mode
9 Echo2Note    10 Echo2Time    11 Feedback       12 PrimeNumbers
13 Groove      14 Feel         15 Saturation     16 LowCut
17 HighCut     18 RhythmMode   19 RhythmNote     20 RhythmTime
21 RhythmRepeats  22 RhythmDecay  23 Style
```

Mode controls whether the instance uses one echo, dual echo, ping-pong or a
rhythm pattern. Echo1 and Echo2 controls depend on that mode. For a Single
echo, do not rewrite Echo2. When Echo1Mode is Note, set Echo1Note and preserve
Echo1Time. When Echo1Mode is Time, set Echo1Time and preserve Echo1Note.
RhythmMode selects the active RhythmNote or RhythmTime family. Change only the
active timing family unless the user explicitly requests a complete preset.

Treat the top-level Mode at index 4 as mandatory whenever the request names
Single, Dual, Ping-Pong or Rhythm. RhythmMode at index 18 is a subordinate
timing selector and never replaces the top-level Mode write. Resolve and write
the active conditional controls in this order:

- Dual Note: `4 Mode = Dual (0.3333333432674408)`, then
  `5 Echo1Mode = Note (0.25)`,
  `6 Echo1Note = 1/8th (0.15000000596046448)`,
  `8 Echo2Mode = Note (0.25)` and
  `9 Echo2Note = 1/4 note (0.10000000149011612)`. Preserve indices 7 and 10.
- Dual Time: `4 Mode = Dual (0.3333333432674408)`, then
  `5 Echo1Mode = Time (0)`,
  `7 Echo1Time = 231.4 (0.65001732110977173)`,
  `8 Echo2Mode = Time (0)` and
  `10 Echo2Time = 419.9 (0.69999676942825317)`. The two Time values may differ.
  Preserve indices 6 and 9.
- Rhythm Note: `4 Mode = Rhythm (1)`, then
  `18 RhythmMode = Note (0.1666666716337204)`,
  `19 RhythmNote = 1/8th (0.11764705926179886)`,
  `21 RhythmRepeats = 8 (0.46666666865348816)` and
  `22 RhythmDecay = 8.0 (0.20000000298023224)`. Preserve index 20.
- Rhythm Time selector transition: set `4 Mode = Rhythm (1)` and
  `18 RhythmMode = Time (0)`. Preserve indices 19 through 22.
- Rhythm Time value edit, only when the current instance is already in
  top-level Rhythm mode with RhythmMode Time: preserve indices 4, 18 and 19,
  then set `20 RhythmTime = 102.8 (0.54999959468841553)`,
  `21 RhythmRepeats = 8 (0.46666666865348816)` and
  `22 RhythmDecay = 8.0 (0.20000000298023224)`.

The literal setter example below demonstrates Single mode only. Do not reuse
its `Mode = Single` assignment for a Dual, Ping-Pong or Rhythm request.

Soundtoys 5.5.5 cannot restore the prior RhythmTime value with one Undo when
one action both switches from another mode into Rhythm Time and writes index
20. The resulting values and delayed readback are correct, but Undo restores
the selectors before the dependent value and leaves RhythmTime changed. Fail
closed on that combined request. Explain that it needs two actions: first
switch the two selectors while preserving indices 19 through 22, then set the
Rhythm Time values after the instance is already in that mode. Do not silently
apply only part of the request. Do not combine the two actions into one script.

Feedback is marked unsafe to sweep because high values can self-oscillate and
raise output substantially. Set a known requested display directly through
the reviewed normalized anchors. EchoBoy formats Feedback as 0.00 through 1.25.
The stored value `0.20000000298023224` reads `0.25`. For unheard material, use
only the certified `0.19`, `0.25` or `0.31` display anchors unless the user
explicitly requests runaway or self-oscillating delay.
Keep Mix at or below 30.0 for an inline starting point. On a dedicated send
return, use 100.0 Mix only when the user explicitly identifies it as a return.

This Soundtoys build does not expose a usable monotonic raw range for the
generic display-search helper. Resolve the complete target table first, then
use the reviewed normalized anchors below. The provenance validator must see
each literal `mapped[N]` index at its setter call, so do not hide these writes
inside a loop or wrapper. Use exactly one `reaper.defer` callback. ReaAssist
commits and verifies delayed live readback before reporting completion. Do not
call `TrackFX_GetFormattedParamValue` in generated code. Do not schedule a
follow-up callback or add any verification loop after the requested writes.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 3, name = "Mix" },
    { index = 4, name = "Mode" },
    { index = 5, name = "Echo1Mode" },
    { index = 6, name = "Echo1Note" },
    { index = 11, name = "Feedback" },
    { index = 15, name = "Saturation" },
    { index = 23, name = "Style" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1],
    0.20000000298023224) -- Mix 20.0
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.0) -- Single
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.25) -- Note
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4],
    0.15000000596046448) -- 1/8th
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5],
    0.20000000298023224) -- Feedback 0.25
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6],
    0.41583332419395447) -- Saturation 9.98
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.0) -- Master Tape
  reaper.Undo_EndBlock("ReaAssist: set EchoBoy controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
A dark restrained tape echo starts with Single mode, Note timing at `1/4 note`,
Mix 15.0, Feedback 0.19, Saturation 8.40 and Studio Tape. Preserve inactive
Echo2 and Rhythm controls. Keep the summary factual: state the selected
settings and call them a starting point. Do not claim the delay sits correctly
without listening.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:EchoBoy -->

<!-- PLUGIN:EchoBoy Jr -->
<!-- SECTION-REVISION:00cfec45aebbc886b08408f43e76b0975b531827ed7652b76748fa333aeea255 -->
## EchoBoy Jr

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-echoboy-jr","display_name":"EchoBoy Jr","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys echoboy jr","identifiers":{"add_by_name":["VST3: EchoBoy Jr","VST3: EchoBoy Jr (Soundtoys)"],"aliases":["echoboy jr","echo boy jr","soundtoys echoboy jr","VST3: EchoBoy Jr","VST3: EchoBoy Jr (Soundtoys)"],"curated":["EchoBoy Jr"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-echoboy-jr","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[10],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: EchoBoy Jr","loaded_name":"VST3: EchoBoy Jr (Soundtoys)","parameter_count":{"mode":"exact","value":17},"required_parameters":[{"index":3,"name":"Mix","section":"","section_required":false},{"index":4,"name":"Mode","section":"","section_required":false},{"index":5,"name":"Style","section":"","section_required":false},{"index":7,"name":"EchoMode","section":"","section_required":false},{"index":8,"name":"EchoNote","section":"","section_required":false},{"index":10,"name":"Feedback","section":"","section_required":false}],"observed_fingerprint_sha256":"6da848693c12b98bfe0e768498890d01ac8d77fdf5f9af55315417fd9e583753"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/echoboy-jr/","document_title":"EchoBoy Jr Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"6da848693c12b98bfe0e768498890d01ac8d77fdf5f9af55315417fd9e583753","body_sha256":"7fd16c20f44a20690e6a188504b5993e1e6372b8c8ca935e26fb2c20d161fbce"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:e1600c3b3c0580881133d5925c6494498e87fbf1a746a6dd304c2c80320b74a9 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "Mode" }`
  - `Normal` = `0`
  - `Wide` = `0.5`
  - `Ping-Pong` = `1`

- `{ index = 5, name = "Style" }`
  - `Studio Tape` = `0`
  - `EchoPlex` = `0.1666666716337204`
  - `Space Echo` = `0.3333333432674408`
  - `Cheap Tape` = `0.5`
  - `Memory Man` = `0.66666668653488159`
  - `Ambient` = `0.83333331346511841`
  - `Transmitter` = `1`

- `{ index = 6, name = "Glide" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 7, name = "EchoMode" }`
  - `Time` = `0`
  - `Note` = `0.25`
  - `Dotted` = `0.5`
  - `Triplet` = `0.75`
  - `Beats` = `1`

- `{ index = 8, name = "EchoNote" }`
  - `1/1 note` = `0`
  - `1/2 note` = `0.05000000074505806`
  - `1/4 note` = `0.10000000149011612`
  - `1/8th` = `0.15000000596046448`
  - `1/16th` = `0.20000000298023224`
  - `1/32nd` = `0.25`
  - `1/64th` = `0.30000001192092896`
  - `1/1 trip` = `0.34999999403953552`
  - `1/2 trip` = `0.40000000596046448`
  - `1/4 trip` = `0.44999998807907104`
  - `1/8 trip` = `0.5`
  - `1/16 trip` = `0.55000001192092896`
  - `1/32 trip` = `0.60000002384185791`
  - `1/64 trip` = `0.64999997615814209`
  - `1/1 dot` = `0.69999998807907104`
  - `1/2 dot` = `0.75`
  - `1/4 dot` = `0.80000001192092896`
  - `1/8 dot` = `0.85000002384185791`
  - `1/16 dot` = `0.89999997615814209`
  - `1/32 dot` = `0.94999998807907104`
  - `1/64 dot` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 4, name = "Mode" }`: `Wide` = `0.5`
- `{ index = 5, name = "Style" }`: `Space Echo` = `0.3333333432674408`
- `{ index = 6, name = "Glide" }`: `Off` = `0`
- `{ index = 7, name = "EchoMode" }`: `Note` = `0.25`
- `{ index = 8, name = "EchoNote" }`: `1/8th` = `0.15000000596046448`
- `{ index = 10, name = "Feedback" }`: `0.31` = `0.24799999594688416`
- `{ index = 11, name = "Saturation" }`: `6.00` = `0.25`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 10, name = "Feedback" }`
  - natural alternative: `0.25` = `0.20000000298023224`
  - exact anchor: `0.31` = `0.24799999594688416`
  - natural alternative: `0.38` = `0.30399999022483826`

- `{ index = 11, name = "Saturation" }`
  - natural alternative: `4.80` = `0.20000000298023224`
  - exact anchor: `6.00` = `0.25`
  - natural alternative: `7.20` = `0.30000001192092896`

Certified natural menu alternative:
- `5 Style`: `Studio Tape` = `0`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:5cac7d95d04aadb7902e9c379d2e99c2fe86e49700942802404b5e381b2ede5e -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

EchoBoy Jr product controls are 1 through 13. Do not write Bypass 0 or host
controls 14 through 16. Use the complete automatable menu map above.

Feedback can self-oscillate. Keep it at or below 0.35 for unheard audio unless
explicitly requested. Resolve all targets, use literal `mapped[N]` setters,
one Undo block and exactly one `reaper.defer` callback. Preserve EchoTime when Note mode
is selected, verify delayed readback and preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a dark restrained tape echo, use Studio Tape, Note timing, an eighth or
quarter note, modest Feedback and Mix, and low Saturation. Style and Mode are
independent. State chosen settings without claiming how they sit in the mix.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:EchoBoy Jr -->

<!-- PLUGIN:FilterFreak1 -->
<!-- SECTION-REVISION:9c2c23765425202c29fbbceb01b98171c3c373deb361c6dbea5c0f95e84e95cc -->
## FilterFreak1

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-filterfreak1","display_name":"FilterFreak1","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys filterfreak1","identifiers":{"add_by_name":["VST3: FilterFreak1","VST3: FilterFreak1 (Soundtoys)"],"aliases":["filterfreak1","filter freak 1","soundtoys filterfreak1","VST3: FilterFreak1","VST3: FilterFreak1 (Soundtoys)"],"curated":["FilterFreak1"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["filterfreak1"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-filterfreak1","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[6],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: FilterFreak1","loaded_name":"VST3: FilterFreak1 (Soundtoys)","parameter_count":{"mode":"exact","value":16},"required_parameters":[{"index":5,"name":"Frequency","section":"","section_required":false},{"index":6,"name":"Resonance","section":"","section_required":false},{"index":7,"name":"FilterOrder","section":"","section_required":false},{"index":8,"name":"FilterShape","section":"","section_required":false}],"observed_fingerprint_sha256":"9f28af429a3b7a8619c1cbc560262ed2f538b1bc6c0b96ca35e3a311336f5216"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/FilterFreak-Manual.pdf","document_title":"FilterFreak User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9f28af429a3b7a8619c1cbc560262ed2f538b1bc6c0b96ca35e3a311336f5216","body_sha256":"71e0c28832c08b068e53cdba408c6c96d18477b8a6aabd46b25a756740ab2dcf"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:174e3f7b1152223d11e5da9a3c801f11823742fdd425a5a4f6292324098b80a4 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 7, name = "FilterOrder" }`
  - `2` = `0`
  - `4` = `0.3333333432674408`
  - `6` = `0.66666668653488159`
  - `8` = `1`
  - Formatter-only host readouts: `3`, `5`, `7`. A script cannot set these
    states in this build. Offer the adjacent writable choices and explain why.

- `{ index = 8, name = "FilterShape" }`
  - `Lowpass` = `0`
  - `Bandpass` = `0.3333333432674408`
  - `Highpass` = `0.66666668653488159`
  - `Notch` = `1`

- `{ index = 10, name = "Trigger" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 4, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 5, name = "Frequency" }`: `1262` = `0.60000979900360107`
- `{ index = 6, name = "Resonance" }`: `7.2` = `0.40000000596046448`
- `{ index = 7, name = "FilterOrder" }`: `4` = `0.3333333432674408`
- `{ index = 8, name = "FilterShape" }`: `Bandpass` = `0.3333333432674408`
- `{ index = 9, name = "ModulationDepth" }`: `0.25` = `0.25`
- `{ index = 10, name = "Trigger" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

- `{ index = 5, name = "Frequency" }`
  - natural alternative: `893` = `0.54994046688079834`
  - exact anchor: `1262` = `0.60000979900360107`
  - natural alternative: `1500` = `0.62502044439315796`

- `{ index = 6, name = "Resonance" }`
  - natural alternative: `5.3` = `0.33214285969734192`
  - natural alternative: `6.5` = `0.375`
  - exact anchor: `7.2` = `0.40000000596046448`

- `{ index = 9, name = "ModulationDepth" }`
  - natural alternative: `0.20` = `0.20000000298023224`
  - exact anchor: `0.25` = `0.25`
  - natural alternative: `0.30` = `0.30000001192092896`

Certified natural menu alternative:
- `8 FilterShape`: `Lowpass` = `0`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:fb55890659773b40a063b765a2477162a2d2c375b9a8f66e4969877f24be65d4 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Product controls are 1 through 12. Do not write Bypass 0 or host controls 13
through 15. Use the complete automatable menu map above. FilterOrder
automation exposes 2, 4, 6 and 8 poles. The host formatter also displays 3,
5 and 7 between those states, but a script cannot store them in this build.
If the user asks for an odd pole count, offer the adjacent writable choices
and explain why.


High resonance can self-oscillate. Keep it moderate on unheard audio. Resolve
all targets first, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. The deep analog-style selector and modulation
editors are not exposed as TrackFX parameters. Do not invent control for them.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
A gentle slow low-pass movement starts with low Resonance, moderate Mix and
ModulationDepth, and a slow LFO. The filter shape and pole count materially
change the result. Preserve them unless the request is clear.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:FilterFreak1 -->

<!-- PLUGIN:FilterFreak2 -->
<!-- SECTION-REVISION:2a6b46ea9d4a6ed549e333e3f44666f1e0f559c98ba4f287dd25055d3ab1abe8 -->
## FilterFreak2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-filterfreak2","display_name":"FilterFreak2","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys filterfreak2","identifiers":{"add_by_name":["VST3: FilterFreak2","VST3: FilterFreak2 (Soundtoys)"],"aliases":["filterfreak2","filter freak 2","soundtoys filterfreak2","VST3: FilterFreak2","VST3: FilterFreak2 (Soundtoys)"],"curated":["FilterFreak2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["filterfreak2"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-filterfreak2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[6,11],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: FilterFreak2","loaded_name":"VST3: FilterFreak2 (Soundtoys)","parameter_count":{"mode":"exact","value":24},"required_parameters":[{"index":5,"name":"Frequency1","section":"","section_required":false},{"index":8,"name":"Filter1Shape","section":"","section_required":false},{"index":10,"name":"Frequency2","section":"","section_required":false},{"index":13,"name":"Filter2Shape","section":"","section_required":false},{"index":16,"name":"FilterRouting","section":"","section_required":false}],"observed_fingerprint_sha256":"958e699ca98c94f0d2fd4764033c7332a9854cb3ed5f7653b8b517aa8b99baf9"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/FilterFreak-Manual.pdf","document_title":"FilterFreak User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"958e699ca98c94f0d2fd4764033c7332a9854cb3ed5f7653b8b517aa8b99baf9","body_sha256":"c85da9e78b5685c58f44342b35f3fe42cb2a1c342f02e55f397aa5831db650db"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:d774baec1c08d464d784b22600c7b003ec8827046f85f487eb78267deb0cf7fb -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 8, name = "Filter1Shape" }`
  - `Lowpass` = `0`
  - `Bandpass` = `0.3333333432674408`
  - `Highpass` = `0.66666668653488159`
  - `Notch` = `1`

- `{ index = 9, name = "Filter1Order" }`
  - `2` = `0`
  - `4` = `0.3333333432674408`
  - `6` = `0.66666668653488159`
  - `8` = `1`
  - Formatter-only host readouts: `3`, `5`, `7`. A script cannot set these
    states in this build. Offer the adjacent writable choices and explain why.

- `{ index = 13, name = "Filter2Shape" }`
  - `Lowpass` = `0`
  - `Bandpass` = `0.3333333432674408`
  - `Highpass` = `0.66666668653488159`
  - `Notch` = `1`

- `{ index = 14, name = "Filter2Order" }`
  - `2` = `0`
  - `4` = `0.3333333432674408`
  - `6` = `0.66666668653488159`
  - `8` = `1`
  - Formatter-only host readouts: `3`, `5`, `7`. A script cannot set these
    states in this build. Offer the adjacent writable choices and explain why.

- `{ index = 15, name = "FilterLink" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 16, name = "FilterRouting" }`
  - `Series` = `0`
  - `Parallel` = `1`

- `{ index = 18, name = "Trigger" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 4, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 5, name = "Frequency1" }`: `316.98` = `0.40000063180923462`
- `{ index = 6, name = "Resonance1" }`: `7.2` = `0.40000000596046448`
- `{ index = 8, name = "Filter1Shape" }`: `Lowpass` = `0`
- `{ index = 9, name = "Filter1Order" }`: `4` = `0.3333333432674408`
- `{ index = 10, name = "Frequency2" }`: `1261.91` = `0.59999948740005493`
- `{ index = 11, name = "Resonance2" }`: `3.0` = `0.25`
- `{ index = 13, name = "Filter2Shape" }`: `Highpass` = `0.66666668653488159`
- `{ index = 14, name = "Filter2Order" }`: `6` = `0.66666668653488159`
- `{ index = 15, name = "FilterLink" }`: `Off` = `0`
- `{ index = 16, name = "FilterRouting" }`: `Series` = `0`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

- `{ index = 5, name = "Frequency1" }`
  - natural alternative: `266.70` = `0.37499767541885376`
  - exact anchor: `316.98` = `0.40000063180923462`
  - natural alternative: `447.74` = `0.4499986469745636`

- `{ index = 6, name = "Resonance1" }`
  - natural alternative: `5.3` = `0.33214285969734192`
  - natural alternative: `6.5` = `0.375`
  - exact anchor: `7.2` = `0.40000000596046448`

- `{ index = 10, name = "Frequency2" }`
  - natural alternative: `893.37` = `0.55000042915344238`
  - exact anchor: `1261.91` = `0.59999948740005493`
  - natural alternative: `1499.79` = `0.62500017881393433`

- `{ index = 11, name = "Resonance2" }`
  - natural alternative: `2.4` = `0.20000000298023224`
  - exact anchor: `3.0` = `0.25`
  - natural alternative: `4.4` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:fc52bb5c7eef162dfec9b2d993e7d02fef4f684048daf01aea89eb7d32511a51 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Product controls are 1 through 20. Do not write Bypass 0 or host controls 21
through 23. Use the complete automatable menu map above. Both FilterOrder
automation controls expose 2, 4, 6 and 8 poles. The host formatter also shows
3, 5 and 7, but a script cannot store them in this build. Offer the adjacent
writable choices when an odd pole count is requested.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Keep resonance conservative. Deep analog
style and modulation editors are not host-exposed and remain manual.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Series routing applies one filter after the other; Parallel blends their
outputs. Link intentionally couples the two filter controls, so leave it Off
for independent exact settings. For gentle motion, keep resonance and Mix
moderate and preserve unrelated modulation controls.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:FilterFreak2 -->

<!-- PLUGIN:Little AlterBoy -->
<!-- SECTION-REVISION:d9305951b474dc7a9213a04d2e74c6af532d2720628ba8681b5b94eb0c63541f -->
## Little AlterBoy

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-little-alterboy","display_name":"Little AlterBoy","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys little alterboy","identifiers":{"add_by_name":["VST3: Little AlterBoy","VST3: Little AlterBoy (Soundtoys)"],"aliases":["little alterboy","little alter boy","soundtoys little alterboy","VST3: Little AlterBoy","VST3: Little AlterBoy (Soundtoys)"],"curated":["Little AlterBoy"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-little-alterboy","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Little AlterBoy","loaded_name":"VST3: Little AlterBoy (Soundtoys)","parameter_count":{"mode":"exact","value":10},"required_parameters":[{"index":1,"name":"Pitch","section":"","section_required":false},{"index":2,"name":"Formant","section":"","section_required":false},{"index":5,"name":"ShiftMode","section":"","section_required":false},{"index":6,"name":"FormantLink","section":"","section_required":false}],"observed_fingerprint_sha256":"03b17bf1e8466344c09d22ca661cb38b699337e61c99db8a0cfec075e6811c55"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/Little-AlterBoy-Manual.pdf","document_title":"Little AlterBoy User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"03b17bf1e8466344c09d22ca661cb38b699337e61c99db8a0cfec075e6811c55","body_sha256":"7d2516daa2aeba2680d410994b98b89b0673d9f88f46872b9f313137cbefe6ec"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:75bd0590f6c8d48ae113e5e9bc0b8ba517c6a6256d58693a76580718b6a008c4 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 5, name = "ShiftMode" }`
  - `Transpose` = `0`
  - `Quantize` = `0.5`
  - `Robot` = `1`

- `{ index = 6, name = "FormantLink" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Pitch" }`: `-6.0` = `0.25`
- `{ index = 2, name = "Formant" }`: `-2.4` = `0.40000000596046448`
- `{ index = 3, name = "Drive" }`: `2.5` = `0.25`
- `{ index = 4, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 5, name = "ShiftMode" }`: `Transpose` = `0`
- `{ index = 6, name = "FormantLink" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 1, name = "Pitch" }`
  - natural alternative: `-7.2` = `0.20000000298023224`
  - exact anchor: `-6.0` = `0.25`
  - natural alternative: `-4.8` = `0.30000001192092896`

- `{ index = 2, name = "Formant" }`
  - natural alternative: `-3.0` = `0.375`
  - exact anchor: `-2.4` = `0.40000000596046448`
  - natural alternative: `-1.2` = `0.44999998807907104`

- `{ index = 3, name = "Drive" }`
  - natural alternative: `2.0` = `0.20000000298023224`
  - exact anchor: `2.5` = `0.25`
  - natural alternative: `3.0` = `0.30000001192092896`

- `{ index = 4, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:ba5595199a0dfab88eb2b3de689787b91d541fa1afab4a375f99d6750bf15d33 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

The installed Soundtoys 5.5.5 VST3 exposes six product controls at indices 1
through 6. Do not write plug-in Bypass at 0 or host controls 7 through 9.

ShiftMode is a nonstandard stepped control. Use the complete automatable menu
map above for ShiftMode and FormantLink.


Resolve every requested index and exact name in one
`reaassist_resolve_profile_params` call before writing. Use literal
`mapped[N]` setter arguments, one Undo block and exactly one `reaper.defer` callback. Soundtoys applies VST3 writes one REAPER frame later. Preserve every
unrequested control and use guarded normalized anchors followed by formatted
readback verification.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Little AlterBoy is intended primarily for clean monophonic vocals. Transpose
preserves independent formant control. Quantize creates stepped pitch and
Robot holds one pitch. For a natural lower vocal, start with Transpose,
FormantLink Off, restrained negative Pitch and Formant values, light Drive and
a moderate Mix. Describe unheard-audio settings as a starting point.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Little AlterBoy -->

<!-- PLUGIN:Little MicroShift -->
<!-- SECTION-REVISION:05772561f60558b81322eaff895df88d48e76b7ca73769d756be83fcf8b28e72 -->
## Little MicroShift

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-little-microshift","display_name":"Little MicroShift","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys little microshift","identifiers":{"add_by_name":["VST3: Little MicroShift","VST3: Little MicroShift (Soundtoys)"],"aliases":["little microshift","little micro shift","soundtoys little microshift","VST3: Little MicroShift","VST3: Little MicroShift (Soundtoys)"],"curated":["Little MicroShift"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-little-microshift","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Little MicroShift","loaded_name":"VST3: Little MicroShift (Soundtoys)","parameter_count":{"mode":"exact","value":7},"required_parameters":[{"index":1,"name":"InputGain","section":"","section_required":false},{"index":2,"name":"Mix","section":"","section_required":false},{"index":3,"name":"Style","section":"","section_required":false}],"observed_fingerprint_sha256":"eb0e0c89289d5fd82a067955b8e2b436bfe340d368b08f26b857b8cc0339b902"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/little-microshift/","document_title":"Little MicroShift Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"eb0e0c89289d5fd82a067955b8e2b436bfe340d368b08f26b857b8cc0339b902","body_sha256":"c84be03170346f77207108a114727b27344606bf6fb0d908b9bcf3859b29e9e8"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:7dec20f1dbe786c068acbdf8df26cc139019c17a49f386db5d52609a4a31d84e -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 3, name = "Style" }`
  - `I` = `0`
  - `II` = `0.5`
  - `III` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "InputGain" }`: `0.6` = `0.40000000596046448`
- `{ index = 2, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 3, name = "Style" }`: `III` = `1`

Calibrated natural value ladders:

- `{ index = 1, name = "InputGain" }`
  - natural alternative: `0.4` = `0.37777778506278992`
  - exact anchor: `0.6` = `0.40000000596046448`
  - natural alternative: `1.0` = `0.4444444477558136`

- `{ index = 2, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:3a7a721b898596a9b141d91b75182eaad2a354fccf4fde376a9c21cd179f41f1 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Little MicroShift product controls are 1 through 3. Do not write Bypass 0 or
host controls 4 through 6. Use the complete automatable Style map above.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve all
unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For subtle width, start with Style I or II and a low Mix. Style III is more
pronounced. Preserve Input Gain unless a level change is requested, and report
the chosen settings without claiming how they sound in context.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Little MicroShift -->

<!-- PLUGIN:Little Plate -->
<!-- SECTION-REVISION:ad3615e5181a361c473db816df8a0868f32640383a467b3fbacc12a78f29c0ed -->
## Little Plate

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-little-plate","display_name":"Little Plate","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys little plate","identifiers":{"add_by_name":["VST3: Little Plate","VST3: Little Plate (Soundtoys)"],"aliases":["little plate","soundtoys little plate","VST3: Little Plate","VST3: Little Plate (Soundtoys)"],"curated":["Little Plate"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-little-plate","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Little Plate","loaded_name":"VST3: Little Plate (Soundtoys)","parameter_count":{"mode":"exact","value":8},"required_parameters":[{"index":1,"name":"Mix","section":"","section_required":false},{"index":2,"name":"Decay","section":"","section_required":false},{"index":3,"name":"Low Cut","section":"","section_required":false},{"index":4,"name":"Mod Enable","section":"","section_required":false}],"observed_fingerprint_sha256":"c9ea83b8c2911f1daab2610eca2b57fd54a51cd885befb027ccb60f2a529b1e8"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/little-plate/","document_title":"Little Plate Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"c9ea83b8c2911f1daab2610eca2b57fd54a51cd885befb027ccb60f2a529b1e8","body_sha256":"03a982e86a36a0c112c7e86f2063b43f4d789d25dd9c0b1f4a393998c86e6abe"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:dd7ab32ce7f0e78c147d473e8acd45446057188daa86903f6589195232a56aa4 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "Mod Enable" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 2, name = "Decay" }`: `3.48` = `0.39986962080001831`
- `{ index = 3, name = "Low Cut" }`: `209` = `0.59984362125396729`
- `{ index = 4, name = "Mod Enable" }`: `On` = `1`

Calibrated natural value ladders:

- `{ index = 1, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 2, name = "Decay" }`
  - natural alternative: `3.08` = `0.37470433115959167`
  - exact anchor: `3.48` = `0.39986962080001831`
  - natural alternative: `4.44` = `0.45007994771003723`

- `{ index = 3, name = "Low Cut" }`
  - natural alternative: `172` = `0.55003821849822998`
  - exact anchor: `209` = `0.59984362125396729`
  - natural alternative: `231` = `0.62542718648910522`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:779791d6b15415fa1bd10a9a4c8b87def0fdf20c7a584597a106815ead9fa1b6 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

The installed VST3 has product controls Mix 1, Decay 2, Low Cut 3 and Mod
Enable 4. Do not write plug-in Bypass 0 or host controls 5 through 7. Use the
complete automatable menu map above for Mod Enable.


Resolve every target before the first write. Use literal `mapped[N]` setter
arguments, one Undo block and exactly one `reaper.defer` callback. Preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Little Plate models a plate reverb with optional tail modulation. A restrained
vocal start uses 20 to 30 percent Mix, a short Decay, some Low Cut and Mod On.
Do not claim the reverb fits the source without listening.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Little Plate -->

<!-- PLUGIN:Little PrimalTap -->
<!-- SECTION-REVISION:fe34294afa0e7e8bcf3724d366c2494bfcadc979195b8cfb2a6cdc6d2d714207 -->
## Little PrimalTap

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-little-primaltap","display_name":"Little PrimalTap","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys little primaltap","identifiers":{"add_by_name":["VST3: Little PrimalTap","VST3: Little PrimalTap (Soundtoys)"],"aliases":["little primaltap","little primal tap","soundtoys little primaltap","VST3: Little PrimalTap","VST3: Little PrimalTap (Soundtoys)"],"curated":["Little PrimalTap"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-little-primaltap","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[5],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Little PrimalTap","loaded_name":"VST3: Little PrimalTap (Soundtoys)","parameter_count":{"mode":"exact","value":10},"required_parameters":[{"index":1,"name":"Time","section":"","section_required":false},{"index":3,"name":"Multiply","section":"","section_required":false},{"index":5,"name":"Feedback","section":"","section_required":false},{"index":6,"name":"Mix","section":"","section_required":false}],"observed_fingerprint_sha256":"b0f08b21d6e44ea83957344632fdd2bc9fe58be40aa50c0a67a8161ad16359ad"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/little-primaltap/","document_title":"Little PrimalTap Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"b0f08b21d6e44ea83957344632fdd2bc9fe58be40aa50c0a67a8161ad16359ad","body_sha256":"e28d034c47a678bd5ec9d4cfaaf65caf7239d5bd24ef4405af569833e811eeea"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:c2c07502344a36a8fb77470e559f25324431b890efe367790fb2d5212b33c0a9 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 3, name = "Multiply" }`
  - `1x` = `0`
  - `2x` = `0.3333333432674408`
  - `4x` = `0.66666668653488159`
  - `8x` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Time" }`: `204` = `0.40019568800926208`
- `{ index = 2, name = "Adjust" }`: `0.758` = `0.39973023533821106`
- `{ index = 3, name = "Multiply" }`: `2x` = `0.3333333432674408`
- `{ index = 4, name = "InputGain" }`: `8.0` = `0.25`
- `{ index = 5, name = "Feedback" }`: `31.3` = `0.25040000677108765`
- `{ index = 6, name = "Mix" }`: `25.0` = `0.25`

Calibrated natural value ladders:

- `{ index = 1, name = "Time" }`
  - natural alternative: `192` = `0.3747553825378418`
  - exact anchor: `204` = `0.40019568800926208`
  - natural alternative: `230` = `0.45009785890579224`

- `{ index = 2, name = "Adjust" }`
  - natural alternative: `0.771` = `0.37519723176956177`
  - exact anchor: `0.758` = `0.39973023533821106`
  - natural alternative: `0.732` = `0.45008444786071777`

- `{ index = 4, name = "InputGain" }`
  - natural alternative: `6.4` = `0.20000000298023224`
  - exact anchor: `8.0` = `0.25`
  - natural alternative: `9.6` = `0.30000001192092896`

- `{ index = 5, name = "Feedback" }`
  - natural alternative: `25.0` = `0.20000000298023224`
  - exact anchor: `31.3` = `0.25040000677108765`
  - natural alternative: `37.5` = `0.30000001192092896`

- `{ index = 6, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:f447bc5c32a9e42a2cf5d49e865df003e65d61fa129d79b500f129915f29838c -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Little PrimalTap product controls are 1 through 6. Do not write Bypass 0 or
host controls 7 through 9. Use the complete automatable Multiply map above.


Feedback can become unstable at high values. Keep it below 40% for unheard
audio unless the user explicitly asks for more. Resolve all targets before
writing, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a restrained lo-fi slap, use a short Time, 1x or 2x Multiply, modest
Feedback and a low Mix. Adjust changes the old-hardware timing character, so
preserve it unless the request calls for that behavior.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Little PrimalTap -->

<!-- PLUGIN:Little Radiator -->
<!-- SECTION-REVISION:78cb0fd9bd1fccfa4ad9452dae4e281f1debf1349240e1f01766ef44d3c4b5b7 -->
## Little Radiator

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-little-radiator","display_name":"Little Radiator","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys little radiator","identifiers":{"add_by_name":["VST3: Little Radiator","VST3: Little Radiator (Soundtoys)"],"aliases":["little radiator","soundtoys little radiator","VST3: Little Radiator","VST3: Little Radiator (Soundtoys)"],"curated":["Little Radiator"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":[]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-little-radiator","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Little Radiator","loaded_name":"VST3: Little Radiator (Soundtoys)","parameter_count":{"mode":"exact","value":8},"required_parameters":[{"index":1,"name":"Heat","section":"","section_required":false},{"index":2,"name":"Mix","section":"","section_required":false},{"index":3,"name":"Bias","section":"","section_required":false},{"index":4,"name":"Noise","section":"","section_required":false}],"observed_fingerprint_sha256":"2f4c4f63a0ecad68e0db852f3ee1164281fa966c16ffbab8916fbcdd3ab32c07"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/little-radiator/","document_title":"Little Radiator Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"2f4c4f63a0ecad68e0db852f3ee1164281fa966c16ffbab8916fbcdd3ab32c07","body_sha256":"4accdf3e922146d661a1ab0d7aafcb6bcc7e68657df79c1ecb5ad2abd6da158f"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:20f0c9107578008b78b5149b62a98302e729d0c0b6fae3a15d92ab1c5ce742df -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 3, name = "Bias" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 4, name = "Noise" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Heat" }`: `3.00` = `0.60000002384185791`
- `{ index = 2, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 3, name = "Bias" }`: `Off` = `0`
- `{ index = 4, name = "Noise" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 1, name = "Heat" }`
  - natural alternative: `1.50` = `0.55000001192092896`
  - exact anchor: `3.00` = `0.60000002384185791`
  - natural alternative: `3.75` = `0.625`

- `{ index = 2, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:c2e70edb4cd5d1a59deb1195cf80374a6f26e83b477203c21fa80b7b5bd1e9cc -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Little Radiator product controls are 1 through 4. Do not write Bypass 0 or host
controls 5 through 7. Use the complete automatable menu map above for Bias and
Noise.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Bias changes the distortion behavior, and
Noise deliberately adds noise. Preserve both unless requested. Verify delayed
readback and preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For subtle warmth, use low positive Heat, a moderate Mix, Bias Off and Noise
Off. Raise Heat or enable Bias only when more obvious saturation is requested.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Little Radiator -->

<!-- PLUGIN:MicroShift -->
<!-- SECTION-REVISION:ea9a5e5b09a837177fd97f769bc824ed35fb46ea2c3c582d505801cdf7668f2b -->
## MicroShift

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-microshift","display_name":"MicroShift","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys microshift","identifiers":{"add_by_name":["VST3: MicroShift","VST3: MicroShift (Soundtoys)"],"aliases":["microshift","micro shift","soundtoys microshift","VST3: MicroShift","VST3: MicroShift (Soundtoys)"],"curated":["MicroShift"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["microshift"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-microshift","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: MicroShift","loaded_name":"VST3: MicroShift (Soundtoys)","parameter_count":{"mode":"exact","value":10},"required_parameters":[{"index":1,"name":"Mix","section":"","section_required":false},{"index":3,"name":"Detune","section":"","section_required":false},{"index":5,"name":"Focus","section":"","section_required":false},{"index":6,"name":"Style","section":"","section_required":false}],"observed_fingerprint_sha256":"64cbde7f06b4b800819731dbdf0e96b406e0cd2e81b741c5ce1b06bdf32afb80"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/wp-content/uploads/MicroShift-Manual.pdf","document_title":"MicroShift User's Guide Version 5","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"64cbde7f06b4b800819731dbdf0e96b406e0cd2e81b741c5ce1b06bdf32afb80","body_sha256":"598a0cafa1f6ddc2a056a5a8aab0117005dd554d5d53706a1cbd92de8abcf9ca"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:e0ff77b8fc6067f900fcec3447081b4b09a62b084c7ed2bd194099ed6b75cc43 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 6, name = "Style" }`
  - `I` = `0`
  - `II` = `0.5`
  - `III` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 2, name = "InputGain" }`: `0.6` = `0.40000000596046448`
- `{ index = 3, name = "Detune" }`: `87.1` = `0.40037232637405396`
- `{ index = 4, name = "Delay" }`: `87.1` = `0.40037232637405396`
- `{ index = 5, name = "Focus" }`: `240.2` = `0.39998331665992737`
- `{ index = 6, name = "Style" }`: `II` = `0.5`

Calibrated natural value ladders:

- `{ index = 1, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 2, name = "InputGain" }`
  - natural alternative: `0.4` = `0.37777778506278992`
  - exact anchor: `0.6` = `0.40000000596046448`
  - natural alternative: `1.0` = `0.4444444477558136`

- `{ index = 3, name = "Detune" }`
  - natural alternative: `84.1` = `0.37508884072303772`
  - exact anchor: `87.1` = `0.40037232637405396`
  - natural alternative: `93.3` = `0.44997450709342957`

- `{ index = 4, name = "Delay" }`
  - natural alternative: `84.1` = `0.37508884072303772`
  - exact anchor: `87.1` = `0.40037232637405396`
  - natural alternative: `93.3` = `0.44997450709342957`

- `{ index = 5, name = "Focus" }`
  - natural alternative: `205.7` = `0.37503355741500854`
  - exact anchor: `240.2` = `0.39998331665992737`
  - natural alternative: `327.8` = `0.45001572370529175`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:f88be1b7606ad3c4787fc7b009ef7c11dd815dd7e496095e2b90efbd3441c33f -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Product controls are Mix 1, InputGain 2, Detune 3, Delay 4, Focus 5 and Style
6. Do not write Bypass 0 or host controls 7 through 9. Use the complete
automatable Style map above.


Resolve all targets first. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed formatted readback and
preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
MicroShift creates stereo width through detune and changing delay. For subtle
vocal width, keep Mix near 20 to 30 percent, keep Detune and Delay below their
100 percent defaults and use Focus to protect low frequencies. All three styles
are valid colors; do not claim one is best without listening.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:MicroShift -->

<!-- PLUGIN:PanMan -->
<!-- SECTION-REVISION:ee32da0c6de5241225652ef6dbbffc79b8f94f17b59fefec837e921eb9d795b7 -->
## PanMan

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-panman","display_name":"PanMan","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys panman","identifiers":{"add_by_name":["VST3: PanMan","VST3: PanMan (Soundtoys)"],"aliases":["panman","pan man","soundtoys panman","VST3: PanMan","VST3: PanMan (Soundtoys)"],"curated":["PanMan"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["panman"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-panman","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: PanMan","loaded_name":"VST3: PanMan (Soundtoys)","parameter_count":{"mode":"exact","value":19},"required_parameters":[{"index":3,"name":"Mix","section":"","section_required":false},{"index":4,"name":"InOutMode","section":"","section_required":false},{"index":5,"name":"Rate","section":"","section_required":false},{"index":7,"name":"Width","section":"","section_required":false},{"index":14,"name":"ManualTrigger","section":"","section_required":false}],"observed_fingerprint_sha256":"f6b45d4c8e18cd3ae4bdf27bf5f766c8f9d636cf7b8c87178ed63e8d7b0c8c16"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/panman/","document_title":"PanMan Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"f6b45d4c8e18cd3ae4bdf27bf5f766c8f9d636cf7b8c87178ed63e8d7b0c8c16","body_sha256":"21de7c4e15a1be79d8b1b879ff7ae2a2cef6c06a25803088df35eb2e08fc0064"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:6f68c36233096c515927ca889a03f80a523a00f171e8d1741959ed1ed7dc6aa2 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 14, name = "ManualTrigger" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 4, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 5, name = "Rate" }`: `0.1585` = `0.40000975131988525`
- `{ index = 6, name = "Offset" }`: `0.00` = `0.5`
- `{ index = 7, name = "Width" }`: `126.00` = `0.60000002384185791`
- `{ index = 8, name = "Smoothing" }`: `0.25` = `0.25`
- `{ index = 14, name = "ManualTrigger" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

- `{ index = 5, name = "Rate" }`
  - natural alternative: `0.1334` = `0.37505194544792175`
  - exact anchor: `0.1585` = `0.40000975131988525`
  - natural alternative: `0.2239` = `0.4500180184841156`

- `{ index = 6, name = "Offset" }`
  - natural alternative: `-10.50` = `0.44999998807907104`
  - exact anchor: `0.00` = `0.5`
  - natural alternative: `10.50` = `0.55000001192092896`

- `{ index = 7, name = "Width" }`
  - natural alternative: `115.50` = `0.55000001192092896`
  - exact anchor: `126.00` = `0.60000002384185791`
  - natural alternative: `131.25` = `0.625`

- `{ index = 8, name = "Smoothing" }`
  - natural alternative: `0.20` = `0.20000000298023224`
  - exact anchor: `0.25` = `0.25`
  - natural alternative: `0.30` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:ad0e8b2eb6ded2be6b6322dfb2cb92347fa09720cad8dd0e84c26922e146793b -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

PanMan product controls are 1 through 15. Do not write Bypass 0 or host
controls 16 through 18. Use the complete automatable menu map above for
InOutMode and ManualTrigger.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve
unrelated controls. PanMan's six operating modes and rhythm editor are not
host-exposed. Do not claim to set them through parameter automation.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For slow restrained movement, use a low Rate, moderate Width and Mix, and some
Smoothing. The hidden operating mode and rhythm editor must be set manually in
the plug-in when the request depends on them.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:PanMan -->

<!-- PLUGIN:PhaseMistress -->
<!-- SECTION-REVISION:434748b652e1ec7ac57387e14f6cd43763ccfcb67fbaed606f94335d0f0083be -->
## PhaseMistress

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-phasemistress","display_name":"PhaseMistress","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys phasemistress","identifiers":{"add_by_name":["VST3: PhaseMistress","VST3: PhaseMistress (Soundtoys)"],"aliases":["phasemistress","phase mistress","soundtoys phasemistress","VST3: PhaseMistress","VST3: PhaseMistress (Soundtoys)"],"curated":["PhaseMistress"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["phasemistress"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-phasemistress","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[6],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: PhaseMistress","loaded_name":"VST3: PhaseMistress (Soundtoys)","parameter_count":{"mode":"exact","value":16},"required_parameters":[{"index":3,"name":"Mix","section":"","section_required":false},{"index":4,"name":"InOutMode","section":"","section_required":false},{"index":5,"name":"Frequency","section":"","section_required":false},{"index":8,"name":"ModulationDepth","section":"","section_required":false},{"index":9,"name":"Style","section":"","section_required":false},{"index":12,"name":"LFO Rate","section":"","section_required":false}],"observed_fingerprint_sha256":"2994deeef08533300bd79adefabac68bf9029865fb3ca15b010f1f9addd92993"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/phasemistress/","document_title":"PhaseMistress Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"2994deeef08533300bd79adefabac68bf9029865fb3ca15b010f1f9addd92993","body_sha256":"b267820acb38b5167600d5047de6900923369f1046c8c706dc2b77a413624531"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:9d87a8ecc0509a1a4bd93a9d07cfe6279ab71272f924128ce14898389df45270 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 4, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 9, name = "Style" }`
  - `Super 12` = `0`
  - `Super 8` = `0.014705882407724857`
  - `Super 7x5L` = `0.029411764815449715`
  - `Super 7x5` = `0.044117648154497147`
  - `Super 7-1` = `0.058823529630899429`
  - `Super 7` = `0.07352941483259201`
  - `Super 6` = `0.088235296308994293`
  - `Super 5-` = `0.10294117778539658`
  - `Super 5` = `0.11764705926179886`
  - `Super 4` = `0.13235294818878174`
  - `Super 3-` = `0.14705882966518402`
  - `Super 3` = `0.1617647111415863`
  - `Super 2` = `0.17647059261798859`
  - `Rezo 6 Hi` = `0.19117647409439087`
  - `Rezo 6 Mid` = `0.20588235557079315`
  - `Rezo 7 Low` = `0.22058823704719543`
  - `Rezo 6 Low` = `0.23529411852359772`
  - `PM 24` = `0.25`
  - `PM 23x12` = `0.26470589637756348`
  - `PM 16` = `0.27941176295280457`
  - `PM 12x10` = `0.29411765933036804`
  - `PM 12` = `0.30882352590560913`
  - `PM 11x6` = `0.32352942228317261`
  - `PM 11` = `0.3382352888584137`
  - `PM 8x6` = `0.35294118523597717`
  - `PM 8` = `0.36764705181121826`
  - `PM 7x15` = `0.38235294818878174`
  - `PM 7x5` = `0.39705881476402283`
  - `PM 7x3` = `0.4117647111415863`
  - `PM 6x9` = `0.42647057771682739`
  - `PM 6 Peak` = `0.44117647409439087`
  - `PM 6` = `0.45588234066963196`
  - `PM 5x6` = `0.47058823704719543`
  - `PM 5 High` = `0.48529410362243652`
  - `PM 4x2` = `0.5`
  - `PM 4` = `0.51470589637756348`
  - `PM 3x17` = `0.52941179275512695`
  - `PM 3x14` = `0.54411762952804565`
  - `PM 2x4` = `0.55882352590560913`
  - `PM 2` = `0.57352942228317261`
  - `Classic 12` = `0.58823531866073608`
  - `Classic 9` = `0.60294115543365479`
  - `Classic 7` = `0.61764705181121826`
  - `Classic 6` = `0.63235294818878174`
  - `Classic 5` = `0.64705884456634521`
  - `Classic 4` = `0.66176468133926392`
  - `Classic 3` = `0.67647057771682739`
  - `Classic 2` = `0.69117647409439087`
  - `WishWash` = `0.70588237047195435`
  - `Vacuum` = `0.72058820724487305`
  - `ThinMan` = `0.73529410362243652`
  - `ThinFace` = `0.75`
  - `The Trine` = `0.76470589637756348`
  - `Squeezer` = `0.77941179275512695`
  - `SeeSaw` = `0.79411762952804565`
  - `Scoopy` = `0.80882352590560913`
  - `Primes` = `0.82352942228317261`
  - `Phase 90` = `0.83823531866073608`
  - `PhaseJet 4` = `0.85294115543365479`
  - `OuterIn` = `0.86764705181121826`
  - `HiWay` = `0.88235294818878174`
  - `FoogerOog` = `0.89705884456634521`
  - `FatFace` = `0.91176468133926392`
  - `FatBottom` = `0.92647057771682739`
  - `DOD 201` = `0.94117647409439087`
  - `Breath 4` = `0.95588237047195435`
  - `BiPhase` = `0.97058820724487305`
  - `Basement` = `0.98529410362243652`
  - `Custom` = `1`

- `{ index = 10, name = "Trigger" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 4, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 5, name = "Frequency" }`: `138` = `0.40002360939979553`
- `{ index = 6, name = "Resonance" }`: `7.2` = `0.40000000596046448`
- `{ index = 8, name = "ModulationDepth" }`: `0.400` = `0.40000000596046448`
- `{ index = 9, name = "Style" }`: `Phase 90` = `0.83823531866073608`
- `{ index = 10, name = "Trigger" }`: `Off` = `0`
- `{ index = 12, name = "LFO Rate" }`: `0.58` = `0.40002995729446411`

Calibrated natural value ladders:

- `{ index = 3, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

- `{ index = 5, name = "Frequency" }`
  - natural alternative: `112` = `0.37485438585281372`
  - exact anchor: `138` = `0.40002360939979553`
  - natural alternative: `209` = `0.45006921887397766`

- `{ index = 6, name = "Resonance" }`
  - natural alternative: `5.3` = `0.33214285969734192`
  - natural alternative: `6.5` = `0.375`
  - exact anchor: `7.2` = `0.40000000596046448`

- `{ index = 8, name = "ModulationDepth" }`
  - natural alternative: `0.375` = `0.375`
  - exact anchor: `0.400` = `0.40000000596046448`
  - natural alternative: `0.450` = `0.44999998807907104`

- `{ index = 12, name = "LFO Rate" }`
  - natural alternative: `0.45` = `0.37502780556678772`
  - exact anchor: `0.58` = `0.40002995729446411`
  - natural alternative: `0.96` = `0.44967406988143921`

Certified natural menu alternative:
- `9 Style`: `Classic 4` = `0.66176468133926392`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:467b58d7ae6a6dd2a2e5f6315b42abb6e88b4203fcdbc5a69402d3184cd4c294 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

PhaseMistress product controls are 1 through 12. Do not write Bypass 0 or host
controls 13 through 15. Use the complete automatable menu map above, including
all 69 measured Style states.

Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Keep resonance conservative, verify delayed readback and
preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a slow smooth sweep, use a Classic style, low LFO Rate, moderate Depth and
Mix, and restrained Resonance. Style names encode different phaser structures,
so choose the requested name exactly and report the setting without claiming
how it sounds in context.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:PhaseMistress -->

<!-- PLUGIN:PrimalTap -->
<!-- SECTION-REVISION:b4d1fdb6c40a0da0e75527ddc8b7e6c052268ccb4a04237d9c73e90b662461e2 -->
## PrimalTap

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-primaltap","display_name":"PrimalTap","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys primaltap","identifiers":{"add_by_name":["VST3: PrimalTap","VST3: PrimalTap (Soundtoys)"],"aliases":["primaltap","primal tap","soundtoys primaltap","VST3: PrimalTap","VST3: PrimalTap (Soundtoys)"],"curated":["PrimalTap"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["primaltap"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-primaltap","safety":{"settle_ms":100,"heavy_selectors":[19],"unsafe_to_sweep":[12,13,19],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: PrimalTap","loaded_name":"VST3: PrimalTap (Soundtoys)","parameter_count":{"mode":"exact","value":36},"required_parameters":[{"index":1,"name":"AB_Link","section":"","section_required":false},{"index":2,"name":"Sync_Mode_A","section":"","section_required":false},{"index":5,"name":"Beats_A","section":"","section_required":false},{"index":9,"name":"Multiply","section":"","section_required":false},{"index":11,"name":"Algorithm","section":"","section_required":false},{"index":12,"name":"Feedback_A","section":"","section_required":false},{"index":16,"name":"Mix","section":"","section_required":false},{"index":19,"name":"Freeze","section":"","section_required":false},{"index":31,"name":"VCO_Shape","section":"","section_required":false}],"observed_fingerprint_sha256":"dc2d51e534c89212c8a5b5ce684a51529db02cc6d51aa7ffdb75a3859aa16a6b"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/primaltap/","document_title":"PrimalTap Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"dc2d51e534c89212c8a5b5ce684a51529db02cc6d51aa7ffdb75a3859aa16a6b","body_sha256":"6db22f3fc205ea2c11aa9ee45af109eb0f3cb18096ede1c567fbab7efb809962"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:f04176dafaedae7974d3bf7afa9e43f8776cca34463e8ec0c1c2499ac3b6ba5e -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 1, name = "AB_Link" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 2, name = "Sync_Mode_A" }`
  - `TIME` = `0`
  - `BEATS` = `1`

- `{ index = 3, name = "Sync_Mode_B" }`
  - `TIME` = `0`
  - `BEATS` = `1`

- `{ index = 9, name = "Multiply" }`
  - `1x` = `0`
  - `2x` = `0.3333333432674408`
  - `4x` = `0.66666668653488159`
  - `8x` = `1`

- `{ index = 11, name = "Algorithm" }`
  - `Classic` = `0`
  - `Parallel` = `0.20000000298023224`
  - `Reverb` = `0.40000000596046448`
  - `Series` = `0.60000002384185791`
  - `CrissCross` = `0.80000001192092896`
  - `Ping-Pong` = `1`

- `{ index = 19, name = "Freeze" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 20, name = "Rolloff_Mode" }`
  - `Feedback` = `0`
  - `Output` = `1`

- `{ index = 25, name = "Output_Polarity_A" }`
  - `Positive` = `0`
  - `Negative` = `1`

- `{ index = 26, name = "Output_Polarity_B" }`
  - `Positive` = `0`
  - `Negative` = `1`

- `{ index = 29, name = "VCO_Polarity_A" }`
  - `Positive` = `0`
  - `Negative` = `1`

- `{ index = 30, name = "VCO_Polarity_B" }`
  - `Positive` = `0`
  - `Negative` = `1`

- `{ index = 31, name = "VCO_Shape" }`
  - `Triangle` = `0`
  - `Square` = `0.25`
  - `Sine` = `0.5`
  - `RampUp` = `0.75`
  - `RampDown` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "AB_Link" }`: `On` = `1`
- `{ index = 2, name = "Sync_Mode_A" }`: `BEATS` = `1`
- `{ index = 3, name = "Sync_Mode_B" }`: `BEATS` = `1`
- `{ index = 5, name = "Beats_A" }`: `1.0000` = `0.25`
- `{ index = 7, name = "Beats_B" }`: `1.0000` = `0.25`
- `{ index = 9, name = "Multiply" }`: `2x` = `0.3333333432674408`
- `{ index = 11, name = "Algorithm" }`: `Parallel` = `0.20000000298023224`
- `{ index = 12, name = "Feedback_A" }`: `20.0` = `0.40000000596046448`
- `{ index = 13, name = "Feedback_B" }`: `20.0` = `0.40000000596046448`
- `{ index = 16, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 19, name = "Freeze" }`: `Off` = `0`
- `{ index = 20, name = "Rolloff_Mode" }`: `Feedback` = `0`
- `{ index = 31, name = "VCO_Shape" }`: `Sine` = `0.5`

Calibrated natural value ladders:

- `{ index = 5, name = "Beats_A" }`
  - natural alternative: `0.8000` = `0.20000000298023224`
  - exact anchor: `1.0000` = `0.25`
  - natural alternative: `1.2000` = `0.30000001192092896`

- `{ index = 7, name = "Beats_B" }`
  - natural alternative: `0.8000` = `0.20000000298023224`
  - exact anchor: `1.0000` = `0.25`
  - natural alternative: `1.2000` = `0.30000001192092896`

- `{ index = 12, name = "Feedback_A" }`
  - natural alternative: `13.9` = `0.33346664905548096`
  - natural alternative: `17.6` = `0.37523326277732849`
  - exact anchor: `20.0` = `0.40000000596046448`

- `{ index = 13, name = "Feedback_B" }`
  - natural alternative: `13.9` = `0.33346664905548096`
  - natural alternative: `17.6` = `0.37523326277732849`
  - exact anchor: `20.0` = `0.40000000596046448`

- `{ index = 16, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:8b72d42933000fa54d31ca277e89507acb790ef5c8e583f5fd7388aa3f679064 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

PrimalTap product controls are 1 through 32. Do not write Bypass 0 or host
controls 33 through 35. The complete stepped menus are:

Freeze and high Feedback can sustain audio indefinitely. Keep Freeze Off and
both Feedback values at or below 35% for unheard audio unless explicitly
requested. Resolve every target before writing, use literal `mapped[N]`
setters, one Undo block and exactly one `reaper.defer` callback. Link A and B before
writing both tap settings. Verify delayed readback and preserve unrelated
controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a restrained linked stereo echo, use Beats mode, Link On, a low Multiply,
Parallel or Classic algorithm, moderate Feedback and low Mix. Freeze is an
intentional hold effect and should stay Off for ordinary echo requests.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:PrimalTap -->

<!-- PLUGIN:Radiator -->
<!-- SECTION-REVISION:1ea67024b4471a6a877b3aef0ac782be258498334b6de4cdf4a5fc529ad882a9 -->
## Radiator

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-radiator","display_name":"Radiator","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys radiator","identifiers":{"add_by_name":["VST3: Radiator","VST3: Radiator (Soundtoys)"],"aliases":["radiator","soundtoys radiator","VST3: Radiator","VST3: Radiator (Soundtoys)"],"curated":["Radiator"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["radiator"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-radiator","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Radiator","loaded_name":"VST3: Radiator (Soundtoys)","parameter_count":{"mode":"exact","value":11},"required_parameters":[{"index":1,"name":"Bass","section":"","section_required":false},{"index":2,"name":"Treble","section":"","section_required":false},{"index":3,"name":"Input","section":"","section_required":false},{"index":4,"name":"Output","section":"","section_required":false},{"index":5,"name":"Mix","section":"","section_required":false},{"index":6,"name":"MicLine","section":"","section_required":false},{"index":7,"name":"Noise","section":"","section_required":false}],"observed_fingerprint_sha256":"3f2d76fffbbae1e24bc12a76ebd8f2b2b90df71025447699fa2b4024d93f1eb8"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/radiator/","document_title":"Radiator Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"3f2d76fffbbae1e24bc12a76ebd8f2b2b90df71025447699fa2b4024d93f1eb8","body_sha256":"37c66d99ed0d8fa59d67f10418774a018d86eebe26ec7bd93cc207830b723bb9"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:738f7b130ffa63ee28ad8109409bcdc8b7304f212f258adba89c865124194ef6 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 6, name = "MicLine" }`
  - `LINE` = `0`
  - `MIC` = `1`

- `{ index = 7, name = "Noise" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Bass" }`: `2.0` = `0.60000002384185791`
- `{ index = 2, name = "Treble" }`: `-2.0` = `0.40000000596046448`
- `{ index = 3, name = "Input" }`: `3.00` = `0.60000002384185791`
- `{ index = 4, name = "Output" }`: `-3.00` = `0.40000000596046448`
- `{ index = 5, name = "Mix" }`: `40.0` = `0.40000000596046448`
- `{ index = 6, name = "MicLine" }`: `MIC` = `1`
- `{ index = 7, name = "Noise" }`: `Off` = `0`

Calibrated natural value ladders:

- `{ index = 1, name = "Bass" }`
  - natural alternative: `1.0` = `0.55000001192092896`
  - exact anchor: `2.0` = `0.60000002384185791`
  - natural alternative: `2.5` = `0.625`

- `{ index = 2, name = "Treble" }`
  - natural alternative: `-2.5` = `0.375`
  - exact anchor: `-2.0` = `0.40000000596046448`
  - natural alternative: `-1.0` = `0.44999998807907104`

- `{ index = 3, name = "Input" }`
  - natural alternative: `1.50` = `0.55000001192092896`
  - exact anchor: `3.00` = `0.60000002384185791`
  - natural alternative: `3.75` = `0.625`

- `{ index = 4, name = "Output" }`
  - natural alternative: `-3.75` = `0.375`
  - exact anchor: `-3.00` = `0.40000000596046448`
  - natural alternative: `-1.50` = `0.44999998807907104`

- `{ index = 5, name = "Mix" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:b542523b1065f725e185dfee623f7fb5a06e692df48bf3c49dc39dbb66d44212 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Radiator product controls are 1 through 7. Do not write Bypass 0 or host
controls 8 through 10. Use the complete automatable menu map above for MicLine
and Noise.


Input and Output interact with saturation and level. When adding Input drive,
use Output compensation when requested and preserve the user's gain structure.
Resolve all targets before writing, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve
unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For subtle warmth, use modest Input, compensating Output, a moderate Mix and
Noise Off. MIC is more colored than LINE. Preserve the tone controls unless a
specific balance is requested.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Radiator -->

<!-- PLUGIN:Sie-Q -->
<!-- SECTION-REVISION:1d3884a4babc53642daebe71b767194625ebf65bba1cc9df6849ee55993e8440 -->
## Sie-Q

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-sie-q","display_name":"Sie-Q","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys sie-q","identifiers":{"add_by_name":["VST3: Sie-Q","VST3: Sie-Q (Soundtoys)"],"aliases":["sie-q","sie q","soundtoys sie-q","VST3: Sie-Q","VST3: Sie-Q (Soundtoys)"],"curated":["Sie-Q"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["sie q"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-sie-q","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Sie-Q","loaded_name":"VST3: Sie-Q (Soundtoys)","parameter_count":{"mode":"exact","value":9},"required_parameters":[{"index":1,"name":"Low Gain","section":"","section_required":false},{"index":2,"name":"Mid Gain","section":"","section_required":false},{"index":3,"name":"Mid Frequency","section":"","section_required":false},{"index":4,"name":"High Gain","section":"","section_required":false},{"index":5,"name":"Drive","section":"","section_required":false}],"observed_fingerprint_sha256":"a812b84639025abf05d7b6007d944d33e1ccbdcb8472ded94a867e5831496a1e"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/sie-q/","document_title":"Sie-Q Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"a812b84639025abf05d7b6007d944d33e1ccbdcb8472ded94a867e5831496a1e","body_sha256":"98135fdda57026ccc5c217e61dbd3d3553633756695d71f5c4fdb819c3206dc5"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:77b20af0f8dda557620f974bb61c668cd9383935e93e853e454fd2f8fdc08c3d -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 3, name = "Mid Frequency" }`
  - `0.7 kHz` = `0`
  - `1.0 kHz` = `0.20000000298023224`
  - `1.5 kHz` = `0.40000000596046448`
  - `2.3 kHz` = `0.60000002384185791`
  - `3.5 kHz` = `0.80000001192092896`
  - `5.6 kHz` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Low Gain" }`: `3.0` = `0.60000002384185791`
- `{ index = 2, name = "Mid Gain" }`: `1.6` = `0.60000002384185791`
- `{ index = 3, name = "Mid Frequency" }`: `2.3 kHz` = `0.60000002384185791`
- `{ index = 4, name = "High Gain" }`: `3.0` = `0.60000002384185791`
- `{ index = 5, name = "Drive" }`: `3.0` = `0.60000002384185791`

Calibrated natural value ladders:

- `{ index = 1, name = "Low Gain" }`
  - natural alternative: `1.5` = `0.55000001192092896`
  - exact anchor: `3.0` = `0.60000002384185791`
  - natural alternative: `3.8` = `0.62666666507720947`

- `{ index = 2, name = "Mid Gain" }`
  - natural alternative: `0.8` = `0.55000001192092896`
  - exact anchor: `1.6` = `0.60000002384185791`
  - natural alternative: `2.0` = `0.625`

- `{ index = 4, name = "High Gain" }`
  - natural alternative: `1.5` = `0.55000001192092896`
  - exact anchor: `3.0` = `0.60000002384185791`
  - natural alternative: `3.8` = `0.62666666507720947`

- `{ index = 5, name = "Drive" }`
  - natural alternative: `1.5` = `0.55000001192092896`
  - exact anchor: `3.0` = `0.60000002384185791`
  - natural alternative: `3.8` = `0.62666666507720947`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:a6e953a3b3cfc8ef8eda11af17cccd6b30ce2736d58a5c9321135fb74dc625d7 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Sie-Q product controls are 1 through 5. Do not write Bypass 0 or host controls
6 through 8. Use the complete automatable Mid Frequency map above.


Resolve all targets before writing. Use the exact switched-frequency constants
in the certified map, literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback.
Verify delayed readback and preserve unrelated controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a gentle broad lift, use small boosts and modest Drive. Mid Frequency is a
six-position selector, so choose the nearest named position only when the user
does not specify one.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Sie-Q -->

<!-- PLUGIN:SpaceBlender -->
<!-- SECTION-REVISION:027469eeb551cd95894ff9422786893b809c08bcb5faf6f403333b0fcf08a4fe -->
## SpaceBlender

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-spaceblender","display_name":"SpaceBlender","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys spaceblender","identifiers":{"add_by_name":["VST3: SpaceBlender","VST3: SpaceBlender (Soundtoys)"],"aliases":["spaceblender","space blender","soundtoys spaceblender","VST3: SpaceBlender","VST3: SpaceBlender (Soundtoys)"],"curated":["SpaceBlender"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["spaceblender"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-spaceblender","safety":{"settle_ms":125,"heavy_selectors":[8,9],"unsafe_to_sweep":[8,9],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: SpaceBlender","loaded_name":"VST3: SpaceBlender (Soundtoys)","parameter_count":{"mode":"exact","value":15},"required_parameters":[{"index":1,"name":"Mix","section":"","section_required":false},{"index":2,"name":"SyncMode","section":"","section_required":false},{"index":4,"name":"Beats","section":"","section_required":false},{"index":5,"name":"Color","section":"","section_required":false},{"index":8,"name":"Warp","section":"","section_required":false},{"index":9,"name":"Freeze","section":"","section_required":false},{"index":10,"name":"ShapeX","section":"","section_required":false},{"index":11,"name":"ShapeY","section":"","section_required":false}],"observed_fingerprint_sha256":"2cad4f9e1a7b588a3b0b29f002d2ef63d79d167a76e9e1c330b2330e6083aa69"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/spaceBlender/","document_title":"SpaceBlender Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"2cad4f9e1a7b588a3b0b29f002d2ef63d79d167a76e9e1c330b2330e6083aa69","body_sha256":"5f83678328b7142c21f01fe6541d2a5160f2ce26cc7fd411d3059923ead75e59"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:4385c5fc9388f5530912ae5f3fe94fc878a1a9dabfe5ea9fd9b2f8cea8276acb -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 2, name = "SyncMode" }`
  - `Time` = `0`
  - `Beats` = `1`

- `{ index = 4, name = "Beats" }`
  - `1 beats` = `0`
  - `2 beats` = `0.032258063554763794`
  - `3 beats` = `0.064516127109527588`
  - `4 beats` = `0.096774190664291382`
  - `5 beats` = `0.12903225421905518`
  - `6 beats` = `0.16129031777381897`
  - `7 beats` = `0.19354838132858276`
  - `8 beats` = `0.22580644488334656`
  - `9 beats` = `0.25806450843811035`
  - `10 beats` = `0.29032257199287415`
  - `11 beats` = `0.32258063554763794`
  - `12 beats` = `0.35483869910240173`
  - `13 beats` = `0.38709676265716553`
  - `14 beats` = `0.41935482621192932`
  - `15 beats` = `0.45161288976669312`
  - `16 beats` = `0.48387095332145691`
  - `17 beats` = `0.5161290168762207`
  - `18 beats` = `0.54838711023330688`
  - `19 beats` = `0.58064514398574829`
  - `20 beats` = `0.61290323734283447`
  - `21 beats` = `0.64516127109527588`
  - `22 beats` = `0.67741936445236206`
  - `23 beats` = `0.70967739820480347`
  - `24 beats` = `0.74193549156188965`
  - `25 beats` = `0.77419352531433105`
  - `26 beats` = `0.80645161867141724`
  - `27 beats` = `0.83870965242385864`
  - `28 beats` = `0.87096774578094482`
  - `29 beats` = `0.90322577953338623`
  - `30 beats` = `0.93548387289047241`
  - `31 beats` = `0.96774190664291382`
  - `32 beats` = `1`

- `{ index = 8, name = "Warp" }`
  - `Off` = `0`
  - `On` = `1`

- `{ index = 9, name = "Freeze" }`
  - `Off` = `0`
  - `On` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 2, name = "SyncMode" }`: `Beats` = `1`
- `{ index = 4, name = "Beats" }`: `8` = `0.22580644488334656`
- `{ index = 5, name = "Color" }`: `-20.0` = `0.40000000596046448`
- `{ index = 6, name = "Mod" }`: `40.0` = `0.40000000596046448`
- `{ index = 7, name = "Texture" }`: `60.0` = `0.60000002384185791`
- `{ index = 8, name = "Warp" }`: `Off` = `0`
- `{ index = 9, name = "Freeze" }`: `Off` = `0`
- `{ index = 10, name = "ShapeX" }`: `0.40` = `0.40000000596046448`
- `{ index = 11, name = "ShapeY" }`: `0.60` = `0.60000002384185791`

Calibrated natural value ladders:

- `{ index = 1, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 5, name = "Color" }`
  - natural alternative: `-25.0` = `0.375`
  - exact anchor: `-20.0` = `0.40000000596046448`
  - natural alternative: `-10.0` = `0.44999998807907104`

- `{ index = 6, name = "Mod" }`
  - natural alternative: `37.5` = `0.375`
  - exact anchor: `40.0` = `0.40000000596046448`
  - natural alternative: `45.0` = `0.44999998807907104`

- `{ index = 7, name = "Texture" }`
  - natural alternative: `55.0` = `0.55000001192092896`
  - exact anchor: `60.0` = `0.60000002384185791`
  - natural alternative: `62.5` = `0.625`

- `{ index = 10, name = "ShapeX" }`
  - natural alternative: `0.38` = `0.37999999523162842`
  - exact anchor: `0.40` = `0.40000000596046448`
  - natural alternative: `0.45` = `0.44999998807907104`

- `{ index = 11, name = "ShapeY" }`
  - natural alternative: `0.55` = `0.55000001192092896`
  - exact anchor: `0.60` = `0.60000002384185791`
  - natural alternative: `0.63` = `0.62999999523162842`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:57d0ea803f81b65ae05da91be4c99c4c11a51a41851084a6b33958c1b18a6a7a -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

SpaceBlender product controls are 1 through 11. Do not write Bypass 0 or host
controls 12 through 14. Use the complete automatable menu map above, including
all 32 measured Beats states, SyncMode, Warp and Freeze.

Warp and Freeze can create sustained or discontinuous output. Keep both Off
for unheard audio unless explicitly requested. Resolve every target before
writing, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Set SyncMode before Beats. Verify delayed readback and preserve unrelated
controls.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a restrained dark evolving space, lower Color and Mix, use moderate Mod and
Texture, and keep Warp and Freeze Off. Shape X and Shape Y jointly select the
space character, so preserve both when the request does not mention them.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:SpaceBlender -->

<!-- PLUGIN:SuperPlate -->
<!-- SECTION-REVISION:400d4f7cf4c8d9a9b068457c12000817e26a5cd06bc897335f28ec221945a1c3 -->
## SuperPlate

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-superplate","display_name":"SuperPlate","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys superplate","identifiers":{"add_by_name":["VST3: SuperPlate","VST3: SuperPlate (Soundtoys)"],"aliases":["superplate","super plate","soundtoys superplate","VST3: SuperPlate","VST3: SuperPlate (Soundtoys)"],"curated":["SuperPlate"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["superplate"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-superplate","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: SuperPlate","loaded_name":"VST3: SuperPlate (Soundtoys)","parameter_count":{"mode":"exact","value":28},"required_parameters":[{"index":1,"name":"Plate Style","section":"","section_required":false},{"index":2,"name":"Analog Style","section":"","section_required":false},{"index":3,"name":"Decay","section":"","section_required":false},{"index":6,"name":"Mix","section":"","section_required":false},{"index":23,"name":"Low Cut Slope","section":"","section_required":false}],"observed_fingerprint_sha256":"d62bb89c771f1f07e0b17ca4a765adc082e7a1db7edb8938859384fedbc832ba"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/superplate/","document_title":"SuperPlate Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"d62bb89c771f1f07e0b17ca4a765adc082e7a1db7edb8938859384fedbc832ba","body_sha256":"a9bda7cd12a6664f84f4ff4a5913ccace10ccd6811c708bb3f4c45373403f6bb"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:3a8a067116ba1b1228cc366a65cc125d17145f29f141ccb9210ecb61dd9ef959 -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 1, name = "Plate Style" }`
  - `Stocktronics` = `0`
  - `E. Plate III` = `0.25`
  - `Audicon` = `0.5`
  - `Goldfoil 240` = `0.75`
  - `Classic 140` = `1`

- `{ index = 2, name = "Analog Style" }`
  - `Tube` = `0`
  - `Solid State` = `0.5`
  - `Clean` = `1`

- `{ index = 23, name = "Low Cut Slope" }`
  - `-6 dB` = `0`
  - `-12 dB` = `0.5`
  - `-24 dB` = `1`

- `{ index = 24, name = "High Cut Slope" }`
  - `-6 dB` = `0`
  - `-12 dB` = `0.5`
  - `-24 dB` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 1, name = "Plate Style" }`: `Goldfoil 240` = `0.75`
- `{ index = 2, name = "Analog Style" }`: `Tube` = `0`
- `{ index = 3, name = "Decay" }`: `3.48` = `0.39986962080001831`
- `{ index = 4, name = "PreDelay" }`: `63` = `0.25200000405311584`
- `{ index = 5, name = "Modulation" }`: `25` = `0.25`
- `{ index = 6, name = "Mix" }`: `25.0` = `0.25`
- `{ index = 9, name = "Low Cut" }`: `209` = `0.59984362125396729`
- `{ index = 10, name = "High Cut" }`: `6034` = `0.59999024868011475`
- `{ index = 23, name = "Low Cut Slope" }`: `-12 dB` = `0.5`
- `{ index = 24, name = "High Cut Slope" }`: `-12 dB` = `0.5`

Calibrated natural value ladders:

- `{ index = 3, name = "Decay" }`
  - natural alternative: `3.08` = `0.37470433115959167`
  - exact anchor: `3.48` = `0.39986962080001831`
  - natural alternative: `4.44` = `0.45007994771003723`

- `{ index = 4, name = "PreDelay" }`
  - natural alternative: `50` = `0.20000000298023224`
  - exact anchor: `63` = `0.25200000405311584`
  - natural alternative: `75` = `0.30000001192092896`

- `{ index = 5, name = "Modulation" }`
  - natural alternative: `20` = `0.20000000298023224`
  - exact anchor: `25` = `0.25`
  - natural alternative: `30` = `0.30000001192092896`

- `{ index = 6, name = "Mix" }`
  - natural alternative: `20.0` = `0.20000000298023224`
  - exact anchor: `25.0` = `0.25`
  - natural alternative: `30.0` = `0.30000001192092896`

- `{ index = 9, name = "Low Cut" }`
  - natural alternative: `172` = `0.55003821849822998`
  - exact anchor: `209` = `0.59984362125396729`
  - natural alternative: `231` = `0.62542718648910522`

- `{ index = 10, name = "High Cut" }`
  - natural alternative: `5195` = `0.5500146746635437`
  - exact anchor: `6034` = `0.59999024868011475`
  - natural alternative: `6503` = `0.62497693300247192`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:7b05d4d93331a14fe6fdc69a31d2c1baa8dd553d05be8313ea4de0acd531da3b -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

SuperPlate exposes product controls 1 through 24. Do not write Bypass 0 or host
controls 25 through 27. Use the complete automatable menu map above.

Decay can reach infinity. Use infinite decay only when explicitly requested.
Resolve all targets before writing, use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Preserve Auto-Decay, EQ and every
unrequested control.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
The five plate styles and three analog input styles are independent choices.
For a dark restrained vocal plate, Goldfoil 240, modest Decay and Mix, a short
PreDelay and filtered lows and highs are conservative starting settings. Tube
adds color; Clean avoids preamp coloration.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:SuperPlate -->

<!-- PLUGIN:Tremolator -->
<!-- SECTION-REVISION:cc1d85fcbd65923aad71f080e2c5d10cad4a8626d4b2e35f461dc023dbf61fad -->
## Tremolator

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"soundtoys-tremolator","display_name":"Tremolator","vendor":"Soundtoys","product_class":"ordinary","preference_type":"soundtoys tremolator","identifiers":{"add_by_name":["VST3: Tremolator","VST3: Tremolator (Soundtoys)"],"aliases":["tremolator","soundtoys tremolator","VST3: Tremolator","VST3: Tremolator (Soundtoys)"],"curated":["Tremolator"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["tremolator"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"soundtoys-tremolator","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Tremolator","loaded_name":"VST3: Tremolator (Soundtoys)","parameter_count":{"mode":"exact","value":19},"required_parameters":[{"index":3,"name":"InOutMode","section":"","section_required":false},{"index":4,"name":"Depth","section":"","section_required":false},{"index":5,"name":"Groove","section":"","section_required":false},{"index":6,"name":"Accent","section":"","section_required":false},{"index":7,"name":"Width","section":"","section_required":false},{"index":10,"name":"Threshold","section":"","section_required":false},{"index":13,"name":"EnvMode","section":"","section_required":false}],"observed_fingerprint_sha256":"5d4b5c61ecd7c045dcf621a01896b92abed649649291de2d9f7151071b6dc305"}],"status":"pilot","provenance":{"source":"https://www.soundtoys.com/product/tremolator/","document_title":"Tremolator Product Guide","product_version":"5.5.5 64 bit","verified_at":"2026-07-31","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"5d4b5c61ecd7c045dcf621a01896b92abed649649291de2d9f7151071b6dc305","body_sha256":"8230e63c2b04b528e8ce51548f2dddc9fe161420293aaf06157ed20a04dcd816"}}
```

<!-- CHUNK:control -->
<!-- SOUND TOYS CERTIFIED STORED VALUES -->
<!-- campaign_sha256:942f4dddd4fd0a9c5eb87e3dfc0c8337b388bb823497cf82024a39a4a2954ea4 receipt_sha256:e7825e3ab7fb578f31ca4c86aedb39658df80c52606741a6492350151e8cc6fe -->
### CERTIFIED STORED VALUES

These are the exact repeated live stored values for Soundtoys 5.5.5.
Use only these normalized constants for writes. Resolve every index and
name first, then verify Soundtoys delayed readback one REAPER frame later.
This section is complete for the listed host-exposed controls. Do not
request additional plug-in context before using its maps and ladders.
An existing-instance request with a session target hint is context-complete.
Generate the runnable script immediately. Do not emit ``context_needed``
for ``fx_chains``, ``fx_params``, ``docs`` or plug-in helper bundles.
This product is script-automatable for every listed control. Never
classify it as manual-only or substitute another product profile.
This certified block overrides generic ``fx_params`` scan formatter,
range and enum approximations. Resolve all targets together with
``reaassist_resolve_profile_params``. Write only through the returned
``mapped[N]`` indices and the exact normalized constants below. Never
use a local parameter finder, a direct numeric index, a range formula,
``set_param_display``, ``set_param_enum`` or ``set_param_enum_paced``
for profile-backed writes.
For a request that says the product already exists, use
``TrackFX_GetByName(..., false)`` only. Never call ``TrackFX_AddByName``.
If the lookup returns less than zero, show a clear error and return before
the resolver. Never wrap the writes in a silent ``if fx >= 0`` branch.
After resolving every target in one call, use the exact nil guard
``if not mapped then error(guard_err) end``. Do not add a fallback
message, wrapper or alternate condition to that guard.
Every ``index`` below is already the exact zero-based REAPER host index.
Copy it unchanged and never subtract one. Each ``name`` is exact and does
not include the index number. Copy the resolver object literally.
For a compound action, use exactly one ``reaper.defer`` callback for the
resolver and every mapped setter. Do not schedule a second callback.
Use one Undo block inside that callback and call ``reaper.UpdateArrange()``
immediately after ``reaper.Undo_EndBlock(...)``. ReaAssist commits the
isolated normalized targets and verifies their live delayed readback before
it reports completion.

Complete automatable menu map:

- `{ index = 3, name = "InOutMode" }`
  - `Digital` = `0`
  - `Analog` = `1`

- `{ index = 13, name = "EnvMode" }`
  - `Envelope` = `0`
  - `Gate` = `1`

Intent gate: use the exact recipe anchors only when the user supplies
explicit numeric or named values. For a natural-language request with
no supplied values, choose only measured ladder rungs for requested
continuous controls and use at least one natural alternative. Copy the
selected rung normalized constant exactly and never shorten it.

Explicit-value exact recipe anchors:
- `{ index = 3, name = "InOutMode" }`: `Analog` = `1`
- `{ index = 4, name = "Depth" }`: `0.40` = `0.40000000596046448`
- `{ index = 5, name = "Groove" }`: `-0.05` = `0.40000000596046448`
- `{ index = 6, name = "Accent" }`: `-4.00` = `0.40000000596046448`
- `{ index = 7, name = "Width" }`: `40` = `0.40000000596046448`
- `{ index = 10, name = "Threshold" }`: `-48.00` = `0.40000000596046448`
- `{ index = 11, name = "Attack" }`: `7.6` = `0.40026083588600159`
- `{ index = 12, name = "Release" }`: `66.0` = `0.60003447532653809`
- `{ index = 13, name = "EnvMode" }`: `Envelope` = `0`

Calibrated natural value ladders:

- `{ index = 4, name = "Depth" }`
  - natural alternative: `0.38` = `0.37999999523162842`
  - exact anchor: `0.40` = `0.40000000596046448`
  - natural alternative: `0.45` = `0.44999998807907104`

- `{ index = 5, name = "Groove" }`
  - natural alternative: `-0.06` = `0.37999999523162842`
  - exact anchor: `-0.05` = `0.40000000596046448`
  - natural alternative: `-0.03` = `0.43999999761581421`

- `{ index = 6, name = "Accent" }`
  - natural alternative: `-5.00` = `0.375`
  - exact anchor: `-4.00` = `0.40000000596046448`
  - natural alternative: `-2.00` = `0.44999998807907104`

- `{ index = 7, name = "Width" }`
  - natural alternative: `38` = `0.37999999523162842`
  - exact anchor: `40` = `0.40000000596046448`
  - natural alternative: `45` = `0.44999998807907104`

- `{ index = 10, name = "Threshold" }`
  - natural alternative: `-50.00` = `0.375`
  - exact anchor: `-48.00` = `0.40000000596046448`
  - natural alternative: `-44.00` = `0.44999998807907104`

- `{ index = 11, name = "Attack" }`
  - natural alternative: `5.8` = `0.37527969479560852`
  - exact anchor: `7.6` = `0.40026083588600159`
  - natural alternative: `13.0` = `0.44987377524375916`

- `{ index = 12, name = "Release" }`
  - natural alternative: `38.4` = `0.54997825622558594`
  - exact anchor: `66.0` = `0.60003447532653809`
  - natural alternative: `86.5` = `0.62503403425216675`

Natural-intent rule: choose only from the exact ladder values above.
Use at least one natural alternative so the complete result differs from
the explicit-value recipe. Never compute, round or
interpolate a normalized value. Preserve
unrequested controls and describe unheard-audio settings as a starting point.
<!-- ladder_evidence_sha256:a67b3eb1bedf0f106ece560ddc30b1733407e4d2ce97c6948e93ce7630b1bec6 receipt_sha256:5e8c6a0ac437e2086eb10a6943ca1c27344197b8f451e953f88a1f8b05ca6330 -->
<!-- /SOUND TOYS CERTIFIED STORED VALUES -->

Tremolator product controls are 1 through 15. Do not write Bypass 0 or host
controls 16 through 18. Use the complete automatable menu map above for
InOutMode and EnvMode.


Resolve all targets before writing. Use literal `mapped[N]` setters, one Undo block and exactly one `reaper.defer` callback. Verify delayed readback and preserve
unrelated controls. Tremolator's full operating-mode selector, waveshape editor
and rhythm editor are not host-exposed. Do not claim to set them through
parameter automation.
End the deferred callback with `reaper.UpdateArrange()` immediately after `reaper.Undo_EndBlock(...)`. This flush is required for Soundtoys state to
survive Redo and save/reload.
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For gentle smooth movement, use moderate Depth and Width, Envelope mode, a
soft Accent and conservative dynamics settings. Rhythmic patterns and custom
waveshapes must be set manually in the plug-in when the request depends on
those hidden editors.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:Tremolator -->

<!-- PLUGIN:ValhallaDelay -->
<!-- SECTION-REVISION:ce74f0b5c7e0ec04e685933007fcb0d867047b319c04b029fece2cd0a6d3ae25 -->
## ValhallaDelay

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"valhalla-delay","display_name":"ValhallaDelay","vendor":"Valhalla DSP","product_class":"ordinary","preference_type":"delay","identifiers":{"add_by_name":["VST3: ValhallaDelay","VST3: ValhallaDelay (Valhalla DSP, LLC)"],"aliases":["valhalladelay","valhalla delay","VST3: ValhallaDelay","VST3: ValhallaDelay (Valhalla DSP, LLC)"],"curated":["ValhallaDelay"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["valhalladelay"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"valhalla-delay","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[16],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: ValhallaDelay","loaded_name":"VST3: ValhallaDelay (Valhalla DSP, LLC)","parameter_count":{"mode":"exact","value":42},"required_parameters":[{"index":0,"name":"Mix","section":"","section_required":false},{"index":16,"name":"Feedback","section":"","section_required":false},{"index":32,"name":"Mode","section":"","section_required":false},{"index":33,"name":"Era","section":"","section_required":false}],"observed_fingerprint_sha256":"6145bd74ff72af1caab3f56f27a8e7c516f1df722865798177d74822bebce12f"}],"status":"pilot","provenance":{"source":"https://valhalladsp.com/2019/04/16/valhalladelay-the-controls/","migrated_at":"2026-07-30","body_sha256":"9b76f797c1c25b943643284c78a4af0801d9f7e9542a3c68ce0422f06f9ae09f","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"6145bd74ff72af1caab3f56f27a8e7c516f1df722865798177d74822bebce12f"}}
```

<!-- CHUNK:control -->
ValhallaDelay is a multi-mode delay with separate left and right timing,
feedback, filtering, modulation, diffusion and ducking. The installed VST3
exposes 42 parameters. Keep indices 38 through 41 unchanged unless the user
explicitly requests bypass, host wet or delta monitoring.

### PRIMARY CONTROLS

```
0 Mix        1 DelayStyle   2 DelayLSync   3 DelayLNote   4 DelayL_Ms
5 DelayRSync 6 DelayRNote   7 DelayR_Ms   16 Feedback    17 Width
18 DriveIn  19 Age         20 Diffusion   22 LowCut      23 HighCut
32 Mode     33 Era         34 Ducking
```

Timing controls are dependent. For `Msec`, set the matching `_Ms` control and
preserve Note. For tempo-note timing, set the matching Note control and
preserve `_Ms`. If the user requests one centered delay time, keep both sides
matched. Preserve separate left and right timing when refining an existing
stereo setup.

Feedback is unsafe to sweep. Use reviewed normalized anchors and keep unheard
starting points at or below 40.0 %. Mix should normally stay at or below
30.0 % on an insert. Use 100.0 % only on an explicitly identified return.

Resolve every requested name and index before the first write. For the
certified starting recipe, use the reviewed normalized anchors below. The
provenance validator must see each literal `mapped[N]` index at its setter call,
so do not place mapped indices in a target table, loop or wrapper. Use exactly
one `reaper.defer` callback and do not add a follow-up verification callback.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 0, name = "Mix" },
    { index = 1, name = "DelayStyle" },
    { index = 2, name = "DelayLSync" },
    { index = 4, name = "DelayL_Ms" },
    { index = 5, name = "DelayRSync" },
    { index = 7, name = "DelayR_Ms" },
    { index = 16, name = "Feedback" },
    { index = 23, name = "HighCut" },
    { index = 32, name = "Mode" },
    { index = 33, name = "Era" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.2) -- Mix 20.0 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.0) -- Single
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 0.25) -- Msec
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.3) -- 300.0 ms
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.25) -- Msec
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 0.3) -- 300.0 ms
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.15) -- 30.0 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 0.2421875) -- 5000 Hz
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9],
    0.0416666679084301) -- Tape
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10],
    0.3333333432674408) -- Past
  reaper.Undo_EndBlock("ReaAssist: set ValhallaDelay controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
For a dark restrained tape echo, start with Single style, matched 300 ms left
and right timing, Tape mode, Past era, 30.0 % Feedback, a 5000 Hz HighCut and
20.0 % Mix. Keep modulation and diffusion unchanged unless requested.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:ValhallaDelay -->

<!-- PLUGIN:ValhallaVintageVerb -->
<!-- SECTION-REVISION:386d39136e05f449951994d942035e78f3c1fd746a04a715b2cb10471a9b4c91 -->
## ValhallaVintageVerb

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"valhalla-vintage-verb","display_name":"ValhallaVintageVerb","vendor":"Valhalla DSP","product_class":"ordinary","preference_type":"reverb","identifiers":{"add_by_name":["VST3: ValhallaVintageVerb","VST3: ValhallaVintageVerb (Valhalla DSP, LLC)"],"aliases":["valhallavintageverb","valhalla vintage verb","vintageverb","VST3: ValhallaVintageVerb","VST3: ValhallaVintageVerb (Valhalla DSP, LLC)"],"curated":["ValhallaVintageVerb"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["valhallavintageverb","vintageverb"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"valhalla-vintage-verb","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: ValhallaVintageVerb","loaded_name":"VST3: ValhallaVintageVerb (Valhalla DSP, LLC)","parameter_count":{"mode":"exact","value":21},"required_parameters":[{"index":0,"name":"Mix","section":"","section_required":false},{"index":12,"name":"ModDepth","section":"","section_required":false},{"index":15,"name":"ColorMode","section":"","section_required":false},{"index":16,"name":"ReverbMode","section":"","section_required":false}],"observed_fingerprint_sha256":"e9e5ec6ca0ca2a3fd0e9cab0286d9d048712ce9614a69ceb56be576f700e6352"}],"status":"pilot","provenance":{"source":"https://valhalladsp.com/shop/reverb/valhalla-vintage-verb/","migrated_at":"2026-07-30","body_sha256":"c2b3f96bfc8e135a86a151ac4adfd305460d707c6588d00a236c298fc0915ee8","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"e9e5ec6ca0ca2a3fd0e9cab0286d9d048712ce9614a69ceb56be576f700e6352"}}
```

<!-- CHUNK:control -->
ValhallaVintageVerb is an algorithmic reverb with selectable reverb modes and
three color eras. The installed VST3 exposes 21 parameters. Keep plug-in and
host controls at indices 17 through 20 unchanged unless explicitly requested.

### PRIMARY CONTROLS

```
0 Mix            1 PreDelay       2 Decay          3 Size
4 Attack         5 BassMult       6 BassXover      7 HighShelf
8 HighFreq       9 EarlyDiffusion 10 LateDiffusion 11 ModRate
12 ModDepth     13 HighCut       14 LowCut        15 ColorMode
16 ReverbMode
```

Resolve each requested index and name before the first write. Use the reviewed
normalized anchors below for the certified recipe. The provenance validator
must see every literal `mapped[N]` index at its setter call, so do not put
mapped indices in a target table, loop or wrapper. Use exactly one
`reaper.defer` callback and no follow-up verification callback. For an insert,
start with Mix at or below 25.0 %. Use 100.0 % only when the user explicitly
identifies a dedicated reverb return.

For an explicit `100.0 %` Mix request on a dedicated return, write exactly
`1.0` to Mix index 0. Do not substitute `0.5`, which displays `50.0 %`.

A conservative vocal plate starting point is Plate mode, eighties color,
1.50 s Decay, 25.00 ms PreDelay, 8000 Hz HighCut, 150 Hz LowCut and 20.0 % Mix.
Keep modulation and diffusion at their existing settings unless requested.
These settings require listening before they can be called correct for the
source.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 0, name = "Mix" },
    { index = 1, name = "PreDelay" },
    { index = 2, name = "Decay" },
    { index = 13, name = "HighCut" },
    { index = 14, name = "LowCut" },
    { index = 15, name = "ColorMode" },
    { index = 16, name = "ReverbMode" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1],
    0.2001953125) -- Mix 20.0 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2],
    0.27520751953125) -- PreDelay 25.00 ms
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3],
    0.3056640625) -- Decay 1.50 s
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4],
    0.59033203125) -- HighCut 8000 Hz
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5],
    0.09375) -- LowCut 150 Hz
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6],
    0.66666668653488) -- eighties
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7],
    0.08333333581686) -- Plate
  reaper.Undo_EndBlock("ReaAssist: set ValhallaVintageVerb controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Use shorter decay and restrained mix for a vocal or drum insert. Use longer
decay only when the user requests a wash or large ambient tail. Preserve the
existing reverb mode when refining an instance unless a mode change is part of
the request.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:ValhallaVintageVerb -->

<!-- PLUGIN:RC-20 Retro Color -->
<!-- SECTION-REVISION:b7a56743f1daaa3320d7e6cd052003fca5bc72dc7890c30c7daf3064166bc440 -->
## RC-20 Retro Color

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"xln-rc-20-retro-color","display_name":"RC-20 Retro Color","vendor":"XLN Audio","product_class":"ordinary","preference_type":"saturation","identifiers":{"add_by_name":["VST3: RC-20 Retro Color","VST3: RC-20 Retro Color (XLN Audio)"],"aliases":["rc-20","rc 20","rc20","rc-20 retro color","retro color","VST3: RC-20 Retro Color","VST3: RC-20 Retro Color (XLN Audio)"],"curated":["RC-20 Retro Color"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["rc 20","rc20"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"xln-rc-20-retro-color","safety":{"settle_ms":150,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: RC-20 Retro Color","loaded_name":"VST3: RC-20 Retro Color (XLN Audio)","parameter_count":{"mode":"exact","value":2142},"required_parameters":[{"index":0,"name":"Magnitude","section":"","section_required":false},{"index":21,"name":"DIST Enable","section":"","section_required":false},{"index":56,"name":"MAST Out Width","section":"","section_required":false},{"index":57,"name":"MAST Out Gain","section":"","section_required":false}],"observed_fingerprint_sha256":"a55f878ac6f29700a72fc1180c3b4cfd495a5abbea452c0efbaf0bd489d0378d"}],"status":"pilot","provenance":{"source":"https://assets.xlnaudio.com/documents/rc-20-retro-color_manual.pdf","migrated_at":"2026-07-30","body_sha256":"06ba4de1e95559de1341cb2844736258d56aa0ef8b1f81a239d850a009a32356","verified_at":"2026-07-30","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"a55f878ac6f29700a72fc1180c3b4cfd495a5abbea452c0efbaf0bd489d0378d"}}
```

<!-- CHUNK:control -->
RC-20 Retro Color is a creative texture effect with six modules: Noise,
Wobble, Distort, Digital, Space and Magnetic. The installed VST3 exposes 2,142
host parameters. Only indices 0 through 58 are the product control surface.
Indices 59 through 2141 are MIDI CC and host rows. Never use those rows for an
RC-20 musical request.

### SAFE PRIMARY SURFACE

```
0 Magnitude       1 NOIS Amount      2 WOBB Amount      3 DIST Amount
4 DIGI Amount     5 SPAC Amount      6 MAGN Amount      7 NOIS Enable
8 NOIS Type       9 NOIS Tone       14 WOBB Enable     21 DIST Enable
22 DIST Type     27 DIGI Enable     35 SPAC Enable     42 MAGN Enable
48 MAST In Gain  49 MAST EQ Enable 54 MAST EQ Tone    56 MAST Out Width
57 MAST Out Gain 58 Bypass
```

Magnitude scales the configured module effect. Preserve it on an existing
instance unless the user asks for the global amount. Preserve module type and
secondary controls unless they are part of the request. Resolve the complete
target set first, then use the reviewed normalized anchors below. The
provenance validator must see every literal `mapped[N]` index at its setter
call, so do not place mapped indices in a target table, loop or wrapper. Use
exactly one `reaper.defer` callback and no follow-up verification callback.
Do not define or call `set_param_display` or `set_param_enum` for this recipe.
When the request says RC-20 already exists, reuse it and do not add another
instance.

For subtle vintage texture on unheard material, start with Magnitude 60 %,
Noise 8 % On using VINYL 1, Wobble 5 % On, Distort 8 % On using TUBEPAIR,
Digital and Space Off, Magnetic 8 % On, Master output width 100 % and output
gain 0.0 dB. Keep Flux and detailed rate controls unchanged. The user should
listen and adjust module amounts.

```lua
reaper.defer(function()
  local mapped, guard_err = reaassist_resolve_profile_params(tr, fx, {
    { index = 0, name = "Magnitude" },
    { index = 1, name = "NOIS Amount" }, { index = 7, name = "NOIS Enable" },
    { index = 8, name = "NOIS Type" },
    { index = 2, name = "WOBB Amount" }, { index = 14, name = "WOBB Enable" },
    { index = 3, name = "DIST Amount" }, { index = 21, name = "DIST Enable" },
    { index = 22, name = "DIST Type" },
    { index = 27, name = "DIGI Enable" }, { index = 35, name = "SPAC Enable" },
    { index = 6, name = "MAGN Amount" }, { index = 42, name = "MAGN Enable" },
    { index = 56, name = "MAST Out Width" }, { index = 57, name = "MAST Out Gain" },
  })
  if not mapped then error(guard_err) end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[1], 0.6015625) -- 60 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[2], 0.078125) -- Noise 8 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[3], 1.0) -- Noise On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[4], 0.0) -- VINYL 1
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[5], 0.046875) -- Wobble 5 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[6], 1.0) -- Wobble On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[7], 0.078125) -- Distort 8 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[8], 1.0) -- Distort On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[9], 0.0) -- TUBEPAIR
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[10], 0.0) -- Digital Off
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[11], 0.0) -- Space Off
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[12], 0.078125) -- Magnetic 8 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[13], 1.0) -- Magnetic On
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[14], 0.5) -- Width 100 %
  reaper.TrackFX_SetParamNormalized(tr, fx, mapped[15], 0.5) -- Gain 0.0 dB
  reaper.Undo_EndBlock("ReaAssist: set RC-20 Retro Color controls", -1)
  reaper.UpdateArrange()
end)
```
<!-- /CHUNK:control -->

<!-- CHUNK:musical -->
Start with one or two modules when the user names a specific character. Use
more modules only for an explicit lo-fi or heavily degraded request. Keep
Digital and Space off for a subtle default. Preserve user-selected types and
Flux settings when refining an existing instance.
<!-- /CHUNK:musical -->
<!-- /PLUGIN:RC-20 Retro Color -->
