# Onsets are found by level, highs and pitch together

Phase 1 took any 3 dB jump in level as an onset. With the metronome that failed both ways: a click in a microphone split a ringing note in two, and, even with no click, a pluck less than 3 dB over the note still ringing was missed (ticket #34). Clicks bypass the app-sound filter, so the listener has to cope by itself. It still knows nothing of clicks, output latency or tempo.

The listener now works in two steps:

- **Candidates.** A 3 dB jump in level, a 1 dB jump, or a 6 dB jump above 3 kHz. Clicks, fret noise and hiss make candidates too. None of them is an onset yet, and they don't put off the report of a note.
- **Deciding, once a pitch has held for 80 ms** (when a note was reported before, so no later):
  - *Which candidate it began at:* the last one that the pitch wasn't already sounding before, by comparing the waveform below 1 kHz whole periods apart. So a click just before or after a pluck doesn't move the onset.
  - *The same pitch as the note ringing* is new only if the level, after a click would have died away, is 1.5 dB above where the note's decay would have left it, and something jumped (3 dB, or 6 dB above 1.5 kHz). An octave, a twelfth or two octaves counts as the same pitch, since harmonics outlast their fundamental.
  - *Another pitch* is new after a 3 dB jump, as before; or if the level rises 2 dB; or if the highs jump 9 dB, the jump and the rise come to 11 dB, and the level falls at most 6 dB. A click within 60 ms before the candidate lends its highs, since it hides the pick's.

The numbers come from the recorded clips: plucks jump 14–22 dB above 1.5 kHz after a second, and by their decay about 12–14 dB at 160 BPM; hammer-ons come to 8 dB, jump and rise together; clicks over a steadily ringing string move the level by 0.6 dB at most.

## Consequences

- Legato is told apart by its highs and level. What can't be: a hammer-on or pull-off that jumps 3 dB (as in Phase 1), rises 2 dB at a candidate, or falls within about 60 ms of a click. Clicks over the recorded legato clip make extra notes in most phases from −30 dB up.
- Missed: one pitch plucked again at less than 1.5 dB above its own decay (soft repeats on low strings at 120 BPM and more), and a new pitch much softer than the note before it on a low string at 160 BPM.
- A click while a finger or pick stops the string can make one extra note of that pitch. Clicks as loud as the guitar can take an onset up to their own distance from it.
- The thresholds rest on seven clips from one guitar and interface, and on synthetic notes shaped like them. The recorded scale clip and playing at the gate are still to confirm them.
- The listener takes about 1% of one core's time in release and 7% in Debug.
