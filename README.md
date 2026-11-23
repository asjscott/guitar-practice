# GuitarPractice

A native macOS app for a daily, varied guitar practice routine: fretboard notes,
scales in position, triads, triads over progressions, and building licks into solos.
It listens to your guitar through an audio interface, plays backing, and adapts to
your weak spots.

## Requirements

- macOS 14+ on Apple silicon
- Xcode 16+ (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

```bash
xcodegen generate                       # creates GuitarPractice.xcodeproj from project.yml
open GuitarPractice.xcodeproj           # then Run (⌘R)
```

Checks (repo rules and package tests), also run by the pre-commit hook and CI:

```bash
git config core.hooksPath .githooks     # once per clone: turns the pre-commit hook on
scripts/check                           # add --build to build the app too
```

## Layout

- `App/` — SwiftUI app target (views, SwiftData models, resources)
- `Packages/` — pure, unit-tested Swift packages: TheoryCore (music theory), ListenCore (pitch detection), PracticeCore (drill engines)
- `scripts/` — `check`, `snapshot` (screens to PNGs); sound fetching arrives in Phase 4
- `Sounds/` — git-ignored; filled by script

## Licence

MIT — see [LICENSE](LICENSE). Third-party asset credits in [CREDITS.md](CREDITS.md).
