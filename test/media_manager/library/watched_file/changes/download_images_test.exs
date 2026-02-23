defmodule MediaManager.Library.WatchedFile.Changes.DownloadImagesTest do
  use MediaManager.DataCase

  # The no-op image downloader is configured in config/test.exs.
  # These tests verify the change module's state transitions, not actual downloads.

  describe "download_images action" do
    test "entity with images — state transitions to :complete" do
      entity = create_entity(%{type: :movie, name: "Fight Club"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        extension: "jpg"
      })

      file =
        create_fetching_images_file(%{
          file_path: "/media/dl/fight_club.mkv",
          entity_id: entity.id
        })

      assert {:ok, downloaded} =
               file
               |> Ash.Changeset.for_update(:download_images, %{})
               |> Ash.update()

      assert downloaded.state == :complete
    end

    test "entity with no images — state = :complete (no-op download)" do
      entity = create_entity(%{type: :movie, name: "No Images Movie"})

      file =
        create_fetching_images_file(%{
          file_path: "/media/dl/no_images.mkv",
          entity_id: entity.id
        })

      assert {:ok, downloaded} =
               file
               |> Ash.Changeset.for_update(:download_images, %{})
               |> Ash.update()

      assert downloaded.state == :complete
    end

    test "entity with movie children — state = :complete" do
      entity = create_entity(%{type: :movie_series, name: "Series"})

      movie =
        create_movie(%{
          entity_id: entity.id,
          name: "Child Movie",
          tmdb_id: "123",
          position: 0
        })

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/child_poster.jpg",
        extension: "jpg"
      })

      file =
        create_fetching_images_file(%{
          file_path: "/media/dl/child.mkv",
          entity_id: entity.id
        })

      assert {:ok, downloaded} =
               file
               |> Ash.Changeset.for_update(:download_images, %{})
               |> Ash.update()

      assert downloaded.state == :complete
    end
  end
end
