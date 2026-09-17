<!-- Prompts.md - on-demand prompt bundles. -->
<!-- Served by CTX.prompt_bundle(name); requested via <context_needed>prompt_bundle:NAME</context_needed>. -->
<!-- Each bundle delimited by SECTION:name / /SECTION:name comment markers. -->
<!-- -->
<!-- Bundles: -->
<!--   plugin         concise Model-authored Lua guidance for adding, modifying, and configuring plug-ins. -->
<!--   plugin_helpers optional live-name and display-value conversion guidance. -->
<!--   drums          phase-safe drum editing / quantize workflow: guide tracks, range/scope questions, Dynamic Split safety, shared stretch-marker maps. -->
<!--   jsfx           EEL2 syntax, slider declarations, DSP safety, host plumbing for .jsfx files. -->
<!--   jsfx_dsp_cookbook  Narrow delay/reverb/modulation JSFX memory-addressing recipes. -->
<!--   jsfx_gfx       Custom @gfx front-panel guidance for JSFX GUI, knobs, buttons, meters, and mouse-driven controls. -->
<!--   theme          theme color change safety + ExtState backup schema for the Undo button. (The full ini_key catalog lives in API_Ref.md SECTION:theme.) -->

<!-- SECTION:plugin -->
PLUGIN WORKFLOW:

GOAL:
Finish the requested plug-in action with one clear, runnable Lua script. Use
normal REAPER APIs. Maintained plug-in profiles, preferred-plug-in data, cached
parameters, and live session data are helpful generation references. They are
never execution authorization and a missing or different fingerprint is not a
reason to refuse the action.

IDENTITY AND TARGETING:
- When adding a new reverb directly on a vocal/source track, "wet" or "make it wet"
  means an audible reverb blend that preserves direct signal. Use an initial
  mix around 30-40% unless the user specifies another amount. This initial
  value does not apply to changes to an existing effect. Do not infer
  100% wet from "wet" alone. An explicit request for fully wet, 100% wet,
  wet-only, or no dry signal takes precedence. A dedicated send/return reverb
  normally uses 100% wet because the source track supplies the direct signal.
- "Wetter", "more wet", "increase the wet mix", and "drier" are relative
  changes to the existing effect. Read its live mix inside the generated script
  each time it runs, then calculate the new mix from that reading. Never replace
  a relative request with a fixed 30%, 40%, or a value from chat history. For an
  unspecified "wetter" step, add 10 percentage points; subtract 10 for "drier".
  Apply a user-specified step instead when provided. Resolve the actual control
  and its mapping first: normalized +0.10 is correct only for a verified linear
  0-100% mix. Clamp to the supported range. Repeated requests must keep moving
  from the new live value until the limit. At the limit, report that it is already
  fully wet or fully dry and make no write or success claim. A missing or invalid
  live reading must stop with a clear message, never fall back to a guessed mix.
  "Set the mix to 40%" is absolute and must still set exactly 40%.
- A product named by the user is binding. Do not substitute another product.
- For a vendor/family name, inspect the installed catalog before asking what the
  user has. Request `fx_list:Vendor` if that list is absent. Ask which product
  only when the installed choices still leave more than one plausible match.
  Interpret the request yourself using that inventory. If the user delegates
  the choice ("choose for me", "any suitable one"), choose an installed product
  that fits the requested role and explain the choice briefly. Otherwise ask
  one concise question with a short numbered list of plausible products when
  a choice is needed. Exclude unrelated effect types and duplicate formats.
  Do not pad an "another reverb" option with every product from that vendor.
  Do not invent parameter ranges to justify asking which product to use.
  For an existing effect, resolve it from the requested track's live FX first;
  do not ask the user to choose from the entire installed catalog.
  A product-choice reply continues the original action and every requested
  setting. Honor revised settings in that reply. Cancellation makes no changes.
  Never offer default settings because a parameter mapping is absent. Resolve
  the controls after the product is chosen.
- Reports of wrong results preserve the earlier requested target. "The decay
  is 5.7 seconds, not 3" means correct it to 3 seconds. "Now it is 70 seconds"
  reports another failure. Never turn seconds into a Mix percentage or change
  an unrelated control while repairing the requested parameter.
