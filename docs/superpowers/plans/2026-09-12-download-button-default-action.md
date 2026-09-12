# Download Button Default Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Download button on a title the library does not own performs the person's default planning mode (manually select release, or auto-select best release), offers the other in its menu, and holds the series scope in a select beside it — built on one reusable glass-menu component family the library sort control also adopts.

**Architecture:** A `Settings.Preferences.PlanningMode` preference names the default planning mode; the title detail view-model carries it; `TitleDetailHost.start_download/4` maps a planning mode to an approval policy and either hands the plan to the supervised door (auto-select) or plans synchronously under `start_async` and opens the plan board on Incoming (choose releases). `MediaCentaurWeb.Components.GlassMenu` provides `menu_list`, `split_button` and `menu_select` on the existing `.glass-menu*` CSS; two input-system contracts make a menu a zone inside a zone that BACK closes on the way out. Spec: `docs/superpowers/specs/2026-09-12-download-button-default-action-design.md`.

**Tech Stack:** Elixir/Phoenix LiveView, Phoenix Storybook (MC0009), the JS input system under `assets/js/input` (bun tests), ExUnit with `MediaCentaurWeb.ConnCase`.

---

## Conventions for every task

- **Never run `mix` directly.** Use `~/scripts/agents/agent-mix` (`agent-mix test path/to/test.exs`, `agent-mix precommit`). Bare `mix` compiles into the dev server's `_build` and takes the daily driver down.
- **Bun tests** run from the repo root: `bun test assets/js/input/core/__tests__/dom_adapter.test.js`.
- **Load the skills** before writing code in a task: `automated-testing` (always), plus `phoenix-thinking` for LiveView/host tasks, `storybook` and `user-interface` for component tasks, `input-system` for tasks 3, 4, 7 and 10, `writing-copy` for any user-facing words.
- **Commits** go straight to `main` (no branches). Every commit message ends with a blank line and then `Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV`. No `Co-Authored-By`.
- **No real titles** in tests or stories: `Sample Movie`, `Sample Show`.
- **Zero warnings.** Unused aliases and attrs are failures.

## File map

| File | Responsibility |
|---|---|
| `lib/media_centaur/acquisition/plans.ex` | `create_title_plan/2` (sync door); `plan_title/2` becomes its supervised wrapper |
| `lib/media_centaur/settings/preferences/planning_mode.ex` | the preference: key, parse, default, `other/1`, `set/1` |
| `lib/media_centaur/settings/preferences.ex` | export `PlanningMode` |
| `assets/js/input/core/dom_adapter.js` | nearest-zone item ownership; `getZoneDismissEvent/1` |
| `assets/js/input/core/orchestrator.js` | push a zone's dismiss event when BACK leaves it |
| `assets/js/input/config.js` | `back` edge on `title_detail_menu`; `library_sort_menu` zone |
| `lib/media_centaur_web/components/glass_menu.ex` | `menu_list/1`, `split_button/1`, `menu_select/1` |
| `storybook/core_components/{menu_list,split_button,menu_select}.story.exs` | their stories |
| `assets/css/app.css` | `.glass-menu-trigger[aria-expanded="true"]` replaces the captures-keys hook |
| `lib/media_centaur_web/components/title/detail.ex`, `logic.ex` | `planning_mode` on the view-model; labels |
| `lib/media_centaur_web/components/title/detail_modal.ex` | the Download control: split button + scope select |
| `lib/media_centaur_web/live/title_detail_host.ex` | menu state, scope, `start_download/4`, the async, `open_plan_board/2` callback |
| `lib/media_centaur_web/live/discovery_live.ex`, `incoming_live.ex` | `open_plan_board/2`; feed row Download via the host |
| `lib/media_centaur_web/live/settings_live/acquisition_section.ex`, `settings_live.ex` | the "Download button" card and its handler |
| `lib/media_centaur_web/components/library_cards.ex`, `lib/media_centaur_web/live/library_live.ex` | sort control on `menu_select`; keyboard model removed |
| docs, wiki | listed in Task 11 |

---

### Task 1: `Plans.create_title_plan/2` — the synchronous door

**Files:**
- Modify: `lib/media_centaur/acquisition/plans.ex` (the `plan_title/2` block, ~lines 123-178)
- Modify: `test/support/tmdb_stubs.ex` (add one stub)
- Test: `test/media_centaur/acquisition/plans_test.exs`

- [ ] **Step 1: Add an unaired-series stub to `test/support/tmdb_stubs.ex`**, right after `stub_series_universe_for_targeting/0`:

```elixir
  @doc """
  A series whose every episode is still to come — nothing pickable, so a
  download scope over it is empty. TMDB id 246_811, one season.
  """
  def stub_unaired_series_for_targeting do
    stub_routes([
      {"/tv/246811/season/1",
       season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2199-01-01"},
           %{"episode_number" => 2, "name" => "Second", "air_date" => "2199-01-08"}
         ]
       })},
      {"/tv/246811",
       tv_detail(%{
         "id" => 246_811,
         "name" => "Unaired Show",
         "original_name" => "Unaired Show",
         "origin_country" => ["US"],
         "seasons" => [%{"season_number" => 1, "episode_count" => 2}]
       })}
    ])
  end
```

- [ ] **Step 2: Write the failing tests.** Append a new `describe` to `test/media_centaur/acquisition/plans_test.exs` before the final `end` (the `movie_title/0` and `show_title/0` helpers defined inside the `plan_title/2` describe are module functions and are reused here):

```elixir
  describe "create_title_plan/2" do
    alias MediaCentaur.Acquisition.Plans.Plan
    alias MediaCentaur.TMDB.Title

    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "a movie returns its plan, stamped with the policy" do
      assert {:ok, %Plan{} = plan} = Plans.create_title_plan(movie_title(), approval_policy: "automatic")

      assert plan.tmdb_type == "movie"
      assert plan.tmdb_id == "246813"
      assert plan.approval_policy == "automatic"
      assert plan.origin == "manual"
      assert [%Plan{id: id}] = Plans.list_drafts()
      assert id == plan.id
    end

    test "the policy defaults to review" do
      assert {:ok, %Plan{approval_policy: "review"}} = Plans.create_title_plan(movie_title())
    end

    test "a series with :first_season plans season 1's pickable episodes" do
      MediaCentaur.TmdbStubs.stub_series_universe_for_targeting()

      assert {:ok, %Plan{} = plan} =
               Plans.create_title_plan(show_title(), scope: :first_season, approval_policy: "review")

      assert plan.tmdb_type == "tv"
      assert plan.approval_policy == "review"

      assert Enum.map(Plans.units_for(plan.id), &{&1.season_number, &1.episode_number}) ==
               [{1, 1}, {1, 2}]
    end

    test "a series with :everything plans every pickable episode" do
      MediaCentaur.TmdbStubs.stub_series_universe_for_targeting()

      assert {:ok, %Plan{} = plan} = Plans.create_title_plan(show_title(), scope: :everything)
      assert length(Plans.units_for(plan.id)) == 3
    end

    test "a series with nothing pickable is :nothing_to_plan and leaves no plan" do
      MediaCentaur.TmdbStubs.stub_unaired_series_for_targeting()

      unaired =
        Title.new!(%{tmdb_id: 246_811, media_type: :tv_series, name: "Unaired Show", year: "2199"})

      assert {:error, :nothing_to_plan} = Plans.create_title_plan(unaired, scope: :first_season)
      assert Plans.list_drafts() == []
    end

    test "a TMDB failure returns the error and leaves no plan" do
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert {:error, _reason} = Plans.create_title_plan(show_title(), scope: :first_season)
      assert Plans.list_drafts() == []
    end
  end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/plans_test.exs`
Expected: the new describe fails with `UndefinedFunctionError: function MediaCentaur.Acquisition.Plans.create_title_plan/2 is undefined`.

- [ ] **Step 4: Implement.** In `lib/media_centaur/acquisition/plans.ex`, replace the `plan_title/2` `@doc`, function and its two `do_plan_title/3` clauses with:

```elixir
  @doc """
  Plans a TMDB title from its snapshot alone, in the background (spec
  2026-09-05 §17): the door the auto-select download action uses, where
  nobody waits for the plan. Runs `create_title_plan/2` on the context
  task supervisor — the work must outlive the calling LiveView
  (ADR-049) — and returns as soon as it is queued; the plan row
  broadcasts on `acquisition:updates` when it exists. Movies take the
  same path so the contract is one shape.

  Options are `create_title_plan/2`'s. A failure inside the task is
  logged at warning on `:acquisition` and leaves no plan.
  """
  @spec plan_title(Title.t(), keyword()) :: :ok
  def plan_title(%Title{} = title, opts \\ []) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      case create_title_plan(title, opts) do
        {:ok, _plan} -> :ok
        {:error, :nothing_to_plan} -> Log.warning(:acquisition, "nothing to plan — #{title.name}")
        {:error, reason} -> Log.warning(:acquisition, "could not plan — #{title.name} — #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Creates the plan for a TMDB title from its snapshot, synchronously —
  the door the choose-releases download action uses, because it waits
  for the plan's id to open its board (spec 2026-09-12 §20).

  Options: `approval_policy:` (`"automatic"` | `"review"`, default
  review) and `scope:` (series only) `:first_season` (default) or
  `:everything`, see `DownloadScope`.

  A scope covers episodes that have *aired*; downloading them says
  nothing about what is still to come, and this door never touches the
  title's rung. Following a series is a person's act on the watchlist
  (ADR-066).

  A movie resolves its ids from TMDB best-effort (`movie_plan_attrs/1`);
  a series needs its targeting selection, so TMDB must answer.
  `{:error, :nothing_to_plan}` when the scope yields no unit; the
  targeting or creation error otherwise.
  """
  @spec create_title_plan(Title.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def create_title_plan(title, opts \\ [])

  def create_title_plan(%Title{media_type: :movie} = title, opts) do
    create_movie_plan(movie_plan_attrs(title), approval_policy: title_policy(opts))
  end

  def create_title_plan(%Title{media_type: :tv_series} = title, opts) do
    scope = Keyword.get(opts, :scope, :first_season)

    with {:ok, selection} <- Targeting.series_selection(title.tmdb_id),
         units when units != [] <- DownloadScope.units(selection, scope) do
      create_series_plan(selection, units, approval_policy: title_policy(opts))
    else
      [] -> {:error, :nothing_to_plan}
      {:error, reason} -> {:error, reason}
    end
  end

  defp title_policy(opts), do: Keyword.get(opts, :approval_policy, "review")
```

