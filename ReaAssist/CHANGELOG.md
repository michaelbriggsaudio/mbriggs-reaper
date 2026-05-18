# ReaAssist - Changelog

## v1.2.4 - 2026-05-18

- **Generated scripts are safer around MIDI, tempo, and automation edge cases.** ReaAssist now catches more bad MIDI input filters, MIDI pitch tables, item labels, tempo-marker alignment mistakes, panner/LFO ambiguity, and unsafe pan automation before code can run.

- **Follow-up questions are lighter and cleaner.** Simple explanation-only follow-ups avoid pulling in heavy project snapshots and pinned reference context, reducing unnecessary prompt weight while preserving the actual conversation.

- **Diagnostics and feedback evidence are more useful.** Reports now carry clearer execution, validation, model, and auto-run context so failed or inert responses are easier to understand from the exported evidence.

- **Model guidance is stricter for common failure patterns.** Lower-tier and mid-tier models get tighter guardrails for stock plugins, third-party parameter guesses, toolbar actions, MIDI generation, and existing-FX edits.

## v1.2.3 - 2026-05-15

- **ReaAssist runtime scratch files now stay in the app's Data folder.** Temporary curl, update, screenshot, feedback, and diagnostics files no longer clutter the REAPER resource root.

- **Recent REAPER guidance is updated for REAPER 7.73.** ReaAssist now knows about the latest grid actions, sample editing improvements, razor edit behavior, track grouping updates, and the built-in MIDI Choke Group JSFX.

- **The update prompt now links to the site-hosted changelog.** The update popup includes a quieter View Changelog button that opens the new `reaassist.app/changelog/` page.

## v1.2.2 - 2026-05-15

- **ReaAssist data now lives in a dedicated Data folder.** Preferences, provider records, selections, runtime state, FX cache, and debug logs are migrated out of REAPER ExtState / shipped Resources files into `Data/`, with cleanup of legacy entries after successful writes.

- **Factory Reset is cleaner and more complete.** Reset now wipes the new data/config files, avoids recreating stale state during the clean-boot pass, and keeps onboarding/model-default state from leaking back in after reset.

- **The updater and repair dialogs are more polished.** Update prompts, repair prompts, progress cells, completion text, wrapping, and alignment now match the installer-style presentation more closely.

- **Prompt guidance is tighter for JSFX, MIDI, and Gemini failures.** JSFX memory-heavy effects get a focused DSP cookbook, MIDI bass/part derivation handles musical intent more carefully, and Gemini provider outages are reported as provider availability problems instead of user/setup failures.

## v1.2.1 - 2026-05-13

- **Chat reply language is now configurable in beta.** Settings has a Chat Language selector for English, Spanish, French, German, Italian, and Portuguese; it changes assistant prose only while keeping code, diagnostics, provider/model names, REAPER API names, paths, filenames, and raw tags unchanged.

- **More track-state questions answer instantly.** ReaAssist can answer common local questions about track volume, pan, mute/solo/record-arm, master/parent output, sends, and generic FX presence without spending a model call.

- **Generated track scripts are guarded more tightly.** The validator better follows track counts through simple creation loops and table-driven naming, catching off-by-one track and folder-child mistakes before code can run.

- **FX loading failures are caught earlier.** The AddByName validator now flags unassigned `TrackFX_AddByName` / `TakeFX_AddByName` calls as well as unchecked assigned results, so scripts retry instead of silently treating a missing plugin as success.

## v1.2.0 - 2026-05-13

- **Local structured edits are now built in.** ReaAssist can handle common track edits locally and offline, including creating tracks, renaming tracks, building folders, setting sends, changing mute/solo states, and applying exact track-order edits with stronger validation before anything runs.

- **DeepSeek is now a first-class provider.** DeepSeek now appears alongside Claude, ChatGPT, and Gemini, with built-in model guidance, help coverage, request handling, and provider-specific safeguards.

- **REAPER knowledge is refreshed through 7.72.** The bundled reference now includes recent ReaScript and workflow updates such as AddRegionOrMarker, GetUserFileName, ruler-lane APIs, displayed-color reads, sample-editing additions, and hidden marker/region render options.

- **More project questions answer instantly.** ReaAssist can answer many track, item, FX, send, selection, playhead, project, settings, update, model, and diagnostics questions directly from REAPER state.

- **Generated edits are safer.** The validator now catches more bad targets, invalid folders, empty parameter writes, stock-FX value mistakes, non-runnable Lua fragments, and other cases that could produce no-op or wrong-session results.

