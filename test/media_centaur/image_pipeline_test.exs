defmodule MediaCentaur.ImagePipelineTest do
  @moduledoc """
  Integration tests for the ImagePipeline Broadway.

  Verifies that the producer queries pending images, the processor downloads
  and resizes them, and the batcher updates Image records and broadcasts changes.
  """
  use MediaCentaur.DataCase

  alias MediaCentaur.ImagePipeline

  @watch_directory "/tmp/image_pipeline_test"

  setup do
    images_dir = Path.join(System.tmp_dir!(), "image_pipeline_test_#{Ecto.UUID.generate()}")
    File.mkdir_p!(images_dir)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    updated_config =
      config
      |> Map.put(:watch_dir_images, %{@watch_directory => images_dir})
      |> Map.update(:watch_dirs, [@watch_directory], fn dirs ->
        if @watch_directory in dirs, do: dirs, else: [@watch_directory | dirs]
      end)

    :persistent_term.put({MediaCentaur.Config, :config}, updated_config)

    on_exit(fn ->
      File.rm_rf!(images_dir)
      :persistent_term.put({MediaCentaur.Config, :config}, config)
    end)

    %{images_dir: images_dir}
  end

  describe "producer work item building" do
    test "builds work items for entity with pending images" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/poster.jpg",
        extension: "jpg"
      })

      work_items = ImagePipeline.Producer.build_work_items(entity.id, @watch_directory)

      assert length(work_items) == 1
      item = hd(work_items)
      assert item.image.role == "poster"
      assert item.owner_id == entity.id
      assert item.entity_id == entity.id
      assert item.watch_dir == @watch_directory
    end

    test "skips images that already have content_url" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/poster.jpg",
        extension: "jpg",
        content_url: "#{entity.id}/poster.jpg"
      })

      work_items = ImagePipeline.Producer.build_work_items(entity.id, @watch_directory)

      assert work_items == []
    end

    test "includes child movie and episode images" do
      entity = create_entity(%{type: :tv_series, name: "Test Show"})
      season = create_season(%{entity_id: entity.id, season_number: 1, name: "Season 1"})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/media/test.mkv"
        })

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/poster.jpg",
        extension: "jpg"
      })

      create_image(%{
        episode_id: episode.id,
        role: "thumb",
        url: "https://image.tmdb.org/thumb.jpg",
        extension: "jpg"
      })

      work_items = ImagePipeline.Producer.build_work_items(entity.id, @watch_directory)

      assert length(work_items) == 2
      roles = Enum.map(work_items, & &1.image.role) |> Enum.sort()
      assert roles == ["poster", "thumb"]
    end
  end
end
