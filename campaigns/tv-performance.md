---
status: in-progress
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

In progress; the TV in standby after the 2026-10-25 night runs (44, 45).
The slowdown is explained and confirmed on the TV: the old page probe
cost the glide 16–19 fps (run 42), and the 59.9 baseline was a
compositor scroll it could not slow. The JS glide presents at 60 fps on
the Sony with the new probe or none (runs 41, 43), the A/A reads 60
against 60 (run 44), and `mc-tv-trace`'s tracing cost nothing
measurable in two traced glides (run 45). M1, M4 and M5 are done. Next:
M2 (Perfetto; `mc-tv-trace` reads presents and converges the held-key
expression), then M3, with decisions 2–4 open for the owner.

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

### Read from the stored data on 2026-10-25 evening (no TV)

* **The 59.9 baseline did not measure the JS glide.** The per-frame
  scroll offsets in `24-old-vs-new-css` ramp up then down (steps 2, 11,
  10, 14, 17, 42, 25, 56, 29, 58 … 30, 10, 11, 1 px): an eased curve. Every
  afternoon run decays from its first step (73, 82, 56, 41, 31 … 1, 1, 1
  px): the exponential glide of `scroll_glide.js`, which can produce no
  other shape. The midday Chromium traces (`10-41-*`) show 31
  `ScrollTree::OnScrollOffsetAnimated` frames, an `ElementAnimations`
  run state named `ScrollOffset-6-5`, 3–5 main-thread commits per glide
  and no `RequestAnimationFrame` event: the compositor animated the
  scroll offset itself. The afternoon trace (`16-00-48`) shows 31
  `RequestAnimationFrame` events, a commit every other frame, 26 of 56
  presented frames partial, no offset animation. The midday session's own
  record (`62e10117`) says it measured "a native smooth-scroll variant of
  the glide" and "the current glide" at 59.9 each; the traces say both
  readings were of the native variant. The page served to the TV did not
  match the working tree the session believed it was measuring.
* **The same mismatch recurs in `40-native-*`.** The "native-smooth
  glide" condition of the afternoon shows the exponential profile, so the
  variant never reached the page; "a native-smooth glide measured no
  better" is not a result.
* **Same distance, longer glide.** A 410 px glide took 384 ms at midday
  (eased, 60 fps, 25 presents) and 583–633 ms in the afternoon
  (exponential, 38–41 fps, 24 presents). The glide's tail of 1 px steps
  is where the time goes; the number of frames presented is the same.
* **Run 41 (2026-10-25 evening, TV, new probe): both animators 60 fps.**
  `--cond base` against `js:native-smooth.js` (the glider's `glide`
  swapped for `scrollTo({behavior: "smooth"})` through
  `window.__scrollGlider`), two rounds, both pages, one page identity
  (`98e7b7ed @4d18f9b2`). The glide: 60 fps on both pages, `animator`
  glide, 410 px in 550 ms on Home. The smooth scroll: 59–60 fps, `eased`,
  410 px in 350 ms. Δ within noise. The TV sat at 15% CPU and 720 MB free,
  against 31–40% and 580–900 MB in the afternoon runs. So in this device
  state the JS glide is not slow, and the afternoon's 35–42 needs another
  explanation than the animator: the old probe (a `querySelectorAll('*')`
  and four layout reads per element on every frame, exactly during the
  glide) or the TV's state. Run 42 reproduces the old probe as a
  condition; run 43 is the probe-cost alternation; run 44 the A/A.
* On the library page one DOWN glide travelled 156 px where the smooth
  variant travelled 88 px for the same press: the glide chases a target
  re-read per tick, the smooth scroll goes to the target as first
  computed. Noted for M5, not pursued here.
