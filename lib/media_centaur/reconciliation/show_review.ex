defmodule MediaCentaur.Reconciliation.ShowReview do
  @moduledoc """
  Everything the show-scoped mapping review surface needs for one show
  (reconciliation campaign): the resolved `Resolution` plus the context to
  render and act on it — the awaiting files (so a placement's `artifact_id`
  maps back to a file path to display and link) and the spine (so a
  placement's `{season, episode}` maps to a canonical title).

  Assembled by `Reconciliation.resolve_show/2`; purely a read model, never
  persisted.
  """

  alias MediaCentaur.Reconciliation.{AwaitingFile, Resolution, SpineNode}

  @enforce_keys [:tmdb_id, :awaiting_files, :spine, :resolution]
  defstruct [:tmdb_id, :series_title, :tv_series_id, :awaiting_files, :spine, :resolution]

  @type t :: %__MODULE__{
          tmdb_id: integer(),
          series_title: String.t() | nil,
          tv_series_id: Ecto.UUID.t() | nil,
          awaiting_files: [AwaitingFile.t()],
          spine: [SpineNode.t()],
          resolution: Resolution.t()
        }
end
