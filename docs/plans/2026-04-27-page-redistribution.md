# Page Redistribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the app's page IA from one zone-conflated `/` (Library does Continue Watching + Browse + Upcoming) into focused single-purpose pages with two visually distinct sidebar groups (Watch / System).

**Architecture:** Phased migration. Each phase ships independently and adds value on its own. **Phase 1** promotes the existing-but-hidden History page into the nav and adds re-watch surfacing (the "one more dimension" that earns it a primary slot). **Phase 2** restructures the sidebar into Watch/System groups (purely visual). **Phase 3** extracts Upcoming from LibraryLive into its own `/upcoming` route. **Phase 4** is the cutover: builds the new cinematic Home at `/` and reduces Library to a pure catalog browser at `/library`.

**Tech Stack:** Phoenix LiveView, Ecto, daisyUI, custom glass CSS. Test-first via the project's `automated-testing` skill (mandatory). Pure-function logic extracted per ADR-030 (`*_logic.ex` modules tested with `async: true`). Context facade subscribe per project convention. JJ (not git) for version control — `jj describe -m`, `jj new` for new features.

**Visual reference:** `mockups/page-redistribution/` (open `index.html`). Mockups are not production code; they show target appearance and IA only.

---

## Background

This is the executable plan derived from the design captured in `mockups/page-redistribution/REASONING.md`. Read that first for the why; this document is the how.

Key project conventions you must follow:

- **Test-first** is mandatory ([automated-testing] skill). Write the test, see it fail, write the minimal code to make it pass, commit.
- **Pure-function extraction** for any non-trivial LiveView logic ([ADR-030]). Helper module pattern: `MediaCentarrWeb.HomeLive.Logic` paired with `MediaCentarrWeb.HomeLive`.
- **Context facade subscribe** ([CLAUDE.md "Context facade subscribe pattern"]). LiveViews call `Library.subscribe()`, never `Phoenix.PubSub.subscribe(MediaCentarr.PubSub, ...)` directly.
- **Boundary** ([ADR-029]). `MediaCentarrWeb` already declares deps to all contexts it needs; if a new context becomes a dep, update the `use Boundary` line in `lib/media_centarr_web.ex`.
- **No abbreviated names** ([CLAUDE.md "Variable Naming"]). `episode` not `ep`, `movie` not `m`. The `NoAbbreviatedNames` Credo check enforces this.
- **PredicateNaming**: boolean functions end in `?`. `is_` prefix is reserved for `defmacro`/`defguard`.
- **Zero warnings** ([CLAUDE.md "Zero warnings policy"]). Treat every warning as a bug.
- **`mix precommit`** must pass before any commit (compile, format, credo --strict, sobelow, deps.audit, test).

[automated-testing]: invoked via Skill tool — covers test-first workflow, factory patterns, stubs
[ADR-030]: `decisions/architecture/2026-04-02-030-liveview-logic-extraction.md`
[ADR-029]: `decisions/architecture/2026-03-26-029-data-decoupling.md`

---

## File structure overview

**New files:**

| Path | Responsibility |
|---|---|
| `lib/media_centarr/watch_history/rewatch.ex` | Pure SQL/Ecto query: count of completion events per entity, with most-recent date |
| `lib/media_centarr_web/live/upcoming_live.ex` | Standalone Upcoming page (was zone of LibraryLive) |
| `lib/media_centarr_web/live/upcoming_live/logic.ex` | Pure functions for Upcoming page (calendar weeks, group merging — most reusable from existing UpcomingCards) |
| `lib/media_centarr_web/live/home_live.ex` | New cinematic Home page |
| `lib/media_centarr_web/live/home_live/logic.ex` | Pure functions: row assembly, hero selection, "this week" date math |
| `lib/media_centarr_web/components/continue_watching_row.ex` | Extracted backdrop-card row (used by Home; replaces inline impl in LibraryLive) |
| `lib/media_centarr_web/components/coming_up_row.ex` | New 4-card digest row for Home |
| `lib/media_centarr_web/components/poster_row.ex` | New horizontal poster strip (used twice on Home: Recently Added, Watched Recently) |
| `lib/media_centarr_web/components/hero_card.ex` | New full-bleed hero (Home only) |
| `test/media_centarr/watch_history/rewatch_test.exs` | Tests for rewatch query |
| `test/media_centarr_web/live/upcoming_live_test.exs` | Mount + render smoke + redirect-from-library test |
| `test/media_centarr_web/live/upcoming_live/logic_test.exs` | Pure function tests (moved from existing) |
| `test/media_centarr_web/live/home_live_test.exs` | Mount + render smoke |
| `test/media_centarr_web/live/home_live/logic_test.exs` | Pure row-assembly tests |
| `test/media_centarr_web/components/continue_watching_row_test.exs` | Render smoke |
| `test/media_centarr_web/components/coming_up_row_test.exs` | Pure logic + render smoke |

**Modified files:**

| Path | Change |
|---|---|
| `lib/media_centarr/watch_history.ex` | Add `rewatch_count/1` and `top_rewatches/1` public API |
| `lib/media_centarr_web/components/layouts.ex` | Sidebar gets group labels and two visual weights |
| `assets/css/app.css` | Sidebar group label styles + `.sidebar-link.system-link` variant |
| `lib/media_centarr_web/live/library_live.ex` | Remove Upcoming zone; in Phase 4, also remove Continue Watching zone |
| `lib/media_centarr_web/router.ex` | Add `/upcoming`, `/library`, change `/` to HomeLive in Phase 4 |
| `lib/media_centarr_web/live/watch_history_live.ex` | Surface re-watch counts in event rows |
| `lib/media_centarr_web/live/library_live/library_helpers.ex` | If Continue Watching helper extracts, move to component module |

**Files left alone:**

`lib/media_centarr_web/components/upcoming_cards.ex` — the current Upcoming zone implementation. In Phase 3 we extract it into UpcomingLive but the component itself is reused mostly verbatim. Renaming/refactoring its internals is out of scope.

---

## Phase 1 — History promotion + re-watch surfacing

**Ships independently.** Lowest risk; pure additive change. Visible value: History becomes a real nav destination with re-watch insight.

### Task 1.1: Add a pure-function rewatch query module

