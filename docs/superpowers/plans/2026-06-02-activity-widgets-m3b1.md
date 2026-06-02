# Activity Widgets — M3b-1 (registry + Watcher widget) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a runtime registry that renders a per-subsystem Activity widget into the health-board drill-in, and use it to fold the watch-dirs/storage section into the Watcher subsystem's drill-in — proving the pattern with one real widget.

**Architecture (approach A):** A config-driven registry (`MediaCentaurWeb.HealthBoard.ActivityWidgets`) maps `component => &Module.fun/1`, mirroring the backend `ErrorReports.Contributors`. The drill-in's existing `:activity` slot (in `HealthComponents.health_drill_in/1`) is filled by `StatusLive` rendering the registered widget for the selected subsystem with a **data bundle** assembled from `StatusLive`'s already-loaded assigns (no render-time queries). A subsystem with no registered widget shows the health-only floor (no Activity section). The first widget — `watcher_widget/1` — is the existing `directories` content extracted into a public component.

**Tech Stack:** Elixir, Phoenix LiveView (function components + slots), Phoenix Storybook, ExUnit.

**Spec:** `docs/superpowers/specs/2026-06-01-phase4-health-board-ui.md` (P4-8 Activity widgets; P4-3 storage fold). Design fork resolved to **A** (function-component registry + data bundle).

---

## File Structure

- **Create** `lib/media_centaur_web/live/status_live/activity_widgets.ex` — the registry (`registry/0`, `widget_for/2`, `render/3`). Pure functions over config, registry injectable (mirrors `ErrorReports.Contributors`).
- **Modify** `lib/media_centaur_web/components/health_components.ex` — add the `watcher_widget/1` function component (the watch-dirs + per-drive storage-headroom content), typed attrs (MC0008) + story (MC0009). This is the existing `directories/1` content relocated to a public, storyable component.
- **Modify** `lib/media_centaur_web/live/status_live.ex` — move the `directories/1` markup (+ its private helpers `find_drive_for_dir/2` etc.) into `health_components.ex` as `watcher_widget/1`; remove the flat `directories` section from the render; fill the drill-in's `:activity` slot via `ActivityWidgets`.
- **Create** `storybook/status/watcher_widget.story.exs`.
- **Create** `config` entry: `config :media_centaur, :health_activity_widgets, %{...}` in `config/config.exs`.
- **Test:** `test/media_centaur_web/live/status_live/activity_widgets_test.exs`; extend the status page smoke for the watcher drill-in.

---

## Task 1: Activity-widget registry

**Files:**
- Create: `lib/media_centaur_web/live/status_live/activity_widgets.ex`
- Modify: `config/config.exs`
- Test: `test/media_centaur_web/live/status_live/activity_widgets_test.exs`

- [ ] **Step 1: Write the failing test.**

```elixir
defmodule MediaCentaurWeb.StatusLive.ActivityWidgetsTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.ActivityWidgets

  defp stub_widget(assigns), do: Phoenix.HTML.raw("<div data-stub>#{assigns.label}</div>")

  @registry %{watcher: {__MODULE__, :stub_widget}}

  describe "widget_for/2" do
    test "resolves a registered component" do
      assert ActivityWidgets.widget_for(:watcher, @registry) == {__MODULE__, :stub_widget}
    end

    test "returns nil for an unregistered component" do
      assert ActivityWidgets.widget_for(:tmdb, @registry) == nil
    end
  end

  describe "render/3" do
    test "renders the registered widget with the given assigns" do
      out = ActivityWidgets.render(:watcher, %{label: "hi"}, @registry)
      assert Phoenix.HTML.safe_to_string(out) =~ "data-stub"
      assert Phoenix.HTML.safe_to_string(out) =~ "hi"
    end

    test "returns nil for an unregistered component (the health-only floor)" do
      assert ActivityWidgets.render(:tmdb, %{}, @registry) == nil
    end
  end

  describe "registry/0" do
    test "reads the configured registry (watcher is registered in config.exs)" do
      assert {_mod, _fun} = ActivityWidgets.registry()[:watcher]
    end
  end
end
```

