# Backing plays through Apple's sampler on the app's output engine, not AudioKit

The spec planned AudioKit for backing (MIDISampler with a SoundFont, AppleSequencer for timing). AudioKit's MIDISampler is a thin wrapper around `AVAudioUnitSampler`, which loads .sf2 by itself, and AppleSequencer runs on its own clock, which would have to be kept in step with the metronome's. Instead the backing is one `AVAudioUnitSampler` per part (bass, keys, drums) on the engine that already plays clicks, and our own code schedules its notes at host times from the same clock, corrected for output latency as clicks are. PracticeCore renders the backing (which pitch sounds when) as pure data, so it can be tested. No new dependency.

## Consequences

- Clicks and backing cannot drift apart: they are scheduled from one clock on one engine.
- Anything AudioKit would have given beyond playing samples (SFZ loading, effects) is not available; SFZ packs are converted to .sf2 beforehand, as the spec already says.
