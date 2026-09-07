---
status: accepted
date: 2026-09-06
---
# Page hero backdrops paint from a decoded-bitmap cache

Amends [UIDR-012](2026-05-20-012-desktop-app-rendering-defaults.md) for one
surface class: the full-viewport hero backdrops, at the time on Home, Library
and Incoming. [UIDR-033](2026-09-07-033-home-is-the-only-page-with-artwork.md)
later removed the Library and Incoming bands, leaving Home's hero as the sole
tenant; the mechanism below is unchanged.

## Context and Problem Statement

UIDR-012 makes every in-flow `<img>` `loading="eager" decoding="sync"` so a
page paints once its artwork is decoded — no blank slot, no fill-in. For
the page hero backdrops this did not hold. The hero is the TMDB master,
typically 3840×2160, and every live navigation destroys and rebuilds the
page DOM, so each return to Home re-decoded the master from the HTTP cache.
Measured in the media-center shell (Chromium 152, GPU raster) with
realistic image-cache pressure between visits: the decode ran on a raster
worker for 32–50 ms (median 46 ms), Chromium painted the page without the
backdrop at ~90 ms after the click, rastered it in bands, and completed it
at ~240 ms. `decoding="sync"` is not honoured for an image this large on
the GPU path. The owner reported it as the one place the UI feels unstable.

Bounding the hero to a width derivative removes most of the decode cost but
upscales 29 of 43 hero masters on the 4K panel; the owner declined the
trade. No image format decodes cheaper than baseline JPEG at the same pixel
count.

## Decision Outcome

Chosen option: "keep the decoded bitmap in JavaScript and paint it onto a
canvas", because the page JavaScript survives live navigation while the DOM
does not, so the decode can be paid once per hero rather than once per visit,
at full master resolution.

* `assets/js/hooks/hero_backdrop.js` owns an LRU of `ImageBitmap`s keyed by
  URL (~33 MB each at 4K). Capacity was three, one per backdrop-bearing page;
  under UIDR-033 it is one.
* `Components.HeroBackdrop.hero_backdrop/1` renders a `<canvas>` with the
  `HeroBackdrop` hook; on `mounted` a cache hit is drawn in the same task as
  the DOM patch, so it lands in the mount frame. A miss decodes off the main
  thread and draws when ready — the previous behaviour, without blocking.
* `data-src` is `LiveHelpers.hero_backdrop_src/1` of the backdrop URL. The
  root layout marks the same URL on its prefetch hint
  (`ArtworkWarmup.hero_backdrop_url/0`, `data-hero-backdrop`) and `app.js`
  pre-decodes it at idle, so the first visit is warm too. Byte-identical keys
  on both sides are asserted in `artwork_warmup_test.exs`.
* Canvas is a replaced element like `<img>`; the page CSS (`object-fit`,
  `object-position`) applies unchanged. The `?v=` availability bump changes
  the URL, so invalidation is the key.

Measured after (same shell, same walk and pressure, five returns): the canvas
is painted at insert + 0 ms on every return, the first frame after the click
already carries the picture, and no hero decode task appears in the trace.

### Consequences

* Good, because the hero is on screen in the frame the page mounts, at the
  master's full resolution, on every return and on first visit after idle.
* Good, because the fix is confined to one component, one hook, and one
  shared URL function; the `<img>` policy in UIDR-012 is untouched for every
  other surface, and Credo MC0016/MC0028 still govern them.
* Bad, because three decoded 4K bitmaps are held for the session (~100 MB).
  Accepted: the shell is a dedicated desktop app on a machine with memory to
  spare, the same trade UIDR-012 already makes.
* Bad, because a canvas has no story to catalog; the component is
  `@storybook_status :skip` and its behaviour is covered by bun tests on the
  cache and hook plus LiveView tests on the three hosts.
