---
status: planning
started: 2026-05-21
last_updated: 2026-05-21
---
# Test-isolation hardening

## Goal

Make the test suite pass deterministically under full-suite
concurrent load. CI flapped repeatedly during the
macos-platform-support campaign on a *different* pre-existing
flake each push, masking the platform refactor's actual CI signal.
The flakes pre-date that work — they were tolerated because the
`mix.exs` precommit alias had a typo (`compile --warning-as-errors`
singular = silently-unrecognized flag) and individual flake
firings under CI's load distribution made each "look transient".

This campaign closes the gap: every test passes every time, both
locally and on CI, with no `@tag :skip`, no manual retries, no
"just push again". When done, the `--warnings-as-errors` typo can
be fixed and Linux CI will stop flapping.

## Status

Planning. Initial flake inventory below from the macos-platform-support
campaign's CI runs (2026-05-20 → 2026-05-21). No code changes yet.

## Architectural posture

1. **Fix at the seam, not the symptom.** Don't `@tag :flaky` or
   bump budgets to mask. Find the global-state mutation, async
   process, or ownership boundary that's actually broken.
2. **Test the test infrastructure.** Where a fix shape applies to
   many test files (e.g. on_exit DB writes), encode the fix as a
   reusable test helper + a Credo check that prevents reintroduction.
3. **No timing assertions on noisy quantities.** Wall-clock mount
   duration under concurrent load is inherently noisy. Replace
   "took N ms" assertions with structural assertions (query count,
   process count, render-once invariant) where they survive.
4. **One commit per category.** Each commit fixes ONE class of
   flake and ships independently. CI must show stable green for
   the touched-file family before moving to the next class.

`@tag :flaky`, `--repeat-until-failure` in production CI, and
`continue-on-error: true` are explicitly out-of-bounds.

## Observed flakes (the inventory)

Each row from CI runs during the macos-platform-support campaign.
Categorized for attack-planning.

### Category A — `on_exit` DB writes without sandbox ownership

The on_exit callback fires from `ExUnit.OnExitHandler` — a
different process from the test, without the test's DB sandbox
ownership. Any DB write inside it races against teardown.

| File:line | Symptom |
|---|---|
| `test/media_centarr_web/live/settings_live_acquisition_test.exs:106` | `Config.update/2` → `Settings.find_or_create_entry/1` exits with "no process" / OwnershipError. **FIXED** in `ef386275` (moved cleanup to setup-start). |
| `test/media_centarr_web/live/settings_live_acquisition_test.exs:157` | Same pattern. **FIXED** in `ef386275`. |

**Suspected fanout:** any of the 71 files using `on_exit(fn -> ...)`
where the callback body writes to the DB.

### Category B — Async task DB ownership

`Task.Supervisor.async/2` (or similar) spawns a child that does DB
work AFTER the parent test's sandbox connection has been released.
Surfaces as `OwnershipError` or "owner exited" logged from the
async task, often pooling into ErrorReports.

| File:line | Symptom |
|---|---|
| `test/media_centarr/error_reports/buckets_test.exs:110-118` | `refute_receive {:buckets_changed, _}` fails because async tasks (SettingsLive's `start_async_settings_load`, WatchHistoryLive's `start_async_history_load`) emit DB errors into the bucket aggregator after the test should have settled. |

**Suspected fanout:** every LiveView that uses `start_async` with
a DB query (SettingsLive, WatchHistoryLive likely; probably more).
LiveView's `start_async` spawns a non-linked Task — the test's
sandbox owner doesn't know about it.

### Category C — Mount-budget noise

Per-test wall-clock assertions on LiveView mount durations.
Under concurrent-test load (~24 processes), mount time has ~30-40%
variance. Tight budgets (35ms, 80ms) bust on the noisy tail.

| File:line | Symptom |
|---|---|
| `test/media_centarr_web/page_smoke_test.exs:191` | `/library?selected=<tv-tracked>` took 99ms, budget 80ms. |
| `test/media_centarr_web/page_smoke_test.exs:224` | `/library?selected=<movie-w-subs>` took 49ms, budget 35ms. |

All `live_within!/3` callers in `page_smoke_test.exs`.

### Category D — Query-count budget on full-suite load

`NoDbOnRenderTest` asserts a query budget per page mount. Under
load, settings-entry queries pile up — likely `Config.get/1` cache
misses when other tests have invalidated `:persistent_term`.

| File:line | Symptom |
|---|---|
| `test/media_centarr_web/no_db_on_render_test.exs:145` | `/library` issued 52 queries (40 to `settings_entries`), budget 45. All `Config.get/1` cache misses. |

### Category E — Cross-test global-state bleed

Tests mutate `:persistent_term`, `Application` env, or shared
registries; the mutations leak into later tests in the same suite
run.

