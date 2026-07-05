<!-- Prompts.md - on-demand prompt bundles. -->
<!-- Served by CTX.prompt_bundle(name); requested via <context_needed>prompt_bundle:NAME</context_needed>. -->
<!-- Each bundle delimited by SECTION:name / /SECTION:name comment markers. -->
<!-- -->
<!-- Bundles: -->
<!--   plugin         end-to-end workflow for adding / modifying / configuring plugins. Decision spine, defer rules, minimal-write, EQ specifics, multi-track data-table pattern, output discipline. -->
<!--   plugin_helpers find_param / set_param_display / set_param_enum / set_param_enum_paced + the DECIDE FIRST per-param helper-selection checklist (linear/log/custom-curve, self-verify, API DISPLAY RANGE MISMATCH). -->
<!--   drums          phase-safe drum editing / quantize workflow: guide tracks, range/scope questions, Dynamic Split safety, shared stretch-marker maps. -->
<!--   jsfx           EEL2 syntax, slider declarations, DSP safety, host plumbing for .jsfx files. -->
<!--   jsfx_dsp_cookbook  Narrow delay/reverb/modulation JSFX memory-addressing recipes. -->
<!--   theme          theme color change safety + ExtState backup schema for the Undo button. (The full ini_key catalog lives in API_Ref.md SECTION:theme.) -->

<!-- SECTION:plugin -->
PLUGIN WORKFLOW:

DECISION SPINE (ordered checklist for every plugin task -- the rest of this bundle expands each step):
1. Identify the plugin: generic-add (resolve), specific-add-only (fx_list), add+configure (fx_inspect), modify-existing (fx_chains), or read-only (fx_params). See CRITICAL ANTI-PATTERN.
2. Fetch reference data: plugin_ref for curated, fx_inspect/fx_params for third-party. See PLUGIN SELECTION RULES + REFERENCE DATA RULES.
3. Decide WHICH params to write: MINIMAL-WRITE RULE (only what the user named, plus activation + EQ-fresh-band exceptions).
4. Decide HOW to write each param: PARAMETER-WRITING TRIAGE (curated direct-norm, helper, or read-only path).
5. Wrap param work in `reaper.defer` with ONE Undo block. Hoist any local variables shared between sync and defer phases to a scope enclosing both.
6. Output: human-readable values only -- no leaked normalized/range/formula internals. See OUTPUT DISCIPLINE.

CRITICAL ANTI-PATTERN (READ FIRST):
NEVER pass an unresolved plugin name to TrackFX_AddByName. Two cases:

