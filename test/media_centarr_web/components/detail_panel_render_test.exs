defmodule MediaCentarrWeb.Components.DetailPanelRenderTest do
  @moduledoc """
  Render-level integration tests for `DetailPanel`. Lightweight —
  asserts the More info routing wires up correctly for movies. Deeper
  function-level tests live in `detail_panel_test.exs` and component
  tests live in `more_info_panel_test.exs`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import MediaCentarr.TestFactory

  alias MediaCentarrWeb.Components.DetailPanel

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

    test "does not render More info button for tv_series" do
      tv = build_entity(%{type: :tv_series, seasons: []})
      html = render_panel(tv)
      refute html =~ "toggle_credits_view"
    end

    test "main view does NOT inline cast — cast lives behind More info" do
      movie =
        build_entity(%{
          type: :movie,
          cast: [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "tmdb_person_id" => 7,
              "profile_path" => "/x.jpg",
              "order" => 0
            }
          ]
        })

      html = render_panel(movie)
      refute html =~ "Sample Actor"
      refute html =~ "Sample Role"
    end

    test "credits view renders cast and crew for a movie" do
      movie =
        build_entity(%{
          type: :movie,
          cast: [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "tmdb_person_id" => 7,
              "profile_path" => nil,
              "order" => 0
            }
          ],
          crew: [
            %{
              "tmdb_person_id" => 1,
              "name" => "Sample Director",
              "job" => "Director",
              "department" => "Directing",
              "profile_path" => nil
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
end
