# Discovery Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Watchlist page becomes the Discovery page (`/discovery/watchlist`) with a shared tab strip, gated by a renamed `show_discovery` preference — the surface the Feed and Friends tabs land on next.

**Architecture:** One generic `tab_strip/1` component (extracted from `review_tabs`, which becomes a thin composition over it) renders navigation tabs with counts inside a `zone-tabs` nav zone. `WatchlistVisibility` becomes `DiscoveryVisibility` (`show_discovery`), with a data migration renaming the stored settings row. `WatchlistLive` becomes `DiscoveryLive` mounted at `/discovery/watchlist` (the only tab for now; `/discovery` arrives with the Feed in a later layer). The JS page behavior and nav-zone layout are renamed to `discovery`, mirroring the Review page's tab-strip layout.

**Tech Stack:** Phoenix LiveView, Phoenix Storybook (MC0009), `MediaCentaur.Settings.Preferences.BooleanSetting`, data migrations (ADR-040), the input system (`assets/js/input/config.js`, `page_behavior.js`; asset watchers are OFF — run `mix assets.build` after JS edits), bun tests.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — unification decisions 7 (feature gate rename) and 8 (shared tab strip); UI section (Discovery page). Layer 1b; layer 1a (title convergence) already landed.

**House rules that bite here:** test-first; zero warnings; no real titles in fixtures; every function component under `lib/media_centaur_web/components/**` has a story (MC0009); loose attr types carry `doc:` (MC0008); no row mutation in schema migrations (MC0015) — the settings-key rename is a data migration; user-facing copy in the house voice (plain, reader-first, no "simply"); commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

**Decisions fixed by this plan (do not re-open):**
- `/discovery/watchlist` is the only route in this layer; the sidebar entry navigates to it. `/discovery` (Feed) and `/discovery/friends` arrive with their layers. No redirect scaffolding.
- The old `/watchlist` route is removed (no compatibility alias).
- The tab strip renders even with one tab: it is the section header the next tabs join.
- Sidebar entry: label "Discovery", icon `hero-sparkles`, tooltip "Discovery".
- Copy (house voice): Settings row label **Discovery**, description **"Show the Discovery page in the sidebar. Early preview — it may still change shape."** Page heading **Discovery**. Tab label **Watchlist** with the item count as its badge. Empty state unchanged.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `lib/media_centaur_web/components/tab_strip.ex` | `tab_strip/1` + `TabStrip.Tab` struct |
| Modify | `lib/media_centaur_web/components/review_tabs.ex` | composes over `tab_strip` |
| Create | `storybook/navigation/_navigation.index.exs`, `storybook/navigation/tab_strip.story.exs` | story (MC0009) |
| Create | `test/media_centaur_web/components/tab_strip_test.exs` | |
| Rename | `lib/media_centaur/settings/preferences/watchlist_visibility.ex` → `discovery_visibility.ex` | `show_discovery` |
| Modify | `lib/media_centaur/settings/preferences.ex` | export |
| Create | `priv/repo/data_migrations/20260902150000_rename_show_watchlist_settings_key.exs` + test | settings row rename |
| Modify | `lib/media_centaur_web/router.ex`, `lib/media_centaur_web/components/layouts.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/preferences.ex`, and every LiveView passing `show_watchlist` to `Layouts.app` | assign rename |
| Rename | `lib/media_centaur_web/live/watchlist_live.ex` → `discovery_live.ex` | `DiscoveryLive`, `/discovery/watchlist`, heading + tab strip |
| Rename | `assets/js/input/watchlist_behavior.js` → `discovery_behavior.js`, its `__tests__` file; modify `page_behavior.js`, `config.js` | page behavior + zone layout |
| Rename | `test/media_centaur_web/live/watchlist_live_test.exs` → `discovery_live_test.exs`; modify `home_live_test.exs`, `settings_live_test.exs`, `page_smoke_test.exs`, `no_db_on_render_test.exs` | |
| Modify | wiki `Watchlist.md`, `Settings-Reference.md`; `docs/input-system.md` if it lists page behaviors; `campaigns/friends-recommendations.md` | docs |

