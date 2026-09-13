defmodule MediaCentaur.Library.ProgressRecordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Library.ProgressRecords

  import MediaCentaur.TestFactory

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
end
