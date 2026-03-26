defmodule MediaCentaur.Pipeline.ImageQueue do
  @moduledoc """
  Context functions for the pipeline image download queue.

  Manages `ImageQueueEntry` records — the pipeline's own tracking of
  pending, in-progress, failed, and completed image downloads.
  """
  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Pipeline.ImageQueueEntry

  @doc """
  Creates a queue entry. Uses upsert on (owner_id, role) — if the same
  image is queued again, the existing entry is updated with the new source_url
  and reset to pending.
  """
  def create(attrs) do
    ImageQueueEntry.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:source_url, :status, :retry_count, :updated_at]},
      conflict_target: [:owner_id, :role]
    )
  end

  @doc "Returns all pending entries for a given entity."
  def list_pending(entity_id) do
    from(e in ImageQueueEntry,
      where: e.entity_id == ^entity_id and e.status == "pending"
    )
    |> Repo.all()
  end

  @doc "Returns the count of entries with status failed (for dashboard display)."
  def retrying_count do
    from(e in ImageQueueEntry,
      where: e.status == "failed",
      select: count(e.id)
    )
    |> Repo.one()
  end

  @doc "Returns all entries with status pending or failed (for retry scheduler)."
  def list_retryable do
    from(e in ImageQueueEntry,
      where: e.status in ["pending", "failed"]
    )
    |> Repo.all()
  end

  @doc "Updates entry status to the given value."
  def update_status(entry, status) when is_atom(status) do
    ImageQueueEntry.status_changeset(entry, to_string(status))
    |> Repo.update()
  end

  @doc "Marks entry as failed and increments retry_count."
  def mark_failed(entry) do
    ImageQueueEntry.fail_changeset(entry)
    |> Repo.update()
  end

  @doc "Resets entry status to pending (for retry)."
  def reset_to_pending(entry) do
    ImageQueueEntry.reset_changeset(entry)
    |> Repo.update()
  end
end
