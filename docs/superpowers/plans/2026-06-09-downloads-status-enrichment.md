# Downloads Status Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Downloads (acquisition) status tile its first Activity widget — a consolidated connectivity-health band (download client + Prowlarr) plus a throughput stat-figure band — without re-listing the live queue/pursuits that already live on `/download`.

**Architecture:** A new pure aggregate (`Acquisition.Pursuits.Throughput`) counts pursuits by terminal/in-flight bucket. `StatusLive` assembles an `acquisition_activity` bundle from cheap cached reads (`Capabilities`, `QueueMonitor.state` → `QueueStatus.derive`, `Throughput.stats`) and hands it to a new `acquisition_widget/1`, registered in the `:health_activity_widgets` map. The widget maps connectivity grades → coloured status rows and renders throughput figures; color is reserved to the connectivity band.

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, daisyUI/Tailwind, ExUnit (DataCase + LiveViewTest).

---

## Background facts (verified — do not re-derive)

- `acquisition` is NOT in `config/config.exs` `:health_activity_widgets`, so its drill-in renders the health-only floor. Adding it makes `ActivityWidgets.render(@selected_subsystem, activity_bundle(assigns))` (status_live.ex:582) render the widget.
- `MediaCentaur.Downloads.QueueStatus.derive(%QueueState{}, cadence_ms, now \\ DateTime.utc_now())` → one of: `:initializing | :live | {:lagging, age_ms} | {:offline, since} | :auth_failed | :not_configured`.
- `MediaCentaur.Downloads.QueueMonitor.state/0` → `%QueueState{last_successful_poll_at, last_error, ...}` (reads `:persistent_term`, no GenServer call; returns empty `%QueueState{}` before first poll).
- `MediaCentaur.Capabilities.{prowlarr_ready?,download_client_ready?,acquisition_ready?}/0` — cached boolean flags. `Capabilities.subscribe_changes/0` subscribes to `:capabilities_changed`.
- `MediaCentaur.Acquisition.subscribe_queue/0` → `acquisition:queue` topic; `QueueMonitor` broadcasts `{:queue_state, %QueueState{}}` there.
- Pursuit schema: table `acquisition_pursuits`, `field :state, :string, default: "active"`. `MediaCentaur.Acquisition.Pursuits.State.bucket/1` maps a state string → `:in_flight | :terminal_success | :terminal_failure` (in_flight=`"active"`, success=`"satisfied"`, failure=`"exhausted"|"cancelled"`; raises on unknown).
- `MediaCentaur.Acquisition.Pursuits.Pursuit.create_changeset/1` casts recipe fields (NOT `:state`, which defaults to `"active"`); validates required recipe fields (for `recipe_type: "tmdb"` → `tmdb_id`, `tmdb_type`).
- `MediaCentaur.Acquisition` carries `use Boundary, exports: [...]` (lib/media_centaur/acquisition.ex) — new public modules must be added to that list.
- Settings section id for client/Prowlarr config is `"services"` (`settings_live.ex` `section_content(%{active_section: "services"})`). `<.settings_link section="services">…</.settings_link>` is the affordance (same component the TMDB widget uses with `section="tmdb"`).
- Playback widget idioms to reuse verbatim: stat figure = `<div class="text-2xl font-semibold tabular-nums">{v}</div>` over `<div class="text-xs uppercase tracking-wider text-base-content/50">{label}</div>`; status dot = `<span class={["size-2 rounded-full shrink-0", dot]}></span>`; card = `card glass-surface border-l-3`.
- Status tests use the `live_async!/2` helper and `~p"/status?subsystem=<atom>"` (the acquisition drill-in is `?subsystem=acquisition`).

---

## File Structure

