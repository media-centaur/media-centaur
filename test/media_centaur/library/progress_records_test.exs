defmodule MediaCentaur.Library.ProgressRecordsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.ProgressRecords

  describe "index_progress_by_key/1" do
    test "indexes by episode_id FK" do
      ep_id_a = Ecto.UUID.generate()
      ep_id_b = Ecto.UUID.generate()

      progress_a =
        build_progress(%{episode_id: ep_id_a, position_seconds: 30.0})

      progress_b =
        build_progress(%{episode_id: ep_id_b, position_seconds: 60.0})

      index = ProgressRecords.index_progress_by_key([progress_a, progress_b])

      assert index[ep_id_a] == progress_a
      assert index[ep_id_b] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "index_progress_by_key/1 keys movie-series progress by movie_id" do
    test "indexes progress records by movie_id FK" do
      movie_id_a = Ecto.UUID.generate()
      movie_id_b = Ecto.UUID.generate()

      progress_a = build_progress(%{movie_id: movie_id_a, position_seconds: 30.0})
      progress_b = build_progress(%{movie_id: movie_id_b, position_seconds: 60.0})

      index = ProgressRecords.index_progress_by_key([progress_a, progress_b])

      assert index[movie_id_a] == progress_a
      assert index[movie_id_b] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "progress_by_leaf/2" do
    test "one query maps each leaf container to its progress row; leaves without one are absent" do
      watched = create_standalone_movie(%{name: "Watched"})
      fresh = create_standalone_movie(%{name: "Fresh"})
      create_watch_progress(%{movie_id: watched.id, position_seconds: 30.0, duration_seconds: 100.0})

      by_id = ProgressRecords.progress_by_leaf(:movie, [watched.id, fresh.id])

      assert %{position_seconds: 30.0} = by_id[watched.id]
      refute Map.has_key?(by_id, fresh.id)
    end
  end
end
