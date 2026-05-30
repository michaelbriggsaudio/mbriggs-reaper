# ReaAssist Help

## Overview

ReaAssist is a session-aware workflow assistant for REAPER. Type a plain-English request and ReaAssist can answer questions, inspect session metadata, generate Lua scripts, configure plugins, build routing, create JSFX when explicitly requested, and help troubleshoot results.

The in-app Help page is a quick reference while you are working. For the complete guide, use the Read Online Manual button at the top of this page.

ReaAssist is not a generative music or audio model. It does not create songs, lyrics, performances, or finished creative ideas for you. It does not upload your audio files or process them through an AI audio model. Generated REAPER scripts can still edit item properties, fades, pitch, routing, FX, and other project settings when you ask for that.

You remain responsible for the creative direction, generated code review, and backups of important projects.

## What It Can Do

- Read useful session metadata such as tracks, items, FX chains, plugin names, routing, sends, tempo, markers, regions, time selection, edit cursor, and selected objects.
- Answer questions about the current REAPER session.
- Generate Lua scripts that run inside REAPER.
- Add, configure, and automate stock or preferred plugins.
- Set up routing, sends, folders, markers, regions, edits, and project structure.
- Use SWS Extension APIs for practical tasks such as mouse context, GUID helpers, clipboard reporting, SWS notes, marker/region subtitles, FX-chain window helpers, and peak/RMS/LUFS measurements.
- Generate JSFX only when you explicitly ask for a custom JSFX effect.
- Help diagnose failed or incorrect results when you tell it what happened.

## Getting Started

1. On first launch, review and accept the Terms of Use.
2. Let ReaAssist install required extensions if prompted, then restart REAPER when asked.
3. Add an API key for at least one provider, or configure a local/custom model server.
4. Select your provider and model from the picker.
5. Decide whether to send a session snapshot with each message.
6. Type a request and press Send or Enter. Use Shift+Enter for a new line.

Before running generated code, read the code window and confirm the action makes sense for your session. For important projects, save or back up the project first.

## Prompt Examples

The most useful ReaAssist prompts usually combine a target, a desired action, and the kind of report or cleanup you want afterward.

### Session Review

- "Audit this session for cleanup issues: armed tracks, muted tracks, hidden tracks, empty tracks, bypassed FX, and unusual routing. Give me a short checklist before writing code."
- "Compare the selected tracks' FX chains, sends, colors, and folder placement, then suggest what should be standardized."
- "Find every selected track that routes to more than one destination and explain the signal flow."
- "Look at the selected vocal tracks and tell me which ones have missing compression, EQ, tuning, or reverb sends based on their FX chains."

### Editing and Analysis

- "Select the item under my mouse cursor, move the edit cursor to its start, and report its track, take name, start time, and length."
- "Find selected audio items that peak above -1 dBFS, color them red, and copy a peak/LUFS report to the clipboard."
- "Pitch-shift the selected melodic audio items up 2 semitones, leave drum tracks unchanged, and report which items were edited."
- "Create 5 ms fades on selected items that do not already have fades, then tell me how many items were changed."
- "Analyze the selected audio items and make a table with item name, track name, peak level, peak position, and integrated LUFS."

### Track and Routing Automation

- "Create a drum bus from the selected drum tracks, route them to it, color it, name it, and preserve any existing sends."
- "Build a stem-print setup for the selected tracks: create matching print tracks, route each source to its print track, name them clearly, and leave the originals muted."
- "Add subtitles to the current markers and regions using their names, then refresh the SWS notes window."
- "Add track notes to the selected tracks summarizing each track's role, routing, and FX chain."

### Mixing and Effects

- "Build a parallel drum crush return for the selected drum tracks with ReaComp, route the tracks to it, and label/color the return."
- "Set up sidechain compression on the bass from the kick, including the send and the ReaComp detector input settings."
- "Create a shared plate reverb return for the selected vocal tracks, add sends at -18 dB, and name/color the return."
- "Find tracks that have a limiter or clipper in the FX chain and make a report of where they are, including bypass/offline state."

### Plugin Configuration

- "On all selected vocal tracks, find Pro-Q 4 or ReaEQ and add a gentle high-pass around 80 Hz without changing existing bands."
- "Normalize ReaComp settings across the selected backing vocal tracks: 3:1 ratio, 10 ms attack, 100 ms release, and auto makeup off."
- "List every track using Pro-Q 4 or ReaEQ, include whether each instance is bypassed or offline, and copy the report to the clipboard."
- "For selected guitar tracks, create a quarter-note delay return, send the tracks to it, and leave the existing insert FX alone."

### MIDI

