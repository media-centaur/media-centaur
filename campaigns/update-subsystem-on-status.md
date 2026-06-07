---
status: in-progress
started: 2026-06-07
last_updated: 2026-06-07
---
# Update subsystem on the Status page

## Goal

Surface the self-update subsystem on the Status page's health board as a
first-class subsystem — a **Updates** tile that reports health like every
other subsystem (faults turn it warning/error) and a drill-in **Activity
widget** that shows the live update state (current version, last/next check,
classification, auto-install state, apply progress). Today the only window
into updating is the Settings card; the Status page is where a media-center
user looks to answer "is anything wrong?", and a silently-wedged updater (or
a failed auto-install) is exactly the kind of thing that page exists to catch.

## Status

**Phases 1 & 2 complete** — the **Updates** tile reports the three fault kinds,
and drilling in shows a live Activity widget (version, last/next check,
classification, auto-install, apply progress) wired to the two self-update
PubSub topics. Only Phase 3 (polish: `vitals/0`, edge cases, wiki) remains.

## Decisions made

Append-only log.

* `2026-06-07` — Scope is **observe + health faults**, not controls or history.
  Check-now / Update-now / auto-install toggles stay in Settings; a recent-checks
  history timeline is explicitly out of scope (deferred).
* `2026-06-07` — Three fault kinds, derived by `assess/0`:
  `:apply_failed` (**error**, dominant), `:check_failing` (**warning**, ≥3
  consecutive check failures), `:checks_stalled` (**warning**, background checks
  enabled but no successful check in ≥3× the configured interval). "Update
  available" is **never** a fault — informational only. "Auto-install disabled"
  is **not** a fault (rejected as too noisy). `assess/0` returns the single
  dominant fault (priority `:apply_failed` > `:check_failing` > `:checks_stalled`).