---

### Task 1: `tab_strip` component; `review_tabs` composes over it

**Files:**
- Create: `lib/media_centaur_web/components/tab_strip.ex`
- Modify: `lib/media_centaur_web/components/review_tabs.ex`
- Create: `storybook/navigation/_navigation.index.exs`, `storybook/navigation/tab_strip.story.exs`
- Test: `test/media_centaur_web/components/tab_strip_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaurWeb.Components.TabStripTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.TabStrip
  alias MediaCentaurWeb.Components.TabStrip.Tab

  defp tabs do
    [
      %Tab{id: :first, label: "First", navigate: "/first", count: 3},
      %Tab{id: :second, label: "Second", navigate: "/second"}
    ]
  end

  test "renders one link per tab, marks the active one, and badges non-zero counts" do
    html = render_component(&TabStrip.tab_strip/1, tabs: tabs(), active: :second)

    assert html =~ ~s(href="/first")
    assert html =~ ~s(href="/second")
    assert html =~ "First"
    assert html =~ "Second"
    # the count badge renders only for the tab that has work
    assert html =~ ">3<"
    # exactly one active tab
    assert length(Regex.scan(~r/zone-tab-active/, html)) == 1
  end

  test "the strip is one zone-tabs nav zone of nav items" do
    html = render_component(&TabStrip.tab_strip/1, tabs: tabs(), active: :first)

    assert html =~ ~s(data-nav-zone="zone-tabs")
    assert length(Regex.scan(~r/data-nav-item/, html)) == 2
  end
end
```

Read `credo_checks/no_markup_substring_assertion.ex` (MC0024) first: it forbids substring assertions on `data-`/`phx-` attribute names and `class=`/`id=` literals in tests. The `data-nav-zone` / `data-nav-item` assertions above may trip it — if so, rewrite those two assertions with `Floki` (`Floki.find(html, "[data-nav-zone=zone-tabs] [data-nav-item]") |> length() == 2`) or whatever the check's moduledoc prescribes, and the `zone-tab-active` count via `Floki.find(html, ".zone-tab-active")`.

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/media_centaur_web/components/tab_strip_test.exs`
Expected: compile error — `MediaCentaurWeb.Components.TabStrip` undefined.

- [ ] **Step 3: Write the component**

`lib/media_centaur_web/components/tab_strip.ex`:

```elixir
defmodule MediaCentaurWeb.Components.TabStrip do
  @moduledoc """
  Tab strip joining sibling pages that share one sidebar entry — Review's
  identity and episode-mapping pages, Discovery's watchlist (and, later,
  feed and friends). Each tab is a navigation link to a page, not in-page
  state, and may carry a pending count.

  One `zone-tabs` nav zone; the host page declares where the strip sits
  in its layout in `assets/js/input/config.js` (see the `review` entry).
  """

  use MediaCentaurWeb, :html

  defmodule Tab do
    @moduledoc """
    One tab. `id` is what `active` matches; `navigate` is the page it
    opens; `count` is the badge (hidden at 0).
    """
    @enforce_keys [:id, :label, :navigate]
    defstruct [:id, :label, :navigate, count: 0]

    @type t :: %__MODULE__{
            id: atom(),
            label: String.t(),
            navigate: String.t(),
            count: non_neg_integer()
          }
  end

  attr :tabs, :list, required: true, doc: "`Tab.t()` in display order"
  attr :active, :atom, required: true, doc: "the `Tab` id of the page rendering the strip"

  def tab_strip(assigns) do
    ~H"""
    <div data-nav-zone="zone-tabs" class="flex items-baseline gap-5">
      <.link
        :for={tab <- @tabs}
        navigate={tab.navigate}
        class={["zone-tab", @active == tab.id && "zone-tab-active"]}
        data-nav-item
        tabindex="0"
      >
        {tab.label}
        <.badge :if={tab.count > 0} variant="ghost" size="xs" class="ml-1">
          {tab.count}
        </.badge>
      </.link>
    </div>
    """
  end