- [ ] **Step 5: Run the whole file**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/plans_test.exs`
Expected: all pass, including the existing `plan_title/2` describe.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/acquisition/plans.ex test/support/tmdb_stubs.ex test/media_centaur/acquisition/plans_test.exs
git commit -m "feat(acquisition): Plans.create_title_plan/2 — the synchronous title door

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 2: `Settings.Preferences.PlanningMode`

**Files:**
- Create: `lib/media_centaur/settings/preferences/planning_mode.ex`
- Modify: `lib/media_centaur/settings/preferences.ex` (exports list + moduledoc sentence)
- Test: `test/media_centaur/settings/preferences/planning_mode_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Settings.Preferences.PlanningModeTest do
  @moduledoc """
  The default planning mode: what the Download button on a title the
  library does not own does by default. Two modes, one default; every
  malformed row reads as the default so a bad value can never turn on
  unattended commits.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.PlanningMode

  describe "value/0" do
    test "is :manually_select_release when no entry exists" do
      assert Settings.get_by_key(PlanningMode.setting_key()) == nil
      assert PlanningMode.value() == :manually_select_release
    end

    test "reads a stored auto_select_best_release" do
      store(%{"mode" => "auto_select_best_release"})
      assert PlanningMode.value() == :auto_select_best_release
    end

    test "reads a stored manually_select_release" do
      store(%{"mode" => "manually_select_release"})
      assert PlanningMode.value() == :manually_select_release
    end

    test "an unknown mode string is the default" do
      store(%{"mode" => "grab_everything"})
      assert PlanningMode.value() == :manually_select_release
    end

    test "a value shaped unexpectedly is the default" do
      store(%{"enabled" => true})
      assert PlanningMode.value() == :manually_select_release
    end
  end

  describe "set/1" do
    test "persists the mode under the key" do
      PlanningMode.set(:auto_select_best_release)
      assert PlanningMode.value() == :auto_select_best_release

      PlanningMode.set(:manually_select_release)
      assert PlanningMode.value() == :manually_select_release
    end

    test "rejects anything but a mode" do
      assert_raise FunctionClauseError, fn -> PlanningMode.set(:grab) end
    end
  end

  describe "other/1" do
    test "is the one alternative" do
      assert PlanningMode.other(:manually_select_release) == :auto_select_best_release
      assert PlanningMode.other(:auto_select_best_release) == :manually_select_release
    end
  end

  defp store(value) do
    Settings.find_or_create_entry!(%{key: PlanningMode.setting_key(), value: value})
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs`
Expected: `UndefinedFunctionError` on `PlanningMode.setting_key/0`.

- [ ] **Step 3: Create `lib/media_centaur/settings/preferences/planning_mode.ex`**

```elixir
defmodule MediaCentaur.Settings.Preferences.PlanningMode do
  @moduledoc """
  Typed accessor for the `default_planning_mode` Settings entry — what
  the Download button on a title the library does not own does when
  pressed (spec 2026-09-12 §9): `:manually_select_release` creates the
  plan for review and opens its board on Incoming; `:auto_select_best_release`
  creates it `automatic`, so a clean plan commits with nobody looking.
  The other mode is always one click away in the button's menu; this
  entry only names the default.

  Default `:manually_select_release`: an absent, malformed or unknown
  value all read as it, so a bad row can never turn on unattended
  commits.

  Read where the title detail is built (`TitleDetailHost`), like the
  auto-grab default mode — not through `SettingAware`: the setting
  changes only on the Settings page, never underneath an open modal.
  """

  alias MediaCentaur.Settings

  @setting_key "default_planning_mode"
  @modes [:manually_select_release, :auto_select_best_release]
  @default :manually_select_release

  @type mode :: :manually_select_release | :auto_select_best_release

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Every mode, the default first."
  @spec modes() :: [mode()]
  def modes, do: @modes

  @doc "The current default mode; `:manually_select_release` when the entry is absent."
  @spec value() :: mode()
  def value do
    case Settings.get_by_key(@setting_key) do
      %{value: value} -> parse(value)
      _ -> @default
    end
  end

  @doc "Parses a stored value; anything but a known mode string is the default."
  @spec parse(term()) :: mode()
  def parse(%{"mode" => "auto_select_best_release"}), do: :auto_select_best_release
  def parse(%{"mode" => "manually_select_release"}), do: :manually_select_release
  def parse(_value), do: @default

  @doc "The mode the button's menu offers beside the default."
  @spec other(mode()) :: mode()
  def other(:manually_select_release), do: :auto_select_best_release
  def other(:auto_select_best_release), do: :manually_select_release

  @doc "Persists the default mode. Subscribers learn of it through `{:setting_changed, key, value}`."
  @spec set(mode()) :: Settings.Entry.t()
  def set(mode) when mode in @modes do
    Settings.find_or_create_entry!(%{key: @setting_key, value: %{"mode" => Atom.to_string(mode)}})
  end
end
```

- [ ] **Step 4: Export it.** In `lib/media_centaur/settings/preferences.ex` add `PlanningMode,` to the `exports:` list (alphabetical, after `LibraryCardInfo`), and change the moduledoc sentence "`UIScale` is the one non-boolean preference and carries its own arithmetic." to "`UIScale` and `PlanningMode` are the non-boolean preferences; each carries its own parsing."

- [ ] **Step 5: Run the test**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/settings/preferences/planning_mode.ex lib/media_centaur/settings/preferences.ex test/media_centaur/settings/preferences/planning_mode_test.exs
git commit -m "feat(settings): PlanningMode preference — the Download button's default planning mode

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 3: Input system — an item counts once, for its nearest zone

**Files:**
- Modify: `assets/js/input/core/dom_adapter.js` (`queryContextItems`, ~lines 41-59)
- Modify: `assets/js/input/__tests__/config_coverage.test.js` (declared zones also come from `menu_zone="…"`)
- Test: `assets/js/input/core/__tests__/dom_adapter.test.js`

- [ ] **Step 1: Write the failing test.** In `dom_adapter.test.js`, change the `stubDocument` helper so extra document members pass through:

```js
function stubDocument({ activeElement, body = {}, documentElement = {}, ...rest }) {
  const real = globalThis.document
  globalThis.document = { activeElement, body, documentElement, ...rest }
  restore = () => { globalThis.document = real }
}
```

and append a new describe at the end of the file:

```js
describe("queryContextItems — an item counts once, for its nearest zone", () => {
  // A fake element tree: `zone` marks a [data-nav-zone] container, `navItem`
  // a [data-nav-item]; closest()/contains() walk `parent` links.
  function el({ zone = null, parent = null, navItem = false } = {}) {
    return {
      parent, zone, navItem,
      disabled: false,
      hasAttribute(name) { return name === "data-nav-item" ? navItem : name === "disabled" ? false : false },
      checkVisibility() { return true },
      closest(selector) {
        let cur = this
        while (cur) {
          if (selector === "[data-nav-zone]" && cur.zone) return cur
          cur = cur.parent
        }
        return null
      },
      contains(other) {
        let cur = other
        while (cur) {
          if (cur === this) return true
          cur = cur.parent
        }
        return false
      },
    }
  }

  const selectors = {
    strip: "[data-nav-zone='strip'] [data-nav-item]",
    menu: "[data-nav-zone='menu'] [data-nav-item]",
  }

  test("items inside a nested zone belong to the inner zone, not the outer", () => {
    const strip = el({ zone: "strip" })
    const button = el({ parent: strip, navItem: true })
    const chevron = el({ parent: strip, navItem: true })
    const menu = el({ zone: "menu", parent: strip })
    const item = el({ parent: menu, navItem: true })

    stubDocument({
      activeElement: null,
      querySelector: (sel) => (sel === "[data-nav-zone='strip']" ? strip : sel === "[data-nav-zone='menu']" ? menu : null),
      querySelectorAll: (sel) => (sel === selectors.strip ? [button, chevron, item] : sel === selectors.menu ? [item] : []),
    })
    const reader = createDomReader({ contextSelectors: selectors })

    expect(reader.getItemCount("strip")).toBe(2)
    expect(reader.getItemAt("strip", 1)).toBe(chevron)
    expect(reader.getItemCount("menu")).toBe(1)
    expect(reader.getItemAt("menu", 0)).toBe(item)
  })

  test("with no nested zone every matched item counts, as before", () => {
    const strip = el({ zone: "strip" })
    const a = el({ parent: strip, navItem: true })
    const b = el({ parent: strip, navItem: true })

    stubDocument({
      activeElement: null,
      querySelector: (sel) => (sel === "[data-nav-zone='strip']" ? strip : null),
      querySelectorAll: (sel) => (sel === selectors.strip ? [a, b] : []),
    })
    const reader = createDomReader({ contextSelectors: selectors })

    expect(reader.getItemCount("strip")).toBe(2)
  })
})
```

- [ ] **Step 2: Run it to see it fail**

Run: `bun test assets/js/input/core/__tests__/dom_adapter.test.js`
Expected: the first new test fails: `expected 3 to be 2`.

- [ ] **Step 3: Implement.** In `dom_adapter.js` replace the `queryContextItems` function (and its doc comment) with:

```js
/**
 * The element a context's selector is scoped to — its first compound
 * (`[data-nav-zone='grid']`, `[data-detail-mode='modal']`). Null when the
 * selector has no scope or the element is not in the DOM.
 */
function contextScopeElement(selector) {
  const scope = selector.split(" ")[0]
  return scope ? document.querySelector(scope) : null
}

/**
 * An item belongs to its nearest zone. A zone may contain another zone — a
 * menu list opened inside an action strip — and the outer zone's descendant
 * selector still matches the inner items, so they are dropped here, at the
 * one chokepoint every count, index and focus read goes through.
 */
function ownedByScope(item, scope) {
  if (!scope) return true
  const nearest = item.closest("[data-nav-zone]")
  return !nearest || nearest === scope || !scope.contains(nearest)
}

/**
 * Resolve the nav items for a context. MODAL items are scoped to the active
 * modal element (see `activeModalElement`); every other context uses its
 * flat config selector, minus items that belong to a zone nested inside it
 * (see `ownedByScope`). Disabled items are excluded (see `isNavigable`).
 * Returns an array (possibly empty).
 */
function queryContextItems(selectors, context) {
  if (context === Context.MODAL) {
    const modal = activeModalElement()
    return modal ? Array.from(modal.querySelectorAll("[data-nav-item]")).filter(isNavigable) : []
  }
  const selector = selectors[context]
  if (!selector) return []
  const scope = contextScopeElement(selector)
  return Array.from(document.querySelectorAll(selector)).filter(el => isNavigable(el) && ownedByScope(el, scope))
}
```

- [ ] **Step 4: Keep the coverage test honest.** In `config_coverage.test.js`, the test "every data-nav-zone has a context selector" reads literal `data-nav-zone="…"` attributes. Zones passed to the glass-menu components arrive as `menu_zone="…"`, so change that test to:

```js
  test("every data-nav-zone (and every menu_zone handed to a GlassMenu component) has a context selector", () => {
    const missing = [...declared("data-nav-zone"), ...declared("menu_zone")]
      .filter(([zone]) => !RESOLVABLE_ZONES.has(zone))
      .map(([zone, path]) => `${zone} (${path})`)

    expect(missing).toEqual([])
  })
```

- [ ] **Step 5: Run the JS suite**

Run: `bun test --dots assets/js/`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add assets/js/input/core/dom_adapter.js assets/js/input/core/__tests__/dom_adapter.test.js assets/js/input/__tests__/config_coverage.test.js
git commit -m "feat(input): an item counts once, for its nearest zone — zones may nest

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 4: Input system — a zone says what BACK pushes when it leaves

**Files:**
- Modify: `assets/js/input/core/dom_adapter.js` (reader gains `getZoneDismissEvent`)
- Modify: `assets/js/input/core/orchestrator.js` (`_handleAction`, after the transition)
- Test: `assets/js/input/core/__tests__/orchestrator.test.js`

- [ ] **Step 1: Write the failing test.** Append to `orchestrator.test.js`, inside the top-level `describe("Orchestrator", …)`:

```js
  describe("BACK out of a zone that declares a dismiss event", () => {
    // A page layout with a menu list (a TREE) under its toolbar: DOWN enters
    // it, BACK leaves along the `back` edge — and the zone's
    // `data-nav-dismiss-event` asks the LiveView to close the list, so the
    // cursor and the DOM leave together.
    const MENU_LAYOUTS = {
      ...TEST_LAYOUTS,
      menus: {
        toolbar: { down: ["menu", "grid"] },
        menu:    { up: ["toolbar"], back: ["toolbar"] },
        grid:    { up: ["toolbar"] },
        sidebar: { right: ["toolbar", "grid"] },
      },
    }

    function menuSetup(readerOverrides = {}) {
      return setup(
        {
          getZone: () => "menus",
          getItemCount: () => 2,
          getFocusedIndex: () => 0,
          getZoneDismissEvent: (ctx) => (ctx === "menu" ? "close_menu" : null),
          ...readerOverrides,
        },
        {
          contextSelectors: { ...TEST_CONFIG.contextSelectors, menu: "[data-nav-zone='menu'] [data-nav-item]" },
          instanceTypes: { ...TEST_CONFIG.instanceTypes, menu: Context.TREE },
          layouts: MENU_LAYOUTS,
          cursorStartPriority: { ...TEST_CONFIG.cursorStartPriority, menus: ["toolbar", "grid", "sidebar"] },
        },
      )
    }

    test("BACK from the menu returns to the toolbar and pushes the zone's dismiss event", () => {
      const { system } = menuSetup()
      const pushEvent = mock(() => {})
      system.start({ pushEvent })
      system.focusMachine.forceContext("menu")

      system._handleAction(Action.BACK)

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
      expect(pushEvent).toHaveBeenCalledWith("close_menu", {})
    })

    test("BACK from a zone without a dismiss event pushes nothing", () => {
      const { system } = menuSetup({ getZoneDismissEvent: () => null })
      const pushEvent = mock(() => {})
      system.start({ pushEvent })
      system.focusMachine.forceContext("menu")

      system._handleAction(Action.BACK)

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
      expect(pushEvent).not.toHaveBeenCalled()
    })

    test("BACK from the toolbar (no back edge) still enters the sidebar", () => {
      const { system } = menuSetup({ getActiveItemIndex: (ctx) => (ctx === "sidebar" ? 0 : -1) })
      const pushEvent = mock(() => {})
      system.start({ pushEvent })
      system.focusMachine.forceContext(Context.TOOLBAR)

      system._handleAction(Action.BACK)

      expect(system.focusMachine.context).toBe("sidebar")
      expect(pushEvent).not.toHaveBeenCalled()
    })
  })
```

- [ ] **Step 2: Run it to see it fail**

Run: `bun test assets/js/input/core/__tests__/orchestrator.test.js`
Expected: the first new test fails on `toHaveBeenCalledWith("close_menu", {})`.

- [ ] **Step 3: Reader.** In `dom_adapter.js`, inside the object `createDomReader` returns, after `getDismissEvent()` add:

```js
    /**
     * The event a zone asks the LiveView for when BACK leaves it —
     * `data-nav-dismiss-event` on the zone container. A menu list closes
     * itself this way. Null when the zone declares none.
     */
    getZoneDismissEvent(context) {
      const selector = selectors[context]
      if (!selector) return null
      return contextScopeElement(selector)?.dataset?.navDismissEvent ?? null
    },
```

- [ ] **Step 4: Orchestrator.** In `_handleAction`, directly after `const directive = this.focusMachine.transition(action)`, add:

```js
    // A zone that declares `data-nav-dismiss-event` is a containment layer
    // the LiveView owns (a menu list). BACK peeling out of it along its
    // `back` edge also tells the LiveView to close it, so the cursor and the
    // DOM leave together.
    if (directive.type === "enter_context" && directive.direction === "back") {
      const dismiss = this.reader.getZoneDismissEvent?.(contextBefore)
      if (dismiss) this._hookEl?.pushEvent?.(dismiss, {})
    }
```

Also extend the module header comment's list of what the orchestrator executes with one line: ` * A zone may declare \`data-nav-dismiss-event\`; BACK leaving it along its back edge pushes that event (menus close themselves this way).`

- [ ] **Step 5: Run the JS suite**

Run: `bun test --dots assets/js/`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add assets/js/input/core/dom_adapter.js assets/js/input/core/orchestrator.js assets/js/input/core/__tests__/orchestrator.test.js
git commit -m "feat(input): data-nav-dismiss-event — BACK out of a zone tells the LiveView to close it

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 5: `GlassMenu` — `menu_list`, `split_button`, `menu_select` with stories

**Files:**
- Create: `lib/media_centaur_web/components/glass_menu.ex`
- Create: `storybook/core_components/menu_list.story.exs`, `storybook/core_components/split_button.story.exs`, `storybook/core_components/menu_select.story.exs`
- Modify: `storybook/core_components/_core_components.index.exs`
- Modify: `assets/css/app.css` (the `.glass-menu` block, ~lines 1399-1484)
- Test: the storybook compile/render tests (`test/media_centaur_web/storybook_compile_test.exs`, `storybook_render_test.exs`) pick the stories up automatically.

- [ ] **Step 1: Create the component module**

```elixir
defmodule MediaCentaurWeb.Components.GlassMenu do
  @moduledoc """
  The house dropdown idiom (`.glass-menu*` in `app.css`): a trigger with a
  chevron and an anchored glass list beneath it, open state owned by the
  LiveView. Three components: `menu_list/1` is the list; `split_button/1`
  puts it under a two-segment trigger whose main segment performs an
  action; `menu_select/1` under a trigger that shows the current value.
  The tenants are the title detail modal's Download control and scope
  select, and the library sort control (spec 2026-09-12 §12–16).

  ## Nav

  The list is its own nav zone (`zone` / `menu_zone`) inside the
  trigger's zone — nesting the input system allows because an item
  counts for its nearest zone only — and declares
  `data-nav-dismiss-event`, so BACK along the zone's `back` edge returns
  the cursor to the trigger and asks the LiveView to close the list in
  one press. The tenant's layout in `config.js` declares the zone: a
  TREE reached by DOWN from the trigger's zone, with `up` and `back`
  edges to it.

  ## Open state

  `open` is the host's assign. `on_toggle` is what the trigger pushes
  (an event name or a `JS.push/2` carrying a value); `on_close` is a
  plain event name, pushed by a click outside (`phx-click-away`) and by
  BACK. The host closes the list itself when an item's event lands.
  """

  use MediaCentaurWeb, :html

  @variants ~w(primary secondary action info risky danger dismiss destructive_inline neutral outline)

  attr :id, :string, required: true
  attr :zone, :string, required: true, doc: "the list's `data-nav-zone` — a TREE declared in `config.js`"
  attr :on_close, :string, required: true, doc: "the event BACK pushes when it leaves the list"
  attr :class, :any, default: nil, doc: "utilities on the `ul`"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean, doc: "the current choice (`menu_select`)"
  end

  def menu_list(assigns) do
    ~H"""
    <ul
      id={@id}
      class={["glass-menu-list glass-surface", @class]}
      role="menu"
      data-nav-zone={@zone}
      data-nav-dismiss-event={@on_close}
    >
      <li
        :for={item <- @item}
        id={item[:id]}
        role="menuitem"
        class={["glass-menu-item", item[:active] && "glass-menu-item-active"]}
        phx-click={item.event}
        {phx_values(item[:values])}
        data-nav-item
        tabindex="0"
      >
        {render_slot(item)}
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true, doc: "the main segment's id; the chevron is `<id>-toggle`, the list `<id>-menu`"
  attr :open, :boolean, required: true
  attr :on_toggle, :any, required: true, doc: "event name or `Phoenix.LiveView.JS` the chevron pushes"
  attr :on_close, :string, required: true, doc: "the event a click outside and BACK push"
  attr :menu_zone, :string, required: true, doc: "the list's `data-nav-zone`"
  attr :variant, :string, default: "primary", values: @variants
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :menu_label, :string, default: "More options", doc: "the chevron's accessible name"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil, doc: "utilities on the wrapper"
  attr :rest, :global, doc: "the main segment's bindings: `phx-click`, `phx-value-*`"

  slot :inner_block, required: true, doc: "the main segment's label"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean
  end

  def split_button(assigns) do
    assigns = assign(assigns, :divider, divider_class(assigns.variant))

    ~H"""
    <span id={@id <> "-split"} class={["glass-menu inline-flex", @class]} phx-click-away={@on_close}>
      <.button
        id={@id}
        variant={@variant}
        size={@size}
        class="rounded-r-none"
        disabled={@disabled}
        data-nav-item
        tabindex="0"
        {@rest}
      >
        {render_slot(@inner_block)}
      </.button>
      <.button
        id={@id <> "-toggle"}
        variant={@variant}
        size={@size}
        shape="square"
        class={["rounded-l-none border-l", @divider]}
        disabled={@disabled}
        phx-click={@on_toggle}
        aria-label={@menu_label}
        aria-haspopup="menu"
        aria-expanded={to_string(@open)}
        data-nav-item
        tabindex="0"
      >
        <span class={["glass-menu-chevron", @open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </.button>
      <.menu_list
        :if={@open}
        id={@id <> "-menu"}
        zone={@menu_zone}
        on_close={@on_close}
        class="glass-menu-list--content"
      >
        <:item :for={item <- @item} id={item[:id]} event={item.event} values={item[:values]} active={item[:active]}>
          {render_slot(item)}
        </:item>
      </.menu_list>
    </span>
    """
  end

  attr :id, :string, required: true, doc: "the trigger's id; the list is `<id>-menu`"
  attr :open, :boolean, required: true
  attr :on_toggle, :any, required: true, doc: "event name or `Phoenix.LiveView.JS` the trigger pushes"
  attr :on_close, :string, required: true, doc: "the event a click outside and BACK push"
  attr :menu_zone, :string, required: true, doc: "the list's `data-nav-zone`"
  attr :value_label, :string, required: true, doc: "the trigger's text — the current choice"
  attr :label, :string, required: true, doc: "the accessible name, e.g. \"Sort\" or \"Download scope\""
  attr :class, :any, default: nil, doc: "utilities on the wrapper"
  attr :rest, :global, doc: "data attributes on the wrapper (`data-sort`)"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean, doc: "the current choice"
  end

  def menu_select(assigns) do
    ~H"""
    <span id={@id <> "-select"} class={["glass-menu inline-flex", @class]} phx-click-away={@on_close} {@rest}>
      <button
        id={@id}
        type="button"
        class="glass-menu-trigger"
        phx-click={@on_toggle}
        aria-label={@label}
        aria-haspopup="menu"
        aria-expanded={to_string(@open)}
        data-nav-item
        tabindex="0"
      >
        {@value_label}
        <span class={["glass-menu-chevron", @open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </button>
      <.menu_list :if={@open} id={@id <> "-menu"} zone={@menu_zone} on_close={@on_close}>
        <:item :for={item <- @item} id={item[:id]} event={item.event} values={item[:values]} active={item[:active]}>
          {render_slot(item)}
        </:item>
      </.menu_list>
    </span>
    """
  end

  # The hairline between the segments takes the variant's own ink so it
  # reads on a solid primary and on a soft tint alike.
  defp divider_class("primary"), do: "border-primary-content/20"
  defp divider_class(_variant), do: "border-base-content/15"

  # `phx-value-<key>` per entry; MC0021 forbids the key `value` itself.
  defp phx_values(nil), do: %{}
  defp phx_values(map), do: Map.new(map, fn {key, value} -> {"phx-value-#{key}", value} end)
