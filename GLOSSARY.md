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

**Circle of fifths**:
The twelve major keys in order, each a fifth above the last: C G D A E B F♯ D♭ A♭ E♭ B♭ F, and back to C. Their relative minors follow it in the same order. A session goes round it from the theme's key, sharpward.
_Avoid_: Cycle of fifths, circle of fourths (that is the same circle the other way)

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

**Progression**:
A sequence of chords written as Roman numerals, each lasting a number of bars, such as I–V–vi–IV. Played in a key, the numerals become chords (I–V–vi–IV in G is G D Em C).
_Avoid_: Chord sequence, changes

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
The record of one prompt's outcome (answered, timed out or skipped), its response time and any wrong answers given before the right one. A sweep is recorded as one attempt per fretboard location; a pass, a triad prompt and a climb as one per note; a time through as one per chord.
_Avoid_: Answer, try, trial

**Response time**:
The time from a prompt appearing (in Hear → find it, from the target pitch starting) to the right answer: the onset of the played note, or the note name being submitted. Within a sweep or a pass it runs from the previous location being dealt with.
_Avoid_: Latency (that means audio delay), reaction time

**Sweep**:
The single prompt of the All instances drill: every fretboard location of one pitch class in a fret range, found string by string from string 6, lowest fret first.
_Avoid_: Round, lap, pass

**Pass**:
One scale played once through a position in a set order, such as up and down from its lowest root. (All instances has sweeps instead.)
_Avoid_: Run, sweep, lap

**Climb**:
The single prompt of the Inversions drill: one chord on one string set, through every voicing in range by fret, up and back, the highest once.
_Avoid_: Ladder (that is the tempo ladder), run, sweep, pass

**Time through**:
One playing of a progression from its first chord to its last, over the backing. A progression drill repeats it until the block ends.
_Avoid_: Loop, chorus, pass (that is a scale)

**Voicing in the position**:
A triad voicing whose three fretboard locations all belong to the theme's position, in any inversion and on any string set.
_Avoid_: Voicing in the shape, voicing in the box

**Clean**:
Said of a pass whose every expected note was played with no wrong note, timeout, skip or hint. Timing does not affect it. A triad's voicing is clean in the same way, and so is a chord in a time through: its voicing played on time, low to high, with no wrong note.
_Avoid_: Perfect, correct (for a whole pass)

**Count-in**:
The whole bars of clicks, at least four clicks, that come before a pass and set its tempo. The first note may come up to half a beat early; anything before that is ignored.
_Avoid_: Lead-in, pre-roll

**Backing**:
The accompaniment the app plays for a progression: bass, keys and drums in one style at one tempo. The app does not treat it as its own sound to ignore, so it must not reach the guitar's input.
_Avoid_: Backing track (when generated), play-along, jam track

**Input delay**:
How long after a pluck the app hears it, measured by the latency check and taken off every onset before it is compared with clicks or backing.
_Avoid_: Latency (on its own), lag, offset

**Click**:
One beat of the metronome, heard and shown. Tempo (BPM) counts clicks, whatever note the time signature makes a beat.
_Avoid_: Tick, pulse (that is only the part shown)

**Emphasis**:
Which beats of the bar have a stronger click. Any beats can be chosen, or none.
_Avoid_: Accent, downbeat (beat 1 need not be emphasised)

**Tempo ladder**:
The rule that raises a scale drill's tempo after clean passes that kept up with the clicks, and lowers it after passes that weren't clean.
_Avoid_: Speed trainer, auto-tempo

**Fade time**:
How long a prompt's notes stay on screen: everything is shown when the prompt starts and fades out by the fade time, except the roots, which stay marked. A pass's prompt is the whole pass; a triad's is its voicing.
_Avoid_: Fade speed, display time

**Expected time**:
How long a prompt should take: for a pass or chord played to clicks or backing, its length at the tempo; otherwise a set allowance per note or voicing. The first fade time is most of it.
_Avoid_: Target time, time limit (a prompt can still time out separately)

**Fade level**:
How far a scale kind in one position, or a triad's quality, inversion and string set, has got towards being played from the roots alone, whatever the key or root. Level 0 never fades; each level after it shortens the fade time; at the last, only the roots are shown from the start. It moves at most one level a session (in free practice, a run): up if every prompt of it played at the level reached was clean, down if any wasn't. Its prompts are played at the level reached before the session or run.
_Avoid_: Fade stage (the earlier Shown / Faded / Hidden), memory level, difficulty

**Hint**:
Showing the position during a pass, or the voicing in a triad drill, on request. The pass or voicing is then not clean.
_Avoid_: Reveal (that follows a timeout)

## Sessions

**Session**:
One run of the daily routine: the same blocks in the same order every day, tied together by a theme, lasting as long as its blocks take.
_Avoid_: Workout, lesson, run (a run is one go at a drill in free practice)

**Block**:
A part of a session spent on one drill. Most end when their drill is done; one with a planned length (step 2) ends only when the player moves on, and step 4 by itself after the pass that crosses its minute.
_Avoid_: Section, stage, segment

**Theme**:
What a day's sessions are built around: a key, a position, a string set and a progression in the key's mode. Every session on one calendar day shares it.
_Avoid_: Seed (the number it is picked with), topic

**Module**:
A group of drills that train one skill: Fretboard notes, Scales in position, Triads, Progressions.
_Avoid_: Category, area

**Extend**:
To move the end of a block with a planned length two minutes later.

**Free practice**:
Doing one drill on its own, outside a session, with no block and no theme.
_Avoid_: Drill mode, solo practice

**Free time**:
The last block of a session: the theme's backing loops with the theme's position shown, and the player plays what they like. Nothing is recorded, and it ends when the player ends the session.
_Avoid_: Jam, free practice (that is a drill outside a session)

**Check run**:
An "In order (check)" run of Note → play it, which tests what the app hears rather than the player. It is never logged.
_Avoid_: Test, calibration
