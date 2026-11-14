defmodule MediaCentaur.Library.ProgressTracker do
  @moduledoc """
  Shared contract for per-item playback progress schemas (WatchProgress,
  ExtraProgress). Each implementation maintains `position_seconds`,
  `duration_seconds`, `completed`, and `last_watched_at`, keyed by a
  schema-specific foreign key.

  A row holds two facts with separate writers. The watched mark
  (`completed`) is set by a finish or the Mark watched control and cleared
  by Mark unwatched. The viewing in flight (`position_seconds`,
  `duration_seconds`, `last_watched_at`) is written by a position tick
  (`update_changeset/2`, which never touches the mark) and ended by a
  finish or either watched control.

  Implementations reuse `mark_completed_changeset/1`,
  `mark_incomplete_changeset/1` and `finish_changeset/2` via `defdelegate`
  — those transitions are identical across all progress schemas.
  """

  import Ecto.Changeset

  @callback create_changeset(attrs :: map()) :: Ecto.Changeset.t()
  @callback update_changeset(record :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  @callback mark_completed_changeset(record :: Ecto.Schema.t()) :: Ecto.Changeset.t()
  @callback mark_incomplete_changeset(record :: Ecto.Schema.t()) :: Ecto.Changeset.t()
  @callback finish_changeset(record :: Ecto.Schema.t(), duration_seconds :: number()) ::
              Ecto.Changeset.t()

  @doc """
  The watched control sets the mark and clears any viewing in flight. It
  is not a viewing: `last_watched_at` stands.
  """
  def mark_completed_changeset(record), do: change(record, completed: true, position_seconds: 0.0)

  @doc """
  The watched control clears the mark and any viewing in flight.
  `duration_seconds` describes the file, so it survives; `last_watched_at`
  stands, because a hand mark is not a viewing.
  """
  def mark_incomplete_changeset(record), do: change(record, completed: false, position_seconds: 0.0)

  @doc "Playback reached the end: the mark is set, the viewing is over, and the duration is kept."
  def finish_changeset(record, duration_seconds) do
    change(record,
      completed: true,
      position_seconds: 0.0,
      duration_seconds: duration_seconds / 1,
      last_watched_at: DateTime.utc_now(:second)
    )
  end
end
