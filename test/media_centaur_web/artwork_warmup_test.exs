defmodule MediaCentaurWeb.ArtworkWarmupTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.ArtworkWarmup

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
