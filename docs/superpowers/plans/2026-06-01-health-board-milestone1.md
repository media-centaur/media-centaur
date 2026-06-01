# Health Board — Milestone 1 (read-surface) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This repo is **strictly test-first** — write the failing test, see it fail, then implement.

**Goal:** Rebuild `/status` to lead with a Subsystem Health Board (tiles + health) and an inline stacked drill-in (Issues → Activity placeholder → collapsed Logs), with incident-anchored "Report this" wired to the existing submission — introduced *non-destructively* (existing operational sections stay until later milestones fold them into per-subsystem widgets).

**Architecture:** Pure view-model helpers (`StatusLive.HealthBoard`) derive tile state from `ErrorReports.health/0` + `list_buckets/0` grouped by component. New function components (`subsystem_tile/1`, `health_drill_in/1`, `incident_row/1`) render the board; each gets a typed ViewModel struct (MC0008) and a Storybook story (MC0009). Tile click drives `push_patch` `?subsystem=` → `handle_params` selects the drill-in. No new backend — read-only over the Phase 1–3 store.

**Tech Stack:** Phoenix LiveView, function components, daisyUI/Tailwind, Phoenix Storybook, ExUnit (`async: true` pure tests + `ConnCase` smoke).

**Design spec:** [`2026-06-01-phase4-health-board-ui.md`](../specs/2026-06-01-phase4-health-board-ui.md). Mockups: `mockups/observability/1b-health-board-refined` (board), `5-drill-in-stacked` (drill-in).

---

## File structure

- Create `lib/media_centaur_web/live/status_live/health_board.ex` — pure view-model + helpers (labels, glyphs, grouping, tile state, headlines). One responsibility: turn store data into renderable view-models.
- Create `lib/media_centaur_web/live/status_live/subsystem_view.ex` — the `SubsystemView` struct (typed attr target for the tile, MC0008).
- Create `lib/media_centaur_web/components/health_components.ex` — `subsystem_tile/1`, `health_drill_in/1`, `incident_row/1` function components.
- Create stories under `storybook/health/` — one per new component (MC0009).
- Modify `lib/media_centaur_web/live/status_live.ex` — assigns (`board`, `selected_subsystem`, `drill_in`), `handle_params` selection, render the board above existing sections, tile/close events.
- Modify `test/media_centaur_web/page_smoke_test.exs` — `/status?subsystem=pipeline` fixture exercising healthy + unhealthy + open drill-in.
- Create `test/media_centaur_web/live/status_live/health_board_test.exs` — pure helper tests.

**Provisional user-facing labels** (easily changed in `HealthBoard.label/1`): watcher→"Watcher", pipeline→"Import", tmdb→"Metadata", playback→"Playback", library→"Library", acquisition→"Downloads", system→"System". Framework components (`:phoenix :ecto :live_view`) fold under `:system`.

---

### Task 1: HealthBoard pure helpers — labels & glyphs

**Files:**
- Create: `lib/media_centaur_web/live/status_live/health_board.ex`
- Test: `test/media_centaur_web/live/status_live/health_board_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaurWeb.StatusLive.HealthBoardTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.HealthBoard

  describe "board_subsystems/0" do
    test "lists the seven app subsystems in display order" do
      assert HealthBoard.board_subsystems() ==
               [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :system]
    end
  end

  describe "label/1 and glyph/1" do
    test "maps each subsystem to a friendly label and a heroicon glyph" do
      assert HealthBoard.label(:pipeline) == "Import"
      assert HealthBoard.label(:tmdb) == "Metadata"
      assert HealthBoard.label(:acquisition) == "Downloads"
      assert "hero-" <> _ = HealthBoard.glyph(:pipeline)
    end

    test "unknown component falls back to system" do
      assert HealthBoard.label(:phoenix) == "System"
      assert HealthBoard.glyph(:nonsense) == HealthBoard.glyph(:system)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live/health_board_test.exs`
Expected: FAIL — `HealthBoard` module/functions undefined.

- [ ] **Step 3: Write minimal implementation**

