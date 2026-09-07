defmodule MediaCentaurWeb.ArtworkWarmupTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.ArtworkWarmup
  alias MediaCentaurWeb.LiveHelpers
  alias MediaCentaurWeb.HomeLive.Logic, as: HomeLogic

  describe "urls/0" do
    test "returns the library grid's poster derivatives, byte-identical to what the grid requests" do
      movie = create_movie(%{name: "Warmup Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      create_image(%{movie_id: movie.id, role: "poster", content_url: "#{movie.id}/poster.jpg"})

      urls = ArtworkWarmup.urls()

      # Must match what the grid renders exactly — any difference is a cache
      # miss and the warmup is dead weight. Both sides call `poster_src/1`,
      # so this asserts the shared function is actually the one in use rather
      # than re-stating a width the test would have to keep in sync too.
      assert LiveHelpers.poster_src("/media-images/#{movie.id}/poster.jpg") in urls
    end

    test "skips entities without artwork and never returns nil or duplicates" do
      movie = create_movie(%{name: "Posterless Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      urls = ArtworkWarmup.urls()

      refute Enum.any?(urls, &is_nil/1)
      assert urls == Enum.uniq(urls)
    end

    test "caps the poster list at the first screen" do
      for n <- 1..35 do
        movie = create_movie(%{name: "Warmup Cap Movie #{n}"})
        create_linked_file(%{movie_id: movie.id})
        create_image(%{movie_id: movie.id, role: "poster", content_url: "#{movie.id}/poster.jpg"})
      end

      poster_marker =
        LiveHelpers.poster_src("/media-images/x/poster.jpg") |> String.split("?") |> List.last()

      poster_urls = Enum.filter(ArtworkWarmup.urls(), &String.contains?(&1, poster_marker))

      assert length(poster_urls) == 30
    end
  end

  describe "backdrop warmup" do
    defp seed_hero_candidate(name) do
      movie = create_movie(%{name: name, description: "A synopsis for #{name}"})
      create_linked_file(%{movie_id: movie.id})

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg"
      })

      movie
    end

    # `urls/0` runs in the root layout on every page render, so it must warm
    # only what is about to be drawn. Home's hero is the app's one backdrop
    # surface and it picks one candidate on a rotation — warming the whole
    # eligible pool would prefetch dozens of images nothing will request
    # before the rotation moves on.
    test "warms only the backdrop Home's hero is currently showing" do
      for index <- 1..10, do: seed_hero_candidate("Warmup Backdrop #{index}")

      backdrop_urls =
        Enum.filter(ArtworkWarmup.urls(), &String.contains?(&1, "/backdrop.jpg"))

      assert length(backdrop_urls) == 1
    end

    # The HeroBackdrop hook keys its decoded-bitmap cache by URL, and app.js
    # pre-decodes the hint at idle. Both sides must go through
    # `hero_backdrop_src/1` — a hint that differs by a byte warms nothing.
    test "hero_backdrop_url/0 is exactly what Home's canvas asks the hook for" do
      for index <- 1..10, do: seed_hero_candidate("Warmup Canvas #{index}")

      expected =
        MediaCentaur.Library.Views.hero_candidates()
        |> HomeLogic.select_hero()
        |> Map.fetch!(:backdrop_url)
        |> LiveHelpers.hero_backdrop_src()

      assert ArtworkWarmup.hero_backdrop_url() == expected
      assert expected in ArtworkWarmup.urls()
    end

    test "does not fail when no candidate qualifies" do
      movie = create_movie(%{name: "Backdropless Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      refute Enum.any?(ArtworkWarmup.urls(), &String.contains?(&1, "/backdrop.jpg"))
    end
  end

  describe "root layout prefetch hints" do
    test "the initial page load ships prefetch links for first-screen artwork", %{conn: conn} do
      movie = create_movie(%{name: "Warmup Prefetch Movie"})
      create_linked_file(%{movie_id: movie.id})
      create_image(%{movie_id: movie.id, role: "poster", content_url: "#{movie.id}/poster.jpg"})

      html = conn |> get("/history") |> html_response(200)

      assert html =~ ~s(rel="prefetch")
      assert html =~ LiveHelpers.poster_src("/media-images/#{movie.id}/poster.jpg")
    end

    test "marks the hero backdrop hints so app.js can pre-decode them at idle", %{conn: conn} do
      for index <- 1..3, do: seed_hero_candidate("Warmup Marker #{index}")

      html = conn |> get("/history") |> html_response(200)

      marked =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s|link[rel="prefetch"][data-hero-backdrop]|)
        |> LazyHTML.attribute("href")

      assert marked == [ArtworkWarmup.hero_backdrop_url()]
      assert marked != []
    end
  end
end
