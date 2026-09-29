---
status: accepted
date: 2026-09-29
---
# A durable job is recorded with the decision that owes it

## Context and Problem Statement

[ADR-076](2026-09-29-076-durability-follows-the-cost-of-losing-the-work.md) says *when* work must be durable: when it carries out a person's decision, or a row records it as pending. It does not say *how*. The `durable-work` campaign's audit found that the sites already on Oban fail in the same few ways, and the sites still to move would repeat them without a common pattern:

* **The job is inserted after the commit.** `Plans` inserts `RunPlan` after the plan's transaction (`plans.ex:325`, `:496`), and three of four `"seeking"` writers do the same for `PursueTarget`. A crash between the two leaves a pending row that no job will ever work on.
* **An insert failure is ignored.** `Pursuits.Commands.Helpers.enqueue_pursue/1` logs the failure and returns `:ok`. `ChangeTarget`'s moduledoc keeps the insert outside the transaction to avoid "a partial enqueue". That premise is backwards: the Lite engine writes jobs through the app's `Repo`, so an insert inside the transaction commits or rolls back with it.
* **Uniqueness drops new work.** `PursueTarget` is unique on `target_id` for 300 s in Oban's default `:successful` states, which include `completed`. Re-arming a target reuses its id (`targets.ex:127`), so re-arming within five minutes of a finished job inserts nothing.
* **Failure is invisible.** No telemetry handler is attached. A raising job records its error in `oban_jobs.errors` and nowhere else: not in the Console, not in ErrorReports, not on Status.
* **An orphaned job is never rescued.** Oban 2.24 enables `Oban.Lifeline` only when it is configured, and it is not. A job running when the node dies stays `executing` for good.
* **Tests run jobs inside the insert.** `testing: :inline` executes the job synchronously in `Oban.insert/1`, which runs inside the caller's transaction. Production never does that. A job's crash then rolls back the decision in tests only, and the ordering this ADR is about is never exercised.

## Considered Options

* **A pending table per context, re-run by a named recovery pass.** This is ADR-076's second row. It suits work that can be re-derived. For a person's decision it rebuilds retries, backoff and failure reporting in every context.
* **Broadway with a table-backed producer.** Broadway provides backpressure and batching, not storage, so the producer would be a hand-built queue.
* **Oban.** It is already in the app, with 13 workers. The Lite engine keeps jobs in the same SQLite file as the domain rows, so a job commits atomically with the decision that owes it. An external queue could not do that.

## Decision Outcome

Chosen option: Oban, used by the rules below. It is the only option that stores the job in the decision's transaction, and it already supplies retries, backoff, uniqueness, pruning and orphan rescue.

A **durable job** is an Oban job that carries work ADR-076 assigns to its first row. A **command** is the context function that records the decision.

1. **Record and enqueue in one transaction.** The command inserts the job in the transaction that writes the decision or the pending state, through `Ecto.Multi` with `Oban.insert/3` or `Oban.insert/1` inside `Repo.transaction`. A failed insert rolls the decision back. Nothing inserts a durable job after the commit, and nothing ignores an insert's result.
2. **Decide synchronously; do the slow work in the job.** A LiveView handler calls the command directly, because a local SQLite write is allowed in a handler (ADR-044, item 2). HTTP calls and media I/O belong to the job. `start_async` never carries a person's decision; it stays with view loads (ADR-049).
3. **The row holds the state; the job only carries the work.** What a person sees ("Importing", "Deleting") is read from a domain row. If the UI shows work as under way, a row says so. Only `MediaCentaur.Jobs` reads `oban_jobs`.
4. **Arguments are ids, and the job re-checks them.** The job first loads its row. If the row has left the pending state, the job returns `:ok` and does nothing. Oban delivers at least once (retries, rescue), so running a job twice must be harmless.
5. **The job ends the pending state.**
   * Success: the job's last write moves the row to its terminal state, in the same transaction as the work's final write.
   * A known permanent failure: the job writes the failure state and returns `{:cancel, reason}`.
   * Any other failure on the last attempt: rule 7's discard hook takes the row out of the pending state.
6. **Unique among jobs that have not started.** A durable job that deduplicates declares `unique: [keys: [...], period: :infinity, states: [:available, :scheduled, :retryable]]`. A double click collapses into the waiting job, which reads the latest state when it starts (rule 4). A request made while a job runs, or after it finished, always inserts: the running job may already have read the state the request changed.
7. **Failure is visible.** One telemetry handler in `MediaCentaur.Jobs`, on `[:oban, :job, :exception]`, logs every failed attempt at `:error` through `MediaCentaur.Log`, so it reaches the Console, ErrorReports and Status. On a discard it calls the worker's `discarded/2` callback, when the worker defines one.
8. **Orphans are rescued.** `Oban.Lifeline` is enabled. Every durable worker declares `timeout/1`, below Lifeline's `rescue_after`, so a job that is still genuinely running is never rescued a second time. A crash delays an orphaned job by at most `rescue_after` plus Lifeline's one-minute interval.
9. **Queues follow the contended resource.** Each queue is named for the resource its jobs contend for: `acquisition` (Prowlarr), `images`, `maintenance`, `self_update`, and a new queue only for a new resource. Work on the library's media files is one such resource.
10. **Tests run jobs as production does.** The test suite uses `testing: :manual`. A durable command's tests assert four things:
    * the row and the job commit together, and neither commits on failure;
    * performing the job completes the work and ends the pending state;
    * performing it twice is harmless;
    * a discard takes the row out of the pending state.

### Consequences

* Good, because a stored pending state always has a stored job, and a crash or restart delays the work instead of losing it.
* Good, because one place logs job failures, and they reach Status like any other `:error`.
* Good, because commands become synchronous writes. The `start_async` and `Task.Supervisor` wrappers around decisions go away.
* Bad, because every job costs two more SQLite write transactions (the fetch `UPDATE` and the completion), and SQLite has one writer. At the rate people make decisions this is negligible. Import runs at library-scan volume, so its move (campaign finding F1) is measured before it commits to one job per file.
* Bad, because a job that is scheduled or snoozed waits up to `stage_interval` (10 s) past its time. An immediately available job is not delayed: the queue is notified on insert, and its fetch waits for the write lock and then sees the committed row.
* Bad, because every durable job must be idempotent (rule 4). That constraint is real work in the jobs that call Prowlarr or delete files.
* Bad, because switching the suite to `:manual` breaks the tests that relied on a job having run by the time `Oban.insert/1` returned. Measured on 2026-09-29, the switch failed 107 tests in 13 files. Most were in the plan path (`run_plan_test`, `drop_planner_test`, `plans_test`, `incoming_live_test`, `reactor/handlers_test`), which campaign finding F3 rewrites anyway.

## Amendments

* **2026-09-29** — Rule 6 first said `states: :incomplete`. That group includes `executing`, so a decision made while a job runs (a release excluded while its plan is being solved) would collapse into a job that had already read the state, and be lost. Corrected to the states of jobs that have not started, before any worker implemented the rule.