```elixir
defmodule MediaCentaurWeb.StatusLive.HealthBoard do
  @moduledoc """
  Pure view-model helpers for the Subsystem Health Board. Turns the
  `ErrorReports` store rollups into renderable per-subsystem view-models.
  No DB, no rendering — unit-tested in isolation (ADR-030).
  """

  @board_subsystems [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :system]

  @labels %{
    watcher: "Watcher",
    pipeline: "Import",
    tmdb: "Metadata",
    playback: "Playback",
    library: "Library",
    acquisition: "Downloads",
    system: "System"
  }

  @glyphs %{
    watcher: "hero-eye",
    pipeline: "hero-arrow-down-on-square-stack",
    tmdb: "hero-film",
    playback: "hero-play-circle",
    library: "hero-rectangle-stack",
    acquisition: "hero-arrow-down-tray",
    system: "hero-cpu-chip"
  }

  @spec board_subsystems() :: [atom()]
  def board_subsystems, do: @board_subsystems

  @spec label(atom()) :: String.t()
  def label(component), do: Map.get(@labels, normalize(component), @labels.system)

  @spec glyph(atom()) :: String.t()
  def glyph(component), do: Map.get(@glyphs, normalize(component), @glyphs.system)

  # Framework + unknown components fold under :system on the board.
  defp normalize(component) when component in @board_subsystems, do: component
  defp normalize(_), do: :system
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/media_centaur_web/live/status_live/health_board_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/health_board.ex test/media_centaur_web/live/status_live/health_board_test.exs
git commit -m "feat(status): HealthBoard subsystem labels + glyphs"
```

---

### Task 2: HealthBoard — group buckets by subsystem

**Files:**
- Modify: `lib/media_centaur_web/live/status_live/health_board.ex`
- Test: `test/media_centaur_web/live/status_live/health_board_test.exs`

- [ ] **Step 1: Write the failing test** (add to the existing test file)

```elixir
  describe "group_buckets/1" do
    alias MediaCentaur.ErrorReports.Bucket

    defp bucket(component, severity) do
      %Bucket{
        fingerprint: "fp-#{component}-#{severity}",
        component: component,
        normalized_message: "msg",
        display_title: "Title",
        severity: severity,
        count: 1,
        first_seen: ~U[2026-06-01 10:00:00Z],
        last_seen: ~U[2026-06-01 12:00:00Z],
        sample_entries: []
      }
    end

    test "groups buckets by component, folding framework comps under :system" do
      buckets = [bucket(:pipeline, :error), bucket(:ecto, :warning), bucket(:system, :warning)]
      grouped = HealthBoard.group_buckets(buckets)

      assert [%Bucket{component: :pipeline}] = grouped[:pipeline]
      # :ecto folds into :system alongside the native :system bucket
      assert length(grouped[:system]) == 2
    end

    test "every board subsystem has a (possibly empty) entry" do
      grouped = HealthBoard.group_buckets([])
      for s <- HealthBoard.board_subsystems(), do: assert(grouped[s] == [])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live/health_board_test.exs`
Expected: FAIL — `group_buckets/1` undefined.

- [ ] **Step 3: Write minimal implementation** (add to `HealthBoard`)

```elixir
  alias MediaCentaur.ErrorReports.Bucket

  @doc """
  Groups buckets by board subsystem. Framework/unknown components fold under
  `:system`. Every board subsystem is present with at least an empty list.
  """
  @spec group_buckets([Bucket.t()]) :: %{atom() => [Bucket.t()]}
  def group_buckets(buckets) do
    base = Map.new(@board_subsystems, &{&1, []})

    buckets
    |> Enum.group_by(fn %Bucket{component: c} -> normalize(c) end)
    |> then(&Map.merge(base, &1))
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/media_centaur_web/live/status_live/health_board_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/health_board.ex test/media_centaur_web/live/status_live/health_board_test.exs
git commit -m "feat(status): group buckets by subsystem for the board"
```

---

### Task 3: HealthBoard — derive tile state