* **Run 42 (TV): the old probe was the cause.** `base` against
  `js:oldprobe.js` (the pre-rewrite probe's per-frame
  `querySelectorAll('*')` and layout reads, installed for the page's
  life), two rounds, both pages. Library: 56.5 against 37.4 fps
  (Δ −19.1, noise 7, beyond). Home: 60 against 43.6 (Δ −16.4, noise 0,
  beyond). TV CPU 15% against 40%: the afternoon's "busy TV" was the
  probe. The old probe ran at midday too, but a compositor scroll
  animation needs no main-thread frame, so it could not slow the eased
  scroll measured then. That closes the loop: 59.9 was a compositor scroll
  the probe could not hurt; 35–42 was the JS glide under the probe; 60 is
  the JS glide without it.
* **Run 43 (TV): the new probe costs nothing measurable.** Probed and
  `--no-probe` alternated twice over both pages: 60 fps in every row,
  Δ 0.0. (A first reading of 39.9 on the library page was the no-probe
  window counting a 400 ms idle gap after the glide; the glide without a
  probe is now the first unbroken run of presents, and the stored
  presents re-derive to 60.)
* So the midday-to-afternoon drop compared two animators. In every
  afternoon measurement the JS glide presented at 35–42 fps with about
  half its frames partial: the main thread's scroll write missed the
  compositor's deadline every other frame while the main frame itself took
  under 5 ms (`SendBeginMainFrameToCommit` p50 4.7 ms;
  `EndActivateToSubmitCompositorFrame` p50 7.0 ms against 2.8 at midday).
  Runs 41–43 then measured the same glide at 60 fps with the new probe or
  none, and at 37–44 with the old probe reinstated: the old probe is what
  made the afternoon glide miss its deadline.
* **Run 44 (TV): the A/A.** `base` against `base#2` on the library,
  three rounds, no overrides: 60 against 60 fps, Δ +0.0 (noise 7). The
  one reading off 60 was 53 in the first trial after the app came
  forward; the five that followed were 60.0 with every gap 16.7 ms. On
  an idle TV the noise is one slow first trial, not a spread. A first
  attempt had recorded zero presents in all 36 presses: the TV's input
  app was in front after the evening's handback and SurfaceFlinger
  presents nothing for a layer behind it, while the WebView still
  answers over CDP. `mc-tv-smooth run` now brings the app to the front
  before its first trial; the empty directory was discarded.
* **Run 45 (TV): `mc-tv-trace`'s own cost, none measurable.** Plain
  D-pad presses alternated with presses made under `mc-tv-trace --key`
  (Chromium tracing with the devtools.timeline categories active), no
  page probe in either, each glide read from SurfaceFlinger as the
  longest unbroken run of presents. Plain: four glides, 60.0 fps, 24–31
  presents each, every gap 16.7 ms. Traced: two glides, 60.0 fps, 22–25
  presents, every gap 16.7 ms. Two traced glides are a small sample, but
  neither dropped a frame. Two things learned for M2: a trace attaching
  presents one frame about 450 ms before the key, so the no-probe
  glide window must skip isolated leading presents (the first-unbroken-
  run rule read the glide as empty); and the trace's `PipelineReporter`
  count after the action (54, 58) exceeds the screen's presents (41, 44
  in the same window), so the trace's frame count is not a present
  count and `mc-tv-trace` should read presents the way `mc-tv-smooth`
  does. Data: `~/.cache/mc-tv-smooth/runs/45-trace-cost/presses.jsonl`
  and `trace-{1..8}.json`.
* **Memory, after `e84dfd99` only (M6, half).** The debug app's main
  process on the dev library page: 79 MB PSS; on Home after settling:
  83 MB PSS, Graphics 0. This is the browser process alone, read with
  `dumpsys meminfo <package>`; the WebView's renderer is a separate
  sandboxed process that this read does not cover, and the hero bitmap
  lives there. M6 reads every process whose name starts with the package
  (`dumpsys meminfo` per pid) for both commits.

## Open decisions

