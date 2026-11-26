# UI decisions

The look and behaviour settled in Phase 0. Keep to these when changing a screen. The prototype is on `prototype/fretboard-explorer` (variant A2), which is never merged. The Tuner and Drill screens' decisions are in the spec doc's "Phase 1 decisions"; their prototype is `prototype/phase1-screens` (T1 and D4).

## Fretboard

- High E at the top, nut on the left, frets 0–22 with real-neck spacing; inlays at 3 5 7 9 12 15 17 19 21.
- Wood board, bone nut, wound bass strings thinning to string 1, pearl inlays, string names on the left, fret-number ruler.
- Orange root and blue tone dots with a white ring.
- Capo bar, with the frets below it dimmed.
- Note labels shown / faded / hidden. The font shrinks on high frets; text that can't fit is hidden.
- Zoomed (`fretWindow`): only those frets, real-neck spacing kept, larger dots, labels and numbers, and a thin bar under the fret numbers for the part of the neck. The nut shows from fret 1 down, the open strings from fret 0.
- Faint markers (no name), a yellow ring on the last note played, any number of lit strings.
- Per-location heatmap tint hook (0–1), with a debug fill.

## Explorer

- Key, scale, position and triad (string set, inversion) pickers in the native window toolbar. Not persisted; defaults are C major, CAGED E shape.
- A header naming key, scale and position, with the notes as chips (root highlighted); the fretboard in a rounded card; a status bar with the legend (root / scale or chord tone).

## Drill

- A drill picker at the left of the toolbar, from `DrillKind.all`, grouped by module, then the options that apply to it. Options are not persisted; Order shows only for drills that offer it.
- The neck and target card (`App/Views/Drill/DrillTarget.swift`) draw a `DrillDisplay`, for any drill, on both the Drill and session screens.
- Pause hides the prompt; Resume gives a new one and drops the old. An "In order (check)" run asks for the same location again, as a new prompt, so that none is missed.
- In a drill answered by typing, `.typesNoteNames` (`App/Views/Drill/NoteNameKeys.swift`) takes A–G, # and b, Backspace and Return before focused controls, the sidebar or shortcuts see them; what is typed replaces the headline. No shortcut uses A–G.
- S skips with no reveal: grey in the attempt strip, and in neither accuracy nor median.
- Where the drill hides the note (Hear → find it shows ♪, Fret → name it ?), a skip shows – in the attempt strip.
- Leaving the screen, sleep and losing the input (or access to it) pause a run, as they do a session, with the reason on the card. A paused run is still there on coming back; the sidebar shows a "Paused" badge. Closing the window ends it.
- Start, and Resume, are disabled until microphone access is given and there is an input, with the reason on the card.
- Prompt counts, here and in summaries, count a sweep as one prompt, from its first attempt on, and a triad or a climb once one of its notes is answered or timed out. Accuracy, median and skips are per attempt.
- Hear → find it is timed from the target being heard, output latency included.
- A drill that needs sound pauses if the output fails, with the reason on the card. No output device disables Start.
- Start is disabled, with the reason on the card, when nothing can be prompted.

## Session