- "In the active MIDI take, find overlapping notes, shorten or remove the duplicates safely, and report how many overlaps were fixed."
- "For selected MIDI items, humanize selected notes by up to 8 ticks and 6 velocity steps while preserving note lengths."
- "Transpose the selected MIDI items from C major to D major, update any marker or region names that mention the old key, and report how many notes were changed."
- "Set all selected notes in the active MIDI take to velocity 96, keep their timing unchanged, and report the note count."
- "Create a MIDI cleanup script for selected takes: remove muted notes, delete notes shorter than 1/128, and sort the events afterward."

### Lua Scripting

- "Write a Lua script that exports selected item metadata to the clipboard: track name, item name, GUID, start time, length, peak level, and LUFS if available."
- "Write a script that saves the current selected items by GUID so I can restore that same selection later after editing the project."
- "Write a script that lists the selected FX in the focused FX-chain window and copies their names and indexes to the clipboard."
- "Write a script that creates a mix prep report from selected tracks: color, folder depth, sends, receives, FX chain, mute/solo state, and SWS track notes."

Review scripts before running, especially scripts that write files or make broad project changes. For routing, pitch, batch edit, or cleanup scripts, save the project or make a backup first.

### JSFX

- "Create a JSFX stereo utility with width, balance, mono, mid/side solo, mono-safe bass below 120 Hz, and output trim."
- "Create a JSFX gain trim with input/output meters, phase invert, clip indicator, and a simple output ceiling."
- "Make a tempo-synced tremolo JSFX with selectable wave shape, stereo phase offset, smoothing, depth, and output level."

Ask explicitly for JSFX when you want custom DSP code.

Less effective prompts are vague or leave out the target, such as "fix my mix," "make this better," or "change the song key." Reword those with the exact tracks/items, the action, and what should happen afterward.

## Session Awareness

When session awareness is enabled, ReaAssist can include REAPER project metadata in requests so answers and scripts are grounded in the current session.

Depending on the request and settings, context may include:

- Track names, numbers, colors, folders, mute/solo/arm state, and selection.
- Items, takes, selected items, time selection, and edit cursor.
- FX chains and plugin names.
- Routing and sends.
- Tempo, markers, regions, and project-level state.
- Preferred-plugin mappings and cached plugin parameter data.

The assistant only knows what ReaAssist sends in text form. It does not hear, understand, or judge audio content, and it does not open or upload your .RPP project file. Generated scripts can still use REAPER and supported extensions to read project metadata or run measurements such as peak, RMS, and LUFS on selected items.

## Providers & Models

ReaAssist supports Claude, ChatGPT, Gemini, DeepSeek, and custom OpenAI-compatible endpoints, including local servers such as LM Studio, Ollama, llama.cpp, vLLM, and similar tools.

Current recommendations:

- Claude: Sonnet 4.6, no thinking. All-around safe default. Pick Opus 4.8, no thinking, for highest quality at higher cost.
- ChatGPT: GPT-5.4, no thinking. Fastest reliable combo.
- Gemini: Flash 3.5, Minimal thinking. Strong default; Flash Lite Low is the cheapest fast option.
- DeepSeek: V4 Flash, Non-Thinking. Cheapest combo in the built-in lineup; very fast, strong cheap pick.

The in-app model picker is the source of truth if this text ever differs from what you see in ReaAssist. Model availability, pricing, and names can change.

For providers with configurable thinking, more is not always better. ReaAssist already gives the model a structured recipe. For most prompts, a strong base model with no extra thinking is better than a smaller model running deeper thinking. If a complex task fails, raise the model tier before raising the thinking level.

You can connect more than one provider and switch per request. Add or remove keys from Settings > API Keys.

## Privacy & Data

ReaAssist does not upload audio files. It does not send .RPP project files. It does not send API keys to the ReaAssist author.

For normal chat requests, ReaAssist sends text to the provider you choose. That text can include:

- Your typed message.
- Conversation history needed for the current chat.
- Optional project/session metadata.
- Files you explicitly attach, such as images, PDFs, or text files.

All normal chat communication goes between your machine and your selected provider or custom model server. For fully offline use, configure a local model server. With a local server, chat data stays on your machine or local network, subject to how that server is configured.

The paths through which data leaves your machine to the ReaAssist project are the in-chat feedback dialog, the Report an Issue form, and automatic diagnostics. Manual feedback and bug reports are sent only after you open them, review a preview of the exact bytes, and explicitly press Send. Basic anonymous diagnostics are enabled by default and can be turned off in Settings.

## Running Code & Safety

When the assistant returns a Lua code block, action buttons appear below it:

- Run Code: execute the code inside REAPER.
- Undo: revert the last action with REAPER's undo system.
- Backup: save a timestamped .rpp-bak project backup.
- Copy: copy code to the clipboard.
- Save: save as a .lua file you can add to the Action List.
- Edit: switch to editable mode before running or saving.

Executed code is wrapped in a REAPER undo block, so normal Undo can revert many actions. You should still keep backups, especially before running code that edits many tracks, items, plugins, files, routing, pitch, or project settings.

