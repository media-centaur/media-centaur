defmodule MediaCentarr.WatchHistory.Views.SummaryData do
  @moduledoc """
  Snapshot of every aggregate the History page renders on mount: the
  top-of-page stats card, the GitHub-style heatmap (one cell-set per
  filter type), and the rewatch-count maps used to badge events with
  "you've watched this N times."

  The fields mirror the legacy multi-call read shape so consumers
  (`MediaCentarrWeb.WatchHistoryLive`) can assign them directly with
  no remapping.
  """

  @enforce_keys [:stats, :heatmap_cells_by_type, :rewatch_counts]
  defstruct [:stats, :heatmap_cells_by_type, :rewatch_counts]

  @type t :: %__MODULE__{
          stats: %{
            total_count: non_neg_integer(),
            total_seconds: float(),
            streak: non_neg_integer(),
            heatmap: %{Date.t() => non_neg_integer()}
          },
          heatmap_cells_by_type: %{
            (nil | :movie | :episode | :video_object) => [map()]
          },
          rewatch_counts: %{
            movie: %{Ecto.UUID.t() => pos_integer()},
            episode: %{Ecto.UUID.t() => pos_integer()},
            video_object: %{Ecto.UUID.t() => pos_integer()}
          }
        }
end
