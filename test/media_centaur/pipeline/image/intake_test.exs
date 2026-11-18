defmodule MediaCentaur.Pipeline.Image.IntakeTest do
  @moduledoc """
  An import's artwork hand-off (`{:enqueue_images, ...}` from
  `Library.Inbound`) becomes queue rows whether or not artwork downloads
  are on. Regression for 2026-11-17: with the artwork pipeline off, the
  only subscriber was its producer, so the message was dropped and the
  imported titles never got artwork.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.Image.Intake
  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Topics

  # The test instance runs no background services, so the tree starts no
  # Intake; the test starts the one a running install has.
  setup do
    start_supervised!(Intake)
    :ok
  end

  test "queues an import's artwork as pending rows while the artwork pipeline is off" do
    refute MediaCentaur.Pipeline.Image.Supervisor.pipeline_running?()

    entity_id = Ecto.UUID.generate()

    images = [
      %{
        owner_id: entity_id,
        owner_type: "movie",
        role: "poster",
        source_url: "https://image.tmdb.org/t/p/original/poster.jpg",
        extension: "jpg"
      },
      %{
        owner_id: entity_id,
        owner_type: "movie",
        role: "backdrop",
        source_url: "https://image.tmdb.org/t/p/original/backdrop.jpg",
        extension: "jpg"
      }
    ]

    Topics.publish(
      Topics.pipeline_images(),
      {:enqueue_images, %{entity_id: entity_id, media_dir: "/media/movies", images: images}}
    )

    queued =
      eventually(
        fn ->
          case ImageQueue.list_pending(entity_id) do
            [] -> nil
            entries -> entries
          end
        end,
        message: "the imported movie's artwork never reached the image queue"
      )

    assert queued |> Enum.map(& &1.role) |> Enum.sort() == ["backdrop", "poster"]
    assert Enum.all?(queued, &(&1.media_dir == "/media/movies"))
  end
end
