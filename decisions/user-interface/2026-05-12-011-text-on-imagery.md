---
status: accepted
date: 2026-05-12
---
# Text and logos over imagery use shared `.text-on-image*` utilities

## Context and Problem Statement

Hero cards, continue-watching cards, upcoming-release cards, and the detail-modal hero all overlay text and logo PNGs directly on backdrop / poster imagery. The pixels under the overlay vary by image — bright skies and white clothing can dissolve white text outright. Six different components had grown six different arbitrary `drop-shadow-[…]` values: `0 1px 3px / 0.85`, `0 2px 8px / 0.7`, `0 2px 10px / 0.85`, `0 2px 12px / 0.6`, `0 2px 14px / 0.75`, plus Tailwind's bare `drop-shadow`. Inconsistent — and most weren't strong enough for worst-case backgrounds (a bright sky, a white wall).

We need one decision, one recipe per size tier, so future overlays don't re-pick numbers.

## Decision Outcome

Chosen option: two CSS utility classes in `assets/css/app.css`, applied wherever text or a logo sits over an uncontrolled image:

- `.text-on-image` — `text-shadow: 0 1px 3px rgba(0, 0, 0, 0.85)`. For body text (description, meta, captions, subtitles). `text-shadow` tracks glyph outlines exactly and stays crisp at small sizes.
- `.text-on-image-lg` — `filter: drop-shadow(0 2px 10px rgba(0, 0, 0, 0.85))`. For titles AND for logo `<img>` elements over imagery. `filter: drop-shadow()` is used because CSS `text-shadow` has no effect on images.

Why these specific recipes:

- The body recipe was picked from a side-by-side comparison (`/tmp/shadow-test.html`) over the actual "All That's Left of You" backdrop. `0 1px 3px / 0.85` was the tightest recipe that still lifted the text on the worst pixels (bright turquoise sky) without reading as "stamped" on darker regions.
- The title recipe matches what `detail/hero.ex` already used for the modal hero — wider blur (10px) and slight downward offset, which gives big display type presence without halo'ing into the image. Verified in the same comparison.
- We deliberately did **not** add a "small image" or "subtitle" tier — fewer classes, less drift. The body class works for small text; the lg class works for both titles and any logo image (small or large).

When to apply:

- Text or logo lives directly over a backdrop / poster / uncontrolled image → apply one of the two utilities.
- Text lives on `.glass-surface`, `.glass-inset`, `base-100`, or any solid → no utility (contrast is already guaranteed).
- Text lives *below* an image in a separate panel → no utility (the text isn't overlaid).

### Consequences

* Good, because new overlay surfaces just add one of two classes — no copy-pasting arbitrary `drop-shadow-[…]` values
* Good, because the recipes are tunable in exactly one place (`app.css`) if the visual judgement changes
* Good, because intent is captured in the class name (`text-on-image`) rather than buried in opaque shadow numbers
* Bad, because there is now a small extra rule to remember on top of Tailwind's own `drop-shadow-*` and v4's `text-shadow-*` utilities — but the semantic naming makes the right choice obvious
* Bad, because future Tailwind v4 features (e.g. `text-shadow-*`) overlap with our class; we accept the duplication for now in exchange for the semantic name
