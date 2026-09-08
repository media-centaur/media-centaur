---
status: planning
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

Planning. No approach chosen. Seven distinct problems below; instances are
recorded in the session memory `project-suite-residual-concurrency-flakes` and
in the git history of the fixes that have already landed piecemeal.

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

## Next steps

1. Decide whether these are one problem or several. Problems 1, 2, 3 and 5 may
   be one thing seen from four sides; 4, 6 and 7 look genuinely separate.
2. Re-measure before designing. The instance log spans months and several of
   its entries have been fixed since; confirm which still reproduce.
3. Then design.

## Completion criteria

* A full `mix test` passes at any seed, repeatedly, with the test count varied.
* A shared-state escape is caught by a check rather than by a reader's
  judgment about whether a written reason is still true.
* No test carries cleanup for state another test created.
* `cannot find mock/stub` does not appear in a clean run.

## Pointers

* `test/support/global_state_sandbox.ex` — the inventory and its vocabulary.
* `test/support/data_case.ex` — sandbox setup and the teardown orphan drain.
* `test/support/task_awaits.ex` — the opt-in task drain.
* `test/media_centaur/global_state_sandbox_test.exs` — the two checks that do
  exist today.
* [ADR-027](../decisions/architecture/2026-03-07-027-regression-tests-append-only.md)
  — regression tests are append-only.
* [ADR-049](../decisions/architecture/2026-05-22-049-testing-principles.md) —
  testing principles, including context-layer background work on supervised
  tasks.
