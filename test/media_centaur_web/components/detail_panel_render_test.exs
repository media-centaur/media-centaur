defmodule MediaCentaurWeb.Components.DetailPanelRenderTest do
  @moduledoc """
  Render-level integration tests for `DetailPanel`. Lightweight —
  asserts the More info routing wires up correctly for movies. Deeper
  function-level tests live in `detail_panel_test.exs` and component
  tests live in `more_info_panel_test.exs`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.DetailPanel

  defp render_panel(entity, overrides \\ %{}) do
    base = %{entity: entity}
    render_component(&DetailPanel.detail_panel/1, Map.merge(base, overrides))
  end

  describe "more info integration" do
    test "renders More info button on the play card for movies" do
      movie = build_entity(%{type: :movie})
      html = render_panel(movie)
      assert html =~ "More info"
      assert html =~ "toggle_credits_view"
    end

    test "renders More info button on the play card for tv_series" do
      tv = build_entity(%{type: :tv_series, seasons: []})
      html = render_panel(tv)
      assert html =~ "More info"
      assert html =~ "toggle_credits_view"
    end

    test "main view does NOT inline cast — cast lives behind More info" do
      movie =
        build_entity(%{
          type: :movie,
          cast: [
            %Person{
              name: "Sample Actor",
              character: "Sample Role",
              tmdb_person_id: 7,
              profile_path: "/x.jpg",
              order: 0
            }
          ]
        })

      html = render_panel(movie)
      refute html =~ "Sample Actor"
      refute html =~ "Sample Role"
    end

    test "credits view renders Created by + cast + meta for a tv_series" do
      tv =
        build_entity(%{
          type: :tv_series,
          seasons: [],
          network: "Sample Network",
          date_published: ~D[2020-01-15],
          status: :returning,
          imdb_id: "tt0000200",
          cast: [
            %Person{
              name: "Sample Actor",
              character: "Sample Role",
              tmdb_person_id: 7,
              profile_path: nil,
              order: 0
            }
          ],
          crew: [
            %Person{
              tmdb_person_id: 11,
              name: "Sample Creator",
              job: "Creator",
              department: "Creator",
              profile_path: nil
            }
          ]
        })

      html = render_panel(tv, %{detail_view: :credits})

      assert html =~ "Created by"
      assert html =~ "Sample Creator"
      assert html =~ "Sample Actor"
      assert html =~ "Sample Role"
      assert html =~ "Network"
      assert html =~ "Sample Network"
      assert html =~ "First aired"
      assert html =~ "Returning"
      assert html =~ "imdb.com/title/tt0000200"
    end

    test "credits view renders cast and crew for a movie" do
      movie =
        build_entity(%{
          type: :movie,
          cast: [
            %Person{
              name: "Sample Actor",
              character: "Sample Role",
              tmdb_person_id: 7,
              profile_path: nil,
              order: 0
            }
          ],
          crew: [
            %Person{
              tmdb_person_id: 1,
              name: "Sample Director",
              job: "Director",
              department: "Directing",
              profile_path: nil
            }
          ]
        })

      html = render_panel(movie, %{detail_view: :credits})

      assert html =~ "Sample Actor"
      assert html =~ "Sample Role"
      assert html =~ "Directed by"
      assert html =~ "Sample Director"
    end
  end

  describe "movie_series constituent rows" do
    test "renders a present constituent movie row without raising" do
      # Regression: `DetailItem.movie_entry_to_map/1` produces movie-row
      # maps with no `:images` key. `movie_row` calls
      # `image_url(@movie, "poster")`, which dot-accessed `entity.images`
      # and raised `KeyError` — taking down the whole HomeLive process
      # the moment a movie_series detail panel rendered a present movie.
      movie_row_map = %{
        id: Ecto.UUID.generate(),
        name: "Sample Movie",
        present?: true,
        content_url: "/movies/sample/sample.mkv",
        date_published: ~D[2022-05-21],
        collection_position: 1
      }

      movie_series = build_entity(%{type: :movie_series, movies: [movie_row_map]})

      html = render_panel(movie_series)

      assert html =~ "Sample Movie"
    end
  end
end