- **Create:** `lib/media_centaur/acquisition/pursuits/throughput.ex` — pursuit count aggregate (one responsibility: bucket counts + success rate).
- **Create:** `test/media_centaur/acquisition/pursuits/throughput_test.exs`
- **Create:** `storybook/status/acquisition_widget.story.exs`
- **Modify:** `lib/media_centaur/acquisition.ex` — export `Pursuits.Throughput`.
- **Modify:** `lib/media_centaur_web/components/activity_widget_components.ex` — new `acquisition_widget/1` + private helpers.
- **Modify:** `config/config.exs` — register the widget.
- **Modify:** `lib/media_centaur_web/live/status_live.ex` — subscribe, assemble bundle, handle_info, add to `activity_bundle/1`.
- **Modify:** `test/media_centaur_web/live/status_live_test.exs` — wiring assertions.

---

## Task 1: Throughput aggregate

**Files:**
- Create: `lib/media_centaur/acquisition/pursuits/throughput.ex`
- Test: `test/media_centaur/acquisition/pursuits/throughput_test.exs`
- Modify: `lib/media_centaur/acquisition.ex`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Acquisition.Pursuits.ThroughputTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Pursuits.Throughput
  alias MediaCentaur.Repo

  defp insert_pursuit(state) do
    {:ok, pursuit} =
      %{
        recipe_type: "tmdb",
        tmdb_id: System.unique_integer([:positive]) |> Integer.to_string(),
        tmdb_type: "movie",
        title: "Movie A",
        origin: "auto"
      }
      |> Pursuit.create_changeset()
      |> Repo.insert()

    if state == "active" do
      pursuit
    else
      pursuit |> Ecto.Changeset.change(state: state) |> Repo.update!()
    end
  end

  describe "empty/0" do
    test "zeroed snapshot for the disconnected mount" do
      assert Throughput.empty() == %{acquired: 0, failed: 0, active: 0, success_rate: nil}
    end
  end

  describe "stats/0" do
    test "no pursuits mirrors empty/0" do
      assert Throughput.stats() == Throughput.empty()
    end

    test "buckets states and computes whole-percent success rate" do
      Enum.each(["satisfied", "satisfied", "satisfied"], &insert_pursuit/1)
      insert_pursuit("exhausted")
      insert_pursuit("cancelled")
      insert_pursuit("active")

      # 3 success, 2 failure => 3/5 = 60%; 1 active.
      assert Throughput.stats() == %{acquired: 3, failed: 2, active: 1, success_rate: 60}
    end

    test "success_rate is nil when there are no terminal pursuits" do
      insert_pursuit("active")
      assert %{acquired: 0, failed: 0, active: 1, success_rate: nil} = Throughput.stats()
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/acquisition/pursuits/throughput_test.exs`
Expected: FAIL — `Throughput` undefined.

- [ ] **Step 3: Implement the aggregate**

```elixir
defmodule MediaCentaur.Acquisition.Pursuits.Throughput do
  @moduledoc """
  Lifetime pursuit-outcome aggregate for the Downloads status tile: how many
  acquisitions have succeeded, failed, and are in flight, plus a success rate.
  Pure read-shaping over `acquisition_pursuits` — one grouped count, folded
  through `State.bucket/1`. `StatusLive` calls `stats/0` on mount and on
  acquisition refresh; `empty/0` serves the disconnected mount.

  ## Shape

      %{acquired: non_neg_integer(), failed: non_neg_integer(),
        active: non_neg_integer(), success_rate: 0..100 | nil}

  `success_rate` is `nil` when no pursuit has reached a terminal state.
  """
  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Repo

  @spec empty() :: map()
  def empty, do: %{acquired: 0, failed: 0, active: 0, success_rate: nil}

  @spec stats() :: map()
  def stats do
    counts =
      from(p in "acquisition_pursuits", group_by: p.state, select: {p.state, count(p.id)})
      |> Repo.all()
      |> Enum.reduce(%{acquired: 0, failed: 0, active: 0}, fn {state, n}, acc ->
        case State.bucket(state) do
          :terminal_success -> %{acc | acquired: acc.acquired + n}
          :terminal_failure -> %{acc | failed: acc.failed + n}
          :in_flight -> %{acc | active: acc.active + n}
        end
      end)

    Map.put(counts, :success_rate, success_rate(counts.acquired, counts.failed))
  end

  defp success_rate(0, 0), do: nil
  defp success_rate(acquired, failed), do: round(100 * acquired / (acquired + failed))
