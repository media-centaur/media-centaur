---
status: in-progress
opened: 2026-10-25
last_updated: 2026-10-26
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
| **Action** | The one thing a measurement does to the page: a D-pad key press over adb, a held key simulated in the page, or a JavaScript expression. |
| **Chromium trace** | Chromium's own trace of the WebView's threads and frame pipeline, recorded over the DevTools protocol (`Tracing.start`). Its clock is Chromium's. |
| **System trace** | Android's Perfetto trace of the whole device: kernel scheduling and CPU frequency (ftrace), framework slices (atrace categories such as `gfx`, `view`, `webview`) and SurfaceFlinger's frame timeline. One clock for everything in it. |
| **Frame timeline** | SurfaceFlinger's per-frame record on Android 12 and later: the time budget an app frame was given, the time it took, whether it presented on time, and who caused a late one (the app or SurfaceFlinger). |
| **Render thread** | The Android app's `RenderThread`, which draws the WebView's frame into the window each vsync (`DrawFrames`, the WebView draw functor). Its time is invisible to the Chromium trace's pipeline stages. |
| **Runnable time** | Time a thread spent ready to run but without a CPU; read from the system trace's scheduler data. |
| **Background services** | Everything a running host does on its own, with no page asking: file watchers, the import and image pipelines, auto-grab, Oban's queues and cron, relay connections and sync, playback recovery, the self-update check, boot backfills and the PubSub listeners that react to library and release events. The bootstrap key `background_services` turns all of it off at once. |
| **Measurement server** | A host started with `background_services = false` against a database copy, so that it serves pages and does nothing else. One per commit under test. |
| **Database copy** | A `sqlite3 .backup` of the dev database at its own path; a measurement server's migrations and writes land there and nowhere else. |
| **Host** | The URL the TV app loads its pages from; `mc-tv launch --host <url>` re-points it. In an A/B each condition is a host. |

## Goal

Make the TV app's performance measurable with tooling the project can
trust, and keep that tooling from perturbing what it measures: every
number a tool prints traces back to the page it measured, the condition,
and a measured cost of the tool's own presence. The campaign opened on a
glide that seemed to drop from 59.9 to 35–42 fps on 2026-10-25; the
tool's old probe was the cause, which is why the goal is the tooling.
UIDR-056 makes the TV the performance floor for every UI change, so the
tooling outlives the slowdown. (Rewritten 2026-10-25 by decision 3.)

## Status

