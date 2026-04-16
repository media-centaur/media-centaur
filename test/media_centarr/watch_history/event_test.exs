defmodule MediaCentarr.WatchHistory.EventTest do
  use MediaCentarr.DataCase

  alias MediaCentarr.WatchHistory.Event

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        entity_type: :movie,
        title: "Sample Movie Thirteen",
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

      {:ok, event} =
        Event.create_changeset(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: "Sample Movie",
          duration_seconds: 7080.0,
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> MediaCentarr.Repo.insert()

      MediaCentarr.Repo.delete!(movie)
      reloaded = MediaCentarr.Repo.get!(Event, event.id)

      assert reloaded.movie_id == nil
      assert reloaded.title == "Sample Movie"
    end
  end

  describe "WatchHistory.remove_event!/1" do
    test "removes the event record" do
      event = create_watch_event(%{title: "Sample Movie Ten"})

      MediaCentarr.WatchHistory.remove_event!(event)

      assert_raise Ecto.NoResultsError, fn ->
        MediaCentarr.Repo.get!(MediaCentarr.WatchHistory.Event, event.id)
      end
    end

    test "does not affect watch progress" do
      movie = create_movie(%{name: "Sample Movie Ten"})
      _progress = create_watch_progress(%{movie_id: movie.id, completed: true})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Ten"})

      MediaCentarr.WatchHistory.remove_event!(event)

      {:ok, progress} = MediaCentarr.Library.get_watch_progress_by_fk(:movie_id, movie.id)
      assert progress.completed == true
    end

    test "returns the deleted event" do
      event = create_watch_event(%{title: "Sample Movie Nine"})
      result = MediaCentarr.WatchHistory.remove_event!(event)
      assert result.id == event.id
    end
  end

  describe "WatchHistory.heatmap_cells_by_type/0" do
    test "returns a map with keys for all types and nil" do
      result = MediaCentarr.WatchHistory.heatmap_cells_by_type()
      assert Map.has_key?(result, nil)
      assert Map.has_key?(result, :movie)
      assert Map.has_key?(result, :episode)
      assert Map.has_key?(result, :video_object)
    end

    test "each value is a list of 364 cell maps" do
      result = MediaCentarr.WatchHistory.heatmap_cells_by_type()

      for {_type, cells} <- result do
        assert length(cells) == 364
        assert %{date: _, count: _, x: _, y: _} = hd(cells)
      end
    end

    test "type-filtered cells only count events of that type" do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :episode, title: "An Episode"})

      result = MediaCentarr.WatchHistory.heatmap_cells_by_type()
      today = Date.utc_today()

      movie_count = Enum.find(result[:movie], &(&1.date == today)).count
      episode_count = Enum.find(result[:episode], &(&1.date == today)).count
      all_count = Enum.find(result[nil], &(&1.date == today)).count

      assert movie_count == 1
      assert episode_count == 1
      assert all_count == 2
    end
  end

  describe "WatchHistory.delete_event!/1" do
    test "deletes the event record" do
      movie = create_movie(%{name: "Sample Movie Eight"})

      event =
        create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Eight"})

      MediaCentarr.WatchHistory.delete_event!(event)

      assert_raise Ecto.NoResultsError, fn ->
        MediaCentarr.Repo.get!(MediaCentarr.WatchHistory.Event, event.id)
      end
    end

    test "resets watch progress to incomplete" do
      movie = create_movie(%{name: "Sample Movie Fourteen"})
      _progress = create_watch_progress(%{movie_id: movie.id, completed: true})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Fourteen"})

      MediaCentarr.WatchHistory.delete_event!(event)

      {:ok, reloaded} = MediaCentarr.Library.get_watch_progress_by_fk(:movie_id, movie.id)
      assert reloaded.completed == false
    end

    test "succeeds when FK is nil (entity already deleted)" do
      event = create_watch_event(%{entity_type: :movie, movie_id: nil, title: "Ghost Movie"})
      result = MediaCentarr.WatchHistory.delete_event!(event)
      assert result.id == event.id
    end
  end
end
