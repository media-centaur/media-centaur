defmodule MediaCentarr.LibraryTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  alias MediaCentarr.Library
  alias MediaCentarr.Watcher.FilePresence

  # Records the file as present in watcher_files so Browser queries include it.
  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  describe "list_in_progress/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_in_progress() == []
    end

    test "returns empty list when no in-progress watch progress exists" do
      movie = create_standalone_movie(%{name: "Completed Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      assert Library.list_in_progress() == []
    end

    test "returns in-progress movie with required shape" do
      movie = create_standalone_movie(%{name: "Prior Lives"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

      results = Library.list_in_progress()

      assert length(results) == 1
      row = hd(results)
      assert row.entity_id == movie.id
      assert row.entity_name == "Prior Lives"
      assert is_binary(row.last_episode_label) or is_nil(row.last_episode_label)
      assert is_integer(row.progress_pct)
      assert row.progress_pct >= 0 and row.progress_pct <= 100
      assert Map.has_key?(row, :backdrop_url)
    end

    test "does not return completed progress" do
      movie = create_standalone_movie(%{name: "Watched Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      assert Library.list_in_progress() == []
    end

    test "respects the limit option" do
      Enum.each(1..5, fn index ->
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
        create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})
      end)

      results = Library.list_in_progress(limit: 3)
      assert length(results) == 3
    end
  end

  describe "list_recently_added/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_recently_added() == []
    end

    test "returns recently added movies with required shape" do
      movie = create_standalone_movie(%{name: "Sample Movie Fourteen"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      results = Library.list_recently_added()

      assert length(results) == 1
      row = hd(results)
      assert row.id == movie.id
      assert row.name == "Sample Movie Fourteen"
      assert Map.has_key?(row, :year)
      assert Map.has_key?(row, :poster_url)
    end

    test "returns multiple entity types" do
      movie = create_standalone_movie(%{name: "Movie A"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      series = create_tv_series(%{name: "Series B"})
      record_present(create_linked_file(%{tv_series_id: series.id}))
      results = Library.list_recently_added()
      names = Enum.map(results, & &1.name)

      assert "Movie A" in names
      assert "Series B" in names
    end

    test "respects the limit option" do
      Enum.each(1..10, fn index ->
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
      end)

      results = Library.list_recently_added(limit: 5)
      assert length(results) == 5
    end
  end

  describe "list_hero_candidates/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_hero_candidates() == []
    end

    test "returns empty list when no entities have both backdrop and description" do
      movie = create_standalone_movie(%{name: "Plain Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      assert Library.list_hero_candidates() == []
    end

    test "returns entities with backdrop image and description with required shape" do
      movie = create_standalone_movie(%{name: "Inception", description: "A thief who steals secrets"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      results = Library.list_hero_candidates()

      assert length(results) == 1
      row = hd(results)
      assert row.id == movie.id
      assert row.name == "Inception"
      assert Map.has_key?(row, :year)
      assert Map.has_key?(row, :runtime_minutes)
      assert Map.has_key?(row, :genres)
      assert Map.has_key?(row, :overview)
      assert Map.has_key?(row, :backdrop_url)
      assert row.overview == "A thief who steals secrets"
    end

    test "does not return entities without a backdrop image" do
      movie =
        create_standalone_movie(%{name: "No Backdrop", description: "Has overview but no backdrop"})

      record_present(create_linked_file(%{movie_id: movie.id}))
      assert Library.list_hero_candidates() == []
    end
  end
end
