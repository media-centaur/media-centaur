defmodule MediaCentaur.Pipeline.Stages.DownloadImagesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.DownloadImages

  defmodule FakeDownloader do
    @moduledoc false
    def download(_url, local_path) do
      File.mkdir_p!(Path.dirname(local_path))
      File.write!(local_path, "fake image bytes")
      :ok
    end
  end

  defmodule FailingDownloader do
    @moduledoc false
    def download(_url, _local_path), do: {:error, :connection_refused}
  end

  setup do
    prev = Application.get_env(:media_centaur, :staging_image_downloader)
    Application.put_env(:media_centaur, :staging_image_downloader, FakeDownloader)

    staging_parent = Path.join(System.tmp_dir!(), ".media-centaur")

    on_exit(fn ->
      if prev, do: Application.put_env(:media_centaur, :staging_image_downloader, prev)
      unless prev, do: Application.delete_env(:media_centaur, :staging_image_downloader)
      File.rm_rf(staging_parent)
    end)

    :ok
  end

  defp payload_with_images(images, child_movie_images \\ nil, episode_images \\ nil) do
    metadata = %{
      entity_type: :movie,
      entity_attrs: %{name: "Test"},
      images: images,
      identifier: %{property_id: "tmdb", value: "123"},
      child_movie:
        if(child_movie_images, do: %{attrs: %{}, images: child_movie_images, identifier: %{}}),
      season:
        if(episode_images,
          do: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 1,
            episode: %{attrs: %{}, images: episode_images}
          }
        )
    }

    %Payload{metadata: metadata, watch_directory: System.tmp_dir!()}
  end

  # ---------------------------------------------------------------------------
  # Success cases
  # ---------------------------------------------------------------------------

  describe "successful downloads" do
    test "downloads entity images to staging directory" do
      images = [
        %{role: "poster", url: "https://example.com/poster.jpg", extension: "jpg"},
        %{role: "backdrop", url: "https://example.com/backdrop.jpg", extension: "jpg"}
      ]

      payload = payload_with_images(images)

      assert {:ok, result} = DownloadImages.run(payload)
      assert length(result.staged_images) == 2

      poster = Enum.find(result.staged_images, &(&1.role == "poster"))
      assert poster.owner == "entity"
      assert File.exists?(poster.local_path)

      backdrop = Enum.find(result.staged_images, &(&1.role == "backdrop"))
      assert backdrop.owner == "entity"
      assert File.exists?(backdrop.local_path)

      # Staging dir is set on payload and is a sibling of the images dir
      assert result.staging_dir != nil
      assert String.contains?(result.staging_dir, "partial-downloads")
      assert String.contains?(result.staging_dir, ".media-centaur")

      File.rm_rf(result.staging_dir)
    end

    test "downloads child movie images" do
      entity_images = [%{role: "poster", url: "https://example.com/coll.jpg", extension: "jpg"}]
      child_images = [%{role: "poster", url: "https://example.com/movie.jpg", extension: "jpg"}]

      payload = payload_with_images(entity_images, child_images)

      assert {:ok, result} = DownloadImages.run(payload)
      child_staged = Enum.filter(result.staged_images, &(&1.owner == "child_movie"))
      assert length(child_staged) == 1
    end

    test "downloads episode images" do
      entity_images = [%{role: "poster", url: "https://example.com/show.jpg", extension: "jpg"}]
      episode_images = [%{role: "thumb", url: "https://example.com/ep.jpg", extension: "jpg"}]

      payload = payload_with_images(entity_images, nil, episode_images)

      assert {:ok, result} = DownloadImages.run(payload)
      ep_staged = Enum.filter(result.staged_images, &(&1.owner == "episode"))
      assert length(ep_staged) == 1
      assert hd(ep_staged).role == "thumb"
    end
  end

  # ---------------------------------------------------------------------------
  # Failure handling
  # ---------------------------------------------------------------------------

  describe "failure handling" do
    test "individual download failure does not fail the stage" do
      Application.put_env(:media_centaur, :staging_image_downloader, FailingDownloader)

      images = [
        %{role: "poster", url: "https://example.com/poster.jpg", extension: "jpg"}
      ]

      payload = payload_with_images(images)

      {result, log} =
        with_log(fn ->
          DownloadImages.run(payload)
        end)

      assert {:ok, downloaded} = result
      assert downloaded.staged_images == []
      assert log =~ "connection_refused"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "no images returns empty staged_images" do
      payload = payload_with_images([])

      assert {:ok, result} = DownloadImages.run(payload)
      assert result.staged_images == []
    end

    test "no child_movie or season skips those downloads" do
      images = [%{role: "poster", url: "https://example.com/poster.jpg", extension: "jpg"}]
      payload = payload_with_images(images)

      assert {:ok, result} = DownloadImages.run(payload)
      assert length(result.staged_images) == 1
      assert hd(result.staged_images).owner == "entity"
    end
  end
end
