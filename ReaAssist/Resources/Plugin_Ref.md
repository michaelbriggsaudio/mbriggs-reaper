<!-- Plugin_Ref.md - markers are PLUGIN:Name (NOT SECTION:) because each block -->
<!-- is a typed, addressable plugin entry served as plugin_ref:Name. SECTION: -->
<!-- is reserved for generic on-demand buckets in API_Ref.md / Prompts.md.    -->
<!-- The two markers are deliberately distinct so the parser can tell plugin -->
<!-- entries apart from the ## sub-headings inside each plugin's body.       -->

# Plugin Parameter Reference

Curated parameter data for plugins ReaAssist supports first-class. Includes
REAPER's stock plugins (verified from live REAPER install via TrackFX_GetParamName
/ TrackFX_GetParam) and selected third-party plugins ReaAssist ships with or
recommends as fallbacks (e.g. ReEQ).

All param indices are 0-based. Use TrackFX_GetNumParams to confirm count at runtime.
Use TrackFX_AddByName(tr, "PluginName", false, -1) to add or find each plugin.

## ENUM PARAM NORMS: LIVE DATA OVERRIDES CURATED TABLES

Curated enum tables (STYLE / TYPE / MODE / etc.) and recipe norm literals
in this file are stamped against a specific plugin version. Vendors
reorder enums across updates -- the same literal norm can map to a
different display name on a different version, silently writing the
wrong setting.

Precedence when setting an enum param:

1. **Live `fx_params` `[enum: ...]` list** (if pinned) -- always wins.
   Find the named target's index in the live list and compute
   `norm = index / (count - 1)`. Do NOT copy a recipe's literal norm
   if it disagrees with live data.
2. **Curated per-plugin enum table** in this file -- fallback only when
   no live data exists (e.g. the plugin is being newly added this turn
   and no `fx_params:` / `fx_inspect:` bucket is pinned).
3. **Recipe norm literals** -- illustrative stamps that may drift.
   The `-- Style: NAME` comment is canonical intent; the number is the
   stamp. When the live enum and the curated table disagree, the
   curated table is wrong; defer to live.

Always cite the enum target *by name* in a comment alongside any enum
SetParamNormalized call (e.g. `-- Style: "Vocal"`, not just `-- 0.769`)
so the intent is auditable on review and the value is recomputable
when versions drift.

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

<!-- PLUGIN:ReaEQ -->
## ReaEQ

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
  Band 1 (Low Shelf):  ENABLED  -- default gain = 0dB (0.50)
  Band 2 (Band):       ENABLED  -- default gain = 0dB (0.50)
  Band 3 (Band):       ENABLED  -- default gain = 0dB (0.50)
  Band 4 (High Shelf): ENABLED  -- default gain = 0dB (0.50)
  Band 5 (High Pass):  DISABLED by default -- setting params has no audible effect
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
1    Gain-Low Shelf     0.25          0.0   1.0   Normalized: 0.50 = 0dB (default 0.25 = -6dB)
2    BW-Low Shelf       0.20          0.0   1.0   Bandwidth normalized

3    Freq-Band 2        0.2895        0.0   1.0   ~300Hz default
4    Gain-Band 2        0.25          0.0   1.0   0.50 = 0dB (default 0.25 = -6dB)
5    BW-Band 2          0.50          0.0   1.0

6    Freq-Band 3        0.4760        0.0   1.0   ~1kHz default
7    Gain-Band 3        0.25          0.0   1.0   0.50 = 0dB (default 0.25 = -6dB)
8    BW-Band 3          0.50          0.0   1.0

9    Freq-High Shelf 4  0.7394        0.0   1.0   ~5kHz default
10   Gain-High Shelf 4  0.25          0.0   1.0   0.50 = 0dB (default 0.25 = -6dB)
11   BW-High Shelf 4    0.20          0.0   1.0

12   Freq-High Pass 5   0.1414        0.0   1.0   ~100Hz default
13   Gain-High Pass 5   0.25          0.0   1.0   0.50 = 0dB (default 0.25 = -6dB)
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
  0.2500 = -6.0 dB  (THIS IS THE DEFAULT -- all bands default to -6dB, NOT flat)
  0.2813 = -5.0 dB
  0.3164 = -4.0 dB
  0.3555 = -3.0 dB
  0.3984 = -2.0 dB
  0.4453 = -1.0 dB
  0.5000 = 0.0 dB   (FLAT/UNITY -- use this when you want no gain change)
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

CRITICAL: 0.50 = 0dB (flat). 0.25 is the default value but it equals -6dB, NOT flat.
When you want a band to have no effect, set gain to 0.50, not 0.25.
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

All values use TrackFX_SetParamNormalized. 0.50 = 0dB (flat). See gain scale above.

**"Make it darker" -- cut the High Shelf (band 4):**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.72)  -- Freq: ~5kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.35)  -- Gain: -3dB cut
```

**"Make it brighter" -- boost the High Shelf (band 4):**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.72)  -- Freq: ~5kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.65)  -- Gain: +5.6dB boost
```

**"Add warmth" -- boost the Low Shelf (band 1):**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.27)   -- Freq: ~200Hz
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.60)   -- Gain: ~+3dB boost
```

**"Remove muddiness" -- cut the Low Shelf (band 1):**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.27)   -- Freq: ~200Hz
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.40)   -- Gain: ~-1.5dB cut
```

**"Remove rumble" -- raise the High Pass (band 5):**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 12, 0.27)  -- Freq: ~80Hz HP
  reaper.TrackFX_SetParamNormalized(tr, fx, 13, 0.50)  -- Gain: flat (0dB)
```

### FULL PATTERN (add ReaEQ and darken)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.72)  -- High Shelf freq ~5kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.35)  -- High Shelf gain: -3dB cut
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReaEQ: darken", -1)
end)
```

<!-- /PLUGIN:ReaEQ -->

<!-- PLUGIN:ReaComp -->
## ReaComp

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
  reaper.TrackFX_SetParam(tr, fx, 0, 0.125)  -- "set Threshold to -18 dB"
  reaper.TrackFX_SetParam(tr, fx, 0, 0.25)   -- "set Threshold to -12 dB"
  reaper.TrackFX_SetParam(tr, fx, 0, 0.5)    -- "set Threshold to -6 dB"
```

### RATIO SCALE

Param 1 (Ratio) normalized 0..1. Use TrackFX_SetParamNormalized.

```
  0.00 ~ 1:1    (no compression)
  0.03 ~ 4:1    (default, moderate)
  0.10 ~ 8:1    (heavy)
  0.20 ~ 20:1   (near limiting)
  1.00 ~ inf:1  (hard limiter)
```

### ATTACK / RELEASE SCALE

Both normalized 0..1. Use TrackFX_SetParamNormalized.

```
  Attack:   0.0=0ms  0.005=5ms  0.01=10ms  0.05=50ms  0.1=100ms  1.0=1000ms
  Release:  0.0=0ms  0.02=20ms  0.05=50ms  0.10=100ms 0.3=300ms  1.0=1000ms
```

### WET / DRY SCALE

Params 10 (Dry) and 11 (Wet) have range 0..2. Use TrackFX_SetParam (not normalized).

```
  0.0 = silence    1.0 = 0dB (unity)    2.0 = +6dB
```

Default: Dry=0 (off), Wet=1.0 (full wet). Leave at defaults for normal use.

### COMMON RECIPES

**"Gentle vocal/instrument compression":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.5)               -- Threshold: -6dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.03)    -- Ratio: ~4:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.01)    -- Attack: ~10ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.10)    -- Release: ~100ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.3)    -- Knee: soft
  reaper.TrackFX_SetParamNormalized(tr, fx, 15, 1.0)    -- Auto make-up gain on
```

**"Drum bus / transient punch":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.35)              -- Threshold: ~-9dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.10)    -- Ratio: ~8:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.003)   -- Attack: ~3ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.05)    -- Release: ~50ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.0)    -- Knee: hard
  reaper.TrackFX_SetParamNormalized(tr, fx, 15, 1.0)    -- Auto make-up gain on
```

**"Brick wall limiter":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.9)               -- Threshold: just under 0dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 1.0)     -- Ratio: inf:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.0)     -- Attack: 0ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.02)    -- Release: ~20ms
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
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.03)    -- Ratio: ~4:1
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.01)    -- Attack: ~10ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.10)    -- Release: ~100ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 14, 0.3)    -- Knee: soft
  reaper.TrackFX_SetParamNormalized(tr, fx, 15, 1.0)    -- Auto make-up gain on
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReaComp: gentle compression", -1)
end)
```

<!-- /PLUGIN:ReaComp -->

<!-- PLUGIN:ReaXcomp -->
## ReaXcomp

REAPER's stock multiband compressor. Fixed 4-band split with per-band threshold,
ratio, attack, release, knee, RMS, and make-up gain. Crossovers set by each
band's "top frequency". Use for multiband mastering, targeted frequency ducking,
or narrowband de-essing.

AddByName string: "ReaXcomp"
Total params (default instance): 50 (indices 0-49)

### CRITICAL CONSTRAINTS

