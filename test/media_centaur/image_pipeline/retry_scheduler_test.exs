defmodule MediaCentaur.ImagePipeline.RetrySchedulerTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ImagePipeline.RetryScheduler
  alias MediaCentaur.Library

  describe "transient_failure tracking" do
    test "records a failure in state" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler)

      image_id = Ash.UUID.generate()
      RetryScheduler.record_failure(image_id, pid)

      # Give the cast time to process
      :sys.get_state(pid)

      state = :sys.get_state(pid)
      assert Map.has_key?(state.retries, image_id)
      {count, _last} = state.retries[image_id]
      assert count == 1

      GenServer.stop(pid)
    end

    test "increments retry count on repeated failures" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_inc)

      image_id = Ash.UUID.generate()
      RetryScheduler.record_failure(image_id, pid)
      :sys.get_state(pid)
      RetryScheduler.record_failure(image_id, pid)
      :sys.get_state(pid)

      state = :sys.get_state(pid)
      {count, _last} = state.retries[image_id]
      assert count == 2

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

      # Simulate 5 failures — set retry count to max
      long_ago = System.monotonic_time(:millisecond) - 600_000

      :sys.replace_state(pid, fn state ->
        %{state | retries: %{image.id => {5, long_ago}}}
      end)

      # Trigger tick manually
      send(pid, :tick)
      :sys.get_state(pid)

      # Image should be destroyed
      assert [] = Library.list_pending_downloads!()

      GenServer.stop(pid)
    end

    test "prunes state for images that were downloaded" do
      {:ok, pid} = RetryScheduler.start_link(name: :test_scheduler_prune)

      old_id = Ash.UUID.generate()

      :sys.replace_state(pid, fn state ->
        %{state | retries: %{old_id => {2, System.monotonic_time(:millisecond)}}}
      end)

      # No pending images in DB — tick should prune the stale entry
      send(pid, :tick)
      :sys.get_state(pid)

      state = :sys.get_state(pid)
      assert state.retries == %{}

      GenServer.stop(pid)
    end
  end
end