- **Diagnostics are clearer.** Feedback reports now include better app, provider, model, extension, settings, and recovery context.

## v1.1.5 - 2026-05-08

- **SWS Extension is now installed and managed by ReaAssist.** Fresh installs and outdated installs can automatically download, verify, and install SWS alongside ReaImGui and js_ReaScriptAPI, with the same restart-after-install flow.

- **New SWS-aware scripting support.** The bundled API reference now includes common SWS functions for clipboard, mouse context, GUID helpers, loudness/peak/RMS analysis, SWS notes, FX-chain windows, FNG MIDI helpers, and action introspection.

- **Dependency installer polish.** The install and success windows are wider on macOS/Linux, SWS install/update paths clean up stale backups after a successful launch, and the PowerShell hash fallback works in stripped-down REAPER-launched environments.

- **Safer generated routing and plugin scripts.** ReaAssist now catches more bad Lua before auto-run, including ignored `CreateTrackSend` return values and cases where a model substitutes third-party EQ/compressor plugins after the user explicitly asked for stock ReaEQ/ReaComp.

- **Prompt and JSFX guidance fixes.** The JSFX pitch bundle and target-continuity rules were tightened so models get clearer instructions on pitch/shimmer limits, plugin-tip scope, and follow-up target handling.

- **Chat UI polish.** Auto-run code blocks now show a calmer status treatment and avoid presenting the manual Run button as the primary next action after code already ran.

## v1.1.4 - 2026-05-06

- **New model picker UX.** Each provider's recommended model and recommended thinking level now show a "*" badge in the chip dropdowns. A brief explainer line ("Best for | Cost | Speed | Note") appears below the chips when you change the selection and fades after 10 seconds. Hovering any row in the thinking dropdown previews that combo's explainer before you click.
  - One-time reset on upgrade: v1.1.4 wipes any existing model + thinking-level picks once on first launch so everyone lands on the new bench-driven defaults. Re-pick from the chip dropdowns if you preferred a different combo.

- **New default model + thinking picks** for built-in providers, based on bench testing of multi-step REAPER scripting tasks:
  - Anthropic: Sonnet 4.6 (no thinking) remains the recommended Claude default; Haiku 4.5 default thinking moves Low to High (the only Haiku combo that handles complex routing reliably).
  - OpenAI: full GPT-5.4 (no thinking) replaces mini as the recommended OpenAI default; nano default thinking moves Low to None.
  - Gemini: Flash Lite default thinking moves Minimal to Low; Flash 3 default thinking moves Low to Minimal (fastest combo in the lineup).

- **Help page Quick model guide** added under Providers & Models with the recommended pick per provider. Help page renderer now handles markdown tables and `###` sub-headings, so the existing Stock Fallbacks table and the new Quick model guide render properly instead of as raw markdown.

- **ReaComp Threshold** conversion clarified in the plugin reference (`value = 10^(dB / 20)` formula + worked examples), reducing the rate at which lighter models pick the default normalized value when asked for a specific dB target.

## v1.1.3 - 2026-05-05

- **Per-turn API call cap.** A 15-call ceiling per turn stops a stuck model from silently racking up cost on retry loops, and nudges toward a higher-tier model where one applies.

