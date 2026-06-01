---
status: in_progress
started: 2026-05-31
last_updated: 2026-06-01
---
# Observability dashboard

## Goal

Give end users — **media lovers, not programmers** — a way to *notice* when
something in Media Centaur is broken, *see* which subsystem is failing, and hand
the developer an **incident report** carrying enough cross-subsystem context to
diagnose it, without the developer ever touching their machine. The author now
has real users who hit bugs he can't reproduce because he has no access to their
data; this closes that loop with durable capture + a consented, comprehensible
report flow.

Full design: [`docs/superpowers/specs/2026-05-31-observability-dashboard-design.md`](../docs/superpowers/specs/2026-05-31-observability-dashboard-design.md).

## The model

Settled across the 2026-05-31 design session. Resumable context — read the spec
before writing code. This is an **evolution of the existing `ErrorReports`
context**, not a greenfield: fingerprint grouping, `Redactor`, `EnvMetadata`,
and a report modal already exist but are volatile (1h, in-memory), errors-only,
and submit via a public-repo `window.open` URL.

**Incidents have three origins**, all flowing into one durable store + one
packaging/report pipeline:
- `:log` — fingerprinted warning/error capture (exists; made durable).
- `:subsystem` — a subsystem *detects* it's malfunctioning and raises an
  incident (active self-monitoring), even with no logged error.
- `:user` — a human reports a problem that produced no log error.

**Incidents are stateful** (`open → resolved`, + `acknowledged`), not just error
tallies — subsystem-asserted faults open when tripped and resolve when cleared.

**Context capture is hybrid**: freeze a lean snapshot at incident time on
**first + latest** occurrence (cross-subsystem lead-up logs from the volatile
Console buffer, all redacted; async-gathered all-subsystem vitals; crash
reason; triggering ids; per-subsystem contributor block), and enrich with live
"now" state at report time — labeled distinctly. Lead-up is sharpened by
**time-window + id correlation** (threaded pipeline correlation id deferred).

**Per-subsystem ownership**: each subsystem owns an `IncidentContext` module
(detect + contribute), wired via a **runtime registry** so `Diagnostics` calls
it without a compile-time dependency (boundary-clean IoC). Baseline packaging is
the floor; contributors are enrichment, phased in (pipeline, tmdb, acquisition
first).

**Uncategorizable errors** are never dropped: classify → fall back to `Internal`
tagged *uncategorized*; group → **layered fallback** (message fp → coarse fp by
exception type/top frame → single `Uncategorized` aggregate per component);
enrich → baseline floor. Out-of-band BEAM death is caught via an
unclean-shutdown marker that raises a `:subsystem` incident on next boot.

**Reporting is an informed-consent, plain-language, guided 3-step flow**: (1)
what happens + four promises, (2) review & remove (auto-redaction + manual
per-section/per-line removal), (3) explicit consent + send. Submission posts to
a **private `media-centaur-reports` repo via a fine-grained issues:write token**
(no user GitHub account, no infra); offline/no-token falls back to copy-the-
bundle.

**Surface**: rebuild `/status` into a **Subsystem Health Board** — but with
**no Console aesthetic and no chip palette**. Subsystems identified by name +
neutral icon + type; color reserved exclusively for health/severity; reads as a
media app, not an ops console.

## Status

**Phase 1 (durable incident store) — complete.** Shipped behind the existing
`ErrorReports` context (kept the name): `diagnostic_events` + `incidents`
tables, synchronous pure-`Repo` `Store`, `Capture.persist_entry/1` (redacts +
persists warning/error + opens/bumps the `:log` incident), `Buckets` reworked
into a store-backed cache (rebuilds from the store on boot, no time window,
surfaces warning + error) over a pure `BucketCache`, a daily `PruneJob` (Oban
cron, `maintenance` queue), and `Store.health/0` / `ErrorReports.health/0`
rollup. Full `mix precommit` green (4200 Elixir + 484 JS). The prod migration
is **not yet applied locally** — it ships with the release (additive, no
backfill).

