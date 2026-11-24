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
- Prompt counts, here and in summaries, count a sweep as one prompt, from its first attempt on, and a triad once one of its notes is answered or timed out. Accuracy, median and skips are per attempt.
- Hear → find it is timed from the target being heard, output latency included.
- A drill that needs sound pauses if the output fails, with the reason on the card. No output device disables Start.
- Start is disabled, with the reason on the card, when nothing can be prompted.

## Session

- First in the sidebar, and the first-launch default. S4 on branch `prototype/phase2-screens`.
- Setup: the theme (key large, position under it, then on a whole neck, left out when the window is too short for it) with Reroll until the day's first session has started; minutes with − and +, Start (↩), the planned blocks grouped by module, then Naturals / All notes and First 12 frets / Whole neck. Start is disabled, with the reason under it, when nothing can be heard or prompted, or microphone access hasn't been given yet.
- The drills bar stays on top through Ready cards and drills: time left per block (orange and counting up in overtime), or time spent once it is over, then "Ends 18:42".
- + (or =) extends the block while it plays. Chimes sound only in a gap, and the next prompt, or the next block's first, waits for them to end. In a sweep the next location stays up without its ring, S and R work, and notes from before the chime still count; a card that would say "Listening…" says "Wait for the chime".
- With no output, Setup says so and the plan leaves out drills that need sound; chimes flash the screen orange. Losing it mid-block pauses; Resume then goes on without a drill that needs sound.
- Keys go through `onPlainKey`, which sees them before any focused control: Space, Return, S and R work whatever has focus, and held-down repeats do nothing.
- A session keeps the tuning, capo and theme it started with; Settings locks the tuning, capo and position system until it ends. The theme is in the status bar while it goes.
- P pauses, on a Ready card too, which then counts down afresh. Leaving the screen, sleep and losing the input (or access to it) pause, with the reason for the last two on the Paused screen; the sidebar shows a "Paused" badge. Without an input or access, Resume is disabled.
- Esc pauses and asks "End session?" on the Paused screen: Return ends, Esc stays paused, P resumes. Its End session button doesn't ask.
- Closing the window ends the session early.
- The summary shows a card per block that started; one where nothing was answered shows no speed.

## Scales and triads (Phase 3, not built yet)

P4 on branch `prototype/phase3-screens`.

- Setup: as Session, with the string set beside the position.
- Playing: no target card. A header line (what to play, feedback, beats and BPM), a tall zoomed neck, then the pass as a line that rises and falls with pitch and fills in as it is played. The drills bar moves below that. The count-in is a big number over the neck.
- The zoomed neck keeps the wood, inlays, string names and fret numbers, stays still during a pass, and has a thin bar showing which part of the neck it is. Scales: the position and two frets either side. Triads: the whole practised range, since a tighter zoom would give the voicing away (so none with Whole neck).
- Only the last note played is lit, ringed in yellow; never the next, and not the earlier ones, which would give the shape away.
- Fade stages: Shown has dots and names, Faded faint dots without names, Hidden faint roots only.
- Triads: the set's strings lit, and a circle per string with its note once played. The countdown ring is at the right of the header. Once the voicing is played or revealed, all of it shows. No attempt strip. At rest, the header is empty and the text is where the circles go.
- Beats: every beat of the bar shown, emphasised ones larger and blue, the current one orange.
- Metronome panel: over the status-bar button ("♩ = 72 · 4/4") or on M: BPM, Hold tempo, time signature, a circle per beat to emphasise, volume, sound.
- Summary: a card per block that started, as now, with the scale and triad figures.

## Settings

- Persisted with `@AppStorage`, not SwiftData.
- Tuning picker with presets + Custom (per-string semitone stepper), capo 0–12, position system (CAGED/3NPS).
