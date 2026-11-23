# Audio input is an input-only Core Audio unit, not an AVAudioEngine tap

ADR 0002 said the listener is fed by a plain `AVAudioEngine` input tap. The tap delivers 100 ms blocks (4410 frames at 44.1 kHz, 4800 at 48 kHz) whatever block size is asked for, and a smaller IO buffer doesn't change that. With 4410-frame blocks a synthetic low E is reported about 181 ms after its onset on average, 227 ms at worst; the budget is 150 ms. So input uses an input-only AUHAL unit with 512-frame IO blocks: 128 ms on average, 138 ms at worst, and 1024 frames would leave almost no margin (136 and 146 ms).

`AVAudioSinkNode` also gives 512-frame blocks, but it keeps the engine: its restart notices (#20), its temporary aggregate, and, on a Mac with no default input device, an engine that runs and hears nothing.

## Consequences

- Core Audio's real-time thread only copies samples into a ring; consumers run on our own audio input thread, so they may lock and allocate.
- We watch the device's sample rate and streams ourselves, and restart only if the set-up differs from the one last tried.
- Output (app sounds, backing) is separate and can still use an engine.
