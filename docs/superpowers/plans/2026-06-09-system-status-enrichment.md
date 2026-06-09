# System Status Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the System status tile its first Activity widget — a runtime-vitals panel (uptime, BEAM memory/processes, host/build facts, datastore footprint) — from one cheap in-VM snapshot, reusing `EnvMetadata` and `format_bytes`.

**Architecture:** A new small `MediaCentaur.Runtime` bounded context exposes `Vitals.snapshot/0` (all `:erlang`/`System`/`File.stat` reads). `StatusLive` assembles it into the activity bundle; a new `system_widget/1` renders uptime + stat figures + detail rows + a host footer, with health color only on a backed-up run queue / process saturation. No Oban (deferred to a separate Oban-tuner feature).

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, daisyUI/Tailwind, ExUnit.

---

## Background facts (verified — do not re-derive)

- `system` is in `HealthBoard.board_subsystems()` (label "System", glyph "hero-cpu-chip") but ABSENT from `config/config.exs` `:health_activity_widgets` — so its drill-in renders the health floor. Registering it makes `ActivityWidgets.render(@selected_subsystem, activity_bundle(assigns))` (status_live.ex:582) render the widget.
- `MediaCentaur.ErrorReports.EnvMetadata.collect/0` (exported from the ErrorReports boundary) returns `%{app_version, otp_release, elixir_version, os, locale, uptime}` — all strings. `os` is like `"unix/linux 6.0.10 (x86_64-...)"`.
- Uptime idiom (from `SelfUpdate.IncidentContext`): `:erlang.monotonic_time() - :erlang.system_info(:start_time)` in native units → seconds via `System.convert_time_unit(native, :native, :second)`.
- `:erlang.memory/0` → keyword with `:total, :processes, :ets, :binary` (among others). `:erlang.system_info(:process_count|:process_limit)` → ints. `:erlang.statistics(:run_queue)` → int. `System.schedulers_online/0` → int.
- `MediaCentaur.Config.get(:database_path)` → the SQLite DB path string. Config is `use Boundary, top_level?: true, check: [in: false, out: false]` — callers need NO boundary dep on it.
- `format_bytes/1` is defined in `MediaCentaurWeb.StatusHelpers` and already `import`ed into `MediaCentaurWeb.ActivityWidgetComponents`.
- `MediaCentaurWeb` boundary (`lib/media_centaur_web.ex`) has a `deps: [...]` list; new contexts the web calls must be added to it.
- `StatusLive`: `assign_self_update/1` pattern shows how snapshots are assigned; the connected mount assigns chain is ~status_live.ex:69-89; the disconnected branch ~91-103; `:refresh_storage` handle_info reschedules every `@storage_refresh_ms` (5 min); `activity_bundle/1` is ~status_live.ex:255-289.
- Status tests use `live_async!/2` and `~p"/status?subsystem=system"`.
- No `storybook/status/system_widget.story.exs` exists yet.

---

## Task 1: Runtime.Vitals snapshot

**Files:**
- Create: `lib/media_centaur/runtime.ex`
- Create: `lib/media_centaur/runtime/vitals.ex`
- Test: `test/media_centaur/runtime/vitals_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Runtime.VitalsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Runtime.Vitals

  test "snapshot/0 returns well-formed, in-bounds runtime vitals" do
    snap = Vitals.snapshot()

    assert is_integer(snap.uptime_seconds) and snap.uptime_seconds >= 0

    assert %{total: total, processes: processes, ets: ets, binary: binary} = snap.memory
    assert total > 0 and processes > 0 and ets >= 0 and binary >= 0

    assert snap.process_count > 0
    assert snap.process_limit >= snap.process_count
    assert snap.run_queue >= 0
    assert snap.schedulers > 0

    assert %{otp: otp, elixir: elixir, os: os, version: version} = snap.host
    assert is_binary(otp) and is_binary(elixir) and is_binary(os) and is_binary(version)

    assert %{size_bytes: db_size, wal_bytes: wal} = snap.db
    assert is_integer(db_size) and db_size >= 0
    assert is_integer(wal) and wal >= 0
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/runtime/vitals_test.exs`
Expected: FAIL — `Vitals` undefined.

- [ ] **Step 3: Create the context boundary root**

`lib/media_centaur/runtime.ex`:

```elixir
defmodule MediaCentaur.Runtime do
  use Boundary, deps: [MediaCentaur.ErrorReports], exports: [Vitals]

  @moduledoc """
  Application-runtime introspection for the System status tile: BEAM/VM vitals,
  uptime, host/build facts, and datastore footprint. Read-only snapshots — no
  processes, no persistence. Named `Runtime` (not `System`) to avoid clashing
  with Elixir's `System` module.
  """
end
```