- First in the sidebar, and the first-launch default. S4 on branch `prototype/phase2-screens`.
- Setup: the theme (key large, position under it, then on a whole neck, left out when the window is too short for it) with Reroll until the day's first session has started; minutes with − and +, Start (↩), a notice if triads are left out because no voicing is in range, the planned blocks grouped by module, then Naturals / All notes and First 12 frets / Whole neck. Start is disabled, with the reason under it, when nothing can be heard or prompted, or microphone access hasn't been given yet.
- The drills bar stays on top through Ready cards and drills (at the bottom all through a scale or triad block): time left per block (orange and counting up in overtime), or time spent once it is over, then "Ends 18:42".
- + (or =) extends the block while it plays. Chimes sound only in a gap, and the next prompt, or the next block's first, waits for them to end. In a sweep the next location stays up without its ring, S and R work, and notes from before the chime still count; a card that would say "Listening…" says "Wait for the chime".
- With no output, Setup says so and the plan leaves out drills that need sound; chimes flash the screen orange. Losing it mid-block pauses; Resume then goes on without a drill that needs sound.
- Keys go through `onPlainKey`, which sees them before any focused control: Space, Return, S and R work whatever has focus, and held-down repeats do nothing.
- A session keeps the tuning, capo and theme it started with; Settings locks the tuning, capo and position system until it ends. The theme is in the status bar while it goes.
- P pauses, on a Ready card too, which then counts down afresh. Leaving the screen, sleep and losing the input (or access to it) pause, with the reason for the last two on the Paused screen; the sidebar shows a "Paused" badge. Without an input or access, Resume is disabled.
- Esc pauses and asks "End session?" on the Paused screen: Return ends, Esc stays paused, P resumes. Its End session button doesn't ask.
- Closing the window ends the session early.
- The summary shows a card per block that started; one where nothing was answered shows no speed. The cards narrow to fit.

## Scales and triads (Phase 3)

P4 on branch `prototype/phase3-screens`.

- Setup: as Session, with the string set beside the position, as in the status bar.
- Playing: no target card. A header line (what to play, feedback, beats and BPM), a tall zoomed neck, then the pass as a line that rises and falls with pitch and fills in as it is played. In a session the drills bar is below that. The count-in is a big number over the neck.
- Scales at rest: the header has only the beats and BPM; the neck shows the position before Start, and is bare while paused; the text is where the line goes, with how to play the drill. A revealed note is ringed as if played, orange on the line. Between passes the header says how the pass went. The count-in number is the beat of the bar. Resume restarts the pass, or gives the next if it was over. The status bar counts complete and clean passes.
- Losing the output pauses a scale drill; Resume, and Start, then go on by the beats shown. When it is back the click is heard again, in time, without a pause.
- The zoomed neck keeps the wood, inlays, string names and fret numbers, stays still during a pass, and has a thin bar showing which part of the neck it is. Scales: the position and two frets either side. Triads: the whole practised range, since a tighter zoom would give the voicing away (so none with Whole neck).
- Only the last note played is lit, ringed in yellow; never the next, and not the earlier ones, which would give the shape away.
- Fade stages: Shown has dots and names, Faded faint dots without names, Hidden faint roots only; the last note played keeps its name. The toolbar's Fade is Follow (the stage reached), Shown, Faded or Hidden.
- H held shows the position, in the count-in and between passes too; between passes it costs nothing unless held into the next. Pausing ends it until H goes down again; letting go, losing the window and a sheet end it.
- Scales in a session: one scale of the theme's mode per pass, in turn, named in the header (From a degree names it beside the degree); the neck zooms to that pass's position. A due chime waits for the bar to end after a pass, and the next count-in for the chime; after S it sounds at once, and the count-in waits too.
- In a session the metronome button is in the status bar in scale blocks, on their Ready cards and while paused, and the panel is over the corner above it. Opening it pauses a Ready card too, which then counts down afresh. Each drill's tempo is taken up again on its Ready card and on Resume, in free practice too, and the fade stages reached are read again on Resume, unless Fade is an override. In a narrow window the status bar leaves the theme out.
- Triads: the set's strings lit, and a circle per string with its note once played (or Shown). The countdown ring is at the right of the header. Once the voicing is played or revealed, all of it shows. No attempt strip. At rest, the header is empty and the text is where the circles go. Inversions has a line between the neck and the circles: a dot per voicing, rising to the highest and back, over its inversion (green played, orange revealed, grey skipped), and the Inversions option is left out. In a session the neck shows the session's fret range, and a chime waits for the voicing to end.
- Triads fade too, each voicing shape (major or minor, inversion, string set and tuning) in any key: Shown has the voicing's dots and names, with its names in the circles, and isn't timed; Faded has faint dots; Hidden nothing. The lowest voicing in range is shown until the first note picks one; Inversions shows the one it has reached. A clean voicing goes one stage on, one with a wrong note, a timeout or a hint one back; one skipped or cut short neither. H and the toolbar's Fade are as for scales; the options give way to the run's buttons during a run.
- Beats: every beat of the bar shown, emphasised ones larger and blue, the current one orange.
- Metronome panel: at the button ("♩ = 72 · 4/4"; "♪ = 72 · 6/8" where an eighth note clicks), or on M: BPM, Hold tempo, time signature, a circle per beat to emphasise, volume, sound. It is drawn in the window, over the corner nearest the button, not a popover; a click elsewhere, M or Esc closes it. While it is closed, [ and ] lower and raise the tempo by 4. Closing it goes on only with a run that opening it paused, and not if sleep or losing the input or output would have paused that. While it is open the run's buttons are disabled.
- In free practice the button is in the toolbar; Key, Scale, Position and Fade give way to it and the run's buttons during a run, when the header names them.
- The header's BPM is the pass's that is going, the button's the next one's. A pass at another tempo than the next one's (changed since by hand) doesn't move the ladder. The count of passes that weren't clean is remembered with each scale drill's tempo, across runs, session blocks and days, and through a change of tempo or Hold.
- Evenness, as "evenness 18 ms", follows how the pass went, until the next count-in ends.
- Summary: a card per block that started, as now, with the scale and triad figures. Scales: clean passes out of complete ones, large, then the fastest clean tempo, and the median evenness. Triads: prompts, first-try accuracy per note, the median time per voicing ("3.10 s a voicing": only voicings played whole, and from Resume if it started one again) and skips. The slowest prompts leave scales out.