In progress; the TV in standby after the 2026-10-26 sessions. M1, M2,
M3, M4, M5 and M8 are done. The slowdown is explained (the old page
probe, run 42); the glide presents at 60 fps on the Sony (runs 41, 43,
44, 49); `mc-tv-trace` records one Perfetto system trace at zero
measured cost; the gamepad poller costs nothing on screen (run 50);
`mc-tv-ab <ref-a> <ref-b>` is the one-command code-version A/B, built
on the new `background_services` bootstrap key (commit `6095f146`),
and its A/A read 60 against 60 on both pages. No decision is open.
M9 is done: a remote player's page starts no gamepad source (Settings →
Controls speaks only of keys there, decision 11), and trace
`20261026T201413` of a Home glide on the dev server shows no polling
thread in any process. The measurement tooling learned to name the
host that served a measured page, to find the debug app's DevTools
socket, to point the app back at the dev server after `mc-tv-ab down`,
to land a trace on a gliding press (`mc-tv-trace --glide`), and to
print the threads a trace lacks. M6 is measured (the hero commit saves
about 24 MB of the page's 199 on the TV, run `20261026-201555`) and M7
is closed (both animators land on the same position; the 156 against
88 was a starting-position difference in run 41). Every milestone is
done and every completion criterion is met; the campaign is ready to
close once the owner has read the two leftovers: UP onto the first
library row leaves the toolbar scrolled off (a design call), and the
wiki sentence for Settings → Controls on the TV is committed locally,
to push when the change ships.

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
  `dumpsys meminfo <package>`. A second read later that night, per pid
  over every process whose name starts with the package, found only that
  one process (82 MB on the library, 79 on Home at `f635aae4`, Graphics
  0): the WebView's renderer is not named after the package on this TV,
  or runs in-process. M6 finds where the renderer's memory is accounted
  (`ps -A` for `sandboxed_process`, `dumpsys meminfo` by the WebView
  package, or `dumpsys gfxinfo`) before it compares the two commits.

* **Runs 46–49 (TV, 2026-10-26): `mc-tv-trace`'s cost, and a first
  look at Android's side.** The tracer's first config cost the glide
  8.3 fps; bisecting found no data source at fault and the DevTools
  session opened for the action mark right before the key at fault on
  its own (6.5 fps). Without it the whole trace costs nothing (Δ −0.0,
  noise 3.8). One Home glide under the finished tool: 60 fps on screen;
  every app frame "Late Present, Buffer Stuffing" with 36 ms actual
  (one frame of latency, no missed deadline); the render thread waits
  10 ms a frame in `dequeueBuffer`; half of Chromium's presented frames
  partial; over 1.6 s the Compositor thread was runnable 42 ms and the
  gamepad poller ran 67 ms and waited 45 ms. Records:
  `~/.cache/mc-tv-trace/4[6-9]-*`.
* A DevTools session opened and closed right before an action costs the
  glide that follows 6.5 fps. `mc-tv-smooth` installs its probe through
  such a session, then clears presents over adb before the key (about
  200 ms), and measured zero cost that way (run 43); the mechanism is
  not understood (a focus or visibility change on detach is the
  suspect). `hold` and `js` actions run through the same session at
  the action itself, in both tools alike; their absolute fps carries
  whatever that costs, and only comparisons within a tool hold for them.

## Open decisions

None. Decisions 1–11 are taken (see *Decisions made*); the reveal
became M7, the gamepad poller M8, the gamepad source on remote players
M9.

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
* `2026-10-25` — The owner approved the four open recommendations at once: (1) a code-version A/B runs from a second server in a worktree on its own port against a read-only copy of the real database, never by switching the dev server's checkout; (2) the glide stays the input system's main-thread glide, nothing measured favours a compositor route and both native routes fail under a held key; (3) the Goal's second half is "keep the tooling from perturbing what it measures" (rewritten above); (4) the 156 px against 88 px reveal is investigated after M2, as M7, with the owner's eye deciding where a glide should land. (owner)
* `2026-10-25` — The TV is used when it is asleep or already in the campaign's hands, never when someone else has it on; it goes back to standby when the session's TV work is done. (owner)
* `2026-10-26` — `mc-tv-trace` is rewritten in Python; both TV tools import one module, `~/scripts/agents/_tv.py`, for the device, the page, the actions and the screen's presents; dependencies are declared inline and run through `uv`. (owner, M2 decision i)
* `2026-10-26` — From here on every TV interaction is asked for first, one question per TV session, and the TV goes back to standby after it. (owner)
* `2026-10-26` — Later: the TV may be woken for tests without asking as long as no sound comes out of it, and goes to standby when done. (owner)
* `2026-10-26` — The DevTools trace is dropped: the WebView's Chromium track events join the Perfetto system trace on this TV, so one trace holds Chromium and Android on one clock. (M2 decision ii, probe)
* `2026-10-26` — `mc-tv-trace` has no action mark: the DevTools session it took right before the key cost 6.5 fps; the window anchors on the screen's first present. Each tool carries its own cost check (`--no-probe`, `--cost`). (M2, runs 47–49)
* `2026-10-26` — The page walks live once, in `_tv.WALKS`, with each press's glide flag. (M2)
* `2026-10-26` — Decision 5 approved: the gamepad poller is measured first, as M8, before M3, M6 and M7; M3 (a worktree server on its own port against a read-only copy of the database) is approved to proceed after it. (owner)
* `2026-10-26` — The gamepad poller stays as it is: with the page's listeners gone Chromium's thread stops, and the glide reads 60 against 60 either way (run 50). (M8)
* `2026-10-26` — After a TV session the display goes back to the PC's HDMI input when the owner asks for it, standby otherwise. (owner)
* `2026-10-26` — Decision 6: the Android TV app needs no gamepad support for now; a page served to a remote player does not start the input system's gamepad source. Becomes M9. (owner)
* `2026-10-26` — Decision 7: a measurement server is made inert by one bootstrap key in its override TOML, `background_services = false`, beside `showcase_mode`; nothing in the database copy can switch background work back on. The test-only start flags converge on it (M3 design). (owner, M3)
* `2026-10-26` — Decision 8: the A/B runs two worktree servers on their own ports (2161, 2162), each against its own database copy; a round switch re-points the TV app (`mc-tv launch --host`). The paired TV needs no re-pairing: admission is a signed session cookie, dev's signing key and salt are fixed, cookies are per host not per port, and the copy carries the player row. (owner, M3)
* `2026-10-26` — Decision 9: each server's database is a `sqlite3 .backup` of the dev database at its own path; artwork is the real image cache, shared, nothing in an inert server writes it. (owner, M3)
* `2026-10-26` — Decision 10: the measurement servers bind `0.0.0.0` for the run, behind the paired-player gate, as the dev server already does. Accepted with reluctance; they are stopped when the run ends. (owner, M3)
* `2026-10-26` — Decision 11: Settings → Controls on a remote player speaks only of keys: no Pad slot in a binding row, no gamepad glyph choice. (owner, M9)

## Milestones

| | | |
|---|---|---|
| M1 | **Trustworthy measurement.** Measure the page probe's own cost: run the same glides with and without it (presents only, the glide window taken from the key press) and fix the probe to cost nothing on a scroll frame (record only the boxes that scroll, no per-frame `querySelectorAll`). Establish the noise with A/A runs, and make `mc-tv-smooth report` print it beside each comparison. | ✅ 2026-10-25 — tool rewritten (scroll-event probe, `--no-probe`, `px/glide`, `animator`, `page id`, `fps range`, `Δ vs first`, repeated `--cond` as A/A); probe cost zero on the TV (run 43, Δ 0.0 both pages); A/A on the library (run 44, three rounds): 60 against 60, Δ +0.0, the only off-reading 53 in the first trial after the app came forward, so the noise band on an idle TV is one slow first trial. `run` now brings the app to the front first (a run after a handback had recorded zero presents). |
| M2 | **Android's side of the frame.** Capture a Perfetto trace on the TV (gfx, view, webview, sched, CPU frequency) alongside the Chromium trace, so the render thread's `DrawFn` and the WebView threads' scheduling show as stages; one command (`mc-tv-trace --perfetto` or its own tool). Also: `mc-tv-trace` reads the screen's presents beside its trace (run 45 showed its frame count is not a present count) and shares the held-key expression with `mc-tv-smooth`. | ✅ 2026-10-26 — `mc-tv-trace` rewritten in Python over one Perfetto system trace (the WebView's Chromium events join it, so the DevTools trace is gone): screen presents first, frame timeline, Chromium pipeline, render thread, per-thread running/runnable, CPU frequency; `_tv.py` shared with `mc-tv-smooth`. Its cost measured with `--cost`: zero (Δ −0.0, noise 3.8) once the DevTools action mark, which alone cost 6.5 fps, was removed. A Home glide: 60 fps, 24 frames buffer-stuffed, `dequeueBuffer` 10 ms a frame. |
| M3 | **Code-version A/B as a script.** `mc-tv-ab <ref-a> <ref-b>` serves the two commits per decision 1 and alternates them in rounds, printing one table. | ✅ 2026-10-26 — `~/scripts/agents/mc-tv-ab` (`up`, `run`, `down`, `status`): two measurement servers from worktrees on 2161/2162, each `background_services = false` (new bootstrap key, commit `6095f146`; the test-only start flags converged on it) against a `sqlite3 .backup` of the dev database with the real data directory; `mc-tv-smooth --cond host:<label>` re-points the TV app per round and `page id` names each host's HEAD. The A/A (`mc-tv-ab HEAD HEAD`, run `20261026-141657`): 60 against 60 on both pages, Δ +0.0, noise 0. |
| M4 | **The cause.** With M1–M3, find why glides went from 59.9 to 35–42 fps. | ✅ 2026-10-25 — the old page probe slowed the JS glide by 16–19 fps (run 42, interleaved on the TV); the 59.9 baseline was a compositor scroll the probe could not slow (runs 41–42, step profiles and Chromium traces). |
| M5 | **The fix and its guard.** Fix the cause; add whatever check would have caught it (a stored baseline the A/A noise bounds, or a rule in `docs/tv-performance.md` with a test where checkable). | ✅ 2026-10-25 — the fix is the scroll-event probe (M1); the guard is the Measuring rule in `docs/tv-performance.md` that a tool's own cost is measured with `--no-probe` before its numbers are believed, plus the `animator` and `page id` columns that would have shown both of the day's mix-ups. No stored baseline: principle 2. |
| M6 | **The hero's memory on the TV.** Measure the debug app's memory on Home before and after `e84dfd99` (estimated about 66 → 16 MB). | ✅ 2026-10-26 — the page is two processes (the app's and the WebView renderer's, never in the package's meminfo); `mc-tv-smooth` reports `app+rend MB` per trial. Run `20261026-201555` (`mc-tv-ab e84dfd99~1 e84dfd99`, Home, two rounds): 198.8 MB before, 174.4 after — about 24 MB saved (renderer 108 → 92, app 91 → 82), replacing the estimate of about 50 (66 → 16). Glides 60 against 60 either way. |
| M8 | **The gamepad poller.** Measure what Chromium's gamepad polling thread costs a glide on the TV (interleaved, both pages, the input system's gamepad source stopped as the condition); if beyond noise, stop paying it when no gamepad is present. | ✅ 2026-10-26 — measured (run 50, both pages, two rounds): 60 against 60, Δ +0.0, with the source stopped; the poller stops when the page's gamepad listeners go, and at the floor's 60 fps it costs nothing the screen shows. No change to the input system (principle 1); the handle `window.__gamepadSource` stays (commit `c7f5c097`). |
| M7 | **The 156 px against 88 px reveal.** On the library one DOWN press scrolled 156 px under the glide and 88 px under the smooth variant (run 41): the glide re-reads its reachable target per tick, so a layout change mid-glide moves it. Find what moves the target and whether the glide lands where the owner's eye says it should. | ✅ 2026-10-26 — nothing moved a target: run 41's own events show both animators landing on 156 (DOWN) and 68 (UP) every round; the smooth trial had started at 68 instead of 0. Reproduced at HEAD on the TV with a per-step read of scrollTop under both animators in both orders: identical, 0 → 0 → 0 → 156 → 156 → 156 → 68. Left for the owner's eye: UP onto the first library row stops at 68, the toolbar above the grid stays scrolled off — "nearest" never returns the page to its top. |
| M9 | **No gamepad source on a remote player.** A page served to a remote player (`html[data-player="remote"]`) does not start the input system's gamepad source (decision 6); the measurement handle `window.__gamepadSource` goes with it, its only purpose was M8. | ✅ 2026-10-26 — `a259085f`: `inputSources(remotePlayer(html), …)` gives a remote player's page the keyboard source alone; the handle and `exposeGamepadSource` gone; Settings → Controls takes `gamepad` (decision 11) with its story variation and a test mounting as a paired LAN player. Confirmed on the TV: trace `20261026T201413`, a Home glide at 60 fps on `6708c0af @d16c35f8 dev`, no `Gamepad polling thread` in any process of the trace (the report now prints an `absent from the trace` line; three non-gliding traces `201117`, `201133`, `201205` agree). |

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

### M2 — Android's side of the frame

1. **Scope.** In: (a) `mc-tv-trace` records a system trace of the
   action beside its Chromium trace: scheduler and CPU frequency, the
   `gfx`, `view` and `webview` atrace categories, the debug app's own
   atrace slices, and SurfaceFlinger's frame timeline; (b) its report
   gains, per presented frame, the frame timeline's verdict (on time or
   late, app or SurfaceFlinger at fault) and, per WebView thread over
   the action window, running and runnable time and the heaviest
   slices, the render thread included; (c) `mc-tv-trace` reads the
   screen's presents the way `mc-tv-smooth` does and prints that fps
   first, with the glide window skipping the stray present a trace
   attaching makes (run 45); (d) the held-key expression and the
   action and present-reading code exist once, shared by both tools;
   (e) `docs/tv-performance.md` Measuring says what the new report
   shows and how to read a late frame's attribution. Out: serving two
   commits (M3), the reveal (M7), the hero's memory (M6). Dropped: a
   Perfetto UI workflow for humans is not built; the trace file is kept
   for `ui.perfetto.dev` and the report is for the agent.
2. **Research.** Perfetto ships in Android 12 and `adb shell perfetto`
   records from the shell; its simple mode takes atrace categories on
   the command line (`--time`, `--app`), and normal mode takes a text
   config (`-c - --txt`) which is what the frame timeline data source
   (`android.surfaceflinger.frametimeline`, Android 12 and later) and
   `atrace_apps` need; output goes under `/data/misc/perfetto-traces/`
   and is pulled with `adb pull` (perfetto.dev: CLI reference, atrace,
   frame timeline). The frame timeline's SQL tables
   (`actual_frame_timeline_slice`, `expected_frame_timeline_slice`)
   carry `jank_type`, `present_type`, `on_time_finish` and
   `layer_name` per app frame; thread scheduling is the `thread_state`
   table. Reading a system trace from a script is the `perfetto`
   Python package, which downloads a pinned `trace_processor` binary;
   this machine has `uv`, so a script declares that dependency inline
   (PEP 723) and installs nothing system-wide. Whether the WebView's
   own Chromium track events join the system trace is not documented
   for WebView (Chrome needs a `chrome://flags` entry on user builds);
   if they do for a debuggable app, one trace holds everything on one
   clock and the Chromium trace over CDP can go. Unverified until the
   TV is free: that `perfetto` runs on the Sony with `traced` enabled;
   that the `webview` category and the frame timeline produce data for
   the debug app; whether the WebView's track events appear. The
   Chromium trace's timestamps and the system trace's are different
   clocks; the action mark (`console.timeStamp`) and the first present
   after the action anchor the two if both traces stay.
3. **Design decisions.** (i) *Language.* `mc-tv-trace` is Node (for the
   DevTools WebSocket); the system trace is read in Python; and the
   action and present-reading code it must share with `mc-tv-smooth`
   is Python. Options: (a) keep Node and add a Python helper it calls
   for the system trace, with the held-key expression in a file both
   languages read; (b) rewrite `mc-tv-trace` in Python (the DevTools
   client is thirty lines over the `websockets` package, declared
   inline like `perfetto`), so both tools import one module for the
   action, the presents and the held key. Recommendation: (b); one
   language, one shared module, no cross-language file. Cost: the
   Node file's summary logic (about 240 lines) is ported, not kept.
   (ii) *If the WebView joins the system trace*: drop the CDP trace
   and read Chromium's pipeline stages from the system trace too.
   Decided by the TV probe, not by the owner. (iii) *The agent's
   dependency manager* is `uv` with inline script metadata; nothing is
   installed into the system Python.
4. **Design unification.** Core idea: a TV measurement is one action on
   one page, observed by the screen (its presents) and explained by
   traces; `mc-tv-smooth` repeats and compares such observations,
   `mc-tv-trace` explains one. Greenfield shape: one Python module
   `~/scripts/agents/_tv.py` (the underscore convention of `_cdp.js`)
   owns the device (the debug app, its layer, `adb` through `mc-tv`),
   the page (eval through `mc-tv eval`, connected and quiet waits, page
   identity), the actions (key over adb, the held-key expression, a JS
   expression) and the screen observation (clear, act, read presents,
   and the glide window). `mc-tv-smooth` imports it and keeps the
   conditions, the probe, trials and the comparison report;
   `mc-tv-trace` imports it and adds the two recordings and the
   explanation. A trace record is one directory
   `~/.cache/mc-tv-trace/<stamp>/` holding `chromium.json`,
   `system.perfetto-trace`, `presents.json` and the printed report; a
   run stays `~/.cache/mc-tv-smooth/runs/<name>/` (a run and a record
   are different things; not merged). Diff against the code: (a) clean
   seams used as they are: `mc-tv` for adb, launch, the DevTools
   forward and `eval`; `mc-tv-smooth`'s `press`/`trial` split; the Node
   summary's PipelineReporter and thread-table logic, ported line for
   line. (b) Duplications unified into `_tv.py`: the held-key
   expression (Python and Node copies), the app id and layer name,
   the presents parse (in `mc-tv-smooth` and the run-45 scratch
   script), the DevTools target lookup. (c) Incoherences decided: (i)
   the glide window without scroll events had two rules, the first
   unbroken run of presents in `mc-tv-smooth` and the longest in the
   run-45 script; one rule, the longest unbroken run, lives in `_tv.py`
   and `mc-tv-smooth` adopts it (fix now; the stored runs re-derive the
   same, an idle gap after the glide was the only case and the glide is
   still the longest run). (ii) `mc-tv-trace`'s headline was a trace
   count; the report leads with the screen's presents and names the
   PipelineReporter count as pipeline frames (fix now). (iii) Page
   evaluation in Python reaches the page two ways: one-shot through
   `mc-tv eval` (the owner's CLI, Node, in `_tv.py`), and inside
   `mc-tv-trace`'s own tracing session, whose evaluates must be on the
   session (the action mark is on its clock). Accepted and documented
   in `_tv.py`; the one-shot path is the owner's tool, the session is
   the trace. (iv) `mc-tv-stress` carries its own `APP` constant and
   shell probe; it is a different rig (incidents, not frames) and is
   left alone, named here so it is not an orphan. (v) The Chromium and
   system traces are two clocks; if the WebView's track events join the
   system trace the Chromium trace goes and the clock question with it,
   otherwise the action mark and the first present after it anchor the
   two. Decided by the probe. Coherence cost: `mc-tv-trace` is
   rewritten in Python (about 300 lines, its summary ported) and
   `mc-tv-smooth` moves about eighty lines into `_tv.py` and becomes a
   `uv` script like its sibling; the owner's call, recorded under
   decision (i) above.
   **Research, continued (TV probe 2026-10-26 morning, owner's
   go-ahead).** `perfetto` is at `/system/bin/perfetto` on the Sony,
   `traced` and `traced_probes` run, `persist.traced.enable` is 1, and a
   text config over stdin records and writes under
   `/data/misc/perfetto-traces/` (4.9 MB for four seconds). The WebView's
   Chromium track events **do** join the system trace without any flag:
   the browser process (`app.mediacentaur.tv.debug`) and the renderer
   (`com.google.android.webview:sandboxed_process0`) both emit
   `PipelineReporter` with its `frame_reporter.*` args and its stage
   children, plus `cc`, `viz`, `blink`, `v8`, `devtools.timeline` and
   `input` slices, on `CrRendererMain`, `Compositor`,
   `ThreadPoolForegroundWorker`, `VizWebView` and
   `Chrome_InProcGpuThread`. So decision (ii) resolves to: the DevTools
   trace goes, one system trace holds Chromium and Android on one clock,
   and `websockets` is not needed. The render thread is visible:
   `HardwareRenderer::Draw` four times in the probe, up to 72 ms each,
   most of it `ScheduleOnVizAndBlock` (the draw functor waiting for
   viz), which the Chromium pipeline stages never showed. Scheduler
   data (`thread_state`: Running, R, S per thread) and `cpufreq`
   counters are present. The frame timeline produced only three rows
   for about twelve Choreographer frames, one of them the app's layer
   ("Late Present, App Deadline Missed", duration 0): its coverage on
   this TV is doubtful and is judged on a real glide. Two overheads to
   measure in execution: Chromium's `PerfettoTrace` producer thread
   carried about 1,500 slices per process in four seconds, and the
   `track_event` category `*` is wide. Side finding, not pursued here:
   the WebView's `Gamepad polling thread` ran about 250 times a second
   throughout the trace (980 `GetGamepadData` in four seconds, 137 ms
   running, 23 ms runnable), with no gamepad in use; the input system's
   polling of `navigator.getGamepads()` keeps Chromium's poller alive.
   Candidate M8.
5. **Implementation plan.** (1) `~/scripts/agents/_tv.py` (stdlib
   only): the device (`MC_TV`, `ENV`, `APP`, `LAYER`, `tv()`, `adb()`,
   `launch()`, `off()`, `hdmi()`), the page (`js()` through `mc-tv
   eval`, `wait_connected()`, `wait_quiet()`, `page_identity()` with
   `BUNDLE`), the actions (`HOLD`, `HOLD_KEYS`, `act(action)` for a
   key, `hold KEY N` or `js EXPR`), the screen (`clear_presents()`,
   `presents()` as ms from the first, `GLIDE_BREAK_MS`,
   `glide_run(presents)` = the longest unbroken run, `fps(run)`), each
   with the comment that today sits beside its copy. (2) `mc-tv-smooth`
   imports `_tv` and deletes its copies; `press()` becomes
   clear → act → read through `_tv`; the no-probe window uses
   `glide_run`; `report` and the trials are untouched; the stored runs
   41–45 re-report identically (checked). Plain `python3` shebang, no
   dependencies. (3) `mc-tv-trace` rewritten in Python as a `uv` script
   declaring `perfetto`: same flags (`--key`, `--hold`, `--js`, `--ms`,
   `--out DIR`, `--top`, `--from DIR`); brings the app forward; writes
   the Perfetto text config (ftrace sched/freq, atrace `gfx view
   webview`, `atrace_apps` the debug app, process stats, frame
   timeline, `track_event` with the Chromium categories the Node tool
   used plus `android_webview`), starts `adb shell perfetto -c - --txt`
   with the duration = lead + `--ms`, waits for its "Connected" line,
   clears presents, marks the action (`console.timeStamp`), acts, waits,
   lets perfetto end, pulls `system.perfetto-trace`, reads presents to
   `presents.json`, then reports from `TraceProcessor`: screen fps
   first (the glide run), the frame timeline for the app's layer after
   the mark, the Chromium pipeline (states, drivers, stage p50/p90/max
   from `PipelineReporter` children, as the Node summary did), the
   render thread (`HardwareRenderer::Draw`, `ScheduleOnVizAndBlock`,
   `DrawFrames` n/p50/p90/max), per thread running and runnable ms with
   the heaviest slices, and the CPU frequency range in the window. The
   report is also written to `report.md` in the record. (4) The Node
   `mc-tv-trace` is deleted; old `~/.cache/mc-tv-trace/*.json` traces
   stay openable in `ui.perfetto.dev` and are not read by the tool.
   (5) `docs/tv-performance.md`: glossary rows for system trace, frame
   timeline, render thread; Measuring's "Explain with a trace" bullet
   rewritten for the new output; Open gains the gamepad poller.
   (6) Verification offline: `--from` over the probe record; then, with
   the owner's go-ahead, one record of a real library glide, and the
   tool's cost as run 46 (`mc-tv-smooth` plain presses alternated with
   presses under `mc-tv-trace`, as run 45 did), recorded in the row
   before the tool's numbers are believed.
6. **Plan unification.** Checked against the design: (i) the design had
   `mc-tv-smooth` become a `uv` script; the plan keeps its plain
   `python3` shebang because `_tv.py` is stdlib-only and only
   `mc-tv-trace` needs `perfetto`, a correction of the design, not a
   second path. (ii) `websockets` is gone with the DevTools trace;
   nothing in the plan reaches the page except `mc-tv eval`. (iii) Two
   glide windows remain, one from scroll events (the probe's, in
   `mc-tv-smooth`'s `summarize_press`) and one from presents alone
   (`_tv.glide_run`); they take different inputs and are not two
   representations of one idea, but the fps formula was about to exist
   twice, so `_tv.fps(run)` is the one both use. (iv) The plan's cost
   measurement reused the run-45 scratch script, a stand-in outside the
   tools and a breach of principle 4; replaced: `mc-tv-trace --cost N`
   alternates N plain presses with N traced presses of the same action
   through `_tv` and prints both fps lists with Δ, so each tool carries
   its own cost check (`mc-tv-smooth` has `--no-probe`). The scratch
   script is retired. (v) "The app is on screen before measuring" is
   one rule in `_tv.launch()` that both tools call first, not a line in
   each. (vi) `--from` takes a record directory of the new shape only;
   `docs/tv-performance.md` changes `--from FILE` to `--from DIR`. (vii)
   Any other script that calls `mc-tv-trace` is found by grep before
   the Node file is deleted. No old path, no copied constant, no
   stand-in remains in the plan.
7. **Execution (2026-10-26, TV sessions by the owner's go-ahead).**
   `~/scripts/agents/_tv.py` written (device, page, actions, presents,
   `glide_run`, `launch()`, and `WALKS` with each press's glide flag,
   read from runs 43–44); `mc-tv-smooth` imports it and its stored runs
   41–44 re-report identically; `mc-tv-trace` rewritten in Python as a
   `uv` script over one Perfetto system trace, the Node file replaced
   at the same path. Verified offline on the probe trace, then live.
   The tool's own cost, measured with `--cost` on the Home walk (six
   glides a side): the first config cost 8.3 fps (run 46: 51.7 against
   60), and bisecting it (runs 47) found every data source free alone
   (ftrace+atrace −6.4, Chromium events −6.4, light categories −6.2,
   all the same) and the whole trace free without the action mark
   (Δ +0.0): a DevTools session opened and closed right before the key
   (`mc-tv eval` for `console.timeStamp`) cost 6.5 fps on its own
   (frame timeline only, with the mark: −6.5, noise 1.9, beyond). The
   mark is gone and the window anchors on the screen's first present
   (the clock snapshots give the offset; zero on this TV). Final config
   with the process scan: Δ −0.0 (noise 3.8), run 49. One Home glide
   under the finished tool (`49-home-glide`): 60.0 fps on screen, every
   gap 16.7 ms; frame timeline 24 app frames all "Late Present, Buffer
   Stuffing", actual 36 ms (the WebView runs a frame ahead of the
   display, never misses a deadline); Chromium pipeline whole frame
   27 ms p50, half the presented frames partial, Submit→Presentation
   19.7 ms; render thread `dequeueBuffer` 9.9 ms p50 per frame (waiting
   for a buffer, the stuffing's other face), `HardwareRenderer::Draw`
   4.0 ms, `DrawFrames` 16.4 ms; over the 1.6 s window the Compositor
   thread was runnable 42 ms, the renderer main 37 ms, the gamepad
   poller ran 67 ms and waited 45 ms. `docs/tv-performance.md` updated
   (glossary, Measuring, Open). M2 closed.

### M8 — The gamepad poller

1. **Scope.** In: price Chromium's gamepad polling thread against a
   glide on the TV, interleaved on both pages, with the input system's
   gamepad source stopped as the condition; a debug handle
   (`window.__gamepadSource`) so the condition needs no code change
   between rounds; then, only if the cost is beyond the noise, stop
   paying it when no gamepad is present. Out: any change to how a
   connected gamepad drives the UI.
2. **Research.** `assets/js/input/core/gamepad.js` already polls
   `getGamepads()` per frame only while a gamepad is connected; with
   none, `start()` reads `getGamepads()` once and registers
   `gamepadconnected`/`gamepaddisconnected` listeners on `window`. The
   TV reports no gamepad (`navigator.getGamepads()` is eight nulls). So
   the poller that ran 250 times a second in every trace is Chromium's
   own, kept alive by the page's gamepad event listeners (Blink starts
   the browser's gamepad sampling when a page listens for connection
   events, so that it can deliver them). Stopping the source removes
   the listeners; whether Chromium's thread then stops is what a trace
   under the condition shows.
3. **Design decisions.** The handle is `exposeGamepadSource(source,
   globals)` in `assets/js/input/index.js`, in the pattern of
   `window.__scrollGlider`, tested through that function (the hook's
   `mounted` needs the whole DOM to run). No fix is designed before
   the measurement.
4–6. Skipped: a debug handle and a measurement change no system
   (steps 3–6 of the procedure apply to a change; the handle follows
   the `__scrollGlider` precedent, test-first, commit `c7f5c097`).
7. **Execution (2026-10-26).** Run 50, `base` against `js:nogamepad.js`
   (`window.__gamepadSource.stop()`), two rounds on Home and the
   library: 60 against 60 on both pages, Δ +0.0 (noise 0), every gap
   16.7 ms. A Home glide traced with the source stopped
   (`50-home-glide-nogamepad`): the `Gamepad polling thread` is absent
   from the window where the base glide (`49-home-glide`) had it
   running 67 ms and runnable 45 ms, so Chromium's poller stops when
   the page's listeners go; the Compositor thread's runnable time is
   unchanged (42 ms) and the frame timeline reads the same (25 frames
   buffer-stuffed). The poller costs nothing the screen shows at 60
   fps. No code change; M8 closed. (The first base trial's page id read
   `MIXED`: the round before commit `c7f5c097` ran on the dirty tree
   with the same bundle digest, exactly what the column is for.)

### M3 — Code-version A/B as a script

1. **Scope.** In: (a) the bootstrap key `background_services` in the
   override TOML, read like `showcase_mode`, that turns every background
   service off at once and that no Settings row overrides; (b) the
   test-only start flags (`:start_relay_sync`, `:start_relay_connections`,
   `:start_playback_recovery`) converge on it; (c) a bootstrap `data_dir`
   key so a database copy at a new path still reads the real
   `image-derivatives`, avatars and profile pictures (today `data_dir` is
   always the database's directory); (d) `mc-tv-ab <ref-a> <ref-b>`:
   worktrees under `~/src/media-centaur/ab/`, each with its override
   TOML, database copy, build and server on 2161/2162, then one
   `mc-tv-smooth run` whose conditions are the two hosts, then the
   servers stopped; (e) `mc-tv-smooth --cond host:<url>` as a condition
   kind, with `page id` read from the host that served the page; (f) the
   Measuring section of `docs/tv-performance.md` and `docs/configuration.md`
   for the two keys. Out: any change to the pages; M6's before-half
   (it uses this milestone's servers afterwards); keeping the worktrees
   between runs beyond what `git worktree` keeps.
2. **Research.** The override TOML is read twice before boot: in
   `config/runtime.exs` (port, bind, database path) and in
   `Settings.Config.load!/0` (`merge_toml/2`, the bootstrap keys incl.
   `showcase_mode`), so a new bootstrap key follows both readers; Oban's
   queues and plugins are config, so only `runtime.exs` can turn them
   off (`queues: false, plugins: false`; Oban itself still starts, pages
   may insert jobs that then wait in the copy). The dev TOML carries only
   `port`, `bind` and `database_path`; media dirs and their image dirs
   live in the database, so the copy inherits the real ones
   (`<media dir>/.media-centaur/images` unless overridden). `data_dir`
   defaults to the database's directory and is not settable; it holds
   `image-derivatives` (made on demand), avatars, profile pictures and
   themes, so a copy without it would regenerate every poster derivative
   on first view and render without avatars. The services with a user
   toggle (`should_start?/1`: watchers, pipeline, acquisition) consult
   the Settings database over the config default, so the copy of a real
   database switches them back on unless the key wins. Children that
   reach out with no gate outside `:test`: `BootHeal` heals (ffprobe over
   the library), the four acquisition and download PubSub listeners
   (`Acquisition.Reactor`, `Downloads.QueueMonitor`, the two Pursuits
   listeners), Oban's cron; `SelfUpdate.boot!` is already prod-only.
   `agent-mix` keys its build root by the checkout's basename, so two
   worktrees with distinct names get distinct roots. A worktree needs
   `deps.get`, `assets.setup` and `assets.build` once. The paired TV
   needs no re-pairing on a second port (decision 8, verified in
   `config/dev.exs` and `endpoint.ex`). `mc-tv launch --host` force-stops
   the app and restarts it with the new address; the first trial after
   that is the known slow one (run 44). `mc-tv-smooth`'s `page id` takes
   HEAD from the one checkout and the bundle digest from the page, so a
   host condition needs HEAD from the host's checkout: the served page
   carries no commit in dev (`Version.build_info/1` is `:dev_build`).
   The `backups` skill routes database backups through Fae; a copy for
   a measurement is a working file, not a backup, and `sqlite3 .backup`
   is WAL-safe against the running server.
3. **Design decisions.** Decisions 7–10 (owner). Taken here within
   them: `data_dir` becomes a bootstrap key on the same criterion as
   `database_path` (needed before the database is reachable; the
   alternative, symlinks beside the copy, encodes the layout in a
   script); with background services off no PubSub listener starts, as
   under `:test`, rather than a judged subset; the three test-only start
   flags are removed, `config/test.exs` sets `background_services: false`
   instead; the host→checkout map for `page id` is the A/B's manifest
   (`~/.cache/mc-tv-ab/hosts.json`, written by `mc-tv-ab`), which
   `mc-tv-smooth` reads for a `host:` condition.
4. **Design unification (2026-10-26).** Core idea: an instance's
   bootstrap state says which instance this is, decided before the VM
   starts; "runs background services" is one such fact, read once and
   asked by every child that would act unprompted. Greenfield: the key
   lives in `Settings.Config` beside `showcase_mode`; `Settings.Services`
   owns "may this toggled service run" and answers no when the key is
   off, whatever its row says; every other unprompted child asks
   `Config.get(:background_services)`; Oban is config, so `runtime.exs`
   reads the same TOML key; the test env sets the key's app-env default
   to false. Diff against the code: (a) seam — the `showcase_mode` path
   through both TOML readers; (b) scattered — the three test-only start
   flags, `BootHeal`'s `:test` clauses and `pubsub_listeners(:test)` are
   four spellings of "no background work", all converge on the key
   (fix now); the `:test` clauses that remain (`cache_children`,
   `http_client_children`) are sandbox reasons, not inertness, and stay
   as env checks; (c) `SelfUpdate.enabled?` is prod-only and gains the
   key (fix now). Scope correction: `data_dir` is already a runtime
   setting (`config:data_dir`, Settings → Library), not bootstrap, so
   scope item (c) is dropped; the A/B writes that row into each copy.
   Confirmed on the real database: `services:dev:start_pipeline` and
   `start_watchers` are enabled, so without the key winning a copy would
   run both. Tooling: `mc-tv-smooth`'s `HOSTS` and `_tv`'s `REPO` are two
   sources for "which checkout serves which URL"; they become one host
   registry in `_tv` (built-in dev and sim plus the A/B's manifest), and
   `page id` reads the page's own `location.origin` to find its checkout
   (fix now). The run loop becomes round → condition → page for every
   condition kind, so a host switch happens once per condition per round
   (fix now; an in-page condition is applied per page as before).
   Coherence cost beyond the bolt-on: BootHeal's three skip tests go
   (they tested env dispatch the key replaces), `config/test.exs` loses
   five flags, three moduledocs change, the defaults TOML, the
   configuration doc and the wiki gain one key. Accepted.
5. **Implementation plan (2026-10-26).** Test-first throughout, in the
   main checkout, `agent-mix` for every mix run. App: (1) `Config`:
   bootstrap key `background_services` (TOML, default from app env,
   `true`), tests in `config_toml_bootstrap_test.exs` (reads, defaults,
   not runtime-settable). (2) `Services.enabled?/2` returns false when
   the key is off, test in `services_test.exs` with an enabled row.
   (3) `SelfUpdate.enabled?/0` = prod and the key, test. (4)
   `Application`: `relay_sync_children`, `pubsub_listeners`, the BootHeal
   calls gated by the key; `Social.Connections.init` and
   `Playback.Supervisor` read the key; BootHeal's env argument and `:test`
   clauses go, with their three tests. (5) `runtime.exs`: Oban
   `queues: false, plugins: false` when the TOML key is false. (6)
   `config/test.exs`: `background_services: false`, the five start flags
   removed. (7) Docs: `defaults/media-centaur.toml` (commented key),
   `docs/configuration.md`, wiki `Configuration-File.md`, the three
   moduledocs. (8) `agent-mix precommit`. Tooling: (9) `_tv.py`: `HOSTS`
   registry (dev, sim, plus `~/.cache/mc-tv-ab/hosts.json` entries
   `{label: {url, checkout}}`), `host_of(url)`, `set_host(url)` (launch
   with the address, wait connected), `page_identity()` from
   `location.origin`; `mc-tv-smooth`: `host:<label|url>` condition
   (apply = `set_host` when the origin differs), loop order round →
   condition → page, `host` subcommand through the registry; stored runs
   44 and 50 re-report unchanged. (10) `mc-tv-ab <ref-a> <ref-b>
   [run args]` with `up | run | down` (default all three): worktrees
   `~/src/media-centaur/ab/<label>` (`a`, `b`), per label a TOML under
   `~/.cache/mc-tv-ab/<label>/` (port 2161/2162, bind `0.0.0.0`,
   `database_path` beside it, `background_services = false`), `sqlite3
   .backup` of the dev database, `deps.get` + `assets.setup` +
   `assets.build` + `ecto.migrate` with the override, the `config:data_dir`
   row set to the real data directory through `Config.update/2`
   (`agent-mix run -e` with the override), `phx.server` in the
   background with its log beside the TOML, readiness on HTTP 200,
   `hosts.json` written; `run` = `mc-tv-smooth run --cond host:a --cond
   host:b` plus the caller's args; `down` stops both servers and removes
   the worktrees. (11) `docs/tv-performance.md`: step 1 of "How to
   change UI safely" names `mc-tv-ab` for code that cannot be
   overridden; Measuring gains its bullet. (12) On the TV: `mc-tv-ab
   HEAD HEAD` as the A/A (60 against 60 expected, both page ids the same
   HEAD), TV woken for it, standby after.
6. **Plan unification (2026-10-26).** Checked against the plan failure
   modes: the five flags leave `config/test.exs` in the same change
   that adds the key (no old path kept; `start_pipeline` and
   `start_watchers` stay in `dev.exs` only, where they are a toggle's
   env default, a different idea); BootHeal's `:test` clauses are
   removed with the env argument, all three functions and the one
   caller at once, and `boot_heal_test.exs` goes whole (its only tests
   were the dispatch); `HOSTS` moves from `mc-tv-smooth` to `_tv`, not
   copied, and `REPO` becomes the dev entry's checkout; `page_identity`
   reads `location.origin` for every condition, not only `host:`;
   `mc-tv-ab` composes `mc-tv-smooth` through the manifest and the
   command line, one direction, no shared code beyond `_tv`. Amendments
   from the pass: the key's precedence is TOML, then app env, then
   `true`, and the test for the silent TOML sets the app-env default
   under the sandbox rather than asserting the test env's own value;
   worktrees are named `mc-ab-a` and `mc-ab-b` so `agent-mix`'s build
   root (keyed by basename) cannot collide with another repo; `mix run
   -e` boots the inert tree against the copy, so the `data_dir` row is
   written through `Config.update/2` with the override set on every mix
   call in the script; the A/B holds for refs whose schema is at or
   below the dev database's (Ecto never downgrades), stated in the doc.
   No incoherence left for a later milestone.
7. **Execution (2026-10-26).** App: commit `6095f146` (key, converged
   gates, `Settings.Services` gate, `SelfUpdate.enabled?`, Oban off in
   `runtime.exs`, `config/test.exs` on the one key, BootHeal without its
   env clauses, docs, defaults TOML, wiki key committed locally and not
   pushed); `agent-mix precommit` green, 8744 tests. Two findings on the
   way: an instance without background services no longer calls
   `pause_auto_grab` at boot — it had persisted
   `services:test:start_acquisition` into the test database on the
   first run (every later test saw the row); and the four tests that
   model a production instance now load one through
   `MediaCentaur.ProductionInstance`, since a production instance with
   the check running is one with background services. Tooling: `_tv`
   holds the host registry (dev, sim, `~/.cache/mc-tv-ab/hosts.json`),
   `set_host`, and `page_identity` from `location.origin`;
   `mc-tv-smooth` has `host:` conditions, the round → condition → page
   loop and the `host` subcommand through the registry; `mc-tv-ab` is
   new. On the TV (woken from standby, standby after): `mc-tv-ab up HEAD
   HEAD` built both sides in about 4 minutes each (deps, assets,
   migrations, the `config:data_dir` row); the servers' logs show no
   watcher, pipeline, relay or Oban queue, only the config listener's
   idempotent retraction pass that dev also runs at boot. `mc-tv-ab run
   --reps 2 --off`, run `20261026-141657`: library 60 against 60 (2
   glides, 122 px), Home 60 against 60 (7 glides, 410 px), Δ +0.0, noise
   0, every gap 16.7 ms; Home under host a had one stall of about 120 ms
   in each round, b none — one frame in a seven-glide walk, within what
   one tool's rounds show, not pursued. Note for reading `page id`: the
   two sides' bundle digests differ for one commit (`8fc9d3fc` against
   `e5e6afad`) because dev's esbuild inlines the source map with each
   worktree's absolute paths; a code A/B compares HEADs, and the digest
   says only that the two sides served different builds. `mc-tv-ab
   down` left no worktree, server or copy behind.

### M9 — No gamepad source on a remote player

1. **Scope.** In: (a) `createInputHook` starts no gamepad source on a
   page served to a remote player (`html[data-player="remote"]`), so
   the page holds no `gamepadconnected` listeners and Chromium's
   polling thread never starts there; (b) `exposeGamepadSource` and
   `window.__gamepadSource` go, with their test, since M8 was their
   only purpose; (c) whatever leans on the source copes with its
   absence: the controls bridge's button capture, the rebind of maps;
   (d) Settings → Controls on a remote player (decision 11); (e)
   `docs/tv-performance.md` (the "Measured and left alone" paragraph
   becomes the rule) and `docs/input-system.md` (the sources list).
   Out: the host's gamepad path, untouched; the hint bar's gamepad
   glyphs (never shown on a remote player once no source sets gamepad
   mode); the TV app's own key handling.
2. **Research.** `<html data-player="remote">` is written by
   `root.html.heex` from `assigns[:player]` (`PlayerAware` assigns it on
   every LiveView, the `RemoteAccess` plug on every conn), and
   `app.js` and `hooks/mouse_autofocus.js` already read
   `document.documentElement.dataset.*` from the app layer, so the hook
   reads the player kind the same way (core stays DOM-free except
   `dom_adapter.js`). The source is the second factory in the
   orchestrator's `sources` list (`index.js`); the orchestrator starts
   whatever factories it is given, so a list without the factory needs
   no orchestrator change. Three things reach the source: `rebind`
   (already guarded on null), `ControlsBridge.captureGamepadButton`
   (`gamepadSource.captureNext` closed over at mount; the bridge treats
   a missing capture as "cannot listen" and returns), and the M8
   handle. `gamepadInputAllowed` (`input_gate.js`) gates a connected
   pad per poll and is unrelated. On the Settings page the server
   assigns `listening: {:gamepad, id}` before the browser is asked to
   capture, so with no source the row stays listening (decision 11).
   `controls_test.exs` covers the gamepad keycap's listen on the host;
   `binding_row.story.exs` has six variations, none without a Pad
   slot.
3. **Design decisions.** The hook decides from the page: `remotePlayer
   (documentElement)` is a pure function in `index.js` beside
   `shellLeave`, tested like it, and the sources list is built by a
   pure `inputSources({ remote, … })` so the choice is testable without
   a DOM. Decision 11 (owner) settles the Controls section.
4. **Design unification.** Core idea: the device a page is served to
   says which input sources the page starts, and a surface that
   configures a source exists only where the source does. The server
   already projects the device as one fact, `assigns.player` (`:host`
   or the paired player; `PlayerAware` on every LiveView, the
   `RemoteAccess` plug on every conn) and `<html data-player="remote">`
   from it; both sides read that one fact, no second signal. Greenfield
   client: the hook composes its sources from the device
   (`inputSources(remote, { keyboard, gamepad })`), hands the bridge a
   button capture only when a gamepad source exists (the bridge's
   constructor already declares the capture optional and "absent when
   no gamepad source exists", so the hook's unconditional closure over a
   possibly-null source was the incoherence; fixed now), and carries no
   measurement handle. Greenfield server: the Controls section takes
   `gamepad` (true on the host) and renders the Pad slot, the glyph
   choice and the "key and button" instruction only then; `binding_row`
   takes the same attr, so the component and the section agree and the
   story shows the key-only row. No second representation: the TV
   never sets gamepad input mode, so the hint bar's glyph labels need
   no gate. Left as is, decided: the Settings overview's one-line
   description "Keyboard and gamepad bindings." is a static catalogue
   entry read on the host's overview; the wiki's rebinding steps say
   "the Key or the Pad one" and gain one sentence for the TV. Coherence
   cost: within scope (two attrs, one story variation, two tests).
5. **Implementation plan.** Test-first throughout. (1) bun:
   `index.test.js` gains `remotePlayer` (true for `data-player="remote"`,
   false without it) and `inputSources` (keyboard alone on a remote
   player, both otherwise); the `exposeGamepadSource` test goes; red,
   then `index.js`: the two pure functions, `mounted` builds the
   factories by name and passes them through `inputSources`, the
   bridge gets `captureGamepadButton` only with a source,
   `exposeGamepadSource` deleted. (2) Elixir: `controls_test.exs` gains
   a describe "on a remote player" (conn with a paired player's session,
   as `player_aware_test.exs` mounts one): no `phx-value-kind='gamepad'`
   keycap, no glyph choice, the instruction reads "Every action has a
   key."; red, then `binding_row` attr `gamepad` (default true) gating
   the Pad slot, `Controls.render` attr `gamepad` gating the glyph choice
   and the copy, `settings_live.ex` passes `gamepad={@player == :host}`;
   the story gains `:key_only`. (3) Docs: `docs/tv-performance.md`'s
   paragraph becomes the rule (a remote player's page starts no gamepad
   source; the M8 measurement stays as its evidence);
   `docs/input-system.md` sources wiring and the bridge row;
   `binding_row` and `Controls` moduledocs; wiki
   `Keyboard-and-Gamepad.md` one sentence (local commit, pushed when the
   change ships). (4) `bun test assets/js/input/`, then precommit; then
   on the TV a `mc-tv-trace` of a glide on HEAD to confirm the polling
   thread is absent on the served page. (5) Campaign row, Status.
6. **Plan unification.** Checked against what the design removed:
   `exposeGamepadSource` is deleted, not kept "for measurements" (the
   M8 condition file `nogamepad.js` is dead with it; the trace is the
   check now); the bridge's capture is absent, not a closure over null;
   `binding_row` and `Controls.render` both take the attr (no section
   hiding what the row still draws); `remotePlayer` and the server's
   `@player == :host` read the same fact, not a parallel attribute on
   the hook element; the doc paragraph is rewritten, not appended to.
   No shim, no two-commit split. Proceed.
7. **Execution (2026-10-26, done).** Code landed test-first:
   `remotePlayer` and `inputSources` in `index.js` (bun 988 pass), the
   hook's bridge gets a button capture only with a source, the handle
   and its test gone; `binding_row` and `Controls.render` take
   `gamepad`, Settings passes `@player == :host` through the section
   router (`player` was not among the explicit assigns it receives; it
   is now), the story's `key_only` variation, the LiveView test mounting
   as a paired LAN player; docs, moduledocs and the wiki sentence
   (local commit). Precommit green (8745 tests). The TV check, a trace of
   the dev server's Home glide on the new bundle showing no `Gamepad
   polling thread`, is not yet done: six traces this session all read
   the thread present, and every one measured a page of unknown
   provenance (page id `@?`), because the tooling had three gaps found
   and fixed on the way — `mc-tv` defaulted to the owner's release app,
   so a bare `mc-tv stop`/`launch --host` from the agent shell restarted
   the owner's app and `webview` forwarded to its pid (now the debug
   app is the default, and `webview` takes the socket from the socket
   list, filtered by the process's cmdline, newest first; `eval`
   renews it per try and names the pid and sockets when none answers);
   `_tv.js` returned a blank for an unreachable page, which
   `page_identity` turned into `@?` (now it raises, `wait_connected`
   tolerates it, and `page_label` ends with the host label or the raw
   origin, so a page served by the wrong server shows in every row);
   `mc-tv-ab down` left the app pointed at the stopped side-b server
   (now `restore_host`: back to dev, woken and put to standby if it
   slept, left with a note if the owner is using it). Paused with the
   TV handed to the HDMI input at the owner's request. Resumed the same
   evening with the TV free: `mc-tv-smooth host dev` put the debug app
   on the dev server (page id `6708c0af @d16c35f8 dev`); traces
   `20261026T201117`, `201133` (DPAD_DOWN) and `201205` (DPAD_RIGHT on
   the Recently row) list no `Gamepad polling thread`, and a query of
   the trace files themselves finds no thread named like it in any
   process (the debug app, its renderer, the release app, the zygote);
   but none of the three glided — DPAD_DOWN moves the cursor a row, and
   the Recently row's 150 px tiles need no scroll after three presses —
   so trace `20261026T201413`, the Continue row's third DPAD_RIGHT, is
   the record: 28 presents at 60.0 fps, the same thread table, the
   thread absent. Two things worked into the tooling: `mc-tv-trace
   --glide [PAGE]` sends the app to the page and makes the walk's
   presses before its first gliding one, so a trace lands on a glide
   without three tries; and the report ends its thread table with an
   `absent from the trace` line, so the evidence for "no poller" is
   printed rather than inferred from a missing row.

### M6 — The hero's memory on the TV

1. **Scope.** In: (a) find where the WebView renderer's memory is
   accounted on this TV; (b) a per-trial reading of the page's memory in
   `mc-tv-smooth`, taken after the presses (never between setup and
   action); (c) the measurement itself, Home under `mc-tv-ab e84dfd99~1
   e84dfd99`, both hosts interleaved, the memory column read per host.
   Out: any change to the hero; a memory reading in `mc-tv-trace`
   (the trace's threads already name the renderer).
2. **Research (2026-10-26, read-only queries while the owner used the
   TV).** The page is two processes. `dumpsys meminfo
   app.mediacentaur.tv.debug` covers the app's process alone (68 MB
   PSS on Home, backgrounded; `Graphics` 0, the GPU work is in-process
   and lands under `Unknown`). The renderer is
   `com.google.android.webview:sandboxed_process0:…` under an isolated
   uid, one per app (the owner's release app has its own), 58 MB PSS at
   the same moment; `dumpsys activity processes` ties it to its app by
   the ProcessRecord suffix `/u0a<appid>i<n>` (appid = uid − 10000).
   Blink's decoded-image cache and the hero hook's bitmaps live there,
   so the number M6 compares is app plus renderer PSS.
3. **Design decisions.** None for the owner: the reading is defined by
   the row. Taken: the memory is one fact owned by `_tv.py`
   (`renderer_pid`, `pss_mb`, `app_memory`), recorded per trial with its
   two parts and reported as one column `app+rend MB` beside `tv mem
   MB`, which stays (the TV's pressure is a different fact).
4. **Design unification.** The device facts live in `_tv.py`, the
   trial record and the report in `mc-tv-smooth`, as `tv cpu` and
   `tv mem` already do; no second reader of `dumpsys`. An older record
   without the parts reports `-`, not a guess.
5. **Implementation plan.** `_tv.py` the three functions; `mc-tv-smooth`
   records `app_mem` after `MemAvailable`, `app_mem_total` sums the
   parts, the usage text and the report column; verify on the resident
   app read-only, then re-report an old run; then the measurement (c)
   when the TV is free: `mc-tv-ab e84dfd99~1 e84dfd99 -- --page /
   --reps 2`, the column per host, recorded in the row with the
   estimate it replaces (about 66 → 16 MB).
6. **Plan unification.** One reader, one owner, one column; the old
   `tv mem` column is not repurposed and no record format is kept in
   two shapes (`app_mem` is new, absent before). Proceed.
7. **Execution (2026-10-26, done).** Steps 1–2 of the plan done and
   checked: renderer pid 24403 for the debug app (pid 24374),
   `app_memory()` read `{app: 68.4, renderer: 58.0}` MB, run
   `20261026-141657` re-reports with `-` in the new column. The
   measurement, the same evening with the TV free: `mc-tv-ab e84dfd99~1
   e84dfd99 -- --page / --reps 2`, run `20261026-201555`. Per trial,
   app + renderer: a (`62e10117`) 200.2 and 197.4 MB; b (`e84dfd99`)
   174.2 and 174.6 MB — the commit saves about 24 MB on Home (renderer
   109/107 → 92, app 91/90 → 82), against the estimate of about 50. The
   glides read 60 against 60, Δ +0.0, noise 0. Two asides: both sides
   showed six stalls over 100 ms, all on the walk's vertical presses,
   where at those commits the window scrolled 204 px on the first DOWN
   and crept 1 px a frame on the next, with gaps of 150–400 ms; at HEAD
   (runs `141657`, 50) the same presses scroll nothing and show one
   present, so it is history, not a lead. And `mc-tv-ab`'s one-command
   form handed the TV to HDMI inside `run`, so `down`'s host restore took
   it for the owner's use and left the app on the dead side-b server;
   now the run keeps the TV on the app (`--no-handback`) and the
   handback or `--off` follows `down`.

### M7 — The 156 px against 88 px reveal

1. **Scope.** In: name what moved the glide's target on the library
   page (run 41: one DOWN press scrolled 156 px under the glide, 88 px
   under the compositor smooth scroll), and whether the glide lands
   where the owner's eye says it should (decision 4). Out: changing the
   glide's motion.
2. **Research (2026-10-26, code only; the TV in use).** `revealItem`
   measures the destination once per press (an instant
   `scrollIntoView`, read, rewind) and hands the glide that number; the
   glide re-reads only the *clamp* per tick (`reachable`: the content
   shrinking), so a growing or shifting layout never moves a recorded
   target — the two animators were given different destinations at
   press time, or one of them was cut short. Library tiles have a fixed
   aspect (`aspect-[2/3]`), no `content-visibility`, no viewport
   loading, so a layout shift from images is unlikely. Candidates for
   the TV, in order: the measuring jump happening with the focused
   card's hover/focus transform mid-transition (a scaled border box
   asks `scrollIntoView` for more); the smooth variant interrupted by a
   later instant write (a post-patch reconcile's focus, or the next
   press) before it arrived; `scroll-padding` or a sticky header
   counted by one route and not the other. Each is one `mc-nav-trace`
   or `mc-tv-smooth` run with the probe's per-event scroll positions.
3. –6. Skipped: the milestone runs a check and changes no system
   (the campaigns convention allows it; a finding that asks for a change
   becomes its own milestone).
7. **Execution (2026-10-26, in progress).** Run 41's own records
   answer the first question before any new TV run. Per press, the
   probe's scroll events on `/library` read: glide DOWN `html` 0 → 156,
   glide UP 156 → 68; smooth DOWN 68 → 156, smooth UP 156 → 68. Both
   animators landed on the same two positions, 156 and 68, in every
   round; nothing moved a target mid-glide. The 156 against 88 is the
   *starting* position: a glide trial began at scrollTop 0 and a smooth
   trial at 68, so the same reveal travelled 156 px from the page top
   and 88 px from the row above. What leaves the page at 68 before the
   smooth trial's first press (no scroll event in the press windows;
   `goto` is a full `location.href` load for every trial) was then
   checked on the TV at HEAD (`d16c35f8`, dev server): a scripted read
   of scrollTop, the focused item and the context after connect, after
   quiet, after the override and after each of three DOWN and three UP
   presses, under glide and smooth in both orders. All four trials
   identical: 0 at connect and quiet (and after the override), 0 after
   DOWN 1 and 2, 156 after DOWN 3, 156 after UP 1 and 2, 68 after UP 3,
   the same items focused throughout. Nothing in today's code leaves the
   page at 68 before a press; run 41's smooth trial had inherited a
   position from its own sequence on an older build. Closed: the glide
   lands where the smooth scroll lands. The second question (where the
   owner's eye says a reveal should land) has no animator half: both
   land on `scrollIntoView` "nearest". One observation for the owner,
   not a milestone: UP onto the first row stops at 68, leaving the
   toolbar above the grid scrolled off; "nearest" never brings the page
   back to its top. Whether the first row should reveal the page top is
   a design call outside this campaign.

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
