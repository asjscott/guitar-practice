# GuitarPractice — Claude Code guide

Native macOS app for a daily, varied guitar practice routine: fretboard notes, scales in position, triads, triads over progressions, and building licks into solos. The guitar comes in through an audio interface; the app listens with pitch detection, plays backing, and adapts to weak spots.

Full spec and roadmap: https://claude.ai/artifact/Qt4EnpkCLa34Z3Fa5icthA
Read the relevant spec section before starting any phase.

## Current phase

**Phase 0 · Foundations.** Done when: the fretboard view draws correctly for any tuning and all TheoryCore tests pass.

Phase order: 0 Foundations → 1 Hear the guitar → 2 Session MVP → 3 Scales and triads → 4 Backing and progressions → 5 Lick → solo → 6 Adaptive and polish. Don't start work from a later phase unless asked.

## Stack

- Swift 6 (strict concurrency), SwiftUI, macOS 14+, Apple silicon
- SwiftData for persistence (app target only)
- AVAudioEngine + AudioKit for audio (from Phase 1; not in Phase 0)
- XcodeGen: `project.yml` is the source of truth for the Xcode project
- Personal use, run from Xcode; public GitHub repo (MIT licence)

## Layout

```
GuitarPractice/
├── CLAUDE.md
├── project.yml                 # XcodeGen spec — edit this, never the .xcodeproj
├── App/                        # SwiftUI app target
│   ├── GuitarPracticeApp.swift
│   ├── Views/                  # Fretboard, Settings, (later) Session, Exercises, Dashboard
│   ├── Models/                 # SwiftData models
│   └── Resources/
├── Packages/
│   └── TheoryCore/             # Pure Swift package: no UI, no audio, no SwiftData
│       ├── Sources/TheoryCore/
│       └── Tests/TheoryCoreTests/
├── Sounds/                     # git-ignored; filled by scripts/fetch-sounds
├── sounds.json                 # (Phase 4) sound pack manifest: url, licence, credit
├── scripts/
└── CREDITS.md
```

## Commands

```bash
xcodegen generate                                    # after any change to project.yml
cd Packages/TheoryCore && swift test                 # theory tests (run often)
xcodebuild -scheme GuitarPractice -destination 'platform=macOS' build
```

Run `swift test` after every TheoryCore change and `xcodebuild … build` after app changes. Fix failures before moving on.

## Architecture rules

- **TheoryCore is pure.** Value types, no side effects, no imports beyond Foundation. Every public function has tests. Exercises ask TheoryCore what is correct; they never do note or fret maths themselves.
- **Layers:** Views → Session engine / Exercise modules / Progress engine → TheoryCore + Audio engine → SwiftData. Lower layers never import higher ones.
- Use `@Observable` for view state; keep views thin.
- SwiftData models live in `App/Models` only.
- No new dependencies without asking first.

## Music conventions (TheoryCore)

Use the terms in `GLOSSARY.md`. Phase 0 decisions are recorded there and in `docs/adr/`.

- `Pitch` = MIDI note number wrapped in a thin type (middle C = 60). `PitchClass` = 0–11 (C = 0). `Interval` = semitones. Thin wrappers around `Int`, so pitches, pitch classes and intervals can't be mixed up.
- Keys: 12 major keys — C G D A E B F♯ F B♭ E♭ A♭ D♭ — and their relative minors, which take the relative major's spelling (D♯m, B♭m). TheoryCore can still spell all 15 key signatures.
- Spelling: key notes follow the key signature (B♭ in F, A♯ in B); scale notes follow the scale's degree formula (A blues has E♭, not D♯); with no key, use sharps. Never spell from pitch class alone when a key is known.
- Tuning = array of open-string MIDI notes in **physical order, string 6 first** (standard: `[40, 45, 50, 55, 59, 64]`). Any string count in the model; the UI is fixed at 6. Pitches need not rise (re-entrant tunings allowed); each string MIDI 24–72. Default is standard; presets: Drop D, DADGAD, Open G, Open D, E♭ standard.
- String index 0 = physical string 6 internally. UI labels use guitarist convention (string 6 = low E).
- Capo 0–12, adds semitones to every string. Fret numbers are counted from the nut; frets below the capo are unplayable.
- Frets 0–22. A fretboard location = `(string, fret)` — don't call it a "position" (that word means a scale position, see glossary).
- Scales: major, natural minor, major/minor pentatonic, blues.
- Positions: CAGED shapes (5, generated for any tuning; named C A G E D only in standard-interval tunings, else Position 1–5) and 3NPS patterns (7, seven-note scales only). Generation and placement rules: `docs/adr/0001-caged-shapes-generated-for-any-tuning.md`.
- Triads: major, minor (later diminished, augmented); root, 1st, 2nd inversion; string sets of three adjacent strings; a triad voicing spans at most 4 frets.
- Everything must work in any tuning. Tests: exact expected answers in standard tuning; invariants (notes in scale, notes per string, span ≤ 4, within capo–22) in Drop D, DADGAD, Open G and with a capo.

## Phase 0 scope

1. XcodeGen `project.yml` with the app target and the local TheoryCore package
2. TheoryCore: notes, intervals, key-aware spelling, scales, triads + inversions, tuning/capo → fretboard map, CAGED + 3NPS shape generation
3. Tests for all of the above, including Drop D and DADGAD
4. Fretboard view: high E at top, nut on the left, frets 0–22 with real-neck spacing and inlays (3 5 7 9 12 15 17 19 21), capo bar with dimmed frets below; highlight locations; note labels shown / faded / hidden (font shrinks on high frets, text hidden if it can't fit); per-location heatmap tint hook (0–1) with a debug fill
5. Main window = fretboard explorer: key, scale, position, triad (string set, inversion) pickers; not persisted, defaults C major, CAGED E shape. Layout (chosen by prototype, see branch `prototype/fretboard-explorer`, variant A2): pickers in the native window toolbar; a header naming key/scale/position with the notes as chips (root highlighted); the fretboard in a rounded card; a status bar with the legend (root / scale or chord tone). Fretboard look: wood board, bone nut, wound bass strings thinning to string 1, pearl inlays, string names on the left, fret-number ruler, orange root and blue tone dots with a white ring
6. Settings (persisted with `@AppStorage`, not SwiftData): tuning picker with presets + Custom (per-string semitone stepper), capo 0–12, position system (CAGED/3NPS)

## Repo rules

- Never commit sound files (`Sounds/`, `*.sf2`, `*.sfz`, audio samples). They are git-ignored and fetched by script.
- Small, focused commits with clear messages.
- Keep `CREDITS.md` up to date when any third-party asset is added.

## How to work

- For anything non-trivial, outline the plan first and wait for approval.
- In TheoryCore, write the tests first, then the implementation.
- When a change affects the spec (a decision or behaviour change), say so, so the spec doc can be updated.

## Agent skills

### Issue tracker

GitHub Issues on asjscott/guitar-practice, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.
