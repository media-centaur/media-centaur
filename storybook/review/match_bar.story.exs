defmodule MediaCentaurWeb.Storybook.Review.MatchBar do
  @moduledoc "The action bar for the ticked rows of Review's bulk list (campaign `review-bulk-match`)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewQueue.match_bar/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s|<div class="w-[1200px]"><.psb-variation/></div>|

  defp results do
    [
      %{
        tmdb_id: "4242",
        tmdb_type: "tv",
        title: "Sample Show",
        year: "1995",
        overview: nil,
        poster_path: nil
      },
      %{
        tmdb_id: "4243",
        tmdb_type: "tv",
        title: "Sample Show: The Special",
        year: "2011",
        overview: nil,
        poster_path: nil
      },
      %{
        tmdb_id: "4244",
        tmdb_type: "tv",
        title: "Sample Show Live",
        year: "2003",
        overview: nil,
        poster_path: nil
      }
    ]
  end

  defp base(overrides) do
    Map.merge(
      %{
        count: 6,
        status: :waiting,
        query: "Sample Show Signed",
        type: :tv,
        delete_label: "Press again to delete 6 files and 6 folders"
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :results,
        description: "Six rows ticked; the search ran with the first row's parsed title",
        attributes: base(%{results: results(), searched: true})
      },
      %Variation{
        id: :searching,
        description: "The search is running",
        attributes: base(%{searching: true})
      },
      %Variation{
        id: :nothing_found,
        description: "TMDB has nothing for the query",
        attributes: base(%{searched: true})
      },
      %Variation{
        id: :accept_guesses,
        description: "Every ticked row has a best guess: Accept best guesses",
        attributes:
          base(%{count: 3, query: "Movie A", type: :movie, accept_guesses: true, searched: true})
      },
      %Variation{
        id: :delete_armed,
        description: "Delete armed: it names what goes",
        attributes: base(%{results: results(), searched: true, delete_armed: true})
      },
      %Variation{
        id: :dismissed,
        description: "The Dismissed view: Restore and Delete",
        attributes: base(%{status: :dismissed, count: 2})
      },
      %Variation{
        id: :no_tmdb,
        description: "TMDB is not set up: no search",
        attributes: base(%{tmdb_ready: false})
      }
    ]
  end
end
