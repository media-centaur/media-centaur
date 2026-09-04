defmodule MediaCentaur.TmdbArtworkTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TmdbArtwork

  # The cache lives under `{data_dir}/images/tmdb/` — point data_dir at a
  # per-test tmp dir (GlobalStateSandbox restores the config term).
  setup do
    dir = Path.join(System.tmp_dir!(), "tmdb_artwork_test_#{System.unique_integer([:positive])}")
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

  defp age_dir(dir, days) do
    File.touch!(dir, System.os_time(:second) - days * 86_400)
  end

  describe "paths" do
    test "relative_path/3 is the media-type-keyed layout" do
      assert TmdbArtwork.relative_path(:backdrop, :movie, 550) == "images/tmdb/movie-550/backdrop.jpg"

      assert TmdbArtwork.relative_path(:poster, :tv_series, 1399) ==
               "images/tmdb/tv_series-1399/poster.jpg"

      assert TmdbArtwork.relative_path(:logo, :movie, 550) == "images/tmdb/movie-550/logo.png"
    end

    test "movie and TV ids are distinct cache entries — TMDB id spaces collide" do
      refute TmdbArtwork.relative_path(:backdrop, :movie, 550) ==
               TmdbArtwork.relative_path(:backdrop, :tv_series, 550)
    end

    test "on_disk_path/3 roots the relative path in data_dir", %{data_dir: data_dir} do
      assert TmdbArtwork.on_disk_path(:backdrop, :movie, 550) ==
               Path.join(data_dir, "images/tmdb/movie-550/backdrop.jpg")
    end
  end

  describe "urls/2" do
    test "returns web paths only for roles that exist on disk", %{data_dir: data_dir} do
      seed_entry(data_dir, :tv_series, 1399, [:backdrop, :logo])

      assert TmdbArtwork.urls(:tv_series, 1399) == %{
               poster_url: nil,
               backdrop_url: "/media-images/images/tmdb/tv_series-1399/backdrop.jpg",
               logo_url: "/media-images/images/tmdb/tv_series-1399/logo.png"
             }
    end

    test "unknown identity and malformed ids resolve to nils" do
      assert TmdbArtwork.urls(:movie, 999_999) ==
               %{poster_url: nil, backdrop_url: nil, logo_url: nil}

      assert TmdbArtwork.urls("movie", "not-a-tmdb-id") ==
               %{poster_url: nil, backdrop_url: nil, logo_url: nil}
    end

    test "string type and id spellings normalize", %{data_dir: data_dir} do
      seed_entry(data_dir, :tv_series, 246_810, [:backdrop])

      assert %{backdrop_url: "/media-images/images/tmdb/tv_series-246810/backdrop.jpg"} =
               TmdbArtwork.urls("tv", "246810")
    end
  end

  describe "download_poster/3" do
    test "a failed download is an error, not a nil success" do
      # The test image client answers every GET with an empty body, which
      # `ImageFiles.download_raw/2` rejects as too small.
      assert {:error, {:body_too_small, _url, 0}} =
               TmdbArtwork.download_poster(:movie, 550, "/sample-poster.jpg")
    end
  end

  describe "sweep/0 — TTL AND no hold" do
    test "keeps a fresh unreferenced entry", %{data_dir: data_dir} do
      seed_entry(data_dir, :movie, 100, [:backdrop])

      assert TmdbArtwork.sweep() == 0
      assert File.exists?(TmdbArtwork.on_disk_path(:backdrop, :movie, 100))
    end

    test "removes an aged unreferenced entry", %{data_dir: data_dir} do
      dir = seed_entry(data_dir, :movie, 100, [:backdrop])
      age_dir(dir, 8)

      assert TmdbArtwork.sweep() == 1
      refute File.exists?(dir)
    end

    test "keeps an aged entry held by a tracked item", %{data_dir: data_dir} do
      dir = seed_entry(data_dir, :tv_series, 246_810, [:backdrop])
      age_dir(dir, 30)
      create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series})

      assert TmdbArtwork.sweep() == 0
      assert File.exists?(dir)
    end

    test "a tracked item of the OTHER media type does not hold the entry", %{data_dir: data_dir} do
      dir = seed_entry(data_dir, :movie, 246_810, [:backdrop])
      age_dir(dir, 30)
      create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series})

      assert TmdbArtwork.sweep() == 1
      refute File.exists?(dir)
    end

    test "keeps an aged entry held by a non-terminal pursuit", %{data_dir: data_dir} do
      dir = seed_entry(data_dir, :movie, 603, [:backdrop])
      age_dir(dir, 30)
      create_pursuit(%{tmdb_id: "603", tmdb_type: "movie", state: "active"})

      assert TmdbArtwork.sweep() == 0
      assert File.exists?(dir)
    end

    test "a terminal pursuit does not hold the entry", %{data_dir: data_dir} do
      dir = seed_entry(data_dir, :movie, 604, [:backdrop])
      age_dir(dir, 30)
      create_pursuit(%{tmdb_id: "604", tmdb_type: "movie", state: "satisfied"})

      assert TmdbArtwork.sweep() == 1
      refute File.exists?(dir)
    end

    test "skips foreign directories it did not write", %{data_dir: data_dir} do
      stray = Path.join([data_dir, "images", "tmdb", "not-a-cache-entry"])
      File.mkdir_p!(stray)
      age_dir(stray, 30)

      assert TmdbArtwork.sweep() == 0
      assert File.exists?(stray)
    end

    test "no data_dir configured sweeps nothing" do
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :data_dir, nil))

      assert TmdbArtwork.sweep() == 0
    end
  end
end
