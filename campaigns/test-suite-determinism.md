---
status: in-progress
started: 2026-09-08
last_updated: 2026-09-08
---
# A full run is green at every seed

## Goal

`mix test` should pass or fail on the code, not on the order ExUnit happened to
pick. Today it does not: a full run intermittently fails tests that pass alone,
and the failures come from state that outlives the test that created it. The
cost is not the minutes spent re-running — it is that `mix precommit` stops
being a gate. Shipping v1.17.0 required deciding, by hand, whether three
failures were real; the only way to answer was to run the suite again and see
if they came back.

This campaign is about the **problems**, catalogued below with what has been
measured about each. It does not prescribe fixes.

## Status

**A and B built 2026-09-08, C fixed at its one site; verification across
seeds remaining.** The design
([`docs/plans/2026-09-08-test-suite-determinism-checkout-design.md`](../docs/plans/2026-09-08-test-suite-determinism-checkout-design.md))
was decided on soundness alone and implemented the same day:

* `MediaCentaur.Case` is the root template every test module uses;
  `DataCase`/`ConnCase` compose it. A sync test is checked out at entry and
  back in at exit by `MediaCentaur.GlobalStateSandbox`: restorable state put
  back, verified state compared, a leak contained and raised as
  `GlobalStateSandbox.Leak` on the test that made it.
* `:accepted` is gone. Dispositions are `:sandboxed`, `:unobservable`,
  `{:reset, mfa}`, `{:probe, mfa}`; the inventory test checks the functions
  exist and the probes read their baseline at rest.
* A live `TaskSupervisor` child at check-in fails the test (B's detector);
  the `DataCase` drain is gone.
* MC0035 and MC0036 are the static half.
* A sync test's `Req.Test` stubs are shared (same condition as the SQL
  sandbox), and a request no stub could answer — logged by the dying
  process, recorded by `GlobalStateSandbox.StubOrphans` — fails the test
  that made it. That is B's detector for the case zero tolerance cannot
  see, and it found eight smoke tests and four sync tests that had been
  requesting unstubbed upstreams inside ExUnit's log capture all along.
* Six full runs at `9a2113af` measured the problems (table below); after the
  change, one full run at seed 281658 is green with zero leaks, back to back
  with the old harness at the same wall time (82.4 s vs 82.5 s).

Measured before the change, at `9a2113af`:

| Run | Result | What the log said |
|---|---|---|
| seed 281658 | green | one orphaned `:tmdb` task crash (`Discovery.ensure_artwork_async/1`) |
| seed 209562 | green | clean |
| seed 30892 | 1 failure | `review_live_test.exs:97` — `render_async/1` past its 100 ms default; one orphaned `:tmdb` task crash (`Activities.ensure_artwork_async/1`) |
| seed 921528 | green | clean |
| seed 310401 | 1 failure | `integration_health/verifier_test.exs:28` — found a Prowlarr URL in Config; one orphaned `:tmdb` task crash |
| seed 281658, probed | green | 356 of 2,926 sync tests exit with an app-owned `:persistent_term` key off the pristine baseline |

Instances are also logged in the session memory
`project-suite-residual-concurrency-flakes`.

## The problems

### 1. The sandbox covers rows, and the suite has more state than rows

`Ecto.Adapters.SQL.Sandbox` is airtight for database rows and knows nothing
about `:persistent_term` or long-lived processes. Every context-owned cache and
every named GenServer therefore survives the test that wrote it. This is
understood — `MediaCentaur.GlobalStateSandbox` exists for it — but the coverage
is an inventory of judgments, one line per supervision-tree child, and a
judgment is only as good as the day it was written.

### 2. An `:accepted` reason is prose that nothing verifies

`GlobalStateSandbox` classifies each singleton `:sandboxed`, `:stateless`,
`:reset` or `:accepted`, and its test enforces two things: every child is
classified, and every `:reset` is actually wired. Nothing checks that an
`:accepted` reason is *still true*.

Worked example, 2026-09-08: `ErrorReports.Buckets` was `:accepted` because
"bucket tests drive named instances". That was true when written. The Status
board reads the globally named process through `ErrorReports.list_buckets/0`,
so as LiveView tests for the board were added they had no choice but to ingest
into the singleton — four files now do. Nine buckets of fixture messages
survived their tests and broke three unrelated assertions. The classification
was never revisited because nothing asked it to be.

### 3. Some singletons cannot be isolated by a test that needs the real read path

A unit test can drive a named instance. A LiveView test cannot: it exercises
production code that reads the singleton by name. `ErrorReports.list_buckets/0`
and `Downloads.QueueMonitor` are both in this position. So the test must write
shared state, and the state must then be reset by something outside the test —
which is problem 1 again, reached from the other direction.

