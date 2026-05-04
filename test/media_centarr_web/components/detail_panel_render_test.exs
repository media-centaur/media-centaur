defmodule MediaCentarrWeb.Components.DetailPanelRenderTest do
  @moduledoc """
  Render-level integration tests for `DetailPanel`. Lightweight — only
  asserts visible content for the cast strip integration; deeper
  function-level tests live in `detail_panel_test.exs`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import MediaCentarr.TestFactory

  alias MediaCentarrWeb.Components.DetailPanel

  defp render_panel(entity) do
    render_component(&DetailPanel.detail_panel/1, entity: entity)
  end

  describe "cast strip integration" do
    test "renders cast strip for a movie with non-empty cast" do
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

      assert html =~ "Sample Actor"
      assert html =~ "Sample Role"
    end

    test "does not render the strip when cast is empty" do
      movie = build_entity(%{type: :movie, cast: []})
      html = render_panel(movie)
      refute html =~ ">Cast<"
    end

    test "does not render the strip for a tv_series" do
      tv = build_entity(%{type: :tv_series, seasons: []})
      html = render_panel(tv)
      refute html =~ ">Cast<"
    end
  end
end
