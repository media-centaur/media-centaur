---
status: accepted
date: 2026-09-12
---
# A review is an opinion of any valence: the sentiment shows when given, nothing when none

Enacts [ADR-068](../architecture/2026-09-12-068-review-replaces-recommendation-on-the-wire.md).
Amends [UIDR-037](2026-09-08-037-friend-provenance-is-the-pennant.md) (the
pennant's flags), [UIDR-038](2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md)
(§1 and the Love-heart rule) and [UIDR-039](2026-09-11-039-add-to-watchlist-then-the-tracking-controls.md)
(the control's glyph); [UIDR-031](2026-09-06-031-friends-carry-shelves-feed-is-recommendations.md)'s
anti-pattern "no reactions beyond Like/Love" is amended in place.

## Context and Problem Statement

The recommendation's sentiment was Like or Love with Like the floor, so
the surfaces encoded Like as absence: a Feed entry showed "a rose heart for
Love and nothing for Like", the pennant flew love and like, and the
Recommend modal preselected Like. Three glyph maps — the pennant's, the
Friends card's and the feed card's inline heart — each spelled sentiment →
icon. A review can carry dislike, like, love, or no sentiment at all, so
absence must mean none, and a third value would have made three maps ×
three values.

## Decision Outcome

1. **Three sentiments, one glyph each, one component.** Dislike is a thumbs
   down, like a thumbs up, love a filled heart in the rose `--color-love`;
   the other two take the surrounding text colour.
   `Components.Title.Sentiment` renders the glyph wherever a sentiment sits
   beside a name; the pennant composes the same map into its own fill.
2. **Nothing means none.** A feed entry reads the friend's name,
   "reviewed", then the glyph when the review gives a sentiment and nothing
   when it does not, then the title, then the text when there is text. A
   bare review is name, verb and title. The Friends card's *Reviewed* shelf
   carries the glyph on the same rule.
3. **Six flags on the mast**, in order: love, like, dislike, reviewed,
   watched, listing. A review flies its sentiment, or the reviewed flag (a
   speech bubble) when it gives none — "Nick reviewed this". Own reviews fly
   ("You"); own watching and listing still never do.
4. **The choice is clearable and starts empty.** The Review modal offers
   the three sentiments as pennant previews, none pressed at open; pressing
   the pressed one clears it. Send is always enabled — a review needs
   neither a sentiment nor text.
5. **The control is Review, a pencil.** On both title surfaces the control
   that opens the modal is the pencil-square icon named *Review*. The paper
   plane said "send"; the verb is now review.

### Consequences

* Good, because absence is honest on every surface at once: a friend's
  thumbs down reads as such on the Feed, the shelf and the mast.
* Good, because one glyph map replaces three.
* Bad, because a mast can carry six flags, so a title several friends
  split on wears a taller mast. Row surfaces already bleed the mast into
  their padding under `overflow-hidden`.
* Bad, because the Feed loses the compactness of "no glyph is a like";
  most entries now carry a glyph.

## Anti-patterns this record names

* **Absence as a value** — nothing on a surface must mean nothing.
* **A colour per sentiment** — love keeps the one warm hue; dislike is not
  red. Colour is for health.
* **A required verdict** — a review is not a rating form.
