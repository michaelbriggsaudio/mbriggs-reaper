# ReaAssist Help

## Overview

ReaAssist is a technical and workflow assistant for REAPER. Type requests in plain English and get explanations or executable Lua code that runs inside your session.

When enabled, ReaAssist can read project state such as tracks, FX chains, tempo, items, and selections so it can give context-aware answers and write more accurate scripts.

ReaAssist does not generate, process, or alter your audio files. It is strictly a scripting and workflow tool. You maintain full creative control over your sound.

## Privacy & Data

Your audio files are never uploaded or sent anywhere. ReaAssist sends text to the provider you choose: your typed messages, optional project metadata (track names, FX lists, tempo, etc.), and any files you explicitly attach (images, PDFs). All chat communication goes directly between your machine and your chosen provider's API. For fully offline use, custom local LLMs (LM Studio, Ollama, etc.) are supported and keep all chat data on your machine.

ReaAssist itself does not send anything automatically. The only paths through which data leaves your machine to the ReaAssist project are the in-chat feedback dialog and the Report an Issue form on the Help page, and only after you open them, review a preview of the exact bytes, and explicitly press Send.

## Sending Feedback

Below every assistant reply, ReaAssist shows small thumbs-up and thumbs-down feedback buttons. Clicking either button opens a preview-and-send dialog with that choice preselected. The buttons themselves send nothing; they only open the dialog.

Inside the dialog you can:

- Pick or change a thumbs-up or thumbs-down rating for the assistant's reply
- If thumbs-down, optionally tag what went wrong: wrong result, wrong plugin, didn't follow request, or too slow
- Add a free-text comment (optional)
- Expand **Preview feedback** to inspect the exact JSON bytes that would be sent
- Expand **Details & privacy** for the full disclosure of what's included, redacted, and excluded
- Press **Send** to upload, or **Cancel** to discard

**What is sent (only when you press Send):**

- The current chat session (all turns visible in the chat)
- Your typed comment and any tags you ticked
- Basic context: app version, REAPER version, OS, provider, model
- A **Diagnostic Report** with app/REAPER/OS/ImGui versions, installed extensions, preferences, plugin cache status, recent errors, and recent token/cache/cost metrics

**Automatically redacted before sending:**

- API keys
- `Authorization:` headers and `Bearer` tokens
- Home-directory paths (e.g. `C:\Users\<user>`), including log-file paths in the Diagnostic Report

**What may still appear in the chat content** (always review the preview before clicking Send):

- Project, track, plugin, or other names you typed or that the assistant mentioned
- Any other text you pasted into the chat

**What is never sent:**

- Audio files
- REAPER project files (`.RPP`)
- Your API keys

**On send:**

- **Successful sends:** the dialog confirms with a brief message and closes.
- **Failed sends:** the dialog stays open with the error and a **Try Again** button. ReaAssist does not queue, retry, or save any feedback file in the background. If you cancel after a failure, the data is discarded.

**Where it goes:**

- Sent to the ReaAssist project maintainer via `https://d.reaassist.app`.
- A random installation ID is generated **only on your first successful send** so duplicate reports from the same install can be deduplicated. This ID is not linked to your identity.

## Reporting a Bug

