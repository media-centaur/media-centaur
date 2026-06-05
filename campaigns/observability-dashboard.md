---
status: in_progress
started: 2026-05-31
last_updated: 2026-06-02
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

**CAMPAIGN COMPLETE — 2026-06-02.** All four phases shipped. Phase 4 finished
with M1 (read surface), M2 (guided consent modal), M3 (health board + Activity
widgets), and M4 (user-origin generic reports + discovery badge). See the
per-milestone records below and the closure note at the end of this file for the
destination-bucketed deferrals.

Three throwaway exploration mockups exist under `mockups/observability/`
(direction 1 chosen; chip/console styling since rejected — do not reuse their
visuals).

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
* `2026-06-01` — **Phase 4 UI settled** in
  [`2026-06-01-phase4-health-board-ui.md`](../docs/superpowers/specs/2026-06-01-phase4-health-board-ui.md):
  health-first reframe; drop the Library catalog overview; Watcher Activity
  widget absorbs per-drive storage capacity (standalone Storage section
  removed); **reporting is incident-anchored** ("Report this" per incident,
  no floating global button; quiet `:user`-origin secondary path); drill-in is
  a **stacked** composition of Issues → Activity widget → collapsed Logs; logs
  available but never default; **per-subsystem Activity widgets** owned by their
  subsystem (UI mirror of the `IncidentContext` contributor registry, phased).
  Chosen mockups: board `1b-health-board-refined`, drill-in `5-drill-in-stacked`.

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
* A user can file a problem from the dashboard — either an identified incident
  (drill-in "Report this") or a generic "something's wrong" report from the
  status page carrying a current-state snapshot — review and remove parts of the
  payload, consent, and have it land as an issue in the private
  `media-centaur-reports` repo, with no GitHub account and no understanding of the
  internals. (Per-entity/per-media reporting was **de-scoped** in the M4
  brainstorm 2026-06-02 — reporting is always status-page, not about titles.) ✅
* An incident report carries cross-subsystem lead-up + vitals + the firing
  subsystem's contributed context, frozen at incident time, plus live-now state.
* Uncategorizable errors are captured, grouped without flooding, and reportable.
* `/status` reads as a media-app health surface — no Console aesthetic, no chip
  palette, color only signaling health.

## Resuming — Phase 4, start here (historical — campaign COMPLETE; see Closure)

Phases 1–3 (the whole backend) are done, committed, and green
(`a838a198 → 5d59c601`). Phase 4 (the user-facing surface) is **in progress**,
broken into milestones — visual direction settled in the 2026-06-01 brainstorm
([`2026-06-01-phase4-health-board-ui.md`](../docs/superpowers/specs/2026-06-01-phase4-health-board-ui.md)).

**Phase 4 — Milestone 1 (read-surface) — done 2026-06-01** (merged to main,
`ea3986b1 → b0bf34af`; plan
[`2026-06-01-health-board-milestone1.md`](../docs/superpowers/plans/2026-06-01-health-board-milestone1.md)).
`/status` now leads with the Subsystem Health Board: 7 tiles (name + neutral
glyph + type, color only for health) over a pure `StatusLive.HealthBoard`
view-model (`build_board/1`, `tile_state/1`, `group_buckets/1`, `tile_summary/1`,
`log_lines/1`), a `SubsystemView` struct, and `subsystem_tile`/`incident_row`/
`health_drill_in` components (each storied, MC0008/MC0009 clean). Tile click →
`push_patch ?subsystem=` → inline stacked drill-in (Issues with incident-anchored
"Report this" → existing modal · Activity slot · collapsed Logs). **Introduced
non-destructively** — existing operational sections untouched; reporting still
uses the old `window.open` modal. Full precommit green (4280 Elixir + 484 JS).

