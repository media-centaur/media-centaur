# Release Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Release Tracking" bounded context that monitors TMDB for upcoming content related to the user's library, with a dedicated "Upcoming" zone in the library UI.

**Architecture:** New bounded context `MediaCentaur.ReleaseTracking` with 3 tables (items, releases, events), fully isolated from Library. Pure function modules (Extractor, Differ) handle TMDB response parsing and change detection. A GenServer (Refresher) runs daily TMDB refresh cycles. The UI adds an "Upcoming" zone tab to the existing library LiveView.

**Tech Stack:** Elixir/Phoenix, Ecto (SQLite), TMDB API via existing `TMDB.Client`, Phoenix PubSub, LiveView

**Spec:** `docs/superpowers/specs/2026-04-04-release-tracking-design.md`

---

## File Map

### New Files

| File | Responsibility |
|------|----------------|
| `priv/repo/migrations/*_create_release_tracking.exs` | 3 tables: items, releases, events |
| `lib/media_centaur/release_tracking.ex` | Context facade — public API |
| `lib/media_centaur/release_tracking/item.ex` | Item schema (tracked movie/TV series) |
| `lib/media_centaur/release_tracking/release.ex` | Release schema (episode/movie air date) |
| `lib/media_centaur/release_tracking/event.ex` | Event schema (change log) |
| `lib/media_centaur/release_tracking/extractor.ex` | Pure functions: TMDB JSON → release data |
| `lib/media_centaur/release_tracking/differ.ex` | Pure functions: old vs new → change events |
| `lib/media_centaur/release_tracking/scanner.ex` | Scan library external IDs via TMDB |
| `lib/media_centaur/release_tracking/refresher.ex` | GenServer: periodic TMDB refresh |
| `lib/media_centaur/release_tracking/image_store.ex` | Poster download to `data/images/tracking/` |
| `lib/media_centaur_web/components/upcoming_cards.ex` | Upcoming zone UI components |
| `test/media_centaur/release_tracking/extractor_test.exs` | Extractor pure function tests |
| `test/media_centaur/release_tracking/differ_test.exs` | Differ pure function tests |
| `test/media_centaur/release_tracking_test.exs` | Context facade resource tests |
| `test/media_centaur/release_tracking/scanner_test.exs` | Scanner tests with TMDB stubs |
| `test/media_centaur/release_tracking/refresher_test.exs` | Refresher tests |

### Modified Files

| File | Change |
|------|--------|
| `lib/media_centaur/topics.ex` | Add `release_tracking_updates/0` |
| `lib/media_centaur/application.ex` | Add Refresher to supervision tree |
| `lib/media_centaur_web/live/library_live.ex` | Add `:upcoming` zone, tab, handlers, PubSub |
| `lib/media_centaur_web/components/detail_panel.ex` | Add tracking icon to hero |
| `test/support/factory.ex` | Add tracking build/create helpers |
| `defaults/backend.toml` | Add `[release_tracking]` section |
| `lib/media_centaur/config.ex` | Add refresh interval config |

---

### Task 1: Database Migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_release_tracking.exs`

- [ ] **Step 1: Generate migration**

Run: `cd /home/shawn/src/media-centaur/backend && mix ecto.gen.migration create_release_tracking`

- [ ] **Step 2: Write migration**

Replace the generated migration content with:

```elixir
defmodule MediaCentaur.Repo.Migrations.CreateReleaseTracking do
  use Ecto.Migration

  def change do
    create table(:release_tracking_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "watching"
      add :source, :string, null: false, default: "library"
      add :library_entity_id, :uuid
      add :last_refreshed_at, :utc_datetime
      add :poster_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:release_tracking_items, [:tmdb_id, :media_type],
      name: "release_tracking_items_tmdb_unique"
    )

    create table(:release_tracking_releases, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :delete_all),
        null: false
      add :air_date, :date
      add :title, :string
      add :season_number, :integer
      add :episode_number, :integer
      add :released, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:release_tracking_releases, [:item_id])
    create index(:release_tracking_releases, [:air_date])

    create table(:release_tracking_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :delete_all),
        null: false
      add :event_type, :string, null: false
      add :description, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:release_tracking_events, [:item_id])
  end
end
```

- [ ] **Step 3: Run migration**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix ecto.migrate`

- [ ] **Step 4: Commit**

```
feat: add release tracking migration — 3 tables
```

---

### Task 2: Ecto Schemas

**Files:**
- Create: `lib/media_centaur/release_tracking/item.ex`
- Create: `lib/media_centaur/release_tracking/release.ex`
- Create: `lib/media_centaur/release_tracking/event.ex`

- [ ] **Step 1: Write Item schema**

```elixir
defmodule MediaCentaur.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :status, Ecto.Enum, values: [:watching, :ignored], default: :watching
    field :source, Ecto.Enum, values: [:library, :manual], default: :library
    field :library_entity_id, Ecto.UUID
    field :last_refreshed_at, :utc_datetime
    field :poster_path, :string

    has_many :releases, MediaCentaur.ReleaseTracking.Release
    has_many :events, MediaCentaur.ReleaseTracking.Event

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :media_type,
      :name,
      :status,
      :source,
      :library_entity_id,
      :last_refreshed_at,
      :poster_path
    ])
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type], name: "release_tracking_items_tmdb_unique")
  end

  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :status, :last_refreshed_at, :poster_path])
  end
end
```

- [ ] **Step 2: Write Release schema**

```elixir
defmodule MediaCentaur.ReleaseTracking.Release do
  @moduledoc """
  An individual upcoming release event — one row per episode or movie.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_releases" do
    field :air_date, :date
    field :title, :string
    field :season_number, :integer
    field :episode_number, :integer
    field :released, :boolean, default: false

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:air_date, :title, :season_number, :episode_number, :released, :item_id])
    |> validate_required([:item_id])
  end

  def update_changeset(release, attrs) do
    release
    |> cast(attrs, [:air_date, :title, :released])
  end
end
```

- [ ] **Step 3: Write Event schema**

```elixir
defmodule MediaCentaur.ReleaseTracking.Event do
  @moduledoc """
  A notable change detected during TMDB refresh — date moved, new season, etc.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_events" do
    field :event_type, Ecto.Enum,
      values: [:date_changed, :new_season_announced, :new_episodes_announced, :item_added, :item_cancelled]

    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps(updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:event_type, :description, :metadata, :item_id])
    |> validate_required([:event_type, :description, :item_id])
  end
end
```

- [ ] **Step 4: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

- [ ] **Step 5: Commit**

```
feat: add ReleaseTracking Ecto schemas — Item, Release, Event
```

---

### Task 3: Test Factory Additions

**Files:**
- Modify: `test/support/factory.ex`

- [ ] **Step 1: Add build and create helpers**

Add to `test/support/factory.ex` before the final `end`:

```elixir
  # ---------------------------------------------------------------------------
  # Release Tracking
  # ---------------------------------------------------------------------------

  alias MediaCentaur.ReleaseTracking

  def build_tracking_item(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series",
      status: :watching,
      source: :library,
      library_entity_id: nil,
      last_refreshed_at: nil,
      poster_path: nil,
      releases: [],
      events: []
    }

    struct(ReleaseTracking.Item, Map.merge(defaults, overrides))
  end

  def build_tracking_release(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      air_date: Date.add(Date.utc_today(), 30),
      title: "Episode 1",
      season_number: 1,
      episode_number: 1,
      released: false,
      item_id: nil
    }

    struct(ReleaseTracking.Release, Map.merge(defaults, overrides))
  end

  def build_tracking_event(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      event_type: :item_added,
      description: "Now tracking Test Series",
      metadata: %{},
      item_id: nil
    }

    struct(ReleaseTracking.Event, Map.merge(defaults, overrides))
  end

  def create_tracking_item(attrs \\ %{}) do
    defaults = %{
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series"
    }

    ReleaseTracking.track_item!(Map.merge(defaults, attrs))
  end

  def create_tracking_release(attrs) do
    ReleaseTracking.create_release!(attrs)
  end
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

