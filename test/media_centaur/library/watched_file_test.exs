defmodule MediaCentaur.Library.WatchedFileTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{FilePresence, WatchedFile}
  alias MediaCentaur.Repo

  describe "Library.Files.link/1 (WatchedFile via PlayableItem)" do
    test "creates record keyed by playable_item_id" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})
      playable_item = create_playable_item_for_movie(movie)

      assert {:ok, file} =
               Library.Files.link(%{
                 file_path: "/media/test/linked.mkv",
                 media_dir: "/media/test",
                 playable_item_id: playable_item.id
               })

      assert file.playable_item_id == playable_item.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.media_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      movie_one = create_entity(%{type: :movie, name: "First Movie"})
      movie_two = create_entity(%{type: :movie, name: "Second Movie"})
      item_one = create_playable_item_for_movie(movie_one)
      item_two = create_playable_item_for_movie(movie_two)

      {:ok, first} =
        Library.Files.link(%{
          file_path: "/media/test/same.mkv",
          media_dir: "/media/test",
          playable_item_id: item_one.id
        })

      {:ok, second} =
        Library.Files.link(%{
          file_path: "/media/test/same.mkv",
          media_dir: "/media/test",
          playable_item_id: item_two.id
        })

      assert first.id == second.id
      assert second.playable_item_id == item_two.id

      # Only one record exists for the upserted file_path.
      all = Library.Files.list_all()
      assert length(all) == 1
    end

    test "requires playable_item_id" do
      changeset =
        WatchedFile.create_changeset(%{
          file_path: "/media/test/missing-item.mkv",
          media_dir: "/media/test"
        })

      assert %{playable_item_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "auto-stamps a Library.FilePresence row and links its id" do
      movie = create_entity(%{type: :movie, name: "Presence Movie"})
      playable_item = create_playable_item_for_movie(movie)

      assert {:ok, file} =
               Library.Files.link(%{
                 file_path: "/media/test/presence-link.mkv",
                 media_dir: "/media/test",
                 playable_item_id: playable_item.id
               })

      assert file.file_presence_id
      presence = Repo.get_by!(FilePresence, file_path: "/media/test/presence-link.mkv")
      assert file.file_presence_id == presence.id
      assert presence.media_dir == "/media/test"
    end
  end

  describe "Library.Files.top_level_entity_id/1" do
    test "resolves a :movie PlayableItem to the Movie id" do
      movie = create_entity(%{type: :movie, name: "Resolver Movie"})
      item = create_playable_item_for_movie(movie)
      file = create_linked_file(%{playable_item_id: item.id})

      assert Library.Files.top_level_entity_id(file) == movie.id
    end

    test "resolves a :video_object PlayableItem to the VideoObject id" do
      video_object = create_entity(%{type: :video_object, name: "Resolver Video"})
      item = create_playable_item_for_video_object(video_object)
      file = create_linked_file(%{playable_item_id: item.id})

      assert Library.Files.top_level_entity_id(file) == video_object.id
    end

    test "resolves a :episode PlayableItem to the TVSeries id" do
      tv_series = create_entity(%{type: :tv_series, name: "Resolver Show"})

      {:ok, season} =
        Library.Seasons.find_or_create(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          name: "S1",
          number_of_episodes: 1
        })

      {:ok, episode} =
        Library.Episodes.find_or_create(%{
          season_id: season.id,
          episode_number: 1,
          name: "E1",
          content_url: "/media/test/resolver.mkv"
        })

      item = create_playable_item_for_episode(episode)
      file = create_linked_file(%{playable_item_id: item.id})

      assert Library.Files.top_level_entity_id(file) == tv_series.id
    end

    test "returns nil for a dangling PlayableItem id" do
      # The schema enforces playable_item_id NOT NULL, so dangling can
      # only happen after Repo-level deletion of the PlayableItem;
      # simulate by inserting a struct directly.
      file = %WatchedFile{playable_item_id: Ecto.UUID.generate()}
      assert Library.Files.top_level_entity_id(file) == nil
    end
  end
end