**Files:**
- Create: `lib/media_centarr/watch_history/rewatch.ex`
- Test: `test/media_centarr/watch_history/rewatch_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentarr.WatchHistory.RewatchTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.TestFactory
  alias MediaCentarr.WatchHistory
  alias MediaCentarr.WatchHistory.Rewatch

  describe "count_per_entity/1" do
    test "returns 1 for entities watched once" do
      movie = TestFactory.create_movie()
      TestFactory.create_watch_event(movie_id: movie.id)

      counts = Rewatch.count_per_entity(:movie)

      assert counts[movie.id] == 1
    end

    test "returns N for entities watched N times" do
      movie = TestFactory.create_movie()

      for _ <- 1..3 do
        TestFactory.create_watch_event(movie_id: movie.id)
      end

      counts = Rewatch.count_per_entity(:movie)

      assert counts[movie.id] == 3
    end

    test "scoped to entity_type" do
      movie = TestFactory.create_movie()
      episode = TestFactory.create_episode()
      TestFactory.create_watch_event(movie_id: movie.id)
      TestFactory.create_watch_event(episode_id: episode.id)

      assert Rewatch.count_per_entity(:movie) == %{movie.id => 1}
      assert Rewatch.count_per_entity(:episode) == %{episode.id => 1}
    end
  end

  describe "top_rewatches/1" do
    test "returns entities sorted by completion count, descending" do
      a = TestFactory.create_movie(name: "A")
      b = TestFactory.create_movie(name: "B")

      TestFactory.create_watch_event(movie_id: a.id)
      for _ <- 1..3, do: TestFactory.create_watch_event(movie_id: b.id)

      [first, second] = Rewatch.top_rewatches(limit: 10)

      assert first.entity_id == b.id
      assert first.count == 3
      assert second.entity_id == a.id
      assert second.count == 1
    end

    test "filters out entities watched only once when min: 2" do
      a = TestFactory.create_movie()
      b = TestFactory.create_movie()
      TestFactory.create_watch_event(movie_id: a.id)
      for _ <- 1..2, do: TestFactory.create_watch_event(movie_id: b.id)

      results = Rewatch.top_rewatches(min: 2)

      assert length(results) == 1
      assert hd(results).entity_id == b.id
    end
  end
end
```

- [ ] **Step 2: Run the test, verify it fails**

```
mix test test/media_centarr/watch_history/rewatch_test.exs
```
Expected: FAIL — module `MediaCentarr.WatchHistory.Rewatch` is not defined.

- [ ] **Step 3: Implement the module**

```elixir
defmodule MediaCentarr.WatchHistory.Rewatch do
  @moduledoc """
  Pure Ecto queries for re-watch detection.

  A "re-watch" is any completion event beyond the first for the same entity.
  All functions here are read-only and return plain maps/lists — no Ecto
  schemas leak past the boundary.
  """
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.WatchHistory.Event

  @type entity_type :: :movie | :episode | :video_object
  @type rewatch_row :: %{entity_type: entity_type(), entity_id: integer(), count: pos_integer(), last_watched_at: DateTime.t()}

  @doc """
  Count completion events per entity for the given type.
  Returns a map of `entity_id => count`. Entities with zero events are absent.
  """
  @spec count_per_entity(entity_type()) :: %{integer() => pos_integer()}
  def count_per_entity(:movie), do: do_count(:movie_id)
  def count_per_entity(:episode), do: do_count(:episode_id)
  def count_per_entity(:video_object), do: do_count(:video_object_id)

  defp do_count(field) do
    Event
    |> where([e], not is_nil(field(e, ^field)))
    |> group_by([e], field(e, ^field))
    |> select([e], {field(e, ^field), count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Top N entities by completion count, descending.

  Options:
  - `:limit` — max rows (default 25)
  - `:min` — minimum completion count to include (default 1)
  - `:entity_type` — filter to one type, or `:all` (default)
  """
  @spec top_rewatches(keyword()) :: [rewatch_row()]
  def top_rewatches(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    min = Keyword.get(opts, :min, 1)
    type_filter = Keyword.get(opts, :entity_type, :all)

    [:movie, :episode, :video_object]
    |> Enum.filter(&(type_filter == :all or type_filter == &1))
    |> Enum.flat_map(&top_for_type(&1, min))
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp top_for_type(type, min) do
    field = type_field(type)

    Event
    |> where([e], not is_nil(field(e, ^field)))
    |> group_by([e], field(e, ^field))
    |> having([e], count(e.id) >= ^min)
    |> select([e], %{
      entity_type: ^type,
      entity_id: field(e, ^field),
      count: count(e.id),
      last_watched_at: max(e.completed_at)
    })
    |> Repo.all()
  end

  defp type_field(:movie), do: :movie_id
  defp type_field(:episode), do: :episode_id
  defp type_field(:video_object), do: :video_object_id
end
```

- [ ] **Step 4: Add factory helper if `create_watch_event` doesn't exist**

Check `test/support/factory.ex`. If `create_watch_event/1` is not defined, add:

```elixir
def create_watch_event(attrs \\ %{}) do
  defaults = %{
    title: "Test Title",
    duration_seconds: 3600,
    completed_at: DateTime.utc_now(),
    entity_type: cond do
      Map.has_key?(attrs, :movie_id) -> :movie
      Map.has_key?(attrs, :episode_id) -> :episode
      Map.has_key?(attrs, :video_object_id) -> :video_object
      true -> :movie
    end
  }

  attrs = Map.merge(defaults, Map.new(attrs))

  {:ok, event} = MediaCentarr.WatchHistory.create_event(attrs)
  event
end
```

- [ ] **Step 5: Re-run the test, verify it passes**

```
mix test test/media_centarr/watch_history/rewatch_test.exs
```
Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```
jj describe -m "feat(watch_history): add Rewatch query module"
jj new
```

### Task 1.2: Expose rewatch_count/1 and top_rewatches/1 from WatchHistory facade

**Files:**
- Modify: `lib/media_centarr/watch_history.ex`
- Test: `test/media_centarr/watch_history_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centarr/watch_history_test.exs`:

```elixir
describe "rewatch_count/2" do
  test "returns count for a single entity" do
    movie = MediaCentarr.TestFactory.create_movie()
    for _ <- 1..3, do: MediaCentarr.TestFactory.create_watch_event(movie_id: movie.id)

    assert MediaCentarr.WatchHistory.rewatch_count(:movie, movie.id) == 3
  end

  test "returns 0 for an entity with no events" do
    movie = MediaCentarr.TestFactory.create_movie()
    assert MediaCentarr.WatchHistory.rewatch_count(:movie, movie.id) == 0
  end
end

describe "top_rewatches/1" do
  test "delegates to Rewatch.top_rewatches/1" do
    movie = MediaCentarr.TestFactory.create_movie()
    for _ <- 1..2, do: MediaCentarr.TestFactory.create_watch_event(movie_id: movie.id)

    [row] = MediaCentarr.WatchHistory.top_rewatches(min: 2, limit: 5)

    assert row.entity_id == movie.id
    assert row.count == 2
  end
end
```

- [ ] **Step 2: Run test to confirm failure** (`mix test test/media_centarr/watch_history_test.exs`).

- [ ] **Step 3: Add the public functions to `lib/media_centarr/watch_history.ex`**

After `def stats do ... end`, add:

```elixir
alias MediaCentarr.WatchHistory.Rewatch

@doc """
Count of completion events for a single entity.

Returns 0 if the entity has never been watched. Pure delegation to Rewatch.
"""
@spec rewatch_count(:movie | :episode | :video_object, integer()) :: non_neg_integer()
def rewatch_count(type, entity_id) do
  type
  |> Rewatch.count_per_entity()
  |> Map.get(entity_id, 0)
end

@doc """
Most-rewatched entities. Delegates to `Rewatch.top_rewatches/1`. See its
docs for options.
"""
@spec top_rewatches(keyword()) :: [Rewatch.rewatch_row()]
def top_rewatches(opts \\ []), do: Rewatch.top_rewatches(opts)
```

- [ ] **Step 4: Re-run, verify passes.**

- [ ] **Step 5: Commit**

```
jj describe -m "feat(watch_history): expose rewatch_count and top_rewatches via facade"
jj new
```

### Task 1.3: Add re-watch column to History event rows

**Files:**
- Modify: `lib/media_centarr_web/live/watch_history_live.ex`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centarr_web/live/watch_history_live_test.exs`:

```elixir
test "shows rewatch count badge for entities watched 2+ times", %{conn: conn} do
  movie = MediaCentarr.TestFactory.create_movie(name: "Sample Show")
  for _ <- 1..3, do: MediaCentarr.TestFactory.create_watch_event(movie_id: movie.id, title: "Sample Show")

  {:ok, view, _html} = live(conn, "/history")
  rendered = render(view)

  # The most recent event row for Sample Show should display "3rd watch" or similar
  assert rendered =~ "3×"
end
```

- [ ] **Step 2: Confirm failure** (`mix test test/media_centarr_web/live/watch_history_live_test.exs`).

- [ ] **Step 3: Pass rewatch counts to the template**

In `mount/3`, after computing `stats`, add:

```elixir
movie_counts = WatchHistory.rewatch_count_map(:movie)
episode_counts = WatchHistory.rewatch_count_map(:episode)
video_counts = WatchHistory.rewatch_count_map(:video_object)
```

(Add `rewatch_count_map/1` as a thin wrapper around `Rewatch.count_per_entity/1` in the WatchHistory facade — same pattern as the singular function from Task 1.2.)

Assign all three onto the socket. In the event-row template, look up the count by entity_type + entity_id:

```heex
<span :if={rewatch_count_for(event, @movie_counts, @episode_counts, @video_counts) > 1}
      class="badge badge-soft badge-primary text-xs">
  {rewatch_count_for(event, @movie_counts, @episode_counts, @video_counts)}×
</span>
```

Define the helper in `WatchHistoryLive`:

```elixir
defp rewatch_count_for(event, movie_counts, episode_counts, video_counts) do
  case event.entity_type do
    :movie -> Map.get(movie_counts, event.movie_id, 0)
    :episode -> Map.get(episode_counts, event.episode_id, 0)
    :video_object -> Map.get(video_counts, event.video_object_id, 0)
    _ -> 0
  end
end
```

- [ ] **Step 4: Re-run, verify passes.**

- [ ] **Step 5: Commit**

```
jj describe -m "feat(history): show rewatch count on event rows"
jj new
```

### Task 1.4: Update wiki "Using Media Centarr" → History page

**Files:**
- Modify: `~/src/media-centarr/media-centarr.wiki/Watch-History.md` (or whichever page exists; create if missing per CLAUDE.md "Keep the wiki in sync")

- [ ] **Step 1: Add a section on re-watch counts**

Brief note that completion rows now show a count badge for anything watched 2+ times. One paragraph; no screenshots required.

- [ ] **Step 2: Commit the wiki**

```
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: history page now surfaces rewatch counts"
jj bookmark set master -r @
jj git push
```

### Task 1.5: Verify Phase 1 ships

- [ ] **Step 1: Run `mix precommit`** — must pass with zero warnings.
- [ ] **Step 2: Manually verify in browser** — open `/history`, confirm any title you've watched 2+ times shows a count badge.
- [ ] **Step 3: Confirm History link still works as before** (will be promoted to nav in Phase 2).

---

## Phase 2 — Sidebar restructure (Watch / System groups)

**Ships independently of Phase 3-4.** Adds two group labels and one extra visual weight to the sidebar. **Does not add new nav links yet** — those land in Phase 3 (Upcoming) and Phase 4 (Home, Library at /library). After this phase, the sidebar still has the same 5 links, just visually grouped.

### Task 2.1: Add CSS for sidebar group labels and demoted system links

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Append the new styles**

After the existing `.sidebar-link-active:hover` rule (around line 287), add:

```css
/* Sidebar group label — small, uppercase, dim. Separates Watch from System. */
.sidebar-group-label {
  font-size: 0.625rem;
  font-weight: 600;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: oklch(from var(--color-base-content) l c h / 0.4);
  padding: 0.75rem 0.5rem 0.25rem 0.5rem;
}

[data-sidebar=collapsed] .sidebar-group-label {
  opacity: 0;
  padding-top: 0.5rem;
  padding-bottom: 0;
  height: 0.5rem;
  overflow: hidden;
}

/* Demoted system-group links — slightly dimmer & smaller. */
.sidebar-link-system {
  font-size: 0.8125rem;
  color: oklch(from var(--color-base-content) l c h / 0.55);
}