1. **Where a code-version A/B runs.** Options: (a) alternate the dev
   server's checkout between two commits (works today; disturbs the
   owner's dev server and any agent in the checkout); (b) a second
   server from a worktree on its own port against a copy of the real
   database (real artwork, nothing shared; needs the copy kept
   read-only and the debug app paired to it). Recommendation: (b).
2. **Whether the glide becomes compositor-driven.** Runs 41 and 43 put
   the JS glide at 60 fps on the Sony, interleaved with a compositor
   smooth scroll at 59–60. Recommendation: keep the glide; nothing
   measured favours replacing it, and the two native routes fail under a
   held key (`scroll_glide.js` moduledoc). The owner closes this.
3. **What the campaign's goal becomes.** The glide never slowed; the
   tool slowed it. Recommendation: the Goal's second half becomes "keep
   the tooling from perturbing what it measures", which M1 delivered and
   M2 extends to `mc-tv-trace`. The owner rewrites or confirms.
4. **The 156 px against 88 px reveal.** On the library page one DOWN
   press scrolled 156 px under the glide and 88 px under the smooth
   variant (run 41). The glide re-reads its reachable target per tick, so
   a layout change mid-glide moves it. Options: investigate as its own
   small milestone, or leave it. Recommendation: investigate after M2; it
   is the owner's eye that decides whether the glide lands where it should.

## Decisions made

* `2026-10-25` — Tooling and technique first, the slowdown's cause after; the campaign opens as the first follow-up to v2.0.0. (owner)
* `2026-10-25` — A measurement row records what it measured: the served bundle's digest and HEAD, each glide's distance and the animator read from its step profile; the probe is a scroll-event listener, not a per-frame poll; a repeated `--cond` is its own condition. (M1, `mc-tv-smooth`)
* `2026-10-25` — No TV in this session, by the owner's word; every TV-dependent step is queued, not skipped. (owner)
* `2026-10-25` — Later the same evening the owner freed the TV; runs 41–43 ran, then the owner asked for a pause that keeps the data whole: the chain stopped between runs, run 44 untouched. (owner)
* `2026-10-25` — The glide slowdown's cause is the old page probe, confirmed interleaved on the TV (run 42); the fix is the scroll-event probe and the guard is the standing rule that a tool's cost is measured with `--no-probe` before its numbers are believed. (M4, M5)
* `2026-10-25` — `window.__scrollGlider` is the page's debug handle for swapping the animator under measurement. (commit `4d18f9b2`)
* `2026-10-25` — Night: the owner freed the TV for whatever runs the campaign needed and asked for it off afterwards; runs 44 and 45 ran, Home's memory was read for the current commit, then `mc-tv off`. (owner)
* `2026-10-25` — `mc-tv-smooth run` brings the app to the front before measuring; a run after a handback had recorded no presents at all. (M1, `mc-tv-smooth`)
* `2026-10-25` — `mc-tv-trace`'s frame count is not a present count (54 against 41 on one glide); M2 gives it SurfaceFlinger's presents and a glide window that skips the trace's own leading present. (run 45)

## Milestones