**Files:**
- Modify: `lib/media_centaur_web/live/status_live/health_board.ex`
- Test: `test/media_centaur_web/live/status_live/health_board_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "tile_state/1" do
    alias MediaCentaur.ErrorReports.Bucket

    defp b(severity), do: %Bucket{
      fingerprint: "fp", component: :pipeline, normalized_message: "m",
      display_title: "t", severity: severity, count: 2,
      first_seen: ~U[2026-06-01 10:00:00Z], last_seen: ~U[2026-06-01 12:00:00Z],
      sample_entries: []
    }

    test "no buckets => :ok with zero counts" do
      assert %{state: :ok, error_count: 0, warning_count: 0} = HealthBoard.tile_state([])
    end

    test "any error/critical => :error; counts reflect severities" do
      assert %{state: :error, error_count: 1, warning_count: 1} =
               HealthBoard.tile_state([b(:error), b(:warning)])
      assert %{state: :error} = HealthBoard.tile_state([b(:critical)])
    end

    test "only warnings => :warning" do
      assert %{state: :warning, error_count: 0, warning_count: 2} =
               HealthBoard.tile_state([b(:warning), b(:warning)])
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live/health_board_test.exs`
Expected: FAIL — `tile_state/1` undefined.

- [ ] **Step 3: Write minimal implementation**

```elixir
  @type tile_state :: %{
          state: :ok | :warning | :error,
          error_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }

  @doc "Derives a tile's health state from its buckets. critical+error => :error."
  @spec tile_state([Bucket.t()]) :: tile_state()
  def tile_state(buckets) do
    error_count = Enum.count(buckets, &(&1.severity in [:error, :critical]))
    warning_count = Enum.count(buckets, &(&1.severity == :warning))

    state =
      cond do
        error_count > 0 -> :error
        warning_count > 0 -> :warning
        true -> :ok
      end

    %{state: state, error_count: error_count, warning_count: warning_count}
  end
```

- [ ] **Step 4: Run test to verify it passes** — `mix test test/media_centaur_web/live/status_live/health_board_test.exs` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/health_board.ex test/media_centaur_web/live/status_live/health_board_test.exs
git commit -m "feat(status): derive subsystem tile health state"
```

---

### Task 4: SubsystemView struct + build_board/2

**Files:**
- Create: `lib/media_centaur_web/live/status_live/subsystem_view.ex`
- Modify: `lib/media_centaur_web/live/status_live/health_board.ex`
- Test: `test/media_centaur_web/live/status_live/health_board_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
  describe "build_board/1" do
    alias MediaCentaur.ErrorReports.Bucket
    alias MediaCentaurWeb.StatusLive.SubsystemView

    test "returns one SubsystemView per board subsystem, in order, with label/glyph/state" do
      buckets = [%Bucket{
        fingerprint: "fp", component: :pipeline, normalized_message: "m",
        display_title: "t", severity: :error, count: 1,
        first_seen: ~U[2026-06-01 10:00:00Z], last_seen: ~U[2026-06-01 12:00:00Z],
        sample_entries: []
      }]

      views = HealthBoard.build_board(buckets)

      assert length(views) == 7
      assert Enum.map(views, & &1.component) == HealthBoard.board_subsystems()

      import_view = Enum.find(views, &(&1.component == :pipeline))
      assert %SubsystemView{label: "Import", state: :error, error_count: 1} = import_view
      assert "hero-" <> _ = import_view.glyph
    end
  end
```

- [ ] **Step 2: Run test to verify it fails** — undefined `SubsystemView` / `build_board/1`.

- [ ] **Step 3: Write the struct**, `lib/media_centaur_web/live/status_live/subsystem_view.ex`:

```elixir
defmodule MediaCentaurWeb.StatusLive.SubsystemView do
  @moduledoc "Typed view-model for one subsystem tile (MC0008 typed-attr target)."

  @enforce_keys [:component, :label, :glyph, :state, :error_count, :warning_count]
  defstruct [:component, :label, :glyph, :state, :error_count, :warning_count]

  @type t :: %__MODULE__{
          component: atom(),
          label: String.t(),
          glyph: String.t(),
          state: :ok | :warning | :error,
          error_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }
