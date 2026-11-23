# GuitarPractice

The language of a daily guitar practice app: where notes live on the neck, how they are named, and the shapes a player learns.

## Notes and keys

**Pitch**:
A specific sounding note, including its octave (middle C and the C an octave above are different pitches).
_Avoid_: Note (when octave matters), MIDI note

**Pitch class**:
A note name with octave ignored; all Cs share one pitch class.
_Avoid_: Note class, chroma

**Key**:
A tonic plus a mode (major or minor) that decides how notes are spelled. The app uses twelve major keys (C G D A E B F♯ F B♭ E♭ A♭ D♭) and their relative minors.
_Avoid_: Scale (a key is not a scale), tonality

**Spelling**:
The written name of a pitch class, with its accidental, chosen from context: the key's signature for key notes, the scale's degree formula for scale notes (A blues has E♭, not D♯), and sharps when no key applies.
_Avoid_: Enharmonic choice, note name (when the accidental matters)

## The neck

**Tuning**:
The open pitch of each string, listed from the physically lowest string (string 6) to the highest (string 1). Pitches need not rise from string to string.
_Avoid_: Open strings

**String number**:
How a string is named to the player: string 6 is the physically lowest, string 1 the highest, followed by its open note in the current tuning, as "string 3 (G)". The open note alone is not enough, since tunings such as DADGAD repeat it.
_Avoid_: "the G string" (on its own), string index

**Fretboard location**:
One string at one fret: the spot a finger presses.
_Avoid_: Position (that means a scale position), spot, note (for the place)

**Capo**:
A clamp at a fret that raises every open string by that many semitones. Fret numbers are still counted from the nut; frets below the capo cannot be played.

**String set**:
Three adjacent strings that a triad is played on, named by their open notes in standard tuning (E-A-D, A-D-G, D-G-B, G-B-E).
_Avoid_: String group, string trio

**Inversion**:
Which chord tone of a triad is lowest: root position (root lowest), 1st inversion (3rd lowest) or 2nd inversion (5th lowest).

**Triad voicing**:
One playable way to fret a triad: a chord, an inversion and a string set at a particular place on the neck, one note per string, spanning at most four frets.
_Avoid_: Triad shape, grip

## Shapes

**Position**:
A playable region of the neck holding one scale in one key. Every position is either a CAGED shape or a 3NPS pattern.
_Avoid_: Box, shape (as a general term), pattern (as a general term)

**CAGED shape**:
One of five positions per key that tile the neck, named C, A, G, E and D when the tuning has standard string-to-string intervals and Position 1–5 otherwise. Used for every scale.
_Avoid_: CAGED box, CAGED form

**3NPS pattern**:
One of seven positions per key with exactly three scale notes on each string. Exists only for seven-note scales (major, natural minor).
_Avoid_: 3NPS shape, three-note box

## Listening

**Played note**:
A pitch the app hears held steadily, close enough to an equal-tempered pitch (A4 = 440 Hz) to count. One pluck gives at most one played note.
_Avoid_: Detection, hit, note event

**Onset**:
The moment a played note started sounding, before the app was sure of it. Response times are measured to the onset.
_Avoid_: Attack (when meaning the time stamp)

**Cents**:
How far a sound is from the nearest equal-tempered pitch, in hundredths of a semitone.
_Avoid_: Detune, offset

## Practice

**Drill**:
One kind of task the player repeats, such as Note → play it. Drills belong to an exercise module (Fretboard notes, Scales in position, …).
_Avoid_: Exercise (for a single drill), game, quiz

**Prompt**:
One task inside a drill, such as "F♯ on string 3 (G)". A prompt is answered by played notes or, in Fret → name it, by a typed note name.
_Avoid_: Question, item, challenge

**Attempt**:
The record of one prompt's outcome (answered, timed out or skipped), its response time and any wrong answers given before the right one. A sweep is recorded as one attempt per fretboard location.
_Avoid_: Answer, try, trial

**Response time**:
The time from a prompt appearing (in Hear → find it, from the target pitch starting) to the right answer: the onset of the played note, or the note name being submitted. Within a sweep it runs from the previous location being dealt with.
_Avoid_: Latency (that means audio delay), reaction time

**Sweep**:
The single prompt of the All instances drill: every fretboard location of one pitch class in a fret range, found string by string from string 6, lowest fret first.
_Avoid_: Round, lap, pass

## Sessions

**Session**:
One planned run of practice: a time budget split into blocks and tied together by a theme.
_Avoid_: Workout, lesson, run (a run is one go at a drill in free practice)

**Block**:
A timed part of a session, spent on one drill. It ends only when the player moves on; time past its planned end is overtime.
_Avoid_: Section, stage, segment

**Theme**:
What a day's sessions are built around: a key and a position, later also a string set and a progression. Every session on one calendar day shares it.
_Avoid_: Seed (the number it is picked with), topic

**Overtime**:
Time spent in a block after its planned end. It lengthens the session; later blocks keep their length.

**Extend**:
To move the end of the current block two minutes later.

**Free practice**:
Doing one drill on its own, outside a session, with no block and no theme.
_Avoid_: Drill mode, solo practice

**Check run**:
An "In order (check)" run of Note → play it, which tests what the app hears rather than the player. It is never logged.
_Avoid_: Test, calibration
