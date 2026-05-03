# ReaAssist - Changelog

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