Note: This will fail until the facade is written in Task 4. That's expected — move to Task 4.

---

### Task 4: Context Facade + Tests

**Files:**
- Create: `lib/media_centaur/release_tracking.ex`
- Create: `test/media_centaur/release_tracking_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentaur.ReleaseTrackingTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking

  describe "track_item/1" do
    test "creates a tracking item" do
      assert {:ok, item} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show Eight"
               })

      assert item.tmdb_id == 1396
      assert item.media_type == :tv_series
      assert item.status == :watching
      assert item.source == :library
    end

    test "enforces unique tmdb_id + media_type" do
      {:ok, _} =
        ReleaseTracking.track_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      assert {:error, changeset} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show Eight"
               })

      assert errors_on(changeset).tmdb_id
    end
  end

  describe "ignore_item/1 and watch_item/1" do
    test "toggles item status" do
      item = create_tracking_item(%{name: "Test Show"})
      assert item.status == :watching

      {:ok, ignored} = ReleaseTracking.ignore_item(item)
      assert ignored.status == :ignored

      {:ok, watching} = ReleaseTracking.watch_item(ignored)
      assert watching.status == :watching
    end
  end

  describe "list_watching_items/0" do
    test "returns only items with status :watching" do
      create_tracking_item(%{name: "Watching Show", tmdb_id: 100})
      ignored = create_tracking_item(%{name: "Ignored Show", tmdb_id: 200})
      ReleaseTracking.ignore_item(ignored)

      items = ReleaseTracking.list_watching_items()
      assert length(items) == 1
      assert hd(items).name == "Watching Show"
    end
  end

  describe "tracking_status/1" do
    test "returns status for tracked item" do
      create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series})
      assert ReleaseTracking.tracking_status({1396, :tv_series}) == :watching
    end

    test "returns nil for untracked item" do
      assert ReleaseTracking.tracking_status({9999, :movie}) == nil
    end
  end

  describe "create_release/1" do
    test "creates a release for an item" do
      item = create_tracking_item()

      assert {:ok, release} =
               ReleaseTracking.create_release(%{
                 item_id: item.id,
                 air_date: ~D[2026-06-15],
                 title: "Pilot",
                 season_number: 1,
                 episode_number: 1
               })

      assert release.air_date == ~D[2026-06-15]
      assert release.released == false
    end
  end

  describe "list_releases/0" do
    test "returns releases grouped as upcoming and released" do
      item = create_tracking_item()

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 30),
        title: "Future Episode",
        season_number: 1,
        episode_number: 1
      })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -5),
        title: "Past Episode",
        season_number: 1,
        episode_number: 0,
        released: true
      })

      %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()
      assert length(upcoming) == 1
      assert hd(upcoming).title == "Future Episode"
      assert length(released) == 1
      assert hd(released).title == "Past Episode"
    end
  end

  describe "create_event/1" do
    test "creates a change event" do
      item = create_tracking_item()

      assert {:ok, event} =
               ReleaseTracking.create_event(%{
                 item_id: item.id,
                 event_type: :item_added,
                 description: "Now tracking #{item.name}"
               })

      assert event.event_type == :item_added
    end
  end

  describe "list_recent_events/1" do
    test "returns events in reverse chronological order" do
      item = create_tracking_item()

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        event_type: :item_added,
        description: "First"
      })

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        event_type: :new_season_announced,
        description: "Second"
      })

      events = ReleaseTracking.list_recent_events(10)
      assert length(events) == 2
      assert hd(events).description == "Second"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking_test.exs`

Expected: Compilation error — `ReleaseTracking` module not found.

- [ ] **Step 3: Write context facade**

```elixir
defmodule MediaCentaur.ReleaseTracking do
  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Fully isolated from the Library context — owns its own tables, images,
  and TMDB extraction logic.
  """

  import Ecto.Query
  alias MediaCentaur.Repo
  alias MediaCentaur.ReleaseTracking.{Item, Release, Event}

  # --- Items ---

  def track_item(attrs) do
    Item.create_changeset(attrs) |> Repo.insert()
  end

  def track_item!(attrs) do
    Item.create_changeset(attrs) |> Repo.insert!()
  end

  def ignore_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :ignored}) |> Repo.update()
  end

  def watch_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :watching}) |> Repo.update()
  end

  def update_item(%Item{} = item, attrs) do
    Item.update_changeset(item, attrs) |> Repo.update()
  end

  def get_item(id), do: Repo.get(Item, id)

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  def list_watching_items do
    from(i in Item,
      where: i.status == :watching,
      order_by: [asc: i.name],
      preload: [:releases]
    )
    |> Repo.all()
  end

  def list_all_items do
    from(i in Item, order_by: [asc: i.name], preload: [:releases])
    |> Repo.all()
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.status
    end
  end

  # --- Releases ---

  def create_release(attrs) do
    Release.create_changeset(attrs) |> Repo.insert()
  end

  def create_release!(attrs) do
    Release.create_changeset(attrs) |> Repo.insert!()
  end

  def update_release(%Release{} = release, attrs) do
    Release.update_changeset(release, attrs) |> Repo.update()
  end

  def list_releases do
    today = Date.utc_today()

    all =
      from(r in Release,
        join: i in assoc(r, :item),
        where: i.status == :watching,
        order_by: [asc: r.air_date],
        preload: [:item]
      )
      |> Repo.all()

    upcoming = Enum.reject(all, & &1.released)
    released = Enum.filter(all, & &1.released)

    %{upcoming: upcoming, released: released}
  end

  def list_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id, order_by: [asc: r.air_date])
    |> Repo.all()
  end

  def delete_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id) |> Repo.delete_all()
  end

  # --- Events ---

  def create_event(attrs) do
    Event.create_changeset(attrs) |> Repo.insert()
  end

  def create_event!(attrs) do
    Event.create_changeset(attrs) |> Repo.insert!()
  end

  def list_recent_events(limit \\ 20) do
    from(e in Event,
      order_by: [desc: e.inserted_at],
      limit: ^limit,
      preload: [:item]
    )
    |> Repo.all()
  end

  # --- Bulk operations ---

  def mark_past_releases_as_released do
    today = Date.utc_today()

    from(r in Release,
      where: not is_nil(r.air_date) and r.air_date <= ^today and r.released == false
    )
    |> Repo.update_all(set: [released: true])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking_test.exs`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```
feat: add ReleaseTracking context facade with CRUD operations
```

---

### Task 5: PubSub Topics + Config