end
```

- [ ] **Step 4: `review_tabs` composes over it**

Replace the body of `lib/media_centaur_web/components/review_tabs.ex` (keep its moduledoc and attrs) so `review_tabs/1` builds the two tabs and renders `tab_strip`:

```elixir
  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]

  alias MediaCentaurWeb.Components.TabStrip.Tab

  # …existing attrs unchanged…

  def review_tabs(assigns) do
    assigns =
      assign(assigns, :tabs, [
        %Tab{id: :identity, label: "Identity", navigate: "/review", count: assigns.identity_count},
        %Tab{id: :mapping, label: "Episode mapping", navigate: "/reconcile", count: assigns.mapping_count}
      ])

    ~H"""
    <.tab_strip tabs={@tabs} active={@active} />
    """
  end
```

Update its moduledoc's last sentence to say it is a composition over `TabStrip` naming the review dimensions. The existing `storybook/review/review_tabs.story.exs` stays as is.

- [ ] **Step 5: Story**

`storybook/navigation/_navigation.index.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Navigation do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "signs-post", :light, "psb:mr-1"}

  def entry("tab_strip"), do: [icon: {:fa, "folder-tree", :thin}, name: "Tab strip"]
end
```

`storybook/navigation/tab_strip.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Navigation.TabStrip do
  @moduledoc """
  The generic tab strip joining sibling pages under one sidebar entry.
  Tabs are page links with an optional pending count; the active tab is
  the page rendering the strip. Review and Discovery both render this.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.TabStrip.Tab

  def function, do: &MediaCentaurWeb.Components.TabStrip.tab_strip/1
  def render_source, do: :function

  defp tabs do
    [
      %Tab{id: :feed, label: "Feed", navigate: "#", count: 2},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "#", count: 7},
      %Tab{id: :friends, label: "Friends", navigate: "#"}
    ]
  end

  def variations do
    [
      %Variation{
        id: :three_tabs,
        description: "Three sibling pages; counts badge the tabs with work, the active one is underlined.",
        attributes: %{tabs: tabs(), active: :watchlist}
      },
      %Variation{
        id: :single_tab,
        description: "One tab — the strip still renders as the section header the next tabs join.",
        attributes: %{tabs: Enum.take(tabs(), 1), active: :feed}
      },
      %Variation{
        id: :no_counts,
        description: "All counts at zero — no badges.",
        attributes: %{tabs: Enum.map(tabs(), &%{&1 | count: 0}), active: :friends}
      }
    ]
  end
end
```

Check `storybook/review/_review.index.exs` for the index conventions and mirror them if anything above differs.

- [ ] **Step 6: Verify**

Run: `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/components/tab_strip_test.exs test/media_centaur_web/live/review_live_test.exs test/media_centaur_web/live/reconcile_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs && mix credo --strict`
(Adjust the review/reconcile test filenames to what exists: `ls test/media_centaur_web/live | grep -i "review\|reconcile"`.)
Expected: pass, no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/components/tab_strip.ex lib/media_centaur_web/components/review_tabs.ex storybook/navigation test/media_centaur_web/components/tab_strip_test.exs
git commit -m "feat(web): tab_strip — the shared page-tab strip; review_tabs composes over it

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 2: `show_discovery` preference (rename + settings-row migration)

**Files:**
- Rename: `lib/media_centaur/settings/preferences/watchlist_visibility.ex` → `lib/media_centaur/settings/preferences/discovery_visibility.ex`
- Modify: `lib/media_centaur/settings/preferences.ex`
- Create: `priv/repo/data_migrations/20260902150000_rename_show_watchlist_settings_key.exs`
- Create: `test/media_centaur/repo/data_migrations/rename_show_watchlist_settings_key_test.exs`
- Modify: `lib/media_centaur_web/router.ex`, `lib/media_centaur_web/components/layouts.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/preferences.ex`, and the `show_watchlist={@show_watchlist}` line in each of: `apps_live.ex`, `guide_live.ex`, `home_live.ex`, `incoming_live.ex`, `library_live.ex`, `reconcile_live.ex`, `review_live.ex`, `settings_live.ex` (three places), `status_live.ex`, `watch_history_live.ex`, `watchlist_live.ex`
- Tests: `test/media_centaur_web/live/settings_live_test.exs`, `test/media_centaur_web/live/home_live_test.exs`, `test/media_centaur_web/no_db_on_render_test.exs` (comments), `test/media_centaur/data_migrations_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/media_centaur/repo/data_migrations/rename_show_watchlist_settings_key_test.exs`, mirroring `rename_watch_dirs_settings_key_test.exs`:

```elixir
defmodule MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKeyTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKey
  alias MediaCentaur.Settings

  @legacy_key "show_watchlist"
  @current_key "show_discovery"

  defp insert_entry(key, enabled) do
    {:ok, _} = Settings.find_or_create_entry(%{key: key, value: %{"enabled" => enabled}})
  end

  defp value_for(key) do
    case Settings.get_by_key(key) do
      %{value: value} -> value
      _ -> nil
    end
  end

  describe "rename_key/1" do
    test "renames the legacy key, preserving the value" do
      insert_entry(@legacy_key, true)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => true}
      assert value_for(@legacy_key) == nil
    end

    test "is idempotent" do
      insert_entry(@legacy_key, true)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)
      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => true}
      assert value_for(@legacy_key) == nil
    end

    test "no-op when no legacy key exists" do
      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)
      assert value_for(@current_key) == nil
    end

    test "keeps the current key and drops the legacy one when both exist" do
      insert_entry(@legacy_key, true)
      insert_entry(@current_key, false)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => false}
      assert value_for(@legacy_key) == nil
    end
  end
end
```

Confirm the stored key has no prefix: `WatchlistVisibility.setting_key()` returns `"show_watchlist"` and `home_live_test.exs` writes `key: ...setting_key()` directly. If `Settings.get_by_key/1` uses the `:persistent_term` cache, the test may need to read through `Settings` after the raw SQL update — the rename_watch_dirs test does exactly this and passes, so mirror it; if a stale cache shows the old value, look at how `Settings` invalidates on write and use the same call the sibling test uses.

Update `test/media_centaur_web/live/settings_live_test.exs`: alias `DiscoveryVisibility` instead of `WatchlistVisibility`; the toggle element becomes `div[phx-click=toggle_show_discovery]`; assertions on `DiscoveryVisibility.enabled?()`.

Update `test/media_centaur_web/live/home_live_test.exs` describe "watchlist sidebar entry" → "discovery sidebar entry": hrefs become `/discovery/watchlist`; the settings write uses `DiscoveryVisibility.setting_key()`; the comment names `"show_discovery"`.

Add to `test/media_centaur/data_migrations_test.exs` a directory test for `"20260902150000_rename_show_watchlist_settings_key.exs"` next to the others.

Run those three files: expected failures — module undefined, element not found.

- [ ] **Step 2: The preference module**

`git mv lib/media_centaur/settings/preferences/watchlist_visibility.ex lib/media_centaur/settings/preferences/discovery_visibility.ex` and make it:

```elixir
defmodule MediaCentaur.Settings.Preferences.DiscoveryVisibility do
  @moduledoc """
  Typed accessor for the `show_discovery` Settings entry.

  Controls whether the Discovery page surfaces at all: the sidebar entry,
  the detail modal's bookmark toggle, and the Incoming search rows'
  bookmark. Default-**off**: Discovery is a work-in-progress feature
  expected to change shape, so it stays out of everyone's UI until a
  user opts in via Settings → Preferences. `/discovery/watchlist` stays
  reachable by URL. The Discovery context underneath is unaffected —
  items already on the watchlist are kept, just not shown.

  Renamed from `show_watchlist` on 2026-09-02 (data migration
  `RenameShowWatchlistSettingsKey`) when the Watchlist page became the
  Discovery page.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_discovery", default: false
