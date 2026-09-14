defmodule MediaCentaurWeb.Storybook.Title.TrackingControls do
  @moduledoc """
  The rows a listed title shows beneath its details (UIDR-042): Track
  release dates and Auto-grab, over the one record. A title not on the
  list shows nothing — the bookmark in the action strip lists it; an
  ignored one shows the line saying the Feed hides it. Auto-grab holds
  the Track row on; a movie that is out has only Auto-grab; a movie the
  library owns has no rows.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.TrackingControls.tracking_controls/1

  defp base(overrides) do
    Map.merge(
      %{
        id: "tracking-controls-story",
        ref: "tv_series-1399",
        rung: :list,
        media_type: :tv_series,
        release_ahead?: true,
        complete?: false,
        approval_policy: "review",
        acquisition?: true
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :not_listed,
        description: "A title with no record: nothing — listing is the bookmark's act (UIDR-039).",
        attributes: base(%{rung: nil})
      },
      %Variation{
        id: :ignored,
        description: "An ignored title shows the one line that says the Feed is hiding it.",
        attributes: base(%{rung: :ignored})
      },
      %VariationGroup{
        id: :series_by_rung,
        description: "A listed series at each rung: both rows; at Grab the Track row is held on.",
        variations:
          for rung <- [:list, :follow, :grab] do
            %Variation{id: rung, attributes: base(%{rung: rung})}
          end
      },
      %VariationGroup{
        id: :movie_by_rung,
        description: "A listed movie with a release ahead, at each rung.",
        variations:
          for rung <- [:list, :follow, :grab] do
            %Variation{id: rung, attributes: base(%{rung: rung, media_type: :movie, ref: "movie-550"})}
          end
      },
      %Variation{
        id: :movie_out,
        description:
          "A movie that is out: nothing left to track, so Auto-grab alone — it keeps " <>
            "searching until a release exists.",
        attributes: base(%{media_type: :movie, ref: "movie-550", release_ahead?: false})
      },
      %Variation{
        id: :movie_in_library,
        description: "A movie the library owns is complete: no rows.",
        attributes: base(%{media_type: :movie, ref: "movie-550", complete?: true})
      },
      %Variation{
        id: :automatic,
        description:
          "Under an automatic approval policy (auto-select planning) the Auto-grab line " <>
            "says it downloads without asking.",
        attributes: base(%{rung: :grab, approval_policy: "automatic"})
      },
      %Variation{
        id: :acquisition_missing,
        description:
          "No indexer or download client yet: the rows stay, and the note says auto-grab " <>
            "downloads nothing until one is set up.",
        attributes: base(%{rung: :grab, acquisition?: false})
      }
    ]
  end
end