Related and not the same: a singleton that is *not started* under `:test` looks
contained but isn't. `QueueMonitor` is not started, yet `queue_monitor_test`
starts its own, and its cached `%QueueState{}` stayed in `:persistent_term` for
the rest of the run.

### 4. Background tasks outlive the test that owns their HTTP stub

Context functions legitimately fire supervised tasks under the global
`MediaCentaur.TaskSupervisor` — searches, artwork fetches, rescans. A task
started from a test carries `$callers`, so `Req.Test` resolves the test's stub
correctly *while the test is alive*. Ownership dies with the test process. A
task still running past that point raises `cannot find mock/stub`, and the
crash is logged into whichever test is running next.

`DataCase` drains orphans at teardown, but teardown runs in `ExUnit.OnExitHandler`
— after the owner is gone, which is already too late for the stub.
`MediaCentaur.TaskAwaits` is the opt-in remedy, and being opt-in it depends on
each author knowing to call it. Its own moduledoc had drifted to name two
functions that no longer exist.

### 5. Missing isolation grows bespoke cleanup inside the tests

Where shared state leaks, individual tests defend themselves: pre-clear the
buckets before asserting, dismiss a fingerprint on exit, sweep leaked
error-severity buckets before a `refute`. Each workaround is local, invisible
to the next author, and indistinguishable from a deliberate fixture. They also
suppress the evidence — a test that cleans up after the leak stops reporting it.

### 6. The symptom points away from the cause

A failing run is not a reliable guide to its own cause. The run that exposed
problem 2 was full of `cannot find mock/stub :tmdb` crashes, which were a real
defect (problem 4) but not the reason the tests failed — `durable_diagnostics`
is off under `:test`, so a logged crash mints nothing. Reading the log led to
the wrong seam; only probing the actual state inside the failing test found the
right one. Any approach here has to make the state a test depends on
inspectable, not just make the failure rarer.

### 7. Ordering-dependent failures defeat the usual attribution check

The standard defence — "reproduce it on `main` with your work stashed" — does
not hold for this class. A full-suite failure can be a pure function of test
ordering, and ordering shifts with the *test count*. Main at the same seed with
a different number of tests interleaves differently and passes, which reads as
exculpation when it is nothing of the kind. Attribution currently requires
padding main with as many inert tests as the branch adds.

Separately, two rate-based classes remain and are not ordering at all: SQLite
write contention under 24 parallel cases, and `assert_receive` deadline
pressure under full-suite load. They need distinguishing from the above before
anything is attempted, because a fix for one does nothing for the other.

### 8. The restore runs at the wrong edge, for the wrong set of tests

`GlobalStateSandbox.restore!/1` is called from `DataCase.setup_sandbox/1` and
nowhere else, so it runs at the *entry* of a `DataCase` or `ConnCase` test. A
test's leak is therefore cleaned by the next test — provided the next test is
one of those. A plain `ExUnit.Case, async: false` test gets no restore and
reads whatever the previous test left. 38 such files exist, and the sync phase
is shuffled by seed, so whether one of them follows a dirty exit is a property
of the seed.

Worked example, 2026-09-08, seed 310401: `IntegrationHealth.VerifierTest`
nulls the download-client keys in its own setup (a problem-5 defence) and
asserts that Prowlarr is *not configured*. A `DataCase` test before it had set
a Prowlarr URL through `Config.update/2`; nothing restored it, and
`Capabilities.configured?(:prowlarr)` was true. The probe says how exposed this
is: after 356 of the run's 2,926 sync tests, at least one app-owned
`:persistent_term` key differs from the baseline — 241 times the Config map
itself — and that count is measured *after* `on_exit`, so the hand-rolled
restores of problem 5 are already netted out.

Two stores are outside the inventory altogether: the named ETS tables of the
projections and caches, and the `:media_centaur` application env (17 test
files save and restore it by hand). Neither leaked in the probed run. The
cache workers are not started under `:test`, so a projection table belongs to
whichever process first touched it and dies with it — which also makes the
three `on_exit` `:ets.delete` sites in the suite inert code.

## What the measurement says

Step 1 of the plan was to decide whether the seven problems are one or several.
They are three, and two of the seven are not problems in their own right.

**A. Containment is at the wrong edge and covers the wrong set** — problems
1, 2, 3, 5 and 8. One mechanism, seen from five sides: the state a sync test
depends on is reset by the *next* test's entry, only when that test is a
`DataCase`, only for `:persistent_term` and three named processes, and the
claim that anything else is safe is a sentence nobody re-reads.