end
```

`lib/media_centaur/settings/preferences.ex`: `WatchlistVisibility` → `DiscoveryVisibility` in `exports:` (keep the list sorted the way it is).

- [ ] **Step 3: Data migration**

`priv/repo/data_migrations/20260902150000_rename_show_watchlist_settings_key.exs`:

```elixir
defmodule MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKey do
  @moduledoc """
  Renames the Settings row `show_watchlist` to `show_discovery`: the
  Watchlist page became the Discovery page (watchlist tab now; feed and
  friends tabs next), and the preference that gates its sidebar entry
  follows. The value (`%{"enabled" => boolean}`) is carried over unchanged.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: the UPDATE only fires while the new key is absent, and the
  trailing DELETE clears a leftover legacy row in the (theoretical) case
  where both keys exist — the new key wins.
  """
  use Ecto.Migration

  @rename_legacy_key """
  UPDATE settings_entries SET key = 'show_discovery'
  WHERE key = 'show_watchlist'
    AND NOT EXISTS (SELECT 1 FROM settings_entries WHERE key = 'show_discovery')
  """

  @drop_leftover_legacy_key """
  DELETE FROM settings_entries WHERE key = 'show_watchlist'
  """

  def up, do: rename_key(repo())

  def down, do: :ok

  @doc "Rename body, exposed for direct testing. Idempotent."
  def rename_key(repo) do
    repo.query!(@rename_legacy_key)
    repo.query!(@drop_leftover_legacy_key)
    :ok
  end
