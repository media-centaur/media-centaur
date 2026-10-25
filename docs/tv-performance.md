# TV performance — the floor every UI change meets

The TV app (a **remote player**, `campaigns/remote-players.md`) renders the
host's pages in an Android TV WebView on hardware far weaker than any
desktop. It is the performance floor: a UI change is done when it holds on
the TV, not when it looks right in a desktop browser. The rule is
[UIDR-056](../decisions/user-interface/2026-10-25-056-the-tv-app-is-the-performance-floor.md);
this document is how to meet it and how to measure it.

## Glossary

| Term | Meaning |
|---|---|
| **Floor device** | The slowest device the app supports, today the Sony below. |
| **Presented frame** | A frame the display compositor (Android's SurfaceFlinger) actually put on screen, with its timestamp. The only measure that matches what the eye sees. |
| **Glide** | The input system's animated scroll after a D-pad move (`assets/js/input/core/scroll_glide.js`). |
| **Main-thread scroll** | A scroll offset written from JavaScript. Each step needs a commit, then raster of any newly exposed tiles, before it can be shown. |
| **Compositor scroll** | A scroll the browser animates itself (`scrollBy({behavior: "smooth"})`, a user fling). It moves already-rastered tiles without the main thread. |
| **Interleaved A/B** | Conditions alternated within one run on one device state, so the device's own variance cancels out. |

## The floor device

Sony BRAVIA 4K VH21: MediaTek MT5895, four cores at up to 1.8 GHz, 3 GB of
RAM with 100 MB of swap that fills, Android TV 12, the Android System
WebView (Chromium 155 on 2026-10-25). The panel is 4K at 60 Hz, but apps
draw a 1920×1080 window that the TV scales up; the WebView runs at a device
pixel ratio of 2, so pages see a 960 CSS px screen. The root layout marks a
page served to a paired player with `data-player="remote"` on `<html>`;
TV-only styles key off it.

## Rules (each measured on the floor device)

1. **No backdrop blur on the TV.** `app.css` turns every `backdrop-filter`
   off under `html[data-player="remote"]`. With it, the library's 44 blurred
   poster cards took 93 ms a frame (9–14 fps glides). Glass must stay
   legible without its blur.
2. **No `background-attachment: fixed`.** Chromium repaints a fixed
   background on every scroll frame, which capped every scroll at 30 fps.
   A fixed background is a fixed layer of its own (`body.media-centaur::before`).
   Enforced by `test/media_centaur_web/tv_performance_css_test.exs`.
3. **Animate only `transform` and `opacity`.** A transform animation runs on
   the compositor and presented at a steady 60 fps on the floor device.
4. **Prefer compositor scrolling; keep main-thread scrolling cheap.** A
   compositor scroll held 57–58 fps in every device state measured. A
   main-thread scroll (the glide) needs a commit and raster per frame and
   measured anywhere from 30 to 60 fps on the same code as the device's
   state changed. Nothing may add work to a scroll frame: scroll listeners
   are passive and constant-time, and no per-frame `querySelectorAll` or
   layout read runs during a glide.
5. **Decode images no larger than the display.** The Home hero's bitmap is
   scaled to the display (`fitToScreen` in `hooks/hero_backdrop.js`); a 4K
   master held at full size spent three quarters of its memory on pixels
   the TV never shows. A poster entering view costs about 25 ms of decode
   on the raster threads — avoid bringing many new images into view at
   once.
6. **The TV shows the desktop's composition.** A remote player has no
   auto-scale floor, so the TV draws the 1920 px layout at scale 0.5
   (`root.html.heex`). Design at 1920 CSS px; the TV has no room for larger.
7. **Memory is shared and small.** The TV runs the release app, often the
   debug app, and other apps in 3 GB. Each WebView holds 150–350 MB; keep
   caches bounded and drop what the screen does not show.

## How to change UI safely

A change that touches CSS, layout, images, animation, scrolling or the
input system's motion is checked on the TV before it is done:

1. Measure the change against its base **interleaved**, at least two
   rounds: a CSS or JS override with `mc-tv-smooth run --cond base --cond
   css:<file>` (the override restores the old behaviour, or applies the
   new one), or, for code that cannot be overridden, alternate the two
   versions in the dev server's checkout between rounds (only when no
   other agent works in it).
2. Accept no regression beyond the noise between rounds (a few fps).
   Record the numbers in the commit message or the campaign.
3. When a result is slow, explain it with `mc-tv-trace` before changing
   anything: which pipeline stage is late decides the fix.

## Measuring

* **Measure what the screen shows.** `~/scripts/agents/mc-tv-smooth`
  reads presented frames from SurfaceFlinger while a glide runs. The page's
  own `requestAnimationFrame` reports 60 fps throughout and `dumpsys
  gfxinfo` counts the app's frames, not the page's; neither shows the
  choppiness.
* **Measure the real library.** `mc-tv-smooth host dev` points the debug
  app at the dev server (posters, full rows). The simulated host has no
  artwork and understates the cost.
* **Only interleaved conditions compare.** Identical code measured 29, 38
  and 60 fps at different times on 2026-10-25. A number from another run is
  not a baseline. Each row records the TV's CPU load and free memory.
* **Wait for a settled page.** The debug app loads with `LOAD_NO_CACHE`,
  so every page load refetches all artwork; `mc-tv-smooth` waits until
  loading stops before measuring.
* **Explain with a trace.** `~/scripts/agents/mc-tv-trace --key DPAD_DOWN`
  records a Chromium trace of one action and prints, per presented frame,
  each pipeline stage's p50/p90 and what drove the frame.
  `PRESENTED_PARTIAL` frames reached the screen without the main thread's
  update — the mark of a main-thread scroll missing its deadline. The
  first trace after a page load often catches only a few frames; take the
  second. `--from FILE` re-reads a saved trace.
* **Never reboot the TV.** It is also the development machine's display;
  a reboot from the rig crashed the desktop session. Ask the owner.

## Open (2026-10-25)

Worked in `campaigns/tv-performance.md`.


Key-press glides measured 59.9 fps on 2026-10-25 at midday and 35–42 fps
from mid-afternoon on, with that midday commit, the current code, both
debug app builds, either glide implementation, either scale and a freshly
booted TV alike; a compositor scroll measured 57 fps throughout. The cause
is not found. Not yet ruled out: `mc-tv-smooth`'s own page probe (it reads
every element's scroll offsets each frame, which costs a main-thread
scroll and not a compositor one), and the WebView's draw on Android's
render thread (`DrawFn_DrawGL`, up to 48 ms).

Also open: the Home hero's memory saving on the TV is estimated (about 66
to 16 MB on Home), not measured — read the debug app's PSS on Home before
and after `e84dfd99`'s change with the TV free.