1. **4 fixed bands.** Band count is hardcoded and cannot be changed via script.
   Use each band's `Active` param (offset +11) to bypass unused bands.

2. **Crossovers set by `N-Band top frequency`.** Band N covers from the top of
   band N-1 up to its own top freq. Band 4's top (default 24 kHz) is the
   overall upper limit.

3. **Gain and Threshold share the same dB scale** (-150..+12 dB, 0.5 = 0 dB).

4. **Attack and RMS share the same linear ms scale** (0..250 ms).

5. **All params use TrackFX_SetParamNormalized** (values 0..1). Do NOT use
   TrackFX_SetParam -- the raw ranges vary per param and aren't documented here.

### BAND LAYOUT

4 bands × 12 params = 48 band params, plus 2 globals (Bypass, Wet).

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
(heavy), 1.0 = 100:1 (near brick-wall). Useful targets:

```
1.5:1  ~ 0.307     4:1   ~ 0.377     10:1   ~ 0.47
2:1    ~ 0.325     6:1   ~ 0.42      20:1   ~ 0.57
3:1    ~ 0.355     8:1   ~ 0.45      inf:1  = 1.0
```

### KNEE SCALE (0..24 dB)

Piecewise: slider 0..0.5 linear to 0..6 dB; slider 0.5..1 linear to 6..24 dB.

```
slider   dB          slider   dB          slider   dB
-------  ------      -------  ------      -------  ------
0.00     0.00        0.35     4.20        0.70     13.20
0.05     0.60        0.40     4.80        0.75     15.00
0.10     1.20        0.45     5.40        0.80     16.80
0.15     1.80        0.50     6.00        0.85     18.60
0.20     2.40        0.55     7.80        0.90     20.40
0.25     3.00        0.60     9.60        0.95     22.20
0.30     3.60        0.65     11.40       1.00     24.00
```

### ATTACK / RMS SCALE (shared, 0..250 ms linear)

Attack (offset +5) and RMS (offset +7) share a simple linear scale.

```
slider   ms          slider   ms          slider   ms
-------  ----        -------  ----        -------  ----
0.00     0           0.35     87          0.70     175
0.05     12          0.40     100         0.75     187
0.10     25          0.45     112         0.80     200
0.15     37          0.50     125         0.85     212
0.20     50          0.55     137         0.90     225
0.25     62          0.60     150         0.95     237
0.30     75          0.65     162         1.00     250
```

Formula: slider = ms / 250. Defaults: Attack=15ms (slider 0.06), RMS=5ms (0.02).

### RELEASE SCALE (0..2000 ms, parabolic)

Quadratic taper -- more resolution at short release times.

```
slider   ms          slider   ms          slider   ms
-------  -----       -------  -----       -------  -----
0.00     0           0.35     244         0.70     979
0.05     5           0.40     320         0.75     1125
0.10     20          0.45     404         0.80     1280
0.15     45          0.50     500         0.85     1445
0.20     80          0.55     605         0.90     1619
0.25     125         0.60     720         0.95     1804
0.30     180         0.65     844         1.00     2000
```

Formula: ms = 2000 * slider^2. Slider = sqrt(ms / 2000).
Default 150 ms = slider ~0.274.

### COMMON RECIPES

**"Gentle mastering bus compression (all 4 bands, ~1dB GR each):"**

```lua
for band = 1, 4 do
  local base = (band - 1) * 12
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 2,  0.45)   -- Threshold: -0.9dB
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 3,  0.26)   -- Ratio: ~1.1:1
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 5,  0.04)   -- Attack: 10ms
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 6,  0.22)   -- Release: ~100ms
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 8,  1.0)    -- Make Up Gain ON
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 11, 1.0)    -- Active ON
end
```

**"Aggressive drum-bus glue (all bands, 3-4dB GR):"**

```lua
for band = 1, 4 do
  local base = (band - 1) * 12
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 2, 0.35)    -- Threshold: -3dB
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 3, 0.377)   -- Ratio: 4:1
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 5, 0.02)    -- Attack: 5ms
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 6, 0.158)   -- Release: ~50ms
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 8, 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, base + 11, 1.0)
end
```

### FULL PATTERN (add ReaXcomp, gentle mastering)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "ReaXcomp", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  for band = 1, 4 do
    local base = (band - 1) * 12
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 2,  0.45)
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 3,  0.26)
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 5,  0.04)
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 6,  0.22)
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 8,  1.0)
    reaper.TrackFX_SetParamNormalized(tr, fx, base + 11, 1.0)
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReaXcomp: gentle mastering compression", -1)
end)
```

<!-- /PLUGIN:ReaXcomp -->

<!-- PLUGIN:ReaGate -->
## ReaGate

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

Same linear amplitude scale as ReaComp param 0. Use TrackFX_SetParam (not normalized).
Default is 0.0 (-inf dB), meaning the gate is fully open by default.

```
  0.0   = -inf dB  (gate always open, default)
  0.063 = -24 dBFS
  0.125 = -18 dBFS
  0.25  = -12 dBFS
  0.5   = -6 dBFS
  1.0   = 0 dBFS
```

### COMMON RECIPES

**"Standard noise gate":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.125)             -- Threshold: -18dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.001)   -- Attack: ~1ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.05)    -- Release: ~50ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.01)    -- Hold: ~10ms
```

**"Drum gate (tight)":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.25)              -- Threshold: -12dBFS
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.0005)  -- Attack: <1ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.02)    -- Release: ~20ms
  reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.005)   -- Hold: ~5ms
```

<!-- /PLUGIN:ReaGate -->

<!-- PLUGIN:ReaDelay -->
## ReaDelay

AddByName string: "ReaDelay"
Total params (1-tap default): 15 (indices 0-14)

IMPORTANT: ReaDelay uses a per-tap structure. Default instance has 1 tap.
Adding taps in the UI adds params dynamically. All tap params are prefixed "N: "
where N is the tap number. Tap 1 params start at index 2.

### PARAM INDEX TABLE (verified, 1-tap instance)

```
idx  Name                  Default val   Min    Max    Notes
---  --------------------  -----------   -----  -----  ----------------------------
0    Wet                   0.5           0.0    2.0    Wet level: 0.5=-6dB
1    Dry                   1.0           0.0    2.0    Dry level: 1.0=0dB
2    1: Enabled            1.0           0.0    1.0    Tap 1 on/off
3    1: Length (time)       0.0           0.0    1.0    Delay in seconds (0=off)
4    1: Length (musical)    0.0078        0.0    1.0    Musical length (display: 2.00)
5    1: Feedback           0.0           0.0    2.0    Feedback: 0=off, 1.0=0dB
6    1: Lowpass            1.0           0.0    1.0    Filter normalized (20000Hz)
7    1: Hipass             0.0           0.0    1.0    Filter normalized (0Hz)
8    1: Resolution         1.0           0.0    1.0    Bit depth (display: 24)
9    1: Stereo width       1.0           0.0    1.0    1.0=full stereo
10   1: Volume             1.0           0.0    2.0    Tap volume: 1.0=0dB
11   1: Pan                0.5           0.0    1.0    Center=0.5
12   Bypass                0.0           0.0    1.0    1=bypassed
13   Wet                   1.0           0.0    1.0    Normalized duplicate of 0
14   Delta                 0.0           0.0    1.0    Delta monitoring toggle
```

### DELAY TIME

There are two length params per tap. Use "Length (musical)" for tempo-synced delay,
"Length (time)" for free time in seconds. To set a specific delay in ms, use
set_param_display on "Length (time)".

### COMMON RECIPE

**"Simple quarter-note echo":**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.25)    -- Wet: ~-12dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.25)    -- Feedback: ~-12dB
```

<!-- /PLUGIN:ReaDelay -->

<!-- PLUGIN:ReaLimit -->
## ReaLimit

AddByName string: "ReaLimit"
Total params: 6 (indices 0-5)

### PARAM INDEX TABLE (verified)

```
idx  Name        Default val   Min    Max    Notes
---  ----------  -----------   -----  -----  ----------------------------
0    Threshold   0.8333        0.0    1.0    Normalized (display: +0.00 dB)
1    Ceiling     1.0           0.0    1.0    Normalized (display: +0.00 dB)
2    Release     0.3548        0.0    1.0    Normalized (display: 15.0 ms)
3    Bypass      0.0           0.0    1.0    1=bypassed
4    Wet         1.0           0.0    1.0    1.0=fully wet
5    Delta       0.0           0.0    1.0    Delta monitoring toggle
```

### THRESHOLD / CEILING SCALE

Both are normalized 0..1. Use set_param_display with dB values for precision.
Threshold default 0.8333 = 0dB. Lower values = more limiting.
Ceiling default 1.0 = 0dB. Sets the output ceiling.

### COMMON RECIPE

**"Loud master (-1dB ceiling, -6dB threshold)":**

```lua
  -- Use set_param_display for precise dB targeting:
  set_param_display(tr, fx, 0, -6.0)   -- Threshold: -6dB
  set_param_display(tr, fx, 1, -1.0)   -- Ceiling: -1dB
```

<!-- /PLUGIN:ReaLimit -->