**Files:**
- Modify: `lib/media_centaur/topics.ex`
- Modify: `defaults/backend.toml`
- Modify: `lib/media_centaur/config.ex`

- [ ] **Step 1: Add topic to Topics module**

Add to `lib/media_centaur/topics.ex` before the final `end`:

```elixir
  def release_tracking_updates, do: "release_tracking:updates"
```

- [ ] **Step 2: Add config section to defaults/backend.toml**

Add at the end of `defaults/backend.toml`:

```toml
[release_tracking]
# How often to refresh TMDB data for tracked items (in hours)
refresh_interval_hours = 24
```

- [ ] **Step 3: Add config loading**

In `lib/media_centaur/config.ex`, add to the `defaults` map in `load_config/0`:

```elixir
release_tracking_refresh_interval_hours: 24,
```

And in `merge_toml/2`:

```elixir
release_tracking_refresh_interval_hours:
  get_in(toml, ["release_tracking", "refresh_interval_hours"]) ||
    defaults.release_tracking_refresh_interval_hours,
```

- [ ] **Step 4: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

- [ ] **Step 5: Commit**

```
feat: add release tracking PubSub topic and config
```

---

### Task 6: Extractor — TDD

**Files:**
- Create: `test/media_centaur/release_tracking/extractor_test.exs`
- Create: `lib/media_centaur/release_tracking/extractor.ex`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentaur.ReleaseTracking.ExtractorTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.Extractor

  describe "extract_tv_status/1" do
    test "maps Returning Series" do
      assert Extractor.extract_tv_status(%{"status" => "Returning Series"}) == :returning
    end

    test "maps Ended" do
      assert Extractor.extract_tv_status(%{"status" => "Ended"}) == :ended
    end

    test "maps Canceled" do
      assert Extractor.extract_tv_status(%{"status" => "Canceled"}) == :canceled
    end

    test "maps In Production" do
      assert Extractor.extract_tv_status(%{"status" => "In Production"}) == :in_production
    end

    test "maps Planned" do
      assert Extractor.extract_tv_status(%{"status" => "Planned"}) == :planned
    end

    test "returns :unknown for missing status" do
      assert Extractor.extract_tv_status(%{}) == :unknown
    end
  end

  describe "extract_tv_releases/1" do
    test "extracts next_episode_to_air" do
      response = %{
        "next_episode_to_air" => %{
          "air_date" => "2026-06-15",
          "season_number" => 3,
          "episode_number" => 1,
          "name" => "The Return"
        },
        "status" => "Returning Series"
      }

      assert [release] = Extractor.extract_tv_releases(response)
      assert release.air_date == ~D[2026-06-15]
      assert release.season_number == 3
      assert release.episode_number == 1
      assert release.title == "The Return"
    end

    test "returns empty list for ended show with no next episode" do
      response = %{
        "next_episode_to_air" => nil,
        "status" => "Ended"
      }

      assert [] = Extractor.extract_tv_releases(response)
    end

    test "handles nil air_date in next_episode_to_air" do
      response = %{
        "next_episode_to_air" => %{
          "air_date" => nil,
          "season_number" => 2,
          "episode_number" => 1,
          "name" => "TBA"
        },
        "status" => "Returning Series"
      }

      assert [release] = Extractor.extract_tv_releases(response)
      assert release.air_date == nil
      assert release.season_number == 2
    end

    test "handles missing next_episode_to_air key" do
      response = %{"status" => "Returning Series"}
      assert [] = Extractor.extract_tv_releases(response)
    end
  end

  describe "extract_season_releases/1" do
    test "extracts future episodes from season data" do
      today = Date.utc_today()
      future = Date.to_iso8601(Date.add(today, 7))
      past = Date.to_iso8601(Date.add(today, -7))

      season = %{
        "season_number" => 2,
        "episodes" => [
          %{"episode_number" => 1, "name" => "Past Ep", "air_date" => past},
          %{"episode_number" => 2, "name" => "Future Ep", "air_date" => future},
          %{"episode_number" => 3, "name" => "No Date", "air_date" => nil}
        ]
      }

      releases = Extractor.extract_season_releases(season)
      assert length(releases) == 2

      future_ep = Enum.find(releases, &(&1.episode_number == 2))
      assert future_ep.title == "Future Ep"
      assert future_ep.season_number == 2

      no_date = Enum.find(releases, &(&1.episode_number == 3))
      assert no_date.air_date == nil
    end
  end

  describe "extract_movie_status/1" do
    test "maps Released" do
      assert Extractor.extract_movie_status(%{"status" => "Released"}) == :released
    end

    test "maps In Production" do
      assert Extractor.extract_movie_status(%{"status" => "In Production"}) == :in_production
    end

    test "maps Post Production" do
      assert Extractor.extract_movie_status(%{"status" => "Post Production"}) == :post_production
    end

    test "maps Planned" do
      assert Extractor.extract_movie_status(%{"status" => "Planned"}) == :planned
    end

    test "maps Rumored" do
      assert Extractor.extract_movie_status(%{"status" => "Rumored"}) == :rumored
    end

    test "maps Canceled" do
      assert Extractor.extract_movie_status(%{"status" => "Canceled"}) == :canceled
    end
  end

  describe "extract_collection_releases/1" do
    test "extracts unreleased movies from collection parts" do
      collection = %{
        "parts" => [
          %{"id" => 1, "title" => "Movie 1", "release_date" => "2020-01-01"},
          %{"id" => 2, "title" => "Movie 2", "release_date" => "2027-12-25"},
          %{"id" => 3, "title" => "Movie 3", "release_date" => ""}
        ]
      }

      releases = Extractor.extract_collection_releases(collection)
      assert length(releases) == 2

      movie2 = Enum.find(releases, &(&1.title == "Movie 2"))
      assert movie2.air_date == ~D[2027-12-25]
      assert movie2.tmdb_id == 2

      movie3 = Enum.find(releases, &(&1.title == "Movie 3"))
      assert movie3.air_date == nil
    end

    test "returns empty for all-released collection" do
      collection = %{
        "parts" => [
          %{"id" => 1, "title" => "Movie 1", "release_date" => "2020-01-01"}
        ]
      }

      assert [] = Extractor.extract_collection_releases(collection)
    end
  end

  describe "extract_poster_path/1" do
    test "returns poster_path from response" do
      assert Extractor.extract_poster_path(%{"poster_path" => "/abc.jpg"}) == "/abc.jpg"
    end

    test "returns nil when missing" do
      assert Extractor.extract_poster_path(%{}) == nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/extractor_test.exs`

Expected: Compilation error — `Extractor` module not found.

- [ ] **Step 3: Write Extractor implementation**

```elixir
defmodule MediaCentaur.ReleaseTracking.Extractor do
  @moduledoc """
  Pure functions that extract release tracking data from raw TMDB JSON responses.
  """

  @tv_status_map %{
    "Returning Series" => :returning,
    "Ended" => :ended,
    "Canceled" => :canceled,
    "In Production" => :in_production,
    "Planned" => :planned
  }

  @movie_status_map %{
    "Released" => :released,
    "In Production" => :in_production,
    "Post Production" => :post_production,
    "Planned" => :planned,
    "Rumored" => :rumored,
    "Canceled" => :canceled
  }

  def extract_tv_status(response) do
    Map.get(@tv_status_map, response["status"], :unknown)
  end

  def extract_tv_releases(response) do
    case response["next_episode_to_air"] do
      nil -> []
      episode -> [parse_episode_release(episode)]
    end
  end

  def extract_season_releases(season) do
    today = Date.utc_today()
    season_number = season["season_number"]

    (season["episodes"] || [])
    |> Enum.filter(fn episode ->
      case parse_date(episode["air_date"]) do
        nil -> true
        date -> Date.after?(date, today)
      end
    end)
    |> Enum.map(fn episode ->
      %{
        air_date: parse_date(episode["air_date"]),
        season_number: season_number,
        episode_number: episode["episode_number"],
        title: episode["name"]
      }
    end)
  end

  def extract_movie_status(response) do
    Map.get(@movie_status_map, response["status"], :unknown)
  end

  def extract_collection_releases(collection) do
    today = Date.utc_today()

    (collection["parts"] || [])
    |> Enum.filter(fn part ->
      case parse_date(part["release_date"]) do
        nil -> true
        date -> Date.after?(date, today)
      end
    end)
    |> Enum.map(fn part ->
      %{
        air_date: parse_date(part["release_date"]),
        title: part["title"],
        tmdb_id: part["id"]
      }
    end)
  end

  def extract_poster_path(response), do: response["poster_path"]

  defp parse_episode_release(episode) do
    %{
      air_date: parse_date(episode["air_date"]),
      season_number: episode["season_number"],
      episode_number: episode["episode_number"],
      title: episode["name"]
    }
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/extractor_test.exs`

Expected: All pass.

- [ ] **Step 5: Commit**

```
feat: add ReleaseTracking.Extractor — TMDB JSON extraction
```

---

### Task 7: Differ — TDD

**Files:**
- Create: `test/media_centaur/release_tracking/differ_test.exs`
- Create: `lib/media_centaur/release_tracking/differ.ex`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentaur.ReleaseTracking.DifferTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory
  alias MediaCentaur.ReleaseTracking.Differ

  describe "diff/2" do
    test "detects no changes" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"}]

      assert [] = Differ.diff(old, new)
    end

    test "detects date change" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-07-01], title: "Pilot"}]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :date_changed
      assert event.metadata.old_date == ~D[2026-06-15]
      assert event.metadata.new_date == ~D[2026-07-01]
    end

    test "detects new episodes" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [
        %{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"},
        %{season_number: 1, episode_number: 2, air_date: ~D[2026-06-22], title: "Second"}
      ]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :new_episodes_announced
    end

    test "detects new season" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 5,
          air_date: ~D[2026-06-15],
          title: "Finale"
        })
      ]

      new = [
        %{season_number: 1, episode_number: 5, air_date: ~D[2026-06-15], title: "Finale"},
        %{season_number: 2, episode_number: 1, air_date: ~D[2026-12-01], title: "Premiere"}
      ]

      events = Differ.diff(old, new)
      assert Enum.any?(events, &(&1.event_type == :new_season_announced))
    end

    test "detects removed releases" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        }),
        build_tracking_release(%{
          season_number: 1,
          episode_number: 2,
          air_date: ~D[2026-06-22],
          title: "Second"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"}]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :date_changed
      assert String.contains?(event.description, "removed")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/differ_test.exs`

