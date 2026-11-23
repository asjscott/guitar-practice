# UI decisions

The look and behaviour settled in Phase 0. Keep to these when changing a screen. The prototype is on `prototype/fretboard-explorer` (variant A2), which is never merged. The Tuner and Drill screens' decisions are in the spec doc's "Phase 1 decisions"; their prototype is `prototype/phase1-screens` (T1 and D4).

## Fretboard

- High E at the top, nut on the left, frets 0–22 with real-neck spacing; inlays at 3 5 7 9 12 15 17 19 21.
- Wood board, bone nut, wound bass strings thinning to string 1, pearl inlays, string names on the left, fret-number ruler.
- Orange root and blue tone dots with a white ring.
- Capo bar, with the frets below it dimmed.
- Note labels shown / faded / hidden. The font shrinks on high frets; text that can't fit is hidden.
- Per-location heatmap tint hook (0–1), with a debug fill.

## Explorer

- Key, scale, position and triad (string set, inversion) pickers in the native window toolbar. Not persisted; defaults are C major, CAGED E shape.
- A header naming key, scale and position, with the notes as chips (root highlighted); the fretboard in a rounded card; a status bar with the legend (root / scale or chord tone).

## Drill

- A drill picker at the left of the toolbar, from `DrillKind.all`. Options are shared by every drill and not persisted; Order shows only for drills that offer it.
- The neck and target card (`App/Views/Drill/DrillTarget.swift`) draw a `DrillDisplay`, for any drill, on both the Drill and session screens.
- Pause hides the prompt; Resume gives a new one and drops the old. An "In order (check)" run asks for the same location again, as a new prompt, so that none is missed.
- In a drill answered by typing, `.typesNoteNames` (`App/Views/Drill/NoteNameKeys.swift`) takes A–G, # and b, Backspace and Return before focused controls, the sidebar or shortcuts see them; what is typed replaces the headline. No shortcut uses A–G.
- S skips with no reveal: grey in the attempt strip, and in neither accuracy nor median.
- Where the drill hides the note (Hear → find it shows ♪, Fret → name it ?), a skip shows – in the attempt strip.
- A drill that needs sound pauses if the output fails, with the reason on the card. No output device disables Start.
- Start is disabled, with the reason on the card, when nothing can be prompted.

## Session

- First in the sidebar, and the first-launch default. S4 on branch `prototype/phase2-screens`.
- Setup: minutes with − and +, Start (↩), the planned blocks, then Naturals / All notes and First 12 frets / Whole neck. Start is disabled, with the reason under it, when nothing can be heard or prompted.
- The drills bar stays on top through Ready cards and drills: time left per block, or time spent once it is over.
- Keys go through `onPlainKey`, which sees them before any focused control: Space, Return, S and R work whatever has focus, and held-down repeats do nothing.
- A session keeps the tuning and capo it started with; Settings locks the tuning, capo and position system until it ends.
- P pauses, on a Ready card too, which then counts down afresh. Leaving the screen, sleep and losing the input pause, with the reason for the last two on the Paused screen; the sidebar shows a "Paused" badge. Without an input, Resume is disabled.
- Esc pauses and asks "End session?" on the Paused screen: Return ends, Esc stays paused, P resumes. Its End session button doesn't ask.
- Closing the window ends the session early.
- The summary shows a card per block that started; one where nothing was answered shows no speed.

## Settings

- Persisted with `@AppStorage`, not SwiftData.
- Tuning picker with presets + Custom (per-string semitone stepper), capo 0–12, position system (CAGED/3NPS).
