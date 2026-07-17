# mbriggs-reaper

REAPER scripts and tools by [Michael Briggs](https://michaelbriggs.audio).

Distributed via [ReaPack](https://reapack.com) and via direct download from this repository.

## Packages

### ReaAssist

The session-aware workflow assistant for REAPER. Reads your project, dials in plugin parameters, writes Lua and JSFX, and runs scripts for you, all from inside the DAW.

- Folder: [ReaAssist/](ReaAssist/)
- Website: [reaassist.app](https://reaassist.app)
- Full docs: [ReaAssist/README.md](ReaAssist/README.md)

### ReaClock

A scalable studio clock and session display for REAPER, with configurable Clock Faces, region and marker countdowns, Action Buttons, audio metering and visualizations, independent pop-out cards, docking, Presentation mode, and a phase-accurate visual click.

- Folder: [ReaClock/](ReaClock/)
- Full docs: [ReaClock/README.md](ReaClock/README.md)

## Installation

### Via ReaPack (recommended)

1. Install [ReaPack](https://reapack.com) if you do not already have it.
2. In REAPER, open `Extensions > ReaPack > Import repositories...`
3. Paste this URL and click OK:
   ```
   https://raw.githubusercontent.com/michaelbriggsaudio/mbriggs-reaper/main/index.xml
   ```
4. Open `Extensions > ReaPack > Browse packages...`, find the package you want, right-click and install.

### Manual

Download the complete package folder you want into your REAPER scripts folder. Each package is self-contained; preserve all included files and subfolders in their original layout. Then load its main script through REAPER's Action List. See the package README for any specific dependencies or instructions.

## Author

Michael Briggs is an award-winning audio engineer and producer based in Denton, Texas, available for production, mixing, recording, and mastering. He has worked with over 400 artists on more than 3,000 songs across just about every genre. Voted Best Producer and Best Audio Engineer in North Texas.

- [michaelbriggs.audio](https://michaelbriggs.audio) - production, mixing, recording
- [michaelbriggsmastering.com](https://michaelbriggsmastering.com) - mastering services

## License

Each package in this repository is licensed individually. See `ReaAssist/LICENSE.txt` or `ReaClock/Resources/LICENSE.txt` for the applicable terms.