| | | |
|---|---|---|
| M1 | **Trustworthy measurement.** Measure the page probe's own cost: run the same glides with and without it (presents only, the glide window taken from the key press) and fix the probe to cost nothing on a scroll frame (record only the boxes that scroll, no per-frame `querySelectorAll`). Establish the noise with A/A runs, and make `mc-tv-smooth report` print it beside each comparison. | ✅ 2026-10-25 — tool rewritten (scroll-event probe, `--no-probe`, `px/glide`, `animator`, `page id`, `fps range`, `Δ vs first`, repeated `--cond` as A/A); probe cost zero on the TV (run 43, Δ 0.0 both pages); A/A on the library (run 44, three rounds): 60 against 60, Δ +0.0, the only off-reading 53 in the first trial after the app came forward, so the noise band on an idle TV is one slow first trial. `run` now brings the app to the front first (a run after a handback had recorded zero presents). |
| M2 | **Android's side of the frame.** Capture a Perfetto trace on the TV (gfx, view, webview, sched, CPU frequency) alongside the Chromium trace, so the render thread's `DrawFn` and the WebView threads' scheduling show as stages; one command (`mc-tv-trace --perfetto` or its own tool). Also: `mc-tv-trace` reads the screen's presents beside its trace (run 45 showed its frame count is not a present count) and shares the held-key expression with `mc-tv-smooth`. | open — tracing cost measured first (run 45): none in two traced glides |
| M3 | **Code-version A/B as a script.** `mc-tv-ab <ref-a> <ref-b>` serves the two commits per decision 1 and alternates them in rounds, printing one table. | open |
| M4 | **The cause.** With M1–M3, find why glides went from 59.9 to 35–42 fps. | ✅ 2026-10-25 — the old page probe slowed the JS glide by 16–19 fps (run 42, interleaved on the TV); the 59.9 baseline was a compositor scroll the probe could not slow (runs 41–42, step profiles and Chromium traces). |
| M5 | **The fix and its guard.** Fix the cause; add whatever check would have caught it (a stored baseline the A/A noise bounds, or a rule in `docs/tv-performance.md` with a test where checkable). | ✅ 2026-10-25 — the fix is the scroll-event probe (M1); the guard is the Measuring rule in `docs/tv-performance.md` that a tool's own cost is measured with `--no-probe` before its numbers are believed, plus the `animator` and `page id` columns that would have shown both of the day's mix-ups. No stored baseline: principle 2. |
| M6 | **The hero's memory on the TV.** Measure the debug app's memory on Home before and after `e84dfd99` (estimated about 66 → 16 MB). | open — after-half read 2026-10-25 for the browser process only (83 MB PSS on Home, 79 on the library); the renderer process, where the bitmap lives, needs a per-pid read, and the before-half needs M3's second server |

Every milestone that changes an existing system runs the campaign
procedure and records each step here.

### M1 — Trustworthy measurement

