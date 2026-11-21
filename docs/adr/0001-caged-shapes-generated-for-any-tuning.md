# CAGED shapes are generated for any tuning, named CAGED only where it means something

CAGED comes from open-chord shapes in standard tuning, but the app must work in any tuning (Drop D, DADGAD, Open G, …). We generate the five CAGED shapes for every tuning with one algorithm derived from where the roots fall, rather than from hard-coded fret tables. The C A G E D names are shown only when the tuning has standard string-to-string intervals (standard, E♭ standard, and Drop D with the low string adjusted); in other tunings the same five shapes are called Position 1–5.

## Considered Options

- Hard-coded CAGED fret tables for standard tuning: rejected, breaks every non-standard tuning.
- Offer CAGED only in standard-interval tunings, 3NPS elsewhere: rejected, pentatonic and blues have no 3NPS patterns, so those tunings would have no positions at all.

## Consequences

- 3NPS patterns cover only seven-note scales; pentatonic and blues always use the CAGED shapes (Position 1–5), even when 3NPS is the chosen position system.

## Generation rule

- **CAGED shapes:** for each of the five notes of the key's major pentatonic on string 6, walk up the strings taking two pentatonic notes per string; that fret window is the shape. Seven-note scales (and blues, for its ♭5) add their other notes inside the window, taken from strings 5–1 only (on string 6, widened to cover its own two notes), so a dropped low string moves only its own notes and Drop D keeps the standard shape on strings 5–1. A dropped tuning (standard intervals with string 6 a whole tone low, as Drop D) builds the shape on the undropped neck and moves string 6 up by the drop, so its string 6 plays exactly the standard shape's string-6 pitches (two frets higher). Names by starting degree: 1→E, 2→D, 3→C, 5→A, 6→G. Minor keys use their relative major's shapes. In standard tuning this reproduces the familiar boxes (including the B-string shift) with no special cases.
- **3NPS patterns:** each of the seven scale degrees on string 6 starts a pattern; every string takes the next three scale notes going up.
- **Placement:** a position sits at the lowest fret where it fits wholly between the capo and fret 22; its octave-up copy is offered too when it fits.
