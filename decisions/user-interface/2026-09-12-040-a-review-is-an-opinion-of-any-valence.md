---
status: accepted
date: 2026-09-12
---
# A review is an opinion of any valence: the sentiment shows when given, nothing when none

Enacts ADR-068; UIDR-037, 038 and 039 carry the change in place.

## Context and Problem Statement

Like was the recommendation's floor, so surfaces encoded Like as absence, and three glyph maps spelled sentiment to icon. A review can carry dislike, like, love, or nothing, so absence must mean none.

## Decision Outcome

1. **Three sentiments, one glyph each, one component** (`Components.Title.Sentiment`): thumbs down, thumbs up, a filled heart in the rose `--color-love`. The pennant composes the same map.
2. **Nothing means none.** A feed entry reads name, "reviewed", the glyph only when given, the title, then any text.
3. **Six flags on the mast**: love, like, dislike, reviewed, watched, listing. A review with no sentiment flies reviewed.
4. **The choice is clearable and starts empty**; pressing the pressed sentiment clears it. Send is always enabled.
5. **The control is Review**, the pencil-square icon on both surfaces.

### Consequences

* A title several friends split on wears a taller mast.

## Anti-patterns

* **Absence as a value.**
* **A colour per sentiment** — love keeps the one warm hue; dislike is not red.
* **A required verdict** — a review is not a rating form.