end
```

(Check the table name in `rename_watch_dirs_settings_key.exs` — `settings_entries` — and use exactly that.)

- [ ] **Step 4: Web rename**

- `lib/media_centaur_web/router.ex`: the on_mount tuple becomes `{MediaCentaur.Settings.Preferences.DiscoveryVisibility, :show_discovery, :setting_aware_show_discovery}`; update the comment ("its Discovery entry needs `:show_discovery` seeded session-wide…").
- `lib/media_centaur_web/components/layouts.ex`: `attr :show_watchlist` → `attr :show_discovery` with its doc naming `show_discovery` / `DiscoveryVisibility` and `/discovery/watchlist`; the sidebar link becomes:
  ```heex
  <.link
    :if={@show_discovery}
    navigate="/discovery/watchlist"
    class={sidebar_link_class(@current_path, ["/discovery", "/discovery/watchlist", "/discovery/friends"])}
    data-tip="Discovery"
    data-nav-item
    data-nav-remember
    tabindex="0"
  >
    <.icon name="hero-sparkles" class="size-5 flex-shrink-0" />
    <span class="sidebar-label">Discovery</span>
  </.link>
  ```
  (`sidebar_link_class/2` already accepts a list. If `hero-sparkles` is not in the bundled heroicons set — `ls deps/heroicons/optimized/24/outline | grep sparkles` — use `hero-globe-alt`.)
- Every LiveView: `show_watchlist={@show_watchlist}` → `show_discovery={@show_discovery}` (`grep -rln "show_watchlist" lib/media_centaur_web/live | xargs sed -i 's/show_watchlist={@show_watchlist}/show_discovery={@show_discovery}/'` then review the diff).
- `lib/media_centaur_web/live/settings_live.ex`: `handle_event("toggle_show_watchlist", …)` → `"toggle_show_discovery"`, reading/assigning `show_discovery`, key from `DiscoveryVisibility.setting_key()`.
- `lib/media_centaur_web/live/settings_live/preferences.ex`: `attr :show_watchlist` → `attr :show_discovery`; the row becomes
  ```heex
  <.settings_row
    label="Discovery"
    description="Show the Discovery page in the sidebar. Early preview — it may still change shape"
    checked={@show_discovery}
    event="toggle_show_discovery"
    color="info"
  />
  ```
- `test/media_centaur_web/no_db_on_render_test.exs`: rename `WatchlistVisibility` in the comments to `DiscoveryVisibility`; budgets unchanged.
- `grep -rn "show_watchlist\|WatchlistVisibility" lib test storybook` must return nothing after this step.

- [ ] **Step 5: Verify, then apply to the dev DB**

Run: `mix format && mix compile --warnings-as-errors && mix test test/media_centaur/repo/data_migrations test/media_centaur/data_migrations_test.exs test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/no_db_on_render_test.exs test/media_centaur_web/live/watchlist_live_test.exs && mix credo --strict`
Expected: pass. (`watchlist_live_test` still hits `/watchlist` at this point — Task 3 moves it.)

Then `mix ecto.migrate_data` against the dev DB (the owner has the preference on; the row must carry over). Verify via Tidewave `project_eval`: `MediaCentaur.Settings.Preferences.DiscoveryVisibility.enabled?()` returns `true` and `MediaCentaur.Settings.get_by_key("show_watchlist")` returns `nil`.

- [ ] **Step 6: Commit**

```bash
git add -A lib/media_centaur/settings priv/repo/data_migrations lib/media_centaur_web test/media_centaur test/media_centaur_web
git commit -m "feat(settings): show_discovery replaces show_watchlist (settings-row migration)

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 3: `DiscoveryLive` at `/discovery/watchlist`

