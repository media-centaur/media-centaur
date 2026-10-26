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
| **System trace** | Android's Perfetto trace of the whole device around one action: kernel scheduling and CPU frequency, framework slices (`gfx`, `view`, `webview`), SurfaceFlinger's frame timeline, and the WebView's own Chromium track events, all on one clock. What `mc-tv-trace` records. |
| **Frame timeline** | SurfaceFlinger's per-frame verdict on Android 12 and later: the budget an app frame had, the time it took, on time or late, and whether the app or SurfaceFlinger was at fault. |
| **Render thread** | The Android app's `RenderThread`, which draws the WebView's frame into the window each vsync (`HardwareRenderer::Draw`, waiting on viz in `ScheduleOnVizAndBlock`). Invisible to Chromium's pipeline stages. |

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
   compositor scroll held 57–60 fps in every device state measured. A
   main-thread scroll (the glide) needs a commit and raster per frame: it
   presents at 60 fps on the floor device when the frame is otherwise
   empty, and lost 16–19 fps to one per-frame `querySelectorAll('*')`
   with layout reads (2026-10-25, run 42). Nothing may add work to a
   scroll frame: scroll listeners are passive and constant-time, and no
   per-frame `querySelectorAll` or layout read runs during a glide.
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
   new one), or, for code that cannot be overridden, the two commits
   served side by side with `~/scripts/agents/mc-tv-ab <ref-a> <ref-b>`
   (never by switching the dev server's checkout; it is the owner's
   daily driver).
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
  not a baseline. Each row records the TV's CPU load and free memory, the
  spread of its own rounds (`fps range`) and, for every condition after
  the first, the difference against that spread (`Δ vs first`): only a
  difference beyond the noise is a result. The same `--cond` given twice
  is an A/A run, which shows the noise on its own.
* **Check what moved before reading the number.** A row's `animator`
  says what produced the glide's step profile: `glide` is the input
  system's main-thread glide (its largest step is always among the
  first); `eased` is a browser smooth scroll on the compositor, which
  presents at 60 fps on the Sony regardless. On 2026-10-25 a 59.9 fps
  "glide" was an `eased` scroll; the glide itself measured 35–42. Two rows
  compare only when `animator` and `px/glide` agree.
* **Measure the tool's own cost before believing its numbers.** The
  probe `mc-tv-smooth` used until 2026-10-25 evening polled every
  element's scroll extents on every frame and cost the glide 16–19 fps;
  a whole afternoon of "slow" readings was the tool. The present probe is
  a passive scroll listener and measured zero cost (run 43). After any
  change to the probe, alternate a probed and a `--no-probe` run into one
  `--out` directory and read `Δ vs first`. `mc-tv-trace`'s tracing cost
  nothing measurable (`mc-tv-trace --cost`, 2026-10-26: Δ −0.0, noise
  3.8 over six glides a side), but only after its DevTools action mark
  was removed: a DevTools session opened and closed right before the
  key cost the glide that followed 6.5 fps on its own. **No DevTools
  traffic between a measurement's setup and its action**; `mc-tv-smooth`
  installs its probe, then clears presents over adb, then presses, and
  measured zero cost in that order. A `hold` or `js` action runs through
  such a session at the action itself, so its absolute fps carries
  whatever that costs; compare such actions only within one tool.
  Chromium's `PipelineReporter` count is not the screen's present count
  (54 against 41 on one glide), which is why the report leads with the
  presents.