(`stub_widget/1` returns a raw safe value so the test doesn't need a real `~H` component; `render/3` just applies `fun` and returns whatever the function returns. The real widgets return `~H` `Rendered` structs, which `safe_to_string` also handles.)

- [ ] **Step 2: Run test to verify it fails.**

Run: `mix test test/media_centaur_web/live/status_live/activity_widgets_test.exs`
Expected: FAIL — module/functions undefined.

- [ ] **Step 3: Implement the registry.**

`lib/media_centaur_web/live/status_live/activity_widgets.ex`:

```elixir
defmodule MediaCentaurWeb.StatusLive.ActivityWidgets do
  @moduledoc """
  Runtime registry mapping a subsystem `component` to its Activity-widget
  function component, for the health-board drill-in.

  Mirrors `MediaCentaur.ErrorReports.Contributors`: the mapping is config data
  (`config :media_centaur, :health_activity_widgets, %{component => {module,
  function}}`), resolved at runtime, so the board renders a subsystem's widget
  without a compile-time dependency on it. A component with no registered widget
  renders the health-only floor (no Activity section).

  The widget is a plain function component; `render/3` applies it to a data
  bundle that `StatusLive` assembles from its already-loaded assigns (no
  render-time queries). Registry injectable for tests.
  """
  @type component :: atom()
  @type registry :: %{optional(component()) => {module(), atom()}}

  @doc "The configured `component => {module, function}` registry (defaults to `%{}`)."
  @spec registry() :: registry()
  def registry, do: Application.get_env(:media_centaur, :health_activity_widgets, %{})

  @doc "The `{module, function}` registered for `component`, or `nil`."
  @spec widget_for(component(), registry()) :: {module(), atom()} | nil
  def widget_for(component, registry \\ registry()), do: Map.get(registry, component)

  @doc """
  Renders `component`'s registered widget with `assigns`, or `nil` when none is
  registered (the health-only floor).
  """
  @spec render(component(), map(), registry()) :: Phoenix.LiveView.Rendered.t() | nil
  def render(component, assigns, registry \\ registry()) do
    case widget_for(component, registry) do
      {module, function} -> apply(module, function, [assigns])
      nil -> nil
    end
  end
end
```

- [ ] **Step 4: Register the watcher widget in config.**

In `config/config.exs`, near the `:diagnostics_contributors` config, add:

```elixir
# Health-board Activity widgets (observability Phase 4 M3b). component => {module, fun}.
config :media_centaur, :health_activity_widgets, %{
  watcher: {MediaCentaurWeb.HealthComponents, :watcher_widget}
}
```

(`watcher_widget/1` is created in Task 2 — config referencing a not-yet-existing function is fine at config-eval time; the registry resolves it at render time. The Task 1 `registry/0` test only checks the key exists.)

- [ ] **Step 5: Run tests to verify they pass.**

Run: `mix test test/media_centaur_web/live/status_live/activity_widgets_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add lib/media_centaur_web/live/status_live/activity_widgets.ex config/config.exs test/media_centaur_web/live/status_live/activity_widgets_test.exs
git commit -m "feat(status): Activity-widget runtime registry (mirrors Contributors)"
```

---

## Task 2: Extract the Watcher widget (the `directories` content) into a public component

**Files:**
- Modify: `lib/media_centaur_web/components/health_components.ex` (add `watcher_widget/1`)
- Modify: `lib/media_centaur_web/live/status_live.ex` (remove `directories/1` + its now-moved private helpers)
- Create: `storybook/status/watcher_widget.story.exs`

The existing `directories/1` function component in `status_live.ex` renders watch dirs + per-drive storage headroom + at-risk state — exactly the Watcher Activity widget. Move it to `HealthComponents` (public, storyable) as `watcher_widget/1`, keeping its markup, and move any private helpers it calls (e.g. `find_drive_for_dir/2`) alongside it.

- [ ] **Step 1: Identify the markup + helpers to move.**

Run: `grep -n "defp directories\|def directories\|find_drive_for_dir\|defp.*drive" lib/media_centaur_web/live/status_live.ex` and read `directories/1` end-to-end plus every private helper it calls. Note the attrs it needs: `dir_health`, `watcher_statuses`, `storage_drives`, `at_risk_summary`, `ttl_days`.

- [ ] **Step 2: Add `watcher_widget/1` to `health_components.ex`** with the SAME markup as `directories/1`, typed attrs (MC0008), and the moved helpers as private functions in `health_components.ex`:

```elixir
@doc "Watcher subsystem Activity widget: watch directories + per-drive storage headroom + at-risk state."
attr :dir_health, :list, required: true
attr :watcher_statuses, :list, required: true
attr :storage_drives, :list, required: true
attr :at_risk_summary, :map, required: true
attr :ttl_days, :integer, required: true

def watcher_widget(assigns) do
  ~H"""
  <%!-- paste the directories/1 markup here verbatim, referencing @dir_health,
        @watcher_statuses, @storage_drives, @at_risk_summary, @ttl_days --%>
  """
end

# + the moved private helpers (find_drive_for_dir/2, etc.) below it
```

Do NOT wrap it in the `<.link navigate="/settings...">` that the old flat section had — the widget renders inside the drill-in. Keep all the inner markup identical otherwise.

- [ ] **Step 3: Remove `directories/1` and its now-orphaned helpers from `status_live.ex`.** Grep to confirm no other caller of `directories/1` or the moved helpers remains in `status_live.ex`.

- [ ] **Step 4: Create the story** `storybook/status/watcher_widget.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.WatcherWidget do
  @moduledoc "Storybook coverage for the Watcher Activity widget (watch dirs + storage headroom)."
  use PhoenixStorybook.Story, :component
  def function, do: &MediaCentaurWeb.HealthComponents.watcher_widget/1

  def variations do
    [
      %PhoenixStorybook.Stories.Variation{
        id: :healthy,
        attributes: %{
          dir_health: [],
          watcher_statuses: [],
          storage_drives: [],
          at_risk_summary: %{},
          ttl_days: 30
        }
      }
    ]
  end
end
```

(If a richer non-empty variation is easy to construct from the structs the markup expects, add a `:populated` variation too — but `:healthy` empty-state must at least render.)

- [ ] **Step 5: Verify.**

Run: `mix compile --warnings-as-errors` (clean), `mix credo --strict lib/media_centaur_web/components/health_components.ex` (no issues — MC0008/MC0009), and `mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs` (the story renders).
NOTE: `status_live.ex` will not fully render until Task 3 wires the widget back in and removes the flat `directories` call — if `mix compile` flags an undefined `directories/1` call still in the status_live template, that's the Task 3 seam; complete Task 3 before the full page test. (Better: do Steps 2-3 here and the template change in Task 3 as one coherent edit if it's cleaner — but commit them separately.)

