# Watch History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `WatchHistory` bounded context that records each completion event, a `/history` page with stats bar + heatmap + event list, and a dashboard widget in `LibraryLive`.

**Architecture:** `WatchHistory.Recorder` (GenServer) subscribes to `"playback:events"` and writes a `WatchEvent` row when `changed_record.completed == true`. The facade exposes `subscribe/0`, `list_events/1`, `stats/0`, `get_event!/1`, `create_event/1`, and `delete_event!/1`. `WatchHistoryLive` at `/history` subscribes to `"watch_history:events"` for real-time updates and renders an SVG heatmap.

**Tech Stack:** Elixir 1.17, Phoenix LiveView, Ecto/PostgreSQL, DaisyUI/Tailwind, inline SVG for heatmap.

---

## File Map

**Create:**
- `priv/repo/migrations/20260411120000_create_watch_history_events.exs`
- `lib/media_centaur/watch_history/event.ex`
- `lib/media_centaur/watch_history/stats.ex`
- `lib/media_centaur/watch_history/recorder.ex`
- `lib/media_centaur/watch_history.ex`
- `lib/media_centaur_web/live/watch_history_live.ex`
- `test/media_centaur/watch_history/event_test.exs`
- `test/media_centaur/watch_history/stats_test.exs`
- `test/media_centaur/watch_history/recorder_test.exs`
- `test/media_centaur_web/live/watch_history_live_test.exs`

**Modify:**
- `lib/media_centaur/topics.ex` — add `watch_history_events/0`
- `lib/media_centaur/application.ex` — add `Recorder` to `pubsub_listeners/1`
- `lib/media_centaur_web/router.ex` — add `/history` route
- `lib/media_centaur_web/live/library_live.ex` — history widget + subscribe
- `test/support/factory.ex` — add `build_watch_event/1`, `create_watch_event/1`

---

## Task 1: Migration

**Files:**
- Create: `priv/repo/migrations/20260411120000_create_watch_history_events.exs`

