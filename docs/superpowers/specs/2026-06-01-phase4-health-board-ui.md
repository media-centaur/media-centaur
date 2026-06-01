# Phase 4 — Subsystem Health Board UI (design)

Surface design for **Phase 4** of the [observability dashboard
campaign](../../../campaigns/observability-dashboard.md). The backend
(Phases 1–3) is complete: durable incident store, subsystem fault lifecycle,
frozen context snapshots, and private-repo report submission all exist behind
`MediaCentaur.ErrorReports`. This doc settles the **user-facing surface** — the
rebuild of `/status` into the Subsystem Health Board and the reporting flow —
and supersedes the surface-level portions (D6/D7/D8) of the master design spec
[`2026-05-31-observability-dashboard-design.md`](2026-05-31-observability-dashboard-design.md)
where they differ. The backend contract in that spec is unchanged.

Audience north star (unchanged): **a media lover, not a programmer**. The page
must read as a media-app health surface, never an ops console.

## Decisions (this session, 2026-06-01)

| ID | Decision |
|----|----------|
| P4-1 | **Health-first reframe.** `/status` becomes the health board; each subsystem is a tile. Pure-activity content that isn't health relocates off this page. |
| P4-2 | **Drop the Library catalog overview** entirely — counts of movies/shows do not belong on a health page. |
| P4-3 | **Watch-directory block stays and absorbs the per-drive storage-capacity indicator** — directory health and drive headroom live together (the Watcher subsystem's Activity widget). The standalone Storage section is removed. |
| P4-4 | **Reporting is incident-anchored.** There is no floating top-of-page "Report a problem" button. The report action lives on each incident ("Report this") and auto-attaches *that* incident's frozen context. |
| P4-5 | **A quiet secondary path** — "something else seems wrong?" — is the only no-incident (`:user`-origin) report entry; small and muted, not a primary CTA. |
| P4-6 | **Drill-in is a composition of three pieces** in a single **stacked** scroll: Issues → Activity widget → Logs. |
| P4-7 | **Logs stay available but never default** — collapsed at the bottom of the drill-in; raw lines also travel in the report payload, not as the surface's primary content. |
| P4-8 | **Per-subsystem Activity widgets** are owned by their subsystem, phased in — the UI mirror of the backend `IncidentContext` contributor registry. Health-only is the floor; a rich widget is enrichment. |
| P4-9 | **Board aesthetic = mockup `1b`** — identity is name + neutral monochrome glyph + type; color reserved exclusively for health/severity; no per-subsystem chips, no console look. (Reaffirms master-spec D7.) |

Decisions carried unchanged from the master spec: D8 discovery badge,
D2/D3 submission + 3-step consent flow, D9–D13 incident model & context capture.

## The board

A grid of subsystem tiles (`watcher`, `import`/pipeline, `metadata`/tmdb,
`playback`, `library`-scanning, `downloads`/acquisition, `system`). Reuses the
`1b-health-board-refined` aesthetic verbatim: glass surfaces over the fixed
two-tone radial field, system font, monospace only for ids/paths/rates/counts.

- **Identity** = name + a neutral monochrome line glyph + a type label. No hue
  per subsystem.
- **Health expression** = a status dot + (only when unhealthy) a left-accent bar
  and semantic tint. Healthy tiles are deliberately quiet so the eye lands on
  the one or two that need attention.
- **Tiles carry a little of their own state** (a metric line or two), not just a
  dot — the lightweight face of the subsystem's Activity widget.

Clicking a tile opens its **drill-in** inline below the board (the board stays
visible — no modal that covers it). One drill-in open at a time; clicking
another tile replaces it.

## Per-subsystem Activity widgets (P4-8)

Each subsystem may contribute a bespoke widget. The pattern mirrors the backend
contributor registry (boundary-clean, runtime-registered, no compile-time
dependency from the board to each subsystem). Phased rollout — a subsystem with
no registered widget renders the health-only floor.

| Subsystem | Activity widget (initial) |
|-----------|---------------------------|
| Watcher | Watch directories + per-drive storage-capacity headroom (P4-3) |
| Import (pipeline) | Pipeline stages: Discovery → Import → Image, with throughput/queue counts |
| Metadata (TMDB) | Rate-limiter status (requests remaining / reset window) |
| Downloads (acquisition) | Active downloads / download-client status |
| Playback | Health-only floor for now (widget TBD by owner) |
| Library scanning | Health-only floor for now (pending-review count is a candidate) |
| System | Version, uptime, unclean-shutdown marker |

A widget is enrichment, not a requirement; ship the floor and let each
subsystem's owner add its widget on the same cadence as its `IncidentContext`
contributor.

## The drill-in (stacked, P4-6)

A single vertical scroll of three sections, in order:

1. **Issues** — the subsystem's detected incidents (grouped, ranked by severity
   then recency). Each row is plain language: *what's wrong · since when · what
   it affects · severity* (severity is the only color here). Each row carries
   its own **"Report this"** button → opens the consent modal pre-loaded with
   that incident's frozen `first_context` (P4-4). Acknowledge/resolve controls
   live here too.