Expected: Compilation error — `Differ` module not found.

- [ ] **Step 3: Write Differ implementation**

```elixir
defmodule MediaCentaur.ReleaseTracking.Differ do
  @moduledoc """
  Pure functions that compare stored releases against freshly extracted releases
  and produce change events.
  """

  @doc """
  Compares old stored releases (Ecto structs) against new extracted releases (maps).
  Returns a list of event maps with `:event_type`, `:description`, and `:metadata`.
  """
  def diff(old_releases, new_releases) do
    old_by_key = index_by_key(old_releases)
    new_by_key = index_by_key(new_releases)

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    date_changes = detect_date_changes(common_keys, old_by_key, new_by_key)
    additions = detect_additions(added_keys, new_by_key, old_by_key)
    removals = detect_removals(removed_keys, old_by_key)

    date_changes ++ additions ++ removals
  end

  defp index_by_key(releases) do
    Map.new(releases, fn r ->
      # Include title in key to distinguish multiple movie releases (both nil/nil)
      key = {get_field(r, :season_number), get_field(r, :episode_number), get_field(r, :title)}
      {key, r}
    end)
  end

  defp get_field(%{} = map, field) when is_struct(map), do: Map.get(map, field)
  defp get_field(%{} = map, field), do: Map.get(map, field)

  defp detect_date_changes(keys, old_by_key, new_by_key) do
    keys
    |> Enum.flat_map(fn key ->
      old = old_by_key[key]
      new = new_by_key[key]
      old_date = get_field(old, :air_date)
      new_date = get_field(new, :air_date)

      if old_date != new_date do
        [%{
          event_type: :date_changed,
          description: format_date_change(key, old_date, new_date),
          metadata: %{
            old_date: old_date,
            new_date: new_date,
            season_number: elem(key, 0),
            episode_number: elem(key, 1),
            title: elem(key, 2)
          }
        }]
      else
        []
      end
    end)
  end

  defp detect_additions(keys, new_by_key, old_by_key) do
    new_seasons =
      keys
      |> Enum.map(fn key -> elem(key, 0) end)
      |> Enum.uniq()
      |> Enum.reject(fn season ->
        Enum.any?(Map.keys(old_by_key), fn {s, _e} -> s == season end)
      end)

    season_events =
      Enum.map(new_seasons, fn season ->
        count = Enum.count(keys, fn {s, _e} -> s == season end)

        %{
          event_type: :new_season_announced,
          description: "Season #{season} announced (#{count} episode#{if count > 1, do: "s", else: ""})",
          metadata: %{season_number: season, episode_count: count}
        }
      end)

    episode_keys =
      MapSet.reject(keys, fn {s, _e} -> s in new_seasons end)

    episode_events =
      if MapSet.size(episode_keys) > 0 do
        count = MapSet.size(episode_keys)

        [%{
          event_type: :new_episodes_announced,
          description: "#{count} new episode#{if count > 1, do: "s", else: ""} announced",
          metadata: %{count: count}
        }]
      else
        []
      end

    season_events ++ episode_events
  end

  defp detect_removals(keys, old_by_key) do
    Enum.map(keys, fn key ->
      old = old_by_key[key]
      title = get_field(old, :title) || if(elem(key, 0), do: "S#{elem(key, 0)}E#{elem(key, 1)}", else: "Unknown")

      %{
        event_type: :date_changed,
        description: "#{title} removed from schedule",
        metadata: %{
          old_date: get_field(old, :air_date),
          new_date: nil,
          season_number: elem(key, 0),
          episode_number: elem(key, 1)
        }
      }
    end)
  end

  defp format_date_change(key, old_date, new_date) do
    label =
      if elem(key, 0) do
        "S#{elem(key, 0)}E#{elem(key, 1)}"
      else
        elem(key, 2) || "Unknown"
      end
    old_str = if old_date, do: Date.to_iso8601(old_date), else: "unannounced"
    new_str = if new_date, do: Date.to_iso8601(new_date), else: "unannounced"
    "#{label} moved from #{old_str} to #{new_str}"
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/differ_test.exs`

