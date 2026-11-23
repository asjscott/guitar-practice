# GuitarPractice — Claude Code guide

Native macOS app for a daily, varied guitar practice routine: fretboard notes, scales in position, triads, triads over progressions, and building licks into solos. The guitar comes in through an audio interface; the app listens with pitch detection, plays backing, and adapts to weak spots.

Full spec and roadmap: Claude Docs `c1631de5-f295-4bd8-a9fe-f1c1948a980d`. Before starting a phase, read that phase's section with the docs connector (not the Artifact tool); edit it with full node ids (`ms84a902bdp.13168`, not `.13168`). The link for people: https://claude.ai/artifact/Qt4EnpkCLa34Z3Fa5icthA

## Current phase

**Phase 2 · Session MVP.** Scope: All instances, Hear → find it and Fret → name it drills; time budget input, daily theme seed, block planner, block player; auto-advance, keyboard shortcuts, end-of-block chime; SwiftData attempt log and session summary. Done when: a timed notes session runs start to finish.

Also in Phase 2: the input-device bug, #20.

Phases 0 (spec #1) and 1 (spec #11) are complete.

Phase order: 0 Foundations → 1 Hear the guitar → 2 Session MVP → 3 Scales and triads → 4 Backing and progressions → 5 Lick → solo → 6 Adaptive and polish. Don't start work from a later phase unless asked.

## Stack

- Swift 6 (strict concurrency), SwiftUI, macOS 14+, Apple silicon
- SwiftData for persistence (app target only)
- An input-only Core Audio unit for audio input (ADR 0004), with our own pitch detector in ListenCore (ADR 0002); AudioKit for backing from Phase 4
- XcodeGen: `project.yml` is the source of truth for the Xcode project
- Personal use, run from Xcode; public GitHub repo (MIT licence)

## Commands

```bash
git config core.hooksPath .githooks   # once per clone: the pre-commit hook runs scripts/check
scripts/check                         # repo rules + all package tests, ~10 s
scripts/check --build                 # the same, then generates the project and builds the app
scripts/snapshot                      # renders each screen to build/snapshots/*.png
```

Run `scripts/check` after package changes and `scripts/check --build` after app changes. Fix failures before moving on.

To see a UI change, run `scripts/snapshot` and read the PNGs (screen recording is not permitted). Add a `save` in `App/Debug/Snapshots.swift` for each new screen or state.

## Architecture rules

- **ListenCore and PracticeCore are pure too** (`scripts/check` enforces each package's imports). ListenCore: samples in, tuner readings and played notes out; the input unit and Core Audio device code live in the app. PracticeCore: drill engines driven by played notes (a `Pitch` and an onset time) and a clock. The app connects them.
- **TheoryCore is pure.** Value types, no side effects. Every public function has tests. Exercises ask TheoryCore what is correct; they never do note or fret maths themselves.
- **Layers:** Views → Session engine / Exercise modules / Progress engine → TheoryCore + Audio engine → SwiftData. Lower layers never import higher ones.
- Before changing the fretboard, explorer or Settings, read `docs/ui.md`.
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

## Repo rules

- Never commit sound files (`Sounds/`, `*.sf2`, `*.sfz`, audio samples). They are git-ignored and fetched by script. One exception: small self-recorded guitar clips (< 1 MB each) used as ListenCore test fixtures, under `Packages/ListenCore/Tests/ListenCoreTests/Fixtures/` (ADR 0002).
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