**Phase 1 hardening (post-review, same day).** Two fumbles caught and fixed:
(1) durable capture was downstream of the volatile Console buffer — now an
**independent `:logger` handler** (`ErrorReports.LogHandler`), a peer of
`Console.Handler`, so a crashed/backed-up buffer can't starve the store
(entry-building shared via `Console.Entry.from_log_event/3`; durable handler not
installed under `:test`); (2) every warning/error was an unthrottled per-line DB
write — now a **per-fingerprint debounce** (`PersistThrottle`): first occurrence
persists, bursts coalesce into one write/window, count stays accurate (flushed
periodically + on `terminate/2`). Documented the single-serial-writer invariant
on `Store.upsert_log_incident`. **Deferred:** incident retention (events prune at
30d, incidents don't) and the metadata atom→string JSON round-trip — both noted
for a later pass.

Phases 2–4 remain. Design settled and specced. Visual mockups deliberately
parked until Phase 4. Three throwaway exploration mockups exist under
`mockups/observability/` (direction 1 chosen; chip/console styling since
rejected — do not reuse their visuals).

## Decisions made

* `2026-05-31` — Primary audience is the end-user reporter, a media lover not a
  programmer; the whole surface must read as a media app, not a dev console.
  ([spec](../docs/superpowers/specs/2026-05-31-observability-dashboard-design.md) D1)
* `2026-05-31` — Submission: private repo + embedded fine-grained issues:write
  token over the GitHub REST API; no user account, no infra. (spec D2)
* `2026-05-31` — Reporting is a guided 3-step informed-consent flow with manual
  redaction + access statement + explicit consent gate. (spec D3)
* `2026-05-31` — Durable error/incident store; volatile `Buckets` becomes a
  cache rebuilt from it. (spec D4, D5)
* `2026-05-31` — Rebuild `/status` into the Subsystem Health Board; no second
  page. (spec D6)
* `2026-05-31` — Do NOT reproduce the Console look or the per-subsystem chip
  palette; identity = name+icon+type, color = health/severity only. (spec D7,
  [[feedback-no-console-look-or-chip-palette]])
* `2026-05-31` — Passive discovery badge on the Status nav item. (spec D8)
* `2026-05-31` — Three incident origins (`:log`/`:subsystem`/`:user`); stateful
  `open→resolved` lifecycle. (spec D9, D10)
* `2026-05-31` — Hybrid context capture (freeze first+latest, enrich live now).
  (spec D11)
* `2026-05-31` — Per-subsystem `IncidentContext` contributors via a runtime
  registry; subsystems own detect + contribute; phased rollout. (spec D12)
* `2026-05-31` — Lead-up isolation = time-window + id correlation; threaded
  correlation id deferred. (spec D13)
* `2026-05-31` — Uncategorizable errors: never dropped; layered grouping
  fallback; unclean-shutdown → `:subsystem` incident on next boot.
* `2026-05-31` — Context naming **resolved**: keep the existing
  `MediaCentaur.ErrorReports` context (no rename to `ErrorReporting`/
  `Diagnostics`/`Observability`). Revisit only if the moduledoc ends up naming
  two responsibilities with "and" ([[feedback-architectural-modularity]]).

## Next steps

1. ~~**Phase 1 — Durable incident store.**~~ ✅ **Done 2026-05-31.**
   `diagnostic_events` + `incidents` tables + migration; `:log` capture of
   warning+error; durable fingerprint grouping; `Buckets` rebuilt from store on
   boot (pure `BucketCache` extracted); daily `PruneJob` retention; `health/0`
   rollup. Context kept as `ErrorReports`.
2. ~~**Phase 2 — Detection + contributors.**~~ ✅ **Done 2026-05-31.**
   `IncidentContext` behaviour + config-driven runtime registry (`Contributors`,
   boundary-clean IoC); subsystem fault lifecycle (`raise_fault`/`resolve_fault`,
   grouped by `{component, kind}`); periodic evaluator (`Evaluator` + Oban-cron
   `EvaluatorJob`, pure `plan/2`); frozen context snapshot (`ContextSnapshot` —
   redacted lead-up + id-correlation + cross-subsystem vitals + contributor +
   crash reason, frozen on first open); unclean-shutdown marker
   (`ShutdownMarker`/`ShutdownMonitor` → `{:system, :unclean_shutdown}`). First
   contributor (TMDB vitals) wired end-to-end. **Deferred:** pipeline +
   acquisition contributors (same pattern, phased rollout); throttled
   `latest_context` refresh; threaded pipeline correlation id (spec D13).
3. **Phase 3 — Submission swap.** Backbone ✅ **done 2026-05-31:**
   `ReportTransport` behaviour + `GithubTransport` (private-repo GitHub REST,
   fine-grained Bearer token); `ReportPayload` (reuses `IssueUrl` markdown, no
   URL size ladder); `ErrorReports.submit_report/2` with copy-fallback on
   no-token/network/non-201; token+repo via app config (release wires the token
   from an env var). Fully `Req.Test`-stubbed. **Deferred to Phase 4:** the
   StatusLive rewire to call `submit_report` + removal of the `window.open`
   `error_report.js` hook — Phase 4 rebuilds that modal as the guided consent
   flow, so the UI swap lands there.
4. **Phase 4 — Dashboard + consent reporting.** Rebuild `/status` as the
   Subsystem Health Board (no chips/console); warnings in health; drill-in
   (issues + diagnostics); discovery badge; the guided 3-step consent modal with
   manual redaction; wire `submit_report` + remove the `window.open` hook (from
   Phase 3); the `:user`-origin entry points (global + per-entity). Mockups
   happen here.

Each phase is test-first, no network in tests, and ships with the wiki/privacy
documentation for its user-visible surface.

## Completion criteria

* A `warning`/`error` survives a restart and is visible on `/status` more than
  an hour later.
* A subsystem can assert a fault that opens and later auto-resolves without a
  logged error.
* A user can file a problem from the dashboard (and a per-entity surface),
  review and remove parts of the payload, consent, and have it land as an issue
  in the private `media-centaur-reports` repo — with no GitHub account and no
  understanding of the internals.
* An incident report carries cross-subsystem lead-up + vitals + the firing
  subsystem's contributed context, frozen at incident time, plus live-now state.
* Uncategorizable errors are captured, grouped without flooding, and reportable.
* `/status` reads as a media-app health surface — no Console aesthetic, no chip
  palette, color only signaling health.

## Resuming — Phase 4, start here

Phases 1–3 (the whole backend) are done, committed, and green
(`a838a198 → 5d59c601`). Phase 4 is the only remaining phase: the user-facing
surface. **First reconcile this file against `git log` + code (ADR-042), then
brainstorm visual direction / mockups — do not auto-build the UI.** Load
`user-interface`, `phoenix-thinking`, `storybook`, `visual-designer` first.

**The backend Phase 4 builds on (`MediaCentaur.ErrorReports` public API):**
- `list_buckets/0`, `get_bucket/1`, and the `{:buckets_changed, buckets}`
  broadcast on `Topics.error_reports()` — `StatusLive` already consumes these.
- `health/0` → `%{status, open_count, by_severity}` (the board header + badge).
- `submit_report/2` → `{:ok, url} | {:fallback, bundle}` — wire the modal Send to
  this; render the fallback bundle as copyable text.
- Incidents (`Store`): `list_incidents(status:/limit:)`,
  `get_incident_by_fingerprint/1`, `set_status/2` (acknowledge/resolve),
  `raise_fault/4`/`resolve_fault/3`. An incident's `first_context` (JSON) is the
  frozen drill-in snapshot.

**Phase 4 work:**
1. Rebuild `/status` → **Subsystem Health Board**. Constraints, non-negotiable:
   name + neutral monochrome icon + type; **color only for health/severity**;
   **no Console look, no chip palette** ([[feedback-no-console-look-or-chip-palette]]).
   Warnings now appear in health.
2. Drill-in: ranked grouped issues + that subsystem's diagnostics (render
   `first_context`). Clean sans-serif rows; monospace only for ids/paths.
