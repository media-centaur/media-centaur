---
status: accepted
date: 2026-09-29
---
# Durability follows the cost of losing the work

## Context and Problem Statement

Background work travels by PubSub, Broadway, Oban or `start_async`, chosen per context with no shared rule. ADR-049 covers only the web layer: work that must outlive a view goes to "Oban or a named service". It does not say when work must be durable.

The gap showed in Review (campaign `review-coherence`): an approval — a person's decision, stored as `:approved` and shown as "Importing" — was carried to Import by a PubSub message. A process crash lost the import, and the item claimed pending work that nothing would do until the next restart.

## Decision Outcome

The mechanism is chosen by what losing the work costs:

| The work | Losing it costs | Mechanism |
|---|---|---|
| Carries out a person's decision, or a row records it as pending | A state that claims work nothing will do | Oban job, inserted in the transaction that records the state |
| Is re-derived by a named recovery pass | Delay until that pass runs | PubSub, or Broadway for volume and backpressure |
| Notifies that something changed | A stale view until the next event | PubSub |
| Recurs on a schedule | Nothing | Oban cron |
| Belongs to one page view | Nothing once the view is gone | `start_async` (ADR-049) |

**Invariant:** no stored "in progress" state without a stored job behind it. The test: does a row say this work is pending? If so, the work lives in a job.

When a durable and a re-derivable caller do the same work, the work has one path, through the job.

### Consequences

* Good, because a pending state always has work behind it, and a crash or restart delays that work instead of losing it.
* Good, because retries and failure reporting come from Oban rather than per-context recovery code.
* Bad, because existing sites must be audited and moved: Review approvals (and with them every import, which shares the path), and the Review and title-detail deletes, which run in `start_async` and stop partway when the page closes.

## Amendments

* **2026-09-30** — The invariant is met by a stored row a scheduled pass carries out, not only by a job. A Review approval is the case: `PendingFile :approved` stores the decision, and `Review.settle_with_library/1` — at startup and every five minutes (`Review.SettleJob`) — re-sends an approval whose import was lost. A job was the first-row answer, but `Pipeline` depends on `Review`, so an approval could not insert a Pipeline job without a cycle (campaign `durable-work`, F1). What the invariant asks is that stored pending work always has something stored that will carry it out; a row plus a pass on a schedule does that, with a delay bounded by the schedule.

