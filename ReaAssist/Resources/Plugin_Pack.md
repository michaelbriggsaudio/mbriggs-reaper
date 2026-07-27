<!-- REAASSIST_PLUGIN_PACK_FORMAT:2 -->
<!-- GENERATED FILE. Edit private Dev/Plugin Profiles sources, then rebuild. -->
<!-- metadata_layout:split-route-validate -->
<!-- profile_schema:2 -->
<!-- builder_version:2 -->
<!-- builder_script_sha256:8dbbedd8d38bc6565928ad35bade8a2fe0bfd32d658a4a6f1799ddd2a55eac79 -->
<!-- section_count:24 -->
<!-- source_set_sha256:b3870bc17433c9ce6fa0eb3453838a846967faf38d38b8442d76857c644dc193 -->
<!-- stoplist_version:1 -->
<!-- aggregate_injected_limit_bytes:98304 -->
<!-- pack_revision:3cd14c8a8a6181b5bdac6b0df3738c93ca37f1685e6081a77d5ae6c920a8be5d -->
<!-- Plugin_Pack.md - markers are PLUGIN:Name (NOT SECTION:) because each block -->
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

Fallback-chain entries are not automatically curated parameter references.
Use a `PLUGIN:Name` section below only for the exact matching version named by
that marker. If an installed fallback has no matching marker (for example,
`Pro-Q 3`, `Pro-Q 2`, or `Twin 2`), add/load it by its resolved identifier but
do not borrow another version's parameter map; request live `fx_inspect` or
`fx_params` before writing parameters.

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
<!-- The load-bearing rules are repeated inside each Pro-* entry, which is   -->
<!-- what the model actually receives.                                       -->

# FabFilter third-party plugins

FabFilter's Pro series is a high-quality commercial plugin suite. ReaAssist
auto-prefers installed FabFilter plugins over stock equivalents (see
FALLBACK CHAINS). The migrated guidance was verified against the formats named
inside each profile. Do not assume VST3, VST2, AU and CLAP parameter layouts
are interchangeable; runtime fingerprint validation must authorize the exact
installed format before mapped guidance is trusted. When preferred_plugins or
a preempt header provides an exact format-prefixed AddByName identifier (for
example "VST3: Pro-G"), use that exact identifier. Do not strip the prefix and
do not add a vendor suffix. Bare names are reference labels only and may fail
on some installs.

All FabFilter params use TrackFX_SetParamNormalized (values 0..1). Raw ranges
are not documented here since the normalized slider values are what scripts
actually write.

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