- For a generic type such as EQ, compressor, reverb, or limiter, use the user's
  resolved preference when it is already available. Otherwise request
  `resolve:Type` once, or choose an exact installed identifier from supplied
  catalog data. Do not pass a bare generic type to TrackFX_AddByName.
- Add/new/insert means create a new instance on the requested target. Existing
  matching instances elsewhere in the project do not make that request
  ambiguous. For TrackFX_AddByName or TakeFX_AddByName, use a negative
  instantiate value for every requested new instance.
- Modify/change/set an existing effect means find the instance on the requested
  track. Ask only when that requested scope still contains multiple plausible
  instances. Use instantiate value `0` to find an existing instance without
  adding one. Stop with a clear message when the requested instance is absent.
- Resolve explicit track names or numbers first. For user-numbered targets, check existence without requiring a snapshot-derived name unless the current request explicitly gives that name for that numbered target too. For selected/current wording,
  use the request-time TARGET HINT when supplied. Validate captured track name
  and index pairs before editing.

LUA SHAPE:
- Return one complete fenced `lua` script. Keep it direct and reasonably short.
- Use one Undo block for the complete action and give it a descriptive label.
- Check every required TrackFX_AddByName, TrackFX_GetByName, TakeFX_AddByName,
  or TakeFX_GetByName result before using it. A missing required target should
  produce one clear message and no false success claim.
- Add all requested plug-ins in the requested order. For multi-plug-in chains,
  keep the targets and returned FX indices in ordinary local tables.
- Apply every requested setting to its intended returned FX index. Before
  finishing, compare the script against the request and keep every named
  parameter, target value, sidechain filter, gain-reduction goal, and output
  setting that the user supplied.
- Leave an add-only effect at its defaults. Configure values only when the user
  requested settings, a recipe, a tonal goal, or a starter treatment.
- Change only the requested parameters. Do not reset unrelated controls.

PARAMETER VALUES:
- Direct TrackFX_SetParam, TrackFX_SetParamNormalized, TakeFX_SetParam, and
  TakeFX_SetParamNormalized calls are allowed.
- Values passed to TrackFX_SetParamNormalized or TakeFX_SetParamNormalized are
  normalized values from 0 through 1. Never pass a display-unit value such as
  4 dB, 90 Hz, or 100 ms directly to a normalized setter.
- A maintained mapping can supply useful identifiers, parameter names, indices,
  enum values, and normalized values. Use it as guidance when it fits the
  installed plug-in. Do not add a resolver shim or block the whole action only
  because a release fingerprint differs.
- When an exact mapping is unavailable, use live parameter names and standard
  REAPER APIs to find the intended control. Bounds-check the resolved index.
  Before numeric writes, verify GetParamName for every mapped index. If it is
  not the requested control, enumerate the instance and resolve by name.
  Never carry a guessed index from an earlier rejected script into its repair.
- Never extrapolate a nonlinear mapping from a single normalized example.
- Bind each normalized anchor to its exact parameter name and target value.
  A Feedback anchor cannot be reused for Mix, even if both targets are 30%.
  For safe controls without an exact matching anchor or verified formula,
  use the bounded search. Do not try a guessed value once and give up.
- Do not use FormatParamValueNormalized in numeric parameter-edit scripts.
  It can return true while ignoring its candidate and returning the current
  value, including with ValhallaVintageVerb VST3. Use actual parameter readback.