**B. A supervised task's lifetime is not its stub owner's** — problem 4. Four
of six runs logged exactly one `cannot find mock/stub :tmdb` crash, from
`Discovery.ensure_artwork_async/1` or `Activities.ensure_artwork_async/1`,
both reached from `discovery_live_test.exs` tests that already call
`await_supervised_tasks/0`. The spawn therefore happens *after* the await
returns — a LiveView or broadcast path, not yet traced. It failed no test in
these runs; it is log noise until the day it is not.

**C. Deadline pressure under load** — the rate-based tail of problem 7.
`render_async/1` at its 100 ms default in `review_live_test.exs:97`. Rate, not
order. `Database busy` did not appear in six runs.

Problems 6 and 7 are what A looks like without a detector. The probe
attributed every `:persistent_term` change in the run to a test, to within
one; with detection at the source, a symptom names its cause and the
ordering-attribution problem has nothing left to attribute.

## Decisions made

* `2026-09-08` — Opened after the v1.17.0 ship, where three `HealthBoardLiveTest`
  failures had to be adjudicated by hand before the release could proceed. The
  specific leak was fixed (commit `9451b095`), but the class it came from is
  what this campaign is about.
* `2026-09-08` — Scope is **isolation and determinism only**. Suite wall time is
  [`serial-test-audit.md`](serial-test-audit.md) and stays there; the two
  campaigns pull in opposite directions (more parallelism, less shared state)
  and must not be merged.
* `2026-09-08` — No approach chosen, deliberately. The problems above were
  found one at a time over months, each fixed where it surfaced; the point of
  writing them down together is to design once against all seven rather than
  add an eighth local remedy.
* `2026-09-08` — Re-measured at `9a2113af` (six full runs). The seven problems
  are three: A (1, 2, 3, 5, 8), B (4), C (the rate-based tail of 7); 6 and 7
  are consequences of A having no detector. Recorded under *What the
  measurement says*.
* `2026-09-08` — `MediaCentaur.StateProbeFormatter` lands as a measurement
  instrument, not a fix. It is opt-in through `--formatter` and changes
  nothing in a normal run. It is the first thing in the suite that says which
  test *wrote* a piece of global state rather than which test read it.
* `2026-09-08` — Design decided on soundness alone (owner's instruction:
  "regardless of the work it takes"), recorded in the design doc, and built.
  One root template rather than a sync-only one; zero tolerance for a live
  task; entry-dirty fails the first sync test; no prose disposition;
  supervisor-aware containment (killing a supervised child stopped the
  application on day one); `setup_all` is outside every checkout.
* `2026-09-08` — The `DataCase` drain is retired: it hid problem B. ADR-049
  amended.

## Next steps

1. Run the full suite at several seeds with the test count varied (pad with
   inert async tests) and confirm zero leaks and zero failures; record the
   seeds here.
2. ~~Trace the artwork spawn that outlived the discovery test's await.~~
   Done: it was the smoke tests' discovery modal and the sync tests'
   feed, both now stubbed and awaited; seeds 310401, 30892, 260789 run clean.
3. Close the campaign: bucket every remaining item by destination.

## Completion criteria

* A full `mix test` passes at any seed, repeatedly, with the test count varied.
* A shared-state escape is caught by a check rather than by a reader's
  judgment about whether a written reason is still true.
* No test carries cleanup for state another test created.
* `cannot find mock/stub` does not appear in a clean run.
* The probe reports no sync test exiting with global state off the baseline.

## Pointers

* `test/support/global_state_sandbox.ex` — the inventory and its vocabulary.
* `test/support/data_case.ex` — sandbox setup and the teardown orphan drain.
* `test/support/case.ex` — the root template; `test/support/global_state_sandbox/`
  — the snapshot value type and the leak error.
* `test/support/task_awaits.ex` — how a test drives its supervised tasks to
  completion.
* `credo_checks/test_case_template.ex` (MC0035),
  `credo_checks/global_state_writes_checked_out.ex` (MC0036).
* `test/support/global_state_sandbox/stub_orphans.ex` — the `:logger`
  handler behind the stub-less-request store.
* `test/support/state_probe_formatter.ex` — the per-test state probe; its
  moduledoc has the run recipe.
* `test/media_centaur/global_state_sandbox_test.exs` — the two checks that do
  exist today.
* [ADR-027](../decisions/architecture/2026-03-07-027-regression-tests-append-only.md)
  — regression tests are append-only.
* [ADR-049](../decisions/architecture/2026-05-22-049-testing-principles.md) —
  testing principles, including context-layer background work on supervised
  tasks.
