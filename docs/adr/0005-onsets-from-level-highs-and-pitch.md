# Onsets are found by level, highs and pitch together

Phase 1 took any 3 dB jump in level as an onset. With the metronome that failed both ways: a click in a microphone split a ringing note in two, and, even with no click, a pluck less than 3 dB over the note still ringing was missed (ticket #34). Clicks bypass the app-sound filter, so the listener has to cope by itself. It still knows nothing of clicks, output latency or tempo.

The listener now works in two steps:

- **Candidates.** A 3 dB jump in level, a 1 dB jump, or a 6 dB jump above 3 kHz. Clicks, fret noise and hiss make candidates too. None of them is an onset yet, and they don't put off the report of a note.
- **Deciding, once a pitch has held for 80 ms** (when a note was reported before, so no later):
  - *Which candidate it began at:* the last one that the pitch wasn't already sounding before, by comparing the waveform below 1 kHz whole periods apart. So a click just before or after a pluck doesn't move the onset.
  - *The same pitch as the note ringing* is new only if the level, after a click would have died away, is 1.5 dB above where the note's decay would have left it, and something jumped (3 dB, or 6 dB above 1.5 kHz). An octave, a twelfth or two octaves counts as the same pitch, since harmonics outlast their fundamental.
  - *Another pitch* is new after a 3 dB jump, as before; or if the level rises 2 dB; or if the highs jump 9 dB, the jump and the rise come to 11 dB, and the level falls at most 6 dB. A click within 60 ms before the candidate lends its highs, since it hides the pick's.

The numbers come from the recorded clips: plucks jump 14–22 dB above 1.5 kHz after a second, and by their decay about 12–14 dB at 160 BPM; hammer-ons come to 8 dB, jump and rise together; clicks over a steadily ringing string move the level by 0.6 dB at most.

**Over ringing notes** (ticket #54). Arpeggiated triads recorded with each note left ringing under the next showed that the pitch detector hears the chord the ringing notes make, not the note just played: string 1 two octaves low (G4 as G2), or no steady pitch at all, so notes were lost. So, while notes heard in the last 4 s may still ring (none since the sound was below the gate for 0.5 s), the tracker also weighs up what is new after an attack:

- *What is new:* the spectrum of the 70 ms from 30 ms after the candidate, less the spectrum of the 70 ms before it, bin by bin, kept where positive. Its pitch is the MIDI note whose harmonics are strongest there, each weighted down by its frequency so that the octave below doesn't win on the same partials (harmonic summation, after Klapuri 2006); it is tuned by where those harmonics peak in the sound after. It counts if it is at least 0.2 of the sound after, by energy: the recorded plucks make 0.35 or more, fret noise and clicks over ringing notes under 0.01.
- *When the pitch detector's pitch holds,* as above, and what is new has another pitch, the new pitch is the note's. Then it is another pitch if it isn't one of the ringing notes, and the same pitch if it is, by the rules above. Where they agree, the pitch detector tunes the note.
- *When it doesn't hold* within 250 ms of the candidate, the note is decided from what is new alone, by the same rules.
- *An octave, a twelfth or two octaves above a ringing note* is left to the pitch detector: a note plucked again grows its harmonics more than its fundamental, so what is new can read an octave up.

## Consequences

- Legato is told apart by its highs and level. What can't be: a hammer-on or pull-off that jumps 3 dB (as in Phase 1), rises 2 dB at a candidate, or falls within about 60 ms of a click. Clicks over the recorded legato clip make extra notes in most phases from −30 dB up.
- Missed: one pitch plucked again at less than 1.5 dB above its own decay (soft repeats on low strings at 120 BPM and more), and a new pitch much softer than the note before it on a low string at 160 BPM.
- A click while a finger or pick stops the string can make one extra note of that pitch. Clicks as loud as the guitar can take an onset up to their own distance from it.
- The thresholds rest on seven clips from one guitar and interface, and on synthetic notes shaped like them. A picked scale recorded afterwards (33 notes at 120 BPM, no click in the sound) is heard note by note with nothing changed.
- Notes ringing on under the next are tested on four recorded takes of triads arpeggiated low to high on each string set's G, D, Em and C (Em, C, D, Em on strings 6–4), at 70 BPM and 100, cut into seven overlapping clips: all 57 notes in them (48 played) are heard once, at the right pitch, within 50 ms, and still with clicks at −24 dB. With clicks at −12 dB, 2 of the 57 are lost or wrong on the middle and low strings.
- A note decided from what is new alone is reported up to 250 ms after its onset, against about 120 ms otherwise. On the recorded arpeggios that is 12 of the 57, mostly on the middle and low strings.
- A new note an octave, a twelfth or two octaves above a note still ringing is heard only as well as before.
- Harmonic summation spots one new pitch, not two: plucks less than 30 ms apart, as in a strum, are still one note.
- The listener takes about 1% of one core's time in release and 7% in Debug; weighing up what is new takes two 8192-point FFTs per attack over ringing notes.