- [ ] **Write the migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.CreateWatchHistoryEvents do
  use Ecto.Migration

  def change do
    create table(:watch_history_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :entity_type, :string, null: false
      add :title, :string, null: false
      add :duration_seconds, :float, null: false, default: 0.0
      add :completed_at, :utc_datetime, null: false

      add :movie_id, references(:library_movies, type: :uuid, on_delete: :nilify_all)
      add :episode_id, references(:library_episodes, type: :uuid, on_delete: :nilify_all)
      add :video_object_id, references(:library_video_objects, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:watch_history_events, [:completed_at])
    create index(:watch_history_events, [:entity_type])
    create index(:watch_history_events, [:movie_id])
    create index(:watch_history_events, [:episode_id])
    create index(:watch_history_events, [:video_object_id])
  end
end
```

- [ ] **Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running 20260411120000 CreateWatchHistoryEvents.change/0 forward` with no errors.

- [ ] **Commit**

```bash
jj describe -m "feat: add watch_history_events migration"
jj new
```

---

## Task 2: WatchHistory.Event schema

**Files:**
- Create: `lib/media_centaur/watch_history/event.ex`
- Create: `test/media_centaur/watch_history/event_test.exs`

- [ ] **Write the failing test**

```elixir
# test/media_centaur/watch_history/event_test.exs
defmodule MediaCentaur.WatchHistory.EventTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.WatchHistory.Event

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        entity_type: :movie,
        title: "Sample Movie Thirteen",
        duration_seconds: 9360.0,
        completed_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = Event.create_changeset(attrs)
      assert changeset.valid?
    end

    test "requires entity_type, title, duration_seconds, and completed_at" do
      changeset = Event.create_changeset(%{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :entity_type)
      assert Keyword.has_key?(changeset.errors, :title)
      assert Keyword.has_key?(changeset.errors, :duration_seconds)
      assert Keyword.has_key?(changeset.errors, :completed_at)
    end

    test "entity_type rejects unknown values" do
      attrs = %{entity_type: :book, title: "X", duration_seconds: 0.0, completed_at: DateTime.utc_now()}
      changeset = Event.create_changeset(attrs)
      refute changeset.valid?
    end
  end

  describe "nilify_all on entity deletion" do
    test "movie_id is nilified when movie is deleted" do
      movie = create_movie(%{name: "Sample Movie"})

      {:ok, event} =
        Event.create_changeset(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: "Sample Movie",
          duration_seconds: 7080.0,
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> MediaCentaur.Repo.insert()

      MediaCentaur.Repo.delete!(movie)
      reloaded = MediaCentaur.Repo.get!(Event, event.id)

      assert reloaded.movie_id == nil
      assert reloaded.title == "Sample Movie"
    end
  end
end
```

- [ ] **Run test to verify it fails**

```bash
mix test test/media_centaur/watch_history/event_test.exs
```

Expected: compile error (module doesn't exist yet).

- [ ] **Write the schema**

```elixir
# lib/media_centaur/watch_history/event.ex
defmodule MediaCentaur.WatchHistory.Event do
  @moduledoc """
  A single completion event. Append-only — one row per time a title is watched
  to completion (≥90%). Re-watching creates a new row.

  FKs are nilify_all so history survives entity deletion. `title` is denormalized
  for the same reason — display remains meaningful after an entity is removed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "watch_history_events" do
    field :entity_type, Ecto.Enum, values: [:movie, :episode, :video_object]
    field :title, :string
    field :duration_seconds, :float
    field :completed_at, :utc_datetime

    belongs_to :movie, MediaCentaur.Library.Movie
    belongs_to :episode, MediaCentaur.Library.Episode
    belongs_to :video_object, MediaCentaur.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :entity_type,
      :title,
      :duration_seconds,
      :completed_at,
      :movie_id,
      :episode_id,
      :video_object_id
    ])
    |> validate_required([:entity_type, :title, :duration_seconds, :completed_at])
  end
end
```

- [ ] **Run tests to verify they pass**

```bash
mix test test/media_centaur/watch_history/event_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add WatchHistory.Event schema"
jj new
```

---

## Task 3: WatchHistory.Stats (pure functions)

**Files:**
- Create: `lib/media_centaur/watch_history/stats.ex`
- Create: `test/media_centaur/watch_history/stats_test.exs`

- [ ] **Write the failing tests**

```elixir
# test/media_centaur/watch_history/stats_test.exs
defmodule MediaCentaur.WatchHistory.StatsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.WatchHistory.{Event, Stats}

  defp make_event(date, duration_seconds \\ 7200.0) do
    %Event{
      completed_at: DateTime.new!(date, ~T[20:00:00], "Etc/UTC"),
      duration_seconds: duration_seconds
    }
  end

  describe "compute/1" do
    test "returns zeros for empty list" do
      assert Stats.compute([]) == %{
               total_count: 0,
               total_seconds: 0.0,
               streak: 0,
               heatmap: %{}
             }
    end

    test "sums count and seconds" do
      events = [make_event(~D[2026-04-10], 7200.0), make_event(~D[2026-04-09], 3600.0)]
      result = Stats.compute(events)
      assert result.total_count == 2
      assert result.total_seconds == 10_800.0
    end
  end

  describe "streak/1" do
    test "returns 0 for empty list" do
      assert Stats.streak([]) == 0
    end

    test "counts consecutive days ending today" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      events = [make_event(today), make_event(yesterday)]
      assert Stats.streak(events) == 2
    end

    test "yesterday alone keeps streak at 1 (grace period)" do
      yesterday = Date.add(Date.utc_today(), -1)
      events = [make_event(yesterday)]
      assert Stats.streak(events) == 1
    end

    test "breaks on a gap" do
      today = Date.utc_today()
      two_ago = Date.add(today, -2)
      events = [make_event(today), make_event(two_ago)]
      assert Stats.streak(events) == 1
    end

    test "multiple completions on same day count as one streak day" do
      today = Date.utc_today()
      events = [make_event(today), make_event(today), make_event(today)]
      assert Stats.streak(events) == 1
    end
  end

  describe "heatmap/1" do
    test "returns empty map for empty list" do
      assert Stats.heatmap([]) == %{}
    end

    test "counts completions per day" do
      date = ~D[2026-04-10]
      events = [make_event(date), make_event(date)]
      assert Stats.heatmap(events)[date] == 2
    end

    test "excludes events older than 364 days" do
      old_date = Date.add(Date.utc_today(), -365)
      events = [make_event(old_date)]
      assert Stats.heatmap(events) == %{}
    end
  end

  describe "heatmap_cells/1" do
    test "returns 364 cells covering last 52 weeks" do
      cells = Stats.heatmap_cells(%{})
      assert length(cells) == 364
    end

    test "each cell has :date, :count, :x, :y" do
      [cell | _] = Stats.heatmap_cells(%{})
      assert Map.has_key?(cell, :date)
      assert Map.has_key?(cell, :count)
      assert Map.has_key?(cell, :x)
      assert Map.has_key?(cell, :y)
    end

    test "last cell is today" do
      cells = Stats.heatmap_cells(%{})
      last = List.last(cells)
      assert last.date == Date.utc_today()
    end

    test "populates count from heatmap data" do
      today = Date.utc_today()
      cells = Stats.heatmap_cells(%{today => 5})
      last = List.last(cells)
      assert last.count == 5
    end
  end
end
```

- [ ] **Run tests to verify they fail**

```bash
mix test test/media_centaur/watch_history/stats_test.exs
```

Expected: compile error (module not found).

- [ ] **Write Stats module**

```elixir
# lib/media_centaur/watch_history/stats.ex
defmodule MediaCentaur.WatchHistory.Stats do
  @moduledoc """
  Pure functions for computing watch history statistics from a list of
  `WatchHistory.Event` structs. No database access — all queries happen
  in the `WatchHistory` facade before calling these functions.
  """

  @cell_size 11
  @cell_gap 2
  @cell_step @cell_size + @cell_gap
  @days 364

  @doc """
  Compute aggregate stats from a list of events.
  Returns %{total_count, total_seconds, streak, heatmap}.
  """
  def compute(events) do
    %{
      total_count: length(events),
      total_seconds: total_seconds(events),
      streak: streak(events),
      heatmap: heatmap(events)
    }
  end

  @doc "Sum duration_seconds across all events."
  def total_seconds([]), do: 0.0
  def total_seconds(events), do: Enum.reduce(events, 0.0, &(&1.duration_seconds + &2))

  @doc """
  Count consecutive days with at least one completion, ending today or yesterday.
  Multiple completions on the same day count as a single streak day.
  """
  def streak([]), do: 0

  def streak(events) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    dates =
      events
      |> Enum.map(fn e -> DateTime.to_date(e.completed_at) end)
      |> Enum.uniq()
      |> Enum.sort({:desc, Date})

    start = if today in dates, do: today, else: yesterday
    count_consecutive(dates, start, 0)
  end

  @doc """
  Group completion counts by date for the last 364 days.
  Returns %{Date => count}.
  """
  def heatmap(events) do
    cutoff = Date.add(Date.utc_today(), -(@days - 1))

    events
    |> Enum.filter(fn e -> Date.compare(DateTime.to_date(e.completed_at), cutoff) != :lt end)
    |> Enum.group_by(fn e -> DateTime.to_date(e.completed_at) end)
    |> Map.new(fn {date, evts} -> {date, length(evts)} end)
  end

  @doc """
  Generate the list of SVG cell descriptors for the heatmap grid (last 364 days).
  Each cell: %{date: Date, count: integer, x: integer, y: integer}.
  Weeks go left-to-right; days go top-to-bottom within each week.
  """
  def heatmap_cells(heatmap_data) do
    today = Date.utc_today()
    start_date = Date.add(today, -(@days - 1))

    Date.range(start_date, today)
    |> Enum.to_list()
    |> Enum.chunk_every(7)
    |> Enum.with_index()
    |> Enum.flat_map(fn {week_dates, week_idx} ->
      Enum.with_index(week_dates, fn date, day_idx ->
        %{
          date: date,
          count: Map.get(heatmap_data, date, 0),
          x: week_idx * @cell_step,
          y: day_idx * @cell_step
        }
      end)
    end)
  end

  # --- Private ---

  defp count_consecutive([], _expected, count), do: count

  defp count_consecutive([date | rest], expected, count) do
    if date == expected do
      count_consecutive(rest, Date.add(expected, -1), count + 1)
    else
      count
    end
  end
end
```

- [ ] **Run tests to verify they pass**

```bash
mix test test/media_centaur/watch_history/stats_test.exs
```

Expected: 12 tests, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add WatchHistory.Stats pure functions"
jj new
```

---

## Task 4: WatchHistory facade

**Files:**
- Create: `lib/media_centaur/watch_history.ex`
- Modify: `lib/media_centaur/topics.ex`

- [ ] **Add topic to Topics**

In `lib/media_centaur/topics.ex`, add after `release_tracking_updates`:

```elixir
def watch_history_events, do: "watch_history:events"
```

- [ ] **Write the facade**

```elixir
# lib/media_centaur/watch_history.ex
defmodule MediaCentaur.WatchHistory do
  @moduledoc """
  Public API for the WatchHistory bounded context.

  Records a permanent, append-only `WatchEvent` for each completion (≥90%
  playback threshold). The `Recorder` GenServer drives writes; this module
  exposes queries and the `delete_event!/1` mutation.
  """
  import Ecto.Query

  alias MediaCentaur.{Library, Repo, Topics}
  alias MediaCentaur.WatchHistory.{Event, Stats}

  @doc "Subscribe to watch_history:events PubSub topic."
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.watch_history_events())
  end

  @doc "Insert a new WatchEvent. Called by Recorder."
  def create_event(attrs) do
    attrs
    |> Event.create_changeset()
    |> Repo.insert()
  end

  @doc "Get a single event by id, raising if not found."
  def get_event!(id), do: Repo.get!(Event, id)

  @doc """
  List completion events, newest first.

  Options:
  - `:entity_type` — filter to `:movie`, `:episode`, or `:video_object`
  - `:search` — case-insensitive title substring match
  - `:date` — filter to a specific `Date`
  - `:limit` — max rows (default 100)
  """
  def list_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    entity_type = Keyword.get(opts, :entity_type)
    search = Keyword.get(opts, :search)
    date = Keyword.get(opts, :date)

    Event
    |> maybe_filter_type(entity_type)
    |> maybe_filter_search(search)
    |> maybe_filter_date(date)
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Return 5 most recent completion events for the dashboard widget.
  """
  def recent_events(limit \\ 5) do
    Event
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Compute aggregate stats from all events.
  Returns %{total_count, total_seconds, streak, heatmap}.
  """
  def stats do
    events = Repo.all(Event)
    Stats.compute(events)
  end

  @doc """
  Delete a WatchEvent and reset the associated WatchProgress to incomplete.

  If the entity FK has been nilified (entity was deleted), the WatchProgress
  reset is skipped. Always returns the deleted event.
  """
  def delete_event!(%Event{} = event) do
    Repo.delete!(event)
    reset_watch_progress(event)
    event
  end

  # --- Private ---

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [e], e.entity_type == ^type)

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    where(query, [e], ilike(e.title, ^"%#{search}%"))
  end

  defp maybe_filter_date(query, nil), do: query

  defp maybe_filter_date(query, %Date{} = date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    where(query, [e], e.completed_at >= ^start_dt and e.completed_at <= ^end_dt)
  end

  defp reset_watch_progress(%Event{movie_id: movie_id}) when not is_nil(movie_id) do
    case Library.get_watch_progress_by_fk(:movie_id, movie_id) do
      {:ok, progress} ->
        Library.mark_watch_incomplete(progress)

        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          Topics.library_updates(),
          {:entities_changed, [movie_id]}
        )

      _ ->
        :ok
    end
  end

  defp reset_watch_progress(%Event{episode_id: episode_id}) when not is_nil(episode_id) do
    case Library.get_watch_progress_by_fk(:episode_id, episode_id) do
      {:ok, progress} -> Library.mark_watch_incomplete(progress)
      _ -> :ok
    end
  end

  defp reset_watch_progress(%Event{video_object_id: video_object_id})
       when not is_nil(video_object_id) do
    case Library.get_watch_progress_by_fk(:video_object_id, video_object_id) do
      {:ok, progress} ->
        Library.mark_watch_incomplete(progress)

        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          Topics.library_updates(),
          {:entities_changed, [video_object_id]}
        )

      _ ->
        :ok
    end
  end

  defp reset_watch_progress(_event), do: :ok
