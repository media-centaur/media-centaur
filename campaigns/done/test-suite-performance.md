---
status: shipped
started: 2026-05-22
last_updated: 2026-05-22
shipped: 2026-05-22
---
# Test-suite performance & principles

## Goal

Establish testing principles and practices that yield a
well-managed, high-performance suite — then use them to resolve the
suite's current problems. Performance here is an *emergent property
of correct, well-architected tests*, not a thing chased by cutting
corners: the same change must be faster, more correct, and more
maintainable, or it is the wrong change. The principles are codified
as a repo-wide ADR ([ADR-049]) and folded into the project's
`automated-testing` skill so future work keeps using them. Scope
spans every automated suite: Elixir (`mix test`), JS unit (`bun
test`), and Playwright E2E.

## Status

**Hang fixed.** Immediate fix landed: the `DataCase` teardown drain
now waits a 100ms grace then *terminates* orphaned tasks instead of
waiting 1000ms each. Full `mix precommit` green: Elixir **54.5s /
3889 tests / 0 failures** (was a 9+ min non-terminating hang),
deterministic across seeds, zero ownership noise; bun 436/0.
[ADR-049] + this campaign written.

**Owned-async rollout complete.** All 8 grandfathered LiveViews
converted; the **MC0019 grandfather list is empty** and the rule is
fully enforced — no fire-and-forget `Task.Supervisor.start_child`
remains in `lib/media_centarr_web`. View loads use `start_async`;
must-outlive work (grabs, searches, library maintenance, rescans)
moved to context-layer `*_async` functions. Fast local ops
(toggles, deletes, rematch) made synchronous (ADR-044). Full suite:
**~53s / 3894 tests / 0 failures**, deterministic.

**Follow-ups closed (2026-05-22):**

* **Drain — kept, not removed.** The "remove the drain" idea rested on
  a wrong premise: must-outlive work was *relocated* to context-layer
  `*_async` functions that still run under the global `TaskSupervisor`
  and legitimately orphan in tests. The grace-kill drain is therefore
  the *permanent* O(grace) teardown safety net, not a bridge —
  re-documented in `data_case.ex`.
* **CI suite-time gate added.** The Linux precommit step is wrapped in
  `timeout -k 60 900` so a hung suite fails in ~15 min instead of
  running to the GitHub Actions ceiling (Principle 1).
* **Sleeps assessed.** The flaky class (`Process.sleep`-to-settle for
  async loads) was eliminated during the rollout (→ `render_async` /
  `wait_until`). The ~52 remaining are bounded debounce/real-timer
  waits; a Credo check can't cleanly separate those from
  poll-with-deadline, so no mechanical gate — tracked as minor hygiene.

Campaign complete.

## The regression (confirmed root cause)

The suite regressed from ~30s to a non-terminating hang. Symptoms
and the chain of evidence:

* **Idle CPU, long wall time.** A full run sat at ~13% CPU / load
  <1 on a 12-core box, sleeping — i.e. *blocked waiting*, not
  computing. A genuinely hung run (PID at 0.0% CPU, 0-byte WAL,
  holding the test DB) confirmed the suite does not complete on its
  own; earlier "9-minute" runs were killed, not finished.
* **Per-file fast, full-suite catastrophic.** Pure DataCase files
  run in ~0.06s; `settings_live_test.exs` 24 tests in 1.4s. The
  cost is a *scale/global* effect, invisible per-file.
* **The ~1s inter-test gap.** Under `--trace`, per-test durations
  are tiny (7–14ms) but ~1s of wall-clock separates consecutive
  tests. Per-test ms **excludes `on_exit`**, so the gap is teardown.
* **Measured proof.** `acquisition_live_test.exs`: 27 tests,
  reported test time **2.8s**, wall **9.0s** — a **6.2s teardown
  overhead (~230ms/test)**.

**Mechanism (confirmed by instrumentation, 2026-05-22).** LiveViews
fire background work via fire-and-forget
`Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, …)`. The
costly orphans are the **action-triggered HTTP tasks**, not the
mount load (the mount load completes in ~10ms and is gone before
teardown). The canonical offender: `acquisition_live.ex:782`'s
`run_search_one` task → `Prowlarr.search` → `Req.get`.

