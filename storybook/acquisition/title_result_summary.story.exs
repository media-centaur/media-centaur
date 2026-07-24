defmodule MediaCentaurWeb.Storybook.Acquisition.TitleResultSummary do
  @moduledoc """
  The shared identity summary of a TMDB title-search hit — used by the
  omnibox dropdown rows and the Track modal result rows, each wrapping
  it in its own row chrome. Poster paths are fake, so thumbnails render
  broken outside the app; the icon-fallback variations show the real
  no-poster treatment.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.TitleResult

  def function, do: &MediaCentaurWeb.Components.Acquisition.TitleResultSummary.title_result_summary/1

  def render_source, do: :function

  # Each variation gets the flex-row container a real caller provides.
  def template do
    """
    <div class="max-w-md flex items-center gap-3 px-3 py-2 glass-inset rounded-lg">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :movie_with_poster,
        description: "Movie with a poster path (fake — renders broken outside the app).",
        attributes: %{
          result: %TitleResult{
            tmdb_id: 777,
            media_type: :movie,
            name: "Sample Movie",
            year: "2010",
            poster_path: "/sample-movie-poster.jpg"
          }
        }
      },
      %Variation{
        id: :tv_no_poster,
        description: "TV without a poster — the type-icon fallback.",
        attributes: %{
          result: %TitleResult{
            tmdb_id: 246_810,
            media_type: :tv_series,
            name: "Sample Show",
            year: "2010"
          }
        }
      },
      %Variation{
        id: :movie_no_poster_no_year,
        description: "Sparse TMDB data — no poster, no year; the type label and name carry the row.",
        attributes: %{
          result: %TitleResult{
            tmdb_id: 778,
            media_type: :movie,
            name: "Sample Movie"
          }
        }
      },
      %Variation{
        id: :long_name_truncates,
        description: "Name truncation inside a constrained row.",
        attributes: %{
          result: %TitleResult{
            tmdb_id: 779,
            media_type: :tv_series,
            name: "Sample Show Returns: An Extraordinarily Long Title That Truncates",
            year: "2012"
          }
        }
      }
    ]
  end
end