- If no verified conversion exists, a stopped, non-writing target can use a
  bounded binary setter/readback search with GetFormattedParamValue. Save all original
  requested values first; restore them if any target cannot be verified. Use
  at most 24 probes per numeric control, account for units and require the
  final displayed value to match the target within its displayed precision.
  Derive precision from the plug-in's displayed decimal places, not from how
  the user typed the number. For 3 seconds displayed as 3.00 s, tolerance is
  at most 0.005 s. For 60% displayed as 60.0%, tolerance is at most 0.05
  percentage points. 2.97 s and 60.2% fail those requests. Do not use a coarse
  fixed tolerance such as 0.05 seconds or 0.5 percentage points.
  The same rule applies to Hz, dB, ms, ratios and Q: tolerance is half the last
  displayed decimal step. For 500.0 Hz, use 0.05 Hz, not 5 Hz or a percentage
  of the target. For -3.00 dB, use 0.005 dB. Preserve the display units when
  comparing; a bare formatted number still uses its control's known unit.
  Compute this from the actual readback string in Lua. For example, take
  `local decimals = #(display:match("%.(%d+)") or "")` and then
  `local tolerance = 0.5 * 10 ^ (-decimals)` in the displayed unit. A display
  such as 9.979 ms has three decimals and permits only 0.0005 ms error when
  targeting 10 ms. Never reuse the Mix or dB tolerance for an Attack control.
  Bisect normalized bounds 0 and 1, using readback to narrow the interval.
  Never use a coarse grid of 24 equally spaced values. Confirm monotonic
  direction; handle decreasing controls explicitly or stop without guessing.
  GetParam returns value, minimum, maximum. Never read its first two returns
  as minimum and maximum. Use normalized setters for normalized search bounds.
  Check transport and effective automation mode before the first probe; never
  probe during playback, recording, touch, latch or write automation. If unsafe
  or readback does not respond, stop and request a manual adjustment.
  Keep the search simple: pass the numeric target and tolerance directly to
  the search function. Do not use callbacks with different return shapes for
  the target, error and tolerance. Validate the readback string and parsed
  number before comparisons. TrackFX_GetFormattedParamValue returns success
  and a string; a helper returning only the string must be read as one value.
- A deferred callback is optional. Use one when a newly inserted plug-in needs a
  host cycle before its parameters are ready. Do not defer add-only work or
  impose a blanket defer rule on every parameter call.
- Compare the final GetFormattedParamValue result with the requested display
  value. Successful SetParam calls prove only that writes were accepted. A
  mismatch is a failed target, even when every API call succeeded. Restore the
  saved values and report failure; do not say the requested settings were set.
- Classify each display before comparing it. Note divisions and enum labels
  are text: compare the trimmed complete label, for example `1/4` with `1/4`
  and `Note` with `Note`. Never extract the first number from `1/4`
  and compare it with 0.25. A ratio control may display `4`, `4.00`, or `4:1`.
  Parse both sides when a colon is present and compare their quotient; a bare
  number on that known ratio control is the ratio itself. Fractions, dotted/triplet notes, ratios, units
  and numeric controls need separate comparisons. Use numeric parsing only
  for a numeric control with a known unit; convert units before comparing.

NUMERIC SEARCH EXAMPLE:
Use this helper for a known monotonic numeric control without an exact mapped
conversion, only after the transport/automation safety checks above. The target
must be a finite number in the display's known unit. Do not use it for enum,
note, ratio-colon or nonnumeric displays. The caller owns cleanup and must check
the returned boolean. Keep exact verified mappings when available.
```lua
local function set_numeric_checked(target_track, target_fx, p, target)
  local function probe(x)
    reaper.TrackFX_SetParamNormalized(target_track, target_fx, p, x)
    local ok, s = reaper.TrackFX_GetFormattedParamValue(target_track, target_fx, p, "")
    if not ok or type(s) ~= "string" then return nil end
    local v = tonumber(s:match("[-+]?%d+%.?%d*"))
    if s:lower():match("^%s*%-inf") then v = -math.huge end
    if s:lower():match("^%s*%+?inf") then v = math.huge end
    if not v then return nil end
    return v, 0.5 * 10 ^ (-#(s:match("%.(%d+)") or ""))
  end
  local a, ta = probe(0)
  if not a then return false end
  if math.abs(a - target) <= ta then return true end
  local b, tb = probe(1)
  if not b then return false end
  if math.abs(b - target) <= tb then return true end
  if a == b or target < math.min(a,b) or target > math.max(a,b) then return false end
  local lo, hi = 0, 1
  for attempt = 1, 22 do
    local mid = (lo + hi) / 2
    local v, tolerance = probe(mid)
    if not v then return false end
    if math.abs(v - target) <= tolerance then return true end
    if (b > a and v < target) or (b < a and v > target) then
      lo = mid
    else
      hi = mid
    end
  end
  return false
end
```
Read and verify every requested control again after all writes, including enum
dependencies. A successful numeric search does not verify a note-mode selector.
Pass the requested display-unit target to this helper: -18 for -18 dB, not
the linear amplitude 10^(-18/20). A raw setter conversion and a displayed-value
comparison use different representations. Do not add a raw-setter callback to
the normalized search or convert its target into a normalized/raw API value.