Before running generated code, ReaAssist scans for potentially dangerous Lua patterns such as file deletion, shell execution, file writes, loading external code, and debug-library access. If risky code is found, Run is replaced by a Review Before Running confirmation. Auto-run is blocked when safety review is required.

The scanner reduces risk, but it cannot prove generated code is safe. Always skim generated code before running it.

### Structured Track Edits

Simple stock track, folder, stock-FX, parameter, and send requests can use a stricter local/offline executor instead of generated Lua. The supported scope is intentionally narrow: ReaEQ, ReaComp, ReaDelay, ReaVerbate, ReaGate, ReaLimit, track properties, folders, and sends. It does not handle MIDI, JSFX, items, takes, markers, regions, envelopes, third-party plugins, presets, or unsupported parameter names; those continue through the normal Lua workflow.

Structured edits still require Auto-run, still use Auto-backup when enabled, and fail closed when the generated plan does not match the request safely.

## JSFX Creation

JSFX generation is opt-in. Ask explicitly for a custom JSFX effect, such as "write a JSFX stereo widener" or "create a custom delay JSFX and add it to selected tracks."

Generic effect requests do not automatically become JSFX. For example, "add a reverb" or "I need a delay" uses stock, preferred, or resolved plugins unless you explicitly request a custom JSFX.

JSFX actions can include Copy JSFX, Save, Add To Selected Track(s), and a companion Lua install script when needed. Generated JSFX files are saved under REAPER's Effects/ReaAssist/ folder with unique names. ReaAssist avoids overwriting existing files.

If a new JSFX does not appear in the FX Browser immediately, rescan REAPER's effects or restart REAPER.

## Preferred Plugins & FX Cache

Preferred Plugins let you choose which plugin ReaAssist should use for generic effect types such as EQ, compressor, reverb, delay, limiter, pitch correction, or synth.

After setup, a request like "add an EQ to the vocal" can use your chosen EQ instead of asking every time. If no preference exists, ReaAssist can show a plugin resolve prompt or use a stock fallback when available.

When you save a preferred plugin, ReaAssist scans parameter information for uncached plugins so future parameter changes can be more precise. The FX Parameter Cache stores scanned plugin data so repeated plugin work is faster and more reliable.

Use Rescan after a plugin update. Use Deep scan only when a normal scan returns unclear values, which can happen with some VST3 plugins. Preferred-plugin mappings and cached parameter data live together in Data/FX_Cache.json.

## File Attachments

Use the + button below the prompt to attach files.

Attachment options include:

- Attach File: choose an image, PDF, or text file.
- Screenshot: capture the REAPER window as an image attachment.
- Paste Image: attach an image from the clipboard.
- Drag and drop: drop files onto the ReaAssist window.

Supported formats include PNG, JPG, GIF, WebP, PDF, and text files. ReaAssist supports up to 10 attachments per message.

Attached files are sent to the selected provider or custom model server as part of the request. Use attachments for screenshots of errors, plugin windows, routing diagrams, notes, or PDFs you want summarized or interpreted.

## Feedback & Bug Reports

ReaAssist offers manual feedback through the thumbs-up/thumbs-down dialog below assistant replies and the Feedback / Report an Issue form on the Help page. Both are opt-in. Nothing is sent until you press Send, and both show a preview of the exact bytes first.

Feedback reports can include the current chat session, your rating, tags, comment, app version, REAPER version, OS, provider, model, and a diagnostic report with installed extensions, preferences, plugin cache status, recent errors, and recent token/cache/cost details.

Bug reports can include your issue description, optional name/email, the same diagnostic report, and either the redacted Advanced Log or the current chat session as a fallback.

Automatic diagnostics are managed in Settings > Advanced. Basic anonymous diagnostics are enabled by default and send structured metrics only, such as versions, OS, provider class, model tier, token/cache/cost totals, latency, retry counters, and error counts. Extended is off unless you enable it and includes Basic plus redacted chat, diagnostic report, Advanced Log/report detail, and recent error detail.

Before sending, ReaAssist redacts API keys, Authorization headers, Bearer tokens, URL query secrets, home-directory paths, install paths in diagnostic reports, and custom-provider endpoint URLs from Advanced Log bug reports.

Name and Email are sent as-is if you fill them in so the maintainer can reply. Project names, track names, plugin names, file names, or other text you typed may still appear in chat or logs. Always review the preview before sending if you are worried about sensitive text.

Reports go to the ReaAssist project maintainer through https://d.reaassist.app. Failed manual sends keep the form/dialog open with a Try Again button. Automatic diagnostics use a next-launch pending queue so they are sent only when ReaAssist is idle and only up to the current tier you have enabled.

## Options & Appearance

Main-screen options:

