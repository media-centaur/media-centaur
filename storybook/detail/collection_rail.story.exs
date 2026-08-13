defmodule MediaCentaurWeb.Storybook.Detail.CollectionRail do
  @moduledoc """
  The movie-first collection modal's picker (UIDR-023) — one poster
  tile per member, muted tiles for announced parts, saga label line
  with the watched count. Poster URLs are intentionally absent (the
  storybook image server can't satisfy them), so every tile renders
  the no-artwork fallback: title text on the inset panel — accurate
  to the "no artwork scraped yet" state.

  Selection is `data-selected` + the white outline ring; the watched
  check and the progress underline are the same state chrome the
  library tiles carry.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.ViewModel.MovieListItem

  def function, do: &MediaCentaurWeb.Components.Detail.CollectionRail.collection_rail/1
  def render_source, do: :function
  def layout, do: :one_column

  # The rail reads over the modal panel — stand a dark panel in.
  def template do
    """
    <div class="rounded-lg bg-base-100 py-4">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :mid_saga,
        description:
          "Three members mid-saga: movie 1 watched (check badge), movie 2 " <>
            "selected + in progress (selection ring, progress underline), " <>
            "movie 3 unwatched. Label line carries \"1 of 3 watched\".",
        attributes: %{
          movie_items: library_items(),
          selected_id: "66666666-6666-6666-6666-666666666602",
          saga_label: "Sample Picture Trilogy"
        }
      },
      %Variation{
        id: :with_upcoming,
        description:
          "A tracked collection's announced fourth part: muted, unpickable " <>
            "dashed tile with the air-date pill.",
        attributes: %{
          movie_items:
            library_items() ++
              [
                %MovieListItem.Upcoming{
                  part_tmdb_id: 900_004,
                  title: "Sample Picture IV",
                  air_date: ~D[2027-03-15],
                  sub_status: :unaired
                }
              ],
          selected_id: "66666666-6666-6666-6666-666666666602",
          saga_label: "Sample Picture Trilogy"
        }
      },
      %Variation{
        id: :untouched,
        description:
          "Nothing watched yet: first member selected, no state chrome, and " <>
            "the label line carries no scorekeeping (the note only appears " <>
            "once something is watched).",
        attributes: %{
          movie_items: untouched_items(),
          selected_id: "66666666-6666-6666-6666-666666666601",
          saga_label: "Sample Picture Trilogy"
        }
      },
      %Variation{
        id: :offline,
        description: "Storage offline (`available: false`) — poster images are dropped.",
        attributes: %{
          movie_items: library_items(),
          selected_id: "66666666-6666-6666-6666-666666666602",
          saga_label: "Sample Picture Trilogy",
          available: false
        }
      }
    ]
  end

  defp library_items do
    [movie_1, movie_2, movie_3] = member_movies()

    [
      %MovieListItem.Library{
        movie: movie_1,
        progress: %{position_seconds: 5400.0, duration_seconds: 5400.0, completed: true},
        state: :watched,
        is_resume_target: false
      },
      %MovieListItem.Library{
        movie: movie_2,
        progress: %{position_seconds: 1500.0, duration_seconds: 5700.0, completed: false},
        state: :current,
        is_resume_target: true
      },
      %MovieListItem.Library{
        movie: movie_3,
        progress: nil,
        state: :unwatched,
        is_resume_target: false
      }
    ]
  end

  defp untouched_items do
    for movie <- member_movies() do
      %MovieListItem.Library{movie: movie, progress: nil, state: :unwatched, is_resume_target: false}
    end
  end

  defp member_movies do
    [
      %{
        id: "66666666-6666-6666-6666-666666666601",
        name: "Sample Picture I",
        date_published: ~D[1920-05-01],
        images: []
      },
      %{
        id: "66666666-6666-6666-6666-666666666602",
        name: "Sample Picture II",
        date_published: ~D[1922-07-10],
        images: []
      },
      %{
        id: "66666666-6666-6666-6666-666666666603",
        name: "Sample Picture III",
        date_published: ~D[1925-11-04],
        images: []
      }
    ]
  end
end
