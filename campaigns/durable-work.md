---
status: planning
started: 2026-09-29
last_updated: 2026-09-29
---
# Durable work: every pending state has a job behind it

## Glossary

* **Pending state.** A stored value that says work is under way or
  owed: a status such as `:approved` shown as "Importing", a plan
  `"planning"`, an image queue entry `"pending"`.
* **Durable.** Survives a process crash and a restart: an Oban job, or a
  row a named pass is guaranteed to re-run.
* **Recovery pass.** A named function that re-derives lost work, such as
  startup recovery (`Watcher.Rescan.recover/0`) re-sending unlinked
  files.
* **Carrier.** How work travels today: PubSub message, Broadway pipeline,
  `Task.Supervisor.start_child`, `start_async`, Oban job, GenServer
  state.

## Goal

Bring the codebase in line with
[ADR-076](../decisions/architecture/2026-09-29-076-durability-follows-the-cost-of-losing-the-work.md):
the mechanism carrying each piece of background work matches what
losing it costs, and no stored pending state lacks a stored job behind
it. Found in Review, where an approval shown as "Importing" rode a PubSub
message a crash could lose.

## Status

Planning. Inventory seeded below; nothing classified yet.

## Method

1. Load `elixir:oban-thinking` and `unify_design` before changing any
   site; `automated-testing` before any code (test-first).
2. For each pending state and each carrier site, record: what the work
   is, who triggers it (a person, the system), what losing it costs, the
   ADR-076 row it belongs in, and whether it already complies.
3. Where two callers do the same work, one durable and one
   re-derivable, design one path through the job (ADR-076, last rule) —
   run the `unify_design` pass for it and put the design in *Decisions*
   before code.
4. Move non-compliant sites one per commit, each with a test that kills
   the carrier mid-work (or restarts) and asserts the work completes or
   is reported.

## Inventory (seed — reconcile against the code first)

**Pending states to classify**

| State | Where |
|---|---|
| `PendingFile.status :approved` ("Importing") | `lib/media_centaur/review/pending_file.ex` — known non-compliant |
| `Plan.status` (`"planning"`, …) | `acquisition/plans/plan.ex` |
| `PlanUnit.status` | `acquisition/plans/plan_unit.ex` |
| `Pursuit.state`, `Pursuits.Unit.state` | `acquisition/pursuits/` (event-logged, ADR-039) |
| `Target.status` (`"seeking"`) | `acquisition/target.ex` |
| `ImageQueueEntry.status` (`"pending"`) | `pipeline/image_queue_entry.ex` |
| `Want.status :open` | `release_tracking/want.ex` |
| `AwaitingFile.status :pending` | `episode_mapping/awaiting_file.ex` — waits on a person, not on work |
| In-memory "in flight" UI states (`deleting`) | `review_live.ex`, `title_detail_host/library_events.ex` |

**Carriers to classify**

* `Task.Supervisor.start_child` in 19 files under `lib/` (`git grep -l
  'Task.Supervisor.start_child' -- lib`), including `acquisition.ex`,
  `acquisition/plans.ex`, `activities.ex`, `activities/publisher.ex`,
  `maintenance.ex`, `watcher/rescan.ex`, `library/inbound.ex`,
  `release_tracking.ex`.
* `start_async` in 11 files — a person's destructive act run there
  stops when the page closes (Review and title-detail deletes).
* 75 `Topics.publish` calls in 61 files — only those carrying work, not
  notifications.
* Broadway: `Pipeline.Discovery`, `Pipeline.Import`, `Pipeline.Image`.
* 13 Oban workers — confirm each is in the right row (most are cron).

**Known findings to carry in**

1. Review approval → Import is a PubSub message behind a stored
   `:approved`. Non-compliant. Discovery's automatic matches do the same
   work re-derivably, so the fix is one import path through an Oban job
   (see the 2026-09-29 proposal in `review-coherence.md`, Next steps 2):
   the Import Broadway pipeline is replaced; the job's last step needs a
   design for the `Pipeline` → `Library.Inbound` boundary (call ingest,
   or await the link outcome).
2. Review and title-detail deletes run in `start_async`; closing the page
   mid-delete stops a person's decision partway.

## Decisions made

* `2026-09-29` — ADR-076 accepted: durability follows the cost of losing
  the work. (commit `f21552c1`)

## Next steps

1. Reconcile the inventory against the code; add anything missed.
2. Classify every row (Method step 2) into a table in this file.
3. Design the single import path (known finding 1) and record it here.
4. Move sites, highest cost of loss first.

## Completion criteria

* Every pending state and every carrier site is classified in this file
  against ADR-076, with its disposition.
* No stored pending state lacks a stored job behind it.
* Every move carries a test that loses the carrier and asserts the work
  completes or is reported.
* A decision on whether a Credo check can hold part of the rule (a house
  rule that fits a static check becomes one, per `CLAUDE.md`), and the
  check if so.
* `docs/architecture.md` and `docs/pipeline.md` describe the carriers as
  shipped.

## Pointers

* ADR-076, ADR-049 (owned async), ADR-044 (no blocking I/O in handlers),
  ADR-039 (pursuits), ADR-040 (data migrations enqueue Oban jobs).
* `campaigns/review-coherence.md` — where the gap was found.
* `lib/media_centaur/pipeline/import.ex`, `import/producer.ex`,
  `library/inbound.ex`, `review.ex`.
