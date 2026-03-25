defmodule MediaCentaur.ImagePipeline.RetrySchedulerTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ImagePipeline.RetryScheduler
  alias MediaCentaur.Library

  describe "transient_failure tracking" do
    test "records a failure and tracks the image" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler)

      image_id = Ecto.UUID.generate()
      RetryScheduler.record_failure(image_id, pid)

      # Sync with the GenServer to ensure the cast has been processed
      assert RetryScheduler.retry_count(image_id, pid) == 1

      GenServer.stop(pid)
    end

    test "increments retry count on repeated failures" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_inc)

      image_id = Ecto.UUID.generate()
      RetryScheduler.record_failure(image_id, pid)
      RetryScheduler.record_failure(image_id, pid)

      assert RetryScheduler.retry_count(image_id, pid) == 2

      GenServer.stop(pid)
    end
  end

  describe "tick processing" do
    test "destroys images that exceed max retries" do
      entity = create_entity(%{type: :movie, name: "Retry Test"})

      create_linked_file(%{
        entity: entity,
        file_path: "/tmp/test/movie.mkv",
        watch_dir: "/tmp/test"
      })

      image =
        create_image(%{
          entity_id: entity.id,
          role: "poster",
          url: "https://image.tmdb.org/poster.jpg",
          extension: "jpg"
        })

      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_destroy)

      # Record 5 failures via public API to hit max retries
      for _ <- 1..5, do: RetryScheduler.record_failure(image.id, pid)
      assert RetryScheduler.retry_count(image.id, pid) == 5

      # Trigger tick manually — backoff will have elapsed since monotonic
      # time advances between the record_failure calls and the tick
      send(pid, :tick)
      _ = RetryScheduler.status(pid)

      # Image should be destroyed
      assert [] = Library.list_pending_downloads!()

      GenServer.stop(pid)
    end

    test "prunes state for images that were downloaded" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_prune)

      # Record a failure for an image ID that doesn't exist in the DB
      old_id = Ecto.UUID.generate()
      RetryScheduler.record_failure(old_id, pid)
      assert RetryScheduler.retry_count(old_id, pid) == 1

      # No pending images in DB — tick should prune the stale entry
      send(pid, :tick)
      _ = RetryScheduler.status(pid)

      assert RetryScheduler.tracked_ids(pid) == []

      GenServer.stop(pid)
    end
  end
end