Expected: All pass.

- [ ] **Step 5: Commit**

```
feat: add ReleaseTracking.Differ — release change detection
```

---

### Task 8: ImageStore

**Files:**
- Create: `lib/media_centaur/release_tracking/image_store.ex`

- [ ] **Step 1: Write ImageStore module**

```elixir
defmodule MediaCentaur.ReleaseTracking.ImageStore do
  @moduledoc """
  Downloads and manages poster images for tracked items.
  Stores to `data/images/tracking/{tmdb_id}/poster.jpg`.
  """

  require MediaCentaur.Log, as: Log

  @base_url "https://image.tmdb.org/t/p/w500"
  @tracking_images_dir "data/images/tracking"

  def download_poster(tmdb_id, tmdb_poster_path) when is_binary(tmdb_poster_path) do
    url = @base_url <> tmdb_poster_path
    dir = Path.join(@tracking_images_dir, to_string(tmdb_id))
    dest = Path.join(dir, "poster.jpg")

    File.mkdir_p!(dir)

    downloader = Application.get_env(:media_centaur, :image_http_client, MediaCentaur.ImageDownloader)

    case downloader.download(url, dest) do
      :ok ->
        Log.info(:library, "downloaded tracking poster for tmdb_id=#{tmdb_id}")
        {:ok, relative_path(dest)}

      {:error, reason} ->
        Log.info(:library, "failed to download tracking poster: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def download_poster(_tmdb_id, nil), do: {:ok, nil}

  def poster_path(tmdb_id) do
    dest = Path.join([@tracking_images_dir, to_string(tmdb_id), "poster.jpg"])
    if File.exists?(dest), do: relative_path(dest), else: nil
  end

  defp relative_path(path), do: Path.relative_to(path, "data")
  end
```

Note: The `ImageDownloader` module and `NoopImageDownloader` (test stub) already exist in the project. This module follows the same pattern.

- [ ] **Step 2: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```
feat: add ReleaseTracking.ImageStore — poster download
```

---

### Task 9: Scanner — TDD