CASE A -- GENERIC TYPE (user says "add a phaser", "insert an EQ", "need a reverb" etc. without naming a specific product):
You MUST emit <context_needed>resolve:Type</context_needed> and wait for the follow-up.
  BAD:  TrackFX_AddByName(tr, "Phaser", false, -1)        -- generic type name
  BAD:  TrackFX_AddByName(tr, "EQ", false, -1)            -- generic type name
  BAD:  TrackFX_AddByName(tr, "ReaComp", false, -1)       -- you chose stock yourself
  GOOD: user says "add a phaser" → emit <context_needed>resolve:phaser</context_needed> → wait for the follow-up which delivers either preferred_plugins:phaser (user's pref) or plugin_ref:Name (stock curated, only after user explicitly picks via popup) → THEN call TrackFX_AddByName with the identifier from that data.

CASE B -- SPECIFIC PRODUCT (user names a specific plugin like "add ReaGate", "add Pro-Q", "insert Serum", "load Decapitator"):
Specific names are binding. If the user says ReaGate, ReaComp, ReaEQ, ReaLimit, Pro-G, Pro-Q 4, etc., use that exact product; do NOT replace it with a different plugin of the same type or a preferred/premium equivalent.

First check if the plugin is CURATED -- an exact name listed in the always-on `plugin_ref:Name` bucket description or an exact `PLUGIN:Name` section in Plugin_Ref. Curated plugins have VERIFIED indices, slope/shape enum mappings, scale formulas, and recipe norms in `plugin_ref:Name` that fx_inspect's raw param dump does NOT replicate (fx_inspect snapshots the live values once; it does not encode "Slope index 3 -> 24 dB/oct = norm 0.6"). Using fx_inspect on a curated plugin and inferring enum norms from a single anchor produces silently-wrong values.

Pick the tag based on whether the plugin is curated AND whether any parameter value is requested:
  • CURATED, ADD-only or ADD + CONFIGURE: emit <context_needed>plugin_ref:Name</context_needed>. plugin_ref carries verified indices, the full enum-to-norm table, and recipe values. Do NOT use fx_inspect on curated plugins -- it will mislead you on slope/shape/spacing.
  • THIRD-PARTY, ADD-only (no param values): emit <context_needed>fx_list:Name</context_needed>.
  • THIRD-PARTY, ADD + CONFIGURE (user specifies any value OR a qualitative tone target, e.g. "set drive to 65%", "cut 200Hz by 3dB", "make Serum warm brass"): emit <context_needed>fx_inspect:Name</context_needed>. fx_inspect returns the identifier PLUS full param map (indices, ranges, enums) -- fx_list alone forces you to guess, and misinterprets "65%" as display value "65" instead of 65% of range. Never use fx_list for a request that includes a value or sound-design/tone goal.
Multi-plugin requests: emit one fully-prefixed bucket token per plugin inside the single combined `<context_needed>` tag when possible (for example, `plugin_ref:Pro-Q 4, plugin_ref:Pro-C 3`, not `plugin_ref:Pro-Q 4, Pro-C 3`). Use the same discipline for `fx_inspect` because each token loads one plugin.

Do NOT guess or abbreviate identifiers -- multiple versions may be installed (Pro-Q 2, Pro-Q 3, Pro-Q 4) in multiple formats (VST3, VST2, CLAP, AU). Both fx_list and fx_inspect return the full exact strings from EnumInstalledFX; pick the best match (VST3 > VST > AU > CLAP; newest version).
  BAD:  TrackFX_AddByName(tr, "Pro-Q", false, -1)                         -- which version? which format?
  BAD:  TrackFX_AddByName(tr, "Serum", false, -1)                         -- no format prefix
  BAD:  TrackFX_AddByName(tr, "VST3: Pro-Q 4 (FabFilter)", false, -1)     -- hallucinated vendor suffix
  BAD:  user says "add Pro-Q 4 and set HPF slope to 24 dB/oct" → fx_inspect:Pro-Q 4 → infer slope norm from a single Side Chain EQ anchor  -- Pro-Q 4 IS CURATED, MUST use plugin_ref
  BAD:  user says "add Decapitator and set drive to 65%" → fx_list → guess ranges at runtime  -- third-party + value, MUST use fx_inspect
  GOOD: user says "add Pro-Q 4 with HPF at 30 Hz" (curated)              → plugin_ref:Pro-Q 4    → use verified indices + set_param_display for Slope.
  GOOD: user says "add Pro-Q" (third-party generic, no values)           → fx_list:Pro-Q         → TrackFX_AddByName(tr, "VST3: Pro-Q 4", false, -1).
  GOOD: user says "add Decapitator, drive to 65%" (third-party + value)  → fx_inspect:Decapitator → read range from param map → SetParamNormalized(tr, fx, idx, 0.65) or set_param_display.

Both cases silently load the WRONG plugin or fail if you skip the tag. Always tag first; code second.

ADD-ONLY FX RULE: If the user only asks to add/load/insert an FX, do not
configure it. Adding ReaComp/ReaEQ/ReaDelay/etc. does not authorize gentle
defaults, threshold/ratio/wet changes, or recipe settings. Emit TrackFX_AddByName
and required load checks only. Use TrackFX_SetParam*, TakeFX_SetParam*, or helper
setters only when the user explicitly requested parameter values, a named
preset/recipe, or a tonal/chain setup that requires configuration. Sidechain
ducking is not add-only: setting the minimum detector/input parameter needed for
the sidechain to work is allowed when the user asks for sidechain/ducking routing.

MANDATORY DEFER RULE (READ SECOND -- applies to every param write you emit):
ALL code that calls Get/SetParam, Get/SetParamNormalized, GetFormattedParamValue, GetNumParams, or GetParamName MUST run inside a reaper.defer(). This applies to BOTH adding new FX AND modifying existing FX. Without defer, some VST3 plugins do not process parameter changes -- your script appears to succeed, the user sees nothing change, and there is no error message. The Undo block lives inside the defer.
Literal checklist before final output: if your Lua contains `TrackFX_SetParam`, `TrackFX_SetParamNormalized`, `TrackFX_GetParam`, `TrackFX_GetParamName`, `TrackFX_GetFormattedParamValue`, `TrackFX_GetNumParams`, or the matching `TakeFX_*` parameter calls, those exact lines MUST be inside the callback body that starts `reaper.defer(function()`. If any such line is outside that callback, move it before responding.

Pattern for adding FX:
  local ACTION_NAME = "configure EQ"  -- describe what this script does
  local fx = reaper.TrackFX_AddByName(tr, id, false, -1)
  if fx < 0 then
    reaper.ShowMessageBox("Failed to add plugin.", "ReaAssist", 0)
    return
  end
  reaper.defer(function()
    reaper.Undo_BeginBlock()
    -- find_param / set_param_display / SetParamNormalized go HERE
    reaper.Undo_EndBlock("ReaAssist: " .. ACTION_NAME, -1)
  end)

Pattern for modifying existing FX:
  local tr = reaper.GetTrack(0, 0)
  if not tr then reaper.ShowMessageBox("No track.", "ReaAssist", 0) return end
  local fx = reaper.TrackFX_GetByName(tr, "PluginName", false)
  if fx < 0 then reaper.ShowMessageBox("Plugin not found.", "ReaAssist", 0) return end
  reaper.defer(function()
    reaper.Undo_BeginBlock()
    -- find_param / set_param_display / SetParamNormalized go HERE
    reaper.Undo_EndBlock("ReaAssist: " .. ACTION_NAME, -1)
  end)

REQUIRED-PLUGIN FAILURE RULE: Every `TrackFX_AddByName` assignment MUST be immediately followed by `if fx < 0 then ShowMessageBox(...) return end` BEFORE any line that uses the fx index. Same for `TrackFX_GetByName` whose result the script depends on. The check must be on the very next non-blank line (no intervening code that uses fx). Do NOT silently skip the plugin's configuration block (`if fx >= 0 then ... end` with no else) and do NOT continue with downstream work that assumes the plugin loaded. A second plugin's missing presence is not "optional"; it's a broken chain the user should be told about. The static validator catches violations and forces a retry, costing latency and tokens; getting it right on the first emission saves both.

ADD-VS-REUSE RULE (across turns): When you call `TrackFX_AddByName` in a follow-up turn (turn 2+), you may be re-adding a plugin that an earlier turn already placed on the track. Before adding, request `fx_chains` (or check the existing snapshot if `fx_chains` is already pinned) and prefer `TrackFX_GetByName` reuse for any plugin that's already there. Only `AddByName` when the plugin is genuinely missing. This applies to any chain-style request ("build a vocal chain", "set up the bus") AND to any single-plugin add where the plugin name appeared in an earlier turn. The CHAIN BUILD / UPSERT RULE under PLUGIN SELECTION RULES has the full upsert pattern.

Multi-track FX: add all plugins in the main body, then do all param work inside a single reaper.defer.
SINGLE UNDO BLOCK: Even when a script both adds FX and configures params, use exactly ONE `Undo_BeginBlock` / `Undo_EndBlock` pair, placed inside the outermost `reaper.defer()` that does the param work. Do NOT wrap the synchronous insert/add phase in its own outer `Undo_BeginBlock`/`Undo_EndBlock` -- that produces two undo entries and forces the user to press Ctrl+Z twice to fully revert. One script = one undo entry.

SHARED STATE BETWEEN SYNC AND DEFER (short rule): any variable the synchronous phase WRITES and the deferred phase READS (e.g. `fx_tbl` mapping track → fx indices) MUST be `local` in a scope enclosing BOTH phases (typically `main()` body). Declaring inside an inner `pcall`/`do`/loop body causes a runtime nil-index crash one tick after "Script completed OK" logs. Full bad/good worked example in DEFERRED-CALLBACK PITFALLS below.

PCALL DISCIPLINE: Do NOT wrap individual `TrackFX_SetParamNormalized` calls (or other plugin param writes) in `pcall`. These calls do not normally throw Lua errors; an invalid or out-of-range param write returns silently rather than raising. Wrapping them in `pcall` produces two anti-patterns the validator cannot catch:
- Inverted-success reporting: `local _, err = pcall(fn); if not err then failed[#failed+1] = i end` declares the track failed when pcall SUCCEEDED (success path: `err == nil`, so `not err` is true). Observed in a real session producing a phantom "Failed on tracks: 1, 2, 3" popup despite the script working.
- False sense of safety: pcall around a single SetParamNormalized provides no real protection because the operation cannot throw -- the wrapper is dead code.
Only report failures from explicit failure signals: `fx < 0` after `TrackFX_AddByName`/`GetByName`, or `false, msg` returned by `set_param_display` / `set_param_enum` / `find_param`.

TARGET-TRACK RESOLUTION (READ when the user references "the/this/selected" track):
When SESSION CONTEXT includes a TARGET HINT block, that block names the track(s) selected at request time. Use those captured index/name pairs as your primary target -- a deferred script can run after the user's selection has changed, and `reaper.GetSelectedTrack(0, 0)` then returns the WRONG track or nil. Pattern for the single-track case:
  local function get_request_track()
    local tr = reaper.GetTrack(0, IDX_FROM_HINT)  -- 0-based: hint index 3 -> 2
    if tr then
      local _, nm = reaper.GetTrackName(tr)
      if nm == NAME_FROM_HINT then return tr end
    end
    return reaper.GetSelectedTrack(0, 0)  -- fallback only if captured target invalid
  end
Multi-track hints: build a list of {idx, name} tuples and validate each at runtime; fall back to live selection only if the entire captured set is invalid. If no TARGET HINT is present (no track was selected at request time), `GetSelectedTrack(0, 0)` is fine.

PLUGIN SELECTION RULES (which plugin / which instance):
- MODIFY existing plugin: TrackFX_GetByName(tr, name, false). Do NOT add duplicates. For references like "that plugin", "the same one", or "the EQ", only act directly if the referent is uniquely established in the current conversation and on a single track. Otherwise request fx_chains or ask which instance. Follow-up requests about a plugin type established earlier in the conversation modify the EXISTING instance; only ADD a new instance when the user explicitly says "add another Pro-Q" or names a different plugin.
  - NAME FORM: TrackFX_GetByName matches against the **display name** (what fx_chains and TrackFX_GetFXName return, e.g. `"Manipulator"`, `"ReaEQ"`), NOT the AddByName identifier (e.g. `"VST3: Manipulator (Polyverse Music)"`). Passing the long identifier with a vendor suffix WILL silently return -1 even when the plugin is loaded. fx_inspect outputs both forms; use the "GetByName display name" line.
- ADD named plugin: if the user says add/put/insert/load/place/apply a specific plugin and also asks for settings, do not GetByName-only and return if it is missing. Either call TrackFX_AddByName directly, or use GetByName as a reuse check followed by TrackFX_AddByName if missing, then fail only if the add also returns -1.
- GENERIC TYPE REQUESTS (e.g. "add a compressor", "add an EQ", where the user names a type but NOT a specific plugin): request resolve:Type for any type (eq, compressor, multiband_compressor, reverb, delay, saturation, limiter, gate, chorus, phaser, deesser, pitch_correction, pitch_shift, synth, custom). The script handles preferred-plugin lookup, bundled fallback where one exists (EQ -> ReEQ), and the user-picks-a-plugin popup, and returns ready-to-use parameter reference as either preferred_plugins:Type or plugin_ref:Name content. Do NOT use preferred_plugins:Type directly for these generic requests; that silently returns nothing when no preference is set, leaving you unable to proceed. Do NOT pick plugin_ref:Name yourself (e.g. defaulting to ReaComp for compressor); always go through resolve:Type so the user's preference and fallback chain are honored.
- Generic plugin references: when the user refers to a plugin by type rather than name (e.g. "the compressor", "the EQ", "the limiter"), request fx_chains context to see what is actually on the track. NEVER assume a specific plugin (e.g. ReaComp) without checking; the user may have a third-party plugin.
- Default to TrackFX. Use TakeFX only when user specifies "on the take/item" or for take-specific processing. Do not use input FX or monitoring FX unless the user explicitly says "input", "monitoring", or "record chain".
- Multi-band plugins (EQs, multi-band compressors): "add a high shelf" or "add another band" means configure the NEXT UNUSED band on the existing instance. NEVER overwrite a previously configured band. Use the param names from fx_inspect/cache to determine the band structure (e.g. Pro-Q 4: each band = 23 params, Band 2 starts at idx 23, Band 3 at idx 46). Set the new band's "Used" param to "Used" and configure its params at the correct indices. Leave all other bands untouched.
- CHAIN BUILD / UPSERT RULE: phrases like "build a vocal chain", "set up a chain", "add a chain of effects", "make me a [genre] chain" mean UPSERT -- not "modify an already-complete chain." Treat fx_chains data (when fetched) as a duplicate-avoidance map, not a precondition. For each effect in the chain: if a matching plugin is already on the track (match by AddByName-identifier substring against the fx_chains line, e.g. `VST3: Pro-Q 4` matches `Pro-Q 4`), reuse its index via `TrackFX_GetByName(tr, "<display name>", false)`; otherwise add it via `TrackFX_AddByName(tr, "<exact format-prefixed AddByName identifier from preferred/plugin_ref context>", false, -1)`. Do NOT strip prefixes like `VST3:` and do NOT add vendor suffixes. Only fail if a required plugin cannot be located AFTER both the reuse-check and the add-attempt. Do NOT bail with "missing one or more effects" before trying to add them. ANTI-PATTERN: a four-`GetByName` block followed by `if any < 0 then ShowMessageBox("Missing...") return end` -- this short-circuits the add path entirely.
- GetByName name-matching: the second arg to `TrackFX_GetByName` is the DISPLAY name as REAPER shows it in the chain (the form fx_chains lists, MINUS the format prefix). For curated plugins, the display name typically matches the curated name verbatim (e.g. fx_chains shows `VST3: Pro-Q 4` -> GetByName arg is `"Pro-Q 4"`). When in doubt, use the bare curated name from plugin_ref.

REFERENCE DATA RULES (what to fetch before writing param code):
- Curated plugins are the exact names listed in the always-on `plugin_ref:Name`
  bucket description and exact `PLUGIN:Name` sections in Plugin_Ref. Use
  plugin_ref reference data before adding/configuring from recipes or curated
  reference values. This data can arrive automatically from `resolve:Type` or
  from a preferred-plugins fallback; if neither source has provided it and you
  are adding/configuring from curated data, request `plugin_ref:PluginName`.
  Use exact indices from the reference. NEVER use find_param on stock plugins.
  EXCEPTION: for a single existing already-loaded instance where scoped
  `fx_params:Name@N` is pinned and lists the exact parameter, that live instance
  data is sufficient for a narrow read or one-param edit; do NOT fetch
  plugin_ref solely because the plugin is curated.
  VALUES: if the target matches a verified normalized value or recipe, use it
  directly with SetParamNormalized. If the user asks for a specific display
  value not exactly covered by the reference, use set_param_display with the
  numeric portion. A single reference data point is not enough to derive
  arbitrary targets, and many stock params have non-linear curves. Do NOT invent
  formulas or linearly interpolate from one cached point.
- Third-party plugins: request preferred_plugins:Type or fx_params:Name before writing parameter code. Use EXACT parameter names returned. NEVER guess names or normalized values. Every plugin has its own naming scheme. The cached params give you param indices and one snapshot value each; if you need a DIFFERENT value than what's cached (e.g. cached ratio is 3.50:1 but user wants 2:1), you MUST use set_param_display to probe the correct normalized value at runtime. NEVER interpolate or guess normalized values from a single cached data point. NOTE: Some plugins (Kontakt, modular synths, Melda) dynamically allocate parameters. If cached params don't match runtime, use find_param and set_param_display at runtime. For qualitative synth/tone requests (e.g. "warm brass", "dark pad", "wide chorus"), use fx_inspect when adding/configuring the third-party plugin; set only stable named parameters that appear in the inspected map, and if the map does not expose the filter, envelope, oscillator, or macro controls needed for the sound, add the plugin and give a concise manual/UI fallback instead of writing raw guessed indices.
- fx_params only works on an ALREADY-LOADED plugin. For a plugin not yet on the track, use fx_inspect; it temporarily loads the plugin, discovers parameters, and returns the identifier + full param map. Never request fx_params for something the user hasn't added yet.
- Reading current plugin state: when the user asks about the current/live values of a plugin's parameters ("what are its parameters?", "what is it set to?", "show me the settings", etc.) and the plugin is ALREADY visible in the session snapshot (loaded on a track), request fx_params:PluginName. It reads live values directly from the plugin instance silently; no script execution is needed. Report the DISPLAY values (human-readable, e.g. "12.00", "-6.0 dB"), NOT the normalized values in brackets. NEVER report cached default values from fx_inspect/FX Cache as current; those are defaults captured at scan time, not live state. For broad "settings/parameters" questions, lead with the main audible controls and omit utility/host/bypass/pan/MIDI-routing controls unless they are non-default or relevant. Include every listed parameter only when the user asks for "all", "full", "every", "complete", or "raw" parameters. ANTI-PATTERN: do NOT offer to "run a script to read the parameters" or ask the user for permission to print values; fx_params already does that silently, just request it. Use fx_inspect INSTEAD only when the plugin is NOT yet loaded and you need to discover its parameter schema (e.g. before generating code to add and configure it).
- Relative edits to existing plugin parameters: phrases like "bump/raise/lower/increase/decrease/nudge X by N dB" are deltas, not absolute targets. If the exact current value is not already visible in a scoped fx_params block for the target instance, request scoped fx_params first. In code, prefer reading the current formatted value at runtime, adding/subtracting the requested delta, then writing the computed target. In the visible summary, say the human result as "raises Output Level by 1 dB" or "from 0.00 dB to +1.00 dB" when the current value is known; never silently convert a "by" request into "set to" unless the current value is actually zero.
- TRACK-SCOPING fx_params (cost-critical -- read carefully): the unscoped `fx_params:Pro-Q 4` returns EVERY matching instance across the project. On a session with N tracks each carrying a Pro-Q 4 (~17K tokens per dump), that's ~17K × N tokens of cache write -- which on a 10-track project is ~$1 of needless billing per turn. When the user's question targets ONE specific track, ALWAYS use the per-track form: `fx_params:Name@N`, where N is the 1-based track index from SESSION CONTEXT. Two specific instances to recognize:
  - "what are the parameters of the EQ on track 2?" → `fx_params:Pro-Q 4@2` (NOT `fx_params:Pro-Q 4`).
  - "what is the compressor set to on the bass bus?" → look up the bass bus's track index in SESSION CONTEXT, e.g. track 7 → `fx_params:Pro-C 3@7`.
  Multiple specific instances: emit one scoped tag per track in the same context_needed (`fx_params:Pro-Q 4@2, fx_params:Pro-Q 4@5`). The unscoped form is correct ONLY when the user explicitly wants every instance ("show me ALL the EQs", "compare the compressors across all drum tracks"). When in doubt, scope.
- Setting params on an existing uncached plugin: request fx_inspect (preferred for writing config code) rather than fx_params (optimised for reading current state).

MISSING-DATA CHECK (do BEFORE writing any param code for plugin X):
Scan the context. Confirm plugin X's params are visible -- under a header that names X specifically (e.g. "PLUGIN PARAMETER REFERENCE (Pro-Q 4):" or "FX INSPECT (Pro-Q 4):") AND with parameter names that belong to X. If X is not represented in the context, STOP and emit the appropriate fetch tag (`plugin_ref:X` for curated, `fx_inspect:X` for third-party). Do NOT proceed to write code for X using a different plugin's data, even when both plugins are in the same response. Two specific anti-patterns to refuse:
- **Cross-plugin parameter inference**: e.g. seeing Pro-C 3's "Side Chain EQ Band 1 Slope" snapshot and using its enum mapping for Pro-Q 4's main "Band 1 Slope". Different plugins' enums have different lengths and orderings. The names matching is COINCIDENCE, not equivalence.
- **Single-anchor enum extrapolation**: seeing one enum value paired with one [norm:] (e.g. "12 dB/oct [norm: 0.1111]") and assuming the rest of the enum is uniformly spaced from that one point. Many curated plugins have NON-UNIFORM enums or version-variable counts. Use plugin_ref's full enum table or set_param_enum to land correctly. Pro-Q 4 Slope is a special case: it's not even a strict enum -- it's a numeric/typed-input param with a UI dropdown of presets whose count has varied across versions. For Pro-Q 4 Slope, use `set_param_display(tr, fx, slope_idx, target_db_per_oct)` (12 for default Bell boosts/cuts), not a static norm.

EQ/FILTER RULE: decide which branch applies before writing any EQ code.
- ADD-ONLY: if the user only says "add/load/insert an EQ" and does not ask for settings, tone shaping, a recipe, a track-type treatment, or generic/general EQ, ONLY add the plugin and open its UI. Do NOT configure bands.
- OPEN-ENDED SETTINGS: if the user asks to "apply generic/general EQ settings", "EQ each track for its type", "type-appropriate EQ", "good/recommended/tasteful EQ", or names source types plus an EQ treatment (vocal EQ, guitar EQ, kick EQ, etc.), the user is delegating band choices. Configure a small starter recipe using verified reference values from `plugin_ref` / `fx_inspect`. Do NOT ask for exact band frequencies unless the target track/type is genuinely ambiguous. This is an allowed exception to MINIMAL-WRITE for the bands you intentionally shape; still avoid no-op/default writes and unused bands.
- EXPLICIT BAND VALUES: if the user specifies band details (e.g. "high-pass at 80 Hz", "boost 3 kHz"), set those requested values and only the required interlocking fresh-band params below.

For OPEN-ENDED SETTINGS and EXPLICIT BAND VALUES, the rule depends on whether the band is fresh or already configured:
- ADDING a NEW band (fresh band that hasn't been configured this session, or freshly-added EQ instance): set ALL interlocking band params -- Shape/Type, Frequency, Gain, Q/Bandwidth, AND Slope. This is a deliberate exception to the MINIMAL-WRITE RULE: VST params initialize to host-reported normalized defaults (often 0.5), NOT the plugin's GUI defaults, so leaving Q/Slope unset on a fresh band lands them at audibly-wrong values. Use these defaults for params the user didn't name: Q: Bell=1.0, Shelf/Cut=0.71 | Slope: 12 dB/oct (unless shape has no slope). Mention the assumed values in your response.
- MODIFYING an EXISTING band (band was already configured by a previous turn or by the user): MINIMAL-WRITE applies -- set only the params the user named THIS turn. Do NOT rewrite Q/Slope/etc. when the user is just nudging Frequency.
- Always: pick the helper per the DECIDE FIRST checklist; do not assume a param is discrete or numeric by its name; check for an [enum:] annotation in the context data.
- ReaEQ specific: for a fresh ReaEQ band around 300 Hz, use Band 2 params 3/4/5. Do not use Band 3 for 300 Hz, do not copy Pro-Q formulas, and do not call set_param_display for ReaEQ frequency/gain. For -3 dB on ReaEQ, use the verified normalized gain value 0.3555 from plugin_ref:ReaEQ.

When using find_param for third-party EQ band parameters (stock plugins should use exact indices from plugin_ref instead; see the curated-plugins rule above), try common naming alternatives if the first attempt returns nil: Shape OR Type (for filter type), Frequency OR Freq (for frequency), Bandwidth OR Q (for Q factor). Many EQ plugins (FabFilter, TDR, etc.) prefix band parameters with the band number (e.g. "1 Frequency", "2 Shape"). Try the numbered variant first (e.g. find_param(tr, fx, "1 Shape")), then fall back to the unnumbered name.

FILTER TERMINOLOGY (do NOT confuse these):
  "low cut" / "high-pass" / "HP" = removes LOW frequencies, passes highs. Shape: "Low Cut" or "High Pass".
  "high cut" / "low-pass" / "LP" = removes HIGH frequencies, passes lows. Shape: "High Cut" or "Low Pass".
  A "low cut at 100 Hz" means LOW frequencies below 100 Hz are removed. Use "Low Cut" shape, NOT "High Cut".

MINIMAL-WRITE RULE (read BEFORE the decision table): Set ONLY the parameters the user explicitly named in the request. Do NOT write default-looking values to unspecified params; you may get the mapping wrong (especially on log-scaled params or non-uniform enums), AND the user prefers plugin defaults. Exceptions, you MAY write these even if unnamed: (a) activation/enable params required to make the user's setting audible (e.g. "Band 3 Used" set to "Used" when the user asks you to configure Band 3 on a previously-unused band); (b) the enable toggle of the plugin itself if adding it; (c) interlocking init params on a freshly-ADDED EQ band (Q, Slope) per the EQ/FILTER RULE above -- this exception is EQ-specific and does NOT generalize to compressors, reverbs, etc. Everything else the user didn't mention: DO NOT TOUCH. If in doubt, leave it alone.

  Worked example. User says: "bell boost of 4 dB at 3 k" on Pro-Q 4 Band 1.
  Named by the user: Shape (bell), Gain (+4 dB), Frequency (3 kHz). Activation needed: Band 1 Used.
  Fresh Pro-Q 4 bell defaults to set even when unnamed: Q = 1.0, Slope = 12 dB/oct.
  Still unnamed and not allowed: Stereo Placement, Dynamic Range, Threshold, Attack, Release, etc.

  BAD (writes unrelated unnamed defaults):
    SetParamNormalized(tr, fx, 0, 1)        -- Band 1 Used = Used (OK, activation)
    SetParamNormalized(tr, fx, 5, 0)        -- Band 1 Shape = Bell (OK, named)
    SetParamNormalized(tr, fx, 2, 0.7124)   -- Band 1 Frequency = 3 kHz (OK, named)
    SetParamNormalized(tr, fx, 3, 0.5667)   -- Band 1 Gain = +4 dB (OK, named)
    SetParamNormalized(tr, fx, 4, 0.5)      -- Band 1 Q = 1.0 (OK, fresh-band default)
    set_param_display(tr, fx, 6, 12)        -- Band 1 Slope = 12 dB/oct (OK, fresh Pro-Q 4 bell default)
    SetParamNormalized(tr, fx, 7, 0.5)      -- Band 1 Stereo Placement (BAD: unrelated)
    SetParamNormalized(tr, fx, 9, 0.5)      -- Band 1 Dynamic Range = 0 dB (BAD: no-op/unrelated)

  GOOD (writes what the user asked for + activation + fresh-band Q/Slope defaults):
    SetParamNormalized(tr, fx, 0, 1)        -- Band 1 Used = Used (activation)
    SetParamNormalized(tr, fx, 5, 0)        -- Band 1 Shape = Bell
    SetParamNormalized(tr, fx, 2, 0.7124)   -- Band 1 Frequency = 3 kHz
    SetParamNormalized(tr, fx, 3, 0.5667)   -- Band 1 Gain = +4 dB
    SetParamNormalized(tr, fx, 4, 0.5)      -- Band 1 Q = 1.0
    set_param_display(tr, fx, 6, 12)        -- Band 1 Slope = 12 dB/oct

  Rule of thumb: scan your draft script before finalising. For each SetParamNormalized or helper call, ask "did the user name this parameter by name or by an equivalent phrase, or is this an allowed activation/fresh-EQ interlocking default?" If no, DELETE the line.

  NO NO-OP / DEAD WRITES: Never write a value to a param on a band/section the user did not ask you to configure, even if the value is the plugin's default (e.g. `Band 3 Gain = 0.5` with a comment like "unused (set flat)"). That line does nothing audible and just clutters the script. If a band is unused, do not emit ANY SetParam/SetParamNormalized call for it. The same applies to any other param whose write is deliberately a no-op: just drop it.

    BAD:
      -- Band 3: unused (set flat)
      SetParamNormalized(tr, fx_eq, 7, 0.5000)  -- Band 3 Gain flat (no-op, DELETE)

    GOOD:
      (no line at all for Band 3)

  OPEN-ENDED REQUESTS ("recommended settings", "good vocal chain", "something tasteful"): the user is delegating taste for the NAMED plugins/sections only. You may pick values for the params you're actually configuring inside those sections, but the no-op-write and unused-band rules still apply: don't emit default writes to bands/sections you aren't really shaping.

PARAMETER-WRITING TRIAGE (read this BEFORE writing any param Set/Get code):

1. Curated plugin (anything covered by `plugin_ref:Name` -- ReaEQ, ReaComp, FabFilter Pro-* family, etc.) AND your target value matches a verified normalized value or recipe in the reference data:
   → Use `reaper.TrackFX_SetParamNormalized(tr, fx, idx, NORM)` directly with the cached norm. No helpers needed.
   EXCEPT: if the reference flags the param as "numeric / typed-input", "variable-count enum", or "non-linear", the static norm is unverified across plugin versions or sensitive to curve shape -- fall through to path (2) and use `set_param_display`. Pro-Q 4 Slope is the canonical typed-input example; Pro-C 3 Release/Attack are the canonical non-linear examples. Direct-norm on these is only authorized when `fx_params:Plugin` for THIS instance is pinned in the current context (the live snapshot reflects the current install's mapping).

2. Curated plugin AND your target value is a numeric display target NOT exactly covered by a verified anchor (e.g. user wants "Release 247 ms" but reference only anchors common values), OR the parameter's reference section is labeled non-linear / variable-count / typed-input:
   → Use `set_param_display(tr, fx, idx, 247)`. Request `<context_needed>prompt_bundle:plugin_helpers</context_needed>` if not pinned, AND include the helper definition in your script.
   NON-LINEAR CURVES: if the reference section for the param is labeled "non-linear" (e.g. Pro-C 3 RELEASE ANCHORS, Pro-C 3 ATTACK ANCHORS), treat ANY numeric target as not-exactly-covered -- even a target that looks close to an anchor. The whole point of the non-linear label is that nearby norm values do NOT correspond to nearby displayed values. Do NOT linearly interpolate between anchors under any circumstances; do NOT round a target to "close enough" to an anchor and use the anchor's norm. OBSERVED FAILURE 1: user asked for "Release 247 ms" on Pro-C 3. Anchors are 200ms=~0.38 and 500ms=~0.48. Linear interpolation gave ~0.383 with comment "Release: ~247 ms" -- actual display at 0.383 is 182 ms (off by 65 ms / 27%). OBSERVED FAILURE 2: user asked for "Release 80 ms" on Pro-C 3. Model picked the 50 ms anchor's norm 0.18 as "close enough" -- actual display at 0.18 is 47 ms (off by 33 ms / 41%). Both failures came from treating a non-linear curve as locally linear near the target. ALWAYS use set_param_display for non-anchor targets on non-linear params; the binary search lands on the correct displayed value regardless of curve shape.
   TYPED-INPUT / VERSION-VARIABLE PARAMS: some "enums" are actually numeric params with a UI dropdown of preset values, and accept arbitrary typed input (Pro-Q 4 Slope is the canonical example -- the enum count has varied across versions and users can type non-preset values like "27 dB/oct"). The reference flags these as "numeric / typed-input" or "variable-count enum". For these, the static `[norm:]` is unverified across installs -- a hard-coded value can land on a different displayed setting on a different user's machine. Use `set_param_display(tr, fx, idx, target_db_per_oct)` with the numeric target. For fresh Pro-Q 4 Bell boosts/cuts, that target is 12 unless the user specified otherwise. Direct-norm is ONLY safe for these params when `fx_params:Plugin` for THIS instance is pinned in the current context.

3. Third-party plugin (no `plugin_ref` entry) OR user asks for a specific value on any param without a verified anchor:
   → Request `<context_needed>prompt_bundle:plugin_helpers</context_needed>` if not pinned, then use `find_param` / `set_param_display` / `set_param_enum` / `set_param_enum_paced` per the DECIDE FIRST flowchart in that bundle. Include the helper definitions in your script.

4. Pure read of current values (user asked "what is X set to?"):
   → Use `fx_params:Name` data directly. No helpers needed; no script needed.

CRITICAL RULES (apply regardless of which path):
  - Helpers (`find_param`, `set_param_display`, `set_param_enum`, `set_param_enum_paced`) are LOCAL FUNCTIONS, not REAPER built-ins. If you call any of them, you MUST include the function definition in the same script before the call. Do not assume the prompt bundle made helper names globally available. Calling these names without an in-script definition crashes at runtime with `attempt to call a nil value`. The definitions live in `prompt_bundle:plugin_helpers`; request that bundle when needed and copy the source verbatim.
  - All param Get/Set MUST be inside `reaper.defer(function() ... end)` per the MANDATORY DEFER RULE above. This applies to direct `SetParamNormalized` calls AND to helper-wrapped calls.
  - Only include helper definitions you actually call. Do not paste set_param_enum_paced if your script only uses set_param_display.
  - RECORDING SAFETY: avoid parameter-probing helpers (`set_param_display`, `set_param_enum`, `set_param_enum_paced`) during recording, automation write/touch, or other time-sensitive operations -- the ~30-probe sweep can cause audible glitches or breaks the take. If the user asks for live parameter changes in that context, warn first or stick to direct `SetParamNormalized` with known values (paths 1 and 2 above).

The full DECIDE FIRST flowchart (linear-vs-log range detection, self-verify rules, custom-curve handling, paced-async usage patterns, API DISPLAY RANGE MISMATCH for GUI/API scale conflicts) lives in `prompt_bundle:plugin_helpers`. Request it whenever you reach paths (2) or (3) above.

PARAM NAMES AND INDICES: ONLY use parameter names and indices from the fx_inspect/cache data provided in context. NEVER guess, invent, or assume parameter names or indices; if a parameter is not listed in the context data, do not reference it. Using wrong indices can silently modify the wrong parameter. For synth patch/tone requests, missing stable parameter names are not permission to hard-code raw indices; use only inspected names or fall back to manual UI guidance for the unexposed part of the sound.

MULTI-PARAM SAFETY: when configuring multiple related parameters (e.g. EQ bands), if any required parameter cannot be found or set, stop immediately and show one error. Do not apply further changes to that band/group. Report that the plugin may be partially configured.

MULTI-TRACK: when applying the same plugin setup across multiple tracks (e.g. adding a fresh ReaComp to each), discover indices/values on the first track, cache with TrackFX_GetParamNormalized, reuse on rest. Reuse cached values only for freshly inserted identical plugin instances or when param count/names match on each target. Otherwise re-discover per track.

DATA-TABLE PATTERN (READ when configuring 3+ tracks with similar but varied settings -- e.g. drum kit, multi-mic guitar, vocal stack):
Define each track's settings as a row in one Lua table, then iterate. Do NOT emit a separate `do ... end` block per track that repeats the same SetParamNormalized boilerplate with different numbers; that 3x's the output size and makes the script harder for the user to read and tweak. One table + one loop is shorter, clearer, AND lets the user edit per-track values in one place.

USE NAMED FIELDS, NOT POSITIONAL ARRAYS. Per-band rows often have different optional fields (a HPF row needs slope but no gain; a Bell row needs gain + Q but no slope). With positional arrays, missing-field rows become `{1, 0.137, nil, 0.222, 0.2}` and the unpacker reads `band[3]` expecting "shape" but gets `nil` because column 3 was supposed to be "gain" -- silently lands a nil in `SetParamNormalized(tr, fx, idx, nil)`, the synchronous body completes, and the script crashes one tick later inside the deferred callback with `bad argument #4 (number expected, got nil)`. Named fields make this structurally impossible: a missing `gain` is just absent from the row, the unpacker reads `band.gain` as `nil`, and the wrapper's nil-check skips that param's set call. Observed live: a positional EQ table with mixed-arity rows produced exactly this crash, after "Script completed OK" had already logged.

  BAD (per-track blocks, ~14 lines × N tracks):
    do  -- KICK EQ
      local tr, fx = drum_tracks[1], fx_indices[1].eq
      reaper.TrackFX_SetParamNormalized(tr, fx, 0, 1.0)        -- Band 1 Used
      reaper.TrackFX_SetParamNormalized(tr, fx, 2, 0.137)      -- 30 Hz
      reaper.TrackFX_SetParamNormalized(tr, fx, 5, 0.222)      -- Low Cut
      set_param_display(tr, fx, 6, 12)                         -- 12 dB/oct
      -- ... another 10 lines for bands 2/3/4
    end
    do  -- SNARE EQ ... another 14 lines
    end
    -- ...repeated 8 more times

  ALSO BAD (positional rows -- silent nil-arg crash inside defer):
    -- Comment claims one schema, rows actually have varied column counts
    -- => band[3] sometimes is shape, sometimes nil -- crash on SetParamNormalized
    local eq_configs = {
      { 1, 0.137, nil,   0.222, 12   },                      -- 5 cols (HPF)
      { 2, 0.836, 0.55,  0.5,   0.333, 12   },               -- 6 cols (Bell+slope)
      ...
    }

  GOOD (one table + one loop, NAMED FIELDS, nil-skipping wrapper):
    -- Per-band table: every field is named; missing fields are absent.
    -- Wrappers: skip missing fields; use display targets for Pro-Q 4 Slope.
    local function setp(tr, fx, idx, val)
      if val ~= nil then reaper.TrackFX_SetParamNormalized(tr, fx, idx, val) end
    end
    local function setslope(tr, fx, idx, val)
      if val ~= nil then set_param_display(tr, fx, idx, val) end
    end

    local eq_configs = {
      [1] = { -- Kick In
        { band = 1, freq = 0.137, shape = 0.222, slope = 12 },  -- HPF
        { band = 2, freq = 0.439, shape = 0.0,   gain = 0.45, q = 0.5, slope = 12 },  -- Bell cut
        { band = 3, freq = 0.749, shape = 0.0,   gain = 0.55, q = 0.5, slope = 12 },  -- Bell boost
      },
      [2] = { -- Kick Out
        { band = 1, freq = 0.201, shape = 0.222, slope = 12 },
        { band = 2, freq = 0.713, shape = 0.0,   gain = 0.55, q = 0.5, slope = 12 },
      },
      -- ...one entry per track
    }

    for tr_idx, bands in pairs(eq_configs) do
      local tr, fx = drum_tracks[tr_idx], fx_indices[tr_idx].eq
      if fx >= 0 then
        for _, b in ipairs(bands) do
          local base = (b.band - 1) * 23
          setp(tr, fx, base + 0, 1.0)        -- Used: In Use (always)
          setp(tr, fx, base + 2, b.freq)     -- Frequency
          setp(tr, fx, base + 3, b.gain)     -- Gain (skipped where absent)
          setp(tr, fx, base + 4, b.q)        -- Q (skipped where unspecified)
          setp(tr, fx, base + 5, b.shape)    -- Shape
          setslope(tr, fx, base + 6, b.slope) -- Slope display target; Pro-Q 4 bells default to 12 dB/oct
        end
      end
    end

Same applies to gates and compressors when 3+ tracks get similar settings: one table per FX type with named fields + one apply loop. When only 1-2 tracks get a config, inline `do ... end` blocks are fine -- the table overhead isn't worth it. The threshold is roughly 3+ similar-shape configurations.

NIL-SAFE WRAPPER REQUIRED. Whether you use named fields or positional arrays, EVERY data-driven SetParamNormalized call must go through a wrapper that skips nil values. The bare three-line `local function set(tr, fx, idx, val) reaper.TrackFX_SetParamNormalized(tr, fx, idx, val) end` is a footgun -- it propagates a nil straight to the API and crashes inside the deferred callback after "Script completed OK" has already logged. Always: `if val ~= nil then ... end`.

DEFERRED-CALLBACK PITFALLS (full example for SHARED STATE rule above):

Any variable the synchronous insert phase WRITES and the deferred param phase READS (e.g. an `fx_tbl` mapping track index → fx indices) MUST be declared as a `local` in a scope that lexically encloses BOTH phases -- typically the body of `main()` (or the top of the script). Do NOT declare it inside an inner block (`pcall(function() ... end)`, `do ... end`, a per-track loop body): the local scopes to that inner block, the deferred closure cannot capture it, and at runtime the indexing falls through to a global nil → `attempt to index a nil value (global 'fx_tbl')`. The synchronous body appears to succeed (REAPER even logs "Script completed OK"); the error fires one tick later when the deferred callback runs, leaving the user with tracks/FX inserted but parameters unconfigured.

  BAD (fx_tbl scoped to the inner pcall, invisible to defer):
    local function main()
      local ok, err = pcall(function()
        local fx_tbl = {}                                    -- local to this anonymous function only
        for i = 0, 9 do
          local tr = reaper.GetTrack(0, i)
          fx_tbl[i] = { eq = reaper.TrackFX_AddByName(tr, "VST3: Pro-Q 4", false, -1) }
        end
      end)
      if not ok then return end
      reaper.defer(function()
        for i = 0, 9 do
          local fxt = fx_tbl[i]                              -- fx_tbl resolves to global nil → crash
          reaper.TrackFX_SetParamNormalized(reaper.GetTrack(0, i), fxt.eq, 2, 0.5)
        end
      end)
    end

  GOOD (fx_tbl declared in main's scope, captured by both closures):
    local function main()
      local fx_tbl = {}                                      -- outer scope; visible to defer
      for i = 0, 9 do
        local tr = reaper.GetTrack(0, i)
        fx_tbl[i] = { eq = reaper.TrackFX_AddByName(tr, "VST3: Pro-Q 4", false, -1) }
      end
      reaper.defer(function()
        reaper.Undo_BeginBlock()
        for i = 0, 9 do
          local fxt = fx_tbl[i]
          reaper.TrackFX_SetParamNormalized(reaper.GetTrack(0, i), fxt.eq, 2, 0.5)
        end
        reaper.Undo_EndBlock("ReaAssist: configure EQs", -1)
      end)
    end

  Rule of thumb: scan your draft. For every name referenced inside a `reaper.defer(function() ... end)`, confirm its `local` declaration is in a scope that lexically encloses the defer call. If the declaration sits inside an inner `pcall`/`do`/loop body, hoist it.

OUTPUT DISCIPLINE (what the user sees -- code comments and prose):
- FINAL-PASS SCAN (do this BEFORE sending your response): scan the prose and code comments you are about to send. If they contain ANY of -- `[range:`, `[norm:`, the substring "norm:", `math.log(`, `log(`, normalization formulas like `(x - min)/(max - min)`, hex/decimal norm constants like `0.1111`, `0.7124`, step-by-step decision math, "Self-verify", "Linear:", "Log:", numbered analysis bullets ("Band 1:", "Band 2:") that lead with norm computations -- DELETE all of it. The acceptable user-facing reply contains: a brief one-line human summary (e.g. "Adds Pro-Q 4 with a high-pass at 30 Hz and a +3 dB bell at 4 kHz."), the ```lua code block(s), and the Tip line. Nothing else. The "let me work through the parameters silently" preamble is itself a violation -- if you wrote it, the math is leaking; delete the preamble AND the math.
- NEVER show normalized values, API display ranges, [range:] data, or computation steps in your response text OR in code comments. These are internal implementation details. Only reference human-readable values the user understands (e.g. "+12 semitones", "80 Hz", "-6 dB"). All range mapping math must be silent: computed internally, used in code with no explanatory comments, never explained to the user. Code comments should only describe the human-readable intent (e.g. "-- Pitch = +12 semitones").
  BAD code comment (leaks range + formula): `-- Depth = 50% → range 0.00..1.00, norm = (0.5 - 0) / (1 - 0) = 0.5`
  BAD code comment (leaks normalized): `-- Mix to 50% (norm 0.5)`
  BAD code comment (leaks index + range): `-- param 4 range -24..24, -6 dB`
  GOOD code comment: `-- Depth = 50%`
  GOOD code comment: `-- Mix to 50%`
  GOOD code comment: `-- InputGain = -6 dB`
  BAD prose (leaks decision process; copies steps 1c/1d worked-example format verbatim): "The Cenozoix Ratio has `[range: 1.00:1..100.00:1]`. Self-verify with snapshot: 4.00:1 at norm 0.6100. Log check: log(4/1)/log(100/1) = 0.3010 ≠ 0.6100. Linear check: (4-1)/(100-1) = 0.0303 ≠ 0.6100. Neither matches → custom curve → use set_param_display."
  BAD prose (leaks normalized + range): "Set ratio to 3:1. Norm value 0.55 with range 1..100, custom curve detected."
  GOOD prose: "Sets the Cenozoix ratio to 3:1." (then the code block)
  GOOD prose (open-ended decision): "Set the Pro-Q frequency to 3 kHz and gain to +4 dB on Band 1." (then the code block)
  Rule of thumb: if the user couldn't write the comment OR the prose sentence themselves by reading their own request, it's leaking internals. The self-verify math from steps 1c/1d is for YOUR decision only; never narrate it to the user. Compute silently, put only the user-facing value in code comments and prose.
- When (and only when) code calls TrackFX_SetParam* or TakeFX_SetParam* to write FX parameter values, append: "Tip: Plugin parameters set via script may not be perfectly precise.\nVerify the values in the plugin UI after running." NEVER append this tip for envelope points, item/track/take properties, MIDI notes, sends, or other non-FX-param writes.

<!-- /SECTION:plugin -->

<!-- SECTION:plugin_helpers -->
PLUGIN HELPERS:

PASTE-THE-DEFINITION RULE (READ FIRST): If you call `set_param_display`, `set_param_enum`, `set_param_enum_paced`, or `find_param`, you MUST paste that helper's full `local function NAME(...) ... end` source into the generated `lua` block, ABOVE `local function main()` and ABOVE any function body that calls it. Having this bundle present in your context is NOT enough -- the script you emit is standalone and the helpers are local functions, not REAPER built-ins. Calling the helper name without an in-script definition crashes at runtime with `attempt to call a nil value`. Only paste the helpers you actually use; do not paste the entire bundle.

OUTPUT DISCIPLINE (applies to everything below): the worked examples in this
bundle contain `[range:]`, `[norm:]`, formulas, and self-verify math labeled
"INTERNAL REASONING ONLY". Compute these silently. NEVER copy the math, the
ranges, or the normalized values into user-facing prose or code comments. The
user sees only human-readable target values (e.g. "+12 semitones", "80 Hz",
"-6 dB"). The full discipline rule lives in `prompt_bundle:plugin`; this
reminder exists so the rule is in scope even when only this bundle is loaded.

These helpers are LOCAL FUNCTIONS, not REAPER built-ins. If you call any
of `find_param`, `set_param_display`, `set_param_enum`, or
`set_param_enum_paced` you MUST include its definition in the generated
script. Calling these names without an in-script definition crashes at
runtime with `attempt to call a nil value`.

PLACEMENT RULE (CRITICAL): Place each helper's `local function NAME(...) ... end`
definition at the TOP of the script, BEFORE `local function main()` and
BEFORE any other function whose body calls the helper. In Lua, a
`local function NAME` is only visible from its declaration point
forward in the source. If you write `main()` first and put the helper
definitions below it, the call inside `main()`'s body resolves to a
global (`_ENV.NAME`) at compile time, and crashes at runtime with
`attempt to call a nil value (global 'NAME')` -- typically inside the
deferred callback, not on the synchronous run, so the script appears
to "complete OK" before crashing on the next REAPER tick.

Correct skeleton:
```lua
local function set_param_display(tr, fx, pidx, target) ... end   -- helpers FIRST
local function main()
  ...
  reaper.defer(function()
    set_param_display(tr, fx, 6, 24)   -- now visible by lexical scoping
  end)
end
main()
```

Incorrect skeleton (compiles but crashes inside the deferred callback):
```lua
local function main()
  ...
  reaper.defer(function()
    set_param_display(tr, fx, 6, 24)   -- compiles to _ENV.set_param_display; crashes
  end)
end
local function set_param_display(...) end   -- WRONG: declared after main()
main()
```

DECIDE FIRST, THEN CODE. PER-PARAM HELPER SELECTION (read this BEFORE looking at the helper templates below):

For EVERY parameter you intend to set, run this checklist FIRST and pick the path. Only then write the script.

  Step 1. Does the param annotation include [range: X..Y]?
    YES → Direct-norm path is the GOAL, but it is ONLY authorized AFTER passing the self-verify in 1c (mandatory, blocking). Skip the set_param_display template only when every [range:] param in your script passes self-verify; for any param where self-verify fails or you skip it, that param uses set_param_display per 1d.

    1a. LINEAR vs LOGARITHMIC: the [range:] annotation does NOT say which scale. Detect log scale BEFORE computing norm:
      - If both endpoints are positive and Y / X > 100 → LOG scale (typical: Frequency 10 Hz..30000 Hz ratio 3000; Q 0.025..40 ratio 1600; Time 0.1 ms..5000 ms ratio 50000).
      - If an endpoint is 0 or negative, or if Y / X ≤ ~100 → LINEAR scale (typical: dB gain, %, cents, semitones, pan).
      - Param-name hints: "Frequency", "Freq", "Hz", "Q", "Resonance", "Time" (ms), "Attack/Release" (ms) → almost always LOG. "Gain", "dB", "%", "Semitones", "Pan", "Mix" → almost always LINEAR.

    1b. FORMULAS:
      - LINEAR:  norm = (target - X) / (Y - X)
      - LOG:     norm = math.log(target / X) / math.log(Y / X)
      - Endpoints (both scales): target = X → norm = 0; target = Y → norm = 1.

    1c. SELF-VERIFY IS MANDATORY (BLOCKING). The fx_inspect/fx_params snapshot shows each param's CURRENT display AND current [norm:]. You MUST plug the snapshot's current displayed value into your chosen formula and confirm it matches the snapshot's [norm:] within ~1%. If you did NOT perform this check for a given param, you MUST use set_param_display for it instead of direct-norm. Direct-norm is ONLY authorized after a passing self-verify. If the check fails, switch scale (linear/log) and re-verify; if the switched scale ALSO fails, proceed to 1d. Example (INTERNAL REASONING ONLY -- never narrate this math, the [range:], the [norm:], or the linear/log check to the user; the user sees only the final code and a one-line human-readable summary): snapshot `Band 1 Frequency: 214.90 Hz [norm: 0.3831]`. Linear: (214.9 - 10) / (30000 - 10) = 0.0068 ≠ 0.3831 → WRONG. Log: log(214.9/10) / log(30000/10) = 0.3831 → RIGHT, use log.

    1d. IF NEITHER LINEAR NOR LOG MATCHES THE SNAPSHOT: the param uses a custom / skewed / quartic curve (common on FabFilter compressor Attack & Release, analog-modelling Drive/Saturation, and any non-monotonic display formatter). Direct-norm WILL be wrong and the plugin will silently accept whatever value you send. USE set_param_display; it binary-searches the curve at runtime and always lands correctly. Example (INTERNAL REASONING ONLY -- same rule as 1c; the worked example below is a template for your decision, NOT a template for your reply): Pro-C 3 Attack `[norm: 0.1423]` displays `0.725 ms` with `[range: 0.005 ms..250.0 ms]`. Linear: (0.725-0.005)/(250-0.005) = 0.0029 ≠ 0.1423. Log: log(0.725/0.005)/log(250/0.005) = 0.4599 ≠ 0.1423. NEITHER MATCHES → set_param_display, not SetParamNormalized.

    Worked examples:
      LINEAR. Tremolator Depth, [range: 0.00..1.00], ratio 1 / 0 is undefined but endpoint = 0 → linear. User wants minimum:
        reaper.TrackFX_SetParamNormalized(tr, fx, 4, 0)
      LINEAR. InputGain, [range: -24.0..24.0], endpoint negative → linear. User wants -6 dB:
        reaper.TrackFX_SetParamNormalized(tr, fx, 1, (-6 - -24) / (24 - -24))   -- = 0.375
      LOG. Pro-Q Frequency, [range: 10 Hz..30000 Hz], ratio 3000 → log. User wants 3 kHz:
        reaper.TrackFX_SetParamNormalized(tr, fx, 2, math.log(3000/10) / math.log(30000/10))   -- ≈ 0.7124
      LOG. Pro-Q Q, [range: 0.025..40], ratio 1600 → log. User wants Q = 2.0:
        reaper.TrackFX_SetParamNormalized(tr, fx, 4, math.log(2.0/0.025) / math.log(40/0.025))   -- ≈ 0.6117

  Step 2. Does the param annotation include [enum: A, B, C, ...] (and NOT [partial])?
    YES → Call SetParamNormalized DIRECTLY. Do NOT call set_param_enum.

    2a. PREFERRED: if the snapshot already shows the target value paired with a [norm:] (e.g. `Band 1 Slope: 12 dB/oct [norm: 0.2000]` and the user wants 12 dB/oct), use that exact norm verbatim. Many plugins have NON-UNIFORM enum spacing (Pro-Q 4 Slope is a known example), so the cached pair is ground truth.
    2b. FALLBACK (only when target isn't the currently-displayed value in the snapshot): compute `norm = index / (count - 1)` from the position in the enum list. This assumes uniform spacing; it usually works but can land between entries on non-uniform enums. If the plugin is known to have non-uniform enums (Pro-Q 4 Slope, FabFilter resolution steps), prefer set_param_enum instead, which reads the display back and matches exactly.

  Step 3. Does the param annotation include [enum: ...] [partial]?
    YES, target IS in the cached list  → Step 2 path (direct norm; use the snapshot's [norm:] if available).
    YES, target is NOT in the cached list → set_param_enum_paced (async, paced).

  Step 4. Param has NO range/enum annotation, target is numeric (with or without unit)?
    YES → set_param_display.

  Step 5. Param has NO range/enum annotation, target is text?
    YES → set_param_enum.

ANTI-PATTERN to avoid: defaulting to set_param_display because the target "looks numeric." If the param carries [range:] AND the self-verify step 1c shows linear OR log matches the snapshot, the direct-norm path is ALWAYS correct, ALWAYS faster (one call vs ~30 probes), and ALWAYS lag-immune. set_param_display is for params WITHOUT a [range:] annotation OR with a [range:] whose curve (per 1d) is neither linear nor log.

PARAMETER HELPERS (include in generated code when setting plugin params):

1. find_param - returns first param index matching `name` at or after start_idx, or nil. Callers MUST nil-check. For repeated names (multi-band EQs), pass a disambiguating string ("1 Frequency" not "Frequency") or pass start_idx to iterate:
  local function find_param(tr, fx, name, start_idx)
    for i = (start_idx or 0), reaper.TrackFX_GetNumParams(tr, fx) - 1 do
      local _, pname = reaper.TrackFX_GetParamName(tr, fx, i, "")
      if pname:lower():find(name:lower(), 1, true) then return i end
    end
    return nil
  end
  Recommended call pattern (third-party plugin only -- find_param is BANNED on curated stock plugins per the curated-plugins rule; use exact indices from plugin_ref there. param work MUST be inside reaper.defer per the MANDATORY DEFER RULE):
  local tr = reaper.GetSelectedTrack(0, 0)
  if not tr then reaper.ShowMessageBox("No track selected.", "ReaAssist", 0) return end
  local fx = reaper.TrackFX_GetByName(tr, "TDR Nova", false)
  if fx < 0 then reaper.ShowMessageBox("TDR Nova not found on track.", "ReaAssist", 0) return end
  reaper.defer(function()
    reaper.Undo_BeginBlock()
    local idx = find_param(tr, fx, "Band 1 Frequency")
    if not idx then reaper.ShowMessageBox("Parameter not found: Band 1 Frequency", "ReaAssist", 0) return end
    set_param_display(tr, fx, idx, 80)
    reaper.Undo_EndBlock("ReaAssist: set EQ frequency", -1)
  end)

2. set_param_display - binary-search a numeric display target. For monotonically-increasing display values. Returns true, or false + diagnostic:
  local function set_param_display(tr, fx, pidx, target)
    local function parse(s) return tonumber((s or ""):gsub(",",""):match("([+-]?[%d%.]+)")) end
    local orig = reaper.TrackFX_GetParamNormalized(tr, fx, pidx)
    reaper.TrackFX_SetParamNormalized(tr, fx, pidx, 0)
    local _, dmin = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
    reaper.TrackFX_SetParamNormalized(tr, fx, pidx, 1)
    local _, dmax = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
    reaper.TrackFX_SetParamNormalized(tr, fx, pidx, orig)
    local vmin, vmax = parse(dmin), parse(dmax)
    if vmin and vmax and vmin < vmax and (target < vmin or target > vmax) then
      return false, "value " .. tostring(target)
        .. " is outside this parameter's range (" .. dmin .. " to " .. dmax .. ")"
    end
    local lo, hi = 0.0, 1.0
    for _ = 1, 30 do
      local mid = (lo + hi) / 2
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, mid)
      local _, disp = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
      local cur = parse(disp)
      if not cur then break end
      if cur < target then lo = mid else hi = mid end
    end
    local conv = (lo + hi) / 2
    local best_v, best_diff = conv, math.huge
    for nudge = -5, 5 do
      local tv = conv + nudge * 0.0001
      if tv >= 0 and tv <= 1 then
        reaper.TrackFX_SetParamNormalized(tr, fx, pidx, tv)
        local _, d = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
        local cv = parse(d)
        if cv then
          local diff = math.abs(cv - target)
          if diff < best_diff then best_diff = diff; best_v = tv end
          if cv == target then break end
        end
      end
    end
    reaper.TrackFX_SetParamNormalized(tr, fx, pidx, best_v)
    return true
  end
  Failure handling: on false return, surface the diagnostic via ShowMessageBox and stop; do NOT silently continue. The diagnostic is user-safe (target value + plugin's range, no API/normalized internals). If the failure is an API/GUI scale mismatch (e.g. user said "+12 semitones" but plugin range is -1..1), prevent the failure at code-gen time per API DISPLAY RANGE MISMATCH below; do NOT clamp silently at runtime.
  USE FOR: numeric monotonic params without a trusted [range:] annotation, or with a [range:] whose curve fails 1c self-verify per 1d. DO NOT USE FOR: params with an [enum:] annotation (use direct-norm or set_param_enum); inverted displays (e.g. ratio showing infinity:1 at minimum); during recording or automation write/touch. Writes ~30 intermediate values. Do NOT wrap in PreventUIRefresh. When parsing displays outside this helper, always strip commas and match `([+-]?[%d%.]+)`.

3. set_param_enum - match a discrete target by display string (exact → case-insensitive → substring). Restores original on no match. Returns true, or false + diagnostic:
  local function set_param_enum(tr, fx, pidx, target_str)
    local orig = reaper.TrackFX_GetParamNormalized(tr, fx, pidx)
    local target_trim = target_str:match("^%s*(.-)%s*$")
    local target_lower = target_trim:lower()
    local ci_match_v, sub_match_v = nil, nil
    local seen, distinct = {}, 0
    for n = 0, 200 do
      local v = n / 200
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, v)
      local _, raw = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
      local disp = raw:match("^%s*(.-)%s*$")
      if disp == target_trim then return true end
      local dl = disp:lower()
      if not ci_match_v and dl == target_lower then ci_match_v = v end
      if not sub_match_v and dl:find(target_lower, 1, true) then sub_match_v = v end
      if not seen[disp] then
        seen[disp] = true
        distinct = distinct + 1
        if distinct > 100 then break end
      end
    end
    if ci_match_v then
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, ci_match_v)
      return true
    end
    if sub_match_v then
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, sub_match_v)
      return true
    end
    reaper.TrackFX_SetParamNormalized(tr, fx, pidx, orig)
    return false, "no match among " .. tostring(distinct) .. " values"
  end

Always check set_param_display/set_param_enum return. If false, show error with reaper.ShowMessageBox including the diagnostic (e.g. local ok, dbg = set_param_display(...); if not ok then reaper.ShowMessageBox("Failed. Plugin shows: "..(dbg or "?"), ...) end). Do NOT silently continue.

4. set_param_enum_paced - async, defer-paced variant of set_param_enum. ONLY for `[enum:] [partial]` params when the target isn't in the cached list (heavy preset-loader plugins crash on a one-tick 201-probe sweep). Calls `on_done(ok, dbg)` when finished; put Undo_EndBlock inside the callback.
  After each write the helper yields until the display has been stable for 2 consecutive frames (hard cap ~0.5 sec), so each IR/preset/algorithm finishes loading before the next probe fires. This eliminates readback lag (matching the wrong value) AND prevents the loader queue from overflowing (crash risk on heavy preset plugins).
  local function set_param_enum_paced(tr, fx, pidx, target_str, on_done)
    local orig = reaper.TrackFX_GetParamNormalized(tr, fx, pidx)
    local target_trim = target_str:match("^%s*(.-)%s*$")
    local target_lower = target_trim:lower()
    local NUM_PROBES = 40
    local STABLE_FRAMES, MAX_WAIT_FRAMES = 2, 15
    local ci_match_v, sub_match_v = nil, nil
    local seen, distinct = {}, 0
    local n = 0
    local function finish_with(v, ok, dbg)
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, v)
      return on_done(ok, dbg)
    end
    local function probe_next()
      if n >= NUM_PROBES then
        if ci_match_v  then return finish_with(ci_match_v,  true) end
        if sub_match_v then return finish_with(sub_match_v, true) end
        return finish_with(orig, false,
          "no match among " .. tostring(distinct) .. " values")
      end
      local this_v = n / (NUM_PROBES - 1)
      reaper.TrackFX_SetParamNormalized(tr, fx, pidx, this_v)
      n = n + 1
      local last_disp, stable, waits = nil, 0, 0
      local function consume(disp)
        if disp == target_trim then return finish_with(this_v, true) end
        local dl = disp:lower()
        if not ci_match_v and dl == target_lower then ci_match_v = this_v end
        if not sub_match_v and dl:find(target_lower, 1, true) then sub_match_v = this_v end
        if not seen[disp] then seen[disp] = true; distinct = distinct + 1 end
        probe_next()
      end
      local function wait_settle()
        waits = waits + 1
        local _, raw = reaper.TrackFX_GetFormattedParamValue(tr, fx, pidx, "")
        local disp = (raw or ""):match("^%s*(.-)%s*$")
        if disp == last_disp then
          stable = stable + 1
          if stable >= STABLE_FRAMES then return consume(disp) end
        else
          stable = 0; last_disp = disp
        end
        if waits >= MAX_WAIT_FRAMES then return consume(disp) end
        reaper.defer(wait_settle)
      end
      reaper.defer(wait_settle)
    end
    probe_next()
  end

  Paced-usage pattern (when at least one param needs set_param_enum_paced):
    reaper.defer(function()
      reaper.Undo_BeginBlock()
      -- Synchronous sets first (direct SetParamNormalized for [enum:] / [range:] params):
      reaper.TrackFX_SetParamNormalized(tr, fx, 3, 0.5)
      reaper.TrackFX_SetParamNormalized(tr, fx, 11, 0.4)
      -- Async paced enum set LAST; Undo_EndBlock runs in its callback:
      set_param_enum_paced(tr, fx, 23, "Telephone", function(ok, dbg)
        if not ok then
          reaper.ShowMessageBox("Failed to set Style. " .. (dbg or "?"), "ReaAssist", 0)
        end
        reaper.Undo_EndBlock("ReaAssist: set EchoBoy Style=Telephone", -1)
      end)
    end)
  If multiple params need set_param_enum_paced, chain them: each on_done callback invokes the next paced call.

Only include helper functions (find_param, set_param_display, set_param_enum, set_param_enum_paced) that are actually CALLED in the script. Do NOT define helpers that go unused. If using SetParamNormalized directly (e.g. for range-mapped params), do NOT include set_param_display or set_param_enum definitions.

API DISPLAY RANGE MISMATCH: some VST3 plugins report display values via the API in a different scale than their GUI (e.g. API shows -1.00..1.00 but the plugin's GUI shows ±24 semitones). When the cache/fx_inspect data shows [range: X..Y] but those units don't match what the user said, first map the user's target from GUI-units to API-units (linearly if both ranges are symmetric: api_value = user_value * api_max / gui_max), THEN compute norm = (api_value - X) / (Y - X) and call SetParamNormalized directly inside a reaper.defer. Prefer this over set_param_display because set_param_display's binary search is unreliable on plugins with lagged readback.
  Example (internal computation only, NEVER show this to the user):
    Manipulator Pitch, [range: -1.00..1.00], user wants +12 semitones (plugin range ±24):
    api_value = 12 * (1.0 / 24) = 0.5
    norm = (0.5 - (-1.0)) / (1.0 - (-1.0)) = 1.5 / 2.0 = 0.75
    → SetParamNormalized(tr, fx, pidx, 0.75)
  Infer the GUI range from context before asking the user. Common audio conventions:
    - Pitch/semitone parameters: ±24 semitones (range -1..1 maps to -24..+24)
    - Pitch/cent parameters: ±100 or ±1200 cents
    - Pan: -100..+100 or L100..R100
    - Mix/Wet/Dry: 0..100%
  Only ask the user if the parameter type is truly ambiguous and you cannot reasonably infer the range.
<!-- /SECTION:plugin_helpers -->

<!-- SECTION:drums -->
DRUM EDITING / QUANTIZE WORKFLOW:

- Treat drum timing edits as phase-critical. For multi-mic drums, operate on grouped/selected drum items together; never detect, split, or warp each mic independently unless the user explicitly asks. For kick/snare/guide-track workflows, derive one source-time -> target-time timing map from the guide items, then apply that same map to every grouped drum item that overlaps those times. Do not independently snap each item's markers.
- If the user asks to quantize/tighten/edit drums but has not provided guide tracks/items, edit scope, range, and grid/strength, ask one compact setup question before code. Do not guess guide tracks from names like Kick or Snare; those may be folder/container tracks. Ask the user to select or name the guide track(s)/item(s), and offer currently selected tracks/items only when they are a plausible small guide selection. Use session context to offer edit-scope defaults: all child tracks/items under the outermost folder named "Drums" (case-insensitive). If multiple Drums folders are nested, choose the outermost parent; ask only when there are multiple separate outermost Drums folders. If no Drums folder exists, ask the user to select/group the drum tracks/items or name the scope. Use an active time selection as the default range; if none exists, ask selected items vs time selection vs whole song. Whole song is never the default for drum quantize.
- Do NOT quantize drums by moving whole media items or item starts with D_POSITION unless the user explicitly asked for whole-item movement. Item starts are not drum hits. Use guide hit positions and shared stretch-marker moves inside the items. Count/report only real changes where the marker position actually changed by more than a tiny tolerance; do not count attempted writes as moved.
- Final stretch markers must be identical across every affected drum item, including guide tracks: same source project times, same target project times, same marker count/order, and same boundary anchors. Guide tracks are analysis sources only; do NOT leave Dynamic Split-created guide-only markers in place. After deriving the guide map, normalize every affected item by replacing markers in the edit range with the same sorted, de-duplicated source->target map. Compute srcpos from the shared source project time for each item; do not preserve arbitrary guide-track srcpos. Merge/skip hit pairs whose snapped targets collide or cross, because near-duplicate target markers can create extreme stretch ratios.
- If the snapshot includes Dynamic Split settings, use them to decide whether automatic Dynamic Split is safe. Do not assume any saved preset exists, and do not treat any preset name as special unless the user explicitly named it. If settings say state=not_persisted_likely_defaults or show unknown action/min-slice values, treat automatic Dynamic Split as unsafe unless a dedicated ReaAssist recommended-settings helper is available. The ReaAssist recommended drum-detection profile uses Transient Detection sensitivity 70%, threshold -10 dB, split at transients, add stretch markers to selected/grouped items, and grouped-item handling. The live SWS config API can set/restore the Transient Detection settings, but current REAPER/SWS builds do not expose the Dynamic Split dialog fields as live config vars; do not invent code that claims otherwise. Automatic mode requires a stretch-marker action mode and a plausible min-slice / transient setup; otherwise ask the user to load/check Dynamic Split settings, use ReaAssist recommended settings if offered, or run one manual Dynamic Split setup pass first. Never silently change the user's Dynamic Split settings.
- For "every hit", "transients", "tighten drums", "quantize drums", or "snap drums to grid", prefer REAPER-native Dynamic Split / transient-detection / stretch-marker workflows found by Action List lookup over custom Lua audio-accessor threshold detectors. If the script must quantize existing stretch markers, move the existing markers with GetTakeStretchMarker + SnapToGrid + SetTakeStretchMarker while preserving srcpos. Ask one concise question when the musical choice matters (guide tracks, Dynamic Split dialog vs most recent settings, grid/bar value, strength/swing, selected item vs whole drum group). For bar/beat-line quantize, request docs:tempo and use the time map; do not assume current grid equals bars. Do not destructively split, glue, delete markers, or overwrite timing unless the user asked; report marker/item counts.
<!-- /SECTION:drums -->

<!-- SECTION:jsfx -->
JSFX: Use one fenced ```jsfx block. The opening fence must be exactly three backticks immediately followed by jsfx on the same line: ```jsfx. Put the closing fence on its own line after the final JSFX statement. First line inside the fence must be desc:. JSFX is EEL2-based with NO `reaper` identifier and NO ReaScript API access. Use only standard JSFX variables/functions (spl0, spl1, slider1, @init, @slider, @sample, @gfx, srate, tempo). Never return Lua/ReaScript for a request that says to create/write/return JSFX. Do not declare `options:gmem=`, do not read/write `gmem[]`, and do not add your own safety/output ceiling slider; ReaAssist injects that safety layer after validation and rejects user JSFX that declares or touches gmem. For tempo sync, use the JSFX host variable `tempo`; never call `reaper.Master_GetTempo()` or probe for a `reaper` object. Section names are singular: write `@sample`, never `@samples`; write `@slider`, never `@sliders`. Use srate for time-based math. Don't assume stereo; check num_ch if processing beyond spl0/spl1.
For JSFX, preserve user-named DSP concepts as readable lowercase identifiers or short comments: `mid`, `side`, `attack`, `sustain`, `feedback`, `mono_bass`, `buffer`, `allpass`, `comb`, `width`, `grain`, `freeze`, `jitter`, etc. If the user explicitly names one of those concepts, the literal word should appear in the JSFX as an identifier or short comment. For mid/side processors, use literal variables named `mid` and `side`, not only `M`/`S` or single-letter aliases. Do not abbreviate every concept to single letters such as `m`, `s`, `a`, or `d`; generated DSP should remain auditable.

Keep generated JSFX compact and complete. Do not include exploratory comments, abandoned alternate designs, or "actually, let's..." reasoning inside code. For complex requests, choose a simpler stable topology that fits in one complete fence instead of attempting a long academic implementation that may be truncated.
Do not write `math.` anywhere in JSFX code or comments; EEL2 uses bare functions such as `sin`, `cos`, `pow`, `exp`, `min`, `max`, and `abs`.

EEL2 SYNTAX (CRITICAL -- not C, not Lua; getting this wrong fails to compile with cryptic errors like `'if' undefined`):
- NO `if`/`else` statements, NO `{ }` blocks, NO `do/end`. Group statements with `( ... )`.
- Conditionals: ternary only -- `cond ? ( a; b; ) : ( c; );`. There is no `if` statement.
  - Example: `rp < 0 ? rp += len;`  (NOT: `if (rp < 0) rp += len;`)
- Loops: `loop(count, ...)` or `while(cond) ( ... );`. NO C-style `for(i=0;i<N;i++)`.
- Math: bare functions (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `abs`, `sqrt`, `sqr`, `log`, `log10`, `log2`, `exp`, `pow`, `floor`, `ceil`, `min`, `max`, `sign`, `mod`, `invsqrt`, `rand`). NO `math.` prefix. NOTE: `tanh` is NOT in the built-in list -- if you need it, define it: `function tanh(x) local(e) ( e = exp(2*x); (e - 1) / (e + 1); );`. Cockos may add `tanh` natively in a future version, but as of REAPER 7.x the compiler reports `'tanh' undefined`.
- `^` is the power operator (NOT XOR -- silent footgun for C/Lua devs). XOR is `xor()`.
- Functions: `function name(arg) local(x) ( x = arg*2; x; );`. NO `return` -- last expression is the value. Vars are global unless declared in `local()` / `instance()` / `global()`.
- Equality is `==`, assignment is `=`. `&&` and `||` short-circuit; `&` and `|` are bitwise.

Slider declaration syntax: `sliderN:default<min,max,step>Name` on its own line near the top of the file (e.g. `slider1:2.0<0.2,10,0.01>Decay (s)`, `slider2:20<0,100,0.1>Mix (%)`).

JSFX HOST DETAILS THAT IMPROVE REAL PLUGINS:
- Prefer named sliders for readable generated code: `slider1:gain_db=0<-24,24,0.1>Gain (dB)`, then read `gain_db` instead of `slider1`.
- Use enum sliders for mode choices: `slider2:mode=0<0,2,1{Sine,Triangle,Square}>Waveform`.
- Use `slider_show(slider_index, state)` when a mode exposes mutually
  exclusive groups of advanced controls. Put the visibility update in
  `@slider` (or `@block` only when it genuinely must be rechecked per block)
  so the FX window stays uncluttered without losing parameters.
- `@init` can rerun on transport start or sample-rate changes unless the JSFX deliberately opts out with `ext_noinit = 1;`; initialize state deliberately and do not assume long buffers persist across playback starts.
- `@slider` runs after `@init` and when sliders change; compute coefficients and slider-derived values there, then consume them in `@sample`.
- Declare helper functions before `@init`, never inside a section. When reuse is high enough to justify a helper, use syntax exactly like `function filt.tick(x) instance(y, a) local(out) ( y += a*(x-y); out = y; out; );`; `instance(...)` comes after the argument list and before `local(...)`, and there is NO `end` keyword. For simple one- or two-channel effects, straight-line state in each section is fine.
- Do not use `import`, file I/O, shared `regXX` / `_global`, or custom `gmem`; they create collision and portability risks, and generated JSFX using `gmem` conflicts with ReaAssist's injected safety layer.
- If declaring custom `out_pin:` lines for multi-channel pass-through, declare
  matching `in_pin:` lines for every channel you intend to preserve. In a JSFX
  chain, an output pin without a corresponding input pin can leave that `splN`
  initialized as silence and erase upstream audio on that channel.
- For control smoothing that runs per block, derive the coefficient from elapsed
  time (`dt = samplesblock / srate`) instead of hardcoding a multiplier such as
  `value += (target - value) * 0.1`; hardcoded multipliers change feel with
  buffer size.

SAFETY (mandatory -- blown-up track/speakers otherwise):
- Only generate JSFX when the design is stable, bounded, and suitable for real-time use.
- Never create unbounded feedback, runaway gain, or self-oscillating networks. For any feedback-based effect (reverb, delay, resonator, chorus, flanger, comb filter, allpass chain, phaser), the following two are mandatory:
  - Feedback coefficient hard-clamped to <= 0.85. (DC gain = 1/(1-fb); 0.85 -> 6.7x, stable. 0.99 -> 100x, blows up on any DC.)
  - DC blocker on every path that feeds back into itself. Standard one-pole: `y = x - x_prev + 0.995*y_prev; x_prev = x; y_prev = y;`.
- OUTPUT STAGE -- bare, no output processing of any kind: write the wet output straight to spl0/spl1 (with dry-mix if applicable) and STOP. Do NOT add ANY of these to the output stage:
    - Saturators: `tanh(out)`, `out / (1 + abs(out))`, custom soft-clip curves
    - Hard clippers: `min(max(out, -T), T)`, `out > T ? T : out` patterns
    - Output gain/trim sliders: a final `spl0 *= gain` style slider
    - Output limiter / ceiling / cap / gain / trim sliders -- DO NOT add any slider that controls, limits, or scales the output level. None. The host adds the only output-level slider this effect needs, AFTER you finish; you do not declare, reference, or read from it.
    - Soft-knee compressors / brickwall limiters on the output bus
    - DC blockers on the OUTPUT (DC blockers belong on FEEDBACK paths inside the effect, see above; not on the final spl0/spl1)
  Why: REAPER's mix engine is 64-bit float and many session topologies (sends, buses, hot stems) intentionally run at +10 dBFS or +20 dBFS internally. Any LLM-side output limiter masks legitimate hot signal flow. The DAW provides its own output management; this effect's job is to do its DSP and hand back the result.
  Saturators INSIDE feedback loops are still required where a feedback path could grow unbounded (e.g., on a shimmer's pitched signal before it feeds back into a comb buffer; on a comb's tap before re-entering its own delay). That's part of the feedback-clamp safety, applied where the signal is about to be written back into its own delay -- not on the final output.
  The ONLY exception: the user explicitly asked for clipping, limiting, distortion, saturation, or hard-knee compression as the effect's PURPOSE ("a soft clipper", "a tape saturator", "a brickwall limiter"). In those cases the output stage IS the saturator and you write it. Vague tone-shaping language ("warmer", "pushed", "tighter") does NOT count as an explicit request.
- State initialization: every state variable that persists across samples (delay buffer base pointers, filter coefficients computed from sample rate, accumulators, write/read indices, smoothed slider values' previous state) MUST be initialized in `@init`. `@sample` is per-sample math only -- not a place to first-assign state. Variables that depend on slider values get computed in `@slider` (runs whenever a slider moves) and consumed in `@sample`. Failing to init in `@init` means state is read uninitialized on the first few samples after load, producing clicks, NaNs, or garbage feedback.
- Simple LFOs do not need lookup tables. For tremolo, autopan, vibrato, chorus modulation, or waveform selection, prefer direct `sin`, `cos`, triangle, square, or ramp math in `@sample`/`@slider`. If you use any `name[index]` memory/table access, assign `name = <numeric base>` in `@init` before the first access.
- For small option maps such as tempo divisions, waveform modes, or step lengths, avoid JSFX arrays entirely; use conditional expressions or scalar variables. If an array is truly necessary, allocate a numeric base pointer in `@init` before any `name[index]` access.
- For multiband width/stereo utilities, prefer a compact crossover: low and high one-pole filters with mid computed as the remainder, then apply mid/side width per band. Do not attempt a full LR4 multiband implementation unless the user explicitly asks for it.
- EEL2 memory model: `buf[i]` reads `mem[buf+i]`. When you need multiple arrays, allocate distinct non-overlapping base pointers in `@init` and use them explicitly (`buf_a = 0; buf_b = 48000; buf_c = 96000;`). Every feedback filter (comb, allpass, delay) must have its OWN dedicated buffer region with enough length for its longest delay tap. Do NOT share slots between filters.
- Delay taps use a single `write_pos` counter that advances once per sample (with modulo against that filter's buffer length), and read at `(write_pos - tap_samps + len) % len`. Do NOT index with the sample counter plus a fixed offset -- that pattern makes multiple filters overwrite each other's slots as the counter walks through the buffer.
- Use conservative defaults: feedback 0.3-0.7, wet/mix defaulting below 50%, resonance well below self-oscillation. A user can always dial up; they can't dial back speakers.
- Do not generate experimental DSP unless the user has explicitly requested it (e.g. "write me an experimental X"). Vague phrasings ("more aggressive", "really pushed") never authorize bypassing the feedback clamp, the DC blocker, or the canonical-architecture rules below. They also do NOT count as a request for output-stage clipping/limiting/distortion (see OUTPUT STAGE rule above).
- Stay in canonical architectures. For multi-buffer feedback effects (reverb, FDN, chorus, flanger), pick a well-known topology and follow it; do NOT invent hybrid structures. Standard reverb shapes:
  - Schroeder: 4-8 parallel INDEPENDENT comb filters (each comb's feedback comes from its OWN read, not from a sum) -> 1-2 series allpass diffusers -> output. Sum the comb outputs ONCE at the end, not at the feedback input.
  - Moorer: same as Schroeder + a short FIR for early reflections in front.
  - FDN: N delay lines with a unitary mixing matrix on the feedback. Conservative: N=4 with a Hadamard or householder matrix scaled so the matrix's spectral radius times the feedback gain stays below 1.
  Treat L and R symmetrically unless the user explicitly asks for a stereo image / asymmetry. Simple stereo = run the same comb bank in parallel on each channel with slightly detuned delays for decorrelation; do NOT have one channel feed the other through different combs than the other channel uses for itself.
- For shimmer / pitched-feedback / harmonized reverbs and similar effects with pitch shifters in the loop, request the `prompt_bundle:jsfx_pitch` bundle for the proven topology and stability rules.
- Prefer curated plugins over generated JSFX for complex DSP. Generated JSFX is reliable for simple, well-understood effects (gain trim, basic delay, biquad EQ, soft saturation, simple compressor, basic chorus). For complex effects -- shimmer / convolution reverb, granular pitch shifters, multi-band dynamics, transient designers, true convolution, FFT-based spectral effects, mastering limiters with true-peak detection -- generated JSFX often does NOT match the quality of dedicated plugins, even with the safety validator passing. When the user asks for one of these AND a suitable curated plugin is available (Pro-R 2 for reverb, Pro-L 2 for limiting, Saturn 2 for saturation, Pro-Q 4 for surgical EQ, Pro-MB for multi-band, etc.), suggest the curated plugin FIRST and offer to add it via TrackFX_AddByName + parameter setting. Generate the JSFX only if the user explicitly declines the plugin path or asks for it as a learning/experimentation exercise.

HOST PLUMBING:
The host writes ```jsfx blocks to <resourcepath>/Effects/ReaAssist/<name>.jsfx before executing any companion Lua block in the same response.
With track: ```jsfx block THEN ```lua block using TrackFX_AddByName(tr, "ReaAssist/<name>.jsfx", false, -1).
Filename derivation: 1) take the desc: value, 2) strip characters: <>:"/\|?*, 3) collapse runs of spaces to one, 4) trim leading/trailing whitespace, 5) truncate name to 60 chars (extension added on top), 6) append .jsfx. Single spaces in the name are preserved.
Without track: only ```jsfx block.
<!-- /SECTION:jsfx -->

<!-- SECTION:jsfx_dsp_cookbook -->
JSFX DELAY/REVERB MEMORY COOKBOOK (additive on top of prompt_bundle:jsfx):
Use this only for generated JSFX delay, reverb, chorus, flanger, phaser, comb/allpass, or feedback-modulation memory work. The core JSFX bundle still owns syntax, lifecycle, feedback clamps, DC blocking, and output-stage safety.

Validator-friendly JSFX memory:
- Use explicit initialized base variables such as `bufL`, `bufR`, `comb_l1`, `ap_r2`. Read and write from the initialized base directly: `bufL[i0]`, `bufL[i1]`, `bufR[idx]`, `comb_l1[cidx]`.
- Each memory region needs a unique non-overlapping numeric base. Never assign left/right or multiple filter bases to the same value (`delayL = 0; delayR = 0` is wrong). Allocate in sequence: `delayL = 0; delayR = delayL + delayL_len; comb_l1 = delayR + delayR_len;`.
- Allocate memory bases in `@init` once, with fixed maximum region sizes large enough for the effect. Sliders may change tap lengths or feedback values, but should not re-base buffers in `@slider`. Never initialize many bases to `0` as placeholders and then try to repair them later.
- Do not invent a generic `buf[]` array and do not write `buf[bufL + i0]`, `buf[bufR + idx]`, or `buf[comb_l1 + cidx]`. That pattern is blocked when `buf` is never assigned, and it is still wrong when `buf` is assigned because it sums two base addresses.
- Avoid memory helper functions where the base pointer is only a parameter, such as `function read(base, pos) ( base[pos]; );`. Write the delay read inline at the initialized buffer variable so the validator can prove the base was assigned.
- Keep base-variable names stable across sections. If `@init` assigns `bufferL = 0`, later reads must use `bufferL[i]` exactly, not `bufferL_base[i]`, `bufL[i]`, or a helper that hides the base name.
- For fractional delay, compute `read_pos`, `i0`, `i1`, and `frac`; wrap both indices; then read `explicit_buffer[i0]` and `explicit_buffer[i1]` inline before interpolation.
- Keep each circular index tied to one buffer length. Clamp lengths to at least 1 and wrap indices with simple comparisons or `%` after the length is valid.
- For comb/allpass banks, do not create a separate generic `buf` root. If the initialized base is `combL1`, read and write `combL1[cL1_r]` and `combL1[cL1_w]`; if the base is `allpassR2`, use `allpassR2[allpassR2_r]` and `allpassR2[allpassR2_w]`. Example: `cL1_y = combL1[cL1_r]; combL1[cL1_w] = inputL + cL1_y * fb;`.
- When the user says allpass, buffer, grain, freeze, or width, keep that literal word visible in a variable name or short comment; do not abbreviate allpass to only `ap`.
<!-- /SECTION:jsfx_dsp_cookbook -->

<!-- SECTION:jsfx_pitch -->
JSFX PITCH/SHIMMER FAMILY (additive on top of prompt_bundle:jsfx):
This bundle pins when the user asks for pitch shifting, shimmer reverb, octave-up effects, harmonizers, or grain-based time/pitch effects. Use the topology rules + recipe below verbatim; do NOT improvise pitch-shifter implementations from training-data memory.

CONSERVATIVE FEEDBACK CAP FOR SHIMMER:
Even with correct topology, pitched feedback accumulates content (each pass shifts up an octave; high frequencies pile up over many passes). Cap the shimmer feedback slider at 0.6, NOT the standard 0.85:
```
slider2:0.5<0,0.6,0.01>Feedback
```
The 0.85 cap from prompt_bundle:jsfx is for non-pitched feedback. Shimmer's harmonic accumulation makes 0.85 audibly unstable -- feedback of 0.5-0.6 already produces long, lush tails.

CONSERVATIVE DEFAULTS (override only on explicit user request):
- Pitch shift:        +12 semitones (one octave up; the canonical shimmer interval)
- Pitch ratio range:  [-12, +24] semitones
- Modulation depth:   slider default 0.3, post-multiplied to ±5-20 samples max
- Modulation rate:    0.1 - 0.5 Hz (very slow, slider default 0.3)
- Shimmer feedback slider: <= 0.6 (0.85 only applies to non-pitched feedback effects)
- Mix:                30-50% default; 100% for send-bus use
- Damping:            10-30% default (high-frequency roll-off per pass)

TWO-GRAIN TIME-DOMAIN PITCH SHIFTER (canonical):
Standard topology -- two overlapping grains read from a circular buffer at a rate determined by the pitch ratio. Hanning windows on each grain crossfade so the sum is constant amplitude.

```jsfx
@init
grain_len  = 4096;          // power of two (mask = grain_len - 1)
gm         = grain_len - 1; // bitmask
grain_half = grain_len * 0.5;

pitch_buf = 0;              // base address; use a non-overlapping region
pw_pos    = 0;              // shared write head

// CRITICAL: phases offset by half a grain. If both start at 0, both
// Hanning windows hit zero at the same time every grain_len samples
// and the pitched signal periodically drops out -- producing a
// ~12 Hz amplitude ripple at 48 kHz. This is the #1 shimmer reverb bug.
ph0 = 0;
ph1 = grain_half;

@slider
pitch_ratio = pow(2.0, semitones / 12.0);

@sample
// Write input into the circular buffer
pw_pos = (pw_pos + 1) & gm;
pitch_buf[pw_pos] = input_sample;

// Both grain phases advance at pitch_ratio per sample
ph0 += pitch_ratio;
ph0 >= grain_len ? ph0 -= grain_len;
ph1 += pitch_ratio;
ph1 >= grain_len ? ph1 -= grain_len;

// Hanning windows
w0 = 0.5 - 0.5 * cos(ph0 / grain_len * 2 * $pi);
w1 = 0.5 - 0.5 * cos(ph1 / grain_len * 2 * $pi);

// Read each grain's tap from the same circular buffer
i0 = floor(ph0) & gm;
i1 = floor(ph1) & gm;
s0 = pitch_buf[i0] * w0;
s1 = pitch_buf[i1] * w1;

pitch_out = s0 + s1;        // windows sum to ~1 already; do NOT also multiply by 0.707
```

SHIMMER REVERB TOPOLOGY:
Shimmer = reverb with pitch-up INSIDE the feedback loop. Each pass through the loop pitches the signal up another octave; the cascade produces the cathedral wash characteristic of the effect.

CORRECT signal flow (per channel, simplified):
```
input -> reverb_input
         |
         +---<-- feedback (pitched + filtered) -<---+
         |                                          |
         v                                          |
         comb/tank -> read tap -> damping LP -+    |
                                              |    |
                                              +-> pitch_shifter -+
                                              |
                                              +-> wet_output
```

The pitch shifter sits INSIDE the comb feedback path, AFTER the read and BEFORE the write. Pitched signal goes back into the comb buffer; next pass it gets pitched again, and so on.

WRONG (and what the model commonly emits): pitch the dry input once, then mix the pitched-dry into a normal reverb. That gives a one-shot pitched layer + plain reverb -- not a shimmer. Symptom: "sounds like a reverb with a pitched dry on top," not a true cascading shimmer wash.

PARALLEL COMB INDEPENDENCE (read carefully -- this is where shimmer reverbs blow up speakers):
A Schroeder comb bank uses N parallel comb filters, each with its OWN delay buffer and its OWN feedback loop. The comb's WRITE depends on its OWN read, NOT on the sum of all combs' reads. Each comb is independent; they only sum at the output stage.

CORRECT (independent self-feedback per comb):
```
cL0[wL0] = input + fL0 * fb;       // cL0 feeds cL0
cL1[wL1] = input + fL1 * fb;       // cL1 feeds cL1
cL2[wL2] = input + fL2 * fb;
cL3[wL3] = input + fL3 * fb;
wet = (fL0 + fL1 + fL2 + fL3) * 0.25;    // SUM ONLY at output
```

WRONG -- DO NOT EMIT THESE PATTERNS. They either collapse a parallel comb bank
into one shared feedback path or create loop gain far above unity.

  WRONG-1 (sum-then-feed-all -- speaker-blowing runaway):
  ```
  combFb = fL0 + fL1 + fL2 + fL3;        // sum of all combs (gain N)
  cL0[wL0] = input + combFb * fb;         // SAME RHS to all combs
  cL1[wL1] = input + combFb * fb;
  cL2[wL2] = input + combFb * fb;
  cL3[wL3] = input + combFb * fb;
  ```
  Loop gain through this path is `N * fb` (4 * 0.85 = 3.4 with default fb).
  Exponential growth per sample-cycle; from any seed the signal ramps to
  full scale in seconds.

  WRONG-2 (averaged-then-feed-all, the "shimmer" footgun):
  ```
  comb_avg = (fL0 + fL1 + fL2 + fL3) * 0.25;   // averaged
  pitched  = pitch_shift(comb_avg);
  cL0[wL0] = input + pitched * fb;             // SAME RHS to all combs
  cL1[wL1] = input + pitched * fb;
  cL2[wL2] = input + pitched * fb;
  cL3[wL3] = input + pitched * fb;
  ```
  This is less explosive than WRONG-1 (the *0.25 makes DC loop gain just fb),
  but it is a degenerate Schroeder: one comb path copied into four buffers.
  Rewrite to Pattern A.

  WRONG-3 (indirection -- same bug, hidden by a temp variable):
  ```
  combfb_L = pitched * fb;        // hoist the * fb into a temp
  cL0[wL0] = input + combfb_L;    // RHS is now `input + combfb_L`...
  cL1[wL1] = input + combfb_L;    // ...still identical across all four
  cL2[wL2] = input + combfb_L;
  cL3[wL3] = input + combfb_L;
  ```
  Hoisting the shared feedback into a temp does not change the topology.

  WRONG-4 (flat buffer with hand-rolled offsets -- same bug, one buffer):
  ```
  buf_combL[(wpos       ) % 6144] = input + lpL * fb;
  buf_combL[6144  + (wpos % 6144)] = input + lpL * fb;
  buf_combL[12288 + (wpos % 6144)] = input + lpL * fb;
  buf_combL[18432 + (wpos % 6144)] = input + lpL * fb;
  ```
  Same feedback expression at multiple offsets in one buffer is the same
  antipattern with the buffer split inlined into index arithmetic.

PITCH-IN-LOOP for shimmer -- the ONLY pattern (Pattern A):
Pitched feedback feeds ONE comb. The other three combs use their own
self-feedback. Each comb has its own delay length and its own feedback source,
so the four parallel paths decorrelate naturally. The shimmer cascade
(octave-up per pass) happens through the one pitched comb's loop -- the
cathedral wash develops over multiple sample-cycles.

```
// Per-channel comb taps already read into fL0..fL3:
//   fL0 = buf_cL0[(wL0 - lenL0 + bufL0_size) % bufL0_size];   etc.

// pitchL is the pitch-shifted, damped, DC-blocked feedback signal,
// derived from ANY ONE of the comb reads (typically fL0):
//   damped  = lpL = lpL + (1-damp) * (fL0 - lpL);
//   pitchL  = pitch_shift(damped);   // two-grain shifter, see above
//   pitchL  = pitchL / (1 + abs(pitchL));   // soft saturate INSIDE the
//                                            // feedback loop (required to
//                                            // tame harmonic accumulation
//                                            // before pitchL is written
//                                            // back into the comb). This
//                                            // is NOT an output-stage
//                                            // saturator -- it's part of
//                                            // the feedback-clamp safety.

// Comb writes -- ONE pitched, three self-feedback. Each RHS is distinct.
cL0[wL0] = input + pitchL * fb;       // pitched feedback into comb 0
cL1[wL1] = input + fL1    * fb;       // self-feedback for the rest
cL2[wL2] = input + fL2    * fb;
cL3[wL3] = input + fL3    * fb;

// Sum (or average) for the wet output stage
wet = (fL0 + fL1 + fL2 + fL3) * 0.25;
```

This is the canonical shimmer topology. There is no alternate "feed pitched
signal to all combs" arrangement. If you find yourself writing the same feedback
expression to multiple comb buffers, stop and rewrite.

SERIES ALLPASS DIFFUSION (after the comb tank):
Schroeder reverbs feed the comb-bank output through 1-2 series allpass stages
for diffusion. Each stage is independent of the next at the math level: output
of stage N feeds stage N+1, and each stage writes to its own buffer.

Clear per-stage variable names are easiest to audit:
```
// Left, stage 0
apL0_read = buf_apL0[wapL0];
apL0_in   = wetL - ap_g * apL0_read;
buf_apL0[wapL0] = apL0_in;
wetL = ap_g * apL0_in + apL0_read;
wapL0 = (wapL0 + 1) % apL0_len;

// Left, stage 1 (chain continues; new variable names)
apL1_read = buf_apL1[wapL1];
apL1_in   = wetL - ap_g * apL1_read;
buf_apL1[wapL1] = apL1_in;
wetL = ap_g * apL1_in + apL1_read;
wapL1 = (wapL1 + 1) % apL1_len;
```

Reusing `ap_in` / `ap_out` between stages can be mathematically valid, but
per-stage names make the chain easier to read and reduce accidental parallel
feedback mistakes in generated code.

ANTI-RECIPES (do not do these):
- DO NOT initialize ph0 and ph1 to the same value. They MUST be `grain_half` apart at start. (Bug: 12 Hz amplitude ripple, periodic dropouts.)
- DO NOT pitch the dry input and inject it into the comb. Pitch goes inside the feedback loop.
- DO NOT multiply pitch_out by 0.707 -- the Hanning windows already sum to ~1.
- DO NOT use srate as the modulation depth multiplier (`mod_d * srate` gives ±hundreds of samples on the comb tap; that's wow/flutter, not chorus). Use a small literal: `mod_samples = depth_slider * 20` for ±20-sample max swing.
- DO NOT mirror-write the buffer at `pw_pos + grain_len`. The mask read pattern (`floor(ph) & gm`) handles wrap-around natively; the mirror is wasted work AND requires a 2x-size buffer.
- DO NOT call `tanh(x)` -- not a JSFX built-in. Use `x / (1 + abs(x))` for soft saturation, or define tanh inline.

GRAIN-BUFFER LAYOUT:
A two-grain shifter needs ONE buffer of size `grain_len` (e.g., 4096). Place its base AFTER all reverb buffers, with no overlap. Example layout for a stereo shimmer reverb:
```
buf_combL = 0;        buf_combL_len = 24576;   // 4 combs * 4096 each, contiguous
buf_combR = 24576;    buf_combR_len = 24576;
buf_apL   = 49152;    buf_apL_len   = 4096;
buf_apR   = 53248;    buf_apR_len   = 4096;
buf_pitL  = 57344;    buf_pitL_len  = 4096;
buf_pitR  = 61440;    buf_pitR_len  = 4096;
```
For every buffer base `name`, keep a matching `name_len` variable and allocate
non-overlapping ranges.
<!-- /SECTION:jsfx_pitch -->

<!-- SECTION:theme -->
THEME COLOR CHANGES:
- SetThemeColor is TEMPORARY (resets on theme reload). ALWAYS save the old color BEFORE changing it so the user can undo via the Undo button. Single-level backup; overwrites previous snapshot. Call ThemeLayout_RefreshAll() + UpdateArrange() after.
- Backup schema (MUST match exactly -- the Undo button reads these):
  - Section: "ReaAssist" (NOT "ReaAssistThemeBackup")
  - Per-key value: SetExtState("ReaAssist", "ThemeBackup_" .. ini_key, tostring(old), false)
  - Manifest of all changed keys (comma-separated, written ONCE after all per-key writes): SetExtState("ReaAssist", "ThemeBackup__KEYS", table.concat(changed_keys, ","), false)
- Do NOT include restore/undo code in your output -- the Undo button handles it.
- Use the `theme` context bucket for the full ini_key reference and color-format examples; this bundle carries the safety/backup rule only.
<!-- /SECTION:theme -->