end
```

- [ ] **Compile to verify no errors**

```bash
mix compile --force 2>&1 | grep -E "error|warning"
```

Expected: no output (zero errors and warnings).

- [ ] **Commit**

```bash
jj describe -m "feat: add WatchHistory facade + topic"
jj new
```

---

## Task 5: WatchHistory.Recorder GenServer + supervision

**Files:**
- Create: `lib/media_centaur/watch_history/recorder.ex`
- Create: `test/media_centaur/watch_history/recorder_test.exs`
- Modify: `lib/media_centaur/application.ex`

- [ ] **Write the failing test**

```elixir
# test/media_centaur/watch_history/recorder_test.exs
defmodule MediaCentaur.WatchHistory.RecorderTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.{Event, Recorder}

  setup do
    # Recorder is excluded from pubsub_listeners in test env — start it manually
    {:ok, pid} = Recorder.start_link([])
    %{recorder: pid}
  end

  describe "handle_info :entity_progress_updated" do
    test "records a WatchEvent when a movie is completed", %{recorder: recorder} do
      movie = create_movie(%{name: "Sample Movie"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          completed: true,
          duration_seconds: 8880.0
        })

      WatchHistory.subscribe()

      send(recorder, {:entity_progress_updated, %{
        entity_id: movie.id,
        changed_record: progress,
        summary: nil,
        resume_target: nil,
        child_targets_delta: nil,
        last_activity_at: DateTime.utc_now()
      }})

      assert_receive {:watch_event_created, event}, 2000
      assert event.title == "Sample Movie"
      assert event.entity_type == :movie
      assert event.movie_id == movie.id
      assert_in_delta event.duration_seconds, 8880.0, 0.01
    end

    test "records a WatchEvent when an episode is completed", %{recorder: recorder} do
      tv_series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 4})

      progress =
        create_watch_progress(%{
          episode_id: episode.id,
          completed: true,
          duration_seconds: 3600.0
        })

      WatchHistory.subscribe()

      send(recorder, {:entity_progress_updated, %{
        entity_id: tv_series.id,
        changed_record: progress,
        summary: nil,
        resume_target: nil,
        child_targets_delta: nil,
        last_activity_at: DateTime.utc_now()
      }})

      assert_receive {:watch_event_created, event}, 2000
      assert event.title == "Sample Show S01E04"
      assert event.entity_type == :episode
      assert event.episode_id == episode.id
    end

    test "ignores progress updates where completed is false", %{recorder: recorder} do
      movie = create_movie(%{name: "Sample Movie Thirteen"})
      progress = create_watch_progress(%{movie_id: movie.id, completed: false, duration_seconds: 9000.0})

      WatchHistory.subscribe()

      send(recorder, {:entity_progress_updated, %{
        entity_id: movie.id,
        changed_record: progress,
        summary: nil,
        resume_target: nil,
        child_targets_delta: nil,
        last_activity_at: DateTime.utc_now()
      }})

      refute_receive {:watch_event_created, _}, 500
      assert WatchHistory.list_events() == []
    end
  end
