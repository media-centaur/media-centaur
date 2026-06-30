---
status: investigating
started: 2026-06-23
last_updated: 2026-06-24
---
# Detail/now-playing page GPU spike

## Goal

A bug report (from Nick) claims the detail/now-playing page holds a sustained
high GPU load, blamed on `background-attachment: fixed` interacting with a
full-viewport backdrop image and stacked `backdrop-filter: blur()` glass layers,
re-blurring on every LiveView progress update during playback. **Find the real
root cause on hardware, then fix the minimal lever** — the report's diagnosis is
partly wrong, so do not implement its proposed fix on faith.

## Status

Investigation only — **no fix written yet**, by request. Report's CSS claims
validated/refuted (below). An automated headless trace ruled out the proposed
fix as a main-thread lever but **cannot** measure the GPU blur pass (software
rendering). Next action is a hardware GPU profile (checklist below); the
investigation is blocked on that measurement.

## What the report got right / wrong

* ✅ `body.media-centaur` has `background-attachment: fixed` — `assets/css/app.css:122`.
  **But** it's on the body's two radial-gradient `background-image`s, **not** the
  backdrop `<img>`. The high-res backdrop is a separate `<img>` element,
  unaffected by `background-attachment`. The report conflates the two.
* ❌ "Detail page renders full-viewport `.page-backdrop`" — wrong. `.page-backdrop`
  is **HomeLive** (`home_live.ex:108`). The detail/now-playing surface is the
  **entity modal** (`entity_modal.ex` → `modal_shell.ex:98`) using
  `.modal-page-backdrop` — `position: absolute`, **70% of the panel height**,
  inside a `.modal-panel` (max-width 1000px, opaque base-100, `overflow:hidden`).
  Not full-viewport.
* ⚠️ Glass tiers: real values are `.glass-surface` 12px (`:183`), `.glass-nav`
  20px (`:233`), `.glass-sidebar` 30px (`:240`). **There is no `.glass` class and
  nothing uses 40px** — that entry is fabricated.
* ⚠️ Report omits the genuinely viewport-sized blur: **`.modal-backdrop`**
  (`assets/css/app.css:414`) — the modal scrim, `position: fixed; inset: 0;
  z-index: 50; backdrop-filter: blur(4px)`, blurs the entire app shell when the
  modal is open. This is the prime suspect, not the body gradient. Other blurs:
  `.console-overlay` 6px (`:1453`), `.identity-banner-strip` 8px (`:1769`).
* ⚠️ "Continuous progress updates" overstated. `MpvSession` persists progress
  **every few seconds** (`entity_modal.ex:481`), not per-frame. The updated node
  is play_card's bar (`play_card.ex:46-49`): a bare `width: X%` with **no CSS
  transition** → one snap-repaint per tick, inside the opaque panel above the
  scrim. A few-second tick does not obviously explain *sustained* load.

## Decisions made

* `2026-06-23` — Do not accept the report's fix (remove `background-attachment:
  fixed`) on faith; the body gradient is the cheap part, the `backdrop-filter`
  layers are the cost. Validate on hardware first.
* `2026-06-24` — Automated headless A/B (SwiftShader, CDP Tracing) result:
  toggling `background-attachment: fixed` off changed paint/raster by **zero**
  (22/14 → 22/14 events over 11 ticks); removing all blur dropped composited
  layers 11→7. **Conclusion: the proposed fix is a no-op for main-thread work;**
  but the headless path **cannot measure the GPU compositor blur pass** (software
  render + `devtools.timeline` only captures main-thread paint). The real
  measurement must be on hardware. Harness at `/tmp/gpu-probe/` (harness.html +
  trace.js) — reproduces the CSS stack with exact app.css values; A/B params
  `fixed=` / `noblur=` / `nomodalblur=` / `mutate=` / `interval=`.

## Next steps — hardware GPU profiling checklist

Run on the real machine; the headless scripts (`mc-debug-browser`,
`chromium-probe`) are SwiftShader and useless here.

1. **Real GPU browser.** Normal Chrome/Chromium → `chrome://gpu` must say
   "Compositing: Hardware accelerated". Open dev app `http://localhost:1080`.
2. **Reproduce state.** Open the detail modal (`.modal-backdrop[data-state="open"]`),
   start real playback so progress ticks fire. If mpv inconvenient, synthesize:
   `Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "playback:events",
   {:entity_progress_updated, %{entity_id: <id>, summary: ..., resume_target: ...,
   changed_record: ...}})` from dev iex (real playback is more faithful).
3. **Sustained vs per-tick.** DevTools → Rendering → Frame Rendering Stats.
   Watch GPU **between** ticks. Continuous high GPU at idle = compositor can't
   cache the blur (the real "sustained" bug, independent of playback). Near-zero
   between ticks, spikes on tick = per-tick re-blur. **This settles the report's
   central premise.**
4. **Performance trace** spanning 2–3 ticks → inspect GPU track + Compositor/
   Raster threads; note GPU ms/tick and whether activity continues between ticks.
5. **Layers panel** → confirm `.modal-backdrop`, `.glass-*` each get a layer with
   a `backdrop-filter` compositing reason; check `.modal-backdrop` layer size.
6. **Decisive A/B in Elements (live, no code yet),** one at a time, re-watch GPU:
   (a) `body` → `background-attachment: scroll` — headless predicts **no change**;
   (b) `.modal-backdrop` → `backdrop-filter: none` — strongest suspect;
   (c) `.glass-nav` / `.glass-sidebar` / `.glass-surface` → `none` individually;
   (d) reduce surviving blur radius (4px→2px) for cost/quality trade.
   Whichever toggle collapses GPU **is** the measured root cause.
7. **Implement the minimal toggle** that drops idle GPU to near-zero while keeping
   the look acceptable. Then proceed via task pipeline (test-first if logic, but a
   pure-CSS blur change may just need before/after profile evidence).

## Completion criteria

* Hardware profile identifies which layer drives the GPU load (named, measured).
* A minimal change drops the GPU load to acceptable, verified by before/after
  Frame Rendering Stats on hardware.
* Wiki Troubleshooting updated if the symptom/fix is user-visible.
* Reporter (Nick) confirmation that the spike is gone.

## Pointers

* CSS: `assets/css/app.css` — `:122` (bg-attachment), `:181/:231/:238` (glass),
  `:414` (`.modal-backdrop` scrim), `:474` (`.modal-page-backdrop`).
* LiveView: `lib/media_centaur_web/live/entity_modal.ex` (modal + progress sub),
  `lib/media_centaur_web/components/modal_shell.ex`,
  `lib/media_centaur_web/components/detail/play_card.ex` (the ticking node).
* Trigger: `MediaCentaur.Playback.MpvSession` → `playback:events` PubSub.
* Repro harness: `/tmp/gpu-probe/harness.html` + `trace.js` (A/B params noted in
  the 2026-06-24 decision). Note: headless = SwiftShader, not GPU-faithful.
