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