**Files:**
- Rename: `lib/media_centaur_web/live/watchlist_live.ex` → `lib/media_centaur_web/live/discovery_live.ex`
- Modify: `lib/media_centaur_web/router.ex`
- Rename: `assets/js/input/watchlist_behavior.js` → `assets/js/input/discovery_behavior.js`; `assets/js/input/__tests__/watchlist_behavior.test.js` → `discovery_behavior.test.js`
- Modify: `assets/js/input/page_behavior.js`, `assets/js/input/config.js`
- Rename: `test/media_centaur_web/live/watchlist_live_test.exs` → `discovery_live_test.exs`; modify `test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 1: Tests first**

`git mv test/media_centaur_web/live/watchlist_live_test.exs test/media_centaur_web/live/discovery_live_test.exs`; module `MediaCentaurWeb.DiscoveryLiveTest`; every `"/watchlist"` → `"/discovery/watchlist"`. Add two tests:

```elixir
  test "renders the Discovery heading and the Watchlist tab with its count", %{conn: conn} do
    {:ok, _} = Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))
    {:ok, view, html} = live(conn, "/discovery/watchlist")

    assert html =~ "Discovery"
    assert has_element?(view, "[data-nav-zone=zone-tabs] a.zone-tab-active", "Watchlist")
    assert has_element?(view, "[data-nav-zone=zone-tabs] a.zone-tab-active", "1")
    await_supervised_tasks()
  end

  test "the sidebar marks Discovery active on the watchlist tab", %{conn: conn} do
    MediaCentaur.Settings.find_or_create_entry!(%{
      key: MediaCentaur.Settings.Preferences.DiscoveryVisibility.setting_key(),
      value: %{"enabled" => true}
    })

    {:ok, view, _html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#sidebar a.sidebar-link-active[href='/discovery/watchlist']")
  end
```

(MC0024 may reject the `[data-nav-zone=…]`/class selectors inside `has_element?` — read the check; if it only targets `=~` substring assertions on raw HTML, selectors are fine. Otherwise use ids: give the strip's active link an id? No — prefer `element(view, "a", "Watchlist")` + `render() =~ "zone-tab-active"` only if the check allows; follow the check.)

`test/media_centaur_web/page_smoke_test.exs`: `{"/watchlist", "watchlist"}` → `{"/discovery/watchlist", "discovery watchlist"}`.

Run the two files: expected failures — no route.

- [ ] **Step 2: `DiscoveryLive`**

`git mv lib/media_centaur_web/live/watchlist_live.ex lib/media_centaur_web/live/discovery_live.ex`. Module `MediaCentaurWeb.DiscoveryLive`. Moduledoc: "The Discovery page — the surface every candidate source lands on. This layer hosts one tab, the watchlist (…existing watchlist paragraph…). Feed and Friends tabs arrive with the recommendations layers." Then:

- `assign(:page_title, "Discovery")`.
- add `import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]` and `alias MediaCentaurWeb.Components.TabStrip.Tab`.
- render: `show_discovery={@show_discovery}`, `current_path="/discovery/watchlist"`, `data-page-behavior="discovery"`, and the content block becomes

```heex
      <div class="relative" data-page-behavior="discovery" data-nav-default-zone="grid">
        <div class="mx-auto w-full max-w-3xl space-y-4 pt-10">
          <h1 class="px-1 text-lg font-semibold">Discovery</h1>

          <.tab_strip tabs={tabs(@items)} active={:watchlist} />

          <div class="space-y-2" data-nav-zone="grid">
            <div
              :if={@items == []}
              id="watchlist-empty"
              class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
            >
              Nothing on your watchlist yet. Titles you save from a search land here.
            </div>

            <WatchlistRow.watchlist_row
              :for={row <- @items}
              item={row.item}
              library_owner_id={row.library_owner_id}
              poster_url={row.poster_url}
              release_mode_available={@prowlarr_ready}
            />
          </div>
        </div>
      </div>