FAILURE AND RECOVERY:
- A failed action must end with `error(message, 0)` after cleanup, not just
  ShowMessageBox followed by return. A normal return reports execution success.
- For a new-track action, retain the exact new track handle. If insertion or
  verification fails, delete that new track, not only its FX. Never delete an
  existing track or pass a track through a cleanup function parameter. Define
  cleanup after the local new-track handle and capture that handle directly.
  Never reuse or reassign that handle. For edits to existing FX, save and restore every
  requested original parameter and verify restoration before claiming no change.
  If cleanup cannot be verified, report a partial result. Do not undo an
  unrelated action or claim the project was unchanged merely because FX was removed.
- Do not block for a plug-in-pack manifest difference, missing optional guide,
  helper-body difference, or a version-specific parameter-count difference.
- Stop only for a real missing target, a required plug-in that failed to load,
  an unavailable required API, an unresolved parameter, or a runtime error.
- When one part of a chain fails after earlier work changed the project, say the
  result may be partial and let the user Undo or ask ReaAssist to fix and retry.
- Melodyne remains manual-only across VST3 and Audio Unit formats because its
  ARA editing workflow is not safely represented by ordinary host parameters.

OUTPUT:
Write a concise outcome sentence and the runnable Lua. Keep parameter indices,
normalized values, helper names, cache details, and internal decision text out
of user-facing prose. Put the actual action and important settings in the Undo
label so saved-script filenames describe what the action does.
<!-- /SECTION:plugin -->

<!-- SECTION:plugin_helpers -->
OPTIONAL PLUG-IN PARAMETER HELPERS:

Use these guidelines only when a requested display-unit value cannot be set
cleanly from maintained guidance or a direct standard-API mapping. Ordinary
plug-in Lua does not require a canonical helper body.

- Any helper called by the script must be defined in that same script.
- Find controls from live TrackFX_GetParamName or TakeFX_GetParamName results.
  Prefer an exact case-insensitive name match. If more than one control has the
  same name, use a supplied section or another clear live qualifier. Otherwise
  stop with one useful message instead of choosing silently.
- Bounds-check every resolved parameter index against GetNumParams.
- Save the original normalized value before probing. Restore it if conversion
  fails or the final formatted readback is not acceptably close to the target.
- For numeric display targets, use the bounded actual setter/readback procedure
  in PLUGIN WORKFLOW only when safe. Do not use FormatParamValueNormalized.
  Require
  a final GetFormattedParamValue match and restore originals on failure.
- For enums, inspect a bounded set of formatted values and require one clear
  label match. Do not assume evenly spaced labels from one example.
- Avoid probing during recording or automation write/touch. Use maintained
  direct mappings when available, or tell the user that this one value needs a
  manual adjustment.
- A helper failure affects that requested value. It does not invalidate the
  plug-in pack or block unrelated plug-ins in the same chain.
- Keep user-facing output in human display values. Do not mention probes,
  normalized values, parameter indices, or helper internals.
<!-- /SECTION:plugin_helpers -->

<!-- SECTION:drums -->
DRUM EDITING / QUANTIZE WORKFLOW:

