# ReaAssist - Changelog

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
