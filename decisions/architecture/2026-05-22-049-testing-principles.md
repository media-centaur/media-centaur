---
status: accepted
date: 2026-05-22
amended: 2026-09-08
---
# Testing principles: a well-managed, high-performance suite

## Context and Problem Statement

The suite regressed from about thirty seconds to a hang, and nobody noticed until someone ran it: a teardown drain compensated for LiveViews firing unowned background tasks, and nothing budgeted or observed wall time. Performance is an emergent property of correct, well-architected tests, not a speed hack; a change that makes the suite faster but less correct is the wrong change. These principles apply to every suite: `mix test`, `bun test`, Playwright.

## Decision Outcome

1. **The suite terminates within an observed budget.** Wall time is measured and gated; a regression past the budget fails like a compiler warning. A suite that can hang is broken.
2. **Async work is owned, never orphaned.** View loads use `start_async/3` or `assign_async/3`, monitored by the LiveView and awaitable with `render_async/1`. Side effects that must outlive the view go to a durable supervised home (Oban, a named service). Fire-and-forget `Task.Supervisor.start_child` from the web layer is forbidden (MC0019). This refines [ADR-044](2026-05-14-044-no-blocking-io-in-liveview-handlers.md): its rule stands, its manual task-and-send shape does not.
3. **Tests drive async to completion.** A test awaits the result it mounted before asserting; nothing depends on teardown to wait.
4. **No wall-clock synchronisation.** No `Process.sleep`; synchronise on a condition with a bounded timeout. No real network or off-process I/O; stub at the boundary.
5. **Isolation enables parallelism.** Global mutable state is injected or reset per test. For SQLite parallelism prefer process partitioning (`MIX_TEST_PARTITION`) over `async: true` on a shared connection.
6. **Taxonomy with budgets.** Prefer the cheapest kind that proves the behaviour.

   | Kind | DB? | Async? | Budget | Use for |
   |---|---|---|---|---|
   | Pure | no | yes | <5 ms | logic extracted per [ADR-030](2026-04-02-030-liveview-logic-extraction.md) |
   | Integration | yes | no | <50 ms | context APIs, schemas, pipeline stages |
   | Smoke | yes | no | <100 ms | route mounts |
   | E2E | n/a | n/a | per flow | input and navigation (Playwright) |

7. **Mechanical enforcement.** A rule that fits a static check becomes one; prose is the fallback.

**Checkout and check-in (amended 2026-09-08).** The teardown drain is gone. `MediaCentaur.GlobalStateSandbox` checks every `async: false` test out at entry and back in at exit, through the root `MediaCentaur.Case` template that `DataCase` and `ConnCase` compose. Restorable global state (app-owned `:persistent_term`, application env, singletons with a reset) is put back silently; registered processes, app-owned ETS tables, live `TaskSupervisor` children and probed singleton state are compared to the baseline, and a difference fails the test that made it. There is no grace window, because a threshold under load is a flake. The static half is MC0035 (every test module states its ownership through the template) and MC0036 (no global-state write in an async module or in `setup_all`).