- [ ] **Step 6: Commit.**

```bash
git add lib/media_centaur_web/components/health_components.ex lib/media_centaur_web/live/status_live.ex storybook/status/watcher_widget.story.exs
git commit -m "feat(status): extract watcher_widget component (was the directories section)"
```

---

## Task 3: Wire the drill-in Activity slot + remove the flat directories section

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex`

- [ ] **Step 1: Fill the drill-in `:activity` slot from the registry.**

At the `<.health_drill_in ...>` invocation (around `status_live.ex:354`), provide the Activity slot conditionally — only when a widget is registered for the selected subsystem (so unregistered subsystems show the health-only floor):

```elixir
<.health_drill_in
  :if={@selected_subsystem}
  view={drill_in_view(@board, @selected_subsystem)}
  buckets={drill_in_buckets(@error_buckets, @selected_subsystem)}
  on_report="open_error_report_modal"
  on_close="close_subsystem"
>
  <:activity :if={ActivityWidgets.widget_for(@selected_subsystem)}>
    {ActivityWidgets.render(@selected_subsystem, activity_bundle(assigns))}
  </:activity>
</.health_drill_in>
```

Add `alias MediaCentaurWeb.StatusLive.ActivityWidgets` to the module aliases. Add a private `activity_bundle/1` that picks the assigns widgets need:

```elixir
# Data bundle handed to whichever Activity widget is registered for the
# selected subsystem. A superset of what any single widget reads; each widget
# declares (via attr) the keys it uses.
defp activity_bundle(assigns) do
  %{
    dir_health: assigns.dir_health,
    watcher_statuses: assigns.watcher_statuses,
    storage_drives: assigns.storage_drives,
    at_risk_summary: assigns.at_risk_summary,
    ttl_days: Config.get(:file_absence_ttl_days) || 30
  }
