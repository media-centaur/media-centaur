defmodule MediaCentaur.WatchHistory.EventTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.WatchHistory.Event

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        entity_type: :movie,
        title: "Sample Movie",
        duration_seconds: 9360.0,
        completed_at: DateTime.utc_now()
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
      attrs = %{
        entity_type: :book,
        title: "X",
        duration_seconds: 0.0,
        completed_at: DateTime.utc_now()
      }

      changeset = Event.create_changeset(attrs)
      refute changeset.valid?
    end
  end

  describe "nilify_all on entity deletion" do
    test "movie_id is nilified when movie is deleted" do
      movie = create_movie(%{name: "Sample Movie"})

      event =
        create_watch_event(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: "Sample Movie",
          duration_seconds: 7080.0,
          completed_at: DateTime.utc_now(:second)
        })

      MediaCentaur.Repo.delete!(movie)
      reloaded = MediaCentaur.Repo.get!(Event, event.id)

      assert reloaded.movie_id == nil
      assert reloaded.title == "Sample Movie"
    end
  end

  describe "WatchHistory.delete_event!/2 (default — no progress reset)" do
    test "removes the event record" do
      event = create_watch_event(%{title: "Sample Movie Ten"})

      MediaCentaur.WatchHistory.delete_event!(event)

      assert_raise Ecto.NoResultsError, fn ->
        MediaCentaur.Repo.get!(MediaCentaur.WatchHistory.Event, event.id)
      end
    end

    test "does not affect watch progress" do
      movie = create_movie(%{name: "Sample Movie Ten"})
      _progress = create_watch_progress(%{movie_id: movie.id, completed: true})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Ten"})

      MediaCentaur.WatchHistory.delete_event!(event)

      {:ok, progress} = MediaCentaur.Library.fetch_watch_progress_by_fk(:movie_id, movie.id)
      assert progress.completed == true
    end

    test "returns :ok" do
      event = create_watch_event(%{title: "Sample Movie Nine"})
      assert :ok = MediaCentaur.WatchHistory.delete_event!(event)
    end
  end

  describe "WatchHistory.heatmap_cells_by_type/0" do
    test "returns a map with keys for all types and nil" do
      result = MediaCentaur.WatchHistory.heatmap_cells_by_type()
      assert Map.has_key?(result, nil)
      assert Map.has_key?(result, :movie)
      assert Map.has_key?(result, :episode)
      assert Map.has_key?(result, :video_object)
    end

    test "each value is a list of 364 cell maps" do
      result = MediaCentaur.WatchHistory.heatmap_cells_by_type()

      for {_type, cells} <- result do
        assert length(cells) == 364
        assert %{date: _, count: _, x: _, y: _} = hd(cells)
      end
    end

    test "type-filtered cells only count events of that type" do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :episode, title: "An Episode"})

      result = MediaCentaur.WatchHistory.heatmap_cells_by_type()
      today = Date.utc_today()

      movie_count = Enum.find(result[:movie], &(&1.date == today)).count
      episode_count = Enum.find(result[:episode], &(&1.date == today)).count
      all_count = Enum.find(result[nil], &(&1.date == today)).count

      assert movie_count == 1
      assert episode_count == 1
      assert all_count == 2
    end
  end

  describe "WatchHistory.delete_event!/2 (reset_progress: true)" do
    test "deletes the event record" do
      movie = create_movie(%{name: "Sample Movie Eight"})

      event =
        create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Eight"})

      MediaCentaur.WatchHistory.delete_event!(event, reset_progress: true)

      assert_raise Ecto.NoResultsError, fn ->
        MediaCentaur.Repo.get!(MediaCentaur.WatchHistory.Event, event.id)
      end
    end

    test "resets watch progress to incomplete" do
      movie = create_movie(%{name: "Sample Movie Fourteen"})
      _progress = create_watch_progress(%{movie_id: movie.id, completed: true})

      event =
        create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Fourteen"})

      MediaCentaur.WatchHistory.delete_event!(event, reset_progress: true)

      {:ok, reloaded} = MediaCentaur.Library.fetch_watch_progress_by_fk(:movie_id, movie.id)
      assert reloaded.completed == false
    end

    test "succeeds when FK is nil (entity already deleted)" do
      event = create_watch_event(%{entity_type: :movie, movie_id: nil, title: "Ghost Movie"})
      assert :ok = MediaCentaur.WatchHistory.delete_event!(event, reset_progress: true)
    end
  end
end