3. **Discovery badge** on the Status nav = unacknowledged open incidents. Open
   question to finalize here: persist `diagnostics_seen_at` in `Settings`; badge
   counts open incidents newer than it; visiting `/status` advances it.
4. **Guided 3-step consent modal** (what-happens + 4 promises → review & remove,
   manual per-section/per-line redaction → consent gate + Send). Plain-language
   rendering + "view technical details" expander. Send → `submit_report`.
5. **Remove the old submission path:** `assets/js/hooks/error_report.js`
   (`window.open`), the `push_event "error_reports:open_issue"` in `StatusLive`,
   and `IssueUrl`'s URL builder — **keep `IssueUrl.format_title/format_body`**
   (reused by `ReportPayload`).
6. **`:user`-origin entry points** (global + per-entity). NOTE: `Store` has no
   `:user`-incident create path yet (only `:log`/`:subsystem`) — Phase 4 adds
   one (origin `:user`, `scope`, `user_description`, attach current context).
7. Mockups first; a Storybook story per new component (MC0009).

**Test-env gotchas (so Phase 4 tests don't trip):** the durable `LogHandler` and
`ShutdownMonitor` are **not started under `:test`**, and the global `Buckets` is
**inert in test** (fed by neither the handler nor PubSub) — exercise capture via
named `Buckets`/`Capture`/`Store` directly. `submit_report` tests inject
`opts[:transport]`; `GithubTransport` tests inject a `Req.Test` client. No
network in tests.

**Phase-2/3 deferrals (pick up if desired, not required for Phase 4):** pipeline
+ acquisition `IncidentContext` contributors (same pattern as `TMDB`); throttled
`latest_context` refresh; threaded pipeline correlation id (spec D13).

**Architecture reports** (orientation; outside the repo, in `~/.agent/diagrams/`):
`observability-phase1.html` (durable store), `observability-after-phase1.html`
(hardening + Phase 2), `observability-phase3.html` (submission, structure &
coupling).

## Pointers

* Design spec: [`docs/superpowers/specs/2026-05-31-observability-dashboard-design.md`](../docs/superpowers/specs/2026-05-31-observability-dashboard-design.md)
* Existing context: `lib/media_centaur/error_reports/`
* Existing page: `lib/media_centaur_web/live/status_live.ex`, `status_live/report_modal.ex`
* Subsystem taxonomy: `lib/media_centaur/console/view.ex`
* Convention: [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
