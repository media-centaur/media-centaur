---
status: accepted
date: 2026-05-12
---
# Text and logos over imagery use shared `.text-on-image*` utilities

## Context and Problem Statement

Cards and the detail-modal hero overlay text and logo PNGs on backdrop or poster imagery, where a bright-sky backdrop can dissolve white text. Six components had grown six different `drop-shadow-[…]` values, most too weak for the worst case.

## Decision Outcome

Two utilities in `assets/css/app.css`, applied wherever text or a logo sits over an uncontrolled image:

1. `.text-on-image` — `text-shadow: 0 1px 3px rgba(0, 0, 0, 0.85)`. Body text: descriptions, meta, captions. Tracks glyph outlines and stays crisp at small sizes.
2. `.text-on-image-lg` — `filter: drop-shadow(0 2px 10px rgba(0, 0, 0, 0.85))`. Titles and logo `<img>` elements, because `text-shadow` has no effect on images.
3. No further tiers.

Apply when text or a logo sits directly over a backdrop, poster or other uncontrolled image. Not on `.glass-surface`, `.glass-inset`, `base-100` or any solid, and not for text below an image in its own panel.

### Consequences

* Tailwind's `drop-shadow-*` and `text-shadow-*` utilities overlap these classes; the semantic class is used instead.