```

and a private

```elixir
  # The tabs this layer hosts. Feed (`/discovery`) and Friends
  # (`/discovery/friends`) join here with their layers.
  defp tabs(items), do: [%Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)}]
```

Keep the wrapper's existing `data-nav-default-zone` value if it was something other than `"watchlist"` — check the file; the zone that holds the rows is `grid`, so `data-nav-default-zone="grid"` is the honest value (the old `"watchlist"` named the page layout, not a zone — verify against `assets/js/input/config.js` semantics: `data-nav-default-zone` names a **zone**; if the old value worked it is because the framework fell back, so `grid` is correct).

- `lib/media_centaur_web/router.ex`: `live "/watchlist", WatchlistLive, :index` → `live "/discovery/watchlist", DiscoveryLive, :watchlist` (keep the list alphabetical: it goes after `/console`).

- [ ] **Step 3: JS page behavior + zone layout**

- `git mv assets/js/input/watchlist_behavior.js assets/js/input/discovery_behavior.js`; export `createDiscoveryBehavior`; header comment: "Discovery page behavior. Layout: the zone-tabs strip above a grid of watchlist rows. Left at the grid's left edge returns to the sidebar (framework-handled via the `discovery` zone layout). No page-specific actions."
- `git mv assets/js/input/__tests__/watchlist_behavior.test.js assets/js/input/__tests__/discovery_behavior.test.js`; import/describe renamed (`"discovery behavior"`), test bodies unchanged.
- `assets/js/input/page_behavior.js`: import `createDiscoveryBehavior` from `./discovery_behavior`; registry key `discovery: () => createDiscoveryBehavior(),` replacing `watchlist`.
- `assets/js/input/config.js`: replace the `watchlist:` zone layout with
  ```js
    // Discovery: the zone-tabs strip above the watchlist grid (feed and
    // friends tabs join the strip later). Same shape as review/reconcile.
    discovery: {
      zone_tabs: { down: ["grid"] },
      grid:      { up: ["zone_tabs"] },
      sidebar:   { right: ["grid", "zone_tabs"] },
    },
  ```
  and the zone list `watchlist: ["grid", "sidebar"]` → `discovery: ["grid", "zone_tabs", "sidebar"]`. Match the key spelling the review entry uses for the strip (`zone_tabs`) exactly.
- `grep -rn "watchlist" assets/js --include=*.js` afterwards: only the WatchlistAware/bookmark-related strings (if any) may remain; no page-behavior or zone-layout reference.
- Run `cd assets && bun test` (or the repo's JS test command — see `mix.exs` aliases / `package.json`): pass.
- **Rebuild assets** (watchers are off): `mix assets.build`.

- [ ] **Step 4: Verify**

Run: `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/no_db_on_render_test.exs test/media_centaur_web/storybook_render_test.exs && mix credo --strict && mix boundaries`
Expected: pass. `grep -rn "WatchlistLive\|\"/watchlist\"\|~p\"/watchlist" lib test storybook` → nothing.

Then a real-browser check against the dev server (`http://127.0.0.1:2160/discovery/watchlist`): `~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery/watchlist --viewport 1920x1080 --wait-ms 3000` and Read the PNG: heading "Discovery", the Watchlist tab underlined with a count badge, rows below, the sidebar's Discovery entry active. If `~/scripts/agents/mc-nav-trace` exists (`ls ~/scripts/agents/`), run it with no args for usage and, if it accepts a URL + key sequence, trace `ArrowDown` from the tab strip into the grid and `ArrowUp` back; report the result. Do not spend more than a few minutes on the tracer.

