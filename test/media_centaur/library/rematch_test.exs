defmodule MediaCentaur.Library.RematchTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Rematch

  defp two_episode_list do
    for n <- 1..2, do: %{episode_number: n, name: "Episode #{n}", air_date: "2020-01-0#{n}"}
  end

  # ---------------------------------------------------------------------------
  # Rematch
  # ---------------------------------------------------------------------------

  describe "release/1" do
    test "destroys the entity and its watched files, and returns the files" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      movie =
        create_entity(%{
          type: :movie,
          name: "Wrong Movie",
          content_url: "/media/movies/Sample Movie (2017).mkv"
        })

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/movies/Sample Movie (2017).mkv",
        media_dir: "/media/movies"
      })

      assert {:ok, files} = Rematch.release(movie.id)

      # Entity destroyed
      assert {:error, _} = Library.Containers.fetch(:movie, movie.id)

      # WatchedFiles destroyed
      assert Library.Files.list_by_entity_id(movie.id) == []

      # Broadcasts entities_changed (via coalescer — allow flush window).
      # Coalescer may bundle this entity's ID with IDs from concurrent tests'
      # broadcasts in the same 200ms window — assert membership, not exact list.
      assert_receive {:entities_changed, %{entity_ids: ids}}, 500
      assert movie.id in ids

      # Returns the file list for review
      assert files == [
               %{
                 file_path: "/media/movies/Sample Movie (2017).mkv",
                 media_dir: "/media/movies"
               }
             ]
    end

    test "returns every file of a TV series with several watched files" do
      tv_series = create_entity(%{type: :tv_series, name: "Wrong Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          episode_list: two_episode_list()
        })

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Second",
        content_url: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv"
      })

      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "wrong"})

      create_linked_file(%{
        tv_series_id: tv_series.id,
        file_path: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv",
        media_dir: "/media/tv"
      })

      create_linked_file(%{
        tv_series_id: tv_series.id,
        file_path: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv",
        media_dir: "/media/tv"
      })

      assert {:ok, files} = Rematch.release(tv_series.id)

      # Entity fully destroyed
      assert {:error, _} = Library.Containers.fetch(:tv_series, tv_series.id)

      # Both files returned for review
      assert length(files) == 2
      paths = Enum.sort(Enum.map(files, & &1.file_path))

      assert paths == [
               "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv",
               "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv"
             ]
    end
  end

  test "an entity with no watched files releases nothing" do
    assert {:ok, []} = Rematch.release(Ecto.UUID.generate())
  end
end