<!-- PLUGIN:ReaPitch -->
## ReaPitch

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
7    1: Formant adjust (full)    0.5       0.0    1.0    Formant: 0.5=no adjust
8    1: Formant adjust (cents)   0.5       0.0    1.0    Formant fine: 0.5=0
9    1: Formant adjust (semi)    0.5       0.0    1.0    Formant semitone: 0.5=0
10   1: Volume                   1.0       0.0    2.0    Shift volume: 1.0=0dB
11   1: Pan                      0.5       0.0    1.0    Center=0.5
12   Bypass                      0.0       0.0    1.0    1=bypassed
13   Wet                         1.0       0.0    1.0    Normalized duplicate of 0
14   Delta                       0.0       0.0    1.0    Delta monitoring toggle
```

### SHIFT PARAMS

Use "Shift (semitones)" for whole-semitone shifts, "Shift (cents)" for fine tuning.
Both are centered at 0.5 = no shift. Use set_param_display for precise values.

### COMMON RECIPE

**"Pitch up 1 octave":**

```lua
  set_param_display(tr, fx, 6, 1)    -- Shift (oct): +1
```

**"Detune effect (wet/dry blend)":**

```lua
  set_param_display(tr, fx, 4, 15)   -- Shift (cents): +15
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.5)  -- Wet: -6dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.5)  -- Dry: -6dB (blend)
```

<!-- /PLUGIN:ReaPitch -->

<!-- PLUGIN:ReaVerbate -->
## ReaVerbate

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
9    Wet         1.0           0.0    1.0    Normalized duplicate of 0
10   Delta       0.0           0.0    1.0    Delta monitoring toggle
```

### COMMON RECIPES

**"Small room ambience":**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.25)    -- Wet: ~-12dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.15)    -- Room size: small
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.7)     -- Dampening: high
```

**"Large hall":**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.35)    -- Wet: ~-9dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.8)     -- Room size: large
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.3)     -- Dampening: low
  reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.05)    -- Pre-delay: small
```

<!-- /PLUGIN:ReaVerbate -->

<!-- PLUGIN:ReaSynth -->
## ReaSynth

AddByName string: "ReaSynth"
Total params: 18 (indices 0-17)

NOTE: ReaSynth is a VSTi (instrument). Use TrackFX_AddByName(tr, "ReaSynth", false, -1)
to add it as an instrument. It responds to MIDI input.

### PARAM INDEX TABLE (verified)

```
idx  Name                                    Default   Min     Max    Notes
---  --------------------------------------  -------   ------  -----  -----------------------
0    Attack                                  0.006     0.0     10.0   Seconds (display: 3.0ms)
1    Release                                 0.0016    0.0     1.0    Seconds (display: 8ms)
2    Square mix                              0.0       0.0     1.0    0=off, 1=full
3    Saw mix                                 0.0       0.0     1.0    0=off, 1=full
4    Triangle mix                            0.0       0.0     1.0    0=off, 1=full
5    Volume                                  0.5012    0.0     2.0    Linear: 0.5=-6dB
6    Decay                                   0.0666    0.0     1.0    Seconds (display: 1000ms)
7    Extra sine mix                          0.0       0.0     1.0    Sub-oscillator: 0=off
8    Extra sine tuning                       0.5       0.0     1.0    Sub-osc tuning: 0.5=0
9    Sustain                                 1.0       0.0     2.0    Linear: 1.0=0dB
10   Pulse Width                             1.0       0.0     1.0    Square PW: 1.0=50%
11   Global detune                           0.5       0.0     1.0    0.5=no detune
12   Legacy oscillator mode                  0.0       0.0     1.0    Leave at 0
13   Portamento                              0.0       0.0     1.0    Glide: 0=off
14   Broken portamento extra sine osc        0.0       0.0     1.0    Leave at 0
15   Bypass                                  0.0       0.0     1.0    1=bypassed
16   Wet                                     1.0       0.0     1.0    1.0=fully wet
17   Delta                                   0.0       0.0     1.0    Delta monitoring toggle
```

### WAVEFORM MIXING

Default ReaSynth produces a sine wave (all mix params at 0). Mix in other waveforms
by setting Square/Saw/Triangle mix > 0. Values are additive.

### COMMON RECIPE

**"Basic saw synth pad":**

```lua
  reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.8)     -- Saw mix: 80%
  reaper.TrackFX_SetParam(tr, fx, 0, 0.1)               -- Attack: 100ms
  reaper.TrackFX_SetParam(tr, fx, 6, 0.5)               -- Decay: ~500ms
  reaper.TrackFX_SetParam(tr, fx, 9, 0.5)               -- Sustain: -6dB
  reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.1)     -- Release: 100ms
```

<!-- /PLUGIN:ReaSynth -->

<!-- PLUGIN:ReaTune -->
## ReaTune

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

<!-- /PLUGIN:ReaTune -->

<!-- PLUGIN:Deesser -->
## Deesser

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

<!-- /PLUGIN:Deesser -->

<!-- PLUGIN:Saturation -->
## Saturation

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

---

<!-- /PLUGIN:Saturation -->

<!-- PLUGIN:Chorus -->
## Chorus

Stock JSFX by Stillwell (chorus_stereo). True stereo chorus with tempo-sync option.
Bundled with REAPER; available in all installs.

AddByName string: "JS: SStillwell/chorus_stereo"  (also accepts "SStillwell/chorus_stereo")
Total params: 11 (8 sliders + Bypass/Wet/Delta meta)

### PARAM INDEX TABLE (verified from JSFX source)

```
idx  Name                        Default   Min     Max    Notes
---  --------------------------  --------  ------  -----  ----------------------------
0    Chorus Length (ms)          15        1       500    Delay line length
1    Number Of Voices            1         1       8      Voice count
2    Rate (Hz)                   0.5       0       16     LFO rate; 0 = tempo sync mode
3    Pitch Fudge Factor          0.7       0       1      Modulation depth
4    Wet Mix (dB)                -6        -100    12     Wet level in dB (-100 = off)
5    Dry Mix (dB)                -6        -100    12     Dry level in dB (-100 = off)
6    Channel Rate Offset (Hz)    0.0       -1      1      L/R rate detune for stereo width
7    Tempo Sync (fraction)       0.25      0.0625  4      Active when Rate=0 (1=whole, 0.25=quarter)
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

<!-- /PLUGIN:Chorus -->

<!-- PLUGIN:Phaser -->
## Phaser

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

### COMMON RECIPES

**"Slow sweeping phaser":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 0.3)     -- Rate: 0.3 Hz
  reaper.TrackFX_SetParam(tr, fx, 1, 300)     -- Min: 300 Hz
  reaper.TrackFX_SetParam(tr, fx, 2, 2500)    -- Max: 2.5 kHz
  reaper.TrackFX_SetParam(tr, fx, 3, -6)      -- Feedback: -6 dB
  reaper.TrackFX_SetParam(tr, fx, 4, -3)      -- Wet: -3 dB
```

**"Fast resonant phaser":**

```lua
  reaper.TrackFX_SetParam(tr, fx, 0, 3.5)     -- Rate: 3.5 Hz
  reaper.TrackFX_SetParam(tr, fx, 1, 500)     -- Min: 500 Hz
  reaper.TrackFX_SetParam(tr, fx, 2, 3500)    -- Max: 3.5 kHz
  reaper.TrackFX_SetParam(tr, fx, 3, -3)      -- Feedback: -3 dB (resonant)
  reaper.TrackFX_SetParam(tr, fx, 4, 0)       -- Wet: 0 dB
```

---

<!-- /PLUGIN:Phaser -->

<!-- PLUGIN:ReEQ -->
## ReEQ

Third-party JSFX EQ by Justin Johnson (MIT licensed). ReaAssist ships a bundled
copy and offers to install it as a fallback when no EQ preference is set.
ReEQ provides far better filter slopes than ReaEQ (6-96 dB/oct in 6 dB steps,
selectable per band) and is the recommended EQ for filter-heavy work.

AddByName string: "ReJJ/ReEQ/ReEQ.jsfx"  (full path required for JSFX)
Total params: 60 (57 sliders + Bypass/Wet/Delta)

### CRITICAL CONSTRAINTS

1. **Use TrackFX_SetParam (NOT SetParamNormalized) for all ReEQ params.**
   Param ranges are native (e.g. Frequency 0..100, Type 0..10, Gain -18..+18).
   The formulas below assume native values.

2. **Only the first 5 bands are script-controllable.**
   ReEQ supports up to 16 bands internally, but only bands 1-5 are exposed as
   sliders. Bands 6-16 exist in internal arrays accessible only via UI mouse
   interaction. If the user requests more than 5 bands, instruct them to add
   the additional bands manually in the ReEQ UI.

3. **Filter Type slider clamps at 10.** The slider declaration is `<0,10,1>` so
   types 11-13 (All Pass, Low Cut Analog, High Cut Analog) are NOT reachable
   via TrackFX_SetParam; any value > 10 is clamped to 10. Use only types 0-10.

4. **All bands default to Enabled=0 (Off).** A new ReEQ instance has every band
   disabled. To use a band, you MUST set its Enabled param to 2 before any
   other settings will be audible.

### BAND LAYOUT

