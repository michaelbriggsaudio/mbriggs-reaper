# ReaAssist Help

## Overview

ReaAssist is a technical and workflow assistant for REAPER. Type requests in plain English and get responses with explanations or executable Lua code that runs directly inside your session. ReaAssist can read your project state (tracks, FX chains, tempo, items, selections) to give context-aware advice and write accurate scripts.

ReaAssist does not generate, process, or alter your audio files. It is strictly a scripting and workflow tool. You maintain full creative control over your sound.

## Privacy & Data

Your audio files are never uploaded or sent anywhere. ReaAssist only sends text to the provider you choose: your typed messages, optional project metadata (track names, FX lists, tempo, etc.), and any files you explicitly attach (images, PDFs). No data is collected by ReaAssist itself. All communication goes directly between your machine and your chosen provider's API. For full data privacy, custom local LLMs (LM Studio, Ollama, etc.) are supported for completely offline use with no data leaving your machine.

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

ReaAssist supports three cloud providers plus custom/local LLMs:

- **Claude** (Anthropic)
- **ChatGPT** (OpenAI)
- **Gemini** (Google)
- **Custom LLM**: connect local servers (LM Studio, Ollama, llama.cpp, vLLM) or cloud services (OpenRouter) via OpenAI-compatible endpoints. Configure from the Settings page.

Each provider offers fast, balanced, and smart model tiers. Use fast for quick questions, smart for complex multi-step tasks.

## Choosing a Model

ReaAssist works with all three providers (and custom LLMs), but **not all models follow the script's plugin-configuration rules equally well**. The assistant gets a structured prompt with multi-step decision rules for picking the right parameter-setting strategy; larger models follow these reliably, while smaller "mini" / "flash" / "nano" variants sometimes shortcut them on complex multi-plugin requests.

Pick a model from the dropdown next to each provider chip. Your choice is remembered per-provider. As a rule of thumb: start with the provider's **balanced mid-tier** model for most work, step up to the smart tier for complex multi-plugin configuration, and use the fast tier only for quick chat or simple single-action prompts.

### Reliability tiers (from direct testing)

Tested on complex multi-plugin rock-vocal stress prompts and on simpler requests.

- **S-tier (handles anything)**: Claude Sonnet 4.6, Claude Opus 4.6, GPT-5.4 full, Gemini Pro 3.1, Gemini Flash 3.
  - **Sonnet 4.6**: most thoroughly tested. Consistent rule-following across single-track edits, multi-plugin chains, MIDI / theme work, and complex third-party plugins.
  - **GPT-5.4 full**: comparable. Slightly more likely to shortcut a nuanced rule on edge cases but code works.
  - **Gemini Pro 3.1**: comparable. Occasionally picks a suboptimal parameter-setting strategy but code works.
  - **Gemini Flash 3** (!): punches well above its "Flash" name. Matched Pro 3.1 on the same stress test and was **~12× cheaper**. Best price-per-success in the whole table.
- **C-tier (simple chat only)**: Claude Haiku 4.5, GPT-5.4 mini, Gemini Flash Lite 3.1, GPT-5.4 nano. Fine for chat, explanations, and simple "add track" / "set tempo" requests. They struggle on multi-plugin configuration, re-request already-provided data, or skip decision rules. Don't use them for "recommended settings" prompts.
- **Custom / local LLMs**: highly variable. Larger instruct-tuned models (Llama 70B+, Qwen 32B+, Mistral Large) generally work; smaller ones often produce malformed code.

### Thinking level: less is usually more

For providers with configurable thinking (ChatGPT, Gemini), the intuition that "more thinking = better results" is usually wrong here. ReaAssist's prompt is a structured recipe with explicit rules; strong models follow it best at Low or None. Higher thinking gives the model room to second-guess the rules and talk itself into edge cases.

Direct test data on a complex multi-plugin rock-vocal request:

| Model | Thinking | Outcome | API response | Cost |
|---|---|---|---|---|
| GPT-5.4 mini | Medium | Failed (wrong strategy) | n/a | $0.0949 |
| GPT-5.4 full | Medium | **Timed out** (>180s) | n/a | n/a |
| GPT-5.4 full | Low | Worked | 53.9s | $0.0580 |
| GPT-5.4 full | **None** | Worked | 16.4s | $0.0541 |
| Gemini Flash 3 | Medium | Worked | 20.2s | **$0.0126** |
| Gemini Pro 3.1 | Low | Worked | 27.3s | $0.0604 |

**Practical takeaway**: start with Thinking: Low on top-tier models (None on GPT-5 full). When a complex request fails, **bump the model tier before bumping thinking**: switch from "mini at Medium" to "full at Low" rather than "mini at High".

### Cost considerations

- **Anthropic** (Claude): pay-as-you-go, cheapest cards-only setup. $5 starter credit for new accounts.
- **OpenAI** (ChatGPT): pay-as-you-go from cent one. No free tier for the API.
- **Google** (Gemini): generous free tier with daily quotas. Easiest free signup. Pro 3.1 requires a paid key; Flash Lite + Flash 3 work on free.

**Gemini Flash 3** is the single strongest cost-vs-capability choice (empirically S-tier, cheap enough to be C-tier priced), and works on the free tier.

### Switching providers

You can connect more than one provider simultaneously and switch between them per-request via the provider picker above the chat input. Add or remove keys at any time from Settings > API Keys. Each provider has its own remembered model pick.

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
- **Always include REAPER API reference**: pin the REAPER Lua API reference to every request. Off by default; the assistant fetches docs on-demand when it needs them, which saves ~10K tokens per turn on non-code questions. Turn on if you do mostly code-generation work and want zero docs-fetch round trips.
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
- Preferences and cached parameter data live together in `ReaAssist_FX_Cache.json` in the script folder. Back that file up to preserve your setup.

