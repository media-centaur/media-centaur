---
status: accepted
date: 2026-06-08
---
# External-dependency faults are subsystem health, not log incidents

## Context and Problem Statement

The observability backbone has two incident tracks (see the `ErrorReports`,
`IncidentContext`, and `Evaluator` moduledocs):

- **`:log`** — minted 1:1 from any `:warning`/`:error` log line by
  `ErrorReports.LogHandler`, fingerprinted by `(component, normalized_message)`.
  No grouping across call layers, no occurrence threshold, no auto-resolution.
- **`:subsystem`** — a subsystem implements `IncidentContext.assess/0`; the
  `Evaluator` (Oban cron) polls it and reconciles. Grouped by
  `{component, kind}`, so one condition is one incident; `:ok` auto-resolves the
  open incident; the poll is duration/trend-driven, so a single transient blip
  never fires.

Download-client connectivity failures currently land on the **`:log`** track,
and it produces three pathologies, all observed live on `2026-06-08` against a
single momentary qBittorrent stall:

1. **No threshold.** One `%Req.TransportError{reason: :timeout}` from a single
   poll mints a durable, board-visible incident, even though the next poll a
   minute later succeeds. A blip reads as a fault.
2. **Cross-layer duplication.** The qBittorrent driver logs the timeout *and*
   returns `{:error, reason}`; its caller (`QueueMonitor`, `PursueTarget`) logs
   the same reason again with its own component tag and phrasing. One physical
   fault → 2–3 incidents with different fingerprints (e.g. `206e…`/`acquisition`
   ≡ `38485…`/`library`). Fingerprint dedup can't merge them — the messages
   genuinely differ.
3. **Mis-classification of retryable outcomes.** A Prowlarr grab rejection
   (`af3d…`) is a normal retryable operational event the pursuit state machine
   already absorbs (snooze + retry). As a standalone `:log` incident it is pure
   noise; it only warrants attention when *persistent*.

The instinctive fix — "drivers return errors, callers log" — reaches into the
*logging* layer to suppress duplicate *incidents*. That couples two concerns
that should be independent (where you log vs. what becomes an incident) and is
fragile: one new caller that forgets the contract reintroduces the duplicate.

The deeper observation: the `:subsystem` track already has every property the
`:log` track lacks (grouping, threshold, auto-resolution). The reduction stage
we'd otherwise build *already exists* — these faults are simply on the wrong
track. And the health signal is already instrumented: `QueueMonitor`'s
`QueueState` carries `last_polled_at`, `last_successful_poll_at`, and
`last_error`.

## Decision Outcome

Chosen option: **classify external-dependency connectivity faults as subsystem
health conditions**, because the existing assessor/Evaluator track already
provides correct grouping, thresholding, and lifecycle — reclassification, not
new machinery.

Concretely:

- A download-client `IncidentContext` implements `assess/0` over
  `QueueMonitor`'s existing health fields, reporting `:ok` when the last poll
  succeeded and `{:fault, :download_client_unreachable, :warning, ids}` when
  polls have been failing past a small duration/streak threshold (a single
  failed poll between successes is not a fault).
- The raw connectivity `Log.warning` lines **stay as logs** for the volatile
  console, but must **not also mint `:log` incidents** once the subsystem
  assessor owns the condition. Logs remain liberal and may appear at multiple
  layers; incident creation is the assessor's job alone. The suppression is an
  explicit `mc_incident: :skip` `:logger` metadata marker read by `LogHandler`.
- A log may only be suppressed once an assessor `kind` actually covers its
  condition — suppression without coverage is a blind spot, not a cleanup. The
  initial assessor covers **poll connectivity** (qBittorrent `sync_maindata` /
  `QueueMonitor` poll), so those logs are suppressed now. Per-operation retryable
  failures (a single Prowlarr **grab rejection**) are also *not* incident-worthy
  on their own — the pursuit state machine already absorbs them with snooze +
  retry — but their suppression is **deferred** until the assessor gains a
  grab-acceptance `kind`, so persistent grab failure still surfaces somewhere.

This is the general rule, not a qBittorrent special-case: **a fault in an
external dependency we poll is a health condition of the subsystem that owns the
dependency, expressed through `assess/0` — not a log incident.** The `:log`
track remains the safety net for genuinely unexpected, un-owned errors.

### Consequences

* Good, because one external-dependency condition is exactly one incident that
  opens on sustained failure and **auto-closes on recovery** — no stale open
  incidents, no cross-layer duplicates.
* Good, because logging and incident creation are decoupled: code may log at any
  layer for debugging without taxing the incident board, retiring the
  "drivers return, callers log" workaround as a required fix.
* Good, because it reuses the boundary-clean assessor seam (config-driven
  registry, no compile-time dependency on `ErrorReports`) rather than adding a
  parallel mechanism.
* Bad, because connectivity faults now surface only after a short detection
  delay (the evaluator poll interval) instead of on the first log line — an
  intentional trade of latency for precision.
* Bad, because each external-dependency subsystem must now own an `assess/0`
  and a suppression marker for its connectivity logs; the `:log` safety net no
  longer auto-covers them. New download drivers inherit this obligation.