Drain instrumentation on `acquisition_live_test.exs` caught **10
tasks per run stuck in `:timer.sleep` inside `Req.Steps.run_plug`**,
each forcing the `data_case.ex` drain to its full **1000ms** ceiling.
Completed searches are fast (0–6ms, stub returns instantly); the
stuck ones **never return**. Root: an orphan that outlives its test
runs after `on_exit` has erased the cached `Req.Test` stub client
(`{Prowlarr,:client}` in `:persistent_term`), so it rebuilds via
`Prowlarr.default_client/0` and hits a **retry-enabled** client whose
backoff `Process.sleep` (the only sleep in Req — `steps.ex:2313`)
blocks. A handful of stuck orphans under the *global* supervisor
poison **every subsequent test's** drain → cumulative minutes →
effective hang. This matches the observed ~1s gap across hundreds of
tests. Before the drain (commit `9528cc1b`, 2026-05-21) there was no
teardown wait, ~30s suite.

The drain is a **band-aid over unowned async work**. The cure (own
the async so orphans can't exist) is simultaneously faster, more
correct, and more maintainable.

**Ruled out (red herrings, both reverted):** the mount-load task
(`:159`, completes too fast to be drained) and the TMDB
`RateLimiter` sleep (not in this call path).

## Principles (codified in [ADR-049])

1. **The suite always terminates within budget, and that budget is
   observable.** A wall-time / CI gate fails on regression.
2. **Async work is owned, never orphaned.** Background tasks spawn
   under a supervisor tied to the owning process (LiveView
   `assign_async`/`start_async`, awaitable via `render_async`) —
   never fire-and-forget under a global supervisor. Teardown is then
   O(1); no global drain needed.
3. **Tests drive async to completion; they never rely on teardown to
   wait.** A test that mounts an async LiveView awaits its result
   before asserting.
4. **Tests never wait on wall-clock for synchronization** — no
   `sleep`-to-settle, no real network/IO, bounded timeouts.
5. **Isolation enables parallelism** — global mutable state injected
   not mutated; a DB-parallelism strategy that's safe (process
   partitioning over async-on-shared-SQLite).
6. **Taxonomy with budgets** — pure / integration / smoke / E2E,
   each with when-to-use + a time budget, applied uniformly across
   Elixir / bun / Playwright.
7. **Mechanical enforcement** — Credo checks (no fire-and-forget
   global `start_child` in the web layer; no `sleep`-for-sync) + a
   CI suite-time gate.

## Decisions made

Append-only log.

* `2026-05-22` — **Root cause = unowned LiveView async drained in
  `on_exit`.** Confirmed by `--trace` wall-vs-reported gap on
  `acquisition_live_test.exs` (2.8s reported / 9.0s wall). The drain
  (`9528cc1b`) is a symptom-mask; the seam is fire-and-forget
  `Task.Supervisor.start_child` under the global supervisor.
* `2026-05-22` — **Performance is an architecture property, not a
  speed hack** (user steer). Don't trade away the
  test-isolation-hardening guarantees; fix at the seam so the result
  is faster *and* more correct. Aligns with the standing
  "architectural fixes, not symptom covers" stance.
* `2026-05-22` — **Enforcement is mechanical** (Credo + CI budget
  gate), per the repo's code-as-spec norm.
* `2026-05-22` — **Immediate fix: grace-then-terminate drain.**
  `data_case.ex` drain waits a 100ms grace (enough for fast sqlite DB
  tasks to finish cleanly, preserving the Category-B no-post-release-
  write guarantee) then kills stragglers. Suite went 9+ min hang →
  ~55s green. Bridge until owned-async lands; then the drain is moot.
* `2026-05-22` — **LiveView tests get stricter treatment, not a
  separate looser suite.** Same suite + same discipline; enforce
  owned-async via Credo (and eventually a teardown orphan assertion)
  rather than quarantining LiveView tests with relaxed setups.
* `2026-05-22` — **Follow-ups closed; campaign shipped.** Drain kept
  as permanent O(grace) safety net (context-layer async still orphans);
  CI precommit wrapped in `timeout -k 60 900` (suite-time gate); sleeps
  assessed (flaky class gone, rest bounded timer waits, no clean check).