<!-- PLUGIN:Pro-C 3 -->
<!-- SECTION-REVISION:b3dc9b95ba1c3ce16cee222cc7c112c8342f8ba0d90dc99a461264444e4b7bce -->
## Pro-C 3

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-c-3","display_name":"Pro-C 3","vendor":"FabFilter","product_class":"ordinary","preference_type":"compressor","identifiers":{"add_by_name":["VST3: Pro-C 3","VST3: Pro-C 3 (FabFilter)"],"aliases":["pro-c 3","pro-c","fabfilter pro-c 3","VST3: Pro-C 3","VST3: Pro-C 3 (FabFilter)"],"curated":["Pro-C 3"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro c"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-c-3","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-C 3","loaded_name":"VST3: Pro-C 3 (FabFilter)","parameter_count":{"mode":"exact","value":240},"required_parameters":[{"index":0,"name":"Style","section":"","section_required":false},{"index":24,"name":"Host Trigger Offset","section":"","section_required":false},{"index":49,"name":"Side Chain EQ Band 2 Speakers","section":"Side Chain EQ Band 2","section_required":true},{"index":73,"name":"Side Chain EQ Band 5 Shape","section":"Side Chain EQ Band 5","section_required":true},{"index":99,"name":"Show Input Level Meter","section":"","section_required":false}],"observed_fingerprint_sha256":"e22bc8283626bbae7a3e5748e68200d6ca8c5d8b95dbb6aa2f88fd6214d1c34c"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"01efef72a33e56c97872425a0f45185c7c9e90da9cf9afb5b4e17e7a8e914d4a","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
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
<!-- SECTION-REVISION:8e177a110c7714ba10f6b8faf5efebd633ce113500cf7fb0017ae255ae95d8ab -->
## Pro-G

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-g","display_name":"Pro-G","vendor":"FabFilter","product_class":"ordinary","preference_type":"gate","identifiers":{"add_by_name":["VST3: Pro-G","VST3: Pro-G (FabFilter)"],"aliases":["pro-g","fabfilter pro-g","VST3: Pro-G","VST3: Pro-G (FabFilter)"],"curated":["Pro-G"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro g"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-g","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-G","loaded_name":"VST3: Pro-G (FabFilter)","parameter_count":{"mode":"exact","value":175},"required_parameters":[{"index":0,"name":"Threshold","section":"","section_required":false},{"index":8,"name":"Hold","section":"","section_required":false},{"index":16,"name":"Side Chain Input Signal","section":"","section_required":false},{"index":24,"name":"Midi State","section":"","section_required":false},{"index":34,"name":"Ex Style","section":"","section_required":false}],"observed_fingerprint_sha256":"06be5f6a23d50266cd8ab70bf4662efdea2a49f5cf82fb2ba0450f3a8e356e27"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"4deb081044e968cc86e341bded1f16c0efd26d411252aeb7b27516c81e7507e2","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
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
Threshold   0.400000           -36.00 dB
Ratio       0.400000           2.00:1
Range       0.500000           16.00 dB
Attack      0.178000           1.004 ms
Release     0.308000           100.2 ms
```

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
<!-- SECTION-REVISION:a4ac86d79baa82e7989fa39a1e10d6703418707fc8ce67e8e1883192b4a6d6af -->
## Pro-L 2

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-l-2","display_name":"Pro-L 2","vendor":"FabFilter","product_class":"ordinary","preference_type":"limiter","identifiers":{"add_by_name":["VST3: Pro-L 2","VST3: Pro-L 2 (FabFilter)"],"aliases":["pro-l 2","pro-l","fabfilter pro-l 2","VST3: Pro-L 2","VST3: Pro-L 2 (FabFilter)"],"curated":["Pro-L 2"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro l"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-l-2","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-L 2","loaded_name":"VST3: Pro-L 2 (FabFilter)","parameter_count":{"mode":"exact","value":172},"required_parameters":[{"index":0,"name":"Gain","section":"","section_required":false},{"index":7,"name":"Channel Link Center","section":"","section_required":false},{"index":15,"name":"Unity Gain","section":"","section_required":false},{"index":23,"name":"Display Mode","section":"","section_required":false},{"index":31,"name":"Loudness Auto-Reset","section":"","section_required":false}],"observed_fingerprint_sha256":"e8d76e3fc0d616f68c1dabcfb5888514479dbd5ad41a957e7378fe55509e05d1"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"633d4030db6ddd4da6f7669042746a3b83456c1b1c58d57be39b019942208007","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
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
<!-- SECTION-REVISION:a4a6b3a99908c7a43c3de6def5d033881406305e698e7e42df3b96bbd2b148e0 -->
## Pro-Q 4

```json plugin-route
{"pack_format":2,"profile_schema":2,"key":"fabfilter-pro-q-4","display_name":"Pro-Q 4","vendor":"FabFilter","product_class":"dynamic","preference_type":"eq","identifiers":{"add_by_name":["VST3: Pro-Q 4","VST3: Pro-Q 4 (FabFilter)"],"aliases":["pro-q 4","pro-q","fabfilter pro-q 4","VST3: Pro-Q 4","VST3: Pro-Q 4 (FabFilter)"],"curated":["Pro-Q 4"]},"routing":{"context_any_of":["vendor","format","current_track_fx","separate_unique_alias","plugin_action"],"context_exempt":[],"context_required":["pro q"]},"chunks":["control","musical"]}
```

```json plugin-validate
{"key":"fabfilter-pro-q-4","safety":{"settle_ms":100,"heavy_selectors":[],"unsafe_to_sweep":[],"volatile_parameters":[]},"fingerprints":[{"format":"VST3","identifier":"VST3: Pro-Q 4","loaded_name":"VST3: Pro-Q 4 (FabFilter)","parameter_count":{"mode":"exact","value":740},"required_parameters":[{"index":0,"name":"Band 1 Used","section":"Band 1","section_required":true},{"index":149,"name":"Band 7 Dynamics Auto","section":"Band 7","section_required":true},{"index":299,"name":"Band 14 Used","section":"Band 14","section_required":true},{"index":448,"name":"Band 20 Dynamics Auto","section":"Band 20","section_required":true},{"index":599,"name":"Band 24 Spectral Tilt","section":"Band 24","section_required":true}],"observed_fingerprint_sha256":"b90f26794dbf05ba04b652c813c932f02ec066c6996988a722d94d35449eb5ce"}],"status":"pilot","provenance":{"source":"Resources/Plugin_Ref.md","migrated_at":"2026-07-24","body_sha256":"2f51e4fb981a2dfef9cf70c5f1309b9af827eb4aa3d14b4757c58a36e3f84322","verified_at":"2026-07-24","reaper_profile":"C:\\REAPER - Test","inventory_sha256":"9df6b57a4b50a61d272496da983161b40aec3f169b45537720383c4495d201a1"}}
```

<!-- CHUNK:control -->
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