| File:line | Symptom |
|---|---|
| `test/media_centarr/library/progress_test.exs:90` | `assert %WatchProgress{position_seconds: 30.0} = Progress.get(pi.id)` — match failure; the struct came back with a different `position_seconds` than the test wrote. Likely cross-test pollution. |
| `test/media_centarr/query_counter_test.exs:26` | "captures multiple queries in invocation order" — order-dependent assertion that's race-prone under concurrent test execution. |

### Category F — Render-time vs assertion-time race

LiveView render returns a partial DOM (Console drawer body) at the
moment the test reads it; the form / page-body content isn't
rendered yet. Hits string-assertion tests on `render(view)`.

| File:line | Symptom |
|---|---|
| `test/media_centarr_web/live/settings_live_exclude_dirs_test.exs:46` | Asserts `tmp` path in rendered HTML; rendered HTML is just the Console drawer panel. |

Likely overlaps with category B — async settings load races against the
`render(view)` call.

## Decisions made

Append-only log.

* `2026-05-21` — **Phase 1 closed (Category A).** Audit of 71
  on_exit callsites found exactly two DB-write offenders, both
  migrated (`ef386275`, `872ea668`). `MC0018 NoDbInOnExit` Credo
  check (commit `e1d6df06`) mechanically prevents re-introduction
  — empty grandfathered list. Post-Phase-1 CI Linux failures no
  longer include any Category A signatures (run #26235171214: now
  Category B `ErrorReports.BucketsTest` + Category D
  `NoDbOnRenderTest`).

## Next steps

Ordered by leverage — smallest, most-impactful fixes first.

1. **Phase 1 — Category A audit.** Grep every `on_exit(fn -> ...)`
   callback body in `test/`; flag those that call `Config.update`,
   `Repo.*`, `Settings.*`, `Library.*`, any context module. Each
   becomes the same setup-start migration as
   `settings_live_acquisition_test.exs` got. Add a Credo check
   `MC0018 NoDbInOnExit` to prevent reintroduction. Ship.
2. **Phase 2 — Category B async-task pattern.** Audit every
   LiveView using `start_async` with a DB query; ensure the test
   either (a) awaits the async result before assertion, or (b)
   stubs the data source so no DB hit happens. Decide on a
   pattern (probably `Sandbox.allow` for the async pid, or
   inject the async runner as a dep). Ship.
3. **Phase 3 — Category E `:persistent_term` reset.** Add a
   `MediaCentarr.Config.TestReset` helper that clears the cache;
   wire it into `DataCase.setup`. Audit which tests need this
   explicitly. Ship.
4. **Phase 4 — Category C mount budgets.** Replace wall-clock
   budgets with structural budgets where possible (e.g.
   "mounts without N+1" via query counter, "renders within K
   process spawns"). Where wall-clock genuinely is what we care
   about, move those measurements out of `mix test` and into
   `scripts/profile`. Ship.
5. **Phase 5 — Category D query budget.** Likely auto-resolves
   once Phase 3 lands (`:persistent_term` resets stop cache
   misses). Verify and ship.
6. **Phase 6 — Restore the `--warnings-as-errors` typo fix in
   `mix.exs`**. With Categories A–E resolved, Linux CI should
   tolerate the strict flag. Add the `MC0017`-style discipline
   check that catches new flakes by pattern (on_exit DB writes,
   wall-clock budgets). Ship.
7. **Phase 7 — CI stability gate.** Push 10 consecutive trivial
   commits and observe CI green on each. Failures during this
   gate get triaged into the campaign as new categories.

## Completion criteria

* `mix precommit` is green locally and on CI in **10 consecutive
  runs** without retry, with no `@tag :flaky` / `@tag :skip`
  bypasses.
* `mix.exs` precommit alias uses `compile --warnings-as-errors`
  (plural — the documented form).
* New Credo checks (`MC0018 NoDbInOnExit` at minimum) enforce the
  patterns mechanically so the next contributor can't quietly
  re-introduce the same shape.
* The macos-platform-support campaign's deferred macOS Phase 5
  work can proceed against a stable CI baseline.

## Pointers

* `test/media_centarr_web/live/settings_live_acquisition_test.exs`
  — already-fixed Category A example (`ef386275`).
* `lib/media_centarr/config.ex` — `:persistent_term` cache that
  many tests mutate.
* `test/test_helper.exs` — global test setup, ideal home for
  cache-reset hooks.
* `test/support/data_case.ex` — shared DataCase setup that most
  DB tests inherit from.
* `mix.exs` — has `FIXME` comment marking the typo to restore
  (Phase 6 deliverable).
* `lib/media_centarr/query_counter.ex` (if exists) — used by
  `NoDbOnRenderTest` for query-count assertions.
* `campaigns/macos-platform-support.md` — the campaign that
  surfaced these flakes; resumes its macOS Phase 5+ work after
  this campaign closes.