**Files:**
- Create: `test/media_centaur/release_tracking/scanner_test.exs`
- Create: `lib/media_centaur/release_tracking/scanner.ex`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentaur.ReleaseTracking.ScannerTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Scanner

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "scan/0" do
    test "tracks a TV series with upcoming episodes" do
      tv_series = create_tv_series(%{name: "Sample Show Eight"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1396"})

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-06-15",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 1
      assert results.skipped == 0

      items = ReleaseTracking.list_watching_items()
      assert length(items) == 1
      assert hd(items).tmdb_id == 1396
      assert hd(items).library_entity_id == tv_series.id
    end

    test "skips ended TV series with no upcoming episodes" do
      tv_series = create_tv_series(%{name: "Sample Show"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1438"})

      stub_routes([
        {"/tv/1438",
         %{
           "id" => 1438,
           "name" => "Sample Show",
           "status" => "Ended",
           "poster_path" => "/wire.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 0
      assert results.skipped == 1
    end

    test "tracks movie collection with unreleased parts" do
      movie_series = create_movie_series(%{name: "Dark Knight Collection"})

      create_external_id(%{
        movie_series_id: movie_series.id,
        source: "tmdb_collection",
        external_id: "263"
      })

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Dark Knight Collection",
           "poster_path" => "/dk.jpg",
           "parts" => [
             %{"id" => 155, "title" => "The Shadowy Sentinel", "release_date" => "2008-07-18"},
             %{"id" => 99999, "title" => "The Shadowy Sentinel Returns", "release_date" => "2027-07-01"}
           ]
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 1
      items = ReleaseTracking.list_watching_items()
      assert hd(items).media_type == :movie
    end

    test "is idempotent — skips already tracked items" do
      tv_series = create_tv_series(%{name: "Sample Show Eight"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1396"})

      create_tracking_item(%{
        tmdb_id: 1396,
        media_type: :tv_series,
        name: "Sample Show Eight"
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-06-15",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      {:ok, results} = Scanner.scan()
      assert results.skipped == 1
      assert results.tracked == 0
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/scanner_test.exs`

Expected: Compilation error — `Scanner` module not found.

- [ ] **Step 3: Write Scanner implementation**

```elixir
defmodule MediaCentaur.ReleaseTracking.Scanner do
  @moduledoc """
  Scans the library for items with TMDB external IDs and creates tracking
  items for any with upcoming releases.
  """

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.Library.ExternalId
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Extractor

  def scan do
    external_ids = load_library_tmdb_ids()
    Log.info(:library, "release tracking scan: #{length(external_ids)} TMDB IDs found")

    results =
      Enum.reduce(external_ids, %{tracked: 0, skipped: 0, errors: 0}, fn ext_id, acc ->
        case process_external_id(ext_id) do
          :tracked -> %{acc | tracked: acc.tracked + 1}
          :skipped -> %{acc | skipped: acc.skipped + 1}
          :error -> %{acc | errors: acc.errors + 1}
        end
      end)

    Log.info(:library, "release tracking scan complete: #{inspect(results)}")
    {:ok, results}
  end

  defp load_library_tmdb_ids do
    from(e in ExternalId,
      where: e.source in ["tmdb", "tmdb_collection"],
      select: %{
        source: e.source,
        external_id: e.external_id,
        tv_series_id: e.tv_series_id,
        movie_series_id: e.movie_series_id,
        movie_id: e.movie_id
      }
    )
    |> Repo.all()
  end

  defp process_external_id(%{source: "tmdb", tv_series_id: tv_series_id} = ext_id)
       when not is_nil(tv_series_id) do
    tmdb_id = parse_tmdb_id(ext_id.external_id)

    if already_tracked?(tmdb_id, :tv_series) do
      :skipped
    else
      process_tv_series(tmdb_id, tv_series_id)
    end
  end

  defp process_external_id(%{source: "tmdb_collection", movie_series_id: movie_series_id} = ext_id)
       when not is_nil(movie_series_id) do
    collection_id = parse_tmdb_id(ext_id.external_id)

    if already_tracked?(collection_id, :movie) do
      :skipped
    else
      process_collection(collection_id, movie_series_id)
    end
  end

  defp process_external_id(_), do: :skipped

  defp process_tv_series(tmdb_id, library_entity_id) do
    case Client.get_tv(tmdb_id) do
      {:ok, response} ->
        status = Extractor.extract_tv_status(response)

        if status in [:returning, :in_production, :planned] do
          releases = Extractor.extract_tv_releases(response)
          create_tracked_item(tmdb_id, :tv_series, response["name"], library_entity_id, releases, response)
          :tracked
        else
          :skipped
        end

      {:error, _reason} ->
        :error
    end
  end

  defp process_collection(collection_id, library_entity_id) do
    case Client.get_collection(collection_id) do
      {:ok, response} ->
        releases = Extractor.extract_collection_releases(response)

        if releases != [] do
          collection_releases =
            Enum.map(releases, fn r ->
              %{air_date: r.air_date, title: r.title, season_number: nil, episode_number: nil}
            end)

          create_tracked_item(
            collection_id,
            :movie,
            response["name"],
            library_entity_id,
            collection_releases,
            response
          )

          :tracked
        else
          :skipped
        end

      {:error, _reason} ->
        :error
    end
  end

  defp create_tracked_item(tmdb_id, media_type, name, library_entity_id, releases, response) do
    {:ok, item} =
      ReleaseTracking.track_item(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: name,
        source: :library,
        library_entity_id: library_entity_id,
        last_refreshed_at: DateTime.utc_now()
      })

    Enum.each(releases, fn release ->
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: release.air_date,
        title: release.title,
        season_number: release[:season_number],
        episode_number: release[:episode_number]
      })
    end)

    ReleaseTracking.create_event!(%{
      item_id: item.id,
      event_type: :item_added,
      description: "Now tracking #{name}"
    })

    # Download poster in background (non-blocking)
    poster_path = Extractor.extract_poster_path(response)

    if poster_path do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        case ReleaseTracking.ImageStore.download_poster(tmdb_id, poster_path) do
          {:ok, path} when is_binary(path) ->
            ReleaseTracking.update_item(item, %{poster_path: path})

          _ ->
            :ok
        end
      end)
    end

    :ok
  end

  defp already_tracked?(tmdb_id, media_type) do
    ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type) != nil
  end

  defp parse_tmdb_id(id) when is_integer(id), do: id
  defp parse_tmdb_id(id) when is_binary(id), do: String.to_integer(id)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/scanner_test.exs`

Expected: All pass.

- [ ] **Step 5: Commit**

```
feat: add ReleaseTracking.Scanner — library TMDB scan
```

---

### Task 10: Refresher GenServer

**Files:**
- Create: `lib/media_centaur/release_tracking/refresher.ex`
- Create: `test/media_centaur/release_tracking/refresher_test.exs`
- Modify: `lib/media_centaur/application.ex`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule MediaCentaur.ReleaseTracking.RefresherTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Refresher

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "refresh_item/1" do
    test "updates releases and detects date changes for TV series" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2026-06-15],
        title: "Return",
        season_number: 6,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-07-01",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      :ok = Refresher.refresh_item(item)

      events = ReleaseTracking.list_recent_events(10)
      assert Enum.any?(events, &(&1.event_type == :date_changed))

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert hd(releases).air_date == ~D[2026-07-01]
    end

    test "marks past releases as released" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -3),
        title: "Past Episode",
        season_number: 1,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      :ok = Refresher.refresh_item(item)

      {_count, _} = ReleaseTracking.mark_past_releases_as_released()
      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert hd(releases).released == true
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/refresher_test.exs`

Expected: Compilation error — `Refresher` module not found.

- [ ] **Step 3: Write Refresher implementation**

```elixir
defmodule MediaCentaur.ReleaseTracking.Refresher do
  @moduledoc """
  GenServer that periodically refreshes TMDB data for all tracked items.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Differ}
  alias MediaCentaur.TMDB.Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def refresh_all do
    GenServer.cast(__MODULE__, :refresh_all)
  end

  @doc "Refresh a single item. Can be called directly in tests."
  def refresh_item(%ReleaseTracking.Item{} = item) do
    do_refresh_item(item)
  end

  @impl true
  def init(_opts) do
    interval = refresh_interval_ms()
    schedule_refresh(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:refresh, state) do
    do_refresh_all()
    schedule_refresh(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_all, state) do
    do_refresh_all()
    {:noreply, state}
  end

  defp do_refresh_all do
    Log.info(:library, "release tracking: starting refresh cycle")

    items = ReleaseTracking.list_watching_items()

    Enum.each(items, fn item ->
      case do_refresh_item(item) do
        :ok -> :ok
        {:error, reason} -> Log.info(:library, "refresh failed for #{item.name}: #{inspect(reason)}")
      end
    end)

    ReleaseTracking.mark_past_releases_as_released()

    changed_ids = Enum.map(items, & &1.id)

    if changed_ids != [] do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.release_tracking_updates(),
        {:releases_updated, changed_ids}
      )
    end

    Log.info(:library, "release tracking: refresh complete (#{length(items)} items)")
  end

  defp do_refresh_item(%{media_type: :tv_series} = item) do
    case Client.get_tv(item.tmdb_id) do
      {:ok, response} ->
        old_releases = ReleaseTracking.list_releases_for_item(item.id)
        new_releases = Extractor.extract_tv_releases(response)

        events = Differ.diff(old_releases, new_releases)
        write_events(item, events)
        replace_releases(item, new_releases)
        update_item_metadata(item, response)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_refresh_item(%{media_type: :movie} = item) do
    case Client.get_collection(item.tmdb_id) do
      {:ok, response} ->
        old_releases = ReleaseTracking.list_releases_for_item(item.id)

        new_releases =
          Extractor.extract_collection_releases(response)
          |> Enum.map(fn r ->
            %{air_date: r.air_date, title: r.title, season_number: nil, episode_number: nil}
          end)

        events = Differ.diff(old_releases, new_releases)
        write_events(item, events)
        replace_releases(item, new_releases)
        update_item_metadata(item, response)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_events(item, events) do
    Enum.each(events, fn event ->
      ReleaseTracking.create_event!(%{
        item_id: item.id,
        event_type: event.event_type,
        description: event.description,
        metadata: event.metadata
      })
    end)
  end

  defp replace_releases(item, new_releases) do
    ReleaseTracking.delete_releases_for_item(item.id)

    Enum.each(new_releases, fn release ->
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: release[:air_date],
        title: release[:title],
        season_number: release[:season_number],
        episode_number: release[:episode_number]
      })
    end)
  end

  defp update_item_metadata(item, response) do
    name = response["name"] || response["title"] || item.name
    ReleaseTracking.update_item(item, %{name: name, last_refreshed_at: DateTime.utc_now()})
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp refresh_interval_ms do
    hours = MediaCentaur.Config.get(:release_tracking_refresh_interval_hours) || 24
    hours * 60 * 60 * 1000
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centaur/release_tracking/refresher_test.exs`

Expected: All pass.

- [ ] **Step 5: Add Refresher to supervision tree**

In `lib/media_centaur/application.ex`, add to the `children` list after `MediaCentaur.Review.Intake` in `pubsub_listeners/1`:

```elixir
  defp pubsub_listeners(:test), do: []

  defp pubsub_listeners(_env) do
    [
      MediaCentaur.Library.Inbound,
      MediaCentaur.Review.Intake,
      MediaCentaur.ReleaseTracking.Refresher
    ]
  end
```

- [ ] **Step 6: Verify compilation and all tests**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test`

Expected: All tests pass, zero warnings.

- [ ] **Step 7: Commit**

```
feat: add ReleaseTracking.Refresher — periodic TMDB refresh
```

---

### Task 11: UI — Upcoming Zone Tab

**Files:**
- Modify: `lib/media_centaur_web/live/library_live.ex`

- [ ] **Step 1: Add `:upcoming` to `parse_zone/1`**

In `library_live.ex`, change `parse_zone/1` from:

```elixir
defp parse_zone("library"), do: :library
defp parse_zone(_), do: :watching
```

To:

```elixir
defp parse_zone("library"), do: :library
defp parse_zone("upcoming"), do: :upcoming
defp parse_zone(_), do: :watching
```

- [ ] **Step 2: Add upcoming tab to the zone tablist**

In the render function, after the Library tab link, add the Upcoming tab:

```elixir
<.link
  patch={@upcoming_path}
  role="tab"
  class={["tab", @zone == :upcoming && "tab-active"]}
  data-nav-item
  data-nav-zone-value="upcoming"
  tabindex="0"
>
  Upcoming
</.link>
```

- [ ] **Step 3: Add `@upcoming_path` assign**

In `mount/3`, add to the assigns:

```elixir
upcoming_path: ~p"/?zone=upcoming",
upcoming_releases: %{upcoming: [], released: []},
upcoming_events: [],
scanning: false,
```

- [ ] **Step 4: Add PubSub subscription**

In `mount/3`, add after the existing PubSub subscriptions:

```elixir
Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.release_tracking_updates())
```

- [ ] **Step 5: Handle upcoming zone in `handle_params/3`**

Add to `handle_params/3` — update the presentation case:

```elixir
presentation =
  case {selected_id, zone} do
    {nil, _} -> nil
    {_, :watching} -> :modal
    {_, :library} -> :modal
    {_, :upcoming} -> nil
  end
```

And after assigning zone, load upcoming data when entering the zone:

```elixir
socket =
  if zone == :upcoming && socket.assigns.zone != :upcoming do
    load_upcoming(socket)
  else
    socket
  end
```

- [ ] **Step 6: Add `load_upcoming/1` private function**

```elixir
defp load_upcoming(socket) do
  releases = MediaCentaur.ReleaseTracking.list_releases()
  events = MediaCentaur.ReleaseTracking.list_recent_events(10)
  assign(socket, upcoming_releases: releases, upcoming_events: events)
end
```

- [ ] **Step 7: Add `build_path/2` support for `:upcoming`**

In `build_path/2`, add after the library zone params:

```elixir
params = if zone == :upcoming, do: Map.put(params, :zone, :upcoming), else: params
```

- [ ] **Step 8: Handle scan event**

```elixir
def handle_event("scan_library", _params, socket) do
  Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
    MediaCentaur.ReleaseTracking.Scanner.scan()
  end)

  {:noreply, assign(socket, scanning: true)}
end
```

- [ ] **Step 9: Handle PubSub refresh**

```elixir
def handle_info({:releases_updated, _item_ids}, socket) do
  if socket.assigns.zone == :upcoming do
    {:noreply, load_upcoming(socket) |> assign(scanning: false)}
  else
    {:noreply, assign(socket, scanning: false)}
  end
end
```

- [ ] **Step 10: Add upcoming zone section to render**

After the Library browse section, add:

```elixir
<section :if={@zone == :upcoming} id="upcoming" class="space-y-6 pb-8">
  <UpcomingCards.upcoming_zone
    releases={@upcoming_releases}
    events={@upcoming_events}
    scanning={@scanning}
  />
</section>
```

Add the alias at the top of the module:

```elixir
alias MediaCentaurWeb.Components.UpcomingCards
```

- [ ] **Step 11: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

Note: Will fail until UpcomingCards is created in Task 12. Move to Task 12.

---

### Task 12: UI — Upcoming Components

**Files:**
- Create: `lib/media_centaur_web/components/upcoming_cards.ex`

- [ ] **Step 1: Write UpcomingCards component module**

```elixir
defmodule MediaCentaurWeb.Components.UpcomingCards do
  @moduledoc """
  Components for the Upcoming releases zone.
  """
  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents

  attr :releases, :map, required: true
  attr :events, :list, required: true
  attr :scanning, :boolean, default: false

  def upcoming_zone(assigns) do
    grouped = group_by_date(assigns.releases.upcoming)
    no_date = Enum.filter(assigns.releases.upcoming, &is_nil(&1.air_date))
    with_date = Enum.reject(assigns.releases.upcoming, &is_nil(&1.air_date))
    grouped_with_date = group_by_date(with_date)

    watching_items = extract_watching_items(assigns.releases.upcoming)
    movie_items = Enum.filter(watching_items, &(&1.item.media_type == :movie))
    tv_items = Enum.filter(watching_items, &(&1.item.media_type == :tv_series))

    assigns =
      assigns
      |> assign(:released, assigns.releases.released)
      |> assign(:grouped, grouped_with_date)
      |> assign(:no_date, no_date)
      |> assign(:movie_items, movie_items)
      |> assign(:tv_items, tv_items)

    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Upcoming Releases</h2>
        <button
          phx-click="scan_library"
          class="btn btn-soft btn-primary btn-sm"
          disabled={@scanning}
        >
          <.icon name="hero-magnifying-glass-mini" class="size-4" />
          {if @scanning, do: "Scanning…", else: "Scan Library"}
        </button>
      </div>

      <.released_section :if={@released != []} releases={@released} />
      <.summary_section :if={@movie_items != [] || @tv_items != []} movie_items={@movie_items} tv_items={@tv_items} />
      <.chronological_list :if={@grouped != [] || @no_date != []} grouped={@grouped} no_date={@no_date} />
      <.events_section :if={@events != []} events={@events} />

      <div :if={@movie_items == [] && @tv_items == [] && @released == []} class="text-center py-12 text-base-content/40">
        <.icon name="hero-calendar-mini" class="size-8 mx-auto mb-2" />
        <p>No upcoming releases tracked</p>
        <p class="text-sm">Click "Scan Library" to find shows and movies with upcoming content</p>
      </div>
    </div>
    """
  end

  attr :releases, :list, required: true

  defp released_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-sm font-medium text-success">Released</h3>
      <div class="space-y-1">
        <div :for={release <- @releases} class="flex items-center gap-3 text-sm text-base-content/60">
          <span class="text-base-content/40">{format_date(release.air_date)}</span>
          <span>{release.item.name}</span>
          <span :if={release.title} class="text-base-content/40">— {release.title}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :movie_items, :list, required: true
  attr :tv_items, :list, required: true

  defp summary_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :if={@movie_items != []} class="space-y-1">
        <h3 class="text-sm font-medium text-base-content/60">Movies</h3>
        <div :for={entry <- @movie_items} class="text-sm">
          <span class="font-medium">{entry.item.name}</span>
          <span class="text-base-content/50">
            {if entry.release, do: "— #{format_date(entry.release.air_date)}", else: "— release date unknown"}
          </span>
        </div>
      </div>
      <div :if={@tv_items != []} class="space-y-1">
        <h3 class="text-sm font-medium text-base-content/60">TV Series</h3>
        <div :for={entry <- @tv_items} class="text-sm">
          <span class="font-medium">{entry.item.name}</span>
          <span class="text-base-content/50">
            {format_next_episode(entry.release)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :grouped, :list, required: true
  attr :no_date, :list, required: true

  defp chronological_list(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :for={{date, releases} <- @grouped} class="space-y-1">
        <h3 class="text-sm font-medium text-base-content/60">{format_date(date)}</h3>
        <div :for={release <- releases} class="text-sm pl-4">
          <span class="font-medium">{release.item.name}</span>
          <span :if={release.season_number}>: Season {release.season_number} Episode {release.episode_number}</span>
          <span :if={release.title} class="text-base-content/50"> — "{release.title}"</span>
        </div>
      </div>
      <div :if={@no_date != []} class="space-y-1">
        <h3 class="text-sm font-medium text-base-content/40">Release date unknown</h3>
        <div :for={release <- @no_date} class="text-sm pl-4">
          <span class="font-medium">{release.item.name}</span>
          <span :if={release.season_number}>: Season {release.season_number} Episode {release.episode_number}</span>
          <span :if={release.title} class="text-base-content/50"> — "{release.title}"</span>
        </div>
      </div>
    </div>
    """
  end

  attr :events, :list, required: true

  defp events_section(assigns) do
    ~H"""
    <details class="collapse collapse-arrow bg-base-200/50 rounded-box">
      <summary class="collapse-title text-sm font-medium min-h-0 py-2">
        Recent Changes
      </summary>
      <div class="collapse-content space-y-1">
        <div :for={event <- @events} class="text-sm text-base-content/60">
          <span class="text-base-content/40">{format_datetime(event.inserted_at)}</span>
          <span class="font-medium">{event.item.name}</span>
          <span>— {event.description}</span>
        </div>
      </div>
    </details>
    """
  end

  # --- Helpers ---

  defp group_by_date(releases) do
    releases
    |> Enum.group_by(& &1.air_date)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
  end

  defp extract_watching_items(releases) do
    releases
    |> Enum.uniq_by(& &1.item_id)
    |> Enum.map(fn release ->
      %{item: release.item, release: release}
    end)
  end

  defp format_next_episode(nil), do: "— no date announced"

  defp format_next_episode(release) do
    date_str = if release.air_date, do: format_date(release.air_date), else: "date unknown"
    "— Season #{release.season_number} Episode #{release.episode_number} (#{date_str})"
  end

  defp format_date(nil), do: "TBA"

  defp format_date(date) do
    Calendar.strftime(date, "%B %-d, %Y")
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_date()
    |> format_date()
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors`

- [ ] **Step 3: Verify all tests still pass**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test`

- [ ] **Step 4: Commit**

```
feat: add Upcoming zone tab and components to library UI
```

---

### Task 13: UI — Detail Panel Tracking Icon

**Files:**
- Modify: `lib/media_centaur_web/components/detail_panel.ex`
- Modify: `lib/media_centaur_web/live/library_live.ex`

- [ ] **Step 1: Add tracking_status attr to detail_panel**

In `detail_panel.ex`, add to the attrs list:

```elixir
attr :tracking_status, :atom, default: nil
```

- [ ] **Step 2: Add tracking icon to hero component**

In the `hero/1` function, add a tracking icon inside the `aspect-[21/9]` div, after the gradient overlay and before the bottom logo/title area. Add `tracking_status` attr to hero:

```elixir
attr :entity, :map, required: true
attr :tracking_status, :atom, default: nil
```

Then update the hero call in `detail_panel/1`:

```elixir
<.hero entity={@entity} tracking_status={@tracking_status} />
```

Add inside the hero template, after the gradient div (line 170) and before the bottom-4 div (line 171):

```elixir
<button
  :if={@tracking_status != nil}
  phx-click="toggle_tracking"
  class="absolute top-3 right-3 btn btn-circle btn-ghost btn-sm opacity-60 hover:opacity-100 transition-opacity"
  title={tracking_title(@tracking_status)}
>
  <.icon
    name={tracking_icon(@tracking_status)}
    class={"size-5 #{tracking_color(@tracking_status)}"}
  />
</button>
```

Add helper functions in `detail_panel.ex`:

```elixir
defp tracking_icon(:watching), do: "hero-bell-solid"
defp tracking_icon(:ignored), do: "hero-bell-slash"
defp tracking_icon(_), do: "hero-bell"

defp tracking_color(:watching), do: "text-info"
defp tracking_color(:ignored), do: "text-base-content/30"
defp tracking_color(_), do: "text-base-content/20"

defp tracking_title(:watching), do: "Tracking new releases — click to ignore"
defp tracking_title(:ignored), do: "Ignoring new releases — click to track"
defp tracking_title(_), do: "Not tracking"
```

- [ ] **Step 3: Add tracking_status to library_live assigns**

In `library_live.ex`, add to mount assigns:

```elixir
tracking_status: nil,
```

- [ ] **Step 4: Load tracking status when selecting an entity**

In the helper that resolves a selected entity (wherever `selected_entry` is computed), add tracking status lookup. Add a private function:

```elixir
defp load_tracking_status(entry) do
  case find_tmdb_id(entry) do
    {tmdb_id, media_type} ->
      MediaCentaur.ReleaseTracking.tracking_status({tmdb_id, media_type})

    nil ->
      nil
  end
end

defp find_tmdb_id(%{entity: %{type: :tv_series} = entity}) do
  case Enum.find(entity.external_ids, &(&1.source == "tmdb")) do
    nil -> nil
    ext_id -> {String.to_integer(ext_id.external_id), :tv_series}
  end
end

defp find_tmdb_id(%{entity: %{type: :movie_series} = entity}) do
  case Enum.find(entity.external_ids, &(&1.source == "tmdb_collection")) do
    nil -> nil
    ext_id -> {String.to_integer(ext_id.external_id), :movie}
  end
end

defp find_tmdb_id(_), do: nil
```

Update the assign where `selected_entry` changes to also set `tracking_status`:

```elixir
tracking_status: if(selected_entry, do: load_tracking_status(selected_entry), else: nil)
```

- [ ] **Step 5: Handle toggle_tracking event**

```elixir
def handle_event("toggle_tracking", _params, socket) do
  selected_entry = socket.assigns.selected_entry

  case {socket.assigns.tracking_status, find_tmdb_id(selected_entry)} do
    {:watching, {tmdb_id, media_type}} ->
      item = MediaCentaur.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
      if item, do: MediaCentaur.ReleaseTracking.ignore_item(item)
      {:noreply, assign(socket, tracking_status: :ignored)}

    {:ignored, {tmdb_id, media_type}} ->
      item = MediaCentaur.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
      if item, do: MediaCentaur.ReleaseTracking.watch_item(item)
      {:noreply, assign(socket, tracking_status: :watching)}

    _ ->
      {:noreply, socket}
  end
end
```

- [ ] **Step 6: Pass tracking_status to detail_panel in render**

Where `detail_panel` is rendered (in the modal), add:

```elixir
tracking_status={@tracking_status}
```

- [ ] **Step 7: Verify compilation and all tests**

Run: `cd /home/shawn/src/media-centaur/backend && MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test`

Expected: All pass, zero warnings.

- [ ] **Step 8: Commit**

```
feat: add tracking toggle icon to entity detail panel
```

---

### Task 14: Final Verification

- [ ] **Step 1: Run full precommit**

Run: `cd /home/shawn/src/media-centaur/backend && mix precommit`

Expected: Zero warnings, all tests pass, formatting clean.

- [ ] **Step 2: Manual verification**

Start dev server and verify:
1. Library → "Upcoming" tab appears and renders
2. Click "Scan Library" → items populate (if TMDB API key is configured)
3. Released section appears for past items
4. Chronological list groups by date
5. Open a library entity detail → tracking icon visible (if entity has TMDB ID)
6. Click tracking icon → toggles between watching/ignored

- [ ] **Step 3: Describe the change**

Run: `jj describe -m "feat: add new release tracking feature — TMDB-powered upcoming releases"`