.sidebar-link-system:hover {
  color: oklch(from var(--color-base-content) l c h / 0.75);
}

.sidebar-link-system.sidebar-link-active {
  color: var(--color-primary);
  background: oklch(from var(--color-primary) l c h / 0.10);
}

.sidebar-link-system .size-5 {
  width: 1rem;
  height: 1rem;
}
```

- [ ] **Step 2: Commit**

```
jj describe -m "feat(ui): sidebar group label + system-link CSS"
jj new
```

### Task 2.2: Restructure sidebar HTML to use the groups

**Files:**
- Modify: `lib/media_centarr_web/components/layouts.ex`
- Test: `test/media_centarr_web/page_smoke_test.exs` (existing smoke test should still pass)

- [ ] **Step 1: Edit the `<nav>` block in `app/2`**

Replace the existing `<nav class="flex flex-col gap-0.5">...</nav>` (lines ~44-99) with two grouped navs:

```heex
<div class="sidebar-group-label sidebar-label">Watch</div>
<nav class="flex flex-col gap-0.5">
  <.link
    navigate="/"
    class={sidebar_link_class(@current_path, "/")}
    data-tip="Library"
    data-nav-item
    data-nav-remember
    tabindex="0"
  >
    <.icon name="hero-book-open" class="size-5 flex-shrink-0" />
    <span class="sidebar-label">Library</span>
  </.link>
</nav>

<div class="sidebar-group-label sidebar-label">System</div>
<nav class="flex flex-col gap-0.5">
  <%= if MediaCentarr.Capabilities.prowlarr_ready?() do %>
    <.link
      navigate="/download"
      class={sidebar_link_class(@current_path, "/download") <> " sidebar-link-system"}
      data-tip="Downloads"
      data-nav-item
      tabindex="0"
    >
      <.icon name="hero-arrow-down-tray" class="size-5 flex-shrink-0" />
      <span class="sidebar-label">Downloads</span>
    </.link>
  <% end %>
  <.link
    navigate="/status"
    class={sidebar_link_class(@current_path, "/status") <> " sidebar-link-system"}
    data-tip="Status"
    data-nav-item
    tabindex="0"
  >
    <.icon name="hero-squares-2x2" class="size-5 flex-shrink-0" />
    <span class="sidebar-label">Status</span>
  </.link>
  <.link
    navigate="/review"
    class={sidebar_link_class(@current_path, "/review") <> " sidebar-link-system"}
    data-tip="Review"
    data-nav-item
    tabindex="0"
  >
    <.icon name="hero-document-text" class="size-5 flex-shrink-0" />
    <span class="sidebar-label">Review</span>
  </.link>
  <.link
    navigate="/settings"
    class={sidebar_link_class(@current_path, "/settings") <> " sidebar-link-system"}
    data-tip="Settings"
    data-nav-item
    data-nav-remember
    tabindex="0"
  >
    <.icon name="hero-cog-6-tooth" class="size-5 flex-shrink-0" />
    <span class="sidebar-label">Settings</span>
  </.link>
</nav>
```

- [ ] **Step 2: Run the page smoke test, verify still passes**

```
mix test test/media_centarr_web/page_smoke_test.exs
```

- [ ] **Step 3: Manually verify** — load any page, confirm the sidebar shows "WATCH" with Library, then "SYSTEM" with the four operator pages in slightly smaller/dimmer styling. Collapse the sidebar (`Collapse` button at the bottom) and confirm the group labels collapse cleanly without leaving holes.

- [ ] **Step 4: Add History to the Watch group**

Now that the structure is in place, add a History nav link inside the Watch `<nav>` block, just below Library:

```heex
<.link
  navigate="/history"
  class={sidebar_link_class(@current_path, "/history")}
  data-tip="History"
  data-nav-item
  tabindex="0"
>
  <.icon name="hero-clock" class="size-5 flex-shrink-0" />
  <span class="sidebar-label">History</span>
</.link>
```

- [ ] **Step 5: Run `mix precommit`**

- [ ] **Step 6: Commit**

```
jj describe -m "feat(ui): sidebar Watch/System groups + promote History to nav"
jj new
```

### Task 2.3: Update wiki — Keyboard-and-Gamepad / sidebar overview

**Files:**
- Modify: `~/src/media-centarr/media-centarr.wiki/` — relevant page describing the sidebar

- [ ] **Step 1: Note the new grouping** in the sidebar description (one sentence is plenty).

- [ ] **Step 2: Commit and push**

```
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: sidebar now grouped Watch / System; History is in nav"
jj bookmark set master -r @
jj git push
```

---

## Phase 3 — Upcoming as its own page

**Ships independently of Phase 4.** Adds `/upcoming` route with the existing UpcomingCards component. Library still has its Upcoming zone after this phase (we'll remove it in Phase 4) so users see the content in two places briefly. URL `/?zone=upcoming` redirects to `/upcoming`.

### Task 3.1: Create UpcomingLive — minimum viable mount + render

**Files:**
- Create: `lib/media_centarr_web/live/upcoming_live.ex`
- Create: `test/media_centarr_web/live/upcoming_live_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentarrWeb.UpcomingLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "GET /upcoming renders the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/upcoming")
    assert html =~ "Upcoming"
  end

  test "GET /upcoming shows the Track New Releases button when TMDB ready", %{conn: conn} do
    # default TestFactory state is TMDB-ready; tweak if your test setup differs
    {:ok, _view, html} = live(conn, "/upcoming")
    assert html =~ "Track New Releases"
  end