end
```

- [ ] **Step 4: Add `build_board/1`** to `HealthBoard`:

```elixir
  alias MediaCentaurWeb.StatusLive.SubsystemView

  @doc "Builds the ordered list of subsystem tile view-models from all buckets."
  @spec build_board([Bucket.t()]) :: [SubsystemView.t()]
  def build_board(buckets) do
    grouped = group_buckets(buckets)

    Enum.map(@board_subsystems, fn component ->
      %{state: state, error_count: ec, warning_count: wc} = tile_state(grouped[component])

      %SubsystemView{
        component: component,
        label: label(component),
        glyph: glyph(component),
        state: state,
        error_count: ec,
        warning_count: wc
      }
    end)
  end
```

- [ ] **Step 5: Run test** → PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/status_live/subsystem_view.ex lib/media_centaur_web/live/status_live/health_board.ex test/media_centaur_web/live/status_live/health_board_test.exs
git commit -m "feat(status): SubsystemView + build_board view-model"
```

---

### Task 5: subsystem_tile/1 component + story

**Files:**
- Create: `lib/media_centaur_web/components/health_components.ex`
- Create: `storybook/health/subsystem_tile.story.exs`

- [ ] **Step 1: Write the component** (`health_components.ex`):

```elixir
defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc "Function components for the Subsystem Health Board (Phase 4)."
  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.StatusLive.SubsystemView

  @doc "One subsystem tile: name + neutral glyph + type; color only for health."
  attr :view, SubsystemView, required: true
  attr :selected, :boolean, default: false
  attr :on_select, :string, default: "select_subsystem"

  def subsystem_tile(assigns) do
    ~H"""
    <button
      id={"subsystem-tile-#{@view.component}"}
      type="button"
      phx-click={@on_select}
      phx-value-subsystem={@view.component}
      data-nav-item
      tabindex="0"
      class={[
        "glass-surface rounded-xl p-4 text-left w-full flex items-start gap-3 transition-colors",
        @view.state == :error && "border-l-2 border-error",
        @view.state == :warning && "border-l-2 border-warning",
        @selected && "ring-1 ring-primary/40"
      ]}
    >
      <.icon name={@view.glyph} class="size-5 shrink-0 text-base-content/65 mt-0.5" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <span class="font-medium truncate">{@view.label}</span>
          <span class={[
            "size-2 rounded-full shrink-0",
            @view.state == :ok && "bg-success/55",
            @view.state == :warning && "bg-warning",
            @view.state == :error && "bg-error"
          ]} />
        </div>
        <p class="text-sm text-base-content/55 mt-1">{tile_summary(@view)}</p>
      </div>
    </button>
    """
  end

  @doc false
  def tile_summary(%SubsystemView{state: :ok}), do: "No issues"

  def tile_summary(%SubsystemView{error_count: ec, warning_count: wc}) do
    parts =
      [ec > 0 && "#{ec} #{pluralize(ec, "error")}", wc > 0 && "#{wc} #{pluralize(wc, "warning")}"]
      |> Enum.filter(& &1)

    Enum.join(parts, " · ")
  end

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"
end
```

- [ ] **Step 2: Write the story** (`storybook/health/subsystem_tile.story.exs`):

```elixir
defmodule MediaCentaurWeb.Storybook.Health.SubsystemTile do
  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.StatusLive.SubsystemView

  def function, do: &MediaCentaurWeb.HealthComponents.subsystem_tile/1

  defp view(component, label, glyph, state, ec, wc),
    do: %SubsystemView{component: component, label: label, glyph: glyph, state: state, error_count: ec, warning_count: wc}

  def variations do
    [
      %Variation{id: :healthy, attributes: %{view: view(:watcher, "Watcher", "hero-eye", :ok, 0, 0)}},
      %Variation{id: :warning, attributes: %{view: view(:tmdb, "Metadata", "hero-film", :warning, 0, 3)}},
      %Variation{id: :error, attributes: %{view: view(:pipeline, "Import", "hero-arrow-down-tray", :error, 2, 1)}},
      %Variation{id: :selected, attributes: %{view: view(:pipeline, "Import", "hero-arrow-down-tray", :error, 2, 1), selected: true}}
    ]
  end
end
```

