# Our own pitch detector instead of AudioKit PitchTap

The spec named AudioKit's PitchTap for pitch detection. We use our own MPM (McLeod) detector instead, in the pure `ListenCore` package, fed by a plain `AVAudioEngine` input tap. Detection is the project's biggest risk: we need control over the analysis window (low E is 82 Hz, Drop D's low string 73 Hz), protection against octave errors, and `swift test` coverage with synthetic signals. PitchTap's fiddle-style tracker gives none of these and hides its buffering from us. AudioKit is not needed until Phase 4 backing; it is not a Phase 1 dependency.

## Consequences

- `ListenCore` is pure like TheoryCore (samples in, pitch estimates and played notes out); only device selection and the engine tap live in the app.
- Small self-recorded guitar clips (< 1 MB each) may be committed as test fixtures under `Packages/ListenCore/Tests/ListenCoreTests/Fixtures/`, a narrow exception to the no-audio-in-git rule.
- `ListenCore` may import Accelerate (a system framework: vDSP keeps the detector fast enough to listen live in Debug builds) besides Foundation; it still has no UI, AVFoundation or SwiftData.
- `ListenCore` reports pitches as plain MIDI note numbers (`Int`), not TheoryCore's `Pitch`, so it stays free of TheoryCore; the app wraps them in `Pitch` where it connects ListenCore to PracticeCore.