- [ ] **Step 5: Commit**

```bash
git add -A lib/media_centaur_web assets/js test/media_centaur_web priv/static
git commit -m "feat(discovery): the Discovery page hosts the watchlist at /discovery/watchlist

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

(Include `priv/static` only if the repo tracks built assets — `git ls-files priv/static | head`; if not tracked, omit it.)

---

### Task 4: Wiki, docs, campaign, precommit

**Files:**
- Modify: `../media-centaur.wiki/Watchlist.md`, `../media-centaur.wiki/Settings-Reference.md`
- Modify: `docs/input-system.md` (only if it lists page behaviors by name — `grep -n "watchlist" docs/input-system.md docs/*.md`)
- Modify: `campaigns/friends-recommendations.md`

- [ ] **Step 1: Wiki**

`Watchlist.md`, first two paragraphs become (house voice, reference register):

> The **Watchlist** is a tab of the Discovery page (`/discovery/watchlist`). It holds titles you want to watch but haven't acted on yet — saved with a bookmark from a search or from a title's page, whether or not the title is in your library. Saving is intent only: nothing is searched or downloaded until you act on a row.
>
> Discovery is an early preview and may still change shape, so its sidebar entry is off by default — turn on **Discovery** under [Settings → Preferences](Settings-Reference#preferences) to add it to the sidebar's Watch group. The page stays reachable at `/discovery/watchlist`, and the bookmark controls work either way.

Rename the "## The Watchlist page" heading to "## The Watchlist tab". Leave the rest.

`Settings-Reference.md` line 52 becomes:

> - **Discovery** (default off) — shows the Discovery page in the sidebar; its Watchlist tab is documented at [Watchlist](Watchlist). The feature is an early preview and may still change shape, so it's opt-in. Only the sidebar entry is affected: `/discovery/watchlist` stays reachable by URL, the bookmark controls stay in place, and saved titles are kept either way.

Commit the wiki in its own repo:

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Watchlist is a tab of the Discovery page; Discovery preference" && cd -
```

Do **not** push the wiki (the app is unpushed; the wiki goes with it).

- [ ] **Step 2: Contributor docs**

If `docs/input-system.md` (or any `docs/*.md`) names the `watchlist` page behavior or zone layout, rename to `discovery` in that sentence. Nothing else.

- [ ] **Step 3: Campaign**

`campaigns/friends-recommendations.md` Status: "Layers 1a and 1b landed 2026-09-02 on main, unpushed (title convergence; Discovery page at `/discovery/watchlist` with `tab_strip` and `show_discovery`); next: layer 2 (`MediaCentaur.Nostr`: keys, events, filters)." Next steps: remove the "Plan 1b — Discovery page" item.

- [ ] **Step 4: Precommit and commit**

Run `mix precommit 2>&1 | tail -40` (several minutes). Expected: PASSED, zero warnings attributable to this work; fix anything it reports from these commits. Then:

```bash
git add campaigns docs
git commit -m "docs(campaign): Discovery page landed; next = Nostr protocol layer

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

No push, no tag.

---

## Self-review

**Spec coverage:** decision 7 (gate rename + settings-row migration + default off) → Task 2; decision 8 (shared tab strip, Review + Discovery) → Tasks 1 and 3; UI "Discovery page at `/discovery/watchlist`, sidebar entry Discovery gated by `show_discovery`, old `/watchlist` removed, `tab_strip` joins the tabs" → Task 3; wiki Settings-Reference → Task 4. Out of this layer by design: `/discovery` (Feed) and `/discovery/friends`.

**Type consistency:** `TabStrip.tab_strip/1` (`tabs`, `active`), `TabStrip.Tab` (`id`, `label`, `navigate`, `count`), `DiscoveryVisibility.setting_key/0` = `"show_discovery"`, assign `:show_discovery`, event `"toggle_show_discovery"`, `DiscoveryLive` at `/discovery/watchlist` with action `:watchlist`, JS `createDiscoveryBehavior`, layout key `discovery`.

**Placeholders:** none.
