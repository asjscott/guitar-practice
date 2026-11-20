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

Theory tests:

```bash
cd Packages/TheoryCore && swift test
```

## Layout

- `App/` — SwiftUI app target (views, SwiftData models, resources)
- `Packages/TheoryCore/` — pure Swift music-theory package, fully unit-tested
- `scripts/` — helper scripts (sound fetching arrives in Phase 4)
- `Sounds/` — git-ignored; filled by script

## Licence

MIT — see [LICENSE](LICENSE). Third-party asset credits in [CREDITS.md](CREDITS.md).