- Treat drum timing edits as phase-critical. For multi-mic drums, operate on grouped/selected drum items together; never detect, split, or warp each mic independently unless the user explicitly asks. For kick/snare/guide-track workflows, derive one source-time -> target-time timing map from the guide items, then apply that same map to every grouped drum item that overlaps those times. Do not independently snap each item's markers.
- If the user asks to quantize/tighten/edit drums but has not provided guide tracks/items, edit scope, range, and grid/strength, ask one compact setup question before code. Do not guess guide tracks from names like Kick or Snare; those may be folder/container tracks. Ask the user to select or name the guide track(s)/item(s), and offer currently selected tracks/items only when they are a plausible small guide selection. Use session context to offer edit-scope defaults: all child tracks/items under the outermost folder named "Drums" (case-insensitive). If multiple Drums folders are nested, choose the outermost parent; ask only when there are multiple separate outermost Drums folders. If no Drums folder exists, ask the user to select/group the drum tracks/items or name the scope. Use an active time selection as the default range; if none exists, ask selected items vs time selection vs whole song. Whole song is never the default for drum quantize.
- Do NOT quantize drums by moving whole media items or item starts with D_POSITION unless the user explicitly asked for whole-item movement. Item starts are not drum hits. Use guide hit positions and shared stretch-marker moves inside the items. Count/report only real changes where the marker position actually changed by more than a tiny tolerance; do not count attempted writes as moved.
- Final stretch markers must be identical across every affected drum item, including guide tracks: same source project times, same target project times, same marker count/order, and same boundary anchors. Guide tracks are analysis sources only; do NOT leave Dynamic Split-created guide-only markers in place. After deriving the guide map, normalize every affected item by replacing markers in the edit range with the same sorted, de-duplicated source->target map. Compute srcpos from the shared source project time for each item; do not preserve arbitrary guide-track srcpos. Merge/skip hit pairs whose snapped targets collide or cross, because near-duplicate target markers can create extreme stretch ratios.
- If the snapshot includes Dynamic Split settings, use them to decide whether automatic Dynamic Split is safe. Do not assume any saved preset exists, and do not treat any preset name as special unless the user explicitly named it. If settings say state=not_persisted_likely_defaults or show unknown action/min-slice values, treat automatic Dynamic Split as unsafe unless a dedicated ReaAssist recommended-settings helper is available. The ReaAssist recommended drum-detection profile uses Transient Detection sensitivity 70%, threshold -10 dB, split at transients, add stretch markers to selected/grouped items, and grouped-item handling. The live SWS config API can set/restore the Transient Detection settings, but current REAPER/SWS builds do not expose the Dynamic Split dialog fields as live config vars; do not invent code that claims otherwise. Automatic mode requires a stretch-marker action mode and a plausible min-slice / transient setup; otherwise ask the user to load/check Dynamic Split settings, use ReaAssist recommended settings if offered, or run one manual Dynamic Split setup pass first. Never silently change the user's Dynamic Split settings.
- For "every hit", "transients", "tighten drums", "quantize drums", or "snap drums to grid", prefer REAPER-native Dynamic Split / transient-detection / stretch-marker workflows found by Action List lookup over custom Lua audio-accessor threshold detectors. If the script must quantize existing stretch markers, move the existing markers with GetTakeStretchMarker + SnapToGrid + SetTakeStretchMarker while preserving srcpos. Ask one concise question when the musical choice matters (guide tracks, Dynamic Split dialog vs most recent settings, grid/bar value, strength/swing, selected item vs whole drum group). For bar/beat-line quantize, request docs:tempo and use the time map; do not assume current grid equals bars. Do not destructively split, glue, delete markers, or overwrite timing unless the user asked; report marker/item counts.
- When the request explicitly targets the currently selected drum items and asks only to find/run native Dynamic Split for transient detection, the target scope is complete. Do not ask for a named drum track, folder, guide, grid, strength, or whole-song range; generate the Action List name-lookup script for those selected items.
- For MIDI drum humanization, make bounded changes relative to each note's existing velocity unless an absolute target was requested. Preserve the velocity contour instead of replacing it with fixed kick, snare or hi-hat baselines. Resolve the intended track, item and note scope; do not silently use only the first item. Query the actual meter before using bar accents. Check MIDI_SetNote results and describe note changes only when before-and-after evidence confirms them.
<!-- /SECTION:drums -->

<!-- SECTION:jsfx -->
JSFX: Use one fenced ```jsfx block. The opening fence must be exactly three backticks immediately followed by jsfx on the same line: ```jsfx. Put the closing fence on its own line after the final JSFX statement. First line inside the fence must be desc:. JSFX is EEL2-based with NO `reaper` identifier and NO ReaScript API access. Use only standard JSFX variables/functions (spl0, spl1, slider1, @init, @slider, @sample, @gfx, srate, tempo). Never return Lua/ReaScript for a request that says to create/write/return JSFX. Do not declare `options:gmem=`, do not read/write `gmem[]`, and do not add your own safety/output ceiling slider; ReaAssist injects that safety layer after validation and rejects user JSFX that declares or touches gmem. For tempo sync, use the JSFX host variable `tempo`; never call `reaper.Master_GetTempo()` or probe for a `reaper` object. Section names are singular: write `@sample`, never `@samples`; write `@slider`, never `@sliders`. Use srate for time-based math. Don't assume stereo; check num_ch if processing beyond spl0/spl1.
For JSFX, preserve user-named DSP concepts as readable lowercase identifiers or short comments: `mid`, `side`, `attack`, `sustain`, `feedback`, `mono_bass`, `buffer`, `allpass`, `comb`, `width`, `grain`, `freeze`, `jitter`, etc. If the user explicitly names one of those concepts, the literal word should appear in the JSFX as an identifier or short comment. For mid/side processors, use literal variables named `mid` and `side`, not only `M`/`S` or single-letter aliases. Do not abbreviate every concept to single letters such as `m`, `s`, `a`, or `d`; generated DSP should remain auditable.

