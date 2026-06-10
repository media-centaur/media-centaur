defmodule MediaCentaur.Acquisition.ArtworkTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Artwork

  describe "resolve/2 — local-first, never a hot-link" do
    test "a tracked item's cached files win" do
      create_tracking_item(%{
        tmdb_id: 246_810,
        media_type: :tv_series,
        backdrop_path: "images/tracking/246810/backdrop.jpg",
        logo_path: "images/tracking/246810/logo.png"
      })

      assert Artwork.resolve(246_810, "tv") == %{
               backdrop_url: "/media-images/images/tracking/246810/backdrop.jpg",
               logo_url: "/media-images/images/tracking/246810/logo.png"
             }
    end

    test "string ids and tmdb_type spellings normalize" do
      create_tracking_item(%{
        tmdb_id: 777,
        media_type: :movie,
        backdrop_path: "images/tracking/777/backdrop.jpg"
      })

      assert %{backdrop_url: "/media-images/images/tracking/777/backdrop.jpg"} =
               Artwork.resolve("777", :movie)
    end

    test "unknown identity and malformed ids resolve to nils" do
      assert Artwork.resolve(999_999, "movie") == %{backdrop_url: nil, logo_url: nil}
      assert Artwork.resolve("not-a-tmdb-id", "tv") == %{backdrop_url: nil, logo_url: nil}
      assert Artwork.resolve(nil, "tv") == %{backdrop_url: nil, logo_url: nil}
    end
  end

  describe "ensure/2" do
    test "degrades to nils when the TMDB fetch fails — callers keep the synthetic fallback" do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      MediaCentaur.TmdbStubs.stub_tmdb_error("/tv/555", 500)

      assert Artwork.ensure(555, "tv") == %{backdrop_url: nil, logo_url: nil}
    end
  end
end
