# System Status Enrichment — Design

**Date:** 2026-06-09
**Status:** Approved, executing

## Problem

The System subsystem tile is the only board subsystem with no Activity widget — it's the catch-all ("application-runtime health… crashes, restarts, framework-level errors") but renders only the health floor. Give it a runtime-vitals widget for the enthusiast/homelab-operator persona (auto-memory `project-status-page-persona`).

## Scope

Bands **A (uptime/stability) + B (BEAM vitals) + C (host/build) + D (datastore)**. **Oban-wide job stats (E) are explicitly out** — deferred to a separate "Oban tuner" feature (queue concurrency + a Pruner; `oban_jobs` is currently unpruned). No error/incident re-listing (that's the board itself — auto-memory `feedback-status-widgets-no-rehash`).

## Design — reuse-first

### Net-new: `MediaCentaur.Runtime.Vitals`

A new small bounded context (`MediaCentaur.Runtime`, `use Boundary, deps: [MediaCentaur.ErrorReports], exports: [Vitals]`). Named `Runtime`, not `System`, to avoid clashing with Elixir's `System`. One cheap, all-in-VM `snapshot/0`:

```
%{
  uptime_seconds,                              # :erlang.monotonic_time - :erlang.system_info(:start_time)
  memory: %{total, processes, ets, binary},    # :erlang.memory/0 keys
  process_count, process_limit,                # :erlang.system_info/1
  run_queue,                                   # :erlang.statistics(:run_queue)
  schedulers,                                  # System.schedulers_online/0
  host: %{otp, elixir, os, version},           # reuse ErrorReports.EnvMetadata.collect/0
  db: %{size_bytes, wal_bytes}                 # File.stat on Config.get(:database_path) (+ "-wal")
}
```

`Config.get/1` needs no boundary dep (Config is `top_level?: true, check: [in: false]`). `EnvMetadata` is already exported from the `ErrorReports` boundary.

### `system_widget` (register `system:` in `:health_activity_widgets`)

Same idioms as the other tiles (`format_bytes/1` is already imported from `StatusHelpers`):
- **Header**: `System` + an uptime pill — `Up 3d 4h` (band A, the stability headline).
- **Vitals stat figures** (band B + D): three big `tabular-nums` figures — **Memory** (`format_bytes(total)`) · **Processes** (`process_count`) · **DB** (`format_bytes(size_bytes)`). Neutral (informational).
- **Runtime detail rows** (band B): `schedulers`, `run queue`, `process limit`, `WAL` size. **Color = signal**: run-queue row amber when `run_queue > schedulers`; process row amber when `process_count > 0.8 * process_limit`.
- **Host/build footer** (band C): quiet `OTP {otp} · Elixir {elixir} · {os}`.

### StatusLive wiring

Assemble `system_vitals: Vitals.snapshot()` on connected mount (disconnected → a static empty snapshot), refresh it on the existing `:refresh_storage` tick (5 min — vitals are a health glance, not real-time monitoring; a faster dedicated tick is a trivial follow-up if wanted), and add it to `activity_bundle/1`. Add `MediaCentaur.Runtime` to the `MediaCentaurWeb` boundary deps.

## What this is NOT

- No Oban/job stats (separate Oban-tuner feature).
- No error/incident re-listing (the board already shows that).
- No new runtime probes — every field is an in-VM `:erlang`/`System` call or a `File.stat`.
- Not real-time — refreshes on the 5-min storage tick + mount.

## Testing

- `Vitals.snapshot/0` — unit test: asserts the shape and types (uptime ≥ 0 integer, memory map with positive total, process_count > 0, schedulers > 0, host map with otp/elixir/os strings, db map with non-negative sizes). All in-VM, deterministic enough to assert structure/bounds (not exact values).
- Widget render — storybook variations (MC0009): healthy, run-queue-backed-up (amber), process-near-limit (amber).
- StatusLive — existing tests stay green; add an assertion that `?subsystem=system` renders the `system-widget` testid.

## Files

- New: `lib/media_centaur/runtime.ex` (context + boundary), `lib/media_centaur/runtime/vitals.ex` (+ test).
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex` (`system_widget/1` + helpers).
- Modify: `config/config.exs` (register `system:`), `lib/media_centaur_web.ex` (boundary dep), `lib/media_centaur_web/live/status_live.ex` (assemble + refresh + bundle).
- New: `storybook/status/system_widget.story.exs`.
- Modify: `test/media_centaur_web/live/status_live_test.exs`.

## Follow-up (separate feature, after this)

**Oban tuner** — UI to tune queue concurrency, plus add `Oban.Plugins.Pruner` (fixes the unbounded `oban_jobs` growth found during this design). At that point an Oban-wide stats band could be revisited cheaply.