- [ ] **Step 4: Implement `Vitals`**

`lib/media_centaur/runtime/vitals.ex`:

```elixir
defmodule MediaCentaur.Runtime.Vitals do
  @moduledoc """
  A single cheap, all-in-VM snapshot of runtime health for the System status
  tile: uptime, memory/process/scheduler vitals, host/build facts (reused from
  `ErrorReports.EnvMetadata`), and the SQLite datastore footprint.

  ## Shape

      %{uptime_seconds: non_neg_integer(),
        memory: %{total: pos_integer(), processes: pos_integer(), ets: non_neg_integer(), binary: non_neg_integer()},
        process_count: pos_integer(), process_limit: pos_integer(),
        run_queue: non_neg_integer(), schedulers: pos_integer(),
        host: %{otp: String.t(), elixir: String.t(), os: String.t(), version: String.t()},
        db: %{size_bytes: non_neg_integer(), wal_bytes: non_neg_integer()}}
  """
  alias MediaCentaur.ErrorReports.EnvMetadata

  @spec snapshot() :: map()
  def snapshot do
    mem = :erlang.memory()

    %{
      uptime_seconds: uptime_seconds(),
      memory: %{
        total: mem[:total],
        processes: mem[:processes],
        ets: mem[:ets],
        binary: mem[:binary]
      },
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: System.schedulers_online(),
      host: host_facts(),
      db: db_sizes()
    }
  end

  defp uptime_seconds do
    native = :erlang.monotonic_time() - :erlang.system_info(:start_time)
    System.convert_time_unit(native, :native, :second)
  end

  defp host_facts do
    meta = EnvMetadata.collect()
    %{otp: meta.otp_release, elixir: meta.elixir_version, os: meta.os, version: meta.app_version}
  end

  defp db_sizes do
    path = MediaCentaur.Config.get(:database_path)
    %{size_bytes: file_size(path), wal_bytes: file_size(wal_path(path))}
  end

  defp wal_path(nil), do: nil
  defp wal_path(path), do: path <> "-wal"

  defp file_size(nil), do: 0

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/media_centaur/runtime/vitals_test.exs`
Expected: PASS (1 test).

- [ ] **Step 6: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/runtime.ex lib/media_centaur/runtime/vitals.ex test/media_centaur/runtime/vitals_test.exs
git commit -m "feat(runtime): Vitals snapshot — uptime, BEAM memory/processes, host, datastore"
```

---

## Task 2: system_widget + story

Built and verified in isolation via storybook. Not registered yet (Task 3), so no live page renders it — nothing else breaks.

**Files:**
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex`
- Create: `storybook/status/system_widget.story.exs`

- [ ] **Step 1: Add the attr + widget function**

Add near the other widget functions in `activity_widget_components.ex` (e.g. after `acquisition_widget/1`). `format_bytes/1` is already imported; `<.settings_link>` and `<.icon>` are in scope.