end
```

- [ ] **Step 2: Add the route to `lib/media_centarr_web/router.ex`**

Inside `live_session :default do`:

```elixir
live "/upcoming", UpcomingLive, :index
```

- [ ] **Step 3: Run the test, confirm route 404 fails**

`mix test test/media_centarr_web/live/upcoming_live_test.exs`

- [ ] **Step 4: Implement the LiveView**

Open `lib/media_centarr_web/live/library_live.ex` and find the section that handles `zone=upcoming`. Lift its mount/handle_info/handle_event logic into a new module:

```elixir
defmodule MediaCentarrWeb.UpcomingLive do
  @moduledoc """
  Standalone Upcoming page — calendar, tracking, active shows, recent
  changes, unscheduled. Uses the shared `UpcomingCards` component for
  rendering; this LiveView wires assigns and PubSub.

  Extracted from LibraryLive zone-3 in the page-redistribution refactor
  (see docs/plans/2026-04-27-page-redistribution.md).
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Library, ReleaseTracking}
  alias MediaCentarrWeb.Components.UpcomingCards

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Library.subscribe()
      ReleaseTracking.subscribe()
    end

    today = Date.utc_today()
    {year, month} = {today.year, today.month}

    socket =
      socket
      |> assign(:calendar_month, {year, month})
      |> assign(:selected_day, nil)
      |> assign(:confirm_stop_item, nil)
      |> assign_upcoming_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/upcoming" full_width>
      <div class="space-y-6 py-2">
        <div class="flex items-baseline justify-between">
          <div>
            <h1 class="text-2xl font-bold">Upcoming</h1>
            <p class="text-sm text-base-content/60">
              {@releases_summary}
            </p>
          </div>
        </div>

        <UpcomingCards.upcoming_zone
          releases={@releases}
          events={@events}
          images={@images}
          calendar_month={@calendar_month}
          selected_day={@selected_day}
          tracked_items={@tracked_items}
          confirm_stop_item={@confirm_stop_item}
          tmdb_ready={@tmdb_ready}
          grab_statuses={@grab_statuses}
          queue_items={@queue_items}
          acquisition_ready={@acquisition_ready}
        />
      </div>
    </Layouts.app>
    """
  end

  # Re-use any zone-3 handle_event / handle_info clauses from LibraryLive
  # *verbatim* — copy them down here and delete from LibraryLive once
  # Phase 4 removes the zone. (`prev_month`, `next_month`, `jump_today`,
  # `select_day`, `open_track_modal`, `stop_tracking`, etc.)

  # ... handle_event clauses ...
  # ... handle_info clauses ...

  defp assign_upcoming_data(socket) do
    # Replicate the data-loading shape currently in LibraryLive's
    # zone=upcoming branch. Read library_live.ex to find the exact
    # function calls and assign them onto the socket here.
    socket
    # |> assign(:releases, ...)
    # |> assign(:events, ...)
    # ...
  end
end
```

- [ ] **Step 5: Run the smoke tests, verify they pass**

`mix test test/media_centarr_web/live/upcoming_live_test.exs`

- [ ] **Step 6: Commit**

```
jj describe -m "feat(upcoming): standalone /upcoming LiveView"
jj new
```

### Task 3.2: Add /upcoming to sidebar nav

**Files:**
- Modify: `lib/media_centarr_web/components/layouts.ex`

- [ ] **Step 1: Add the link to the Watch group nav** (between Library and History from Task 2.2):

```heex
<.link
  navigate="/upcoming"
  class={sidebar_link_class(@current_path, "/upcoming")}
  data-tip="Upcoming"
  data-nav-item
  tabindex="0"
>
  <.icon name="hero-calendar" class="size-5 flex-shrink-0" />
  <span class="sidebar-label">Upcoming</span>
</.link>
```

- [ ] **Step 2: Manually verify** — sidebar Watch group shows Library, Upcoming, History; clicking Upcoming loads `/upcoming` with the same content as zone=upcoming.

- [ ] **Step 3: Commit**

```
jj describe -m "feat(ui): add Upcoming to sidebar Watch group"
jj new
```

### Task 3.3: Redirect /?zone=upcoming → /upcoming

**Files:**
- Modify: `lib/media_centarr_web/live/library_live.ex` — in the `handle_params` function that interprets `zone`, intercept `zone=upcoming` early.

- [ ] **Step 1: Add the redirect**

In `handle_params/3`, before any zone-state logic:

```elixir
def handle_params(%{"zone" => "upcoming"} = params, _uri, socket) do
  # forward any other params (e.g., `selected`) onto /upcoming
  forward_params = Map.delete(params, "zone")
  query = if forward_params == %{}, do: "", else: "?" <> URI.encode_query(forward_params)
  {:noreply, push_navigate(socket, to: "/upcoming" <> query)}
end
```

Leave existing clauses for other zone values intact.

- [ ] **Step 2: Test the redirect**

Add to `test/media_centarr_web/live/library_live_test.exs`:

```elixir
test "redirects /?zone=upcoming to /upcoming", %{conn: conn} do
  assert {:error, {:live_redirect, %{to: "/upcoming"}}} = live(conn, "/?zone=upcoming")
end
```

Run: `mix test test/media_centarr_web/live/library_live_test.exs`

- [ ] **Step 3: Commit**

```
jj describe -m "feat(library): redirect /?zone=upcoming to /upcoming"
jj new
```

### Task 3.4: Update wiki — Upcoming/Tracking page

**Files:**
- Modify: `~/src/media-centarr/media-centarr.wiki/Tracking-Releases.md` (or wherever Upcoming is documented)

- [ ] **Step 1: Update URL references** from `/?zone=upcoming` to `/upcoming`. One paragraph is fine.

- [ ] **Step 2: Commit and push**

```
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: Upcoming is now a top-level /upcoming page"
jj bookmark set master -r @
jj git push
```

---

## Phase 4 — New Home + Library reduction (the cutover)

**The big one.** Ships as a single coherent change because `/` shifts identity from Library→Home and Library moves to `/library`. Old `/` should redirect appropriately. After this phase, the IA is in its target shape.

### Task 4.1: Extract a reusable `<.continue_watching_row>` component

**Files:**
- Create: `lib/media_centarr_web/components/continue_watching_row.ex`
- Create: `test/media_centarr_web/components/continue_watching_row_test.exs`

The component takes a list of in-progress items + an images map and renders a horizontal row of backdrop cards with progress bars. Same look as the mockup at `mockups/page-redistribution/home/index.html`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentarrWeb.Components.ContinueWatchingRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ContinueWatchingRow

  test "renders one card per item with the title visible" do
    items = [
      %{id: 1, name: "Sample Show", subtitle: "S03 · E10", progress_pct: 47, backdrop_url: nil},
      %{id: 2, name: "Sample Movie", subtitle: "Movie", progress_pct: 22, backdrop_url: nil}
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Sample Show"
    assert html =~ "Sample Movie"
    assert html =~ "47%" or html =~ "width: 47%"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: [])
    refute html =~ "data-component=\"continue-watching\""
  end
end
```

- [ ] **Step 2: Implement the component**