5 script-controllable bands × 7 params per band = 35 band params, plus 17 global
params and 5 tail params, plus the standard Bypass/Wet/Delta (auto-added by REAPER).

Band N param indices (1-based N, 0-based param indices):

```
Formula: base = 17 + (N-1) * 7

Band N param            Index
---------------------   ---------
Filter{N} Mode (Enab)   base + 0
Filter{N} Group         base + 1
Filter{N} Type          base + 2
Filter{N} Frequency     base + 3
Filter{N} Gain          base + 4
Filter{N} Q             base + 5
Filter{N} Slope         base + 6

Band 1: indices 17-23
Band 2: indices 24-30
Band 3: indices 31-37
Band 4: indices 38-44
Band 5: indices 45-51
```

### PER-BAND PARAM TABLE

```
Param        Min    Max    Step  Notes
-----------  -----  -----  ----  ---------------------------------------------
Mode (Enab)  0      2      1     0=Off, 1=Disabled (bypassed), 2=Enabled
Group        0      4      1     0=Stereo, 1=Mid, 2=Side, 3=Left, 4=Right
Type         0      10     1     See FILTER TYPES below (script-accessible only)
Frequency    0.0    100.0  0.01  Normalized log scale, see FREQUENCY FORMULA
Gain         -18.0  18.0   0.01  Direct dB. Used by Peak/Shelf/Tilt/Pultec types
Q            0.0    100.0  0.01  Normalized log scale, see Q FORMULA
Slope        0      15     1     dB/oct = (slope+1) * 6. See SLOPE TABLE
```

### FILTER TYPES (script-accessible: 0-10 only)

```
Value  Name                       Use
-----  -------------------------  --------------------------------------------
0      Peak                       Bell EQ (uses Gain + Q)
1      Low Cut                    HPF (uses Slope; Q affects resonance)
2      Low Cut (Butterworth)      HPF, Butterworth response (uses Slope)
3      Low Shelf                  Low shelf (uses Gain + Q for slope)
4      High Shelf                 High shelf (uses Gain + Q for slope)
5      High Cut                   LPF (uses Slope; Q affects resonance)
6      High Cut (Butterworth)     LPF, Butterworth response (uses Slope)
7      Notch                      Narrow cut (uses Q)
8      Band Pass                  Isolate a band (uses Q)
9      Tilt Shelf                 Tonal tilt around the freq (uses Gain)
10     Pultec Low Shelf           Pultec-style low shelf (uses Gain)
```

NOT accessible via script (slider clamps to 10; instruct user to set manually
in the ReEQ UI if these are required):

```
11     All Pass
12     Low Cut Analog
13     High Cut Analog
```

### FREQUENCY FORMULA (slider 0..100 → Hz, log scale)

ReEQ's Frequency slider is a normalized log mapping over 10 Hz..22050 Hz,
sample-rate independent. Use the formulas; do not interpolate from samples.

```
Hz from slider:   Hz     = 10 * exp(7.698484 * slider / 100)
Slider from Hz:   slider = 100 * ln(Hz / 10) / 7.698484

Constants: MIN_FREQ = 10 Hz, MAX_FREQ = 22050 Hz, FREQ_LOG_MAX = ln(2205) ≈ 7.698484
Valid Hz range: 10..22050 (clamp inputs accordingly)

PRECISION: Use the FULL constant 7.698484 (NOT 7.698). At high frequencies the
exponential amplifies tiny constant errors -- e.g. slider 95.7 with constant
7.698 gives 15.83 kHz, but with 7.698484 gives ~16.0 kHz. Always carry at least
4 significant figures in the slider value (e.g. 95.83, not 95.8).

The slider's step is 0.01, so exact frequencies near the top of the range may
not be reachable -- e.g. 16 kHz lies between sliders 95.83 and 95.84. The
recipe values below are the closest snap point to each target.
```

Reference values (computed from precise formula, verified against plugin):

```
Hz       Slider       Hz       Slider       Hz       Slider
-----    -------      -----    -------      -----    -------
20       9.00         500      50.82        5000     80.73
50       20.91        1000     59.82        10000    89.73
100      29.91        2000     68.82        15000    95.00
250      41.81        3000     74.09        20000    98.73
```

### Q FORMULA (slider 0..100 → Q, log scale)

ReEQ's Q slider is a normalized log mapping over 0.1..40, sample-rate independent.

```
Q from slider:    Q      = 0.1 * exp(5.99146 * slider / 100)
Slider from Q:    slider = 100 * ln(Q / 0.1) / 5.99146

Constants: MIN_Q = 0.1, MAX_Q = 40, Q_LOG_MAX = ln(400) ≈ 5.99146
Valid Q range: 0.1..40 (clamp inputs accordingly)
```

Reference values (computed from precise formula, verified against plugin):

```
Q       Slider       Q       Slider
-----   -------      -----   -------
0.1     0.00         2.0     50.00
0.5     26.86        4.0     61.58
0.707   32.65  ← Butterworth (default)
1.0     38.43        10.0    76.86
1.41    44.17        20.0    88.43
                     40.0    100.00
```

### SLOPE TABLE (cut filters only; types 1, 2, 5, 6)

```
Slope  dB/oct      Slope  dB/oct
-----  -------     -----  -------
0      6           8      54
1      12          9      60
2      18          10     66
3      24          11     72
4      30          12     78
5      36          13     84
6      42          14     90
7      48          15     96

Formula: dB/oct = (slope + 1) * 6
```

Slope is ignored for Peak, Notch, Band Pass, Pultec; set to 0 for these.
Shelf types (Low/High Shelf, Tilt) use Gain + Q for shape; Slope is ignored.

### GLOBAL PARAMS (rarely needed for typical EQ work)

```
idx  Name              Range          Notes
---  ----------------  -------------  -------------------------------------
0    Stereo Mode       0..1           0=Mid/Side, 1=Left/Right
1    Quality           0..1           0=Eco, 1=HQ
2    Gain              -136..30 dB    Master output gain (direct dB)
3    Mid/Left Gain     -136..30 dB    Per-channel gain
4    Side/Right Gain   -136..30 dB    Per-channel gain
5    Scale             0..200         Display scale (UI only)
6    Spectrum          0..6           Spectrum analyzer source (UI only)
7    Display           0..2           Spectrum display style (UI only)
8    Ceiling           0..2           Spectrum ceiling (UI only)
9    Floor             0..2           Spectrum floor (UI only)
10   Tilt              0..4           Spectrum tilt compensation (UI only)
11   Type              0..3           Spectrum window function (UI only)
12   Block Size        0..3           Spectrum FFT size (UI only)
13   Show Piano        0..1           UI only
14   Show Peaks        0..1           UI only
15   Show Pre-EQ       0..1           UI only
16   dB Range          0..4           UI only
```

### TAIL PARAMS

```
idx  Name              Range  Notes
---  ----------------  -----  -------------------------------------
52   Mid Polarity      0..1   0=normal, 1=inverted
53   Side Polarity     0..1   0=normal, 1=inverted
54   Limit Output      0..1   Output limiter toggle
55   AGC Enabled       0..1   Auto gain compensation
56   Panel Enabled     0..1   UI panel toggle (no audio effect)
57   Bypass            0..1   1=bypassed
58   Wet               0..1
59   Delta             0..1
```

### COMMON RECIPES

All examples assume a fresh ReEQ instance. Remember: bands default to Off,
so every recipe starts by enabling the band (Enabled = 2). Use TrackFX_SetParam
with native values throughout.

### FILTER DEFAULTS (when user doesn't specify slope or type)

When the user asks for a HPF / "high pass" / "low cut" without naming a filter
type or slope, default to **Type 2 (Low Cut Butterworth)** at **slope=7
(48 dB/oct)**. When the user asks for a LPF / "low pass" / "high cut" without
specifics, default to **Type 6 (High Cut Butterworth)** at **slope=7 (48 dB/oct)**.
These steep, phase-clean defaults match the user's preferred working setup.
Override only when the user explicitly requests a different slope, type, or
"gentle" / "analog" / "smooth" wording.

**"Remove rumble". HPF at 80 Hz, 48 dB/oct (Butterworth) on band 1:**

```lua
  -- Band 1 base = 17
  reaper.TrackFX_SetParam(tr, fx, 17, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 19, 2)        -- Type: Low Cut (Butterworth)
  reaper.TrackFX_SetParam(tr, fx, 20, 27.0)     -- Frequency: 80 Hz
  reaper.TrackFX_SetParam(tr, fx, 23, 7)        -- Slope: (7+1)*6 = 48 dB/oct
```

**"Tame harshness". LPF at 10 kHz, 48 dB/oct (Butterworth) on band 5:**

```lua
  -- Band 5 base = 45
  reaper.TrackFX_SetParam(tr, fx, 45, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 47, 6)        -- Type: High Cut (Butterworth)
  reaper.TrackFX_SetParam(tr, fx, 48, 89.73)    -- Frequency: 10 kHz
  reaper.TrackFX_SetParam(tr, fx, 51, 7)        -- Slope: 48 dB/oct
```

**"Cut mud". Narrow bell cut at 300 Hz on band 2:**

