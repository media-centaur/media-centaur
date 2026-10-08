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

  describe "progress_by_leaf/3" do
    test "one query maps each leaf container to its progress row; leaves without one are absent" do
      watched = create_standalone_movie(%{name: "Watched"})
      fresh = create_standalone_movie(%{name: "Fresh"})
      create_watch_progress(%{movie_id: watched.id, position_seconds: 30.0, duration_seconds: 100.0})

      by_id = ProgressRecords.progress_by_leaf(owner_profile_id(), :movie, [watched.id, fresh.id])

      assert %{position_seconds: 30.0} = by_id[watched.id]
      refute Map.has_key?(by_id, fresh.id)
    end
  end

  describe "two profiles" do
    setup do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      ana = create_profile(%{name: "Ana"})
      %{movie: movie, me: owner_profile_id(), ana: ana.id}
    end

    test "each profile has its own row for the same title", %{movie: movie, me: me, ana: ana} do
      movie_id = movie.id

      {:ok, mine} =
        ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})

      {:ok, hers} =
        ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{position_seconds: 90.0})

      assert mine.id != hers.id
      assert mine.playable_item_id == hers.playable_item_id
      assert {:ok, %{position_seconds: 10.0}} = ProgressRecords.fetch_for_container(me, :movie, movie.id)

      assert {:ok, %{position_seconds: 90.0}} =
               ProgressRecords.fetch_for_container(ana, :movie, movie.id)

      assert [%{position_seconds: 10.0}] = ProgressRecords.list_for_container(me, :movie, movie.id)

      assert %{^movie_id => %{episode_position_seconds: 90.0}} =
               ProgressRecords.summaries(ana, [movie.id])
    end

    test "a profile without a row reads nothing", %{movie: movie, me: me, ana: ana} do
      {:ok, _} =
        ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})

      assert {:error, :not_found} = ProgressRecords.fetch_for_container(ana, :movie, movie.id)
      assert ProgressRecords.list_for_container(ana, :movie, movie.id) == []
      assert ProgressRecords.summaries(ana, [movie.id]) == %{}
      assert ProgressRecords.profile_ids_with_progress() == [me]
    end

    test "removing a profile removes its rows and no one else's", %{movie: movie, me: me, ana: ana} do
      {:ok, _} = ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{})
      {:ok, _} = ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{})

      :ok = MediaCentaur.Profiles.remove(MediaCentaur.Profiles.get(ana))

      assert {:ok, _} = ProgressRecords.fetch_for_container(me, :movie, movie.id)
      assert {:error, :not_found} = ProgressRecords.fetch_for_container(ana, :movie, movie.id)
    end
  end
end