For issues that need more than a thumbs-down (something crashed, the wrong code ran, a feature isn't working as expected), open **Feedback / Report an Issue** from the Help page. The page hosts a form that collects everything the maintainer needs to investigate in one place.

Inside the form you can:

- Describe what happened, what you expected, and what actually happened (required)
- Add an optional **Name** and **Email** if you'd like a reply (otherwise leave blank)
- Expand **Preview report** to inspect the exact JSON bytes that would be sent (right-click the preview to copy)
- Expand **Details & privacy** for the full disclosure of what's included, redacted, and excluded
- Press **Send** to upload

**What is sent (only when you press Send):**

- Your description and any contact info you provided
- The same Diagnostic Report as the in-chat dialog (app/REAPER/OS, installed extensions, recent errors, metrics)
- One of the following, depending on the **Enable Advanced Log** toggle below the form:
  - **If the log is enabled** (the default): the entire Advanced Log file, redacted before sending. The log captures full API request/response traffic, FX scan events, and exchange summaries — the most useful evidence for debugging.
  - **If the log is disabled or empty:** the current chat session as a fallback, so reports are still useful when the log isn't available.

**Automatically redacted before sending:**

- API keys (yours and any pasted into chat)
- `Authorization:` headers and `Bearer` tokens
- Home-directory paths
- `?key=` / `?token=` style URL query secrets
- Custom-provider endpoint URLs (so LAN IPs and self-hosted hostnames stay private)

**What is *not* redacted** (so the maintainer can read the report and reply):

- Your **Name** and **Email**, if you typed them — sent as-is
- Project, track, plugin, or file names that appear in the chat or the log
- Anything else you pasted into the chat

**What is never sent:**

- Audio files
- REAPER project files (`.RPP`)
- Your API keys

The **Preview report** expander shows the exact redacted bytes that will be POSTed. Always skim it before sending if you're worried about anything sensitive in your chat or log.

**Contact info is remembered.** If you fill in Name and Email, they're saved locally so the next visit pre-fills them. They're never sent unless you press Send. Clear them by emptying the fields and sending another report (or by Factory Reset).

**Where it goes:** same as in-chat feedback — the ReaAssist project maintainer via `https://d.reaassist.app`. Failed sends keep the form filled with a **Try Again** button; nothing is queued in the background.

## What It Can Do

- **Session Awareness**: read tracks, FX, routing, tempo, items, and selections for context-aware responses
- **Lua Scripting**: automate tasks, batch-process tracks, rename items, manage routing, and more
- **JSFX Creation**: generate custom JSFX effects and install them to your tracks from a single prompt
- **Mixing & Effects**: add and configure plugins, adjust levels and panning, set up sends, build FX chains
- **Editing**: items, splits, nudges, crossfades, time selection, markers, and regions
- **Project Management**: create tracks, set colors, manage folders, configure I/O
- **General Questions**: shortcuts, features, best practices, and workflow tips

## Getting Started

1. On first launch, review and accept the Terms of Use.
2. Get an API key from at least one provider (Claude, ChatGPT, Gemini, or a custom/local LLM).
3. Enter your key on the intro screen, or open **Settings** later to add more.
4. Select your provider and model from the dropdowns at the bottom.
5. Type a message and press Send or Enter. Use **Shift+Enter** to add a new line without sending.

## Example Prompts

- "Add a reverb to every selected track"
- "Set the tempo to 120 BPM"
- "What FX are on track 3?"
- "Write a script that fades in the first item on each track"
- "Rename all tracks by their first item name"
- "How do I set up a sidechain compressor?"
- "Create a JSFX stereo widener and add it to track 1"

## Providers & Models

ReaAssist supports Claude, ChatGPT, Gemini, and custom OpenAI-compatible endpoints, including local servers such as LM Studio, Ollama, llama.cpp, and vLLM.

Each provider has fast, balanced, and smart model tiers. Start with a balanced model for normal work, use a smart/full model for complex scripts or multi-plugin tasks, and use fast/mini models for quick questions or simple edits.

For providers with configurable thinking, more is not always better. ReaAssist gives the model a structured recipe; strong models usually follow it best at low or minimal thinking. If a complex task fails, raise the model tier before raising the thinking level.

### Quick model guide

| Provider | Recommended pick | Best for |
|---|---|---|
| Anthropic (Claude) | Sonnet 4.6, no thinking | All-around safe default. Pick Opus 4.7 (no thinking) for highest quality at higher cost. |
| OpenAI (ChatGPT) | GPT-5.4, no thinking | Fastest reliable combo |
| Google (Gemini) | Flash 3, Minimal thinking | Cheapest fast option |

The model and thinking dropdowns mark each provider's recommended row with a `*` on the left. Hover any row to see what that combination is best for; the same explainer briefly appears as a muted line below the chips after you change the selection.

You can connect more than one provider and switch per request from the provider picker above the chat input. Add or remove keys from **Settings > API Keys**. Model choices are remembered per provider.

## Code Execution

When the assistant returns a Lua code block, buttons appear beneath it:

- **Run Code**: execute the code inside REAPER immediately.
- **Undo**: revert the last action (Ctrl+Z).
- **Backup**: save a timestamped backup of your project (.rpp-bak).
- **Copy**: copy code to clipboard.
- **Save**: save as a .lua file you can add to the Actions menu.
- **Edit**: switch to editable mode for manual tweaks before running.

All executed code is wrapped in an undo block, so Ctrl+Z can revert changes.

## JSFX Creation

JSFX generation is **opt-in**. Ask explicitly ("write me a JSFX stereo widener", "make a custom delay plugin") and the assistant produces the code. Generic effect requests ("add a reverb", "I need a delay") always use stock or preferred plugins; they never improvise a JSFX.

- Responses come with Copy and Save buttons. If you specify a track, a companion Lua script installs the JSFX on that track automatically.
- **Add To Selected Track(s)**: saves the JSFX and adds it to all selected tracks in one click.
- With Auto-run enabled, JSFX are saved and installed without prompting.
- Files land in `Effects/ReaAssist/` with unique names (no overwrites). They appear in your FX Browser after REAPER rescans, or on the next restart.

## File Attachments

Attach files to your messages for the assistant to analyze. Click the **+** button below the prompt to open the attachment menu:

- **Attach File**: open a file picker for images, PDFs, or text files.
- **Screenshot**: capture the REAPER window as an image attachment.
- **Paste Image**: attach an image from your clipboard.
- **Drag & Drop**: you can also drop files anywhere on the window.

Supported formats: PNG, JPG, GIF, WebP, PDF, and text files. Max 10 attachments per message.

## Safety Scanner

Before running code, ReaAssist scans for potentially dangerous calls: file deletion/renaming (`os.remove`, `os.rename`), shell execution (`os.execute`, `io.popen`), writing to files (`io.open` in write/append mode), loading external code (`require`, `dofile`, `loadfile`, `loadstring`, `load`), and debug-library access.

When any of these are detected, the Run button is replaced by a **Review Before Running** confirmation modal that lists what was found. You must explicitly accept it before the code will execute. Auto-run is blocked too. This is a hard gate, not a label; always read the warning and skim the code before accepting.

## Theme & Appearance

ReaAssist includes Dark and Light themes plus an Auto mode that follows your operating system's appearance setting. Change the theme from the **Theme** dropdown on the Settings page.

- **Auto** (default): detects your OS dark/light mode preference and applies the matching theme automatically. Supported on Windows, macOS, and Linux (GNOME/GTK).
- **Dark**: dark background with light text, easy on the eyes in dim environments.
- **Light**: light background with dark text, ideal for bright environments.

The theme is applied immediately as a live preview. Changes are saved when you click **Save & Return**.

## UI Scale

Adjust the interface size from the **UI Scale** dropdown on the Settings page. Available options: 75%, 85%, 100%, 125%, 150%, and 200%.

- When you change the scale, a **confirmation popup** appears with a 10-second countdown. Click **Keep Scale** (or press Enter) to confirm. Click **Revert Now** (or press Escape) to undo. If you don't respond, the scale automatically reverts after 10 seconds. This prevents getting stuck at an unusable size.
- The window size is **clamped to your monitor's work area**, so choosing a large scale on a small screen will not push the window off-screen. This works correctly on multi-monitor setups.
- **Reset Window Size** on the Settings page restores the default window size and clears any saved position.
- **Shift-Launch recovery**: if the UI becomes unreachable due to a bad scale setting, hold **Shift** while launching ReaAssist to reset the scale to 100%, theme to Auto, and clear saved window geometry. Requires js_ReaScriptAPI.

ReaAssist remembers your window position and size between sessions. Moving or resizing the window is automatically saved.

## Options

These checkboxes are available on the main screen:

- **Auto-run code**: automatically execute returned code without clicking Run. Use with caution.
- **Auto-backup**: automatically save a project backup before running code.
- **Show details**: display model name, token counts, prompt-cache hits, and estimated cost per exchange plus a running session total.

Additional options are available on the **Settings** page:

- **Send session snapshot**: attach a live project snapshot with every message (tracks, FX, tempo, markers, selections, cursor position).
- **Always include REAPER API reference**: pin the REAPER Lua API reference to every request. Off by default; the assistant fetches docs on-demand when it needs them, which saves about 10K tokens per turn on non-code questions. Turn on if you do mostly code-generation work and want no docs-fetch round trips.
- **Check for updates**: automatically check for new versions on startup.
- **Preferred Plugins**: set default plugins for each generic type, e.g. "EQ" → your favorite EQ plugin (see below).
- **FX Param Cache**: view and manage cached plugin parameter data (see below).
- **Reset Window Size**: restore the default window size and clear saved position.
- **Factory Reset**: clear all keys, preferences, settings, theme, scale, and window geometry to start fresh.

## Preferred Plugins

Set default plugins for generic types (EQ, compressor, reverb, etc.) so the assistant uses your pick automatically when you say "add an EQ." Access from the **Settings** page.

- **Autocomplete**: start typing a plugin name and matches appear. Arrow keys highlight, Enter or click selects. **Tab** / **Shift+Tab** move between the Type and Plugin name fields. Add comma-separated aliases in the type field (e.g. "EQ, equalizer, tone").
- **Format dedup**: VST2 entries are hidden when a same-named VST3 is also installed (same for VSTi / VST3i). AU and CLAP builds are shown so you can pick a specific format.
- **Save** commits your mappings and scans any plugins that aren't already cached. Already-cached plugins are skipped, so Save is cheap to run repeatedly. Scanning is what lets the assistant set specific parameters on your third-party plugins by name rather than guessing.
- **Rescan All** / **Rescan** (per row): force a fresh parameter scan, e.g. after a plugin update.
- **Clear All** wipes every preferred-plugin mapping (confirmation popup). Cached parameter data is kept, so re-picking the same plugin later doesn't force a rescan.
- Leave a row blank for types you don't need; the assistant raises a resolve popup or falls back to a stock REAPER plugin when appropriate.
- Preferences and cached parameter data live together in `FX_Cache.json` in the script folder. Back that file up to preserve your setup.

## FX Parameter Cache

Whenever a plugin's parameters are scanned (through Preferred Plugins, the resolve popup, or an on-demand `fx_inspect`), the results are cached so future requests are instant. Open the cache page from the **FX Param Cache** button on the Settings page.

- The top row shows how many plugins are cached and a **Clear All** button (with confirmation) that removes every entry. Preferred-plugin mappings are not affected.
- Each plugin row has three actions:
  - **Rescan**: re-scan this plugin's parameters quickly (one frame). Use after a plugin update.
  - **Deep**: defer-paced scan with a per-probe delay. Use only when a normal Rescan returns garbage values, typically VST3 plugins that report parameters one frame late (e.g. Soundtoys). Shows live progress and can be cancelled.
  - **Remove**: drop this entry from the cache. It will be re-scanned the next time it's needed.
- A `needs deep scan` label (in amber) next to a plugin's param count means the normal scan couldn't read clean values; click Deep to finish it.
- The cache is unified with your preferred-plugin mappings in `FX_Cache.json`, so "Clear All" here only wipes parameter data, not your type → plugin choices.

## Plugin Resolve Prompts

When a request needs a plugin of a generic type (e.g. "add a compressor") and you haven't set a preferred plugin for that type, a popup titled **"Choose a plugin to use..."** appears. Pick once and it's saved to Preferred Plugins so the popup doesn't come back for that type.

- **Type a plugin name**: autocomplete shows matches as you type; arrow keys highlight, Enter or click selects. **Use this** confirms.
- **Install ReEQ Instantly (Free)** (EQ only): one-click install of ReaAssist's bundled JSFX EQ (by Justin Johnson, MIT licensed). Better filter slopes than ReaEQ; recommended if you don't own a third-party EQ.
- **Use [stock plugin] instead**: if REAPER ships a stock plugin or JSFX that fits the type, this proceeds immediately and saves it as your preference. See the table below for each type's fallback.
- **Cancel**: appears only when there's no stock fallback (currently "custom"); aborts the turn.

### Stock Fallbacks

| Request type | Stock fallback | Saved as preferred on use? |
|---|---|---|
| EQ | ReaEQ | No: always re-prompts toward ReEQ or a third-party choice |
| Compressor | ReaComp | Yes |
| Multiband Compressor | ReaXcomp | Yes |
| Gate | ReaGate | Yes |
| Delay | ReaDelay | Yes |
| Limiter | ReaLimit | Yes |
| Pitch Shift | ReaPitch | Yes |
| Pitch Correction | ReaTune | Yes |
| Reverb | ReaVerbate | Yes |
| Synth | ReaSynth | Yes |
| De-esser | JSFX Liteon/deesser | Yes |
| Saturation | JSFX LOSER/Saturation | Yes |
| Chorus | JSFX SStillwell/chorus_stereo | Yes |
| Phaser | JSFX Guitar/phaser | Yes |
| Custom | n/a | Cancel only |

All fallback plugins ship with a stock REAPER install. The JSFX entries use the source files found in REAPER's `Effects/` folder.

## On-Demand Context

The assistant can request extra context mid-conversation when needed, even if **Send session snapshot** is off. This happens automatically.

Available context includes project snapshots, REAPER API docs, MIDI reference notes, curated plugin guidance, preferred-plugin settings, FX search results, FX chain listings, and live parameter scans for installed plugins.

## Prompt Caching & Cost

All three providers cache repeated prompt content between turns, which can cut per-turn costs by 5-10× on ongoing conversations. With **Show details** on, each exchange shows token counts, cache hits, and estimated USD cost; a session total appears below the options. Cost estimates are approximations only.

## Keyboard Shortcuts

- **Enter**: send message
- **Shift+Enter**: insert a new line in the prompt
- **Escape**: close popups, help screen, and settings pages. On the main chat screen, Escape opens a quit confirmation dialog.
- **Ctrl+C**: copy selected text from chat
- **Right-click** on chat text: copy selection, copy all, or copy table

## Button Reference

- **+**: attach files, screenshots, or clipboard images.
- **Settings**: manage API keys, models, preferred plugins, cache, theme, and scale.
- **Clear Chat**: reset the current conversation.
- **Copy Chat**: copy the full chat to clipboard.
- **Run Code / Undo / Backup / Copy / Save / Edit**: actions shown below generated code.

## Troubleshooting

- **Code doesn't run or buttons don't appear**: make sure ReaImGui is installed and up to date. ReaAssist auto-installs ReaImGui on first launch when missing; if you uninstalled it manually, relaunch ReaAssist and accept the install prompt, or update via ReaPack (Extensions > ReaPack > Browse Packages).
- **API errors or "invalid key"**: double-check your key on the Settings page. Verify your billing status with your provider.
- **Gemini free tier limits**: the free tier has lower rate limits and may reject large requests. Enable billing on your Google Cloud account for full access.
- **Screenshots not working**: accurate window capture requires js_ReaScriptAPI. ReaAssist auto-installs it on first launch on Windows, macOS, and Linux x86_64; if it was skipped or you uninstalled it, install via ReaPack (Extensions > ReaPack > Browse Packages). Platforms without an upstream binary fall back to non-native capture.
- **JSFX not showing in FX Browser**: REAPER needs to rescan. Go to Options > Preferences > Plug-ins > VST and click Re-scan, or restart REAPER.
- **UI is too large or off-screen**: hold Shift while launching ReaAssist to reset the scale to 100%, theme to Auto, and clear saved window position.

## Requirements

- **ReaImGui** - required (auto-installed by ReaAssist on first launch; can also be installed via ReaPack)
- **API key** for at least one provider - required
- **curl** (built into Windows 10+, macOS, and Linux) - required
- **js_ReaScriptAPI** - auto-installed by ReaAssist on first launch on Windows, macOS, and Linux x86_64; enables native file dialogs and accurate window screenshots. ReaAssist runs without it on platforms with no upstream binary, using non-native fallbacks.

## Disclaimer and Terms of Use

ReaAssist is provided as-is. Review generated code before running it, keep project backups, and follow your provider's terms and pricing. Cost estimates are approximations only.