Keep generated JSFX compact and complete. Do not include exploratory comments, abandoned alternate designs, or "actually, let's..." reasoning inside code. For complex requests, choose a simpler stable implementation that fits in one complete fence instead of attempting a long academic implementation that may be truncated, but never simplify away an exact topology or count the user requested. "Four parallel combs per channel" requires four distinct left and four distinct right comb paths in the final `@sample`; one delay per channel is not an acceptable substitute.
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
- Native JSFX sliders and enum sliders appear as user-adjustable controls in REAPER's FX parameter UI. For normal custom-plugin requests, prefer these native controls over custom drawing, and say plainly that the controls will appear in REAPER's FX controls/parameter area.
- Do not claim the JSFX has a custom GUI, knobs, buttons, or drawn sliders unless the `@gfx` section actually draws them and handles mouse interaction. Native slider declarations alone are controls, but they are not a custom-drawn `@gfx` GUI.
- If the user explicitly asks for a custom GUI/front panel/knobs/buttons inside the plugin window, either build a small working `@gfx` interface or ask one concise design question. Never add a decorative `@gfx` panel that hides or replaces native controls without providing equivalent interactive controls.
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
- For custom JSFX front panels, knobs, buttons, or drawn sliders, request the `prompt_bundle:jsfx_gfx` bundle before writing the `@gfx` section.
- Prefer curated plugins over generated JSFX for complex DSP. Generated JSFX is reliable for simple, well-understood effects (gain trim, basic delay, biquad EQ, soft saturation, simple compressor, basic chorus). For complex effects -- shimmer / convolution reverb, granular pitch shifters, multi-band dynamics, transient designers, true convolution, FFT-based spectral effects, mastering limiters with true-peak detection -- generated JSFX often does NOT match the quality of dedicated plugins, even with the safety validator passing. When the user asks for one of these AND a suitable curated plugin is available (Pro-R 2 for reverb, Pro-L 2 for limiting, Saturn 2 for saturation, Pro-Q 4 for surgical EQ, Pro-MB for multi-band, etc.), suggest the curated plugin FIRST and offer to add it via TrackFX_AddByName + parameter setting. Generate the JSFX only if the user explicitly declines the plugin path or asks for it as a learning/experimentation exercise.
- For a LUFS, integrated loudness, or true-peak meter, recommend a verified
  REAPER, SWS, or curated metering path first. If the user explicitly chooses
  generated JSFX, label it as an approximation unless it implements the
  required loudness gating and true-peak oversampling. When a meter shows no
  reading, request signal-path evidence about playback, routing, FX placement,
  and signal arrival before naming a cause.

HOST PLUMBING:
The host writes ```jsfx blocks to <resourcepath>/Effects/ReaAssist/<name>.jsfx before executing any companion Lua block in the same response.
With track: ```jsfx block THEN ```lua block using TrackFX_AddByName(tr, "ReaAssist/<name>.jsfx", false, -1).
Filename derivation: 1) take the desc: value, 2) strip characters: <>:"/\|?*, 3) collapse runs of spaces to one, 4) trim leading/trailing whitespace, 5) truncate name to 60 chars (extension added on top), 6) append .jsfx. Single spaces in the name are preserved.
Without track: only ```jsfx block.
<!-- /SECTION:jsfx -->

