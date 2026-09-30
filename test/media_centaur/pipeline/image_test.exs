defmodule MediaCentaur.Pipeline.ImageTest do
  @moduledoc """
  Integration tests for the Pipeline.Image Broadway.

  Verifies that the producer queries pending queue entries, the processor
  downloads and resizes them, and the batcher marks each entry complete
  and records its `Library.Image`, together.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.{Image, ImageQueue}

  @media_directory "/tmp/image_pipeline_test"

  setup do
    images_dir = Path.join(System.tmp_dir!(), "image_pipeline_test_#{Ecto.UUID.generate()}")
    File.mkdir_p!(images_dir)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    updated_config =
      config
      |> Map.put(:media_dir_images, %{@media_directory => images_dir})
      |> Map.update(:media_dirs, [@media_directory], fn dirs ->
        if @media_directory in dirs, do: dirs, else: [@media_directory | dirs]
      end)

    :persistent_term.put({MediaCentaur.Settings.Config, :config}, updated_config)

    on_exit(fn -> File.rm_rf!(images_dir) end)

    %{images_dir: images_dir}
  end

  # Regression (campaign durable-work, F11): the batcher marked an entry
  # complete and published `{:image_ready, ...}` for `Library.Inbound` to
  # write the image row; a lost message left the file downloaded, the entry
  # complete, and no row — nothing ever wrote it.
  describe "handle_batch/4 — the downloaded image is recorded with its entry" do
    test "marks the entry complete and writes the Library.Image row, with no message between" do
      movie = MediaCentaur.TestFactory.create_entity(%{type: :movie, name: "Sample Movie"})

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: movie.id,
          owner_type: "movie",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: movie.id,
          media_dir: @media_directory
        })

      message = %Broadway.Message{
        data: %{
          queue_entry: entry,
          relative_path: "images/#{movie.id}/poster.jpg",
          extension: "jpg",
          owner_id: movie.id,
          entity_id: movie.id
        },
        acknowledger: Broadway.NoopAcknowledger.init()
      }

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
      Image.handle_batch(:default, [message], %{}, %{})

      assert MediaCentaur.Repo.reload!(entry).status == "complete"
      assert [poster] = MediaCentaur.Library.Images.list_for_owner(:movie, movie.id)
      assert poster.content_url == "images/#{movie.id}/poster.jpg"
      assert_receive {:entities_changed, %{entity_ids: entity_ids}}, 500
      assert movie.id in entity_ids
    end
  end

  describe "producer work item building" do
    test "builds work items from pending queue entries" do
      entity_id = Ecto.UUID.generate()

      {:ok, _entry} =
        ImageQueue.create(%{
          owner_id: entity_id,
          owner_type: "entity",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: entity_id,
          media_dir: @media_directory
        })

      work_items = Image.Producer.build_work_items(entity_id)

      assert length(work_items) == 1
      item = hd(work_items)
      assert item.queue_entry.role == "poster"
      assert item.owner_id == entity_id
      assert item.entity_id == entity_id
      assert item.media_dir == @media_directory
    end

    test "skips completed queue entries" do
      entity_id = Ecto.UUID.generate()

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: entity_id,
          owner_type: "entity",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: entity_id,
          media_dir: @media_directory
        })

      ImageQueue.update_statuses([entry], :complete)

      work_items = Image.Producer.build_work_items(entity_id)

      assert work_items == []
    end

    test "includes entries for different owner types" do
      entity_id = Ecto.UUID.generate()
      episode_id = Ecto.UUID.generate()

      {:ok, _} =
        ImageQueue.create(%{
          owner_id: entity_id,
          owner_type: "entity",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: entity_id,
          media_dir: @media_directory
        })

      {:ok, _} =
        ImageQueue.create(%{
          owner_id: episode_id,
          owner_type: "episode",
          role: "thumb",
          source_url: "https://image.tmdb.org/thumb.jpg",
          entity_id: entity_id,
          media_dir: @media_directory
        })

      work_items = Image.Producer.build_work_items(entity_id)

      assert length(work_items) == 2
      roles = Enum.sort(Enum.map(work_items, & &1.queue_entry.role))
      assert roles == ["poster", "thumb"]
    end
  end
end
