---
status: planning
started: 2026-06-08
last_updated: 2026-06-08
---
# External-dependency health classification

## Goal

Move download-client connectivity faults off the noisy `:log` incident track
and onto the existing `:subsystem` assessor track, so one external-dependency
condition is one incident that auto-opens on sustained failure and auto-closes
on recovery — instead of a transient blip minting 2–3 duplicate, never-closing
board entries. Codifies [ADR-054](../decisions/architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md).

## Status

Phases 1 + 2 done in the working tree (unpushed); only the production-side
reconcile remains, and it needs the user + their prod node.

- **Phase 1 — assessor.** `MediaCentaur.Downloads.IncidentContext` reports
  `:ok` / `{:fault, :download_client_unreachable, :warning, _}` /
  `{:fault, :download_client_auth_failed, :error, _}` over `QueueMonitor`
  health, registered under `:acquisition`. Pure `decide/3` unit-tested (8 cases).
- **Phase 2 — suppression.** `mc_incident: :skip` `:logger` metadata marker
  added to the `MediaCentaur.Log` macros and honoured by `LogHandler` (new
  guard + test). Applied to the qBittorrent `sync_maindata` failure logs and the
  `QueueMonitor` poll-failed log — the connectivity duplicates the assessor
  covers. **Grab-rejection suppression deferred** (see Open decisions): no
  assessor `kind` covers grab acceptance yet, so suppressing it would blind us to
  persistent grab failure.
- **Phase 3 — docs (partial).** `troubleshoot` skill updated with the two-track
  classification. Wiki Troubleshooting page intentionally **not** updated yet —
  the behaviour isn't live until this ships; do it at ship time.

274 tests green across `downloads/` + `error_reports/`; format + Credo +
warnings-as-errors clean.

Triggered by live incidents `206e…`/`38485…` (one qBit timeout, double-logged
across `acquisition` + `library`) and `af3d…` (a retryable grab rejection
surfaced as a standalone incident) on prod `0.82.1`.

## Decisions made

* `2026-06-08` — External-dependency connectivity faults are subsystem health
  conditions expressed via `IncidentContext.assess/0`, not `:log` incidents.
  ([ADR-054](../decisions/architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md))
* `2026-06-08` — Owning component is **`:acquisition`** (matches the driver's
  log tag and the existing Status subsystem). Module lives under `Downloads`
  (with `QueueMonitor`) but registers as the acquisition assessor; it owns
  acquisition's external-dependency health and can grow more `kind`s (e.g.
  Prowlarr reachability) later.
* `2026-06-08` — Threshold is **elapsed-since-last-successful-poll ≥ 180s**
  (a `decide/3` parameter), read from `QueueState`. `:auth_failed` ignores the
  grace window; `{:offline, since}` measures from its own onset timestamp.

## Open decisions / deferred

* **Grab-acceptance assessor `kind`.** The assessor covers poll connectivity,
  not whether grabs are *accepted* by the client. Add a second `kind` (e.g.
  `:download_client_rejecting_grabs`) fed by a grab-outcome health signal, then
  suppress the Prowlarr grab-failed + `PursueTarget` grab-failed logs. Until
  then those stay on the `:log` track so persistent grab failure still surfaces.

## Next steps

1. **Ship.** `/ship patch` — Phases 1 + 2 are one shippable unit (Phase 1 alone
   would *add* a subsystem incident without removing the log duplicates, so they
   must land together). Mention the observability behaviour change in the
   CHANGELOG.
2. **Reconcile prod (user + prod node).** After the release lands, dismiss the
   stale `:log` incidents `206e…`, `38485…`, `af3d…` via
   `scripts/troubleshoot` / `mc-rpc`, and verify on the running app that a real
   qBit outage opens exactly one `{:acquisition, :download_client_unreachable}`
   incident and that it auto-resolves on recovery.
3. **Wiki.** Update the Troubleshooting page with the two-track classification
   at ship time (held until the behaviour is live).
4. **Follow-up.** Grab-acceptance assessor `kind` (see Deferred).

## Completion criteria

* A sustained qBittorrent outage produces **exactly one** open `:subsystem`
  incident, regardless of how many code paths log it, and it **auto-resolves**
  when polling recovers.
* A single transient poll timeout between two healthy polls produces **zero**
  incidents (still visible as a console log line).
* No connectivity `Log.warning` site mints a `:log` incident; the `:log` track
  is reserved for un-owned, unexpected errors.
* ADR-054 referenced from the relevant moduledocs (`LogHandler`, the new
  assessor); wiki Troubleshooting reflects the behaviour.

## Pointers

* [ADR-054](../decisions/architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md) — the decision.
* `lib/media_centaur/error_reports/incident_context.ex` — `assess/0` contract.
* `lib/media_centaur/error_reports/evaluator.ex` — reconcile + auto-resolve.
* `lib/media_centaur/error_reports/log_handler.ex` — `:log` capture (suppression target).
* `lib/media_centaur/downloads/queue_monitor.ex` — `QueueState` health fields.
* Related: [`update-subsystem-on-status.md`](update-subsystem-on-status.md) — adjacent subsystem-incident work.