## FX Parameter Cache

Whenever a plugin's parameters are scanned (through Preferred Plugins, the resolve popup, or an on-demand `fx_inspect`), the results are cached so future requests are instant. Open the cache page from the **FX Param Cache** button on the Settings page.

- The top row shows how many plugins are cached and a **Clear All** button (with confirmation) that removes every entry. Preferred-plugin mappings are not affected.
- Each plugin row has three actions:
  - **Rescan**: re-scan this plugin's parameters quickly (one frame). Use after a plugin update.
  - **Deep**: defer-paced scan with a per-probe delay. Use only when a normal Rescan returns garbage values, typically VST3 plugins that report parameters one frame late (e.g. Soundtoys). Shows live progress and can be cancelled.
  - **Remove**: drop this entry from the cache. It will be re-scanned the next time it's needed.
- A `needs deep scan` label (in amber) next to a plugin's param count means the normal scan couldn't read clean values; click Deep to finish it.
- The cache is unified with your preferred-plugin mappings in `ReaAssist_FX_Cache.json`, so "Clear All" here only wipes parameter data, not your type → plugin choices.

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

The assistant can request project data mid-conversation when needed, even with Send snapshot off. You don't need to do anything; this happens automatically. Available data:

- **Session**: tracks, selections, cursor, items, tempo, markers, regions
- **Docs**: REAPER Lua API function signatures
- **Curated plugin data**: verified parameter recipes for REAPER stock (ReaEQ, ReaComp, ReaXcomp, ReaGate, ReaDelay, ReaLimit, ReaPitch, ReaTune, ReaVerbate, ReaSynth), bundled / stock JSFX fallbacks (ReEQ, De-esser, Saturation, Chorus, Phaser), and selected third-party (FabFilter Pro-Q 4, Pro-C 3, Pro-L 2, Pro-MB, Pro-R 2, Pro-DS, Pro-G; Saturn 2; Timeless 3). Anything not in this list is handled by live parameter scanning instead
- **FX parameters**: live parameter values for any plugin on a track
- **FX search**: search your installed plugins by name
- **FX chains**: full FX chain listing for all tracks
- **Track flags**: mute, solo, and record-arm state for all tracks
- **MIDI reference**: note/CC helpers, PPQ, and MIDI workflow patterns
- **Preferred plugins**: your configured plugin choices and cached parameters

## Prompt Caching & Cost

All three providers cache repeated prompt content between turns, which can cut per-turn costs by 5-10× on ongoing conversations. With **Show details** on, each exchange shows token counts, cache hits, and estimated USD cost; a session total appears below the options. Cost estimates are approximations only.

## Keyboard Shortcuts

- **Enter**: send message
- **Shift+Enter**: insert a new line in the prompt
- **Escape**: close popups, help screen, and settings pages. On the main chat screen, Escape opens a quit confirmation dialog.
- **Ctrl+C**: copy selected text from chat
- **Right-click** on chat text: copy selection, copy all, or copy table

## Buttons

Main screen:

- **Send**: send your message (or press Enter).
- **+**: attach files, screenshots, or clipboard images.
- **Settings**: manage API keys, preferred plugins, and other options.
- **Help**: open this help page.
- **Clear Chat**: reset the conversation (with confirmation).
- **Copy Chat**: copy the entire conversation to clipboard.
- **Credits**: view credits and acknowledgments.
- **Donate**: support further development.

Code block buttons (appear under generated code):

- **Run Code**: execute the code in REAPER.
- **Undo**: revert the last executed action.
- **Backup**: save a project backup.
- **Copy**: copy the code to clipboard.
- **Save**: save as a standalone .lua script.
- **Edit**: edit the code before running.

Settings page:

- **UI Scale**: choose an interface zoom level (75% to 200%).
- **Theme**: choose Auto, Dark, or Light appearance.
- **Preferred Plugins**: configure default plugins by type (with Save, Rescan All, Clear All, and per-row Rescan).
- **FX Param Cache**: view and manage cached plugin parameter data (Rescan, Deep rescan, Remove, Clear All).
- **Reset Window Size**: restore default window dimensions and clear saved position.
- **Factory Reset**: clear all data and return to the first-run setup.

## Troubleshooting

- **Code doesn't run or buttons don't appear**: make sure ReaImGui is installed and up to date via ReaPack (Extensions > ReaPack > Browse Packages).
- **API errors or "invalid key"**: double-check your key on the Settings page. Verify your billing status with your provider.
- **Gemini free tier limits**: the free tier has lower rate limits and may reject large requests. Enable billing on your Google Cloud account for full access.
- **Screenshots not working**: install js_ReaScriptAPI via ReaPack for accurate window capture.
- **JSFX not showing in FX Browser**: REAPER needs to rescan. Go to Options > Preferences > Plug-ins > VST and click Re-scan, or restart REAPER.
- **UI is too large or off-screen**: hold Shift while launching ReaAssist to reset the scale to 100%, theme to Auto, and clear saved window position.

## Requirements

- **ReaImGui** (install via ReaPack) - required
- **API key** for at least one provider - required
- **curl** (built into Windows 10+, macOS, and Linux) - required
- **js_ReaScriptAPI** (optional) - enables native file dialogs and accurate window screenshots

## Disclaimer and Terms of Use

ReaAssist for REAPER is provided as-is, with no warranty of any kind. Running any code generated by this tool is entirely at your own risk. The script author is not liable for any direct, indirect, incidental, or consequential damages, including data loss or project corruption. Always review generated code before running it and back up your project file first. Use of this tool requires an API key from at least one supported provider and is subject to each provider's Terms of Service. Cost estimates are approximations only.
