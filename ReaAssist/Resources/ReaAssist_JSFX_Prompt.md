<!-- ReaAssist_JSFX_Prompt.md - on-demand JSFX generation instructions. -->
<!-- Served by CTX.prompt_bundle("jsfx"); requested via <context_needed>prompt_bundle:jsfx</context_needed>. -->
<!-- Kept separate from ReaAssist_System_Prompt.md so JSFX rules do not ship on non-JSFX turns. -->

JSFX: Use ```jsfx fence. First line must be desc:. JSFX is EEL2-based with NO reaper.* API access. Use only standard JSFX variables/functions (spl0, spl1, slider1, @init, @slider, @sample, @gfx). Use srate for time-based math. Don't assume stereo; check num_ch if processing beyond spl0/spl1.
Slider declaration syntax: `sliderN:default<min,max,step>Name` on its own line near the top of the file (e.g. `slider1:2.0<0.2,10,0.01>Decay (s)`, `slider2:20<0,100,0.1>Mix (%)`).
The host writes ```jsfx blocks to <resourcepath>/Effects/ReaAssist/<name>.jsfx before executing any companion Lua block in the same response.
With track: ```jsfx block THEN ```lua block using TrackFX_AddByName(tr, "ReaAssist/<name>.jsfx", false, -1).
Filename derivation: 1) take the desc: value, 2) strip characters: <>:"/\|?*, 3) collapse runs of spaces to one, 4) trim leading/trailing whitespace, 5) truncate name to 60 chars (extension added on top), 6) append .jsfx. Single spaces in the name are preserved.
Without track: only ```jsfx block.

SAFETY (mandatory -- blown-up track/speakers otherwise):
- Only generate JSFX when the design is stable, bounded, and suitable for real-time use.
- Never create unbounded feedback, runaway gain, or self-oscillating networks. For any feedback-based effect (reverb, delay, resonator, chorus, flanger, comb filter, allpass chain, phaser), all of these are mandatory:
  - Feedback coefficient hard-clamped to <= 0.85. (DC gain = 1/(1-fb); 0.85 -> 6.7x, stable. 0.99 -> 100x, blows up on any DC.)
  - DC blocker on every path that feeds back into itself. Standard one-pole: `y = x - x_prev + 0.995*y_prev; x_prev = x; y_prev = y;`.
  - Output soft-shaping via `tanh(x)` or similar where peaks can escape -- NOT hard clipping.
- NO hard-clipping stage (`min(max(x, -T), T)`, explicit saturator at a fixed ceiling, etc.) unless the user explicitly asked for clipping/limiting/distortion. DAW internals are 32-bit float; intentional peaks above 0dBFS are normal and hard-clipping them introduces unwanted distortion. Use soft saturation (tanh, x/(1+|x|)) when shaping is actually needed.
- EEL2 memory model: `buf[i]` reads `mem[buf+i]`. When you need multiple arrays, allocate distinct non-overlapping base pointers in `@init` and use them explicitly (`buf_a = 0; buf_b = 48000; buf_c = 96000;`). Every feedback filter (comb, allpass, delay) must have its OWN dedicated buffer region with enough length for its longest delay tap. Do NOT share slots between filters.
- Delay taps use a single `write_pos` counter that advances once per sample (with modulo against that filter's buffer length), and read at `(write_pos - tap_samps + len) % len`. Do NOT index with the sample counter plus a fixed offset -- that pattern makes multiple filters overwrite each other's slots as the counter walks through the buffer.
- Use conservative defaults: feedback 0.3-0.7, wet/mix defaulting below 50%, resonance well below self-oscillation. A user can always dial up; they can't dial back speakers.
- Do not generate experimental DSP unless explicitly requested ("write me an experimental X", "no safety limits", etc.).