```elixir
  @doc "System (runtime) Activity widget: uptime, BEAM vitals, host facts, datastore footprint."
  attr :system_vitals, :map,
    required: true,
    doc: "Runtime.Vitals.snapshot/0 bundle (uptime_seconds, memory, process_*, run_queue, schedulers, host, db)"

  def system_widget(assigns) do
    v = assigns.system_vitals
    proc_tone = if v.process_count > v.process_limit * 0.8, do: :warn, else: :ok
    rq_tone = if v.run_queue > v.schedulers, do: :warn, else: :ok

    assigns =
      assigns
      |> Map.put(:proc_tone, proc_tone)
      |> Map.put(:rq_tone, rq_tone)

    ~H"""
    <div class="card glass-surface" data-testid="system-widget">
      <div class="card-body">
        <%!-- Header + uptime (stability headline) --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">System</h2>
          <span class="text-xs text-base-content/60">
            Up {format_uptime(@system_vitals.uptime_seconds)}
          </span>
        </div>

        <%!-- Vitals stat figures (neutral) --%>
        <div data-component="system-vitals" class="mt-2 grid grid-cols-3 gap-3">
          <div>
            <div class="text-2xl font-semibold tabular-nums">
              {format_bytes(@system_vitals.memory.total)}
            </div>
            <div class="text-xs uppercase tracking-wider text-base-content/50">Memory</div>
          </div>
          <div>
            <div class="text-2xl font-semibold tabular-nums">{@system_vitals.process_count}</div>
            <div class="text-xs uppercase tracking-wider text-base-content/50">Processes</div>
          </div>
          <div>
            <div class="text-2xl font-semibold tabular-nums">
              {format_bytes(@system_vitals.db.size_bytes)}
            </div>
            <div class="text-xs uppercase tracking-wider text-base-content/50">Database</div>
          </div>
        </div>

        <%!-- Runtime detail rows (color = signal) --%>
        <div
          data-component="system-detail"
          class="mt-3 pt-3 border-t border-base-content/10 grid grid-cols-2 gap-x-6 gap-y-1 text-xs"
        >
          <div class="flex items-center justify-between">
            <span class="text-base-content/50">Schedulers</span>
            <span class="tabular-nums text-base-content/70">{@system_vitals.schedulers}</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-base-content/50">Run queue</span>
            <span class={["tabular-nums", tone_chrome(@rq_tone).text]}>{@system_vitals.run_queue}</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-base-content/50">Processes / limit</span>
            <span class={["tabular-nums", tone_chrome(@proc_tone).text]}>
              {@system_vitals.process_count} / {@system_vitals.process_limit}
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-base-content/50">WAL</span>
            <span class="tabular-nums text-base-content/70">
              {format_bytes(@system_vitals.db.wal_bytes)}
            </span>
          </div>
        </div>

        <%!-- Host / build footer (quiet) --%>
        <div data-component="system-host" class="mt-3 text-xs text-base-content/40">
          OTP {@system_vitals.host.otp} · Elixir {@system_vitals.host.elixir} · {@system_vitals.host.os}
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 2: Add the `format_uptime/1` helper**

Place with the other private helpers (e.g. near `format_recent_title/1`). `tone_chrome/1` already exists (added for the acquisition widget) — reuse it; do NOT redefine it.

```elixir
  defp format_uptime(s) when s < 60, do: "#{s}s"
  defp format_uptime(s) when s < 3600, do: "#{div(s, 60)}m"
  defp format_uptime(s) when s < 86_400, do: "#{div(s, 3600)}h #{rem(div(s, 60), 60)}m"
  defp format_uptime(s), do: "#{div(s, 86_400)}d #{rem(div(s, 3600), 24)}h"
```

> Note: `tone_chrome/1` is the shared helper added in the acquisition widget (`:ok → text-success`, `:warn → text-warning`, etc.). Confirm it exists before relying on it; it returns a map with `:text` and `:dot`.

- [ ] **Step 3: Write the story**

Create `storybook/status/system_widget.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.SystemWidget do
  @moduledoc "Storybook coverage for the System runtime-vitals widget."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.system_widget/1

  def render_source, do: :function

  def variations do
    host = %{otp: "27", elixir: "1.18.1", os: "unix/linux 6.0.10 (x86_64-pc-linux-gnu)", version: "0.86.1"}
    db = %{size_bytes: 148_897_792, wal_bytes: 4_194_304}

    healthy = %{
      uptime_seconds: 273_600,
      memory: %{total: 298_844_160, processes: 121_634_816, ets: 18_874_368, binary: 41_943_040},
      process_count: 1432,
      process_limit: 262_144,
      run_queue: 0,
      schedulers: 8,
      host: host,
      db: db
    }

    [
      %Variation{id: :healthy, attributes: %{system_vitals: healthy}},
      %Variation{
        id: :run_queue_backed_up,
        attributes: %{system_vitals: %{healthy | run_queue: 14}}
      },
      %Variation{
        id: :processes_near_limit,
        attributes: %{system_vitals: %{healthy | process_count: 230_000}}
      }
    ]
  end
end
```

- [ ] **Step 4: Compile + render**

Run: `mix compile --warnings-as-errors`
Run: `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS — the system story compiles and all 3 variations render (`run_queue_backed_up` and `processes_near_limit` exercise the amber `tone_chrome(:warn)` path).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/activity_widget_components.ex storybook/status/system_widget.story.exs
git commit -m "feat(status): system runtime-vitals widget — uptime, BEAM vitals, host, datastore"
```

---

## Task 3: Register + wire into StatusLive

**Files:**
- Modify: `config/config.exs`
- Modify: `lib/media_centaur_web.ex`
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Test: `test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/status_live_test.exs` a `describe "system activity widget"`:

```elixir
  describe "system activity widget" do
    test "system drill-in renders the runtime-vitals widget", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=system")
      assert html =~ ~s(data-testid="system-widget")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: the new test FAILS — `system` not registered, so the drill-in has no widget. Pre-existing tests stay green.

- [ ] **Step 3: Register the widget**

In `config/config.exs` `:health_activity_widgets`, add the `system` entry:

```elixir
  system: {MediaCentaurWeb.ActivityWidgetComponents, :system_widget},
```

- [ ] **Step 4: Add the boundary dep**