* `2026-06-07` — Fault reporting uses the **pull model**: a small durable
  "update health" projection feeds a pure `assess/0`, polled by the existing
  diagnostics evaluator (which raises/resolves the incident). Chosen over a
  push-based observer GenServer (in-memory streak lost on restart, extra process,
  duplicates the evaluator) and over a transient-only `assess/0` (misses the
  transient `:failed` phase, can't count a failure streak). Rationale: matches the
  board's pull contract, durable across restarts, pure/testable per ADR-030, and
  the same projection feeds the Activity widget.
* `2026-06-07` — New durable state lives under the existing `update.*`
  `Settings.Entry` namespace (additive keys only — no rename/drop, so the
  updater's hydration contract and the `/ship` schema-compat check stay green).
* `2026-06-07` — Subsystem identity is a **new** board tile `:self_update`,
  label "Updates", glyph `hero-arrow-down-circle` — distinct from the existing
  `:system` (CPU) tile.
* `2026-06-07` — Thresholds: `:check_failing` ≥3 consecutive failures;
  `:checks_stalled` ≥3× interval since last success.
* `2026-06-07` — **Phase 1 shipped** (commit pending). `SelfUpdate.Health`
  (durable `update.check_failure_streak` + `update.last_apply`), writers in
  `CheckerJob` (check outcome) and `Updater` (clear on apply start, record on
  the two failure transitions), `SelfUpdate.IncidentContext` (pure `decide/4` +
  `assess/0`), registered in `:diagnostics_contributors`, and the `:self_update`
  "Updates" tile (glyph `hero-arrow-down-circle`).
* `2026-06-07` — **`IncidentContext` fulfils the `assess/0` contract
  structurally, not via `@behaviour`.** Declaring the behaviour adds a
  compile-time `SelfUpdate → ErrorReports` edge that closes a Boundary cycle
  (`SelfUpdate → ErrorReports → Console → SelfUpdate`; `Console` already depends
  on `SelfUpdate` for `detected_unit/0`). The registry binds assessors by
  `function_exported?(module, :assess, 0)` — name-based — so the behaviour
  declaration is unnecessary, and omitting it keeps the boundary acyclic. (TMDB
  can declare `@behaviour` because nothing depends back into it.)
* `2026-06-07` — **Phase 2 shipped** (commit pending). `self_update_widget`
  Activity widget + story, `StatusLive` PubSub wiring, `:health_activity_widgets`
  registration. The render-path `activity_bundle/1` is kept DB-free by holding
  `last_check_at` in assigns; `SystemSection.tone_class/1` promoted to dedupe the
  tone→CSS map shared with the Settings card.

## Next steps

Concrete, ordered. Three phases.

### Phase 1 — Health half (tile reports correctly) — ✅ DONE

1. ✅ **`SelfUpdate.Health` projection** — durable record holding
   `consecutive_check_failures` and `last_apply_outcome` (`{result, version,
   reason, at}`), stored under `update.*` `Settings.Entry` keys. A pure builder
   + read function. Writers: `CheckerJob` (success resets the streak, failure
   increments) and `Updater` (records the terminal apply outcome on
   `:done` / `:failed`).
2. ✅ **`SelfUpdate.IncidentContext`** — pure `decide/4` + `assess/0` over
   `Health` + `last_check_at` age + config, returning the dominant fault or
   `:ok`. Registered in `:diagnostics_contributors` (bound by name, not
   `@behaviour` — see Decisions).
3. ✅ **Board entry** — `:self_update` added to `HealthBoard` subsystems / label
   ("Updates") / glyph (`hero-arrow-down-circle`); board tests updated to 8.
4. ✅ **Tests** — pure `decide/4` matrix, `Health` projection, and `assess/0`
   wiring (registry + reads). Full `mix precommit` green (4409 tests).

### Phase 2 — Observe half (drill-in widget) — ✅ DONE

5. ✅ **`self_update_widget`** in `ActivityWidgetComponents` — version, last/next
   check (reuses `SystemSection` helpers), classification, auto-install state,
   and a live apply-progress bar. Registered in `:health_activity_widgets`.
   `SystemSection.tone_class/1` promoted to a shared helper (was duplicated in
   `settings_live`). New side-effect-free `SelfUpdate.last_known_status/0` feeds it.
6. ✅ **Live wiring** — `StatusLive` subscribes to both self-update topics and
   folds a `self_update` slice into `activity_bundle/1`. The slice reads only
   assigns + `Config` (persistent_term) + `utc_now` — `last_check_at` is captured
   into assigns so the render path stays DB-free (ADR-012, no_db_on_render green).
7. ✅ **Storybook story** (7-variation matrix) + index entry; `/status?subsystem=
   self_update` page-smoke entry. Full `mix precommit` green (4412 tests).

### Phase 3 — Polish

8. **`vitals/0`** on the IncidentContext for cross-subsystem causality (current
   version, last check, classification).
9. Edge cases (never-checked install, deferred-while-playing apply, prod vs
   dev/test where `enabled?()` is false), then wiki/docs (Status page +
   Troubleshooting).

## Completion criteria

* The Status board shows an **Updates** tile that is `:ok` in the normal case
  and turns `:warning` / `:error` for the three defined fault kinds, raised and
  resolved through the existing incident evaluator.
* Drilling into the tile shows a live Activity widget with version, last/next
  check, classification, auto-install state, and apply progress — updating in
  real time via the two PubSub topics.
* `assess/0` and the `Health` projection are covered by pure unit tests; the
  widget has a Storybook story; `/status?subsystem=self_update` has a smoke entry.
* `mix precommit` green; wiki Status/Troubleshooting pages updated.
* Controls and history remain out of scope (recorded as deferred, not shipped).

## Pointers

* Design brainstorm: this file's Decisions section is the spec.
* Self-update context: `lib/media_centaur/self_update.ex` (`view_status/0`,
  `current_status/0`, `last_check_at/0`), `self_update/checker_job.ex`,
  `self_update/updater.ex`, `self_update/storage.ex`.
* Health board: `lib/media_centaur_web/live/status_live.ex`,
  `status_live/health_board.ex`, `status_live/subsystem_view.ex`,
  `status_live/activity_widgets.ex`,
  `lib/media_centaur_web/components/health_components.ex`,
  `components/activity_widget_components.ex`.
* Incident model: `lib/media_centaur/error_reports/incident_context.ex`
  (the behaviour), `error_reports/contributors.ex` (registry, `assessors/0`),
  `error_reports/store.ex` (`raise_fault` / `resolve_fault`),
  `error_reports/incident.ex`. Example contributor:
  `lib/media_centaur/tmdb/incident_context.ex`.
* Registries: `config/config.exs` (`:diagnostics_contributors`,
  `:health_activity_widgets`).
* Builds on v0.80.0 self-update fixes (commit `c7d80478`).