```lua
  -- Band 2 base = 24
  reaper.TrackFX_SetParam(tr, fx, 24, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 26, 0)        -- Type: Peak
  reaper.TrackFX_SetParam(tr, fx, 27, 44.18)    -- Frequency: 300 Hz
  reaper.TrackFX_SetParam(tr, fx, 28, -3.0)     -- Gain: -3 dB
  reaper.TrackFX_SetParam(tr, fx, 29, 50.0)     -- Q: 2.0
```

**"Add air". High shelf boost at 12 kHz on band 4:**

```lua
  -- Band 4 base = 38
  reaper.TrackFX_SetParam(tr, fx, 38, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 40, 4)        -- Type: High Shelf
  reaper.TrackFX_SetParam(tr, fx, 41, 92.10)    -- Frequency: 12 kHz
  reaper.TrackFX_SetParam(tr, fx, 42, 3.0)      -- Gain: +3 dB
  reaper.TrackFX_SetParam(tr, fx, 43, 32.65)    -- Q: 0.707 (Butterworth shelf)
```

**"Add warmth". Low shelf boost at 200 Hz on band 1:**

```lua
  -- Band 1 base = 17
  reaper.TrackFX_SetParam(tr, fx, 17, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 19, 3)        -- Type: Low Shelf
  reaper.TrackFX_SetParam(tr, fx, 20, 38.91)    -- Frequency: 200 Hz
  reaper.TrackFX_SetParam(tr, fx, 21, 2.5)      -- Gain: +2.5 dB
  reaper.TrackFX_SetParam(tr, fx, 22, 32.65)    -- Q: 0.707
```

### FULL PATTERN (add ReEQ and apply HPF + LPF)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "ReJJ/ReEQ/ReEQ.jsfx", false, -1)
reaper.defer(function()
  if fx == -1 then return end
  -- Band 1: HPF 80 Hz @ 48 dB/oct (Butterworth) -- default for unspecified HPF
  reaper.TrackFX_SetParam(tr, fx, 17, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 19, 2)        -- Type: Low Cut (BW)
  reaper.TrackFX_SetParam(tr, fx, 20, 27.0)     -- 80 Hz
  reaper.TrackFX_SetParam(tr, fx, 23, 7)        -- 48 dB/oct
  -- Band 5: LPF 16 kHz @ 48 dB/oct (Butterworth) -- default for unspecified LPF
  reaper.TrackFX_SetParam(tr, fx, 45, 2)        -- Enabled
  reaper.TrackFX_SetParam(tr, fx, 47, 6)        -- Type: High Cut (BW)
  reaper.TrackFX_SetParam(tr, fx, 48, 95.83)    -- 16 kHz
  reaper.TrackFX_SetParam(tr, fx, 51, 7)        -- 48 dB/oct
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add ReEQ: HPF 80Hz / LPF 16kHz", -1)
end)
```

---

# FabFilter third-party plugins

FabFilter's Pro series is a high-quality commercial plugin suite. ReaAssist
auto-prefers installed FabFilter plugins over stock equivalents (see
FALLBACK CHAINS). Param layouts are identical across VST3 / VST2 / AU / CLAP
formats -- the sections below apply regardless of the format the user has
installed. AddByName strings use the bare plugin name (e.g. "Pro-DS") so
REAPER picks whichever format is available.

All FabFilter params use TrackFX_SetParamNormalized (values 0..1). Raw ranges
are not documented here since the normalized slider values are what scripts
actually write.

<!-- /PLUGIN:ReEQ -->

<!-- PLUGIN:Pro-DS -->
## Pro-DS

FabFilter Pro-DS is a single-band de-esser with automatic range detection
and sidechain HP/LP filtering. Works well for dialogue, vocals, and general
sibilance reduction without user threshold hunting.

AddByName string: "Pro-DS"
Total params (default instance): 23 useful (plus ~130 MIDI-CC routing params
REAPER exposes but scripts should ignore)

### CRITICAL CONSTRAINTS

1. **Single band, fixed design.** Pro-DS detects sibilance automatically via
   the Mode + HP/LP sidechain. No user compression controls (attack/release/
   knee/ratio) are exposed -- just Threshold and Range.

2. **Threshold is non-linear below slider 0.2.** Slider 0 collapses to -INF
   (silence). From slider 0.2 to 1.0 it's linear at 60 dB/unit: slider 0.2 =
   -48 dB, slider 1.0 = 0 dB. Most real use is slider 0.3..0.5.

3. **HP and LP use the same frequency scale** (2000..20000 Hz, log base 10).
   Formula: Hz = 2000 * 10^slider.

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

Useful threshold targets:

```
-30 dB  = 0.500    -15 dB  = 0.750    -6 dB   = 0.900
-24 dB  = 0.600    -12 dB  = 0.800    -3 dB   = 0.950
-18 dB  = 0.700    -9 dB   = 0.850     0 dB   = 1.000
```

### RANGE SCALE (0..24 dB linear)

Range sets the maximum gain reduction Pro-DS will apply when the threshold
is exceeded. Default 6 dB is a moderate start for vocals.

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

```
slider   Hz         slider   Hz         slider   Hz
-------  --------   -------  --------   -------  --------
0.00     2000       0.35     4477       0.70     10024
0.05     2244       0.40     5024       0.75     11247
0.10     2518       0.45     5637       0.80     12619
0.15     2825       0.50     6325       0.85     14159
0.20     3170       0.55     7096 *     0.90     15887
0.25     3557       0.60     7962       0.95     17825
0.30     3991       0.65     8934       1.00     20000

* = HP default near here (7000 Hz = slider 0.544)
  LP default 14000 Hz = slider 0.845
```

Formula: Hz = 2000 * 10^slider. Or: slider = log10(Hz / 2000).

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

**"Gentle vocal de-essing (default-like, slightly more conservative):"**

```lua
-- Most users want default-ish behavior. Pro-DS defaults are already a good
-- starting point; below just pulls the threshold a bit higher.
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.0)    -- Mode: Single Vocal
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.5)    -- Threshold: -30 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.25)   -- Range: 6 dB
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

<!-- /PLUGIN:Pro-DS -->

<!-- PLUGIN:Pro-G -->
## Pro-G

FabFilter Pro-G is a gate / expander with upward and downward processing.
Supports classic, clean, and vocal styles; sidechain HP/LP filtering;
lookahead.

AddByName string: "Pro-G"
Total params (default instance): 38 useful (MIDI CC routing filtered out)

### PARAM INDEX TABLE (verified, main controls)

```
idx  Name                      Default val   Type        Notes
---  ------------------------  -----------   ----------  ---------------------------
0    Threshold                 0.4           continuous  dB (-30..0 linear, see below)
1    Threshold (Upward)        0.8           continuous  dB (-30..0 linear, same scale)
2    Ratio                     0.9           continuous  Downward ratio (see Ratio scale)
3    Ratio (Upward)            0.25          continuous  Upward ratio (see Ratio scale)
4    Range                     0.751         continuous  Max GR in dB (-inf..0, see below)
5    Style                     0             enum        0=Classic, etc. (see Style enum)
6    Attack                    0.178         continuous  ms 0..1000 (see Attack scale)
7    Release                   0.308         continuous  ms 0..5000 (see Release scale)
8    Hold                      0.119         continuous  ms 0..500 (approx; linear-ish)
9    Knee                      0             continuous  dB 0..24 linear: dB=slider*24
10   Lookahead                 0             continuous  ms 0..5 linear: ms=slider*5
11   Lookahead Enabled         0             toggle      0=Disabled, 1=Enabled
17   Low Pass Frequency        1.0           continuous  Hz (SC LP; 1.0 = off/30kHz)
18   High Pass Frequency       0             continuous  Hz (SC HP; 0 = off/5Hz)
19   Audition Side Chain       0             toggle      0=Off, 1=On
25   Oversampling              0             toggle      0=Off, 1=On
27   Channel Mode              0             enum        0=Left/Right, etc.
```

Utility I/O params (15-16, 20-24, 28-31) are standard level/pan/wet-dry and
usually left at defaults. Bypass params (32, 35, 172) are redundant -- use
idx 32 if scripting bypass.

### THRESHOLD SCALE (-30..0 dB linear, shared by idx 0 and 1)

Formula: dB = -30 + slider * 30. Slider = (dB + 30) / 30.

```
-30 dB = 0.000    -15 dB = 0.500    -6 dB = 0.800
-24 dB = 0.200    -12 dB = 0.600    -3 dB = 0.900
-18 dB = 0.400 *  -9 dB  = 0.700     0 dB = 1.000

* = Threshold default. Threshold (Upward) default: -6 dB (slider 0.8).
```

### RATIO SCALE (idx 2 downward, idx 3 upward)

Idx 2 (downward gate/expander ratio) -- default 10:1 at slider 0.9.
Idx 3 (upward expander ratio) -- default 1.5:1 at slider 0.25.

```
slider   ratio       slider   ratio
-------  -------     -------  -------
0.00     1.00:1      0.60     5.64:1
0.25     1.50:1      0.70     6.81:1
0.40     2.50:1      0.80     8.11:1
0.50     4.00:1      0.90     10.0:1
                     1.00     inf:1  (hard gate)
```

