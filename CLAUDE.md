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

- Pitch = MIDI note number (`Int`, middle C = 60). Pitch class = 0–11 (C = 0).
- Note spelling is key-aware: B♭ in F major, A♯ in B major. Never spell from pitch class alone when a key is known.
- Tuning = array of open-string MIDI notes, **low to high** (standard: `[40, 45, 50, 55, 59, 64]`). Default is standard; presets: Drop D, DADGAD, Open G, Open D, E♭ standard. Capo adds semitones to every string.
- String index 0 = lowest-pitched string internally. UI labels use guitarist convention (string 6 = low E).
- Frets 0–22. Fretboard position = `(string, fret)`.
- Scales: major, natural minor, major/minor pentatonic, blues.
- Positions: CAGED (5 shapes, named C A G E D) and 3-notes-per-string (7 patterns), both derived from the tuning, not hard-coded fret tables.
- Triads: major, minor (later diminished, augmented); root, 1st, 2nd inversion; string sets of three adjacent strings.
- Everything must work in any tuning; test non-standard tunings, not just standard.

## Phase 0 scope

1. XcodeGen `project.yml` with the app target and the local TheoryCore package
2. TheoryCore: notes, intervals, key-aware spelling, scales, triads + inversions, tuning/capo → fretboard map, CAGED + 3NPS shape generation
3. Tests for all of the above, including Drop D and DADGAD
4. Fretboard view: highlight positions, label note names, fade/hide labels, ready for a heatmap overlay later
5. Settings: tuning picker with presets + custom per-string, capo, position system (CAGED/3NPS)

## Repo rules

- Never commit sound files (`Sounds/`, `*.sf2`, `*.sfz`, audio samples). They are git-ignored and fetched by script.
- Small, focused commits with clear messages.
- Keep `CREDITS.md` up to date when any third-party asset is added.

## How to work

- For anything non-trivial, outline the plan first and wait for approval.
- In TheoryCore, write the tests first, then the implementation.
- When a change affects the spec (a decision or behaviour change), say so, so the spec doc can be updated.
