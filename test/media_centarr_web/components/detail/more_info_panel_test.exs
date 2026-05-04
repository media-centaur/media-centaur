defmodule MediaCentarrWeb.Components.Detail.MoreInfoPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.Detail.MoreInfoPanel

  defp render_panel(assigns) do
    render_component(&MoreInfoPanel.more_info_panel/1, assigns)
  end

  defp default_entity(overrides \\ %{}) do
    Map.merge(
      %{
        type: :movie,
        name: "Sample Movie",
        url: "https://www.themoviedb.org/movie/1",
        imdb_id: nil,
        duration: nil,
        date_published: nil,
        studio: nil,
        country_code: nil,
        original_language: nil,
        cast: [],
        crew: []
      },
      overrides
    )
  end

  describe "more_info_panel/1" do
    test "renders director name with TMDB person link" do
      crew = [
        %{
          "tmdb_person_id" => 1,
          "name" => "Sample Director",
          "job" => "Director",
          "department" => "Directing",
          "profile_path" => nil
        }
      ]

      html = render_panel(%{entity: default_entity(%{crew: crew})})

      assert html =~ "Directed by"
      assert html =~ "Sample Director"
      assert html =~ "themoviedb.org/person/1"
    end

    test "renders multiple writers separated by commas" do
      crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Writer A",
          "job" => "Screenplay",
          "department" => "Writing",
          "profile_path" => nil
        },
        %{
          "tmdb_person_id" => 3,
          "name" => "Writer B",
          "job" => "Story",
          "department" => "Writing",
          "profile_path" => nil
        }
      ]

      html = render_panel(%{entity: default_entity(%{crew: crew})})

      assert html =~ "Written by"
      assert html =~ "Writer A"
      assert html =~ "Writer B"
      assert html =~ "themoviedb.org/person/2"
      assert html =~ "themoviedb.org/person/3"
    end

    test "omits credit lines that have no entries" do
      html = render_panel(%{entity: default_entity()})

      refute html =~ "Directed by"
      refute html =~ "Written by"
    end

    test "renders cast as a grid without horizontal-scroll classes" do
      cast = [
        %{
          "name" => "Sample Actor",
          "character" => "Sample Role",
          "tmdb_person_id" => 9,
          "profile_path" => "/p.jpg",
          "order" => 0
        }
      ]

      html = render_panel(%{entity: default_entity(%{cast: cast})})

      assert html =~ "Sample Actor"
      assert html =~ "Sample Role"
      assert html =~ "grid"
      refute html =~ "overflow-x-auto"
    end

    test "links out to TMDB" do
      html = render_panel(%{entity: default_entity()})
      assert html =~ "TMDB"
      assert html =~ "themoviedb.org/movie/1"
    end

    test "renders IMDb link only when imdb_id is set" do
      with_imdb = render_panel(%{entity: default_entity(%{imdb_id: "tt0000001"})})
      assert with_imdb =~ "IMDb"
      assert with_imdb =~ "imdb.com/title/tt0000001"

      without_imdb = render_panel(%{entity: default_entity()})
      refute without_imdb =~ "imdb.com/title"
    end

    test "renders meta block with studio, country, and runtime when present" do
      html =
        render_panel(%{
          entity:
            default_entity(%{
              studio: "Sample Studio",
              country_code: "US",
              original_language: "en",
              duration: "PT1H47M"
            })
        })

      assert html =~ "Sample Studio"
      # Country code is shown as-is for v1 (no full-name lookup)
      assert html =~ "US"
      assert html =~ "en"
    end
  end
end
