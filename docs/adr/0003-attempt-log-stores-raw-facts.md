# The attempt log stores raw facts, with no SkillItem

The spec lists a SkillItem model holding mastery scores, but Phase 2 stores only Session, Attempt and DayTheme. Each Attempt holds what happened (drill, target string, fret and pitch, tuning, capo, outcome, response time, wrong answers, source, date), and Phase 6 derives skill items and mastery from that. The log can't be recollected once months of practice are in it, while a scoring rule chosen now would be a guess.

## Consequences

- Tuning and capo are on every attempt, since a string and fret mean nothing without them.
- All instances logs one attempt per fretboard location, grouped by sweep, so a heatmap needs no special case.
- Check runs are never logged: they test detection, not the player.
- The schema is versioned from its first commit.