- [ ] **Step 3: Verify it compiles & the story renders**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS (story compiles and renders).

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur_web/components/health_components.ex storybook/health/subsystem_tile.story.exs
git commit -m "feat(status): subsystem_tile component + story"
```

---

### Task 6: incident_row/1 + health_drill_in/1 components + stories

**Files:**
- Modify: `lib/media_centaur_web/components/health_components.ex`
- Create: `storybook/health/incident_row.story.exs`, `storybook/health/health_drill_in.story.exs`

- [ ] **Step 1: Add `incident_row/1`** (renders one reportable bucket):

```elixir
  alias MediaCentaur.ErrorReports.Bucket

  @doc "One reportable incident row in the drill-in Issues section."
  attr :bucket, Bucket, required: true
  attr :on_report, :string, default: "report_incident"

  def incident_row(assigns) do
    ~H"""
    <div id={"incident-#{@bucket.fingerprint}"} class="glass-inset rounded-lg p-3 flex items-start gap-3">
      <span class={[
        "size-2 rounded-full shrink-0 mt-1.5",
        @bucket.severity == :warning && "bg-warning",
        @bucket.severity in [:error, :critical] && "bg-error"
      ]} />
      <div class="min-w-0 flex-1">
        <p class="text-sm">{@bucket.display_title}</p>
        <p class="text-xs text-base-content/50 mt-0.5">
          {@bucket.count}× · since {Calendar.strftime(@bucket.first_seen, "%b %-d, %H:%M")}
        </p>
      </div>
      <.button variant="neutral" size="xs" phx-click={@on_report} phx-value-fingerprint={@bucket.fingerprint}>
        Report this
      </.button>
    </div>
    """
  end
