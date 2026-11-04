---
status: accepted
date: 2026-09-12
amended: 2026-11-04
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

## Amendment 2026-09-28 — no warm hue

UIDR-049 removes the rose: love is drawn like every other sentiment, as a social glyph at its grade, and `Components.Title.Sentiment` is gone (a Feed row draws its sentiment through `Title.SocialGlyph`). Rule 1's rose and the anti-pattern's "love keeps the one warm hue" no longer hold; the grade owns the glyph's colour. Rule 3's flags stand as the social glyph's flags; there is no mast. The Review modal's choice (rule 4) is the segmented control.

## Amendment 2026-11-04 — the modal says what you are saying

The Review modal (`Live.ReviewModal` over `Live.ReviewFlow`) is rebuilt around the reader's statement (`docs/superpowers/specs/2026-11-04-review-modal-redesign-design.md`). Rule 4 stands — the choice is clearable, starts empty, and Share is always enabled — but the control is the house segmented control with each sentiment's glyph beside its word, under a headline sentence "You ___ this" that the pressed sentiment fills with its solid glyph and the reader's verb (`SocialWords.own_verb/1`). The heading "Share a review", the TMDB overview and the relay count are gone; the footer carries no line about who will see it — who reads a relay is not the app's to list, and the flash after Share already says when it is kept for a relay to come. The words are held in the flow (`phx-change`), which is what fixes the review a sentiment press used to erase. A title the reader already reviewed opens as editing — prefilled, Save, Remove review — and the detail shows the own review in its note line as You with the glyph and the words; the pencil reads "Edit your review".