### ATTACK SCALE (0..1000 ms, quartic -- ms = 1000 * slider^4)

```
slider   ms          slider   ms
-------  ----        -------  ----
0.00     0.0         0.50     62.5
0.10     0.1         0.60     129.6
0.20     1.6         0.70     240.1
0.25     3.9         0.80     409.6
0.30     8.1         0.90     656.1
0.35     15.0        1.00     1000
0.40     25.6

Formula: ms = 1000 * slider^4. Slider = (ms / 1000)^0.25.
Default 1 ms = slider ~0.178 (= (0.001)^0.25).
```

### RELEASE SCALE (0..5000 ms, non-standard)

Use lookup table. Formula approximates but isn't exact.

```
slider   ms          slider   ms
-------  ------      -------  ------
0.00     0           0.50     428.7
0.10     3.4         0.60     740.7
0.20     27.4        0.70     1176
0.25     53.6 *      0.80     1756
0.30     92.6        0.90     2500
0.40     219.5       1.00     5000

* = Release default-ish: 100 ms at slider 0.308. Useful anchors:
50 ms  ~ 0.247    200 ms ~ 0.389    500 ms ~ 0.516
```

### RANGE SCALE (-inf..0 dB, special curve)

Default 50 dB GR at slider 0.751 -- high values mean "gate fully closes."
Slider 1.0 = infinite GR (hard gate). Slider 0 = 0 dB (no gating applied).
Use slider 0.5..0.9 for typical gate behavior; use 0.3..0.5 for gentle
expansion.

### COMMON RECIPES

**"Gentle dialogue gating (light expansion):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.4)    -- Threshold: -18 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.4)    -- Ratio: 2.5:1
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.5)    -- Range: ~24 dB GR
reaper.TrackFX_SetParamNormalized(tr, fx, 6, 0.178)  -- Attack: 1 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.308)  -- Release: 100 ms
```

**"Drum gate (tight, hard-close):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 0.5)    -- Threshold: -15 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 1.0)    -- Ratio: inf:1
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.9)    -- Range: heavy GR
reaper.TrackFX_SetParamNormalized(tr, fx, 6, 0.1)    -- Attack: 0.1 ms (fast)
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.247)  -- Release: 50 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 8, 0.15)   -- Hold: ~5 ms
```

<!-- /PLUGIN:Pro-G -->

<!-- PLUGIN:Pro-L 2 -->
## Pro-L 2

FabFilter Pro-L 2 is a true peak limiter with 8 character styles, true-peak
metering, dither / noise shaping, and loudness monitoring. Used as the final
stage of mastering chains.

AddByName string: "Pro-L 2"
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

```
0 dBTP    = 1.000 (default)    -1 dBTP  = ~0.967
-0.1 dBTP = ~0.997             -3 dBTP  = ~0.900
-0.3 dBTP = ~0.990             -6 dBTP  = ~0.800
```

Common choice for streaming: -1.0 dBTP (~slider 0.967) to leave headroom.

### COMMON RECIPES

**"Master bus limiter (streaming target, ~-14 LUFS integrated):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.167)  -- Gain: +5 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 1,  0.714)  -- Style: Modern
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 1.0)    -- True Peak Limiting ON
reaper.TrackFX_SetParamNormalized(tr, fx, 18, 0.967)  -- Ceiling: -1 dBTP
```

**"Transparent peak catch (small gain, minimal character):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.067)  -- Gain: +2 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 1,  0.0)    -- Style: Transparent
reaper.TrackFX_SetParamNormalized(tr, fx, 18, 0.950)  -- Ceiling: -1.5 dBTP
```

<!-- /PLUGIN:Pro-L 2 -->

<!-- PLUGIN:Pro-C 3 -->
## Pro-C 3

FabFilter Pro-C 3 is a transparent / character compressor with 14 styles,
auto-threshold, auto-release, auto-gain, character saturation, internal
sidechain EQ, and mid/side stereo link. The go-to compressor for most work.

AddByName string: "Pro-C 3"
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
version reports a different order or count via `fx_params`, trust the
live list (see ENUM PARAM NORMS section at top of file).

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
1.5:1 = 0.30    3:1   = 0.526   10:1 = 0.90
2:1   = 0.40    4:1   = 0.60    20:1 = 0.94
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

### COMMON RECIPES

Style values below resolve via the STYLE ENUM table; if `fx:Pro-C 3` is
pinned, recompute from the live `[enum:]` list instead (see precedence
note at top of file).

**"Gentle vocal compression (Vocal style, ~3 dB GR):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 10/13)   -- Style: "Vocal" (idx 10/14)
reaper.TrackFX_SetParamNormalized(tr, fx, 1, 0.75)    -- Threshold: -15 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.40)    -- Ratio: 2:1
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.15)    -- Knee: ~10 dB (soft)
reaper.TrackFX_SetParamNormalized(tr, fx, 7, 0.342)   -- Attack: 10 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 8, 0.278)   -- Release: 100 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 19, 1.0)    -- Auto Gain ON
```

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

<!-- /PLUGIN:Pro-C 3 -->

<!-- PLUGIN:Pro-MB -->
## Pro-MB

FabFilter Pro-MB is a dynamic-range processor that can compress OR expand
any number of frequency bands independently. Up to 6 user-defined bands,
each with its own crossovers, dynamics mode, threshold, ratio, and sidechain
filtering. Primary tool for surgical multiband problems (resonances,
de-honking, mud cleanup, band-specific de-essing).

AddByName string: "Pro-MB"
Total params: 66 useful (this reference covers Bands 1-2 as representative;
bands 3-6 follow the same per-band offset pattern and exist at higher indices
but are typically set via UI, not script).

### CRITICAL CONSTRAINTS

1. **All bands start "Unused" by default.** Fresh Pro-MB has no active
   processing. Set `Band N State` to "In Use" (slider < 0.5 -- see State enum)
   before any other band params take effect.

2. **Each band has BOTH compression and expansion modes** via `Dynamics Mode`.
   Compression reduces signal above threshold; expansion reduces below.

3. **Attack and Release are percentages (0..100%), not ms.** Pro-MB uses an
   auto-detected per-band time base; the % scale is relative to that.
   Default 20% is moderate for both.

### BAND LAYOUT (per-band structure, 22 params each)

```
Formula: base = (N - 1) * 22  (for bands 1-2; bands 3-6 follow same stride)

Offset  Name                          Type        Notes
------  ----------------------------  ----------  --------------------------
+0      N State                       enum        Unused / In Use (see enum)
+1      N Low Crossover               continuous  Hz (30..30000, log)
+2      N Low Slope                   enum        dB/oct (see Slope enum)
+3      N High Crossover              continuous  Hz (30..30000, log)
+4      N High Slope                  enum        dB/oct (see Slope enum)
+5      N Dynamics Mode               enum        0=Compression, 1=Expansion
+6      N Threshold                   continuous  dB -60..0 linear
+7      N Range                       continuous  dB (-60..+60; 0.5=0dB)
+8      N Ratio                       continuous  Ratio (see Ratio scale)
+9      N Attack                      continuous  % 0..100 linear: slider=%/100
+10     N Release                     continuous  % 0..100 linear: slider=%/100
+11     N Knee                        continuous  dB 0..72: dB=slider*72 approx
+12     N Lookahead                   continuous  ms (0..20 linear)
+13     N Level                       continuous  dB band output trim (0.5=0dB)
+14     N Pan                         continuous  Mid/Side or L/R pan
+15     N Side Chain Filtering        enum        Band-only / External / ...
+16     N Side Chain Low Frequency    continuous  SC HPF (shares Crossover scale)
+17     N Side Chain High Frequency   continuous  SC LPF (shares Crossover scale)
+18     N Side Chain Input            enum        Plug-in Input / External
+19     N Stereo Link                 continuous  % 0..200 (default 100%)
+20     N Stereo Link Mode            enum        0=Mid, 1=Side, 2=L/R
+21     N Solo/Mute State             enum        Normal / Solo / Mute

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

Default slider 1.0 = "Unused". To activate a band, set slider < 0.5.

```
slider  Display      Meaning
------  -----------  --------------------------------
0.0     In Use       Band processes audio
1.0     Unused       Band bypassed (default)
```

### CROSSOVER FREQUENCY SCALE (30..30000 Hz, log)

Used by idx +1, +3, +16, +17 within each band.

Formula: Hz = 30 * 1000^slider (approx). Or: slider = log10(Hz/30) / 3.

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
- **Range (offset +7):** dB -60..+60 (bipolar, 0.5 = 0 dB). Negative = compression
  max GR, positive = expansion max GR. Default 0 disables dynamics within
  the band.

### COMMON RECIPES

**"De-mud the low-mids (cut 200-500 Hz when signal exceeds threshold):"**

