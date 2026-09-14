---
status: accepted
date: 2026-06-08
---
# External-dependency faults are subsystem health, not log incidents

## Context and Problem Statement

Diagnostics has two incident tracks: `:log`, minted one-to-one from any warning or error line with no threshold, no cross-layer grouping and no auto-resolution; and `:subsystem`, where a subsystem implements `IncidentContext.assess/0` and the `Evaluator` cron polls it, grouping by `{component, kind}`, opening on sustained failure and closing on `:ok`. Download-client connectivity failures sat on the `:log` track, so one momentary stall minted several durable incidents with different fingerprints from the driver and each caller, and a single retryable grab rejection read as a fault.

## Decision Outcome

1. **A fault in an external dependency we poll is a health condition of the subsystem that owns the dependency**, expressed through `assess/0` over the health fields that subsystem already tracks, never a `:log` incident. The `:log` track remains the safety net for unexpected, un-owned errors.
2. **Logs stay liberal; incident creation belongs to the assessor.** A connectivity warning may still be logged at any layer for the console, marked `mc_incident: :skip` in its logger metadata so `ErrorReports.LogHandler` mints nothing from it.
3. **Suppress a log only once an assessor kind covers its condition.** Suppression without coverage is a blind spot. A per-operation retryable failure the pursuit state machine already absorbs is not incident-worthy on its own, but its log keeps minting until an assessor kind exists for persistent failure of that operation.

### Consequences

* A connectivity fault surfaces after the evaluator's poll interval rather than on the first log line: latency traded for precision.
* Every external-dependency subsystem, including a new download driver, must own an `assess/0` and the skip marker on its connectivity logs; the `:log` safety net no longer covers it.