2. **Activity** — the subsystem's widget (above).
3. **Logs** — a collapsible "view technical logs" section, **collapsed by
   default** (P4-7). Plain monospace lines scoped to this subsystem. Available
   for the curious; never the default content.

For a healthy subsystem the Issues section is empty/absent and the drill-in
leads with Activity.

## Reporting model (P4-4, P4-5)

- **Normal path:** every report originates from a specific incident's "Report
  this". The user never describes a problem from scratch; they confirm and send
  a problem the app already detected and contextualized.
- **Secondary path:** a quiet, muted "Something else seems wrong? Report a
  problem" link (placement: below the board or in the drill-in footer) creates a
  `:user`-origin incident with the current cross-subsystem context attached.
  This requires the `:user`-origin create path that `Store` does not yet have
  (master-spec Phase 4 work item — origin `:user`, `scope`, `user_description`).
- **The action** opens the existing **guided 3-step consent modal** (what
  happens + four promises → review & remove with manual redaction → consent gate
  + Send). Send → `ErrorReports.submit_report/2`; copy-fallback rendered on
  no-token/offline.

## Discovery badge (D8, unchanged)

A passive badge on the Status nav item counts **unacknowledged open incidents**.
Open detail to finalize in implementation: persist `diagnostics_seen_at` in
`Settings`; the badge counts open incidents newer than it; visiting `/status`
advances it.

## What moves or is removed

- **Removed:** the Library catalog overview (P4-2); the standalone Storage
  section (folded into Watcher, P4-3); the old `window.open` submission path
  (`assets/js/hooks/error_report.js`, the `error_reports:open_issue`
  `push_event`, and `IssueUrl`'s URL builder — **keep**
  `IssueUrl.format_title/format_body`, reused by `ReportPayload`).
- **Relocated:** "Recently Watched" and "Recent Changes" are library activity,
  not health — they move to Home/Library (or drop if already represented there).
  Final placement is an implementation decision, not a blocker for the board.

## Components & Storybook

New function components (each gets a Storybook story per MC0009, typed attrs per
MC0008): subsystem **tile**, the **drill-in shell**, the **incident row**
(with Report this), each **Activity widget**, the **logs section**, and the
**consent-modal steps**. Reuse `<.button>`, `<.badge>`, glass surfaces, and the
always-in-DOM modal shell. No console aesthetic, no chip palette.

## Testing

Per `automated-testing`: extract non-trivial render logic into pure functions
(`tile_health/1`, `incident_summary/1`, widget formatters) and unit-test them;
add `/status` to the page smoke test with fixture data exercising healthy +
unhealthy tiles and an open drill-in; `submit_report` tests inject
`opts[:transport]`. Test-env gotchas (from the campaign): the durable
`LogHandler`/`ShutdownMonitor` are not started under `:test` and the global
`Buckets` is inert — exercise capture via named `Buckets`/`Capture`/`Store`.
No network in tests.

## Mockups

- Board aesthetic (approved): `mockups/observability/1b-health-board-refined/`
- Drill-in arrangement (chosen): `mockups/observability/5-drill-in-stacked/`
- Drill-in alternative (tabbed, not chosen): `mockups/observability/4-drill-in-tabbed/`
- Rejected: `1-subsystem-health-board` (chip palette), `2-incident-triage-feed`,
  `3-operations-cockpit` — do not reuse their visuals.

## Open questions (resolve in the plan, not blockers)

- Exact `diagnostics_seen_at` acknowledgement semantics for the badge.
- Final home for Recently Watched / Recent Changes.
- Whether Playback / Library-scanning ship a widget in Phase 4 or stay health-only.