end
```

- [ ] **Run test to verify it fails**

```bash
mix test test/media_centaur/watch_history/recorder_test.exs
```

Expected: compile error (Recorder not defined).

- [ ] **Write the Recorder**

```elixir
# lib/media_centaur/watch_history/recorder.ex
defmodule MediaCentaur.WatchHistory.Recorder do
  @moduledoc """
  GenServer that subscribes to `"playback:events"` and records a `WatchEvent`
  whenever a movie, episode, or video object is completed (≥90% threshold).

  The `MpvSession.maybe_mark_completed/3` guard (`not record.completed`) ensures
  this broadcast fires exactly once per physical viewing — no dedup needed here.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Repo, Topics, WatchHistory}
  alias MediaCentaur.Library.{Episode, Movie, Season, TVSeries, VideoObject}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.playback_events())
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        {:entity_progress_updated, %{changed_record: %{completed: true} = record}},
        state
      ) do
    record_completion(record)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp record_completion(record) do
    case build_event_attrs(record) do
      {:ok, attrs} ->
        case WatchHistory.create_event(attrs) do
          {:ok, event} ->
            Phoenix.PubSub.broadcast(
              MediaCentaur.PubSub,
              Topics.watch_history_events(),
              {:watch_event_created, event}
            )

            Log.info(:library, "watch history: recorded — #{attrs.title}")

          {:error, reason} ->
            Log.error(:library, "watch history: insert failed — #{inspect(reason)}")
        end

      {:error, reason} ->
        Log.error(:library, "watch history: could not resolve title — #{inspect(reason)}")
    end
  end

  defp build_event_attrs(%{movie_id: movie_id} = record) when not is_nil(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :movie_not_found}

      movie ->
        {:ok,
         %{
           entity_type: :movie,
           movie_id: movie_id,
           title: movie.name,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
         }}
    end
  end

  defp build_event_attrs(%{episode_id: episode_id} = record) when not is_nil(episode_id) do
    case Repo.get(Episode, episode_id) do
      nil ->
        {:error, :episode_not_found}

      episode ->
        episode = Repo.preload(episode, season: :tv_series)
        title = format_episode_title(episode)

        {:ok,
         %{
           entity_type: :episode,
           episode_id: episode_id,
           title: title,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
         }}
    end
  end

  defp build_event_attrs(%{video_object_id: video_object_id} = record)
       when not is_nil(video_object_id) do
    case Repo.get(VideoObject, video_object_id) do
      nil ->
        {:error, :video_object_not_found}

      video_object ->
        {:ok,
         %{
           entity_type: :video_object,
           video_object_id: video_object_id,
           title: video_object.name,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
         }}
    end
  end

  defp format_episode_title(episode) do
    season_num = String.pad_leading("#{episode.season.season_number}", 2, "0")
    ep_num = String.pad_leading("#{episode.episode_number}", 2, "0")
    "#{episode.season.tv_series.name} S#{season_num}E#{ep_num}"
  end
end
```

- [ ] **Add Recorder to supervision tree**

In `lib/media_centaur/application.ex`, add `MediaCentaur.WatchHistory.Recorder` to the `pubsub_listeners/1` function:

```elixir
defp pubsub_listeners(_env) do
  [
    MediaCentaur.Library.Inbound,
    MediaCentaur.Review.Intake,
    MediaCentaur.ReleaseTracking.Refresher,
    MediaCentaur.WatchHistory.Recorder
  ]
end
```

- [ ] **Run tests to verify they pass**

```bash
mix test test/media_centaur/watch_history/recorder_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add WatchHistory.Recorder GenServer"
jj new
```

---

## Task 6: delete_event! tests + factory additions

**Files:**
- Modify: `test/support/factory.ex`
- The delete test goes in `test/media_centaur/watch_history/event_test.exs`

- [ ] **Add factory helpers**

In `test/support/factory.ex`, add these two functions (alongside the other build/create pairs):

```elixir
def build_watch_event(overrides \\ %{}) do
  defaults = %{
    id: Ecto.UUID.generate(),
    entity_type: :movie,
    movie_id: nil,
    episode_id: nil,
    video_object_id: nil,
    title: "Test Movie",
    duration_seconds: 7200.0,
    completed_at: DateTime.truncate(DateTime.utc_now(), :second)
  }

  struct(MediaCentaur.WatchHistory.Event, Map.merge(defaults, overrides))
end

def create_watch_event(attrs \\ %{}) do
  defaults = %{
    entity_type: :movie,
    title: "Test Movie",
    duration_seconds: 7200.0,
    completed_at: DateTime.truncate(DateTime.utc_now(), :second)
  }

  {:ok, event} =
    Map.merge(defaults, attrs)
    |> MediaCentaur.WatchHistory.create_event()

  event
end
```

- [ ] **Write delete_event! tests — add to existing event test file**

Append to `test/media_centaur/watch_history/event_test.exs`:

```elixir
describe "WatchHistory.delete_event!/1" do
  test "deletes the event record" do
    movie = create_movie(%{name: "Sample Movie Eight"})
    event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Eight"})

    MediaCentaur.WatchHistory.delete_event!(event)

    assert_raise Ecto.NoResultsError, fn ->
      MediaCentaur.Repo.get!(MediaCentaur.WatchHistory.Event, event.id)
    end
  end

  test "resets watch progress to incomplete" do
    movie = create_movie(%{name: "Sample Movie Fourteen"})
    progress = create_watch_progress(%{movie_id: movie.id, completed: true})
    event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Fourteen"})

    MediaCentaur.WatchHistory.delete_event!(event)

    {:ok, reloaded} = MediaCentaur.Library.get_watch_progress_by_fk(:movie_id, movie.id)
    assert reloaded.completed == false
  end

  test "succeeds when FK is nil (entity already deleted)" do
    event = create_watch_event(%{entity_type: :movie, movie_id: nil, title: "Ghost Movie"})
    result = MediaCentaur.WatchHistory.delete_event!(event)
    assert result.id == event.id
  end
end
```

- [ ] **Run tests to verify they pass**

```bash
mix test test/media_centaur/watch_history/event_test.exs
```

Expected: 6 tests, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add delete_event! and factory helpers"
jj new
```

---

## Task 7: WatchHistoryLive page + route

**Files:**
- Create: `lib/media_centaur_web/live/watch_history_live.ex`
- Modify: `lib/media_centaur_web/router.ex`
- Create: `test/media_centaur_web/live/watch_history_live_test.exs`

- [ ] **Write the failing test**

```elixir
# test/media_centaur_web/live/watch_history_live_test.exs
defmodule MediaCentaurWeb.WatchHistoryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders the history page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Watch History"
    end

    test "shows zero stats when no events", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "0"
    end

    test "shows completion events", %{conn: conn} do
      movie = create_movie(%{name: "Sample Anime One"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Anime One"})
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Sample Anime One"
    end

    test "shows stat totals", %{conn: conn} do
      create_watch_event(%{title: "Movie A", duration_seconds: 3600.0})
      create_watch_event(%{title: "Movie B", duration_seconds: 7200.0})
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "2"
    end
  end

  describe "type filter" do
    test "filter_type event narrows the list", %{conn: conn} do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :video_object, title: "A Video"})

      {:ok, view, _html} = live(conn, "/history")

      html =
        view
        |> element("[phx-click='filter_type'][phx-value-type='movie']")
        |> render_click()

      assert html =~ "A Movie"
      refute html =~ "A Video"
    end
  end

  describe "search filter" do
    test "filter_search narrows the list by title", %{conn: conn} do
      create_watch_event(%{title: "Sample Movie"})
      create_watch_event(%{title: "Alien"})

      {:ok, view, _html} = live(conn, "/history")

      html =
        view
        |> element("input[phx-change='filter_search']")
        |> render_change(%{"value" => "Blade"})

      assert html =~ "Sample Movie"
      refute html =~ "Alien"
    end
  end

  describe "real-time updates" do
    test "a new watch_event_created broadcast adds the event to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/history")
      assert render(view) =~ "0"

      movie = create_movie(%{name: "Sample Movie Thirteen"})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Thirteen"})

      send(view.pid, {:watch_event_created, event})
      assert render(view) =~ "Sample Movie Thirteen"
    end
  end
end
```

- [ ] **Run test to verify it fails**

```bash
mix test test/media_centaur_web/live/watch_history_live_test.exs
```

Expected: compile error or route error.

- [ ] **Add route**

In `lib/media_centaur_web/router.ex`, inside `live_session :default`:

```elixir
live_session :default do
  live "/", LibraryLive, :index
  live "/status", StatusLive, :index
  live "/settings", SettingsLive, :index
  live "/review", ReviewLive, :index
  live "/console", ConsolePageLive, :index
  live "/history", WatchHistoryLive, :index
end
```

- [ ] **Write WatchHistoryLive**

```elixir
# lib/media_centaur_web/live/watch_history_live.ex
defmodule MediaCentaurWeb.WatchHistoryLive do
  @moduledoc """
  Watch history page — stats bar, GitHub-style heatmap, and a filterable
  completion event list with real-time updates and mark-as-unwatched.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Format, WatchHistory}
  alias MediaCentaur.WatchHistory.Stats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WatchHistory.subscribe()

    stats = WatchHistory.stats()
    events = WatchHistory.list_events()

    {:ok,
     assign(socket,
       stats: stats,
       heatmap_cells: Stats.heatmap_cells(stats.heatmap),
       events: events,
       filter_type: nil,
       filter_search: "",
       filter_date: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/history">
      <div class="max-w-5xl mx-auto space-y-8 py-6" data-page-behavior="watch-history">
        <h1 class="text-2xl font-bold">Watch History</h1>

        <%!-- Stats bar --%>
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">Titles Completed</div>
            <div class="stat-value"><%= @stats.total_count %></div>
          </div>
          <div class="stat">
            <div class="stat-title">Hours Watched</div>
            <div class="stat-value"><%= format_hours(@stats.total_seconds) %></div>
          </div>
          <div class="stat">
            <div class="stat-title">Current Streak</div>
            <div class="stat-value"><%= @stats.streak %>d</div>
            <div class="stat-desc"><%= if @stats.streak == 0, do: "No active streak", else: "consecutive days" %></div>
          </div>
        </div>

        <%!-- Heatmap --%>
        <div class="bg-base-200 rounded-box p-4 overflow-x-auto">
          <h2 class="text-sm font-medium text-base-content/60 mb-3">Completions — last 52 weeks</h2>
          <svg
            width="676"
            height="91"
            viewBox="0 0 676 91"
            xmlns="http://www.w3.org/2000/svg"
          >
            <rect
              :for={cell <- @heatmap_cells}
              x={cell.x}
              y={cell.y}
              width="11"
              height="11"
              rx="2"
              style={heatmap_fill(cell.count)}
              class={if cell.count > 0, do: "cursor-pointer", else: "cursor-default"}
              phx-click={if cell.count > 0, do: "filter_date"}
              phx-value-date={Date.to_iso8601(cell.date)}
            >
              <title><%= heatmap_tooltip(cell) %></title>
            </rect>
          </svg>
        </div>

        <%!-- Filters --%>
        <div class="flex flex-wrap items-center gap-3">
          <div role="group" class="join">
            <button
              class={["join-item btn btn-sm", is_nil(@filter_type) && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="all"
            >All</button>
            <button
              class={["join-item btn btn-sm", @filter_type == :movie && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="movie"
            >Movies</button>
            <button
              class={["join-item btn btn-sm", @filter_type == :episode && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="episode"
            >Episodes</button>
            <button
              class={["join-item btn btn-sm", @filter_type == :video_object && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="video_object"
            >Video</button>
          </div>

          <input
            type="search"
            class="input input-bordered input-sm"
            placeholder="Search titles…"
            value={@filter_search}
            phx-change="filter_search"
            phx-debounce="300"
            name="value"
          />

          <button
            :if={@filter_date}
            class="btn btn-sm btn-ghost"
            phx-click="clear_date_filter"
          >
            <%= Date.to_string(@filter_date) %> ×
          </button>
        </div>

        <%!-- Event list --%>
        <div class="space-y-2">
          <div
            :if={@events == []}
            class="text-base-content/50 py-12 text-center"
          >
            No completions yet.
          </div>

          <div
            :for={event <- @events}
            class="flex items-center gap-4 p-3 rounded-box bg-base-200 group"
          >
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate"><%= event.title %></div>
              <div class="text-sm text-base-content/60">
                <span class="badge badge-ghost badge-sm mr-2"><%= type_label(event.entity_type) %></span>
                Completed <%= format_completed_at(event.completed_at) %>
                · <%= Format.format_seconds(round(event.duration_seconds)) %>
              </div>
            </div>
            <button
              class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100 transition-opacity"
              phx-click="delete_event"
              phx-value-id={event.id}
              data-confirm="Mark as unwatched? This will reset your progress."
            >
              Unwatch
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter_type", %{"type" => type_str}, socket) do
    type = if type_str == "all", do: nil, else: String.to_existing_atom(type_str)
    events = load_events(socket, entity_type: type)
    {:noreply, assign(socket, events: events, filter_type: type)}
  end

  @impl true
  def handle_event("filter_search", %{"value" => search}, socket) do
    events = load_events(socket, search: search)
    {:noreply, assign(socket, events: events, filter_search: search)}
  end

  @impl true
  def handle_event("filter_date", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    events = load_events(socket, date: date)
    {:noreply, assign(socket, events: events, filter_date: date)}
  end

  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    events = load_events(socket, date: nil)
    {:noreply, assign(socket, events: events, filter_date: nil)}
  end

  @impl true
  def handle_event("delete_event", %{"id" => id}, socket) do
    event = WatchHistory.get_event!(id)
    WatchHistory.delete_event!(event)
    stats = WatchHistory.stats()
    events = load_events(socket)

    {:noreply,
     assign(socket,
       events: events,
       stats: stats,
       heatmap_cells: Stats.heatmap_cells(stats.heatmap)
     )}
  end

  @impl true
  def handle_info({:watch_event_created, _event}, socket) do
    stats = WatchHistory.stats()
    events = load_events(socket)

    {:noreply,
     assign(socket,
       events: events,
       stats: stats,
       heatmap_cells: Stats.heatmap_cells(stats.heatmap)
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp load_events(socket, overrides \\ []) do
    opts =
      [
        entity_type: socket.assigns.filter_type,
        search: socket.assigns.filter_search,
        date: socket.assigns.filter_date
      ]
      |> Keyword.merge(overrides)

    WatchHistory.list_events(opts)
  end

  defp heatmap_fill(0), do: "fill: oklch(var(--b3))"
  defp heatmap_fill(1), do: "fill: oklch(var(--su) / 0.35)"
  defp heatmap_fill(n) when n <= 3, do: "fill: oklch(var(--su) / 0.65)"
  defp heatmap_fill(_), do: "fill: oklch(var(--su))"

  defp heatmap_tooltip(%{count: 0, date: date}), do: Date.to_string(date)
  defp heatmap_tooltip(%{count: 1, date: date}), do: "#{Date.to_string(date)} — 1 completion"
  defp heatmap_tooltip(%{count: n, date: date}), do: "#{Date.to_string(date)} — #{n} completions"

  defp type_label(:movie), do: "Movie"
  defp type_label(:episode), do: "Episode"
  defp type_label(:video_object), do: "Video"

  defp format_hours(seconds) do
    hours = round(seconds / 3600)
    "#{hours} hrs"
  end

  defp format_completed_at(completed_at) do
    # Format as "April 10, 2026 at 9:34 PM"
    Calendar.strftime(completed_at, "%B %-d, %Y at %-I:%M %p")
  end
end
```

- [ ] **Run tests to verify they pass**

```bash
mix test test/media_centaur_web/live/watch_history_live_test.exs
```

Expected: 7 tests, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add WatchHistoryLive page and /history route"
jj new
```

---

## Task 8: LibraryLive dashboard widget

**Files:**
- Modify: `lib/media_centaur_web/live/library_live.ex`

- [ ] **Add WatchHistory subscribe + assigns in mount**

In `lib/media_centaur_web/live/library_live.ex`:

1. Add `WatchHistory` to the alias block at the top:
```elixir
alias MediaCentaur.{
  Format,
  Library,
  Library.FileEventHandler,
  LibraryBrowser,
  Playback,
  Playback.ProgressBroadcaster,
  Playback.ResumeTarget,
  ReleaseTracking,
  Settings,
  WatchHistory
}
```

2. Add subscribe in `mount/3` (inside `if connected?(socket)`):
```elixir
if connected?(socket) do
  Library.subscribe()
  Playback.subscribe()
  Settings.subscribe()
  ReleaseTracking.subscribe()
  WatchHistory.subscribe()
end
```

3. Add assigns to `assign/2` call in `mount/3`:
```elixir
history_events: WatchHistory.recent_events(5),
history_stats: WatchHistory.stats()
```

- [ ] **Add handle_info clause for watch_event_created**

Add before the catch-all `handle_info`:
```elixir
@impl true
def handle_info({:watch_event_created, _event}, socket) do
  {:noreply,
   assign(socket,
     history_events: WatchHistory.recent_events(5),
     history_stats: WatchHistory.stats()
   )}
end
```

- [ ] **Add the history widget to the template**

In the `render/1` function template, inside the `:watching` zone section
(after the continue-watching grid, before the closing `</section>`):

```heex
<%!-- Watch History widget --%>
<div class="mt-10">
  <div class="flex items-center justify-between mb-3">
    <h2 class="text-base font-semibold">Recently Watched</h2>
    <.link navigate={~p"/history"} class="text-sm text-base-content/60 hover:text-base-content">
      View all history →
    </.link>
  </div>

  <div :if={@history_stats.total_count > 0} class="text-sm text-base-content/60 mb-3">
    <%= @history_stats.total_count %> titles completed
    · <%= round(@history_stats.total_seconds / 3600) %> hrs watched
  </div>

  <div :if={@history_events == []} class="text-sm text-base-content/40 italic">
    No completed titles yet.
  </div>

  <div :if={@history_events != []} class="space-y-2">
    <div
      :for={event <- @history_events}
      class="flex items-center gap-3 p-2 rounded-lg bg-base-200"
    >
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium truncate"><%= event.title %></div>
        <div class="text-xs text-base-content/50">
          <%= Calendar.strftime(event.completed_at, "%b %-d, %Y") %>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Run full test suite**

```bash
mix test
```

Expected: all tests pass, 0 failures.

- [ ] **Commit**

```bash
jj describe -m "feat: add watch history widget to LibraryLive dashboard"
jj new
```

---

## Task 9: Final precommit check

- [ ] **Run precommit**

```bash
mix precommit
```

Expected: compiles with zero warnings, all tests pass, formatting clean.

- [ ] **Fix any warnings or failures before moving on**

Common issues to watch for:
- Unused aliases (check each new file's alias block)
- Unused variables (pattern match with `_` prefix)
- Missing `@impl true` before LiveView callbacks
- Any log output during tests indicating real HTTP calls (should be zero)

- [ ] **Final commit**

```bash
jj describe -m "chore: precommit clean for watch history feature"
```