end
```

- [ ] **Step 2: CSS.** In `assets/css/app.css` replace

```css
.glass-menu-trigger:hover,
.glass-menu[data-captures-keys="true"] .glass-menu-trigger {
```

with

```css
.glass-menu-trigger:hover,
.glass-menu-trigger[aria-expanded="true"] {
```

and update the block comment above `.glass-menu` to: `/* Glass menu — the house dropdown idiom: a quiet trigger with a chevron and a glass list beneath it, LiveView-owned open state. Rendered by \`MediaCentaurWeb.Components.GlassMenu\` (menu_list, split_button, menu_select); worn by the library sort control and the title detail modal's Download control and scope select. */`. Because dev asset watchers are off, rebuild once: `~/scripts/agents/agent-mix assets.build`.

- [ ] **Step 3: Stories.** Create `storybook/core_components/menu_list.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.CoreComponents.MenuList do
  @moduledoc """
  The glass menu's list on its own (spec 2026-09-12 §13): items are nav
  items in the list's zone, the list carries the dismiss event BACK
  pushes, and the active item wears the primary colour. The tenants
  (`split_button`, `menu_select`) anchor it under their triggers; here it
  sits in a relative box so it renders in place.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.menu_list/1
  def render_source, do: :function

  def template do
    """
    <div class="glass-menu inline-block pb-40">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :two_items,
        description: "Two choices, the first active.",
        attributes: %{id: "list-two", zone: "sample_menu", on_close: "close_menu"},
        slots: [
          ~s|<:item id="list-two-a" event="pick" values={%{"choice" => "a"}} active>Season 1</:item>|,
          ~s|<:item id="list-two-b" event="pick" values={%{"choice" => "b"}}>All seasons</:item>|
        ]
      },
      %Variation{
        id: :content_width,
        description: "`--content` sizing: the list hugs its longest label instead of its anchor.",
        attributes: %{id: "list-content", zone: "sample_menu", on_close: "close_menu", class: "glass-menu-list--content"},
        slots: [
          ~s|<:item id="list-content-a" event="pick">Manually select release</:item>|
        ]
      }
    ]
  end
