# Fade by time, levelled per subject

Phase 3 faded a position or a triad's voicing in three steps (Shown, Faded, Hidden). One clean pass moved it on a step. Instead, so that a prompt is learned within the time it takes to play, each prompt's notes now start fully shown and fade out over its fade time, a share of its expected time, and the roots stay marked throughout. A ladder of fade levels shortens that time. It belongs to the same subjects the stages did: a scale kind in a position, and a triad's quality, inversion and string set. Level 0 never fades, so anything new is first seen whole. At the last level only the roots are shown from the start.

## Considered options

- **More discrete stages.** Rejected: smoother steps are still jumps, and stages can't adapt to how long a prompt takes.
- **Fade time from the player's own response times.** Rejected for now: fast but unclean answers would speed the fade. A level moved only by clean prompts is easier to trust. Phase 6 can revisit this.

## Consequences

- A triad's last level keeps its root marked. The Hidden stage marked nothing.
- Fade levels, like the stages before them, are worked out from the log and never stored. Attempts record the level they were played at. Old attempts map Shown to level 0, Faded to level 2 and Hidden to the last level, so no progress is lost. That's a schema migration.
- A paced prompt's expected time comes from its clicks or backing. An unpaced prompt's comes from a set allowance per note or voicing.

## Update, 2026-11-27: a level a session at most

A level moved by every prompt climbed a subject several levels in one session, before the player had shown they knew it on another day. Now each subject moves at most one level a session (in free practice, a run): up if every prompt of it played at the level reached was clean, down if any wasn't. Its prompts are played all session at the level reached before it. This holds for every fade subject, scales and triads alike. To work this out from the log, attempts record their run (a session's id, or a free-practice run's), so the schema gains a run id (V5). Attempts logged before it count a pass or voicing each as a run of its own, as they did.