1. **Scope.** In: (a) the page probe records scroll events instead of
   polling every element each frame; (b) each glide records its
   distance, its step profile and which animator the profile belongs to
   (the exponential glide or an eased browser scroll); (c) each trial
   records the identity of the page it measured (the served `app.js`
   digest, the checkout's HEAD and whether it was dirty); (d) `--no-probe`
   measures presents only, so the probe's own cost is one interleaved
   run; (e) `report` prints each condition's spread across rounds and,
   beside every comparison, the difference against that spread; (f) a
   repeated `--cond` is a separate condition, so an A/A run is one
   command. Out: Perfetto (M2), serving two commits (M3). Added to the
   original scope: (b) and (c), because both mix-ups of 2026-10-25 were
   a page that did not match the code the session believed it measured,
   and neither the row nor the trial recorded enough to notice.
2. **Research.** The present probe runs `querySelectorAll('*')` and four
   layout reads per element on every animation frame for 1.3 s, on the
   main thread, exactly where a main-thread scroll is scored. The
   afternoon Chromium trace, taken without the probe, shows the same
   partial-frame glide, so the probe is not the cause of the 35–42; its
   cost is still unmeasured. A `scroll` event fires once per frame per
   scroller that moved and nothing when nothing moves, which is the
   "record only the boxes that scroll" the scope asked for. The glide's
   shape is decisive for animator identity: `scroll_glide.js` closes a
   fixed fraction of the remaining distance per frame, so its largest
   step is always among its first; a browser smooth scroll peaks in the
   middle. In dev the bundle has no digest in its URL, so identity is a
   digest of the fetched `app.js` text, taken once per trial before the
   presses. `mc-tv eval` opens and closes a DevTools session per call, so
   no session is attached during a press.
3. **Design decisions.** None for the owner; the choices above follow
   from the scope.
4. **Design unification.** Core idea: a measurement is a record of what
   was measured, so every number in a row traces back to a page identity,
   a condition and the scroll events that moved. Greenfield shape: a trial
   is (page identity, condition, device state, presses); a press stores
   the presents and the raw scroll events, and distance, duration, step
   profile and animator are derived from the events at report time, so
   there is one source of truth per glide. Incoherences found: (i) the
   condition string served as both override spec and row label, so two
   identical specs merged into one row — fixed: a condition is (label,
   kind, source), the label suffixed `#2` when the spec repeats; (ii) two
   fps definitions threatened (glide-window and press-window) — resolved
   to one: fps is presents over the span from the first to the last
   present inside the glide, and without the probe the glide is the whole
   press window, which on an idle page coincides; (iii) the per-frame
   trace strings stored today are a second representation of what the
   scroll events record — dropped, not kept beside the new shape, so
   `report` reads only new runs (the stored `report.md` files remain);
   (iv) the held-key simulator exists in both `mc-tv-smooth` and
   `mc-tv-trace` — pre-existing, scheduled for M2, which touches
   `mc-tv-trace`. Coherence cost: old `trials.jsonl` files are no longer
   reportable by the tool. Accepted: principle 2 forbids comparing across
   runs anyway.
5. **Implementation plan.** One file, `~/scripts/agents/mc-tv-smooth`:
   (1) `PROBE` becomes a capturing passive `scroll` listener that pushes
   `[t, box, top, left]` per event, plus the long-task observer; the box
   is named by its tag, id and first class; `--no-probe` skips it;
   (2) `press()` stores `events`, `presents` (all in the window) and the
   gaps, with the glide span taken from the events when present;
   (3) `trial()` records `page_id` = {`bundle`: digest of the served
   `app.js`, `head`, `dirty`} before the presses; (4) conditions are
   parsed once into (label, kind, source); (5) `summarize()` derives
   distance, settle, step profile and animator per glide; (6) `report`
   adds `px/glide`, `animator`, `page` identity, and per condition the
   fps spread across rounds and `Δ vs first (noise)`; (7) the moduledoc
   says what each new column means and how the probe-cost run and an A/A
   run are invoked; (8) `docs/tv-performance.md` Measuring gains the
   animator and page-identity checks. Verified offline by a synthetic
   `trials.jsonl` through `report`; the TV runs (probe cost, A/A) wait
   for a free TV.
6. **Plan unification.** Step 2 stored present times and the gaps
   between them: two representations. Fixed: a press stores present
   times (ms from the first) and the scroll events only; gaps, fps,
   stalls, distance, settle and animator are derived in `summarize()`,
   which both the live per-trial line and `report` call. Each trial
   records `probe: true|false` so a report says why its scroll columns
   are empty. No old path remains: the per-frame `TRACE` constant goes.
7. **Execution.** `~/scripts/agents/mc-tv-smooth` rewritten; Python and
   the embedded JavaScript compile; `report` run on the midday and two
   afternoon runs converted to the new trial shape prints `eased` 59.9
   against `glide` 35–40, Δ beyond noise, the A/A pair's own spread
   (1.6–5.4 fps) and the dirty-tree marker. `docs/tv-performance.md`
   Measuring and Open updated. On the TV the same evening: run 41 (glide
   against `js:native-smooth.js`), run 42 (base against `js:oldprobe.js`),
   run 43 (probed and `--no-probe` alternated into one directory). The
   animator rule moved from "largest step among the first two" to "the
   opening third outweighs the middle third" after a jittered glide
   mislabelled; the no-probe glide window became the first unbroken run
   of presents after an idle gap inflated one row. Both are derivations,
   re-run over the stored events. Run 44 (A/A, later the same evening):
   `base` against `base#2` on the library, three rounds, 60 against 60
   fps, Δ +0.0, one trial at 53 (the first after the app came forward);
   the first attempt recorded zero presents in every trial because the
   TV's input app was in front after the handback, so `cmd_run` now
   calls `mc-tv launch` before its first trial and the empty directory
   was discarded. M1 closed.

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