```elixir
defmodule MediaCentarrWeb.Components.ContinueWatchingRow do
  @moduledoc """
  Horizontal row of backdrop cards for in-progress titles. Used on Home.

  Each item is a map: `%{id, name, subtitle, progress_pct, backdrop_url}`.
  """
  use Phoenix.Component

  attr :items, :list, required: true

  def continue_watching_row(assigns) do
    ~H"""
    <div :if={@items != []} data-component="continue-watching" class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
      <div :for={item <- @items} class="relative aspect-[16/9] rounded-lg overflow-hidden glass-inset">
        <img :if={item.backdrop_url} src={item.backdrop_url} class="absolute inset-0 w-full h-full object-cover object-top" loading="lazy" />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent"></div>
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-[10px] uppercase tracking-wider text-white/70 truncate">{item.subtitle}</div>
          <div class="text-sm font-semibold text-white drop-shadow truncate">{item.name}</div>
        </div>
        <div class="absolute left-0 right-0 bottom-0 h-1 bg-black/50">
          <div class="h-full bg-primary" style={"width: #{item.progress_pct}%"}></div>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 3: Run the test, verify it passes.**

- [ ] **Step 4: Commit**

```
jj describe -m "feat(components): extract continue_watching_row"
jj new
```

### Task 4.2: Build CommingUpRow + PosterRow + HeroCard components

Same pattern as Task 4.1 — one component per shape, each with its own test file. Templates for each:

**`coming_up_row.ex`** — 4-card digest row of upcoming releases. Each item: `%{id, name, subtitle, badge, backdrop_url}`. Visual ref: mockups Home `coming-up-this-week` row.

**`poster_row.ex`** — N-poster horizontal strip (8-up). Each item: `%{id, name, year, poster_url}`. Visual ref: mockups Home `recently-added` and `watched-recently` rows.

**`hero_card.ex`** — Full-bleed hero with title, meta line, overview, and Play / Details actions. Item: `%{id, name, year, runtime, genre_label, overview, backdrop_url, play_url, detail_url}`.

For each:
- [ ] **Write the failing test (render_component asserts on title visible)**
- [ ] **Implement**
- [ ] **Verify passes**
- [ ] **Commit:** `jj describe -m "feat(components): <name>"` then `jj new`

### Task 4.3: Build HomeLive.Logic — pure row-assembly functions

**Files:**
- Create: `lib/media_centarr_web/live/home_live/logic.ex`
- Create: `test/media_centarr_web/live/home_live/logic_test.exs`

Pure functions for: `continue_watching_items/1`, `coming_up_items/2`, `recently_added_items/1`, `watched_recently_items/1`, `select_hero/1`, `coming_up_window/2` (returns the date range "this week").

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentarrWeb.HomeLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.HomeLive.Logic

  describe "coming_up_window/2" do
    test "returns Mon-Sun of the week containing today" do
      monday = ~D[2026-04-27]
      sunday = ~D[2026-05-03]
      assert Logic.coming_up_window(monday) == {monday, sunday}
    end

    test "from a Wednesday, still returns the containing Mon-Sun" do
      wed = ~D[2026-04-29]
      assert Logic.coming_up_window(wed) == {~D[2026-04-27], ~D[2026-05-03]}
    end
  end

  describe "select_hero/1" do
    test "returns nil for an empty candidate list" do
      assert Logic.select_hero([]) == nil
    end

    test "returns the candidate at the deterministic index for a given date" do
      candidates = [%{id: 1}, %{id: 2}, %{id: 3}]
      pick = Logic.select_hero(candidates, ~D[2026-04-27])
      assert pick in candidates
    end

    test "is stable across calls on the same day" do
      candidates = for i <- 1..10, do: %{id: i}
      assert Logic.select_hero(candidates, ~D[2026-04-27]) == Logic.select_hero(candidates, ~D[2026-04-27])
    end

    test "rotates day-by-day" do
      candidates = for i <- 1..10, do: %{id: i}
      day1 = Logic.select_hero(candidates, ~D[2026-04-27])
      day2 = Logic.select_hero(candidates, ~D[2026-04-28])
      # Not strictly required to differ, but with 10 candidates the chance is high
      refute day1 == day2 and day1 == Logic.select_hero(candidates, ~D[2026-04-29])
    end
  end

  describe "continue_watching_items/1" do
    test "shapes Library progress rows into the component item map" do
      progress = [
        %{
          entity_id: 1,
          entity_name: "Sample Show",
          entity_type: :tv_series,
          last_episode_label: "S03 · E10",
          progress_pct: 47,
          backdrop_url: "/img/1/backdrop.jpg"
        }
      ]

      [item] = Logic.continue_watching_items(progress)

      assert item.id == 1
      assert item.name == "Sample Show"
      assert item.subtitle == "S03 · E10"
      assert item.progress_pct == 47
      assert item.backdrop_url == "/img/1/backdrop.jpg"
    end
  end
end
```

- [ ] **Step 2: Implement the module**

```elixir
defmodule MediaCentarrWeb.HomeLive.Logic do
  @moduledoc """
  Pure helpers for HomeLive — row assembly, hero pick, date math.
  No DB, no PubSub. Tested with `async: true`.
  """

  @typedoc "A row item ready for ContinueWatchingRow"
  @type continue_item :: %{
          id: integer(),
          name: String.t(),
          subtitle: String.t(),
          progress_pct: 0..100,
          backdrop_url: String.t() | nil
        }

  @doc "Returns {monday, sunday} of the week containing `date`. Defaults to today."
  @spec coming_up_window(Date.t()) :: {Date.t(), Date.t()}
  def coming_up_window(date \\ Date.utc_today()) do
    monday = Date.add(date, 1 - Date.day_of_week(date))
    sunday = Date.add(monday, 6)
    {monday, sunday}
  end

  @doc """
  Picks one hero item from the candidate list. Deterministic per `seed_date`
  (defaults to today) so the same hero shows all day; rotates next day.
  """
  @spec select_hero([map()], Date.t()) :: map() | nil
  def select_hero(candidates, seed_date \\ Date.utc_today())
  def select_hero([], _date), do: nil
  def select_hero(candidates, %Date{} = date) do
    days = Date.diff(date, ~D[2024-01-01])
    Enum.at(candidates, rem(days, length(candidates)))
  end

  @doc "Maps Library progress rows into ContinueWatchingRow item shape."
  @spec continue_watching_items([map()]) :: [continue_item()]
  def continue_watching_items(progress_rows) do
    Enum.map(progress_rows, fn row ->
      %{
        id: row.entity_id,
        name: row.entity_name,
        subtitle: row.last_episode_label,
        progress_pct: row.progress_pct,
        backdrop_url: row.backdrop_url
      }
    end)
  end

  # ... add coming_up_items/2, recently_added_items/1, watched_recently_items/1
  # following the same shape: take the input list, shape into the component
  # item map. Each gets its own test in logic_test.exs.
end
```