end
```

- [ ] **Step 4: Export from the Acquisition boundary**

In `lib/media_centaur/acquisition.ex`, add `Pursuits.Throughput` to the `exports:` list (keep alphabetical near the other `Pursuits.*` entries):

```elixir
      Pursuits,
      Pursuits.Commands.Cancel,
```

becomes

```elixir
      Pursuits,
      Pursuits.Throughput,
      Pursuits.Commands.Cancel,
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/media_centaur/acquisition/pursuits/throughput_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/acquisition/pursuits/throughput.ex test/media_centaur/acquisition/pursuits/throughput_test.exs lib/media_centaur/acquisition.ex
git commit -m "feat(acquisition): pursuit throughput aggregate (acquired/failed/active/success-rate)"
```

---

## Task 2: acquisition_widget component + story

The widget is built and verified in isolation via storybook. It is NOT yet registered (Task 3), so no live status page renders it — no existing test breaks.

**Files:**
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex`
- Create: `storybook/status/acquisition_widget.story.exs`

- [ ] **Step 1: Add the attr + widget function**

Add near the other widget functions in `activity_widget_components.ex` (e.g. after `self_update_widget/1`). The module already `import`s `MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]` and has `<.settings_link>` and `<.icon>` in scope.

```elixir
  @doc "Downloads (acquisition) Activity widget: connectivity health + throughput figures."
  attr :acquisition_activity, :map,
    required: true,
    doc:
      "bundle from StatusLive: %{configured?, client_grade, last_poll_at, prowlarr_ready?, throughput}"

  def acquisition_widget(assigns) do
    client = acq_client_status(assigns.acquisition_activity.client_grade, assigns.acquisition_activity.last_poll_at)
    prowlarr = acq_prowlarr_status(assigns.acquisition_activity.prowlarr_ready?)
    tone = worst_tone([client.tone, prowlarr.tone])

    assigns =
      assigns
      |> Map.put(:client, client)
      |> Map.put(:prowlarr, prowlarr)
      |> Map.put(:tone, tone)

    ~H"""
    <div
      class={["card glass-surface border-l-3", acq_border_class(@tone)]}
      data-testid="acquisition-widget"
    >
      <div class="card-body">
        <%!-- Unconfigured: single settings affordance, nothing else --%>
        <p :if={!@acquisition_activity.configured?} class="text-sm text-base-content/60">
          <.settings_link section="services">
            Acquisition isn't set up — configure a download client and Prowlarr in Settings.
          </.settings_link>
        </p>

        <div :if={@acquisition_activity.configured?}>
          <%!-- Band 1 · Connectivity (the only coloured band) --%>
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
            Connectivity
          </h3>
          <div data-component="acquisition-connectivity" class="mt-2 space-y-2">
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/70 w-32 shrink-0">Download client</span>
              <span class={["size-2 rounded-full shrink-0", tone_chrome(@client.tone).dot]}></span>
              <span class={tone_chrome(@client.tone).text}>{@client.label}</span>
              <span :if={@client.detail} class="ml-auto text-xs text-base-content/40 tabular-nums">
                {@client.detail}
              </span>
            </div>
            <div class="flex items-center gap-2 text-sm">
              <span class="text-base-content/70 w-32 shrink-0">Prowlarr indexers</span>
              <span class={["size-2 rounded-full shrink-0", tone_chrome(@prowlarr.tone).dot]}></span>
              <span class={tone_chrome(@prowlarr.tone).text}>{@prowlarr.label}</span>
            </div>
          </div>

          <%!-- Band 2 · Throughput stat figures --%>
          <div
            data-component="acquisition-throughput"
            class="mt-4 pt-4 border-t border-base-content/10 grid grid-cols-3 gap-3"
          >
            <div>
              <div class="text-2xl font-semibold tabular-nums">
                {@acquisition_activity.throughput.acquired}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/50">Acquired</div>
            </div>
            <div>
              <div class="text-2xl font-semibold tabular-nums">
                {acq_rate_label(@acquisition_activity.throughput.success_rate)}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/50">Success</div>
            </div>
            <.link navigate={~p"/download"} class="block group">
              <div class="text-2xl font-semibold tabular-nums group-hover:text-primary">
                {@acquisition_activity.throughput.active}
              </div>
              <div class="text-xs uppercase tracking-wider text-base-content/50 group-hover:text-primary">
                Active
              </div>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 2: Add the private helpers**

Place after the playback helpers (near `format_recent_title/1`). `time_ago/1` is already imported.

```elixir
  # --- Acquisition widget helpers ---

  defp tone_chrome(:ok), do: %{dot: "bg-success", text: "text-success"}
  defp tone_chrome(:warn), do: %{dot: "bg-warning", text: "text-warning"}
  defp tone_chrome(:error), do: %{dot: "bg-error", text: "text-error"}
  defp tone_chrome(:muted), do: %{dot: "bg-base-content/30", text: "text-base-content/50"}

  defp acq_client_status(:live, last), do: %{label: "Connected", tone: :ok, detail: poll_suffix(last)}
  defp acq_client_status(:initializing, _last), do: %{label: "Connecting…", tone: :muted, detail: nil}

  defp acq_client_status({:lagging, _age}, last),
    do: %{label: "Lagging", tone: :warn, detail: poll_suffix(last)}

  defp acq_client_status({:offline, _since}, _last), do: %{label: "Offline", tone: :error, detail: nil}
  defp acq_client_status(:auth_failed, _last), do: %{label: "Auth failed", tone: :error, detail: nil}

  defp acq_client_status(:not_configured, _last),
    do: %{label: "Not configured", tone: :muted, detail: nil}

  defp acq_prowlarr_status(true), do: %{label: "Reachable", tone: :ok}
  defp acq_prowlarr_status(false), do: %{label: "Unreachable", tone: :error}

  defp poll_suffix(nil), do: nil
  defp poll_suffix(%DateTime{} = at), do: "polled #{time_ago(at)}"

  defp acq_rate_label(nil), do: "—"
  defp acq_rate_label(rate), do: "#{rate}%"

  defp worst_tone(tones) do
    cond do
      :error in tones -> :error
      :warn in tones -> :warn
      true -> :ok
    end
  end

  defp acq_border_class(:error), do: "border-error/60"
  defp acq_border_class(:warn), do: "border-warning/60"
  defp acq_border_class(_), do: "border-base-content/10"