* `2026-05-22` — **Owned-async rollout complete.** All 8
  grandfathered LiveViews converted across 5 batches (watch_history/
  console/status; review/upcoming; entity_modal; acquisition;
  settings). Pattern: view loads → `start_async`/`handle_async`;
  must-outlive work → context `*_async` (Maintenance, Acquisition,
  Watcher.Supervisor, Review, ReleaseTracking); fast local ops →
  synchronous. MC0019 grandfather list empty → rule fully enforced.
* `2026-05-22` — **Enforcement + skill shipped.** `MC0019
  OwnedAsyncInWeb` Credo check bans fire-and-forget
  `Task.Supervisor.start_child` in `lib/media_centarr_web` (8 LiveViews
  grandfathered as the rollout backlog). `automated-testing` skill now
  carries the async-ownership principles + a runner/diagnostics
  playbook (`--slowest`/`--trace`/`--repeat-until-failure`, the
  `pkill -f 'mix test'` self-kill and `| tail` buffering gotchas).
  First rollout site: AcquisitionLive mount-load → `start_async`.
* `2026-05-22` — **Fixed first unmasked Category-F flake.** The
  faster drain surfaced a render-vs-assertion race in
  `acquisition_live_test.exs` ("matched queue item" test) that the
  1000ms drain had been masking; fixed with `wait_until` (poll-with-
  deadline) per Principle 3. 8/8 repeat runs green.

## Next steps

Ordered by leverage; ship one coherent change at a time.

1. **Write [ADR-049]** — principles 1–7 as a repo-wide decision.
2. **Proof case: acquisition mount-load seam.** Convert
   `acquisition_live.ex:159` `start_child` load to LiveView
   `start_async`/`handle_async`; update `acquisition_live_test.exs`
   to `render_async`. Target: 9.0s → ~3s on that file, still green.
3. **Roll out owned-async** to remaining fire-and-forget sites
   (acquisition action sites 710/744/782/1064; status, upcoming,
   review, entity_modal, console_live/shared, release_tracking).
4. **Remove the band-aids.** Once no fire-and-forget global
   `start_child` remains: delete/bound `drain_supervised_tasks`,
   reassess `busy_timeout: 10_000`. Verify the full suite returns to
   ~30s and terminates deterministically (flake gate:
   `--repeat-until-failure`).
5. **Add enforcement.** Credo check banning global `start_child` in
   the web layer + `sleep`-for-sync; CI suite-time budget gate.
6. **Cross-suite pass.** Apply taxonomy + budgets to bun and
   Playwright; E2E `workers:1` serial ×2 input methods is the
   E2E lever (server-isolation/sharding).
7. **Evolve the `automated-testing` skill** — principles + runner
   playbook (mix test/`--trace`/`--slowest`/flake-detect, bun,
   Playwright, partition strategy, and the `pkill -f 'mix test'`
   self-kill gotcha).

## Completion criteria

* Full `mix test` terminates deterministically at a budget near the
  historical ~30s, verified under `--repeat-until-failure`.
* No fire-and-forget global `Task.Supervisor.start_child` in the web
  layer; the global teardown drain is gone or provably O(1).
* [ADR-049] merged; `automated-testing` skill carries the principles
  + runner playbook.
* Credo + CI suite-time gate enforce the rules mechanically.
* The test-isolation-hardening determinism guarantees are preserved
  (no reintroduced flakes).

## Pointers

* `test/support/data_case.ex` — `drain_supervised_tasks` /
  `setup_sandbox` (the teardown drain).
* `config/test.exs` — `busy_timeout: 10_000`, `pool_size`.
* `lib/media_centarr_web/live/acquisition_live.ex` — proof-case
  seam (`start_child` sites 159/710/744/782/1064).
* `campaigns/test-isolation-hardening.md` — the campaign whose
  correctness fixes introduced the drain; its determinism
  guarantees must be preserved.
* [ADR-044] no-blocking-io-in-liveview-handlers — adjacent
  async-discipline decision.

[ADR-049]: ../decisions/architecture/2026-05-22-049-testing-principles.md
[ADR-044]: ../decisions/architecture/2026-05-14-044-no-blocking-io-in-liveview-handlers.md