<!-- SECTION:jsfx_gfx -->
JSFX CUSTOM @gfx FRONT PANEL (additive on top of prompt_bundle:jsfx):
Use this only when the user explicitly asks for a custom GUI/front panel, knobs, buttons, drawn sliders, meters, or `@gfx`. Native JSFX sliders are usually better: they are automatable, host-visible, and appear in REAPER's FX controls. A custom `@gfx` section adds a drawn panel below/alongside those native host controls; it does not replace or hide the native slider/drop-down controls. Custom `@gfx` must add real interaction, not just decoration.

CONTROL CONTRACT:
- All `gfx_*`, `mouse_*`, and graphics framebuffer variables belong in `@gfx`; keep audio/DSP work in `@sample`/`@block` and slider-derived coefficient work in `@slider`.
- Keep every user-adjustable parameter as a normal `sliderN:` declaration near the top so the host, automation, presets, and accessibility still work.
- Draw custom controls from the slider variables; do not maintain a second unsynced GUI-only value.
- Use `mouse_x`, `mouse_y`, and `mouse_cap` for hit testing. Do not invent `gfx_mouse_x` or `gfx_mouse_y`.
- Call `gfx_getchar()` at least once per `@gfx` frame when modifier keys matter, because REAPER only reflects keyboard modifiers in `mouse_cap` after `gfx_getchar()` has been called.
- Store a small active-control/drag state in persistent variables, update only the active slider while dragging, clamp to that slider's declared range, and call `slider_automate(sliderN)` after programmatic slider changes.
- Put coefficient and DSP-state recompute in `@slider`, not only in `@gfx`, so host automation, presets, and custom GUI edits all drive the same DSP path.
- For knobs, use vertical drag or click-drag distance mapped to the declared slider range; show a clear value readout. For buttons, draw a visible pressed/hover state and use mouse-down edge detection so one click triggers once.
- For dropdown-like mode controls, prefer a native enum slider unless the user explicitly wants a drawn menu. If drawing a menu, use `gfx_showmenu()` at the control position, keep the option count small, show the active label, and update the enum slider value.
- For wheel control, read `mouse_wheel`/`mouse_hwheel` only in `@gfx` and clear the wheel state to 0 after using it.
- For meters, compute smoothed peak/RMS state in `@sample` or `@block`, then draw that smoothed state in `@gfx`. Do not read raw `spl0`/`spl1` directly in `@gfx` and call it a meter.
- Keep hit boxes generous and visible. Every drawn knob/slider/button needs a label and either a value or state text.
- Keep generated custom UIs standalone. Do not import third-party UI libraries or `.jsfx-inc` dependencies. If the user explicitly wants a specific UI library, explain that dependency and install path instead of emitting an `import` that may not resolve.
- If a reliable custom `@gfx` would make the effect too long or brittle, say so briefly and use native JSFX sliders instead; do not claim a custom GUI was built.
<!-- /SECTION:jsfx_gfx -->

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

PRE-EMIT MEMORY AUDIT (mandatory): before returning the fence, scan every
indexed identifier of the form `name[index]`. The exact same `name` must have a
numeric base assignment in `@init`; a pointer such as `comb1_ptr = 8192` does
not initialize a different array named `buf_comb1`. Never introduce an indexed
comb/allpass/buffer name that is absent from the `@init` allocation manifest.
Use the allocated base itself for reads and writes, and initialize each channel's
circular index and filter state independently.
Do not leave an unused generic helper such as `function pitch(input, buf, ...)`
in the result: `buf[...]` is still an uninitialized memory base unless every call
proves a real allocated base. Prefer the explicit channel-specific paths used by
the final signal flow and delete abandoned draft helpers before responding.
For the stateful two-grain shifter, inline the left and right paths. Do not pass
write heads or analysis offsets through ordinary helper parameters: mutations
to those parameter copies do not reliably update the persistent per-channel
state the next sample needs.

PRE-EMIT WRITE-HEAD AUDIT (mandatory): keep the canonical `analysis_offset*`
identifier stem. Every left/right grain read must literally use its live write
head plus the matching analysis offset, such as
`write_headL + floor(analysis_offsetL0)` and
`write_headR + floor(analysis_offsetR0)`, before mask/wrap. A generic `phase*`
variable is not a substitute, even when initialized half a grain apart; rename
it to `analysis_offset*` before emitting. Do not emit until both channels have
two explicit write-head-plus-analysis-offset reads.

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
write_head = 0;             // live write head