```

- [ ] **Step 3: Write the story**

Create `storybook/status/acquisition_widget.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.AcquisitionWidget do
  @moduledoc "Storybook coverage for the Downloads Activity widget (connectivity + throughput)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.acquisition_widget/1

  def render_source, do: :function

  def variations do
    throughput = %{acquired: 142, failed: 18, active: 3, success_rate: 89}

    [
      %Variation{
        id: :healthy,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            client_grade: :live,
            last_poll_at: ~U[2026-06-09 12:00:00.000000Z],
            prowlarr_ready?: true,
            throughput: throughput
          }
        }
      },
      %Variation{
        id: :client_offline,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            client_grade: {:offline, ~U[2026-06-09 11:30:00.000000Z]},
            last_poll_at: ~U[2026-06-09 11:30:00.000000Z],
            prowlarr_ready?: true,
            throughput: throughput
          }
        }
      },
      %Variation{
        id: :prowlarr_unreachable,
        attributes: %{
          acquisition_activity: %{
            configured?: true,
            client_grade: :live,
            last_poll_at: ~U[2026-06-09 12:00:00.000000Z],
            prowlarr_ready?: false,
            throughput: %{acquired: 0, failed: 0, active: 0, success_rate: nil}
          }
        }
      },
      %Variation{
        id: :unconfigured,
        attributes: %{
          acquisition_activity: %{
            configured?: false,
            client_grade: :not_configured,
            last_poll_at: nil,
            prowlarr_ready?: false,
            throughput: %{acquired: 0, failed: 0, active: 0, success_rate: nil}
          }
        }
      }
    ]
  end
