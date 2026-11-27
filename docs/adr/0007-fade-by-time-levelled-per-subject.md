# Fade by time, levelled per subject

Phase 3 faded a position or a triad's voicing in three steps (Shown, Faded, Hidden). One clean pass moved it on a step. Instead, so that a prompt is learned within the time it takes to play, each prompt's notes now start fully shown and fade out over its fade time, a share of its expected time, and the roots stay marked throughout. A ladder of fade levels shortens that time. It belongs to the same subjects the stages did: a scale kind in a position, and a triad's quality, inversion and string set. Level 0 never fades, so anything new is first seen whole. At the last level only the roots are shown from the start.

## Considered options

- **More discrete stages.** Rejected: smoother steps are still jumps, and stages can't adapt to how long a prompt takes.
- **Fade time from the player's own response times.** Rejected for now: fast but unclean answers would speed the fade. A level moved only by clean prompts is easier to trust. Phase 6 can revisit this.

## Consequences

- A triad's last level keeps its root marked. The Hidden stage marked nothing.
- Fade levels, like the stages before them, are worked out from the log and never stored. Attempts record the level they were played at. Old attempts map Shown to level 0, Faded to level 2 and Hidden to the last level, so no progress is lost. That's a schema migration.
- A paced prompt's expected time comes from its clicks or backing. An unpaced prompt's comes from a set allowance per note or voicing.
