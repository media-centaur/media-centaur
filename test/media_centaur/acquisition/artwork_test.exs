defmodule MediaCentaur.Acquisition.ArtworkTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Artwork

  # Artwork resolves from the TmdbArtwork cache on disk — point data_dir
  # at a per-test tmp dir (GlobalStateSandbox restores the config term).
  setup do
    dir = Path.join(System.tmp_dir!(), "acq_artwork_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :data_dir, dir))

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, data_dir: dir}
  end

  defp seed_entry(data_dir, type, id, roles) do
    dir = Path.join([data_dir, "images", "tmdb", "#{type}-#{id}"])
    File.mkdir_p!(dir)

    Enum.each(roles, fn role ->
      filename = if role == :logo, do: "logo.png", else: "#{role}.jpg"
      File.write!(Path.join(dir, filename), :binary.copy("x", 60_000))
    end)

    dir
  end

  describe "resolve/2 — local-first, never a hot-link" do
    test "cached files win", %{data_dir: data_dir} do
      seed_entry(data_dir, :tv_series, 246_810, [:backdrop, :logo])

      assert Artwork.resolve(246_810, "tv") == %{
               backdrop_url: "/media-images/images/tmdb/tv_series-246810/backdrop.jpg",
               logo_url: "/media-images/images/tmdb/tv_series-246810/logo.png"
             }
    end

    test "string ids and tmdb_type spellings normalize", %{data_dir: data_dir} do
      seed_entry(data_dir, :movie, 777, [:backdrop])

      assert %{backdrop_url: "/media-images/images/tmdb/movie-777/backdrop.jpg"} =
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
