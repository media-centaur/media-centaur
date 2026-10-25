---
status: planning
opened: 2026-10-25
last_updated: 2026-10-25
---
# Campaign: TV performance tooling and the glide slowdown

## Glossary

| Term | Meaning |
|---|---|
| **Floor device** | The slowest device the app supports, today the owner's Sony BRAVIA 4K VH21 running the TV app (UIDR-056). |
| **Presented frame** | A frame Android's display compositor (SurfaceFlinger) put on screen, with its timestamp. The measure of what the eye sees. |
| **Glide** | The input system's animated scroll after a D-pad move (`assets/js/input/core/scroll_glide.js`). |
| **Main-thread scroll** | A scroll offset written from JavaScript; each step needs a commit and raster before it can be shown. The glide is one. |
| **Compositor scroll** | A scroll the browser animates itself; it moves already-rastered tiles without the main thread. |
| **Partial frame** | A presented frame that reached the screen without the main thread's update (`PRESENTED_PARTIAL` in Chromium's frame reporter). |
| **Page probe** | The per-frame script `mc-tv-smooth` injects to record the page's scroll offsets during a measurement. |
| **Interleaved A/B** | Two conditions alternated within one run on one device state. |
| **A/A run** | One condition measured repeatedly in one run, to establish the noise between rounds. |
| **Code-version A/B** | An interleaved A/B where the two conditions are two commits of the app. |

## Goal

Make the TV app's performance measurable with tooling the project can
trust, then use it to find and fix why key-press glides dropped from
59.9 fps (midday 2026-10-25) to 35–42 fps (from mid-afternoon on) with
every code version tried. The owner set the order: tooling and technique
first, the root cause after. UIDR-056 makes the TV the performance floor
for every UI change, so the tooling outlives the slowdown.

## Status

Planning. Opened 2026-10-25 as the first follow-up to v2.0.0; nothing
built yet. Resume from M1.

## Principles

1. Measure before changing anything; a fix without a measurement that
   names its cause is not a fix.
2. Only interleaved conditions compare. A number from another run is
   never a baseline (identical code measured 29, 38 and 60 fps on one
   day).
3. A tool's own cost is measured before its numbers are believed.
4. Every repeated procedure becomes a parameterised script in
   `~/scripts/agents/`, documented in `docs/tv-performance.md`.
5. TV time is the owner's: the TV is this computer's display. Run only
   when the owner says it is free; never reboot it.

## What is known (2026-10-25)

* Key-press glides: 59.9 fps on screen at midday; 35–42 fps from
  mid-afternoon with the midday commit, the current code, both debug app
  builds, the old and the new glide, a native-smooth glide, scale 0.5 and
  0.7, the release app stopped, and a freshly booted TV.
* A compositor scroll (`scrollBy` smooth) presented 57–58 fps in every
  state; a bare transform animation 60 fps.
* The page's `requestAnimationFrame` ran every 16.7 ms throughout; main
  frames took about 3.8 ms and started within 0.5 ms; half of the
  presented frames were partial during a glide.
* No DOM mutation on the idle library page; display mode 60 Hz; WebView
  155.0.8059.43 unchanged since 2026-10-23; no CPU frequency cap.
* One probe-free attempt (SurfaceFlinger presents only) produced no
  scroll at all — untested, not a result.
* Runs, traces and the A/B records: `~/.cache/mc-tv-smooth/runs/`
  (`24-old-vs-new-css` is the 59.9 baseline; `30`–`40` the slow
  afternoon), `~/.cache/mc-tv-trace/`.

## Open decisions

1. **Where a code-version A/B runs.** Options: (a) alternate the dev
   server's checkout between two commits (works today; disturbs the
   owner's dev server and any agent in the checkout); (b) a second
   server from a worktree on its own port against a copy of the real
   database (real artwork, nothing shared; needs the copy kept
   read-only and the debug app paired to it). Recommendation: (b).
2. **Whether the glide becomes compositor-driven.** Decided only after
   M4 names the cause; a native-smooth glide measured no better in the
   slow state, so it is not the answer by itself.

## Decisions made

* `2026-10-25` — Tooling and technique first, the slowdown's cause after; the campaign opens as the first follow-up to v2.0.0. (owner)

## Milestones

| | | |
|---|---|---|
| M1 | **Trustworthy measurement.** Measure the page probe's own cost: run the same glides with and without it (presents only, the glide window taken from the key press) and fix the probe to cost nothing on a scroll frame (record only the boxes that scroll, no per-frame `querySelectorAll`). Establish the noise with A/A runs, and make `mc-tv-smooth report` print it beside each comparison. | open |
| M2 | **Android's side of the frame.** Capture a Perfetto trace on the TV (gfx, view, webview, sched, CPU frequency) alongside the Chromium trace, so the render thread's `DrawFn` and the WebView threads' scheduling show as stages; one command (`mc-tv-trace --perfetto` or its own tool). | open |
| M3 | **Code-version A/B as a script.** `mc-tv-ab <ref-a> <ref-b>` serves the two commits per decision 1 and alternates them in rounds, printing one table. | open |
| M4 | **The cause.** With M1–M3, find why glides went from 59.9 to 35–42 fps. | open |
| M5 | **The fix and its guard.** Fix the cause; add whatever check would have caught it (a stored baseline the A/A noise bounds, or a rule in `docs/tv-performance.md` with a test where checkable). | open |
| M6 | **The hero's memory on the TV.** Measure the debug app's memory on Home before and after `e84dfd99` (estimated about 66 → 16 MB). | open |

Every milestone that changes an existing system runs the campaign
procedure and records each step here.

## Completion criteria

* `mc-tv-smooth` and `mc-tv-trace` measure without perturbing the scroll
  they measure, and report the noise band with every comparison.
* Android's render-thread timing is visible per frame in one command.
* A code-version A/B is one command.
* The glide slowdown's cause is named and fixed, with key-press glides
  back at 60 fps on the Sony in an interleaved run against the slow code.
* `docs/tv-performance.md` carries the method and any new standing rule.

## Pointers

* `docs/tv-performance.md` — the device, the standing rules, measuring;
  its Open section is this campaign's starting point.
* `decisions/user-interface/2026-10-25-056-the-tv-app-is-the-performance-floor.md`
* `~/scripts/agents/mc-tv-smooth`, `mc-tv-trace`, `mc-tv` (`check-16k`,
  `off`, `hdmi`), `mc-tv-stress`.
* `assets/js/input/core/scroll_glide.js`, `dom_adapter.js` (`revealItem`).
* The debug app: `app.mediacentaur.tv.debug`, paired to the dev server as
  "TV debug (perf rig)" (two rows with that name exist in the real
  database's players).
