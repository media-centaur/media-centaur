defmodule MediaCentarr.Pipeline.Image.RetrySchedulerTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Pipeline.Image.RetryScheduler
  alias MediaCentarr.Pipeline.ImageQueue

  @watch_directory "/tmp/retry_test"

  describe "tick processing" do
    test "marks entries as permanent when retry_count exceeds max" do
      entity_id = Ecto.UUID.generate()

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: entity_id,
          owner_type: "entity",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: entity_id,
          watch_dir: @watch_directory
        })

      # Simulate 5 failures by marking as failed with incremented retry_count
      Enum.reduce(1..5, entry, fn _i, current ->
        {:ok, updated} = ImageQueue.mark_failed(current)
        updated
      end)

      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_destroy)

      # Trigger a synchronous tick via the public API (ADR-026).
      :ok = RetryScheduler.tick(pid)

      # Entry should be marked permanent
      [entry] = MediaCentarr.Repo.all(MediaCentarr.Pipeline.ImageQueueEntry)
      assert entry.status == "permanent"

      GenServer.stop(pid)
    end

    test "resets failed entries to pending after backoff elapsed" do
      entity_id = Ecto.UUID.generate()

      {:ok, entry} =
        ImageQueue.create(%{
          owner_id: entity_id,
          owner_type: "entity",
          role: "poster",
          source_url: "https://image.tmdb.org/poster.jpg",
          entity_id: entity_id,
          watch_dir: @watch_directory
        })

      # Mark as failed once (retry_count = 1)
      {:ok, failed_entry} = ImageQueue.mark_failed(entry)
      assert failed_entry.status == "failed"
      assert failed_entry.retry_count == 1

      # Backdate updated_at to ensure backoff has elapsed
      MediaCentarr.Repo.update_all(
        MediaCentarr.Pipeline.ImageQueueEntry,
        set: [updated_at: ~U[2020-01-01 00:00:00Z]]
      )

      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_retry)

      :ok = RetryScheduler.tick(pid)

      # Entry should be reset to pending
      [entry] = MediaCentarr.Repo.all(MediaCentarr.Pipeline.ImageQueueEntry)
      assert entry.status == "pending"

      GenServer.stop(pid)
    end
  end
end
