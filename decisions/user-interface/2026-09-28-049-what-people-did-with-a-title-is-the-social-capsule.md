---
status: accepted
date: 2026-09-28
---
# What people did with a title is the social capsule

Supersedes UIDR-037 (the pennant). Amends UIDR-040 (no warm hue) and UIDR-046 (the social glyph, the grade on every title surface). Design: `docs/superpowers/specs/2026-09-28-remove-pennant-and-rose-design.md`, mockups in `docs/superpowers/specs/2026-09-28-remove-pennant-and-rose-mockups/`.

## Context and Problem Statement

The person card's grade (UIDR-046, amended 2026-09-28) drew what people did with a title as glyphs graded plain, silver and gold. The title surfaces still drew it as the pennant: named flags flying from a hero's right edge, love on a rose fill, and no grade. The owner decided the social surfaces lead, and asked that the title surfaces follow them and that the pennant and the rose go.

## Decision Outcome

One drawing of what people did with a title, on every surface: the **social glyph** (`Title.SocialGlyph`) — a flag at its grade (`Title.Grade`), plain a white line drawing, silver and gold the solid glyph in metal (smooth since the same day's UIDR-046 amendment; it was first drawn brushed). Formerly the *act glyph*.

1. **One feed, one count.** Every title surface reads `Activities.activity_for/1` — every known person's live acts, the reader's included — and grades it with `Title.Grade`, the same count the person cards make. "You and one friend" is silver on both.
2. **Drawn when a friend did it.** A flag appears on a title surface only when at least one friend did that act; the reader counts toward its grade but never draws one alone (`SocialWords.drawn_flags/1`). The bookmark, the watched state and the Review control already say what the reader did.
3. **The title detail: the social capsule.** In the hero's upper right, a dark ink pill holds the title's social glyphs at 24px, then a chevron; it names no one. Pressing it opens the **social panel** over the backdrop: every review (the tile, the name, the glyph, how long ago, the words), then one sentence per wordless act ("Nick, Sam and you watched this"). The panel closes the way a glass menu does — a click outside, BACK, or the capsule again. It is the one place the modal names who did each act (`Title.Social`).
4. **The lead review.** When the modal is opened from a review, that review leads the prose above the synopsis: the tile, the name, the glyph, the words.
5. **Title rows** (the Watchlist, Incoming's search results) show the title's social glyphs at their right, each with its sentence on hover; no names.
6. **No warm hue.** The rose (`--color-love`) is gone; the heart is drawn like every other glyph. A Feed row's sentiment is a plain social glyph.
7. **The Review modal's choice** is the house segmented control: Dislike, Like, Love, none pressed at open, the pressed one pressed again to clear.

### Consequences

* Good, because a title's social picture is one idiom everywhere — the person card, the row, the modal — with one count behind it.
* Good, because the hero no longer carries a stack of names at rest; the capsule is small and the names are one press away.
* Bad, because who did an act is no longer visible without a press (or a hover on a row); a gamepad reader opens the social panel to read it.
* Bad, because the reader's own review, alone on a title, shows nowhere in the modal but the Review control.

## Anti-patterns

* **Names at rest on a title surface** — the capsule and the rows carry glyphs; the panel carries names.
* **A colour per sentiment** — the grade owns the glyph's colour.
* **The reader's lone act drawn** — the title's own controls already say it.
