# ReaAssist

**The Session-Aware Workflow Assistant for REAPER.**

ReaAssist is a session-aware workflow assistant for REAPER. Describe what you want done in plain English and ReaAssist reads your project state, then generates the Lua script, JSFX plugin, plugin parameter changes, or other automation to do it. Press send and the code runs in REAPER, with built-in safety checks for risky patterns.

**Website:** [reaassist.app](https://reaassist.app)

## What it does

- Reads your project state (tracks, items, FX chains, plugin parameters, transport, time selection, edit cursor, routing) so requests like "compress the vocal" act on the right target.
- Configures plugins by name and parameter, dialing in precise dB / Hz / ms / % values. Includes verified parameter references for REAPER stock plugins (ReaEQ, ReaComp, ReaXcomp, ReaGate, etc.) and many popular third-party plugins (FabFilter Pro-Q 4, Pro-C 3, Pro-L 2, Soundtoys Decapitator, EchoBoy, etc.). Aliases auto-resolved.
- Generates Lua scripts on demand: track and item creation, FX configuration, MIDI editing, marker and region placement, theme changes, and anything else the REAPER ReaScript API supports.
- Writes JSFX (custom DSP code) on explicit request when stock plugins do not cover a specific need. Opt-in only; generic effect requests route through stock or third-party plugin workflows.
- Surfaces and fixes mistakes when you tell it what went wrong.

## What it is not

ReaAssist is a workflow and automation tool, not a generative creative tool. It does not produce audio, music, samples, lyrics, melodies, or any other creative content. It does not make artistic decisions for you. Its job is to translate workflow steps you already know you want into the script code or plugin configuration that performs them, faster than you would write the code yourself.

## Privacy and local models

In addition to cloud providers, ReaAssist supports custom provider endpoints and local models running on your own machine via OpenAI-compatible servers (Ollama, LM Studio, llama.cpp, and similar). Point ReaAssist at a localhost endpoint and your project context, prompts, and responses never leave your computer. Useful when you cannot or prefer not to send session data to a cloud provider, or when you want to keep working offline.

## Requirements

- REAPER 7.0 or later
- ReaImGui extension (install via ReaPack from the ReaTeam Extensions repository)
- An API key from one of the supported cloud providers (Anthropic, OpenAI, Google), or a local / custom-endpoint setup as described above

## Installation

### Via ReaPack (recommended)

1. Install [ReaPack](https://reapack.com) if you do not already have it.
2. In REAPER, open `Extensions > ReaPack > Import repositories...`
3. Paste this URL and click OK:
   ```
   https://raw.githubusercontent.com/michaelbriggsaudio/mbriggs-reaper/main/index.xml
   ```
4. Open `Extensions > ReaPack > Browse packages...`, find ReaAssist, right-click and install.
5. Run the action `Script: ReaAssist.lua` from REAPER's Action List. Recommended: bind it to a toolbar button or keyboard shortcut.

### Manual

Download `ReaAssist.lua` and the `Resources/` directory into your REAPER scripts folder. Keep `Resources/` directly beside `ReaAssist.lua`; the script expects them in the same directory. Then load `ReaAssist.lua` via REAPER's Action List.

## Author

Michael Briggs is an award-winning audio engineer and producer based in Denton, Texas, available for production, mixing, recording, and mastering. He has worked with over 400 artists on more than 3,000 songs across just about every genre. Voted Best Producer and Best Audio Engineer in North Texas.

- [michaelbriggs.audio](https://michaelbriggs.audio) - production, mixing, recording
- [michaelbriggsmastering.com](https://michaelbriggsmastering.com) - mastering services

## License

See [LICENSE.txt](LICENSE.txt) for terms.