end
```

Create `storybook/core_components/split_button.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.CoreComponents.SplitButton do
  @moduledoc """
  The split button (spec 2026-09-12 §14): a main segment that performs
  the default action and a chevron that opens the glass menu with the
  other choices. The open list is a nav zone of its own, so the story
  pins the wiring — `data-nav-zone`, `data-nav-dismiss-event`,
  `aria-expanded` — as much as the look. Every `variant` and `size` of
  the underlying button is exercised (MC0009).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.split_button/1
  def render_source, do: :function

  # The open list drops below the trigger via `position: absolute`.
  def template do
    """
    <div class="pb-24">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed: the main segment carries the verb, the chevron waits.",
        attributes: base(open: false),
        slots: slots()
      },
      %Variation{
        id: :open,
        description: "Open: the one other choice, under the button.",
        attributes: base(open: true),
        slots: slots()
      },
      %Variation{
        id: :open_two_items,
        description: "A longer menu.",
        attributes: base(open: true),
        slots: [
          ~s|Download|,
          ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|,
          ~s|<:item id="split-follow" event="title_follow">Download and follow</:item>|
        ]
      },
      %Variation{
        id: :pending,
        description: "Disabled while the host plans — the label says why.",
        attributes: base(open: false, disabled: true),
        slots: [
          ~s|Planning…|,
          ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|
        ]
      },
      %VariationGroup{
        id: :variants,
        description: "Every button variant, closed.",
        variations:
          for variant <- ~w(primary secondary action info risky danger dismiss destructive_inline neutral outline) do
            %Variation{
              id: String.to_atom("variant_" <> variant),
              attributes: base(open: false, variant: variant),
              slots: slots()
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Every size, closed.",
        variations:
          for size <- ~w(xs sm md lg) do
            %Variation{
              id: String.to_atom("size_" <> size),
              attributes: base(open: false, size: size),
              slots: slots()
            }
          end
      }
    ]
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "split",
        open: false,
        on_toggle: "title_menu_toggle",
        on_close: "title_menu_close",
        menu_zone: "sample_menu",
        menu_label: "More download options",
        "phx-click": "title_download"
      },
      Map.new(overrides)
    )
  end

  defp slots do
    [
      ~s|Download|,
      ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|
    ]
  end
end
```

Create `storybook/core_components/menu_select.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.CoreComponents.MenuSelect do
  @moduledoc """
  The menu select (spec 2026-09-12 §15): a quiet trigger showing the
  current value, a chevron, and the glass menu of options with the
  current one marked. The library sort control and the title detail
  modal's scope select are its tenants.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.menu_select/1
  def render_source, do: :function

  def template do
    """
    <div class="pb-32">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed, showing the current choice.",
        attributes: base(open: false),
        slots: scope_items()
      },
      %Variation{
        id: :open,
        description: "Open: the current choice marked, the other plain.",
        attributes: base(open: true),
        slots: scope_items()
      },
      %Variation{
        id: :sort,
        description: "The library sort control's four options, with a `data-sort` on the wrapper.",
        attributes: base(id: "sort", open: true, value_label: "Recently Added", label: "Sort", "data-sort": "recent"),
        slots: [
          ~s|<:item id="sort-recent" event="sort" values={%{"sort" => "recent"}} active>Recently Added</:item>|,
          ~s|<:item id="sort-watched" event="sort" values={%{"sort" => "watched"}}>Recently Watched</:item>|,
          ~s|<:item id="sort-alpha" event="sort" values={%{"sort" => "alpha"}}>A–Z</:item>|,
          ~s|<:item id="sort-year" event="sort" values={%{"sort" => "year"}}>Year</:item>|
        ]
      }
    ]
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "scope",
        open: false,
        on_toggle: "title_scope_toggle",
        on_close: "title_menu_close",
        menu_zone: "sample_menu",
        value_label: "Season 1",
        label: "Download scope"
      },
      Map.new(overrides)
    )
  end

  defp scope_items do
    [
      ~s|<:item id="scope-first_season" event="title_scope" values={%{"choice" => "first_season"}} active>Season 1</:item>|,
      ~s|<:item id="scope-everything" event="title_scope" values={%{"choice" => "everything"}}>All seasons</:item>|
    ]
  end