**Milestone 2 (reporting rebuild) — in progress.** Done: Send routes through
`submit_report/2` with `{:ok, url}` / `{:fallback, bundle}` result views
(`7d4f0615`); the modal's main view + copy corrected for the private inbox
(previews via `ReportPayload`, no public-issue language), and the **whole old
`window.open` path removed** — `IssueUrl.build/2` + URL-budget helpers,
`error_report.js` + its `app.js` import, the `phx-hook="ErrorReport"` attr
(`8b819993`; `IssueUrl` is now just `format_title`/`format_body/3`, reused by
`ReportPayload` — candidate to fold into `ReportPayload`).

**Milestone 2 — the guided 3-step consent flow — DONE 2026-06-01** (commits
`2d02b8d5 → f80851f5`; design [`2026-06-01-consent-flow-design.md`](../docs/superpowers/specs/2026-06-01-consent-flow-design.md),
plan [`2026-06-01-consent-flow.md`](../docs/superpowers/plans/2026-06-01-consent-flow.md)).
A brainstorm reframed step 2: because privacy leaks live *inside* free text
(a title/username in a message), removal is **editing the exact outgoing text**,
not per-section toggles — so the structured-payload / settings-summary idea was
**dropped**. Shipped: `ErrorReports.assemble_body/2` (optional narrative +
technical body) and `submit_payload/2` (submit an already-edited payload, same
copy-fallback); three storied step components (`ConsentComponents`); the
3-step `ReportModal` LiveComponent (1: optional narrative → 2: editable
title+body = exact outgoing text → 3: consent gate + Send); StatusLive anchors
the modal to a single incident (`bucket`, fingerprint from "Report this"); old
parent `report_confirm` gone. Full precommit green (4289 Elixir + 484 JS).
**Deferred to M4:** the standalone `:user`-origin "something else is wrong"
entry point (still no `Store` user-incident create path).

**M3 — health-board completion — DONE 2026-06-02.** Sliced:
- **M3a — section cleanup — DONE 2026-06-02** (`11c0cc97`): dropped the non-health
  sections from `/status` — `recent_changes_card`, `recently_watched_card`,
  `error_summary_card` (+ dead assigns/async), and the library catalog *counts*;
  **kept** pending-review as a slim health card and `error_buckets`/board/drill-in.
  Product calls: Recently Watched / Recent Changes **dropped** from `/status`
  (not relocated); catalog counts dropped, pending-review kept. Note: retiring
  `error_summary_card` removed the old board-level "Report errors" entry — the
  consent modal is now reached only via the drill-in's per-incident "Report
  this" (the intended incident-anchored model). Full precommit green.
- **M3b — Activity-widget registry + widgets (the architectural piece).**
  Design fork **resolved → approach A** (function-component registry + data
  bundle): config maps `component → {module, fun}`; the drill-in looks up the
  widget and renders it via `apply(mod, fun, [bundle])`, where the bundle is
  assembled from `StatusLive`'s already-loaded async assigns (no render-time
  queries). Mirrors the backend `Contributors`, boundary-clean. Plan:
  `docs/superpowers/plans/2026-06-02-activity-widgets-m3b1.md`.
  - **M3b-1 — registry + Watcher widget — DONE 2026-06-02** (`1b0e9d62`,
    `e10332bb`, `898ca7cf`): `MediaCentaurWeb.StatusLive.ActivityWidgets`
    (`registry/0`/`widget_for/2`/`render/3`, injectable); `watcher_widget/1`
    extracted from the old private `directories/1` into public `HealthComponents`
    (typed attrs + story + index); drill-in `:activity` slot filled conditionally
    (`:if={ActivityWidgets.widget_for(@selected_subsystem)}`) from `activity_bundle/1`;
    flat watch-dirs/storage `<.link><.directories/></.link>` section + dead defp/helper
    removed; `status_live_test.exs` at-risk test now drills into `?subsystem=watcher`.
    Widget invoked with a plain bundle map (no `__changed__`) → derives values with
    `Map.put/3`, not `assign/3`. Full precommit green (4297 + 484, 0 failures).
  - **M3b-2 — remaining widgets — DONE 2026-06-02** (`6e6d1363`, `5bebac75`):
    extracted a dedicated `MediaCentaurWeb.ActivityWidgetComponents` module (the
    clean board-shell-vs-widgets seam), relocated `watcher_widget` into it, then
    added `pipeline_widget` (folds `pipeline_card`), `tmdb_widget` (folds
    `external_integrations` rate-limiter), `playback_widget` (folds
    `playback_summary_card`) — each registered, storied, with the `assign`→`Map.put`
    gotcha handled. The flat `<.link section=services>` grid is gone; `/status`'s
    flat body is now just the health board + `pending_review_card`. Playback
    regression tests repointed to `?subsystem=playback` (coverage preserved).
    Full precommit green (4306 + 484, 0 failures); review APPROVED.

  **M3 (health-board completion) is now COMPLETE** — M3a (section cleanup) + M3b
  (Activity-widget registry + all four subsystem widgets). The flat `/status`
  scroll is retired in favour of the board + per-subsystem drill-ins. Subsystems
  without a registered widget (`:library`, `:acquisition`, `:system`) show the
  health-only floor — add widgets later if those grow diagnostics worth folding.