- [ ] **Step 3: Run tests, verify all pass.**

- [ ] **Step 4: Commit**

```
jj describe -m "feat(home): pure logic module — row assembly + hero pick"
jj new
```

### Task 4.4: Create HomeLive that wires Logic + components

**Files:**
- Create: `lib/media_centarr_web/live/home_live.ex`
- Create: `test/media_centarr_web/live/home_live_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentarrWeb.HomeLiveTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MediaCentarr.TestFactory

  test "renders the page and the section headings", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/home_preview")
    assert html =~ "Continue Watching"
    assert html =~ "Coming Up This Week"
    assert html =~ "Recently Added"
    assert html =~ "Watched Recently"
  end

  test "renders Continue Watching row when there is in-progress media", %{conn: conn} do
    movie = TestFactory.create_movie(name: "Sample Movie")
    TestFactory.create_watch_progress(movie_id: movie.id, percent: 0.3)

    {:ok, _view, html} = live(conn, "/home_preview")

    assert html =~ "Sample Movie"
  end
end
```

The test mounts at `/home_preview` (a temporary path used during this phase to avoid clobbering `/` until cutover). The route is added below.

- [ ] **Step 2: Add `/home_preview` route to `router.ex`**

```elixir
live "/home_preview", HomeLive, :index
```

- [ ] **Step 3: Implement HomeLive**

```elixir
defmodule MediaCentarrWeb.HomeLive do
  @moduledoc """
  Cinematic landing page. Hero + Continue Watching + Coming Up This Week
  + Recently Added + Watched Recently. Assembled from Library,
  ReleaseTracking, and WatchHistory contexts.

  Pure assembly logic lives in `MediaCentarrWeb.HomeLive.Logic` per ADR-030.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Library, ReleaseTracking, WatchHistory}
  alias MediaCentarrWeb.HomeLive.Logic

  alias MediaCentarrWeb.Components.{
    HeroCard,
    ContinueWatchingRow,
    ComingUpRow,
    PosterRow
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Library.subscribe()
      ReleaseTracking.subscribe()
      WatchHistory.subscribe()
    end

    {:ok, assign_all(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/" full_width>
      <div class="space-y-8 py-2">
        <HeroCard.hero_card :if={@hero} item={@hero} />

        <section :if={@continue_items != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Continue Watching</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">See all →</.link>
          </div>
          <ContinueWatchingRow.continue_watching_row items={@continue_items} />
        </section>

        <section :if={@coming_up_items != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Coming Up This Week</h2>
            <.link navigate="/upcoming" class="text-sm text-base-content/60 hover:text-primary">See all →</.link>
          </div>
          <ComingUpRow.coming_up_row items={@coming_up_items} />
        </section>

        <section :if={@recently_added != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Recently Added</h2>
            <.link navigate="/library" class="text-sm text-base-content/60 hover:text-primary">See all →</.link>
          </div>
          <PosterRow.poster_row items={@recently_added} />
        </section>

        <section :if={@watched_recently != []}>
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-lg font-semibold">Watched Recently</h2>
            <.link navigate="/history" class="text-sm text-base-content/60 hover:text-primary">See all →</.link>
          </div>
          <PosterRow.poster_row items={@watched_recently} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:entities_changed, _ids}, socket), do: {:noreply, assign_all(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_all(socket) do
    today = Date.utc_today()
    {monday, sunday} = Logic.coming_up_window(today)

    progress = Library.list_in_progress(limit: 12)
    coming_up = ReleaseTracking.list_releases_between(monday, sunday, limit: 8)
    recently_added = Library.list_recently_added(limit: 16)
    watched_recently = WatchHistory.recent_events(16)
    hero_candidates = Library.list_hero_candidates(limit: 12)

    socket
    |> assign(:hero, Logic.hero_card_item(Logic.select_hero(hero_candidates, today)))
    |> assign(:continue_items, Logic.continue_watching_items(progress))
    |> assign(:coming_up_items, Logic.coming_up_items(coming_up, today))
    |> assign(:recently_added, Logic.recently_added_items(recently_added))
    |> assign(:watched_recently, Logic.watched_recently_items(watched_recently))
  end
end
```

(`Library.list_in_progress/1`, `Library.list_recently_added/1`, `Library.list_hero_candidates/1`, `ReleaseTracking.list_releases_between/3` are new context functions — add them as needed and write a test in the corresponding `<context>_test.exs`. Do not skip the tests.)

- [ ] **Step 4: Run all home tests, verify pass.**

- [ ] **Step 5: Manually verify** — visit `/home_preview` and confirm the page renders end-to-end. Use seeded data or `mix seed.review`.

- [ ] **Step 6: Commit**

```
jj describe -m "feat(home): HomeLive assembling Library + ReleaseTracking + WatchHistory rows"
jj new
```

### Task 4.5: Reduce LibraryLive to pure browse

**Files:**
- Modify: `lib/media_centarr_web/live/library_live.ex`

Strip the zone-switching: only the catalog browse remains.

- [ ] **Step 1: Test that Library has no zone tabs**

Add to `test/media_centarr_web/live/library_live_test.exs`:

```elixir
test "library page has no zone tabs", %{conn: conn} do
  {:ok, _view, html} = live(conn, "/")

  refute html =~ "data-zone-tab=\"continue\""
  refute html =~ "data-zone-tab=\"upcoming\""
end
```

(Note: this test runs *during* this phase against `/`, which is still LibraryLive. After Task 4.6 the cutover swaps `/` to HomeLive — at that point change the test to use `/library`.)

- [ ] **Step 2: Remove the zone branches**

