defmodule MediaCentarr.Pipeline.ImageQueueTest do
  @moduledoc """
  Tests for the Pipeline.ImageQueue context — CRUD operations on image
  download queue entries.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Pipeline.ImageQueue
  alias MediaCentarr.Repo

  defp queue_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        owner_id: Ecto.UUID.generate(),
        owner_type: "entity",
        role: "poster",
        source_url: "https://image.tmdb.org/poster.jpg",
        entity_id: Ecto.UUID.generate(),
        watch_dir: "/media"
      },
      overrides
    )
  end

  describe "create" do
    test "inserts a new entry with pending status" do
      assert {:ok, entry} = ImageQueue.create(queue_attrs())
      assert entry.status == "pending"
      assert entry.retry_count == 0
      assert entry.role == "poster"
    end

    test "upserts on duplicate owner_id + role" do
      attrs = queue_attrs()
      {:ok, _first} = ImageQueue.create(attrs)

      # Same owner_id + role, different source_url — upserts, not duplicates
      {:ok, _second} = ImageQueue.create(%{attrs | source_url: "https://new.jpg"})

      pending = ImageQueue.list_pending(attrs.entity_id)
      assert length(pending) == 1
      assert hd(pending).source_url == "https://new.jpg"
    end
  end

  describe "list_pending" do
    test "returns only pending entries for the given entity" do
      entity_id = Ecto.UUID.generate()
      other_entity_id = Ecto.UUID.generate()

      {:ok, _} = ImageQueue.create(queue_attrs(%{entity_id: entity_id, role: "poster"}))
      {:ok, _} = ImageQueue.create(queue_attrs(%{entity_id: entity_id, role: "backdrop"}))
      {:ok, _} = ImageQueue.create(queue_attrs(%{entity_id: other_entity_id, role: "poster"}))

      pending = ImageQueue.list_pending(entity_id)
      assert length(pending) == 2
      assert Enum.all?(pending, &(&1.entity_id == entity_id))
    end

    test "excludes non-pending entries" do
      entity_id = Ecto.UUID.generate()
      {:ok, entry} = ImageQueue.create(queue_attrs(%{entity_id: entity_id}))
      ImageQueue.update_status(entry, :complete)

      assert ImageQueue.list_pending(entity_id) == []
    end
  end

  describe "status transitions" do
    test "mark_failed increments retry_count and sets status" do
      {:ok, entry} = ImageQueue.create(queue_attrs())
      assert entry.retry_count == 0

      {:ok, failed} = ImageQueue.mark_failed(entry)
      assert failed.status == "failed"
      assert failed.retry_count == 1

      {:ok, failed_again} = ImageQueue.mark_failed(failed)
      assert failed_again.retry_count == 2
    end

    test "reset_to_pending sets status back to pending" do
      {:ok, entry} = ImageQueue.create(queue_attrs())
      {:ok, failed} = ImageQueue.mark_failed(entry)

      {:ok, reset} = ImageQueue.reset_to_pending(failed)
      assert reset.status == "pending"
      assert reset.retry_count == 1
    end

    test "update_status sets arbitrary status" do
      {:ok, entry} = ImageQueue.create(queue_attrs())

      {:ok, updated} = ImageQueue.update_status(entry, :complete)
      assert updated.status == "complete"
    end
  end

  describe "list_retryable" do
    test "returns pending and failed entries" do
      {:ok, pending} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, failed_entry} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))
      {:ok, _failed} = ImageQueue.mark_failed(failed_entry)
      {:ok, complete_entry} = ImageQueue.create(queue_attrs(%{role: "logo"}))
      ImageQueue.update_status(complete_entry, :complete)

      retryable = ImageQueue.list_retryable()
      retryable_ids = MapSet.new(retryable, & &1.id)

      assert pending.id in retryable_ids
      # failed entry's ID stays the same after mark_failed
      assert failed_entry.id in retryable_ids
      refute complete_entry.id in retryable_ids
    end
  end

  describe "retrying_count" do
    test "counts only failed entries" do
      {:ok, entry} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, _} = ImageQueue.mark_failed(entry)

      {:ok, _} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))

      assert ImageQueue.retrying_count() == 1
    end
  end

  describe "update_statuses/2" do
    test "updates all given entries to the target status in one query" do
      {:ok, a} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, b} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))
      {:ok, c} = ImageQueue.create(queue_attrs(%{role: "thumb"}))

      {count, _} = ImageQueue.update_statuses([a, b, c], :complete)
      assert count == 3

      for entry <- [a, b, c] do
        refreshed = Repo.get!(MediaCentarr.Pipeline.ImageQueueEntry, entry.id)
        assert refreshed.status == "complete"
      end
    end

    test "no-ops on an empty list" do
      assert ImageQueue.update_statuses([], :complete) == {0, nil}
    end
  end

  describe "mark_failed_batch/1" do
    test "marks all given entries failed and increments retry_count" do
      {:ok, a} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, b} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))

      {count, _} = ImageQueue.mark_failed_batch([a, b])
      assert count == 2

      for entry <- [a, b] do
        refreshed = Repo.get!(MediaCentarr.Pipeline.ImageQueueEntry, entry.id)
        assert refreshed.status == "failed"
        assert refreshed.retry_count == entry.retry_count + 1
      end
    end

    test "no-ops on an empty list" do
      assert ImageQueue.mark_failed_batch([]) == {0, nil}
    end
  end
end
