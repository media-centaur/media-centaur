defmodule MediaCentaurWeb.Storybook.Acquisition.MediaResults do
  @moduledoc """
  The flat media-search answer sheet — TMDB results as page content
  below the omnibox (no floating overlay). Rows carry poster thumb,
  identity line, overview, the row verb (Download / Track release), and
  a sibling bookmark toggle for the watchlist; rows the library already
  presents carry a quiet In library marker. The header row holds the
  search status and the Clear search reset.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.TitleResult

  def function, do: &MediaCentaurWeb.Components.Acquisition.MediaResults.media_results/1
  def render_source, do: :function
  def layout, do: :one_column

  defp results do
    [
      %TitleResult{
        tmdb_id: 246_810,
        media_type: :tv_series,
        name: "Sample Show",
        year: "2010",
        release_date: ~D[2010-06-16],
        poster_path: "/sample-show-poster.jpg",
        overview: "A sample overview line that helps confirm this is the show you meant.",
        tracked?: true
      },
      %TitleResult{
        tmdb_id: 777,
        media_type: :movie,
        name: "Sample Movie",
        year: "2010",
        release_date: ~D[2010-03-05],
        overview: "A sample movie overview."
      },
      %TitleResult{
        tmdb_id: 778,
        media_type: :movie,
        name: "Sample Movie Returns: An Extraordinarily Long Title That Truncates",
        year: "2999",
        release_date: ~D[2999-01-01]
      },
      %TitleResult{
        tmdb_id: 779,
        media_type: :tv_series,
        name: "Sample Upcoming Show",
        year: "2999",
        release_date: ~D[2999-03-01],
        overview: "Already tracked and not yet out — the verb slot stays empty.",
        tracked?: true
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :results,
        description:
          "The answer sheet: one row per TMDB hit in relevance order — poster thumb " <>
            "(fake paths render broken outside the app; the icon fallback shows the " <>
            "no-poster treatment), identity line with quiet type/year text, overview, " <>
            "tracked marker, and the row verb. Each row ends in the bookmark toggle — " <>
            "filled primary on Sample Movie (watchlisted), ghost elsewhere — and " <>
            "Sample Show carries the quiet In library marker. The upcoming/released " <>
            "chips sit between the box and the rows with counts.",
        attributes: %{
          query: "sample",
          results: results(),
          searching?: false,
          release_mode_available: true,
          scope: :all,
          today: ~D[2026-08-02],
          watchlisted_refs: MapSet.new([{777, :movie}]),
          in_library_refs: MapSet.new([{246_810, :tv_series}])
        }
      },
      %Variation{
        id: :scoped_upcoming,
        description:
          "The Upcoming chip active — only future/undated titles remain; clicking the " <>
            "active chip returns to everything.",
        attributes: %{
          query: "sample",
          results: results(),
          searching?: false,
          release_mode_available: true,
          scope: :upcoming,
          today: ~D[2026-08-02]
        }
      },
      %Variation{
        id: :scoped_empty,
        description:
          "An active scope with nothing on its side — the honest scoped-empty line " <>
            "(the chip stays so toggling off remains possible).",
        attributes: %{
          query: "sample",
          results: Enum.take(results(), 2),
          searching?: false,
          release_mode_available: true,
          scope: :upcoming,
          today: ~D[2026-08-02]
        }
      },
      %Variation{
        id: :track_only,
        description:
          "No indexer configured — the row verb honestly reads Track; nothing " <>
            "promises a grab the page can't make. (Also the Released scope: both " <>
            "rows are out.)",
        attributes: %{
          query: "sample",
          results: Enum.take(results(), 2),
          searching?: false,
          release_mode_available: false,
          scope: :released,
          today: ~D[2026-08-02]
        }
      },
      %Variation{
        id: :searching,
        description: "Type-ahead in flight — status in the header row, prior rows still standing.",
        attributes: %{
          query: "sample",
          results: Enum.take(results(), 1),
          searching?: true,
          release_mode_available: true
        }
      },
      %Variation{
        id: :no_results,
        description: "The honest empty answer, with Clear search as the one reset.",
        attributes: %{
          query: "zzzzz",
          results: [],
          searching?: false,
          release_mode_available: true
        }
      },
      %Variation{
        id: :inactive_query,
        description:
          "Under two typed characters the section does not exist at all — results are " <>
            "page content gated on an active query, never an empty shell.",
        attributes: %{
          query: "z",
          results: [],
          searching?: false,
          release_mode_available: true
        }
      }
    ]
  end
end
