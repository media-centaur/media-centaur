defmodule MediaCentaur.Library.ProgressTracker do
  @moduledoc """
  Shared contract for per-item playback progress schemas (WatchProgress,
  ExtraProgress). Each implementation maintains `position_seconds`,
  `duration_seconds`, `completed`, and `last_watched_at`, keyed by a
  schema-specific foreign key.

  Implementations reuse `mark_completed_changeset/1` and
  `mark_incomplete_changeset/1` via `defdelegate` — those transitions are
  identical across all progress schemas.
  """

  import Ecto.Changeset

  @callback create_changeset(attrs :: map()) :: Ecto.Changeset.t()
  @callback update_changeset(record :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  @callback mark_completed_changeset(record :: Ecto.Schema.t()) :: Ecto.Changeset.t()
  @callback mark_incomplete_changeset(record :: Ecto.Schema.t()) :: Ecto.Changeset.t()

  @doc "Flags the record as completed and stamps `last_watched_at`."
  def mark_completed_changeset(record) do
    change(record, completed: true, last_watched_at: DateTime.utc_now(:second))
  end

  @doc """
  Returns the record to unwatched: clears the position, drops the
  completed flag, and stamps `last_watched_at`.

  The position goes back to zero because the control that reaches here is
  labelled "Mark unwatched". Leaving it where it stood would put an item
  that ran to the end unattended back as "in progress at 100%" — a full
  progress bar, and a Play that resumes at the last second. `ProgressRecords.state_from_progress/1`
  reads position 0 with `completed: false` as `:unwatched`, so zeroing is
  what makes the record say what the label promised.

  `duration_seconds` describes the file rather than the watching, so it
  survives. `last_watched_at` is stamped rather than cleared: it is the
  anchor `Playback.Resume` and `Library.ProgressSummary` walk from, so the
  item just unmarked becomes the one Play picks up — now from the start.
  """
  def mark_incomplete_changeset(record) do
    change(record,
      completed: false,
      position_seconds: 0.0,
      last_watched_at: DateTime.utc_now(:second)
    )
  end
end