```lua
-- Activate Band 1 as a dynamic EQ cut
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.0)     -- Band 1 State: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 1,  0.275)   -- Low Crossover: 200 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 3,  0.408)   -- High Crossover: 500 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 5,  0.0)     -- Mode: Compression
reaper.TrackFX_SetParamNormalized(tr, fx, 6,  0.7)     -- Threshold: -18 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 7,  0.4)     -- Range: -6 dB (max GR)
reaper.TrackFX_SetParamNormalized(tr, fx, 8,  0.5)     -- Ratio: ~2.75:1
reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.15)    -- Attack: 15%
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.30)    -- Release: 30%
```

**"De-ess via Band 2 (tight 5-8 kHz, hard ratio):"**

```lua
-- Use Band 2 so Band 1 can stay configured for other purposes
reaper.TrackFX_SetParamNormalized(tr, fx, 22, 0.0)     -- Band 2 State: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 23, 0.742)   -- Low Xover: 5000 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 25, 0.819)   -- High Xover: ~8000 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 27, 0.0)     -- Mode: Compression
reaper.TrackFX_SetParamNormalized(tr, fx, 28, 0.75)    -- Threshold: -15 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 29, 0.35)    -- Range: -9 dB max
reaper.TrackFX_SetParamNormalized(tr, fx, 30, 0.80)    -- Ratio: 8:1
reaper.TrackFX_SetParamNormalized(tr, fx, 31, 0.05)    -- Attack: 5% (fast)
reaper.TrackFX_SetParamNormalized(tr, fx, 32, 0.10)    -- Release: 10%
```

<!-- /PLUGIN:Pro-MB -->

<!-- PLUGIN:Pro-R 2 -->
## Pro-R 2

FabFilter Pro-R 2 is a natural-sounding reverb with macro-style controls
(Space, Decay Rate, Distance, Brightness, Character, Thickness) and
post-EQ. Designed for quick tonal shaping without managing individual
reflections.

AddByName string: "Pro-R 2"
Total params (default instance): 75 useful -- mostly macros + internal EQ

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
Idx 61-78 = Post EQ (two bands shaping reverb output). These follow the
same per-band pattern as Pro-Q 4's bands (see Pro-Q 4 section for band layout
conventions). Usually left at defaults unless explicitly tuning reverb tone.

Idx 115-123 = "Tilt" params for macro-to-band response (advanced; default
0.5 = balanced). Leave at defaults.

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

At least 3 distinct values seen in scan. The plugin may have additional
styles not sampled at 21-probe resolution; use UI to audition.

```
Slider    Display      Feel
-------   -----------  ----------------------------
0.00      Modern       Clean, neutral (default)
~0.33     Vintage      Warm, analog-flavored
~0.80     Plate        Metallic, bright, dense
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

<!-- /PLUGIN:Pro-R 2 -->

<!-- PLUGIN:Saturn 2 -->
## Saturn 2

FabFilter Saturn 2 is a multiband saturation/distortion processor with 21+
character styles (tube, tape, amp, transformer, etc.), per-band tone shaping
(Bass/Mid/Treble/Presence), modulation, feedback, and up to 6 user bands.

AddByName string: "Saturn 2"
Total params: 146 useful -- this reference covers global + Bands 1-2 as
representative; bands 3-6 follow the same 17-param stride.

### CRITICAL CONSTRAINTS

1. **Start with `Num Active Bands` (idx 6)** set to the number of bands you
   want (1..6). Default is 1 active band. Setting >1 activates subsequent
   bands' params.

2. **Drive is the main processing parameter** -- idx 11 (Band 1 Drive).
   Default 20% is modest; 40-60% is typical; 80%+ is aggressive.

3. **Bass / Mid / Treble / Presence (offsets +6..+9)** are per-band post-
   saturation tone shaping. Default 0 dB (slider 0.5). Range is bipolar.

4. **Heavy modulation params (XLFO, EG, XY controllers)** at idx 109+ are
   intentionally not documented here -- they're rarely script-set. Use the
   UI. Main-chain controls below are what scripts should touch.

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
+0      N Feedback Amount           continuous  % 0..100 (default 0)
+1      N Feedback Frequency        continuous  Hz (see Crossover scale)
+2      N Dynamics                  continuous  Bipolar mod depth (0.5=neutral)
+3      N Style                     enum        21+ styles (see Style enum)
+4      N Drive                     continuous  % 0..100 linear (default 20%)
+5      N Drive Pan                 continuous  Bipolar (0.5=center)
+6      N Bass                      continuous  dB tone (0.5=0dB)
+7      N Mid                       continuous  dB tone (0.5=0dB)
+8      N Treble                    continuous  dB tone (0.5=0dB)
+9      N Presence                  continuous  dB tone (0.5=0dB)
+10     N Mix                       continuous  Per-band wet (1.0=100%)
+11     N Level                     continuous  Band output trim (0.5=0dB)
+12     N Pan                       continuous  Mid/Side or L/R pan
+13     N Enabled                   toggle      1=enabled
+14     N State                     enum        Normal / Solo / Mute
+15     N Crossover Frequency       continuous  Hz (log, see scale)
+16     N Crossover Slope           enum        dB/oct (see slope enum)

Band 1: indices 7-23
Band 2: indices 24-40
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

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 6,  0.0)    -- 1 active band
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.20)   -- Band 1 Style: Clean Tape
reaper.TrackFX_SetParamNormalized(tr, fx, 11, 0.30)   -- Band 1 Drive: 30%
reaper.TrackFX_SetParamNormalized(tr, fx, 13, 0.55)   -- Band 1 Bass: +2 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 18, 0.5)    -- Band 1 Level: 0 dB
```

**"Aggressive amp on guitar (Lead Amp, heavy drive):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.50)   -- Band 1 Style: Lead Amp
reaper.TrackFX_SetParamNormalized(tr, fx, 11, 0.70)   -- Band 1 Drive: 70%
reaper.TrackFX_SetParamNormalized(tr, fx, 15, 0.45)   -- Band 1 Treble: ~-3 dB (tame fizz)
reaper.TrackFX_SetParamNormalized(tr, fx, 16, 0.55)   -- Band 1 Presence: +2 dB
```

**"Subtle tube warmth (master bus, 15% mix):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 5,  0.15)   -- Global Mix: 15%
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 0.05)   -- Band 1 Style: Clean Tube
reaper.TrackFX_SetParamNormalized(tr, fx, 11, 0.25)   -- Band 1 Drive: 25%
```

<!-- /PLUGIN:Saturn 2 -->

<!-- PLUGIN:Timeless 3 -->
## Timeless 3

FabFilter Timeless 3 is a creative delay with tape / digital / extreme read
modes, multi-tap support, per-feedback-path filters, and feedback effects
(drive, lo-fi, diffuse, dynamics, pitch shift). Heavy plugin; typical script
use only touches the main delay/feedback/mix controls.

AddByName string: "Timeless 3"
Total params: 169 useful. Most modulation/XLFO/EG/XY params at idx 162+ are
intentionally not documented here -- use the UI for detailed modulation.

### PARAM INDEX TABLE (main controls)

```
idx  Name                  Default val   Type        Notes
---  --------------------  -----------   ----------  ---------------------------
0    Delay Time            0.293         continuous  ms (see Delay Time scale)
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
reaper.TrackFX_SetParamNormalized(tr, fx, 3,  0.0)    -- Delay Sync: Free
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.275)  -- Delay Time: 300 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 4,  0.0)    -- Read Mode: Tape
reaper.TrackFX_SetParamNormalized(tr, fx, 85, 0.175)  -- Feedback: 35%
reaper.TrackFX_SetParamNormalized(tr, fx, 99, 0.65)   -- Filter 2 Freq: ~3 kHz
reaper.TrackFX_SetParamNormalized(tr, fx, 104, 0.0)   -- Filter 2: Low Pass
reaper.TrackFX_SetParamNormalized(tr, fx, 160, 0.25)  -- Mix: 25%
```

**"Dark ping-pong delay (ambient pads):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.362)  -- Delay Time: ~500 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 6,  1.0)    -- Ping Pong: On
reaper.TrackFX_SetParamNormalized(tr, fx, 85, 0.30)   -- Feedback: 60%
reaper.TrackFX_SetParamNormalized(tr, fx, 99, 0.55)   -- Filter 2 Freq: ~1.5 kHz
reaper.TrackFX_SetParamNormalized(tr, fx, 104, 0.0)   -- Filter 2: Low Pass
reaper.TrackFX_SetParamNormalized(tr, fx, 160, 0.35)  -- Mix: 35%
```

**"Short slapback echo:"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  0.125)  -- Delay Time: ~50 ms
reaper.TrackFX_SetParamNormalized(tr, fx, 85, 0.05)   -- Feedback: 10% (single echo)
reaper.TrackFX_SetParamNormalized(tr, fx, 160, 0.20)  -- Mix: 20%
```

<!-- /PLUGIN:Timeless 3 -->

<!-- PLUGIN:Pro-Q 4 -->
## Pro-Q 4

FabFilter Pro-Q 4 is a surgical / musical parametric EQ with up to 24 bands,
dynamic EQ per band, spectral processing, per-band mid/side/surround routing,
and multiple processing modes (Zero Latency / Natural Phase / Linear Phase).
The most-used FabFilter plugin -- this section is the most important for
typical EQ scripting.