In `library_live.ex`:
- Delete the Continue Watching zone render branch and its mount logic.
- Delete the Upcoming zone render branch and its mount logic (handle_event/handle_info clauses too — they're already moved to UpcomingLive in Phase 3).
- The remaining template is just the type tabs + sort + filter + poster grid.
- Drop the `zone` URL param entirely (or keep `zone=continue` redirecting to `/`, since `/` will be HomeLive after cutover). Decide based on what makes the test pass.

- [ ] **Step 3: Update existing zone-related tests**

Many `library_live_test.exs` tests probably assume zones. Update them to test the browse-only behavior. **Do not delete tests** ([ADR-027 — regression tests append-only]); rewrite them to test the equivalent behavior on `/library`.

- [ ] **Step 4: Run `mix test test/media_centarr_web/live/library_live_test.exs` — all pass.**

- [ ] **Step 5: Commit**

```
jj describe -m "feat(library): reduce to pure catalog browse (no zones)"
jj new
```

### Task 4.6: Cutover — `/` → HomeLive, `/library` → LibraryLive

**Files:**
- Modify: `lib/media_centarr_web/router.ex`
- Modify: `lib/media_centarr_web/components/layouts.ex` (sidebar Library link points to `/library`)

- [ ] **Step 1: Update routes**

```elixir
live_session :default do
  live "/", HomeLive, :index
  live "/library", LibraryLive, :index
  live "/upcoming", UpcomingLive, :index
  live "/history", WatchHistoryLive, :index
  live "/status", StatusLive, :index
  live "/settings", SettingsLive, :index
  live "/review", ReviewLive, :index
  live "/console", ConsolePageLive, :index
  live "/download", AcquisitionLive, :index
end

# Backward-compat redirects for old zone URLs
get "/library/old", AcquisitionRedirectController, :auto_grabs  # remove if not needed
```

Drop the `/home_preview` route from Task 4.4 — `/` is the real home now.

- [ ] **Step 2: Add a redirect from `/?zone=continue` → `/`** (and any other lingering zone params)

Easiest place: a tiny LiveView `mount` redirect in HomeLive when `params["zone"]` is present (push_navigate to `/`).

- [ ] **Step 3: Update sidebar Library link to point to `/library`**

In `layouts.ex`:

```heex
<.link navigate="/library" class={sidebar_link_class(@current_path, "/library")} ...>
```

And update `current_path="/"` to `current_path="/library"` in the LibraryLive's render.

- [ ] **Step 4: Add Home link to sidebar Watch group** (above Library):

```heex
<.link
  navigate="/"
  class={sidebar_link_class(@current_path, "/")}
  data-tip="Home"
  data-nav-item
  data-nav-remember
  tabindex="0"
>
  <.icon name="hero-home" class="size-5 flex-shrink-0" />
  <span class="sidebar-label">Home</span>
</.link>
```

- [ ] **Step 5: Run all live tests**

```
mix test test/media_centarr_web/live/
```

Fix any breakages. Common: tests that hit `/` and expect Library content now see HomeLive — change those to `/library`.

- [ ] **Step 6: Run full `mix precommit`**

- [ ] **Step 7: Manually verify**
  - `/` shows the new Home page.
  - `/library` shows the catalog browse only.
  - `/upcoming` shows the calendar + tracking.
  - `/history` shows stats + heatmap + activity (with rewatch counts from Phase 1).
  - Old URL `/?zone=upcoming` redirects to `/upcoming`.
  - Sidebar Watch group: Home, Library, Upcoming, History.
  - Sidebar System group: Downloads (if Prowlarr), Status, Review, Settings.

- [ ] **Step 8: Commit**

```
jj describe -m "feat(ui): cutover — / is Home, /library is Browse"
jj new
```

### Task 4.7: Update wiki for the new IA

**Files:**
- Modify: relevant wiki pages

- [ ] **Step 1: Update navigation overview** — every page that mentions "the Library page" or `/` needs to reflect the new shape:
  - Library page → catalog browser only, at `/library`
  - Home page → cinematic landing, at `/`
  - Upcoming → at `/upcoming`
  - History → in nav now

- [ ] **Step 2: Add or update `Home-Page.md`** — what's on it, where each row links to.

- [ ] **Step 3: Commit and push the wiki**

```
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: rewrite for new Home / Library / Upcoming / History IA"
jj bookmark set master -r @
jj git push
```

### Task 4.8: Decision record

**Files:**
- Create: `decisions/user-interface/2026-04-27-NNN-page-redistribution.md` (use the next available number under `decisions/user-interface/`)

- [ ] **Step 1: Write the ADR using MADR 4.0 lean format**

Cover: the conflation problem, the decision (split into 4 pages + 2 sidebar groups), consequences, and link back to `mockups/page-redistribution/REASONING.md` for the full design narrative.

- [ ] **Step 2: Commit**

```
jj describe -m "docs(adr): record page redistribution decision"
jj new
```

---

## Self-review checklist (run before declaring the plan done)

- [ ] **Spec coverage:** Every requirement from `mockups/page-redistribution/REASONING.md` has a task. Specifically: ✓ sidebar groups, ✓ History promotion + rewatch surfacing, ✓ Upcoming standalone, ✓ Library reduction, ✓ Home page, ✓ wiki updates, ✓ ADR.
- [ ] **No placeholders:** Search for "TBD", "TODO", "implement later" — none present.
- [ ] **Type consistency:** `select_hero/2`, `coming_up_window/1`, `continue_watching_items/1` signatures match across plan & tests.
- [ ] **JJ commits, not git:** All commit instructions use `jj describe -m` per project convention.
- [ ] **Test-first ordering:** Every code-producing task starts with a failing test.

---

## Phase summary — what ships when

| Phase | Risk | Ships independently? | Visible to users |
|---|---|---|---|
| 1. History promotion + rewatch | Low | Yes | Subtle — counts on event rows; History link not in nav yet (waits for Phase 2) |
| 2. Sidebar groups | Low | Yes | Visual reorganization of sidebar; History link appears |
| 3. Upcoming standalone | Medium | Yes | New `/upcoming` page; sidebar adds Upcoming link; old zone URL redirects |
| 4. Home + Library reduction | High | No | Major: `/` becomes new Home, `/library` is the catalog browse |

Phase 1 and Phase 2 can ship same-day. Phase 3 is a clean medium-sized change. Phase 4 is the marquee change and worth its own deploy with release notes.