In `lib/media_centaur_web.ex`, add `MediaCentaur.Runtime` to the `use Boundary, deps: [...]` list (alphabetical-ish, near the other `MediaCentaur.*` entries):

```elixir
      MediaCentaur.Runtime,
```

- [ ] **Step 5: Alias + assemble in StatusLive**

In `lib/media_centaur_web/live/status_live.ex` alias block, add (skip if present):

```elixir
  alias MediaCentaur.Runtime.Vitals
```

In the connected-mount assign chain (near `assign(playback_activity: ...)`), add:

```elixir
        |> assign(system_vitals: Vitals.snapshot())
```

In the disconnected-mount branch (near `assign(playback_activity: PlaybackActivity.empty())`), add a static empty snapshot:

```elixir
        |> assign(system_vitals: empty_system_vitals())
```

Add the private helper (group with the other `build_*`/`empty_*` helpers):

```elixir
  defp empty_system_vitals do
    %{
      uptime_seconds: 0,
      memory: %{total: 0, processes: 0, ets: 0, binary: 0},
      process_count: 0,
      process_limit: 0,
      run_queue: 0,
      schedulers: 0,
      host: %{otp: "", elixir: "", os: "", version: ""},
      db: %{size_bytes: 0, wal_bytes: 0}
    }
  end
```

- [ ] **Step 6: Refresh on the storage tick + add to bundle**

Find the `:refresh_storage` `handle_info` clause (it reschedules itself every `@storage_refresh_ms`). Add the vitals re-assemble to it — change its `assign(...)` to also set `system_vitals: Vitals.snapshot()`. For example, if it currently ends `{:noreply, start_async_storage(socket)}` or assigns storage, wrap so it also does `assign(socket, system_vitals: Vitals.snapshot())`. Concretely, add this line into that handler's socket pipeline (READ the handler first and splice cleanly):

```elixir
    socket = assign(socket, system_vitals: Vitals.snapshot())
```

In `activity_bundle/1`, near `playback_activity: assigns.playback_activity,`, add:

```elixir
      system_vitals: assigns.system_vitals,
```

> The disconnected mount uses `empty_system_vitals/0`; the empty snapshot's `process_limit: 0` makes `process_count > process_limit * 0.8` false (0 > 0 is false) → no spurious amber. Safe.

- [ ] **Step 7: Run the wiring test (green)**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS — `system-widget` renders in the drill-in; all pre-existing tests green.

- [ ] **Step 8: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations (web → `MediaCentaur.Runtime` now declared).

- [ ] **Step 9: Commit**

```bash
git add config/config.exs lib/media_centaur_web.ex lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): register + wire the system runtime-vitals widget"
```

---

## Task 4: Full precommit + self-screenshot + wiki

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: format, Credo (incl. MC0009), boundaries, sobelow/deps.audit, full suite all green.

> If Credo flags "nested modules could be aliased" for `MediaCentaur.Runtime.Vitals` in status_live.ex, the Step 5 alias covers it. Known intermittent SQLite flake → re-run the file with `--repeat-until-failure 50`.

- [ ] **Step 2: Self-capture (don't ask the user)**

If :1080 is up: capture the storybook variation in isolation (sidebar-free) —
`~/scripts/agents/viz-screenshot --url 'http://localhost:1080/storybook/iframe/status/system_widget?variation_id=healthy' --viewport 700x500 --wait-ms 2500 -o /tmp/system-now.png`, Read it, sanity-check (uptime pill, three stat figures, detail grid, host footer; amber on the backed-up/near-limit variations). Per auto-memory `reference-responsive-ui-screenshot`.

- [ ] **Step 3: Wiki sync**

The System status tile now shows runtime vitals (uptime, memory, processes, DB footprint, host/build).

```sh
cd ~/src/media-centaur/media-centaur.wiki
# note the System tile now shows uptime + BEAM vitals + host/build + datastore footprint.
git add -A && git commit -m "wiki: System status tile now shows runtime vitals" && git push
```

> If the wiki page is unclear, grep for "status"; if none, record as a follow-up.

---

## Notes / scope cuts

- **No Oban/job stats** — deferred to the separate "Oban tuner" feature (which will also add `Oban.Plugins.Pruner` to fix unbounded `oban_jobs` growth).
- **No error/incident re-listing** — the board already shows that.
- **Refresh on the 5-min storage tick** + mount; a faster dedicated vitals tick is a trivial follow-up if liveliness is wanted.
- Color reserved to a backed-up run queue / process saturation; everything else neutral.
- Spec: `docs/superpowers/specs/2026-06-09-system-status-enrichment-design.md`. Persona: auto-memory `project-status-page-persona`.
```