end
```

- [ ] **Step 4: Compile + render the story**

Run: `mix compile --warnings-as-errors`
Run: `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS — the acquisition story compiles and all 4 variations render.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/activity_widget_components.ex storybook/status/acquisition_widget.story.exs
git commit -m "feat(status): downloads activity widget — connectivity health + throughput"
```

---

## Task 3: Register + wire into StatusLive

**Files:**
- Modify: `config/config.exs`
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Test: `test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/status_live_test.exs` a `describe "downloads activity widget"`:

```elixir
  describe "downloads activity widget" do
    test "acquisition drill-in renders the connectivity + throughput widget", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/status?subsystem=acquisition")

      assert html =~ ~s(data-testid="acquisition-widget")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: the new test FAILS — widget not registered, so the drill-in renders only the health floor (no `acquisition-widget` testid). Pre-existing tests in the file stay green.

- [ ] **Step 3: Register the widget**

In `config/config.exs`, add the acquisition entry to `:health_activity_widgets`:

```elixir
config :media_centaur, :health_activity_widgets, %{
  library: {MediaCentaurWeb.ActivityWidgetComponents, :library_widget},
  watcher: {MediaCentaurWeb.ActivityWidgetComponents, :watcher_widget},
  pipeline: {MediaCentaurWeb.ActivityWidgetComponents, :pipeline_widget},
  tmdb: {MediaCentaurWeb.ActivityWidgetComponents, :tmdb_widget},
  playback: {MediaCentaurWeb.ActivityWidgetComponents, :playback_widget},
  acquisition: {MediaCentaurWeb.ActivityWidgetComponents, :acquisition_widget},
  self_update: {MediaCentaurWeb.ActivityWidgetComponents, :self_update_widget}
}
```

- [ ] **Step 4: Add aliases + cadence constant in StatusLive**

In `lib/media_centaur_web/live/status_live.ex`, add to the alias block (near the other `alias MediaCentaur.*` lines):

```elixir
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Pursuits.Throughput
  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Downloads.QueueStatus
```

