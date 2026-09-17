defmodule MediaCentaur.Pipeline.ImageQueueTest do
  @moduledoc """
  Tests for the Pipeline.ImageQueue context — CRUD operations on image
  download queue entries.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Pipeline.ImageQueueEntry
  alias MediaCentaur.Repo

  defp queue_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        owner_id: Ecto.UUID.generate(),
        owner_type: "entity",
        role: "poster",
        source_url: "https://image.tmdb.org/poster.jpg",
        entity_id: Ecto.UUID.generate(),
        media_dir: "/media"
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
      ImageQueue.update_statuses([entry], :complete)

      assert ImageQueue.list_pending(entity_id) == []
    end
  end

  # These guards were written against the per-entry `mark_failed/1`,
  # `reset_to_pending/1` and `update_status/2`, which production never called —
  # the pipeline only ever used the batch forms. The functions are gone; the
  # failure modes they guarded are kept here against the surviving API
  # (ADR-027: a regression guard moves, it does not disappear).
  describe "status transitions" do
    test "successive failures keep incrementing retry_count" do
      {:ok, entry} = ImageQueue.create(queue_attrs())
      assert entry.retry_count == 0

      {1, _} = ImageQueue.mark_failed_batch([entry])
      failed = Repo.get!(ImageQueueEntry, entry.id)
      assert failed.status == "failed"
      assert failed.retry_count == 1

      {1, _} = ImageQueue.mark_failed_batch([failed])
      assert Repo.get!(ImageQueueEntry, entry.id).retry_count == 2
    end

    test "reset_to_pending_all sets status back to pending without clearing retries" do
      {:ok, entry} = ImageQueue.create(queue_attrs())
      {1, _} = ImageQueue.mark_failed_batch([entry])
      failed = Repo.get!(ImageQueueEntry, entry.id)

      {1, _} = ImageQueue.reset_to_pending_all([failed])

      reset = Repo.get!(ImageQueueEntry, entry.id)
      assert reset.status == "pending"
      assert reset.retry_count == 1
    end

    test "reset_to_pending_all no-ops on an empty list" do
      assert ImageQueue.reset_to_pending_all([]) == {0, nil}
    end

    test "update_statuses sets an arbitrary status" do
      {:ok, entry} = ImageQueue.create(queue_attrs())

      {1, _} = ImageQueue.update_statuses([entry], :complete)
      assert Repo.get!(ImageQueueEntry, entry.id).status == "complete"
    end
  end

  describe "list_retryable" do
    test "returns pending and failed entries" do
      {:ok, pending} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, failed_entry} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))
      {1, _} = ImageQueue.mark_failed_batch([failed_entry])
      {:ok, complete_entry} = ImageQueue.create(queue_attrs(%{role: "logo"}))
      ImageQueue.update_statuses([complete_entry], :complete)

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
      {1, _} = ImageQueue.mark_failed_batch([entry])

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
        refreshed = Repo.get!(ImageQueueEntry, entry.id)
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
        refreshed = Repo.get!(ImageQueueEntry, entry.id)
        assert refreshed.status == "failed"
        assert refreshed.retry_count == entry.retry_count + 1
      end
    end

    test "no-ops on an empty list" do
      assert ImageQueue.mark_failed_batch([]) == {0, nil}
    end
  end

  describe "prune/2" do
    test "deletes complete entries past the completed cutoff and keeps fresh pending ones" do
      {:ok, complete} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {1, _} = ImageQueue.update_statuses([complete], :complete)
      {:ok, pending} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))

      future_completed_cutoff = DateTime.add(DateTime.utc_now(), 60, :second)
      distant_stale_cutoff = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

      assert ImageQueue.prune(future_completed_cutoff, distant_stale_cutoff) == 1
      assert Repo.get(ImageQueueEntry, complete.id) == nil
      assert Repo.get!(ImageQueueEntry, pending.id)
    end

    test "deletes entries of any status not touched since the stale cutoff" do
      {:ok, abandoned_pending} = ImageQueue.create(queue_attrs(%{role: "poster"}))

      future_stale_cutoff = DateTime.add(DateTime.utc_now(), 60, :second)
      distant_completed_cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

      assert ImageQueue.prune(distant_completed_cutoff, future_stale_cutoff) == 1
      assert Repo.get(ImageQueueEntry, abandoned_pending.id) == nil
    end

    test "keeps recently-touched entries of every status" do
      {:ok, pending} = ImageQueue.create(queue_attrs(%{role: "poster"}))
      {:ok, failed} = ImageQueue.create(queue_attrs(%{role: "backdrop"}))
      {1, _} = ImageQueue.mark_failed_batch([failed])

      completed_cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)
      stale_cutoff = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

      assert ImageQueue.prune(completed_cutoff, stale_cutoff) == 0
      assert Repo.get!(ImageQueueEntry, pending.id)
      assert Repo.get!(ImageQueueEntry, failed.id)
    end
  end
end