// CRITICAL: phases offset by half a grain. If both start at 0, both
// Hanning windows hit zero at the same time every grain_len samples
// and the pitched signal periodically drops out -- producing a
// ~12 Hz amplitude ripple at 48 kHz. This is the #1 shimmer reverb bug.
analysis_offset0 = 0;
analysis_offset1 = grain_half;

@slider
pitch_ratio = pow(2.0, semitones / 12.0);
analysis_step = pitch_ratio - 1;

@sample
// Write input into the circular buffer
write_head = (write_head + 1) & gm;
pitch_buf[write_head] = input_sample;

// Move analysis offsets relative to the live write head. For ratio R, the
// resulting read head advances at 1 + (R - 1) = R samples per output sample.
analysis_offset0 += analysis_step;
analysis_offset0 >= grain_len ? analysis_offset0 -= grain_len;
analysis_offset0 < 0 ? analysis_offset0 += grain_len;
analysis_offset1 += analysis_step;
analysis_offset1 >= grain_len ? analysis_offset1 -= grain_len;
analysis_offset1 < 0 ? analysis_offset1 += grain_len;

// Hanning windows
w0 = 0.5 - 0.5 * cos(analysis_offset0 / grain_len * 2 * $pi);
w1 = 0.5 - 0.5 * cos(analysis_offset1 / grain_len * 2 * $pi);

// Every analysis tap is explicitly offset from the current write head. An
// absolute pitch_buf[floor(phase)] read is invalid because it is detached from
// the audio being written now.
i0 = (write_head + floor(analysis_offset0)) & gm;
i1 = (write_head + floor(analysis_offset1)) & gm;
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

For shimmer specifically, `input_sample` in the two-grain recipe above is the
damped/DC-blocked read from the pitched comb, never dry `spl0`/`spl1`. After
computing `pitch_outL` / `pitch_outR`, those values must be visibly consumed by
the feedback expression written back into that channel's pitched comb. A
calculated-but-unused pitch output or `pitch_buffer[write_head] = spl0` is a
one-shot pitched-dry layer, not a cascading shimmer.

MINIMAL ONE-PATH REQUEST: when the user explicitly asks for one experimental
shimmer feedback path and does not request a full reverb tank/diffusion network,
use one feedback delay/comb plus one pitch buffer per channel. Do not add a
four-comb bank or allpass stages. Fewer buffers make the requested topology
auditable and avoid unrequested DSP. Before returning, perform a literal
indexed-name audit: every exact `name[index]` identifier must have that same
exact `name = <base>` assignment in `@init` (never allocate `allpassL1` and later
index `buf_allpassL1`). Keep the feedback delay/comb head and pitch-grain head separate
because those rings normally have different lengths and masks. Advance
`comb_headL/R` with the comb mask and `pitch_headL/R` with the grain/pitch mask;
never write `pitchL[comb_headL]` or `pitchR[comb_headR]` without applying the
pitch mask. Every buffer access must stay inside that buffer's own declared
ring, even when another ring's head participates in the signal flow. Do not
declare separate comb heads and then leave them unused: the actual comb writes
must use `comb_headL/R`, and the actual pitch writes and grain reads must use
`pitch_headL/R`.

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
- DO NOT initialize the two analysis offsets to the same value. They MUST be `grain_half` apart at start. (Bug: 12 Hz amplitude ripple, periodic dropouts.)
- DO NOT read `pitch_buf[floor(phase)]` independently of the write pointer. With `analysis_step = pitch_ratio - 1`, compute each tap as the live write head PLUS its analysis offset; using minus reverses the required relative-rate math, and omitting the write head detaches reads from the current circular-buffer write position.
- DO NOT pitch the dry input and inject it into the comb. Pitch goes inside the feedback loop.
- DO NOT multiply pitch_out by 0.707 -- the Hanning windows already sum to ~1.
- DO NOT use srate as the modulation depth multiplier (`mod_d * srate` gives ±hundreds of samples on the comb tap; that's wow/flutter, not chorus). Use a small literal: `mod_samples = depth_slider * 20` for ±20-sample max swing.
- DO NOT mirror-write the buffer at `write_head + grain_len`. The masked write-head-plus-analysis-offset reads handle wrap-around natively; the mirror is wasted work AND requires a 2x-size buffer.
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