> If any of these aliases already exists in the module, skip that line (don't duplicate). Add the cadence module attribute near the top of the module body (after the existing `@`-attributes):

```elixir
  # Mirrors AcquisitionLive's watched cadence — the rhythm QueueMonitor polls at
  # when a LiveView is subscribed; QueueStatus.derive grades freshness in multiples of it.
  @queue_cadence_ms 1_500
```

- [ ] **Step 5: Subscribe + assign on mount**

In the connected-mount branch (alongside the other `subscribe` calls, ~status_live.ex:34-40), add:

```elixir
        Acquisition.subscribe_queue()
        Capabilities.subscribe_changes()
```

In the connected-mount assign chain (near `assign(playback_activity: ...)`), add:

```elixir
        |> assign(acquisition_activity: build_acquisition_activity())
```

In the disconnected-mount branch (near `assign(playback_activity: PlaybackActivity.empty())`), add:

```elixir
        |> assign(acquisition_activity: empty_acquisition_activity())
```

- [ ] **Step 6: Add the bundle builders**

Add as private functions (group with the other `build_*` helpers, e.g. near `build_playback_state/0`):

```elixir
  defp build_acquisition_activity do
    state = QueueMonitor.state()

    %{
      configured?: Capabilities.download_client_ready?() or Capabilities.prowlarr_ready?(),
      client_grade: QueueStatus.derive(state, @queue_cadence_ms),
      last_poll_at: state.last_successful_poll_at,
      prowlarr_ready?: Capabilities.prowlarr_ready?(),
      throughput: Throughput.stats()
    }
  end

  defp empty_acquisition_activity do
    %{
      configured?: false,
      client_grade: :initializing,
      last_poll_at: nil,
      prowlarr_ready?: false,
      throughput: Throughput.empty()
    }
  end
```

- [ ] **Step 7: Refresh on queue / capability changes**

Add `handle_info/2` clauses above the catch-all `handle_info(_msg, socket)`:

```elixir
  @impl true
  def handle_info({:queue_state, _state}, socket) do
    {:noreply, assign(socket, acquisition_activity: build_acquisition_activity())}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply, assign(socket, acquisition_activity: build_acquisition_activity())}
  end
```

> If the module already handles `:capabilities_changed` for another reason, merge the acquisition re-assemble into that existing clause instead of adding a duplicate (a duplicate function clause for the same pattern is a compile error).

- [ ] **Step 8: Add to the render bundle**

In `activity_bundle/1`, in the section near `playback_activity: assigns.playback_activity,`, add:

```elixir
      acquisition_activity: assigns.acquisition_activity,
```

- [ ] **Step 9: Run the wiring test (now green)**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS — the acquisition drill-in renders `data-testid="acquisition-widget"`, and all pre-existing tests stay green.

- [ ] **Step 10: Compile clean**

Run: `mix compile --warnings-as-errors`
Expected: no warnings, no boundary violations (web → Acquisition/Downloads/Capabilities are already permitted; `Throughput` is now exported).

- [ ] **Step 11: Commit**

```bash
git add config/config.exs lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): register + wire the downloads activity widget in StatusLive"
```

---

## Task 4: Full precommit + wiki sync

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: format, Credo (incl. MC0009 — the acquisition story satisfies it), boundaries, sobelow/deps.audit, full suite all green.

> If Credo flags "Nested modules could be aliased" for the new `MediaCentaur.*` references in status_live.ex, add the alias (Task 3 Step 4 already does) and use the short name. If the suite hits the known intermittent SQLite "Database busy" flake, re-run the affected file with `--repeat-until-failure 50` to confirm it's pre-existing.

- [ ] **Step 2: Self-capture the rendered widget (don't ask the user)**

Run: `~/scripts/agents/viz-screenshot --url 'http://localhost:1080/status?subsystem=acquisition' --viewport 1700x1250 --wait-ms 3000 -o /tmp/dl-now.png`
Read `/tmp/dl-now.png` and sanity-check the layout (connectivity rows readable, stat figures aligned, no doubled "Downloads"/"Playback"-style title). Iterate on the widget if it reads poorly. (Per auto-memory `reference-responsive-ui-screenshot`.)

- [ ] **Step 3: Wiki sync**

The Downloads status tile now shows connectivity health (client + Prowlarr) and throughput stats. Update the wiki Status/observability page.

```sh
cd ~/src/media-centaur/media-centaur.wiki
# note the Downloads tile now surfaces download-client + Prowlarr reachability and lifetime throughput.
git add -A
git commit -m "wiki: downloads status tile now shows connectivity health + throughput"
git push
```

> If the exact wiki page is unclear, grep for "status"/"health"; if none exists, record as a follow-up rather than blocking.

---

## Notes / explicit scope cuts

- **No active-downloads list, no pursuit-in-flight rows** — those stay on `/download` (auto-memory `feedback-status-widgets-no-rehash`). "Active" is a single count that links there.
- **No download-byte throughput** — declined (no cheap data source).
- Color reserved to the connectivity band; throughput figures are neutral.
- Refresh is event-driven on `{:queue_state, _}` (frequent — every poll cycle) + `:capabilities_changed`; throughput is a lifetime aggregate that doesn't need sub-second freshness, so a queue-cycle refresh is sufficient.
- Spec: `docs/superpowers/specs/2026-06-09-downloads-status-enrichment-design.md`. Persona: auto-memory `project-status-page-persona`.
```
