defmodule MediaCentarrWeb.Components.Detail.MoreInfoPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentarr.Library.Person
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
        %Person{
          tmdb_person_id: 1,
          name: "Sample Director",
          job: "Director",
          department: "Directing",
          profile_path: nil
        }
      ]

      html = render_panel(%{entity: default_entity(%{crew: crew})})

      assert html =~ "Directed by"
      assert html =~ "Sample Director"
      assert html =~ "themoviedb.org/person/1"
    end

    test "renders multiple writers separated by commas" do
      crew = [
        %Person{
          tmdb_person_id: 2,
          name: "Writer A",
          job: "Screenplay",
          department: "Writing",
          profile_path: nil
        },
        %Person{
          tmdb_person_id: 3,
          name: "Writer B",
          job: "Story",
          department: "Writing",
          profile_path: nil
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
        %Person{
          name: "Sample Actor",
          character: "Sample Role",
          tmdb_person_id: 9,
          profile_path: "/p.jpg",
          order: 0
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

  defp tv_entity(overrides \\ %{}) do
    Map.merge(
      %{
        type: :tv_series,
        name: "Sample Series",
        url: "https://www.themoviedb.org/tv/1",
        imdb_id: nil,
        date_published: nil,
        network: nil,
        status: nil,
        country_code: nil,
        original_language: nil,
        cast: [],
        crew: []
      },
      overrides
    )
  end

  describe "more_info_panel/1 — TV series" do
    test "renders Created by row with linked creators" do
      crew = [
        %Person{
          tmdb_person_id: 11,
          name: "Sample Creator A",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        },
        %Person{
          tmdb_person_id: 12,
          name: "Sample Creator B",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        }
      ]

      html = render_panel(%{entity: tv_entity(%{crew: crew})})

      assert html =~ "Created by"
      assert html =~ "Sample Creator A"
      assert html =~ "Sample Creator B"
      assert html =~ "themoviedb.org/person/11"
      assert html =~ "themoviedb.org/person/12"
    end

    test "does not render Directed by / Written by for tv_series" do
      crew = [
        %Person{
          tmdb_person_id: 11,
          name: "Sample Creator",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        }
      ]

      html = render_panel(%{entity: tv_entity(%{crew: crew})})

      refute html =~ "Directed by"
      refute html =~ "Written by"
    end

    test "Created by row is omitted when crew has no creators" do
      html = render_panel(%{entity: tv_entity()})
      refute html =~ "Created by"
    end

    test "renders aggregate cast as the same grid shape as movies" do
      cast = [
        %Person{
          name: "Sample Actor",
          character: "Sample Role",
          tmdb_person_id: 9,
          profile_path: nil,
          order: 0
        }
      ]

      html = render_panel(%{entity: tv_entity(%{cast: cast})})

      assert html =~ "Sample Actor"
      assert html =~ "Sample Role"
      assert html =~ "grid"
      refute html =~ "overflow-x-auto"
    end

    test "renders TV-shaped meta block (Network, First aired, Status)" do
      html =
        render_panel(%{
          entity:
            tv_entity(%{
              network: "Sample Network",
              date_published: ~D[2020-01-15],
              status: :returning,
              country_code: "US",
              original_language: "en"
            })
        })

      assert html =~ "Network"
      assert html =~ "Sample Network"
      assert html =~ "First aired"
      assert html =~ "2020-01-15"
      assert html =~ "Status"
      # Status atom is humanised in the panel — TV statuses include
      # :returning, :ended, :canceled, :in_production, :planned.
      assert html =~ "Returning"
      assert html =~ "US"
      assert html =~ "en"
    end

    test "TV meta block omits movie-only fields (Studio, Runtime, Released)" do
      # TV series entity has no `:duration`, no `:studio`, and uses
      # `:date_published` for first-aired (relabelled "First aired"
      # in the TV meta block, not "Released"). Confirm those movie
      # labels never appear.
      html =
        render_panel(%{
          entity:
            tv_entity(%{
              network: "Sample Network",
              date_published: ~D[2020-01-15],
              status: :returning
            })
        })

      refute html =~ "Studio"
      refute html =~ "Runtime"
      refute html =~ "Released"
    end

    test "links out to TMDB" do
      html = render_panel(%{entity: tv_entity()})
      assert html =~ "TMDB"
      assert html =~ "themoviedb.org/tv/1"
    end

    test "renders IMDb link when imdb_id is set" do
      with_imdb = render_panel(%{entity: tv_entity(%{imdb_id: "tt0000200"})})
      assert with_imdb =~ "IMDb"
      assert with_imdb =~ "imdb.com/title/tt0000200"

      without_imdb = render_panel(%{entity: tv_entity()})
      refute without_imdb =~ "imdb.com/title"
    end

    test "empty cast and crew — credit lines collapse, meta + links remain" do
      html =
        render_panel(%{
          entity: tv_entity(%{network: "Sample Network", imdb_id: "tt0000200"})
        })

      refute html =~ "Created by"
      assert html =~ "Network"
      assert html =~ "TMDB"
      assert html =~ "IMDb"
    end

    test "cast filter input is hidden when cast count is at or below the cap" do
      cast = build_cast(24)
      html = render_panel(%{entity: tv_entity(%{cast: cast})})

      # Filter input + hook only render when cast > cap. With exactly 24
      # cards, the user has the full cast in front of them already.
      refute html =~ ~s(phx-hook="CastGridFilter")
      refute html =~ "Filter cast"
      refute html =~ "No cast members match"
    end

    test "cast filter input renders when cast count exceeds the cap" do
      cast = build_cast(30)
      html = render_panel(%{entity: tv_entity(%{cast: cast})})

      assert html =~ ~s(phx-hook="CastGridFilter")
      assert html =~ "Filter cast"
      assert html =~ "No cast members match"

      # Server still renders all 30 entries — the JS hook hides the
      # ones past the cap client-side. This is what gives the filter
      # something to search.
      Enum.each(cast, fn person ->
        assert html =~ person.name
      end)
    end

    test "cards past the cap are server-rendered with display: none" do
      # Belt-and-suspenders: even before the JS hook mounts, the 25th
      # card onwards must be hidden so users don't see a flash of the
      # full 30-card grid before JS catches up.
      cast = build_cast(30)
      html = render_panel(%{entity: tv_entity(%{cast: cast})})

      assert html =~ ~s(style="display: none")
    end
  end

  defp build_cast(count) do
    Enum.map(0..(count - 1), fn i ->
      %Person{
        name: "Sample Cast Member #{i + 1}",
        character: "Sample Role #{i + 1}",
        tmdb_person_id: 5000 + i,
        profile_path: nil,
        order: i
      }
    end)
  end
end