```

- [ ] **Step 2: Add `health_drill_in/1`** (stacked: Issues → Activity slot → collapsed Logs):

```elixir
  @doc "Inline stacked drill-in for one subsystem."
  attr :view, SubsystemView, required: true
  attr :buckets, :list, required: true, doc: "[Bucket.t()] for this subsystem"
  attr :on_report, :string, default: "report_incident"
  attr :on_close, :string, default: "close_subsystem"
  slot :activity, doc: "the subsystem's bespoke Activity widget"

  def health_drill_in(assigns) do
    ~H"""
    <section id="health-drill-in" class="glass-surface rounded-xl p-5 space-y-5">
      <header class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <.icon name={@view.glyph} class="size-5 text-base-content/65" />
          <h2 class="text-lg font-medium">{@view.label}</h2>
        </div>
        <.button variant="dismiss" size="sm" phx-click={@on_close}>Close</.button>
      </header>

      <div :if={@buckets != []} class="space-y-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Issues</h3>
        <.incident_row :for={bucket <- @buckets} bucket={bucket} on_report={@on_report} />
      </div>
      <p :if={@buckets == []} class="text-sm text-base-content/55">No issues for this subsystem.</p>

      <div :if={@activity != []} class="space-y-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Activity</h3>
        {render_slot(@activity)}
      </div>

      <details class="glass-inset rounded-lg">
        <summary class="cursor-pointer select-none px-3 py-2 text-sm text-base-content/60">
          View technical logs
        </summary>
        <div class="px-3 pb-3 text-xs font-mono text-base-content/50">
          <p :for={entry <- log_lines(@buckets)}>{entry}</p>
          <p :if={log_lines(@buckets) == []}>No recent log lines.</p>
        </div>
      </details>
    </section>
    """
  end

  @doc false
  def log_lines(buckets) do
    buckets
    |> Enum.flat_map(& &1.sample_entries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(20)
    |> Enum.map(fn %{timestamp: ts, message: msg} ->
      "#{Calendar.strftime(ts, "%H:%M:%S")}  #{msg}"
    end)
  end
```

- [ ] **Step 3: Write both stories** (`incident_row.story.exs`, `health_drill_in.story.exs`) using a `%Bucket{}` fixture and a `%SubsystemView{}` fixture (mirror the Task 5 story pattern; include an empty-issues variation and a with-issues variation for the drill-in).

```elixir
# storybook/health/incident_row.story.exs
defmodule MediaCentaurWeb.Storybook.Health.IncidentRow do
  use PhoenixStorybook.Story, :component
  alias MediaCentaur.ErrorReports.Bucket

  def function, do: &MediaCentaurWeb.HealthComponents.incident_row/1

  defp bucket(severity), do: %Bucket{
    fingerprint: "fp-#{severity}", component: :pipeline, normalized_message: "m",
    display_title: "Image downloads failing for 11 items", severity: severity, count: 11,
    first_seen: ~U[2026-06-01 14:02:00Z], last_seen: ~U[2026-06-01 15:00:00Z], sample_entries: []
  }

  def variations do
    [
      %Variation{id: :error, attributes: %{bucket: bucket(:error)}},
      %Variation{id: :warning, attributes: %{bucket: bucket(:warning)}}
    ]
  end
end
```

```elixir
# storybook/health/health_drill_in.story.exs
defmodule MediaCentaurWeb.Storybook.Health.HealthDrillIn do
  use PhoenixStorybook.Story, :component
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.SubsystemView

  def function, do: &MediaCentaurWeb.HealthComponents.health_drill_in/1

  defp view(state), do: %SubsystemView{component: :pipeline, label: "Import", glyph: "hero-arrow-down-tray", state: state, error_count: 1, warning_count: 0}
  defp bucket(), do: %Bucket{fingerprint: "fp", component: :pipeline, normalized_message: "m", display_title: "Image downloads failing for 11 items", severity: :error, count: 11, first_seen: ~U[2026-06-01 14:02:00Z], last_seen: ~U[2026-06-01 15:00:00Z], sample_entries: []}

  def variations do
    [
      %Variation{id: :with_issues, attributes: %{view: view(:error), buckets: [bucket()]}},
      %Variation{id: :healthy, attributes: %{view: view(:ok), buckets: []}}
    ]
  end
end
```

- [ ] **Step 4: Verify stories compile & render** — `mix test test/storybook_compile_test.exs test/storybook_render_test.exs` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/health_components.ex storybook/health/incident_row.story.exs storybook/health/health_drill_in.story.exs
git commit -m "feat(status): incident_row + health_drill_in components + stories"
```

---

### Task 7: Wire the board into StatusLive (assigns + handle_params + render)

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex` (assigns near line 90; add `handle_params/3`; render board at top of `render/1`; add `select_subsystem`/`close_subsystem` events; reuse existing `report_confirm`/modal for "Report this")

- [ ] **Step 1: Write a failing LiveView test** (`test/media_centaur_web/live/status_live/health_board_live_test.exs`):

```elixir
defmodule MediaCentaurWeb.StatusLive.HealthBoardLiveTest do
  use MediaCentaurWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "renders a tile per subsystem and opens a drill-in on ?subsystem=", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    assert has_element?(view, "#subsystem-tile-pipeline")
    assert has_element?(view, "#subsystem-tile-watcher")

    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    assert has_element?(view, "#health-drill-in", "Import")
  end

  test "clicking a tile patches to that subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    view |> element("#subsystem-tile-tmdb") |> render_click()
    assert_patch(view, ~p"/status?subsystem=tmdb")
    assert has_element?(view, "#health-drill-in", "Metadata")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails** — `mix test test/media_centaur_web/live/status_live/health_board_live_test.exs` → FAIL (no tiles/drill-in).

- [ ] **Step 3: Implement.** In `status_live.ex`:
  - Add `alias MediaCentaurWeb.StatusLive.HealthBoard` and `import MediaCentaurWeb.HealthComponents`.
  - In mount, assign `board: HealthBoard.build_board([])`, `selected_subsystem: nil`.
  - Where `error_buckets` is set (mount + the `{:buckets_changed, snapshot}` handler), also recompute `board: HealthBoard.build_board(snapshot)`.
  - Add `handle_params(%{"subsystem" => s}, _, socket)` that sets `selected_subsystem: String.to_existing_atom(s)` when `s` is in `board_subsystems()` (else `nil`); a no-subsystem clause sets `nil`.
  - Add events: `select_subsystem` → `push_patch(~p"/status?subsystem=#{component}")`; `close_subsystem` → `push_patch(~p"/status")`.
  - In `render/1`, above the existing sections, render the board grid (`<.subsystem_tile :for={v <- @board} view={v} selected={v.component == @selected_subsystem} />`) and, when `@selected_subsystem`, the `<.health_drill_in view={...} buckets={subsystem_buckets} on_report="report_confirm" />` using buckets grouped for the selected subsystem. Reuse the existing `report_confirm` event + report modal so "Report this" works end-to-end now.

- [ ] **Step 4: Run the test** → PASS. Then run the existing status tests: `mix test test/media_centaur_web/live/status_live` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live/health_board_live_test.exs
git commit -m "feat(status): render Subsystem Health Board + drill-in on /status"
```

---

### Task 8: Extend the page smoke test

**Files:**
- Modify: `test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 1: Add a smoke entry** mounting `/status?subsystem=pipeline` with fixture data: persist (via named `Capture`/`Store` per the campaign's test-env note) a warning + an error bucket for `:pipeline` so the board renders an unhealthy tile and the drill-in renders incident rows. Assert the mount returns a binary and the drill-in/tile elements exist.

- [ ] **Step 2: Run** `mix test test/media_centaur_web/page_smoke_test.exs` → PASS.

- [ ] **Step 3: Commit**

```bash
git add test/media_centaur_web/page_smoke_test.exs
git commit -m "test(status): smoke the health board + drill-in"
```

---

### Task 9: Full precommit

- [ ] **Step 1:** Run `mix precommit` and fix everything it reports (format/credo/boundaries/tests). Expected: green. Storybook compile/render covers the new stories (MC0009); MC0008 is satisfied by the `SubsystemView`/`Bucket` typed attrs.
- [ ] **Step 2: Commit** any formatting/credo fixes if needed.

---

## Self-review notes

- **Spec coverage (Milestone 1 slice):** board + tiles + health ✅ (T1–T7); stacked drill-in with Issues + collapsed Logs ✅ (T6–T7); incident-anchored "Report this" ✅ (wired to existing submit in T7); Activity slot present but empty (widgets are Milestone 3). Discovery badge, consent-modal rebuild, `:user`-origin, section removal, per-subsystem widgets, and the storage→watcher fold are **out of this plan** (roadmap below) — by design, to ship the surface non-destructively first.
- **Type consistency:** `SubsystemView` fields (`component/label/glyph/state/error_count/warning_count`) are used identically in T4–T7. `Bucket` fields match the explored struct. `tile_state/1` keys match `build_board/1` destructure.
- **Non-destructive:** existing operational sections remain until later milestones; nothing the user relies on is removed in Milestone 1.

## Roadmap (subsequent plans — not detailed here)

- **M2 — Reporting rebuild:** guided 3-step consent modal (4 promises → review & remove with manual redaction → consent gate + Send); wire Send to `ErrorReports.submit_report/2`; render `{:fallback, bundle}` as copyable text; remove `error_report.js`, the `error_reports:open_issue` push_event, and `IssueUrl.build/2` (keep `format_title`/`format_body`). Resolve the incident↔bucket submission mapping (`:log` incidents map to a bucket by fingerprint).
- **M3 — Per-subsystem Activity widgets:** a runtime widget registry mirroring the `IncidentContext` contributor IoC; Watcher widget (watch dirs + per-drive storage capacity — the storage fold + Storage-section removal); Import pipeline-stages widget; Metadata rate-limiter; Downloads client status. Remove the old standalone sections as each widget lands.
- **M4 — `:user`-origin + discovery badge:** add the `:user`-origin create path to `Store` (origin/`scope`/`user_description`/attach context); the quiet "something else seems wrong?" entry (global + per-entity); the Status-nav discovery badge with `diagnostics_seen_at` in `Settings`. Drop/relocate Recently Watched + Recent Changes.
- **Each milestone:** test-first, no network in tests, ships wiki/privacy docs for its user-visible surface.