**M4 — user-origin reports + discovery badge — DONE 2026-06-02**
(`d18d1be → 23db7c2`; spec
[`2026-06-02-user-origin-reports-design.md`](../docs/superpowers/specs/2026-06-02-user-origin-reports-design.md),
plan [`2026-06-02-user-origin-reports.md`](../docs/superpowers/plans/2026-06-02-user-origin-reports.md)).
`Store.create_user_incident/1` (ungrouped `:user` write path — no migration, the
schema already had `origin: :user`/`user_description`/`scope`/`first_context`);
`count_unseen_incidents/1`; `ReportPayload.build_generic/2` +
`ErrorReports.create_user_report/2` (snapshot → persist `:user` incident →
submit). The M2 consent modal was **generalized** to accept a pre-built `payload`
(decoupled from `Bucket`); a board-header "Report a problem" opens it in generic
mode with a fresh `ContextSnapshot.assemble(:user, %{})`. Discovery badge:
`MediaCentaurWeb.DiagnosticsBadge` owns `diagnostics_seen_at` in `Settings`
(so `ErrorReports` gains **no** `Settings` dep), an `on_mount` hook assigns
`:diagnostics_unseen` app-wide + live-refreshes on `{:buckets_changed, _}`, the
`/status` nav shows an error dot (hidden at 0), and visiting `/status` advances
the timestamp. Per-entity/per-media reporting was de-scoped. Full precommit green
(4317 + 484); both review passes APPROVED.

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

## Closure (2026-06-02) — deferred items, bucketed by destination

The campaign's completion criteria are all met. No item ships or needs
verification now; the remaining work is enrichment, re-homed so nothing is an
undifferentiated "open follow-up":

- **Incident retention** — events prune at 30d, incidents are never pruned.
  *Defer →* a maintenance/retention pass (extend the existing `PruneJob`); not
  urgent until the incidents table grows.
- **`IncidentContext` contributors for pipeline + acquisition** — same registry
  pattern as the shipped `TMDB` contributor; richer drill-in/report context.
  *Defer →* whenever pipeline/acquisition debugging needs the extra vitals.
- **Throttled `latest_context` refresh** — currently only `first_context` is
  frozen; a live-now refresh was scoped out. *Defer →* same workstream as the
  contributors above.
- **Threaded pipeline correlation id** (spec D13) — improves id-correlation in
  the lead-up. *Defer →* a Broadway/pipeline-observability pass.
- **Metadata atom→string JSON round-trip** (Phase 1 note) — cosmetic key
  fidelity in stored context. *Defer →* fold into the next `Store` touch.

These are tracked here rather than as a new campaign; promote one to its own
campaign only if it grows past a single session.

## Pointers

* Design spec: [`docs/superpowers/specs/2026-05-31-observability-dashboard-design.md`](../docs/superpowers/specs/2026-05-31-observability-dashboard-design.md)
* Existing context: `lib/media_centaur/error_reports/`
* Existing page: `lib/media_centaur_web/live/status_live.ex`, `status_live/report_modal.ex`
* Subsystem taxonomy: `lib/media_centaur/console/view.ex`
* Convention: [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
