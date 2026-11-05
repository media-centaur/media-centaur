defmodule MediaCentaurWeb.Storybook.Review.QueueItem do
  @moduledoc "One row of Review's bulk list (campaign `review-bulk-match`): the whole row ticks it."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewQueue.queue_item/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s|<div class="w-[1200px] glass-surface rounded-lg p-2"><.psb-variation/></div>|

  defp file(overrides) do
    Map.merge(
      %{
        id: "f1",
        file_path:
          "/media/Sample.Show.Signed.S01E01-GROUP/Sample.Show.Signed.S01E01.Episode.One.1080p.WEB-DL.mkv",
        media_directory: "/media",
        parsed_title: "Sample Show Signed",
        parsed_year: nil,
        parsed_type: "tv",
        parsed_season: 1,
        parsed_episode: 1,
        tmdb_id: nil,
        tmdb_type: nil,
        match_title: nil,
        match_year: nil,
        match_poster_path: nil,
        confidence: nil,
        candidates: [],
        status: :pending,
        error_message: nil,
        wanted_title: nil
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :no_results,
        description: "Waiting, nothing found on TMDB under the name it carries",
        attributes: %{id: "item-no-results", file: file(%{})}
      },
      %Variation{
        id: :ticked,
        description: "Ticked",
        attributes: %{id: "item-ticked", file: file(%{}), ticked: true}
      },
      %Variation{
        id: :unsure,
        description: "A best guess below the auto-approve threshold",
        attributes: %{
          id: "item-unsure",
          file:
            file(%{
              file_path: "/media/Movie.A.1999.1080p.BluRay.x264-GROUP.mkv",
              parsed_title: "Movie A",
              parsed_year: 1999,
              parsed_type: "movie",
              parsed_season: nil,
              parsed_episode: nil,
              tmdb_id: 550,
              tmdb_type: "movie",
              match_title: "Movie A",
              match_year: "1999",
              confidence: 0.72
            })
        }
      },
      %Variation{
        id: :grab_conflict,
        description:
          "A confident match that contradicts what a grab of ours asked for; the row names that title",
        attributes: %{
          id: "item-grab-conflict",
          file:
            file(%{
              file_path:
                "/media/Movie.I.2003.1080p.BluRay.x264-GROUP/Movie.I.2003.1080p.BluRay.x264-GROUP.mkv",
              parsed_title: "Movie I",
              parsed_year: 2003,
              parsed_type: "movie",
              parsed_season: nil,
              parsed_episode: nil,
              tmdb_id: 990_009,
              tmdb_type: "movie",
              match_title: "Movie I",
              match_year: "2003",
              confidence: 1.05,
              wanted_title: "Movie J"
            })
        }
      },
      %Variation{
        id: :not_added,
        description: "Matched, but the library did not add it; the reason is the tip",
        attributes: %{
          id: "item-not-added",
          file:
            file(%{
              tmdb_id: 4242,
              tmdb_type: "tv",
              match_title: "Sample Show",
              match_year: "1995",
              error_message: "Importing it failed. Approve it again to retry."
            })
        }
      },
      %Variation{
        id: :importing,
        description: "Importing: nothing to act on, so no tick and not a control",
        attributes: %{
          id: "item-importing",
          selectable: false,
          file: file(%{status: :approved, tmdb_id: 4242, match_title: "Sample Show", match_year: "1995"})
        }
      },
      %Variation{
        id: :dismissed,
        description: "Dismissed",
        attributes: %{id: "item-dismissed", file: file(%{status: :dismissed})}
      }
    ]
  end
end
