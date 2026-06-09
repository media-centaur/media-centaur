# Downloads Status Enrichment — Design

**Date:** 2026-06-09
**Status:** Approved (design), pending implementation plan

## Problem

The Downloads (acquisition) subsystem tile on `/status?subsystem=acquisition` has **no Activity widget at all** — `acquisition` is absent from the `:health_activity_widgets` registry, so the drill-in renders only the health floor (description + incidents). Every other subsystem now tells a story; Downloads is blank below the fold.

## Persona & guardrail

Designed for the enthusiast/homelab-operator persona (auto-memory `project-status-page-persona`): narrative-at-rest + plumbing health + aggregate stats. **Critical guardrail (auto-memory `feedback-status-widgets-no-rehash`):** the tile must NOT re-list what the `/download` page (`AcquisitionLive`) already shows. Downloads already has a full feature page with the live queue and pursuit rows — so the status tile surfaces what has *no other home*: consolidated connectivity health and lifetime aggregates, plus at most a count that *links* to `/download`.

Shawn explicitly chose **Connectivity health + Throughput**, and rejected active-downloads / pursuit-in-flight lists as rehashes.

## Design — two bands

### Band 1 — Connectivity *(the lead; the only band that carries health color)*

A consolidated, labeled status of the acquisition pipeline's live reachability — the "can it acquire right now?" view that exists nowhere else:

- **Download client** — grade from `Downloads.QueueStatus.derive(queue_state, cadence_ms, now)`:
  - `:fresh` → "Connected" (success), with freshness suffix from `last_successful_poll_at` (e.g. "polled 20s ago")
  - `{:lagging, _}` → "Lagging" (warning)
  - `{:offline, since}` → "Offline" (error)
  - `:auth_failed` → "Auth failed" (error)
- **Prowlarr (indexers)** — `Capabilities.prowlarr_ready?/0` → "Reachable" (success) / "Unreachable" (error).

Each is a row: service label · status dot · state text. Color is reserved to this band (health = signal).

**Unconfigured state:** when neither the download client nor Prowlarr is configured (`!download_client_ready? and !prowlarr_ready?` with no queue history), render a single "Acquisition isn't set up — configure in Settings" link (mirrors the TMDB widget's unconfigured affordance) and omit Band 2.

### Band 2 — Throughput *(the flex; aggregate numbers with no other home)*

Three stat figures, identical visual treatment to the playback lifetime band (`text-2xl font-semibold tabular-nums` value over `text-xs uppercase tracking-wider` label):

- **Acquired** — lifetime count of pursuits in the `:terminal_success` bucket.
- **Success rate** — `success / (success + failure)` as a whole-percent; renders "—" when the denominator is 0.
- **Active** — `:in_flight` count, wrapped in a `<.link navigate={~p"/download"}>` (the glanceable summary that points to the live list — a count+link, not a rehashed list).

## Data flow

A new pure aggregate shapes throughput; connectivity is assembled by `StatusLive` from already-cheap reads and handed to the widget as a bundle (widgets never query at render time — the ActivityWidgets contract).

- **Throughput aggregate** — new `MediaCentaur.Acquisition.Pursuits.Throughput`:
  - `stats/0` → `%{acquired: non_neg_integer, failed: non_neg_integer, active: non_neg_integer, success_rate: integer | nil}`.
  - Implementation: one `from p in "acquisition_pursuits", group_by: p.state, select: {p.state, count()}` Repo query, fold each state through `Pursuits.State.bucket/1` into the three buckets. `success_rate` = `round(100 * acquired / (acquired + failed))` or `nil` when `acquired + failed == 0`. Cheap; result size bounded by the number of distinct states (4).
  - `empty/0` → `%{acquired: 0, failed: 0, active: 0, success_rate: nil}` for the disconnected mount.
  - Exported from the AcquisitionPursuits boundary.
- **Connectivity bundle** — `StatusLive` assembles `acquisition_activity`:
  - `client_grade` = `QueueStatus.derive(QueueMonitor.state(), cadence_ms, now)` (reuse the cadence constant `AcquisitionLive` uses for consistency).
  - `last_poll_at` = `QueueMonitor.state().last_successful_poll_at`.
  - `prowlarr_ready?`, `download_client_ready?` = `Capabilities.*`.
  - `throughput` = `Throughput.stats/0`.
- **Refresh triggers** — `StatusLive` subscribes to the capabilities/queue/pursuit topics and re-assembles the bundle on their messages (exact topic atoms confirmed during planning — candidates: `Capabilities` flag-change broadcasts, `QueueMonitor` updates, `Pursuits.Events`). Lifetime throughput and connectivity refresh on those events and on mount — no render-time queries.

## Components & files (anticipated)

- New: `lib/media_centaur/acquisition/pursuits/throughput.ex` (+ test) — the aggregate.
- New: `acquisition_widget/1` in `lib/media_centaur_web/components/activity_widget_components.ex` — two bands; reuses the playback stat-figure + status-dot idioms.
- New: `storybook/status/acquisition_widget.story.exs` — variations: healthy, client-offline, prowlarr-unreachable, unconfigured (MC0009).
- Modify: `config/config.exs` — register `acquisition: {MediaCentaurWeb.ActivityWidgetComponents, :acquisition_widget}`.
- Modify: `lib/media_centaur_web/live/status_live.ex` — subscribe, assemble `acquisition_activity`, handle_info refresh, add to `activity_bundle/1`.
- Modify: `test/media_centaur_web/live/status_live_test.exs` — wiring assertions.

## What this is NOT

- No active-downloads list and no pursuit-in-flight rows — those live on `/download` (the no-rehash guardrail). "Active" is a single count that links there.
- No new download-throughput byte tracking (declined — not worth a new data source).
- Connectivity is read from existing caches/derivations; no new health-probing machinery.

## Testing

- `Throughput.stats/0` — unit-tested (DataCase): bucket mapping, success-rate rounding, division-by-zero → `nil`. Fixtures use generic placeholders / PD-CC titles.
- Widget is a pure function over the bundle — storybook variations are the render acceptance (MC0009): healthy / client-offline / prowlarr-unreachable / unconfigured.
- StatusLive wiring (assign on mount, refresh on event, `?subsystem=acquisition` renders the widget) — `status_live_test.exs`, using the `live_async!/2` helper like the playback tests.

## Open items for planning

- Confirm the exact PubSub topics StatusLive must subscribe to for live connectivity/throughput refresh (Capabilities / QueueMonitor / Pursuits.Events).
- Confirm the cadence constant for `QueueStatus.derive` (reuse `AcquisitionLive`'s rather than inventing one).
- Confirm `Pursuits.State.bucket/1`'s exact signature (string vs atom input) for the aggregate fold.