## Progressions (Phase 4)

B on branch `prototype/phase4-screens`, chosen provisionally: the player will judge it in use with the backing, and A (a row of chord cards under the neck) is the fallback.

- Playing: a header line (the drill and the progression's chords, feedback, which time through and the fade stage), the tall zoomed neck, then a timeline of chord blocks (name and numeral, a tick per beat) that scrolls left past a fixed playhead, with the next time through coming in from the right.
- The neck shows the current chord's voicing at the run's fade stage, with the notes played so far solid and the last one ringed. While Shown, the next chord's voicing is ghosted on it.
- Past blocks are tinted by outcome: green clean, orange wrong, grey missed; the current one is outlined.
- Target top note: the top notes as a line that rises and falls over the blocks, each named.
- The count-in is a big number over the neck, as for scales.
- The neck moves on to the next chord half a beat before its first beat, when its window opens. The header's right end says which time through and the fade stage ("3rd time through · Faded"); H shows the current voicing but doesn't bring back the ghost.
- Free practice: Key (all 24, by mode), Progression (of the key's mode), Position (of the key's scale), Style and Tempo (♩ = 70 at first). The tempo is remembered for all progression drills, the style per progression. They give way to the run's buttons during a run. At rest the neck shows the position faintly, with the drill's text where the timeline goes.
- Under the timeline, orange notices: without the backing's sounds, that the drill plays clicks and how to fetch them; with the Mac's built-in microphone as input, that it will hear the backing as notes.
- Summary: chords, clean and times through, then "23 of 24 chords clean · 6 times through · Hidden from the 5th" and the hardest chords ("Hardest: D (5 of 6)"), only those not always clean.

## Settings

- Persisted with `@AppStorage`, not SwiftData.
- Tuning picker with presets + Custom (per-string semitone stepper), capo 0–12, position system (CAGED/3NPS).
- Metronome tab: the eight common time signatures as buttons, then beats in a bar (1–12) and the beat note (4 or 8); the bar's beats, each a button that turns its emphasis on or off; sound on or off (off, the beats still show), volume, Listen. Listen plays at 60 BPM, and stops on leaving the tab, sleep and losing the output; it is disabled while a drill has the click. The tab isn't locked during a session.
- Metronome tab, Backing section: Listen plays I–V–vi–IV in G, rock, at 70 BPM, after a bar of drumsticks, with the click on top unless "With the click" is off. It stops as the metronome's Listen does, and the two exclude each other. Without the sounds fetched it is disabled, and the footer says to run `scripts/fetch-sounds`.