- Auto-run code: automatically execute eligible returned code. Use carefully.
- Auto-backup: save a project backup before running code.
- Show details: show model name, token counts, prompt-cache hits, estimated cost, and session total.

Settings includes API Keys, provider/model selection, custom provider configuration, theme selection, UI scale, and Advanced options for session snapshots, API reference, diagnostics, cloud timeout, Preferred Plugins, update checks, FX Param Cache, Reset Window Size, and Factory Reset.

Themes include Auto, Dark, and Light. Auto follows the operating system's light/dark appearance when supported.

UI Scale options are 75%, 85%, 100%, 125%, 150%, and 200%. When changing scale, ReaAssist shows a confirmation popup with a 10-second countdown so the UI cannot get stuck at an unusable size.

If the UI becomes unreachable, hold Shift while launching ReaAssist. Shift-launch recovery resets scale to 100%, theme to Auto, and saved window geometry. Shift-launch recovery requires js_ReaScriptAPI.

## Updates & Repair

ReaAssist can check for updates and repair missing or mismatched installed files. The update system checks installed files against the official release file list, downloads missing or outdated files, cleans up removed files, and relaunches ReaAssist after update or repair when needed.

ReaAssist also checks required extensions such as ReaImGui and SWS Extension during startup. If a required extension is missing or too old, ReaAssist can install or update the pinned version from the upstream release. After extension installs or updates, restart REAPER so the newly installed binaries load.

If repair fails because a file is locked or unavailable, close REAPER, reopen it, and try again. If the problem persists, reinstall ReaAssist through ReaPack.

## Keyboard Shortcuts

- Enter: send message.
- Shift+Enter: insert a new line in the prompt.
- Escape: close popups, Help, Settings, and other overlay screens. On the main chat screen, Escape opens quit confirmation.
- Ctrl+C: copy selected chat text.
- Right-click chat text: copy selection, copy all, or copy table.

## Troubleshooting

- Code buttons do not appear: make sure ReaImGui is installed and up to date. ReaAssist auto-installs required extensions on first launch when missing. If you uninstalled one manually, relaunch ReaAssist and accept the install prompt, or update via ReaPack.
- ReaAssist will not launch: check that REAPER is version 7.0 or later, ReaImGui and SWS Extension are installed, Resources/ is directly beside ReaAssist.lua, and the install was not partially copied or interrupted.
- API key errors: verify the key, selected provider, billing/account access, and chosen model.
- Local model server errors: verify the server is running, the base URL is correct, the API is OpenAI-compatible, the model name exists, and firewall settings are not blocking localhost.
- Gemini free tier limits: the free tier may reject large requests or hit lower rate limits. Enable billing on the Google account for full access, or use a smaller request/model when appropriate.
- Screenshots do not work: accurate window capture requires js_ReaScriptAPI. ReaAssist auto-installs it on supported platforms. Platforms without an upstream binary use a non-native capture fallback.
- JSFX does not appear in the FX Browser: restart REAPER, rescan effects, and check REAPER's Effects/ReaAssist/ folder.
- UI is too large or off-screen: hold Shift while launching ReaAssist to reset UI scale, theme, and saved window geometry.
- Plugin parameters are wrong: rescan the plugin in FX Param Cache, use Deep scan for plugins that report delayed values, reword the request with exact parameter names, or choose a stronger model.
- Generated code did the wrong thing: use Undo if possible, then tell ReaAssist exactly what happened and what should have happened.

## Requirements

- REAPER 7.0 or later.
- ReaImGui extension, required. ReaAssist auto-installs the pinned version on first launch if missing.
- SWS Extension, required. ReaAssist auto-installs the pinned version on first launch if missing or too old.
- curl, required. Built into current Windows, macOS, and Linux systems.
- API key for at least one provider, or a configured local/custom model server.
- js_ReaScriptAPI, optional. ReaAssist auto-installs the pinned version on supported platforms. It enables native file dialogs and more accurate window screenshots. Platforms without an upstream binary use non-native fallbacks.

## Limitations

- ReaAssist cannot hear, understand, or judge audio content. It can run supported REAPER/SWS measurements such as peak, RMS, and LUFS on selected items when a script uses those APIs.
- It does not upload audio files.
- It does not inspect .RPP project files as project documents.
- Generated code can be wrong.
- Plugin parameter names and values can vary by plugin version and format.
- Smaller local models may be less reliable than stronger cloud models for complex scripting.
- Safety scanning reduces risk but cannot prove code is safe.
- Cost estimates are approximate.

Use backups and review generated code before running it.

## Disclaimer and Terms of Use

ReaAssist is provided as-is. Review generated code before running it. Keep project backups. Follow your provider's terms, pricing, and usage policies.

You are responsible for deciding whether generated scripts, plugin changes, routing changes, or project edits are appropriate for your session.
