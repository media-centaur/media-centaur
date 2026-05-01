defmodule MediaCentarr.Library.ProgressTracker do
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

  @doc "Flags the record as incomplete and stamps `last_watched_at`."
  def mark_incomplete_changeset(record) do
    change(record, completed: false, last_watched_at: DateTime.utc_now(:second))
  end
end
