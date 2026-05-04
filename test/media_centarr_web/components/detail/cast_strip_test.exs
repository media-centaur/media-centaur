defmodule MediaCentarrWeb.Components.Detail.CastStripTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.Detail.CastStrip

  defp render_strip(cast) do
    render_component(&CastStrip.cast_strip/1, cast: cast)
  end

  describe "cast_strip/1" do
    test "renders nothing when cast is empty" do
      assert render_strip([]) == ""
    end

    test "renders one card per cast member with name and character" do
      cast = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => 1,
          "profile_path" => "/a.jpg",
          "order" => 0
        },
        %{
          "name" => "Actor B",
          "character" => "Role B",
          "tmdb_person_id" => 2,
          "profile_path" => "/b.jpg",
          "order" => 1
        }
      ]

      html = render_strip(cast)

      assert html =~ "Actor A"
      assert html =~ "Role A"
      assert html =~ "Actor B"
      assert html =~ "Role B"
    end

    test "links each card to the TMDB person page in a new tab" do
      cast = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => 1234,
          "profile_path" => "/a.jpg",
          "order" => 0
        }
      ]

      html = render_strip(cast)

      assert html =~ ~s{href="https://www.themoviedb.org/person/1234"}
      assert html =~ ~s{target="_blank"}
      assert html =~ ~s{rel="noopener}
    end

    test "uses TMDB w185 image URL for the photo" do
      cast = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => 1,
          "profile_path" => "/abc.jpg",
          "order" => 0
        }
      ]

      assert render_strip(cast) =~ "https://image.tmdb.org/t/p/w185/abc.jpg"
    end

    test "renders silhouette fallback when profile_path is nil" do
      cast = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      html = render_strip(cast)

      refute html =~ "image.tmdb.org"
      assert html =~ "hero-user"
    end

    test "renders cards with no tmdb_person_id as non-interactive" do
      cast = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => nil,
          "profile_path" => "/a.jpg",
          "order" => 0
        }
      ]

      html = render_strip(cast)

      refute html =~ "themoviedb.org/person"
      assert html =~ "Actor A"
    end
  end
end