end
```

Add to `storybook/core_components/_core_components.index.exs` (alphabetical):

```elixir
  def entry("menu_list"), do: [icon: {:fa, "list-ul", :thin}, name: "Menu list"]
  def entry("menu_select"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Menu select"]
  def entry("split_button"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Split button"]
```

- [ ] **Step 4: Run the storybook tests and Credo**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS (three new stories render).
Run: `~/scripts/agents/agent-mix credo --strict`
Expected: no MC0008/MC0009 findings on `glass_menu.ex`.

- [ ] **Step 5: Look at them.** With the dev server up: `~/scripts/agents/page-shot --url 'http://127.0.0.1:2160/storybook/core-components/split-button' --wait-ms 3000 --viewport 1920x1080` and the same for `menu-select`; Read the PNGs and fix anything that is not a clean two-segment button with a hairline divider and a glass list under it.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/glass_menu.ex storybook/core_components assets/css/app.css
git commit -m "feat(ui): GlassMenu — menu_list, split_button, menu_select on the glass dropdown idiom

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 6: The view-model carries the planning mode; labels live in `Title.Logic`

**Files:**
- Modify: `lib/media_centaur_web/components/title/detail.ex`
- Modify: `lib/media_centaur_web/components/title/logic.ex`
- Test: `test/media_centaur_web/components/title/logic_test.exs`

- [ ] **Step 1: Write the failing tests.** Append to `logic_test.exs` (inside the module; alias `MediaCentaurWeb.Components.Title.Logic` is already there):

```elixir
  describe "planning mode words" do
    test "each mode has its label" do
      assert Logic.planning_mode_label(:auto_select_best_release) == "Auto-select best release"
      assert Logic.planning_mode_label(:manually_select_release) == "Manually select release"
    end

    test "each scope has its label" do
      assert Logic.download_scope_label(:first_season) == "Season 1"
      assert Logic.download_scope_label(:everything) == "All seasons"
    end
  end

  describe "title_detail/2 planning mode" do
    alias MediaCentaur.TMDB.Title

    defp facts(overrides) do
      Map.merge(
        %{
          library_owner_id: nil,
          rung: nil,
          acquisition_state: nil,
          release_mode_available: true,
          today: ~D[2026-09-12]
        },
        overrides
      )
    end

    test "carries the host's planning mode" do
      title = Title.new!(%{tmdb_id: 1, media_type: :movie, name: "Sample Movie", release_date: ~D[2020-01-01]})

      assert %{planning_mode: :auto_select_best_release} =
               Logic.title_detail(title, facts(%{planning_mode: :auto_select_best_release}))
    end

    test "defaults to manually selecting" do
      title = Title.new!(%{tmdb_id: 1, media_type: :movie, name: "Sample Movie", release_date: ~D[2020-01-01]})

      assert %{planning_mode: :manually_select_release} = Logic.title_detail(title, facts(%{}))
    end
  end
```

- [ ] **Step 2: Run to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: `UndefinedFunctionError` on `Logic.planning_mode_label/1`.

- [ ] **Step 3: View-model.** In `detail.ex`: add `planning_mode: :manually_select_release` to the `defstruct` defaults (after `default_grab_mode: "off"`), add `planning_mode: PlanningMode.mode(),` to `@type t`, add `alias MediaCentaur.Settings.Preferences.PlanningMode`, and add to the moduledoc after the `scoped?` sentence: "`planning_mode` is the person's default planning mode (`Settings.Preferences.PlanningMode`), read on build like `default_grab_mode`: the main segment of Download performs it and the menu names the other."

- [ ] **Step 4: Logic.** In `logic.ex`: add `alias MediaCentaur.Acquisition.Plans.DownloadScope` and `alias MediaCentaur.Settings.Preferences.PlanningMode`; add `planning_mode: Map.get(facts, :planning_mode, :manually_select_release),` to the `%TitleDetail{}` in `title_detail/2`; add `planning_mode` to the `@doc`'s optional facts list; and add after `acquisition_marker/1`:

```elixir
  @doc "The words for a planning mode — the Settings option and the Download menu item alike (spec 2026-09-12 §2, §11)."
  @spec planning_mode_label(PlanningMode.mode()) :: String.t()
  def planning_mode_label(:auto_select_best_release), do: "Auto-select best release"
  def planning_mode_label(:manually_select_release), do: "Manually select release"

  @doc "The scope select's words for a download scope."
  @spec download_scope_label(DownloadScope.scope()) :: String.t()
  def download_scope_label(:first_season), do: "Season 1"
  def download_scope_label(:everything), do: "All seasons"
```

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/title/detail.ex lib/media_centaur_web/components/title/logic.ex test/media_centaur_web/components/title/logic_test.exs
git commit -m "feat(title): the detail view-model carries the planning mode; labels in Logic

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 7: The Download control — modal, host, hosts' callbacks, nav layout

**Files:**
- Modify: `lib/media_centaur_web/components/title/detail_modal.ex`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex`
- Modify: `lib/media_centaur_web/live/discovery_live.ex` (`open_plan_board/2`)
- Modify: `lib/media_centaur_web/live/incoming_live.ex` (`open_plan_board/2`)
- Modify: `assets/js/input/config.js` (`title_detail_menu` back edge)
- Modify: `assets/js/input/__tests__/discovery_behavior.test.js`
- Modify: `storybook/title/title_detail_modal.story.exs`
- Test: `test/media_centaur_web/live/discovery_live_test.exs`, `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Write the failing tests (Discovery).** In `discovery_live_test.exs` add `alias MediaCentaur.Settings.Preferences.PlanningMode` to the aliases, add this helper at the bottom of the module:

```elixir
  # Polls until `fun` returns a non-nil value. A manual plan is created by
  # an owned async, so the assertion waits for the row rather than sleeping.
  defp eventually(fun, deadline_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    case fun.() do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("eventually/1 timed out")
        else
          Process.sleep(10)
          do_eventually(fun, deadline)
        end

      value ->
        value
    end
  end
```

and add this helper inside the `describe "title detail modal"` block next to `released_movie/0`:

```elixir
    defp released_show do
      Title.new!(%{
        tmdb_id: 246_810,
        media_type: :tv_series,
        name: "Sample Show",
        year: "2010",
        release_date: ~D[2010-01-01]
      })
    end
```

Then **replace** the test `"Download creates an automatic plan, closes the modal, flashes, and the row shows the state"` and the test `"a series Download offers season 1 and the scope menu's Download all"` with these six tests:

```elixir
    test "Download under the default mode plans for manual selection and opens its board on Incoming",
         %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      assert has_element?(view, "#title-download", "Download")
      # A movie has one scope: no scope select.
      refute has_element?(view, "#title-scope")

      html = view |> element("#title-download") |> render_click()
      assert html =~ "Planning…"

      plan = eventually(fn -> List.first(Plans.list_drafts()) end)
      assert plan.approval_policy == "review"
      assert plan.tmdb_type == "movie"
      assert_redirect(view, "/incoming?plan=#{plan.id}")
    end

    test "Download under the auto-select mode creates an automatic plan, closes the modal and flashes",
         %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-download") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      assert render(view) =~ "Finding a release for Sample Movie"
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review on the row.
      render_until(view, fn _html -> has_element?(view, "#watchlist-item-movie-777", "Needs review") end)
    end

    test "the menu names the other mode and performs it", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      refute has_element?(view, "#title-download-menu")
      view |> element("#title-download-toggle") |> render_click()
      assert has_element?(view, "#title-download-menu #title-download-other", "Auto-select best release")

      view |> element("#title-download-other") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      await_supervised_tasks()
      assert [%{approval_policy: "automatic"}] = Plans.list_drafts()
    end

    test "with auto-select as the default the menu offers manual selection", %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-download-toggle") |> render_click()
      assert has_element?(view, "#title-download-other", "Manually select release")

      # Closing the menu is its own event (a click outside, or BACK).
      render_hook(view, "title_menu_close", %{})
      refute has_element?(view, "#title-download-menu")
    end

    test "a series Download plans season 1 by default; the scope select widens it to all seasons",
         %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()
      {:ok, _} = Discovery.put_rung(released_show(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      assert has_element?(view, "#title-download", "Download")
      assert has_element?(view, "#title-scope", "Season 1")
      refute has_element?(view, "#title-scope-menu")

      view |> element("#title-scope") |> render_click()
      assert has_element?(view, "#title-scope-menu #title-scope-everything", "All seasons")
      assert has_element?(view, "#title-scope-first_season.glass-menu-item-active")

      view |> element("#title-scope-everything") |> render_click()
      refute has_element?(view, "#title-scope-menu")
      assert has_element?(view, "#title-scope", "All seasons")

      view |> element("#title-download") |> render_click()

      plan = eventually(fn -> List.first(Plans.list_drafts()) end)
      assert plan.tmdb_type == "tv"
      assert plan.approval_policy == "review"
      assert length(Plans.units_for(plan.id)) == 3
      assert_redirect(view, "/incoming?plan=#{plan.id}")

      # Downloading what has aired says nothing about what is to come: the
      # title stays where the person put it, at List.
      refute ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
      assert Discovery.rung(246_810, :tv_series) == :list
    end

    test "a TMDB failure while planning manually flashes on the modal and leaves no plan",
         %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_show(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      view |> element("#title-download") |> render_click()

      render_until(view, "Couldn't plan Sample Show")
      assert has_element?(view, "#title-download", "Download")
      assert Plans.list_drafts() == []
    end
```

- [ ] **Step 2: Write the failing test (Incoming).** In `incoming_live_test.exs`, inside `describe "omnibox — one search surface, two modes (UIDR-014)"`, add:

```elixir
    test "Download in the title detail on Incoming patches to the new plan's board", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_search_multi([
        %{"id" => 246_810, "media_type" => "tv", "name" => "Sample Show", "first_air_date" => "2010-06-16"}
      ])

      {:ok, view, _html} = live_async!(conn, ~p"/incoming")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view, 2_000)
      view |> element("#omnibox-result-tv_series-246810") |> render_click()
      assert_patch(view, "/incoming?title=tv_series-246810")

      # The targeting fetch behind Download reads the series universe.
      TmdbStubs.stub_series_universe_for_targeting()
      view |> element("#title-download") |> render_click()

      plan = eventually(fn -> List.first(MediaCentaur.Acquisition.Plans.list_drafts()) end)
      assert plan.approval_policy == "review"
      assert_patch(view, "/incoming?plan=#{plan.id}")
      assert has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "#title-detail-modal[data-state='open']")
    end
```

and the same `eventually/2` + `do_eventually/2` helpers at the bottom of that module. The module's top-level `setup` already stubs Prowlarr and marks it ready, so Download is offered in the title detail.

- [ ] **Step 3: Run the tests to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/incoming_live_test.exs`
Expected: the new tests fail (`#title-download-toggle`, `#title-scope` not found; the default-mode test finds an `automatic` plan).

- [ ] **Step 4: Nav layout.** In `assets/js/input/config.js` change the `title_detail` overlay layout to:

```js
    title_detail: {
      entry: ["title_detail_body", "title_detail_menu", "title_detail_tracking"],
      layout: {
        title_detail_body: { down: ["title_detail_menu", "title_detail_tracking"] },
        // The open menu (the other planning mode, or the scope) is a list
        // nested inside the strip; BACK leaves it for the strip and, through
        // the list's `data-nav-dismiss-event`, closes it.
        title_detail_menu: { up: ["title_detail_body"], down: ["title_detail_tracking"], back: ["title_detail_body"] },
        title_detail_tracking: { up: ["title_detail_menu", "title_detail_body"] },
      },
    },
```

and update the `instanceTypes` comments: `title_detail_body`: "The title detail modal's action row walks LEFT/RIGHT like the library detail's action row; its menus are zones nested inside it." and `title_detail_menu`: "Whichever Download menu is open — the other planning mode, or the scope — a short vertical list under the strip." In `discovery_behavior.test.js` change the expected `title_detail_menu` line to `title_detail_menu: { up: ["title_detail_body"], down: ["title_detail_tracking"], back: ["title_detail_body"] },` and the test name to "…over the open menu over the tracking strip, DOWN/UP between them, BACK out of the menu".

- [ ] **Step 5: The modal.** In `detail_modal.ex`:

Aliases: add `alias MediaCentaurWeb.Components.GlassMenu` and `alias MediaCentaur.Settings.Preferences.PlanningMode`.

Replace the attrs of `title_detail_modal/1` — remove `attr :scope_menu_open …` and add:

```elixir
  attr :open_menu, :atom,
    default: nil,
    values: [nil, :mode, :scope],
    doc: "which of the Download control's menus is open: the other planning mode, or the scope"

  attr :download_scope, :atom, default: :first_season, values: [:first_season, :everything]

  attr :download_pending?, :boolean,
    default: false,
    doc: "a manual plan is being created — the split button is disabled and says so"
```

Replace the strip block (from the `<%!-- The scope menu is a sibling …` comment through the closing `</div>` of `<div class="mt-4 pb-5">`) with:

```heex
          <%!-- The action strip. The Download control's menus are zones
                nested inside it: the input system counts an item for its
                nearest zone, and BACK out of an open list closes it
                (`data-nav-dismiss-event`). --%>
          <div class="mt-4 pb-5">
            <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
              <.primary
                detail={@detail}
                open_menu={@open_menu}
                download_scope={@download_scope}
                download_pending?={@download_pending?}
              />
              <WatchlistToggle.watchlist_toggle
                id="title-watchlist"
                rung={@detail.rung}
                event="set_rung"
                phx-value-ref={@ref}
              />
              <.button
                :if={@review?}
                id="title-review"
                variant="dismiss"
                size="sm"
                shape="circle"
                class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
                phx-click="title_review_open"
                data-nav-item
                tabindex="0"
                title="Review"
                aria-label="Review"
              >
                <.icon name="hero-pencil-square" class="size-5" />
              </.button>
              <.tertiary detail={@detail} />
            </div>
          </div>
```

Replace the `primary/1` attrs and its two `:download` clauses (`scoped?: true` and plain) with:

```elixir
  attr :detail, TitleDetail, required: true
  attr :open_menu, :atom, required: true, values: [nil, :mode, :scope]
  attr :download_scope, :atom, required: true, values: [:first_season, :everything]
  attr :download_pending?, :boolean, required: true

  # … the :in_library and {:state, _} clauses stay as they are …

  # The split's main segment performs the person's default planning
  # mode; the menu names the other. A series adds the scope select.
  defp primary(%{detail: %{primary: :download}} = assigns) do
    assigns = assign(assigns, :other_mode, PlanningMode.other(assigns.detail.planning_mode))

    ~H"""
    <GlassMenu.split_button
      id="title-download"
      open={@open_menu == :mode}
      on_toggle="title_mode_toggle"
      on_close="title_menu_close"
      menu_zone="title_detail_menu"
      menu_label="More download options"
      disabled={@download_pending?}
      phx-click="title_download"
    >
      {if @download_pending?, do: "Planning…", else: "Download"}
      <:item
        id="title-download-other"
        event="title_download"
        values={%{"mode" => Atom.to_string(@other_mode)}}
      >
        {Logic.planning_mode_label(@other_mode)}
      </:item>
    </GlassMenu.split_button>
    <GlassMenu.menu_select
      :if={@detail.scoped?}
      id="title-scope"
      open={@open_menu == :scope}
      on_toggle="title_scope_toggle"
      on_close="title_menu_close"
      menu_zone="title_detail_menu"
      value_label={Logic.download_scope_label(@download_scope)}
      label="Download scope"
    >
      <:item
        :for={scope <- [:first_season, :everything]}
        id={"title-scope-" <> Atom.to_string(scope)}
        event="title_scope"
        values={%{"choice" => Atom.to_string(scope)}}
        active={scope == @download_scope}
      >
        {Logic.download_scope_label(scope)}
      </:item>
    </GlassMenu.menu_select>
    """
  end
```

Moduledoc: replace the sentence beginning "A series Download is a split control — …" through "(ADR-066)." with: "Download is a split button (`GlassMenu.split_button`): its main segment performs the person's default planning mode (`Settings.Preferences.PlanningMode`) and its menu names the other; a series adds a scope select beside it (`GlassMenu.menu_select`, Season 1 or All seasons). Neither follows the series: a scope covers episodes that have aired, and what is still to come is the ladder's business, never a download's (ADR-066)." Update the events sentence to: "`close_title`, `title_download` (`mode` from the menu, none from the main segment), `title_mode_toggle`, `title_scope_toggle`, `title_menu_close`, `title_scope` (`choice`), `title_activity_delete`, `set_rung`, `reset_lower_quality`." Update the Nav paragraph to: "the action strip is the `title_detail_body` TOOLBAR, whichever Download menu is open the `title_detail_menu` TREE nested inside it (BACK closes it), and the ladder strip the `title_detail_tracking` TOOLBAR in the body."

- [ ] **Step 6: The host.** In `title_detail_host.ex`:

Aliases: add `alias MediaCentaur.Acquisition.Plans.DownloadScope` and `alias MediaCentaur.Settings.Preferences.PlanningMode`.

Behaviour: add after the `title_detail_path` callback:

```elixir
  @callback open_plan_board(socket :: Phoenix.LiveView.Socket.t(), plan_id :: Ecto.UUID.t()) ::
              Phoenix.LiveView.Socket.t()
```

`@modal_events`: `~w(title_mode_toggle title_scope_toggle title_menu_close title_scope title_download title_activity_delete title_review_open)`.

`on_mount` seed: `assign(title_detail: nil, open_menu: nil, download_scope: :first_season, download_pending: nil)`.

`apply_title_params` fresh-open branch: `assign(title_detail: build_detail(socket, title, facts, nil), open_menu: nil, download_scope: :first_season)`.

`close/1`:

```elixir
  # Closing while a manual plan is being created abandons it: the person
  # left, so nobody should be taken to its board.
  defp close(socket) do
    socket =
      case socket.assigns.download_pending do
        nil -> socket
        name -> socket |> cancel_async(name) |> assign(:download_pending, nil)
      end

    assign(socket, title_detail: nil, open_menu: nil, download_scope: :first_season)
  end
```

`build_detail`: add `planning_mode: PlanningMode.value(),` to the `facts` map (after `default_grab_mode:`).

Replace the `title_scope_toggle`, `title_scope_close` and `title_download` event clauses with:

```elixir
  def handle_title_event("title_mode_toggle", _params, %{assigns: %{title_detail: %TitleDetail{}}} = socket),
    do: {:halt, update(socket, :open_menu, &toggle_menu(&1, :mode))}

  def handle_title_event("title_scope_toggle", _params, %{assigns: %{title_detail: %TitleDetail{}}} = socket),
    do: {:halt, update(socket, :open_menu, &toggle_menu(&1, :scope))}

  def handle_title_event("title_menu_close", _params, socket), do: {:halt, assign(socket, :open_menu, nil)}

  # A closed set, mapped explicitly: `String.to_existing_atom/1` would
  # depend on whether `DownloadScope` happens to be loaded yet.
  def handle_title_event("title_scope", %{"choice" => choice}, %{assigns: %{title_detail: %TitleDetail{}}} = socket)
      when choice in ~w(first_season everything) do
    scope = if choice == "everything", do: :everything, else: :first_season
    {:halt, assign(socket, download_scope: scope, open_menu: nil)}
  end

  # The main segment sends no mode (the person's default); the menu item
  # names the other one. A movie has one scope, so it sends none.
  def handle_title_event(
        "title_download",
        params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    mode =
      case params do
        %{"mode" => "auto_select_best_release"} -> :auto_select_best_release
        %{"mode" => "manually_select_release"} -> :manually_select_release
        _default -> detail.planning_mode
      end

    scope = if detail.scoped?, do: socket.assigns.download_scope, else: nil

    {:halt, socket |> assign(:open_menu, nil) |> start_download(detail.title, mode, scope)}
  end
```

Add, after the `handle_title_event/3` clauses:

```elixir
  defp toggle_menu(open, menu) when open == menu, do: nil
  defp toggle_menu(_open, menu), do: menu

  @doc """
  Performs a planning mode on a title (spec 2026-09-12 §5–7). Auto-select
  hands the plan to the supervised door (`Plans.plan_title/2`,
  `automatic`), flashes, and closes the modal when one is open. Manually
  selecting plans here under `start_async` (`Plans.create_title_plan/2`,
  `review`) and opens the plan's board on Incoming once it exists,
  through the host's `open_plan_board/2`; a failure flashes on the modal
  instead. A click while one is pending is a no-op. `scope` is nil for
  a movie. A download never moves the title's rung (ADR-066).
  """
  @spec start_download(
          Phoenix.LiveView.Socket.t(),
          Title.t(),
          PlanningMode.mode(),
          DownloadScope.scope() | nil
        ) :: Phoenix.LiveView.Socket.t()
  def start_download(%{assigns: %{download_pending: name}} = socket, _title, _mode, _scope)
      when not is_nil(name),
      do: socket

  def start_download(socket, %Title{} = title, :auto_select_best_release, scope) do
    :ok = Plans.plan_title(title, [approval_policy: "automatic"] ++ scope_opts(scope))

    socket = put_flash(socket, :info, download_flash(title.name))
    if socket.assigns.title_detail, do: push_close(socket), else: socket
  end

  def start_download(socket, %Title{} = title, :manually_select_release, scope) do
    opts = [approval_policy: "review"] ++ scope_opts(scope)
    name = {:title_download, Title.ref(title), title.name}

    socket
    |> assign(:download_pending, name)
    |> start_async(name, fn -> Plans.create_title_plan(title, opts) end)
  end

  defp scope_opts(nil), do: []
  defp scope_opts(scope), do: [scope: scope]
```

Add before the existing `handle_title_async({:title_preview, …})` clauses:

```elixir
  def handle_title_async({:title_download, _ref, _name}, {:ok, {:ok, plan}}, socket) do
    socket = assign(socket, download_pending: nil, open_menu: nil)
    {:halt, socket.view.open_plan_board(socket, plan.id)}
  end

  def handle_title_async({:title_download, _ref, name}, {:ok, {:error, reason}}, socket) do
    Log.warning(:acquisition, "could not plan — #{name} — #{inspect(reason)}")

    {:halt,
     socket
     |> assign(:download_pending, nil)
     |> put_flash(:error, plan_failure_flash(name, reason))}
  end

  def handle_title_async({:title_download, _ref, name}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "planning crashed — #{name} — #{inspect(reason)}")

    {:halt,
     socket
     |> assign(:download_pending, nil)
     |> put_flash(:error, plan_failure_flash(name, :crashed))}
  end
```

and near `download_flash/1`:

```elixir
  # The one remedy that matters, per cause: nothing to plan is a fact
  # about the library; anything else is TMDB's answer or its absence.
  defp plan_failure_flash(name, :nothing_to_plan),
    do: "Nothing to download for #{name}: every aired episode is already in your library or on its way."

  defp plan_failure_flash(name, _reason),
    do: "Couldn't plan #{name}. Check TMDB under Settings and try again."
```

Fix the moduledoc: the host contract table's `:handle_event` row lists the new events; `:handle_async` gains "and the manual plan (`{:title_download, ref, name}`) that opens its board"; the on_mount sentence says it seeds `:title_detail`, `:open_menu`, `:download_scope` and `:download_pending`; the "Beyond the `use`" list gains a third callback: "`open_plan_board/2` — navigates to Incoming with the plan's board open (`push_navigate` from another page, `push_patch` on Incoming itself)."

- [ ] **Step 7: The hosts' callbacks.** In `discovery_live.ex`, after `title_detail_path/2`:

```elixir
  @impl TitleDetailHost
  def open_plan_board(socket, plan_id), do: push_navigate(socket, to: "/incoming?plan=#{plan_id}")
```

In `incoming_live.ex`, after `title_detail_path/2`:

```elixir
  # The board is this page's own modal: a patch swaps the title detail
  # for it (`apply_plan_modal_params/2`).
  @impl TitleDetailHost
  def open_plan_board(socket, plan_id),
    do: push_patch(socket, to: incoming_path(socket, %{"plan" => plan_id}))
```

- [ ] **Step 8: The story.** In `title_detail_modal.story.exs` replace the `series_split` and `series_menu_open` variations with:

```elixir
      %Variation{
        id: :series_split,
        description:
          "A series: the split Download (main segment = the default planning mode, chevron " <>
            "for the other) and the scope select beside it, on Season 1.",
        attributes: %{today: @today, detail: detail(show(), %{})}
      },
      %Variation{
        id: :series_mode_menu_open,
        description: "The mode menu open: manual selection is the default, so it offers auto-select.",
        attributes: %{today: @today, detail: detail(show(), %{}), open_menu: :mode}
      },
      %Variation{
        id: :series_auto_default,
        description: "Auto-select as the default: the menu offers manual selection instead.",
        attributes: %{
          today: @today,
          detail: detail(show(), %{planning_mode: :auto_select_best_release}),
          open_menu: :mode
        }
      },
      %Variation{
        id: :series_scope_menu_open,
        description: "The scope menu open, Season 1 active, All seasons on offer.",
        attributes: %{today: @today, detail: detail(show(), %{}), open_menu: :scope}
      },
      %Variation{
        id: :series_all_seasons,
        description: "All seasons chosen: the select shows it; nothing else moves.",
        attributes: %{today: @today, detail: detail(show(), %{}), download_scope: :everything}
      },
      %Variation{
        id: :series_planning,
        description: "A manual plan is being created: the split is disabled and reads Planning…",
        attributes: %{today: @today, detail: detail(show(), %{}), download_pending?: true}
      },
```

and update the moduledoc sentence "a series Download is the split control" to "Download is the split control with the scope select beside it on a series". Because `open_menu` has `values: [nil, :mode, :scope]` and `download_scope` has `values: [:first_season, :everything]`, MC0009 needs every value string present in the story source — the variations above cover `mode`, `scope`, `everything`; `nil` and `first_season` appear in the descriptions/attributes already (check with `grep -c 'first_season' storybook/title/title_detail_modal.story.exs`; if 0, add `download_scope: :first_season` to the `series_split` attributes).

- [ ] **Step 9: Run everything touched**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/components/title`
Expected: PASS.
Run: `bun test --dots assets/js/`
Expected: PASS.

- [ ] **Step 10: Real browser.** Dev server on 2160 with a fresh `~/scripts/agents/agent-mix assets.build` if CSS changed. Open a watchlisted, released series' detail on Discovery in the visible browser and press Download once with the default mode: expect the board on Incoming. Then: `~/scripts/agents/mc-nav-trace --url 'http://127.0.0.1:2160/discovery/watchlist?title=tv_series-<id>' 'Right Right Right Left Left Enter Down Escape'` — expect: Right from Download lands on the chevron, then the scope trigger, then the bookmark; Enter on the chevron opens the mode menu; Down enters `title_detail_menu` (i/n = 0/1); Escape lands back in `title_detail_body` on the chevron with the menu gone. Fix anything that differs before committing.

- [ ] **Step 11: Commit**

```bash
git add lib/media_centaur_web/components/title/detail_modal.ex lib/media_centaur_web/live/title_detail_host.ex lib/media_centaur_web/live/discovery_live.ex lib/media_centaur_web/live/incoming_live.ex assets/js/input/config.js assets/js/input/__tests__/discovery_behavior.test.js storybook/title/title_detail_modal.story.exs test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/incoming_live_test.exs
git commit -m "feat(title): Download is a split button with the planning mode in its menu and the scope beside it

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 8: The feed row's Download follows the default mode

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live.ex` (`feed_download`, ~line 237)
- Test: `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Write the failing test.** Replace the test `"Download starts the automatic plan and flashes; the slot then reads the state"` with:

```elixir
    test "Download performs the default planning mode — manual selection opens the board", %{conn: conn} do
      stub_prowlarr()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-download") |> render_click()

      plan = eventually(fn -> List.first(Plans.list_drafts()) end)
      assert plan.approval_policy == "review"
      assert_redirect(view, "/incoming?plan=#{plan.id}")
    end

    test "Download under auto-select starts the automatic plan and flashes; the slot then reads the state",
         %{conn: conn} do
      stub_prowlarr()
      PlanningMode.set(:auto_select_best_release)
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-download") |> render_click()

      assert render(view) =~ "Finding a release for Sample Movie 777"
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review in the slot.
      render_until(view, fn _html ->
        has_element?(view, entry(rec) <> "[data-download-slot='Needs review']")
      end)

      refute has_element?(view, entry(rec) <> "-download")
    end
```

- [ ] **Step 2: Run to see the first one fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: the manual-selection test fails (the plan is `automatic`, no redirect).

- [ ] **Step 3: Implement.** In `discovery_live.ex` add `alias MediaCentaur.Settings.Preferences.PlanningMode` and replace the `feed_download` handler with:

```elixir
  # The row's plain Download performs the default planning mode on the
  # default scope (season 1 for a series); the full control is in the
  # modal. The host owns the two paths (TitleDetailHost.start_download/4).
  def handle_event("feed_download", %{"activity" => id}, socket) do
    case feed_entry(socket, id) do
      %FeedEntry{download_slot: :download} = entry ->
        scope = if entry.title.media_type == :tv_series, do: :first_season, else: nil
        {:noreply, TitleDetailHost.start_download(socket, entry.title, PlanningMode.value(), scope)}

      _state_or_unknown ->
        {:noreply, socket}
    end
  end
```

Remove the now-unused `Plans` alias from `discovery_live.ex` if nothing else in the file uses it (`grep -n 'Plans\.' lib/media_centaur_web/live/discovery_live.ex`).

- [ ] **Step 4: Run the file**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/discovery_live.ex test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat(discovery): the feed row's Download performs the default planning mode

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 9: Settings — the "Download button" card

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/acquisition_section.ex`
- Modify: `lib/media_centaur_web/live/settings_live.ex` (the acquisition `section_content/1` and a handler)
- Test: `test/media_centaur_web/live/settings_live_acquisition_test.exs`

- [ ] **Step 1: Write the failing tests.** Append a describe to `settings_live_acquisition_test.exs`:

```elixir
  describe "download button — default planning mode" do
    alias MediaCentaur.Settings.Preferences.PlanningMode

    setup do
      Config.update(:prowlarr_url, "http://prowlarr.test")
      Config.update(:prowlarr_api_key, "test-key")
      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    test "defaults to manual selection and persists a change", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      assert has_element?(view, "#settings-planning-mode option[value='manually_select_release'][selected]")

      view
      |> form("#settings-download-button", %{planning_mode: "auto_select_best_release"})
      |> render_change()

      assert PlanningMode.value() == :auto_select_best_release
      assert has_element?(view, "#settings-planning-mode option[value='auto_select_best_release'][selected]")
    end

    test "the card is hidden until Prowlarr is ready", %{conn: conn} do
      Config.update(:prowlarr_url, nil)
      Config.update(:prowlarr_api_key, nil)

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      refute has_element?(view, "#settings-download-button")
    end
  end
```

- [ ] **Step 2: Run to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_acquisition_test.exs`
Expected: the first fails on `#settings-planning-mode` not found.

- [ ] **Step 3: The section.** In `acquisition_section.ex` add `alias MediaCentaur.Settings.Preferences.PlanningMode` and `alias MediaCentaurWeb.Components.Title.Logic`; add the attr

```elixir
  attr :planning_mode, :atom,
    required: true,
    values: [:manually_select_release, :auto_select_best_release],
    doc: "the Download button's default planning mode (`Settings.Preferences.PlanningMode`)"
```

render the card before the auto-grab defaults: `<.download_button_card :if={@prowlarr_ready} planning_mode={@planning_mode} />`, and add the component after `release_tracking_form/1`:

```elixir
  attr :planning_mode, :atom, required: true, values: [:manually_select_release, :auto_select_best_release]

  # The Download button on a title the library does not own (Discovery,
  # Incoming) performs this mode; its menu carries the other one. The
  # words are `Title.Logic.planning_mode_label/1`'s — the same ones the
  # menu shows. Saves on change; the select is the state.
  defp download_button_card(assigns) do
    ~H"""
    <form
      id="settings-download-button"
      phx-change="set_planning_mode"
      class="p-5 rounded-lg glass-surface space-y-5"
    >
      <div class="min-w-0">
        <h2 class="text-lg font-semibold">Download button</h2>
        <p class="text-sm text-base-content/55 mt-0.5">On a title you don't own yet.</p>
      </div>

      <div>
        <label
          for="settings-planning-mode"
          class="text-xs font-medium uppercase tracking-wider text-base-content/55 block mb-1.5"
        >
          Default planning mode
        </label>
        <select
          id="settings-planning-mode"
          name="planning_mode"
          class="select select-bordered w-full"
          data-nav-item
          tabindex="0"
        >
          <option :for={mode <- PlanningMode.modes()} value={mode} selected={mode == @planning_mode}>
            {Logic.planning_mode_label(mode)}
          </option>
        </select>
        <p class="text-xs text-base-content/55 mt-1">
          The button's main action. The other choice is in its menu.
        </p>
      </div>
    </form>
    """
  end
```

Update the section moduledoc's first sentence to include "the Download button's default planning mode".

- [ ] **Step 4: The LiveView.** In `settings_live.ex`: add `PlanningMode` to the `alias MediaCentaur.Settings.Preferences.{…}` line; in the acquisition `section_content/1` add `planning_mode: PlanningMode.value()` to the `assign(assigns, …)` call and `planning_mode={@planning_mode}` to `<AcquisitionSection.render …>`; add next to `save_auto_grab_defaults`:

```elixir
  def handle_event("set_planning_mode", %{"planning_mode" => mode}, socket)
      when mode in ~w(manually_select_release auto_select_best_release) do
    PlanningMode.set(PlanningMode.parse(%{"mode" => mode}))
    {:noreply, socket}
  end
```

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_acquisition_test.exs test/media_centaur_web/live/settings_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/settings_live/acquisition_section.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur_web/live/settings_live_acquisition_test.exs
git commit -m "feat(settings): Download button card — the default planning mode

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 10: The library sort control converges on `menu_select`

**Files:**
- Modify: `lib/media_centaur_web/components/library_cards.ex` (the toolbar, ~lines 145-225, 257)
- Modify: `lib/media_centaur_web/live/library_live.ex` (mount seed ~line 84, sort handlers ~146-170, `sort_key/2` ~604-644, toolbar call ~368-374)
- Modify: `assets/js/input/config.js` (selector, instance type, library layout)
- Modify: `storybook/library_cards/toolbar.story.exs`
- Test: `test/media_centaur_web/live/library_live_test.exs`, `assets/js/input/__tests__/library_behavior.test.js`

- [ ] **Step 1: Write the failing tests.** In `library_live_test.exs`, in the `describe "sort=watched"` block after the "selecting Recently Watched…" test:

```elixir
    test "the sort menu is a nav zone that closes itself on BACK, with no private keyboard model",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      refute has_element?(view, "[phx-keydown='sort_key']")
      refute has_element?(view, "#library-sort-menu")

      view |> element("#library-sort") |> render_click()

      assert has_element?(
               view,
               "#library-sort-menu[data-nav-zone='library_sort_menu'][data-nav-dismiss-event='close_sort']"
             )

      assert has_element?(view, "#library-sort-recent.glass-menu-item-active", "Recently Added")

      render_hook(view, "close_sort", %{})
      refute has_element?(view, "#library-sort-menu")
    end
```

In `library_behavior.test.js` add (importing `inputConfig` from `"../config.js"` and `Context` from `"../core/index.js"` at the top if not already):

```js
  test("the sort menu is a TREE under the toolbar: DOWN enters it, UP and BACK leave for the toolbar", () => {
    expect(inputConfig.contextSelectors.library_sort_menu).toBe("[data-nav-zone='library_sort_menu'] [data-nav-item]")
    expect(inputConfig.instanceTypes.library_sort_menu).toBe(Context.TREE)
    expect(inputConfig.layouts.library).toEqual({
      toolbar:           { down: ["library_sort_menu", "grid"] },
      library_sort_menu: { up: ["toolbar"], back: ["toolbar"] },
      grid:              { up: ["toolbar"], right: ["drawer"] },
      sidebar:           { right: ["grid", "toolbar"] },
      drawer:            { left: ["grid", "toolbar"] },
    })
  })
```

- [ ] **Step 2: Run to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/library_live_test.exs` and `bun test assets/js/input/__tests__/library_behavior.test.js`
Expected: both new tests fail.

- [ ] **Step 3: Config.** In `config.js`: add the selector `library_sort_menu: "[data-nav-zone='library_sort_menu'] [data-nav-item]",` after the `[Context.TOOLBAR]` selector; add `library_sort_menu: Context.TREE,` to `instanceTypes` with the comment `// The library sort menu, present only while open: a short list under the toolbar's Sort trigger.`; replace the `library` layout with:

```js
    library: {
      toolbar:           { down: ["library_sort_menu", "grid"] },
      // The open sort menu, nested in the toolbar: BACK leaves it for the
      // toolbar and, through its `data-nav-dismiss-event`, closes it.
      library_sort_menu: { up: ["toolbar"], back: ["toolbar"] },
      grid:              { up: ["toolbar"], right: ["drawer"] },
      sidebar:           { right: ["grid", "toolbar"] },
      drawer:            { left: ["grid", "toolbar"] },
    },
```

- [ ] **Step 4: The toolbar.** In `library_cards.ex`: add `alias MediaCentaurWeb.Components.GlassMenu`; change the `@sort_options` comment to `# The menu's order. \`LibraryLive.@sort_options\` lists the same values for parsing the URL.`; remove `attr :sort_highlight, :integer, required: true`; replace the sort `<div class="glass-menu" …>…</div>` block with:

```heex
        <GlassMenu.menu_select
          id="library-sort"
          open={@sort_open}
          on_toggle="toggle_sort"
          on_close="close_sort"
          menu_zone="library_sort_menu"
          value_label={sort_label(@sort_order)}
          label="Sort"
          data-sort={@sort_order}
        >
          <:item
            :for={{value, label} <- @sort_options}
            id={"library-sort-" <> Atom.to_string(value)}
            event="sort"
            values={%{"sort" => Atom.to_string(value)}}
            active={@sort_order == value}
          >
            {label}
          </:item>
        </GlassMenu.menu_select>
```

- [ ] **Step 5: The LiveView.** In `library_live.ex`: remove `sort_highlight: 0,` from the mount assigns; replace the `toggle_sort` handler with `def handle_event("toggle_sort", _params, socket), do: {:noreply, update(socket, :sort_open, &(!&1))}`; delete the `"sort_key"` handler and every `sort_key/2` clause plus the `# --- Sort Dropdown Keyboard ---` comment; remove `sort_highlight={@sort_highlight}` from the toolbar call. Keep `@sort_options` if `parse_sort/1` uses it (it does).

- [ ] **Step 6: The story.** In `toolbar.story.exs`: drop `sort_highlight` from the contract shape in the moduledoc and from `base_attrs/1` defaults; replace the `:sort_open` VariationGroup with one variation:

```elixir
      %Variation{
        id: :sort_open,
        description: "Sort dropdown open — the current order (`:recent`) is the active item.",
        attributes: base_attrs(sort_order: :recent, sort_open: true)
      },
```

and reword the "Variation matrix" bullet to "Sort dropdown states — closed (showing each `sort_order` label) and open."

- [ ] **Step 7: Run**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS.
Run: `bun test --dots assets/js/`
Expected: PASS (config coverage now resolves `library_sort_menu` through `menu_zone=`).

- [ ] **Step 8: Real browser.** `~/scripts/agents/mc-nav-trace --url 'http://127.0.0.1:2160/library' 'Right Right Right Enter Down Down Escape'` — expect Right along the tabs onto Sort (`toolbar`, the trigger), Enter opens it, Down enters `library_sort_menu` at 0/4, Down to 1/4, Escape lands on the Sort trigger in `toolbar` with the menu gone. Then by mouse: open Sort, pick Year, see the grid re-sort and the URL carry `?sort=year`. If the trace or the click fails and the cause is not a one-line fix, revert this task alone (`git checkout -- <files>`) and note in the spec's Coherence pass that the convergence stays scheduled and why.

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur_web/components/library_cards.ex lib/media_centaur_web/live/library_live.ex assets/js/input/config.js storybook/library_cards/toolbar.story.exs test/media_centaur_web/live/library_live_test.exs assets/js/input/__tests__/library_behavior.test.js
git commit -m "refactor(library): the sort control is a GlassMenu.menu_select — private keyboard model retired

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 11: Documentation — spec amendment, glossary, input-system doc, moduledoc, wiki

**Files:**
- Modify: `docs/superpowers/specs/2026-09-05-one-click-download-design.md` (append an amendment)
- Modify: `docs/GLOSSARY.md`
- Modify: `docs/input-system.md`
- Modify: `lib/media_centaur/acquisition/plans/plan.ex` (moduledoc approval paragraph)
- Modify (wiki repo `~/src/media-centaur/media-centaur.wiki/`): `Settings-Reference.md`, `Searching-and-Downloading.md`, `Social.md`, `Watchlist.md`, `Keyboard-and-Gamepad.md`

- [ ] **Step 1: One-click spec amendment.** Append to `2026-09-05-one-click-download-design.md`:

```markdown

## Amendment (2026-09-12) — superseded in part by the download button default action spec

`2026-09-12-download-button-default-action-design.md` replaces decisions 7, 10 and 17 of this spec: the Download control is a `GlassMenu.split_button` whose main segment performs the person's default planning mode (`Settings.Preferences.PlanningMode`, default *manually select release*) and whose menu names the other; the series scope moved out of the menu into a `GlassMenu.menu_select` beside the button; the manual path plans synchronously (`Plans.create_title_plan/2`) under `start_async` and opens the plan board on Incoming. The scheduled convergence of the library sort control onto nav items (the amendment to decision 10) is done. The approval policy column, the gate and the clean-plan rule stand as decided here.
```

- [ ] **Step 2: Glossary.** In `docs/GLOSSARY.md`:
  - Approval policy row: replace "…(the picker and plan-now as `review`, one-click downloads as `automatic`)…" — wherever the row says who stamps what — with "the picker and Plan now as `review`; the Download button as its planning mode says: auto-select `automatic`, manual selection `review`".
  - Download scope row: append " Chosen by the scope select beside a series' Download button (`GlassMenu.menu_select`, Season 1 or All seasons)."
  - Add after Download scope: `| **Planning mode** | What the Download button on a title the library does not own does when pressed: *auto-select best release* (\`:auto_select_best_release\`, approval policy \`automatic\`: a clean plan commits with nobody looking, anything else parks on Incoming) or *manually select release* (\`:manually_select_release\`, approval policy \`review\`: the plan is created and its board opens on Incoming). The person's default is \`Settings.Preferences.PlanningMode\` (key \`default_planning_mode\`, default manual); the button's menu offers the other. The mapping to a policy lives in \`TitleDetailHost.start_download/4\`. |`
  - In the UI section, add rows: `| **Glass menu** | The house dropdown idiom (\`.glass-menu*\`): a trigger with a chevron and an anchored glass list beneath it, open state owned by the LiveView. \`MediaCentaurWeb.Components.GlassMenu\` renders it: \`menu_list/1\` (the list, its own nav zone carrying \`data-nav-dismiss-event\`), \`split_button/1\` (a main segment that performs an action plus a chevron), \`menu_select/1\` (a trigger showing the current value). Tenants: the title detail modal's Download control and scope select, the library sort control. |`
  - Nav zone row (in Input system section, "Zone"): append "Zones may nest: an item counts once, for its nearest zone (`dom_adapter.js` \`ownedByScope\`). A zone may carry \`data-nav-dismiss-event\`, the event BACK pushes when it leaves the zone along its \`back\` edge — how a menu list closes itself."

- [ ] **Step 3: Input-system doc.** In `docs/input-system.md`:
  - Replace the paragraph `**Nav zone containers must not nest.** …` with: `**A zone may contain a zone; an item counts once, for its nearest zone.** The adapter's item query (\`queryContextItems\`) drops any item whose nearest \`[data-nav-zone]\` ancestor is a different zone nested inside the context's scope element, so an outer zone's descendant selector never double-counts a menu list opened inside it. The glass menu (\`GlassMenu.menu_list\`) relies on this.`
  - Add to the attribute table after `data-nav-overlay`: `| \`data-nav-dismiss-event\` | On a zone container: the LiveView event BACK pushes when it leaves the zone along its \`back\` edge — a menu list closes itself this way | \`title_menu_close\`, \`close_sort\` |`
  - In the BACK section, rung 1: append " — and, when the region's container declares \`data-nav-dismiss-event\`, that event is pushed as the cursor leaves, so a menu list closes as BACK backs out of it. The rung is not overlay-only: a page layout may give a zone a \`back\` edge too (the library sort menu)."
  - In the overlays paragraph describing `title_detail` (search for `title_detail_menu`), say the menu is "whichever Download menu is open — the other planning mode, or the scope — a `title_detail_menu` TREE nested inside the strip with `up` and `back` to it". Add a sentence to the library layout description (search for `layouts.library` or the library page section) naming `library_sort_menu`.

- [ ] **Step 3b: The input-system skill.** `.claude/skills/input-system/SKILL.md` repeats the old rule under its Design Rules (search for "must not nest"). Replace that rule with the same sentence as the doc: "A zone may contain a zone; an item counts once, for its nearest zone. A zone may declare `data-nav-dismiss-event`, the event BACK pushes when it leaves the zone along its `back` edge — a menu list closes itself this way." Commit it with the app docs (Step 6).

- [ ] **Step 4: Plan schema moduledoc.** In `lib/media_centaur/acquisition/plans/plan.ex` change "the picker and plan-now as `review`, one-click downloads as `automatic`" to "the picker and Plan now as `review`; the Download button as its planning mode says — auto-select `automatic`, manual selection `review` (`TitleDetailHost.start_download/4`)".

- [ ] **Step 5: Wiki.** In `~/src/media-centaur/media-centaur.wiki/`:

`Settings-Reference.md`, insert before `**Auto-acquisition defaults**`:

```markdown
**Download button** (shown once Prowlarr's test passes)

What the **Download** button does on a title you don't own yet — on the Discovery page's title view and on Incoming. The button performs this mode; its menu carries the other one.

- **Default planning mode**
  - *Manually select release* (default) — the search runs and its plan opens on Incoming, where you swap releases, exclude episodes, and approve.
  - *Auto-select best release* — a clean plan (every episode found at your quality preference) starts downloading without asking; anything that needs a decision parks on Incoming.
```

`Searching-and-Downloading.md`, replace the paragraph beginning "Drafts also arrive from one-click downloads…" with:

```markdown
Drafts also arrive from **Download** on the [Watchlist](Watchlist#what-happens-after-download), [Feed](Social#feed) and [Friends](Social#friends) tabs. Under the default planning mode (*Manually select release*) the plan opens here as soon as the search has started, with the same board to steer it. Under *Auto-select best release* (Settings → Acquisition → Download button) a clean plan commits itself and parks here only when something needs your decision. Whenever a draft is waiting, the **Incoming** entry in the sidebar shows the count — the same pill the Review and Status entries use for things waiting on you. It stays until you approve or discard the draft.
```

`Social.md`, the `**Download**` table row: "The Download button — performs your default planning mode (Settings → Acquisition → Download button), season 1 for a series; the title view's chevron offers the other mode and a scope select. Reads **Downloading**, **Planning** or **Needs review** while a plan is running, **In library** when you own the title."

`Watchlist.md`, replace the body of `## What happens after Download` with:

```markdown
**Download** performs your default planning mode. With *Manually select release* (the default) the view closes and you land on the plan's board on Incoming, where you watch the search, swap releases, exclude episodes, and approve. With *Auto-select best release* the view closes, a search starts in the background, and a clean result — every wanted episode, or the movie, found at your quality preference — starts the download without asking; anything that needs a decision parks as a draft on [Downloads](Searching-and-Downloading#download-plans), the row reads **Needs review**, and the **Incoming** entry in the sidebar shows how many are waiting. The chevron beside **Download** offers the other mode for this one download. On a series, the select beside the button chooses **Season 1** or **All seasons**. Rows update on their own as the search runs and when the file lands. Set the default under Settings → Acquisition → Download button.
```

`Keyboard-and-Gamepad.md`, in "In the Discovery title view", replace the sentence beginning "On a series, **Enter** / A on the chevron beside **Download season 1**…" with: "**Enter** / A on the chevron beside **Download** opens its menu (the other planning mode); on a series **Enter** / A on the scope select beside it (**Season 1**) opens the scope menu. **Down** enters an open menu, **Up** returns to the row, and `Esc` / B closes the menu and puts the cursor back on the row; a second `Esc` / B closes the view." Add under the Library section (create a short `### Library toolbar` if none exists): "**Enter** / A on **Sort** opens its menu; **Down** enters it, **Up** returns to the toolbar, `Esc` / B closes it and returns to Sort."

Then commit the wiki:

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Download button default planning mode, split button and scope select, sort menu keys" && cd -
```

(Do not push the wiki or the app; the owner pushes.)

- [ ] **Step 6: Commit the app docs**

```bash
git add docs/superpowers/specs/2026-09-05-one-click-download-design.md docs/GLOSSARY.md docs/input-system.md .claude/skills/input-system/SKILL.md lib/media_centaur/acquisition/plans/plan.ex
git commit -m "docs: planning mode, glass menu, nested zones and BACK-dismiss — glossary, input-system, spec amendment

Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV"
```

---

### Task 12: Precommit and verification

- [ ] **Step 1: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: format, credo, boundaries, audit, sobelow and the whole test suite pass with zero warnings. Fix anything it reports and amend the relevant task's commit or add a `fix:` commit.

- [ ] **Step 2: Real browser pass** (the dev server on 2160 is the daily driver; rebuild assets with `~/scripts/agents/agent-mix assets.build` if CSS or JS changed and the server has not picked it up):
  - Settings → Acquisition: the Download button card shows, the select persists across a reload.
  - Discovery → a released, watchlisted series' title view: split Download + scope select; the chevron menu names the other mode; Download opens the board on Incoming; back on Discovery with auto-select set, Download flashes and closes.
  - `mc-nav-trace` on the title view and on the library toolbar as written in Tasks 7 and 10.
  - `page-shot` the title view at 1920x1080 and Read it: the split button reads as one control with a hairline divider; the scope select is the quiet ghost trigger beside it; nothing wraps oddly.

- [ ] **Step 3: Report.** State plainly what was verified and how, what was not, and the one open owner check: the look of the split button and scope select on the TV shell.