AddByName string: "Pro-Q 4"
Total params (default instance): 75 useful -- this reference covers Bands 1-2
as representative; bands 3-24 follow the same 23-param stride.

### CRITICAL CONSTRAINTS

1. **Bands default to "Unused".** Set `Band N Used` (offset +0) to "In Use"
   (slider 1.0) before any other band params take effect. "Enabled" (offset
   +1) is a separate toggle that temporarily bypasses an in-use band.

2. **Setting a band's `Used` to In Use creates a point at default Freq/Gain.**
   Always follow with Frequency + Gain + Shape + Q to position it.

3. **Shape defaults to Bell.** For HPF / LPF, set Shape accordingly and use
   Slope (offset +6) for the cut steepness.

4. **Dynamics per band is OFF by default via `Dynamic Range = 0 dB`.**
   To activate dynamic EQ, set offset +9 to non-0.5 (negative=downward
   dynamic, positive=upward). Then tune Threshold/Attack/Release.

5. **Pro-Q 4 supports 24 bands.** Band N indices run 0..22 for N=1, then stride
   23 per band. Band 24 last param = 547. Params at 552+ are globals.

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

```
slider   Hz            slider   Hz
-------  --------      -------  --------
0.00     10.0          0.50     547.7
0.05     14.9          0.55     817.4
0.10     22.3          0.60     1219.8
0.15     33.2          0.65     1820.2
0.20     49.6          0.70     2716.3
0.25     74.0          0.75     4053.6
0.30     110.4         0.80     6049.2
0.35     164.8         0.85     9027.2
0.40     246.0         0.90     13471
0.45     367.0         0.95     20103
                       1.00     30000
```

Common target frequencies:

```
20 Hz   = 0.086     500 Hz   = 0.488     5 kHz   = 0.777
30 Hz   = 0.137     1 kHz    = 0.575     8 kHz   = 0.836
50 Hz   = 0.201     2 kHz    = 0.662     10 kHz  = 0.863
80 Hz   = 0.266     3 kHz    = 0.713     12 kHz  = 0.886
100 Hz  = 0.297     4 kHz    = 0.749     16 kHz  = 0.925
150 Hz  = 0.352                          20 kHz  = 0.949
200 Hz  = 0.391                          24 kHz  = 0.965
250 Hz  = 0.417
```

Formula is exact -- interpolate between probes for arbitrary Hz.

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

```
slider   Q              slider   Q
-------  -----          -------  -----
0.00     0.025          0.50     1.00 * (default)
0.10     0.052          0.55     1.45
0.20     0.109          0.60     2.09
0.25     0.158          0.65     3.02
0.30     0.229          0.70     4.37
0.35     0.331          0.75     6.33
0.40     0.478          0.80     9.15
0.45     0.692          0.85     13.23
                        0.90     19.13
                        0.95     27.66
                        1.00     40.00
```

Useful Q targets:

```
0.5 (wide)        = 0.300    1.0 (medium)      = 0.500 *
0.707 (Butterworth) = 0.379  1.41 (Linkwitz)   = 0.550
                             2.0 (narrow)      = 0.594
                             4.0 (very narrow) = 0.694
                             10.0 (surgical)   = 0.796
```

### SHAPE ENUM (offset +5, 10 shapes)

Formula: slider = shape_value / 9.

```
Value  Shape         Slider target    Uses Gain?   Uses Q?   Uses Slope?
-----  ------------  --------------   ----------   -------   -----------
0      Bell          0.000 *          yes          yes       no
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

### SLOPE PARAM (offset +6, cut types only)

Applies to Low Cut and High Cut shapes only (Shape values 2 and 4; see
Shape enum above). Slope is **NOT** a strict enum: Pro-Q 4 exposes a dropdown
of preset values AND accepts arbitrary typed values (e.g. "27 dB/oct").
Treat it as a numeric display target, not a fixed enum.

The dropdown presets observed on a current Pro-Q 4 install (subject to
change across versions):

```
0 dB/oct  6 dB/oct  12 dB/oct  18 dB/oct  24 dB/oct  30 dB/oct
36 dB/oct  48 dB/oct  72 dB/oct  96 dB/oct  Brickwall
```

The preset count has varied across Pro-Q versions (older revs had as few
as 6 entries). **Do NOT trust any static norm for this parameter** -- a
hard-coded value like `0.6` lands on a different displayed slope on
different installs (e.g. 24 dB/oct on a 6-entry build vs 36 dB/oct on
the 11-entry build above).

**ALWAYS use `set_param_display` for Slope:**

```lua
set_param_display(tr, fx, slope_idx, 24)   -- lands on "24 dB/oct"
set_param_display(tr, fx, slope_idx, 27)   -- lands on typed value 27
```

This is robust to version drift and works whether the user wants a
preset value or a non-preset typed value. Direct `SetParamNormalized` is
ONLY safe when `fx_params:Pro-Q 4` for THIS instance is pinned in the
current context (the cached `[norm:]` then reflects this exact install).

### COMMON RECIPES

**"HPF at 80 Hz, 24 dB/oct (standard low-cut for non-bass tracks):"**

```lua
-- Band 1: Low Cut at 80 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)      -- Used: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.266)    -- Frequency: 80 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.222)    -- Shape: Low Cut
set_param_display(tr, fx, 6, 24)                       -- Slope: 24 dB/oct
```

**"Vocal de-mud (pull -3 dB around 350 Hz with Q=1):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)      -- Used: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.444)    -- Frequency: ~370 Hz
reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.45)     -- Gain: -3 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.5)      -- Q: 1.0
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.0)      -- Shape: Bell
```

**"Presence shelf (boost +2 dB shelf from 5 kHz up):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)      -- Used: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.777)    -- Frequency: 5 kHz
reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.533)    -- Gain: +2 dB
reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0.4)      -- Q: ~0.48 (gentle shelf)
reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.333)    -- Shape: High Shelf
```

**"Dynamic de-ess at 7 kHz (band 1 with dynamic -6 dB when excited):"**

```lua
reaper.TrackFX_SetParamNormalized(tr, fx, 0,  1.0)     -- Used: In Use
reaper.TrackFX_SetParamNormalized(tr, fx, 2,  0.816)   -- Frequency: 7 kHz
reaper.TrackFX_SetParamNormalized(tr, fx, 3,  0.5)     -- Gain: 0 dB (static)
reaper.TrackFX_SetParamNormalized(tr, fx, 4,  0.7)     -- Q: ~4.4 (tight)
reaper.TrackFX_SetParamNormalized(tr, fx, 5,  0.0)     -- Shape: Bell
reaper.TrackFX_SetParamNormalized(tr, fx, 9,  0.40)    -- Dynamic Range: -6 dB (downward)
reaper.TrackFX_SetParamNormalized(tr, fx, 10, 1.0)     -- Dynamics Enabled
reaper.TrackFX_SetParamNormalized(tr, fx, 11, 0.0)     -- Dynamics: Auto threshold
```

**"Full vocal chain EQ (HPF + cut mud + boost presence + roll top):"**

(Recipe is illustrative -- shows indices and the right tools. When generating
a runnable script, include the `set_param_display` helper definition from
`prompt_bundle:plugin_helpers`; calling it without the definition crashes.)

```lua
local tr = reaper.GetTrack(0, 0)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local fx = reaper.TrackFX_AddByName(tr, "Pro-Q 4", false, -1)
reaper.defer(function()
  if fx == -1 then return end

  -- Band 1: HPF 80 Hz, 24 dB/oct
  reaper.TrackFX_SetParamNormalized(tr, fx, 0,  1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, 2,  0.266)
  reaper.TrackFX_SetParamNormalized(tr, fx, 5,  0.222)
  set_param_display(tr, fx, 6, 24)                       -- Slope: 24 dB/oct (typed/version-safe)

  -- Band 2: -3 dB bell at 370 Hz, Q 1
  reaper.TrackFX_SetParamNormalized(tr, fx, 23, 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, 25, 0.444)
  reaper.TrackFX_SetParamNormalized(tr, fx, 26, 0.45)
  reaper.TrackFX_SetParamNormalized(tr, fx, 27, 0.5)
  reaper.TrackFX_SetParamNormalized(tr, fx, 28, 0.0)

  -- Band 3: +2 dB high shelf at 5 kHz
  reaper.TrackFX_SetParamNormalized(tr, fx, 46, 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, 48, 0.777)
  reaper.TrackFX_SetParamNormalized(tr, fx, 49, 0.533)
  reaper.TrackFX_SetParamNormalized(tr, fx, 50, 0.4)
  reaper.TrackFX_SetParamNormalized(tr, fx, 51, 0.333)

  -- Band 4: LPF 16 kHz, 12 dB/oct
  reaper.TrackFX_SetParamNormalized(tr, fx, 69, 1.0)
  reaper.TrackFX_SetParamNormalized(tr, fx, 71, 0.925)
  reaper.TrackFX_SetParamNormalized(tr, fx, 74, 0.444)
  set_param_display(tr, fx, 75, 12)                      -- Slope: 12 dB/oct (typed/version-safe)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Add Pro-Q 4: vocal EQ chain", -1)
end)
```

<!-- /PLUGIN:Pro-Q 4 -->
