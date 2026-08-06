defmodule MediaCentaurWeb.ArtworkWarmupTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.ArtworkWarmup
  alias MediaCentaurWeb.HomeLive.Logic, as: HomeLogic

  describe "urls/0" do
    test "returns the library grid's poster derivatives, byte-identical to what the grid requests" do
      movie = create_movie(%{name: "Warmup Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      create_image(%{movie_id: movie.id, role: "poster", content_url: "#{movie.id}/poster.jpg"})

      urls = ArtworkWarmup.urls()

      # Must match the grid's `sized_image_url(poster_url, 640)` exactly —
      # any difference is a cache miss and the warmup is dead weight.
      assert "/media-images/#{movie.id}/poster.jpg?w=640" in urls
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

      poster_urls = Enum.filter(ArtworkWarmup.urls(), &String.contains?(&1, "?w=640"))

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
    # only what is about to be drawn. Three pages show an ambient backdrop
    # (home, library, incoming) and each picks one candidate on a rotation —
    # warming the whole eligible pool would prefetch dozens of images no page
    # will request before the rotation moves on.
    test "warms only the backdrops the hero pages are currently showing" do
      for index <- 1..10, do: seed_hero_candidate("Warmup Backdrop #{index}")

      backdrop_urls =
        Enum.filter(ArtworkWarmup.urls(), &String.contains?(&1, "/backdrop.jpg"))

      assert length(backdrop_urls) == HomeLogic.hero_pages()
    end

    test "the warmed backdrops are exactly the current picks for each hero page" do
      for index <- 1..10, do: seed_hero_candidate("Warmup Pick #{index}")

      candidates = MediaCentaur.Library.Views.hero_candidates()

      expected =
        0..(HomeLogic.hero_pages() - 1)
        |> Enum.map(&HomeLogic.select_page_hero(candidates, &1).backdrop_url)
        |> Enum.uniq()

      urls = ArtworkWarmup.urls()

      for url <- expected, do: assert(url in urls)
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
      assert html =~ "#{movie.id}/poster.jpg?w=640"
    end
  end
end