* **Compare two commits with `mc-tv-ab`.** `~/scripts/agents/mc-tv-ab
  <ref-a> <ref-b>` serves each commit from its own worktree as a
  measurement server (`background_services = false` in its override
  TOML: it serves pages and does nothing on its own, whatever the
  copied database's service toggles say) on ports 2161 and 2162,
  against a `sqlite3 .backup` of the dev database with the real image
  cache and data directory, then runs `mc-tv-smooth run --cond host:a
  --cond host:b` and takes both down. A host condition re-points the TV
  app (a restart, so the first trial after a switch is the slow one run
  44 showed); `page id` names each host's HEAD. The paired TV needs no
  pairing against them: admission is a signed session cookie, dev's
  signing key is fixed and cookies are per host, not per port. Ecto
  never downgrades, so a ref whose schema is older than the dev
  database's runs against the newer schema. `mc-tv-ab up`, `run`,
  `down` and `status` are the steps on their own (M6 reads a server's
  memory between `up` and `down`).
* **A run starts with the app on screen.** SurfaceFlinger presents
  nothing for a layer behind the TV's input, while the WebView still
  answers over CDP: a run after a handback recorded zero presents in
  every trial. `mc-tv-smooth run` brings the app to the front first; a
  row with zero glides on a page that scrolls is this, not a result.
* **Check the page identity.** Each row's `page id` is the served
  bundle's digest and the checkout's HEAD (`*` when the tree is dirty).
  `MIXED` means the rounds measured different pages. Twice on 2026-10-25
  the page on the TV was not the code the session believed it was
  measuring; this column is what would have shown it. The HEAD is the
  checkout serving the page's own origin (the host registry in
  `~/scripts/agents/_tv.py`: the dev server, the sim host and
  `mc-tv-ab`'s servers). The digest identifies a build, not a commit:
  dev's esbuild inlines the source map with the checkout's absolute
  paths, so two worktrees at one commit serve two digests. Under
  `mc-tv-ab`, compare the HEADs.
* **Wait for a settled page.** The debug app loads with `LOAD_NO_CACHE`,
  so every page load refetches all artwork; `mc-tv-smooth` waits until
  loading stops before measuring.
* **Explain with a trace.** `~/scripts/agents/mc-tv-trace --key DPAD_DOWN`
  records a system trace of one action into a record directory
  (`~/.cache/mc-tv-trace/<stamp>/`) and prints, in this order: the
  screen's presents over the glide (the same fps `mc-tv-smooth` would
  print), the frame timeline's verdict on each app frame (late, and
  whether the app or SurfaceFlinger was at fault), Chromium's pipeline
  (frames by state and driver, each stage's p50/p90/max;
  `PRESENTED_PARTIAL` frames reached the screen without the main thread's
  update, the mark of a main-thread scroll missing its deadline), the
  render thread's draw and its wait on viz per frame, every WebView
  thread's running and runnable time with its heaviest slices, and the
  CPU frequency range. A long render-thread wait under a short pipeline
  means Android, not Blink. The trace file opens in `ui.perfetto.dev`.
  `--from DIR` re-reads a record; `--cost N` measures the tracer's own
  cost (plain and traced presses alternated) and is run after any change
  to its trace config. The first trace after a page load often catches
  only a few frames; take the second.
* **Never reboot the TV.** It is also the development machine's display;
  a reboot from the rig crashed the desktop session. Ask the owner.

## Open (2026-10-25)

Worked in `campaigns/tv-performance.md`.


The 2026-10-25 glide slowdown is explained: the 59.9 fps midday reading
was a compositor scroll animation (the browser's own smooth scroll), and
the 35–42 fps afternoon readings were the input system's glide under the
tool's old per-frame probe, which cost it 16–19 fps (run 42, interleaved).
With the present probe or none the glide presents at 60 fps on the Sony,
the same as a compositor smooth scroll (runs 41, 43); the A/A reads 60
against 60 (run 44) and `mc-tv-trace`'s tracing costs nothing measurable
(run 49). Android's side of a glide is now visible per frame: on Home at
60 fps every app frame is "Late Present, Buffer Stuffing" with 36 ms
actual (the WebView runs a frame ahead of the display), the render
thread waits 10 ms a frame in `dequeueBuffer`, half of Chromium's
presented frames are partial, and the Compositor thread waited for a CPU
42 ms in a 1.6 s window. `mc-tv-ab` is the one-command code-version
A/B (its A/A read 60 against 60 on both pages, 2026-10-26). Still open
in the campaign: a reveal that scrolled 156 px under the glide where
the smooth variant scrolled 88.

A page served to a remote player starts no gamepad source
(`inputSources` in `assets/js/input/index.js`; the TV app is driven by
the remote, and its Settings → Controls speaks only of keys). The
WebView's `Gamepad polling thread` runs about 250 times a second while a
page holds `gamepadconnected` listeners, with no gamepad in use (67 ms
running and 45 ms runnable in a 1.6 s glide window); with the source
stopped the thread stopped, and the glide read 60 against 60 on both
pages either way (run 50, 2026-10-26), so the thread's absence is
housekeeping at 60 fps, not a measured gain. A trace of the TV page
shows no such thread now.

Also open: the Home hero's memory saving on the TV is estimated (about 66
to 16 MB on Home), not measured. The package's only process reads 79–83
MB PSS on Home and the library at `f635aae4` with Graphics 0, so the
WebView renderer's memory, where the bitmap lives, is accounted somewhere
else on this TV; find where before comparing the commits before and
after `e84dfd99`.