- **More auto-recovery from broken replies.** One-shot hidden retries for unfenced Lua, unclosed ```lua fences, and `local x = reaper.InsertTrackAtIndex(...)` (the function returns nothing) -- all previously dropped silently or produced no-op scripts.

- **ReaScript reference fixes** to reduce wrong-output on lighter models: ReaComp Threshold direct values, immediate `TrackFX_AddByName` error checks, `D_PAN` is direct (-1..1) not percent, and `TrackFX_SetParam`/`GetParam` arg order.

## v1.1.2 - 2026-05-05

- Per-model thinking levels. Each model now remembers its own thinking-effort pick instead of one shared setting per provider. Switching Sonnet -> Haiku -> Opus and back keeps each model's level independent. Models can also carry a default (Haiku 4.5 starts at Low; GPT-5.4 nano/mini start at Low; Gemini Flash Lite at Minimal, Flash at Low, Pro at Medium; everything else None).
  - One-time reset on upgrade: v1.1.2 wipes any existing thinking-level pick once on first launch so everyone lands on the new defaults. Re-pick from the chip dropdown if you preferred a different level -- your choice is then remembered per-model from then on.

- Anthropic extended thinking. Claude models can now run with thinking enabled (off by default). Opus 4.7 uses the new adaptive shape; Sonnet 4.6 / Haiku 4.5 use the manual budget shape. If a thinking turn burns its visible-output budget on reasoning, the existing length-retry path automatically falls back to thinking off.

- Per-model context windows in preflight. The local token gate now respects each model's actual context window (Sonnet 4.6 / Opus 4.7 = 1M, GPT-5.4 nano/mini = 400K, GPT-5.4 full = 1.05M, Gemini 3.x = 1.05M) instead of treating everything as 200K. Long-context requests that previously got rejected before reaching the wire now go through.

- Backup-warn popup hardened. "Save Project" path now bails (and surfaces a Log error) if the safety backup itself fails, instead of silently running the generated code without a backup. New "Disable Auto-Backup" button on the same popup for users who want to opt out.

- Details card: "Est. Cost" / "Est. Total" rows hide when the active model has no prices entered (e.g. local llama.cpp, custom OpenAI-compatible endpoints), so you don't see "~$0.000000". Free-tier Gemini still shows the "would have been ~$X" framing.

- Chip dropdowns: Provider / Model / Thinking popups open with a labelled header so it's clear what each chip selects.

- API Keys cards: dropped the bold weight on provider names and the redundant "API Key" suffix from card titles.

## v1.1.1 - 2026-05-04

- New Report an Issue form on the Help page for bugs that need more than a thumbs reaction. Captures a description, optional contact info for replies, and ReaAssist attaches the redacted Advanced Log (or current chat as a fallback). Custom-provider endpoint URLs (LAN IPs and self-hosted hostnames) are scrubbed before send.

- Custom LLMs: new "Test with a real chat/completions request" option above Test Connection. Catches misconfigurations the models-list probe misses (auth scope mismatch, configured id is not a chat model). Off by default to avoid surprise inference charges on reasoning models.

- Custom LLMs: Test Connection no longer silently rewrites unrelated endpoint paths to /v1/models, so testing against servers with non-OpenAI chat paths works correctly.

- Custom LLMs: multi-line endpoint values now round-trip correctly through REAPER's INI ExtState; configured providers no longer silently lose lines after a REAPER restart.

- Custom LLMs: model rows with a typed override but no id are blocked at save time; stale model-index values are clamped when the active row is deleted underneath them.

- FX-parameter calls scope per-track and dedupe identical-state writes, reducing redundant calls when chaining FX state across tracks.

- Manual and Help: documented the new Report an Issue form and clarified that js_ReaScriptAPI is auto-installed alongside ReaImGui.

## v1.1.0 - 2026-05-04

- First public release announcement.
- Dependency auto-install: ReaAssist now installs its required dependencies (ReaImGui, js_ReaScriptAPI) on first launch instead of pointing you at ReaPack docs.
- Various bug fixes and polish.

## v1.0.8 - 2026-05-03

### Install & onboarding

- ReaImGui (the required UI dependency) now installs itself on first launch instead of pointing users at the ReaPack docs. A small dark-themed installer downloads the right binary for your platform, SHA-256 verifies it, and atomically installs it -- no manual ReaPack step needed. macOS quarantine attribute is stripped automatically. Same path applies if ReaImGui is older than the pinned minimum (v0.10.0.5).
- Bootstrap UI distinguishes first-launch (minimal popup with per-file progress cells) from existing-install repair (styled dialog with file list and Repair/Quit buttons). Install errors that previously stalled on a blank popup now route to the styled error view.
- Cross-platform install hardening: Linux ARM detection (was falling through to x64 on aarch64), PowerShell rollback when the move-into-place step fails, progress-cell off-by-one, ASCII bullet in the repair list (Mac/Linux Proggy fallback), and `sha256sum` tried before `shasum` for broader Linux compatibility.

### UI

- Custom-provider model rows: notes are now a second inline column instead of buried in the Details popup, so a duplicated row can be retagged in place. The wide "Details" pill and bare "x" are replaced with three ghost icon buttons (settings / duplicate / delete). Active model gets the same checkmark as built-in providers.

### Prompt

- Generic chain prompts ("rock vocal chain", "add a compressor") now correctly trigger pref discovery on non-thinking models. Previously these would skip resolution entirely on lighter models and emit code against stock plugins instead of your preferred FX.

## v1.0.7 - 2026-05-02

- New "Send Feedback" flow: thumbs-up / thumbs-down icon buttons appear under each assistant message; click opens a single-screen modal with an optional comment box and, on thumbs-down, a row of secondary tags (Wrong result, Wrong plugin, Didn't follow request, Too slow). Submission goes to ReaAssist's feedback endpoint and surfaces a "Feedback sent" toast.

## v1.0.6 - 2026-05-01

### Reliability

- Static validator stack expanded with five new checks running before auto-run: arity check for fixed-arity `reaper.*` calls (catches missing `paramidx` arguments), unchecked `TrackFX_AddByName` results (silent-skip prevention), chain-build upsert pairing (every plugin needs both `GetByName` and `AddByName`), helper-body integrity (catches subtly rewritten `set_param_display` bodies -- missing parens on the range guard, missing `pidx`, etc.), and a Lua-syntax preflight on `lua` blocks. Each fires a hidden retry on hit; the visible response is the corrected one.
- Auto-run gate now consults all validator outcomes. Previously, four newer validators could correctly mark a script as "auto-run blocked" but the auto-run check was stale and ran the script anyway. Centralised the check so future validators wire in automatically.
- Auto-retry on transient provider stalls (empty response with `finish_reason=stop` and no body) and on Lua parse failures in the generated code block.
- `set_param_display` canonical helper is now nil-safe in its parse step; some VST3 plugins return nil during the binary-search probe and the bare form crashed.
- Helper-validator catches out-of-order helper definitions (helper called above its `local function` declaration -- Lua compiles the call as a global lookup and crashes at runtime).

### Cost & cache

- Curated plugin names in the prompt (Pro-Q 4, Pro-C 3, ReaEQ, etc.) now pre-pin their full parameter reference + plugin bundle on the first turn, eliminating the round-trip the model used to spend asking for it.
- Chain-build follow-up turns ("build a vocal chain" after an earlier turn placed plugins) now pre-pin the current FX chain plus a short upsert skeleton, so the model reuses existing plugins instead of duplicating them.
- Already-pinned `<context_needed>` re-requests are caught by a fast-path that fires the corrective hint without re-fetching the data.
- Anthropic cache TTL frozen per-rung at 5m; the 1h-after-5m escalation that previously generated invalid_request errors on multi-turn sessions is removed.
- Opt-in history compaction (off by default) for users running many-turn sessions.

### Prompt fidelity

- Plugin bundle restructured around an explicit decision spine; resolved a conflict between the EQ "configure all band params on a fresh band" rule and the minimal-write rule.
- New rules cover: `pcall` discipline for param writes, paste-the-definition for helper functions, chain-build upsert pattern, required-plugin failure check, cross-turn add-vs-reuse, and target-track resolution from the session snapshot.
- Hardened against version-variable enums (Pro-Q 4 Slope) and non-linear curve loopholes that previously produced silent value drift.
- API reference: fixed a MIDI tempo bug, a broken Lua pattern, and a few wrong API claims; deduped and reordered for clearer top-down flow; MIDI_SetAllEvts pointer added.

### JSFX

- Safety output-ceiling injector with a visible alert when a generated JSFX would exceed -0 dBFS.
- JSFX validator now gates auto-save and auto-run before the file lands; new EEL2 syntax rules in the jsfx bundle.
- `jsfx_pitch` family bundle (shimmer reverbs, pitch shifters, harmonizers).
- Multi-plugin `fx_inspect` requests now detect truncation and warn the model instead of silently dropping plugins past the first.

### UI & UX

- "Est. Total" running-cost row added to the chat Details box for per-session billing visibility.
- AUTO-RAN pill reflects the actual run outcome (success vs error) instead of just "Code.run was called".
- "Extend by Ns" timeout button now updates the displayed Timeout value.
- TARGET HINT block in the session snapshot lets generated scripts target the track that was selected at request time, falling back to live selection only if the captured target is invalid (fixes drift when the user clicks elsewhere between sending the prompt and the deferred script running).
- Auto-update: native SHA verify is faster, JSFX-intent detection prevents docs co-pin on JSFX-only requests, manual update checks fire faster.

## v1.0.5 - 2026-04-28

- Update flow now cleans up files dropped or renamed in a new release. Previously such files lingered on disk forever after an in-plugin update; ReaPack handled this on its end, but the in-plugin updater had no equivalent. Manifest-driven and safety-gated (path-traversal blocked, install zone enforced, user-state files protected: System_Prompt_Custom.md, Debug.log, FX_Cache.json).
- Lucide icon font now ships subsetted to only the glyphs ReaAssist uses (~7 KB, down from the ~815 KB upstream font). Unused JetBrainsMono-SemiBold weight dropped. Roughly 1 MB lighter per install.
- MIDI and theme reference content folded into the main API reference file (Resources/API_Ref.md) as new SECTION blocks. Same bucket names exposed to the model, same auto-injection rules - two fewer files in Resources/, one fewer code path in the loader.

## v1.0.4 - 2026-04-28

### Plugin & FX fidelity
- Curated FabFilter and ReEQ-family plugins now auto-attach their verified parameter reference when set as your preferred plugin, instead of falling back to a thinner live-scan. Eliminates wrong-index writes and runtime popups on drum-kit-style multi-plugin scripts.
- Non-linear curve params (Pro-C 3 Release, Pro-G timing, etc.) now land at the exact requested dB/ms/Hz instead of an approximation - the plugin reference flags non-linear curves and routes through the binary-search helper.
- D_VOL volume reads use the correct linear-amplitude conversion (no more -1000 dB on a track at 0 dB).
- Anthropic flagship updated: Opus 4.6 -> Opus 4.7 (same price tier, same context window).

### Reliability
- Defer-compliance check catches param writes outside reaper.defer() that some VST3 plugins silently ignore - script reports "completed OK" but no audio change, which the validator now blocks with a single silent retry first.
- Defer validator no longer false-positives on locally-defined helper functions called from inside a defer block; correct scripts no longer get auto-run blocked.
- Empty-response auto-retry when reasoning consumes the entire output budget.
- Test API Keys no longer reports "internet down" when curl was busy with a tier check; defers the test until curl frees up, with clearer error wording for the genuine failure cases.
- Gemini tier detection: ambiguous responses (timeouts, 503s) no longer poison the cached tier; sticky toast confirms the test result; auto-retests once on next launch when the previous attempt was inconclusive.
- Data-table examples in the plugin bundle moved from positional to named-field schema to prevent the "completed OK then deferred crash" failure mode on multi-band EQ writes.

### UI & UX
- Max Tokens dropdown removed from Settings. Each model now uses its published output ceiling automatically - no more empty replies after 1-2 minutes when reasoning eats a 16K cap.
- "API Calls" counter is always visible in the Details box (was hidden when count == 1), and the Context label correctly reflects when docs were pinned.
- Removing the active provider's API key in Settings no longer leaves the home screen showing a stranded provider with Send disabled - Save snaps to the first usable provider.
- Larger Delete Provider confirmation popup so body text and buttons aren't cramped.
- Friendly error message if Resources/UI.lua is launched directly instead of through ReaAssist.lua.

### Cost & cache
- Adaptive cache TTL: 5 min on the first turn, escalating to 1 hour once multi-turn intent is confirmed. Saves the 2x write premium on one-shot script-gen sessions.
- Plugin bundle split into core + on-demand helpers; API reference split into core + 5 on-demand sections (items, envelopes, take FX, routing, tempo). Fewer tokens shipped per turn on the common case.
- Docs core is co-pinned alongside plugin context on chain-phrase preempts ("drum kit", "vocal chain", etc.) so the model writes correct code on the first try instead of triggering a silent retry.
- Single-word / conversational prompts no longer trigger a docs fetch round-trip.
- Curated user-prefs route through plugin_ref instead of live-scan when a curated plugin matches.

### Internal
- Track-iteration paths nil-guard against project-tab-close races.
- Hot-path optimizations from log analysis: cached details-card field/color maps per message, throttled session-cache rebuilds, short-circuited pipe-scrubber, cached user-bubble width.
- Resources/ filenames consolidated and de-prefixed (Plugin_Prompt + JSFX_Prompt + Theme_Prompt -> Prompts.md with section markers; ReaAssist_*.md -> unprefixed).

## v1.0.3 - 2026-04-26

Initial public release of ReaAssist - the session-aware workflow assistant for REAPER.

- Plain-English chat interface for REAPER automation
- Reads project state and acts on it directly: plugin parameters, FX chains, routing
- Lua and JSFX generation with built-in safety scanner
- Provider support: Claude, ChatGPT, Gemini, plus local/custom OpenAI-compatible endpoints
- Per-message Undo, optional pre-run session backups, dangerous-code review modal
