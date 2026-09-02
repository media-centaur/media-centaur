defmodule MediaCentaurWeb.Storybook.TMDB.TitleSummary do
  @moduledoc """
  The one identity block for a TMDB title — poster thumb, name, quiet
  type/year text, overview — that search rows, watchlist rows and feed
  rows share. Surfaces add markers (Tracked, In library) and may
  displace the overview with a note. `poster_url: nil` shows the icon
  fallback.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary/1
  def render_source, do: :function
  def layout, do: :one_column

  defp title(overrides) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          release_date: ~D[2010-03-05],
          overview: "A sample movie overview that confirms this is the title you meant."
        },
        overrides
      )
    )
  end

  def variations do
    [
      %Variation{
        id: :movie,
        description:
          "A movie with no cached art — the film icon fallback, name, Movie · year, overview.",
        attributes: %{title: title(%{}), poster_url: nil}
      },
      %Variation{
        id: :show_no_year,
        description: "A show without a year — the TV icon and no dangling separator.",
        attributes: %{
          title:
            title(%{
              tmdb_id: 42,
              media_type: :tv_series,
              name: "Sample Show",
              year: nil,
              overview: nil
            }),
          poster_url: nil
        }
      },
      %Variation{
        id: :with_poster,
        description:
          "With art the placeholder gives way to the eager+sync poster thumb " <>
            "(the bundled sample poster).",
        attributes: %{title: title(%{}), poster_url: "/images/sample-nosferatu-poster.jpg"}
      },
      %Variation{
        id: :markers,
        description:
          "Surface decorations ride the identity line — the Tracked and In library " <>
            "markers as search rows render them.",
        attributes: %{title: title(%{}), poster_url: nil},
        slots: [
          ~s|<:markers><span class="shrink-0 text-xs text-success/70">Tracked</span><span class="shrink-0 text-xs text-base-content/50">In library</span></:markers>|
        ]
      },
      %Variation{
        id: :secondary,
        description:
          "A secondary line displaces the overview — a watchlist note is why the title is here.",
        attributes: %{title: title(%{}), poster_url: nil},
        slots: [
          ~s|<:secondary>Recommended after movie night — the sequel to the one we liked.</:secondary>|
        ]
      },
      %Variation{
        id: :long_name,
        description: "A long name truncates; the type/year text never wraps.",
        attributes: %{
          title: title(%{name: "Sample Movie Returns: An Extraordinarily Long Title That Truncates"}),
          poster_url: nil
        }
      }
    ]
  end
end