end
```

(`<:activity :if={...}>` — slot entries support `:if`. If this Phoenix version rejects `:if` on a slot, fall back to always providing the slot but having `ActivityWidgets.render/3` return `nil` for unregistered components AND change `health_drill_in`'s activity section guard from `@activity != []` to also treat a nil-rendering slot as empty — but try `:if` on the slot first; it's supported in recent LiveView.)

- [ ] **Step 2: Remove the flat `directories` section.** Delete the `<.link navigate="/settings?section=configuration"> <.directories .../> </.link>` block from the render (the watcher/storage content now lives in the Watcher drill-in). Keep the `dir_health`/`watcher_statuses`/`storage_drives`/`at_risk_summary` assigns + their async loads — `activity_bundle/1` still needs them.

- [ ] **Step 3: Verify.**

Run: `mix compile --warnings-as-errors` (clean — no leftover `directories/1` reference), and `mix test test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/live/status_live/` (page mounts; drilling into `:watcher` renders the widget).

- [ ] **Step 4: Extend the status smoke to cover the watcher drill-in.** In the status page smoke (or `health_board`/status_live test), add an assertion that navigating to `/status?subsystem=watcher` renders the watcher widget content (e.g. a stable string from the widget markup, or `[data-testid=...]` if you add one to `watcher_widget`). Seed enough (a watch dir / drive) so the widget's non-empty branch renders. (Adding a `data-testid="watcher-widget"` to the widget's root is the cleanest anchor — do that in Task 2's component if helpful.)

- [ ] **Step 5: Commit.**

```bash
git add lib/media_centaur_web/live/status_live.ex test/...
git commit -m "feat(status): render registered Activity widget in the drill-in; fold the directories section into Watcher"
```

---

## Task 4: Full gate + campaign reconcile

- [ ] **Step 1: `mix precommit`** — exit 0 (format, Credo incl. MC0008/MC0009, boundaries, sobelow, deps.audit, full Elixir + JS). The known `store_test`/acquisition parallelism flakes are unrelated — if one appears, confirm it passes in isolation per `campaigns/observability-dashboard.md`. Fix anything genuinely caused by this change.

- [ ] **Step 2: Reconcile the campaign.** In `campaigns/observability-dashboard.md`, mark M3b-1 done (registry + Watcher widget; directories folded), and note the remaining M3b widgets (pipeline/tmdb/playback) as the phased follow-up. Bump `last_updated`.

- [ ] **Step 3: Commit.** `git add campaigns/observability-dashboard.md && git commit -m "docs(campaign): M3b-1 (activity registry + watcher widget) shipped"`

---

## Notes for the implementer

- **Dynamic render:** `apply(module, function, [assigns])` on a function component returns a `%Phoenix.LiveView.Rendered{}`; interpolating it with `{...}` in the parent `~H` works. The `assigns` map need not carry `__changed__` — `~H` treats a plain map as fully-changed (fine for an infrequently-rendered drill-in).
- **Boundary cleanliness:** the registry holds `{module, fun}` as config DATA — `StatusLive`/`ActivityWidgets` never name a widget module at compile time. New widgets register in config + implement a function component; no edit to the registry or the drill-in.
- **No render-time queries:** the widget reads ONLY from the `activity_bundle/1` map (assigns already loaded async in mount). Don't fetch in the widget.
- Match the design system (glass, daisyUI, color only for health) — the moved `directories` markup already complies; keep it.
