---
status: accepted
date: 2026-09-06
amended: 2026-09-07
---
# Page hero backdrops paint from a decoded-bitmap cache

Amends UIDR-012 for the full-viewport page hero; UIDR-033 (2026-09-07) narrowed the tenants to Home alone.

## Context and Problem Statement

The hero is the TMDB master, typically 3840×2160; every live navigation rebuilds the DOM, so each return to Home re-decoded it (32–50 ms, backdrop complete about 240 ms after the click). `decoding="sync"` is not honoured for an image this large on the GPU path, and a width derivative would upscale most masters on a 4K panel.

## Decision Outcome

1. `assets/js/hooks/hero_backdrop.js` keeps decoded `ImageBitmap`s in an LRU keyed by URL. Page JavaScript survives live navigation, so the decode is paid once per hero at full resolution. Capacity is one.
2. `Components.HeroBackdrop.hero_backdrop/1` renders a `<canvas>` with the hook. A cache hit is drawn in the same task as the DOM patch; a miss decodes off the main thread and draws when ready.
3. `LiveHelpers.hero_backdrop_src/1` builds the key on both sides: the canvas's `data-src` and the root layout's prefetch hint (`ArtworkWarmup.hero_backdrop_url/0`), pre-decoded at idle so the first visit is warm.
4. Canvas is a replaced element, so `object-fit` and `object-position` apply unchanged; the `?v=` bump changes the key, which is the invalidation.

After: painted at insert on every return, no decode task in the trace.

### Consequences

* One decoded 4K bitmap (about 33 MB) is held for the session.
