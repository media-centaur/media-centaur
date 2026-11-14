defmodule MediaCentaurWeb.ViewModel.LeafDetailTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaurWeb.ViewModel.LeafDetail

  describe "compose/3 — the entry for a movie or video object the library owns" do
    test "carries the entity, its records and the title progress" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      assert {:ok, %LeafDetail{} = entry} = LeafDetail.compose(owner_profile_id(), :movie, movie.id)
      assert entry.entity.id == movie.id
      assert entry.entity.type == :movie
      assert entry.entity.name == "Sample Movie"
      assert entry.progress_records == []

      assert %TitleProgress{state: :unstarted, next: %{item_id: next_id}, total: 1} =
               entry.title_progress

      assert next_id == movie.id
    end

    test "a movie with a viewing in flight is in progress at its offset" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      create_watch_progress(%{movie_id: movie.id, position_seconds: 600.0, duration_seconds: 5400.0})

      assert {:ok, entry} = LeafDetail.compose(owner_profile_id(), :movie, movie.id)
      assert [%{position_seconds: 600.0}] = entry.progress_records
      assert %TitleProgress{state: :in_progress, next: %{offset_seconds: 600.0}} = entry.title_progress
    end

    test "a movie marked watched by hand, with no timestamp, is complete" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      {:ok, %{last_watched_at: nil}} =
        MediaCentaur.Library.ProgressRecords.toggle_watched(
          MediaCentaur.Profiles.Actor.new(owner_profile_id()),
          :movie,
          movie.id
        )

      assert {:ok, entry} = LeafDetail.compose(owner_profile_id(), :movie, movie.id)
      assert %TitleProgress{state: :complete, next: nil} = entry.title_progress
    end

    test "a movie the library has no file for is not found" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      assert LeafDetail.compose(owner_profile_id(), :movie, movie.id) == :not_found
    end

    test "an unknown id is not found" do
      assert LeafDetail.compose(owner_profile_id(), :movie, Ecto.UUID.generate()) == :not_found
    end
  end
end
