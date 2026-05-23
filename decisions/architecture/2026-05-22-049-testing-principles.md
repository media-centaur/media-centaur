---
status: accepted
date: 2026-05-22
---
# Testing principles: a well-managed, high-performance suite

## Context and Problem Statement

The Elixir test suite regressed from ~30s to a **non-terminating
hang**, and nobody noticed until a contributor tried to run it. The
proximate cause was a correctness patch shipped without a
performance guardrail: the test-isolation-hardening campaign added
`drain_supervised_tasks` to `DataCase` `on_exit` (commit `9528cc1b`,
2026-05-21) to stop async tasks from hitting the DB after sandbox
release. The drain waits up to 1000ms per lingering
`MediaCentaur.TaskSupervisor` child. Because many LiveViews fire
background work on mount via raw
`Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, …)` and
tests never await it, those tasks are orphaned under the *global*
supervisor — so teardown blocks on them, ~230ms–1000ms per test,
invisible in per-test timing (it runs in `on_exit`). Across
thousands of tests, and with any task that blocks longer or never
terminates, the suite stops completing.

Three things failed at once:

1. **No feedback loop.** Suite wall-time was neither budgeted nor
   observed, so an 18×+ regression shipped silently.
2. **A symptom-mask, not a seam fix.** The drain compensates for
   unowned async work instead of removing it.
3. **No mechanical guard.** Nothing prevented fire-and-forget global
   tasks from accumulating.

This ADR pins the principles that keep the suite well-managed and
high-performance. The governing stance: **performance is an emergent
property of correct, well-architected tests, not a speed hack.** A
change that makes the suite faster but less correct or less
maintainable is the wrong change. These principles apply to every
automated suite — Elixir `mix test`, JS `bun test`, Playwright E2E.

## Decision Outcome

### Principle 1 — The suite terminates within an observed budget

Each suite has a wall-time budget. The budget is measured routinely
and gated in CI; a regression past it fails the build, the same way
a new compiler warning does. A suite that can hang is a broken
suite. *Rationale: the absence of this principle is the sole reason a
30s→hang regression shipped unseen.*

### Principle 2 — Async work is owned, never orphaned

Background work spawns under a supervisor tied to the lifecycle of
the process that needs it:

* **View data loads** use Phoenix LiveView `assign_async/3` or
  `start_async/3`. The task is monitored by the LiveView, cancelled
  when the LiveView dies, and **awaitable in tests via
  `render_async/1`**. Multi-assign atomic updates and identity-aware
  stale-result drops are expressible in `handle_async/3` — the
  manual pattern's advantages without its ownership gap.
* **Side-effects that must outlive the view** (e.g. dispatching
  grabs to the download client) go to a **durable, supervised home**
  — Oban, or a named GenServer/service — never a bare
  `Task.Supervisor.start_child` whose lifecycle nobody owns and no
  test can await.

Fire-and-forget `Task.Supervisor.start_child(MediaCentaur.Task
Supervisor, …)` from the web layer is **forbidden**. Teardown then
needs no global drain because there is nothing to drain.

### Principle 3 — Tests drive async to completion

A test that mounts an async LiveView **awaits the async result**
(`render_async/1`, or `assert_receive` on the completion message)
before asserting. Tests never depend on `on_exit`/teardown to wait
for in-flight work. Awaiting is the test's job; cleanup is O(1).

### Principle 4 — Tests never wait on wall-clock to synchronize

No `Process.sleep`/`:timer.sleep` to "let things settle"; synchronize
on a condition (`assert_receive`, `render_async`, poll-with-deadline
on a deterministic predicate). No real network or off-process I/O —
stub at the boundary (`Req.Test`, `NoopImageDownloader`). Every
`receive`/await has a bounded timeout. *Rationale: wall-clock waits
are both slow and flaky; they trade determinism for nothing.*

### Principle 5 — Isolation enables parallelism

Tests that share no mutable global state can run in parallel.
Therefore: global mutable state (`:persistent_term`, named
processes, ETS) is injected or reset per-test, not mutated in place.
For DB parallelism on SQLite, prefer **process partitioning**
(`MIX_TEST_PARTITION`, one DB file + one BEAM per partition) over
`async: true` on a shared connection — partitioning sidesteps both
single-writer contention and global-cache bleed by construction.

### Principle 6 — Taxonomy with budgets

Every test is one of four kinds, each with a when-to-use rule and a
per-test budget:

| Kind | DB? | Async? | Budget | Use for |
|---|---|---|---|---|
| **Pure** | no | yes | <5ms | logic extracted from LiveViews/contexts ([ADR-030]) |
| **Integration** | yes | no | <50ms | context APIs, schemas, pipeline stages |
| **Smoke** | yes | no | <100ms | route mounts (`page_smoke_test`) |
| **E2E** | n/a | n/a | per-flow | input/navigation (Playwright) |

Prefer the cheapest kind that proves the behaviour. The bias is
toward pure tests; reach for integration only when the behaviour is
the wiring.

### Principle 7 — Mechanical enforcement

Rules that fit a static check become one, per the repo's
code-as-spec norm:

* A Credo check bans fire-and-forget global `start_child` in the web
  layer (Principle 2) and `sleep`-for-sync in tests (Principle 4).
* A CI step gates suite wall-time against the budget (Principle 1).

Prose in a skill or this ADR is the fallback only where a check
can't express the rule.

## Relationship to [ADR-044]

[ADR-044] (no blocking I/O in LiveView handlers) is **refined, not
overturned**. Its core rule stands: slow/external work must not run
synchronously on the LiveView process. This ADR changes only the
*preferred async mechanism*: ADR-044 listed the manual
`Task.Supervisor.start_child + send + handle_info` loop as the
canonical shape. That shape orphans tasks under the global
supervisor (untestable, drain-dependent). **Going forward,
`start_async`/`assign_async` (owned, awaitable) is the canonical
shape for view data loads**; the manual global-`start_child` loop is
deprecated for that purpose. Work that must outlive the LiveView
moves to a durable home (Principle 2). ADR-044's audit trigger list
still applies to what counts as "slow".

## Consequences

* Good — teardown becomes O(1); the global drain and the inflated
  `busy_timeout` can be removed, restoring the suite to its ~30s
  budget while *keeping* the determinism the isolation campaign won.
* Good — owned async is more correct (no post-test DB writes), more
  testable (`render_async`), and idiomatic Phoenix.
* Good — the budget gate makes the next regression impossible to
  ship silently.
* Bad — converting existing call sites is real work (≈7 LiveViews +
  helpers), and "must-outlive" side-effects need a durable home
  rather than a one-line task. Paid once per site; bounded.
* Bad — partitioning multiplies compile/startup cost per partition;
  the wrapper must compile once and fork. Acceptable for the
  wall-time win on a 12-core box.

[ADR-030]: 2026-04-02-030-liveview-logic-extraction.md
[ADR-044]: 2026-05-14-044-no-blocking-io-in-liveview-handlers.md
