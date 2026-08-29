defmodule MediaCentaur.Apps.ArtworkTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Apps.Artwork
  alias MediaCentaur.Settings.Config

  setup do
    data_dir = Path.join(System.tmp_dir!(), "mc-apps-art-#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)

    original = :persistent_term.get({Config, :config}, %{})
    :persistent_term.put({Config, :config}, Map.put(original, :data_dir, data_dir))

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
      File.rm_rf!(data_dir)
    end)

    %{data_dir: data_dir}
  end

  test "urls/1 resolves only roles that exist on disk", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    dir = Path.join([data_dir, "images", "apps", app_id])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "banner.jpg"), "jpg")

    assert %{banner_url: "/media-images/images/apps/" <> _rest, poster_url: nil} =
             Artwork.urls(app_id)
  end

  test "urls/1 is all-nil for an app with no art" do
    assert %{banner_url: nil, poster_url: nil} = Artwork.urls(Ecto.UUID.generate())
  end

  # Overwriting a master in place (refresh_steam_artwork) must change the
  # URL, or morphdom keeps the old src and the browser never refetches.
  test "urls/1 versions each URL by the master's mtime", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    dir = Path.join([data_dir, "images", "apps", app_id])
    File.mkdir_p!(dir)
    banner = Path.join(dir, "banner.jpg")
    File.write!(banner, "jpg")

    assert %{banner_url: url} = Artwork.urls(app_id)
    assert url =~ ~r/\?v=\d+$/

    File.touch!(banner, {{2020, 1, 1}, {0, 0, 0}})
    assert %{banner_url: aged_url} = Artwork.urls(app_id)
    assert aged_url != url
  end

  test "store_file/3 copies a source file into the cache", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    source = Path.join(data_dir, "source.jpg")
    File.write!(source, "jpg-bytes")

    assert :ok = Artwork.store_file(:banner, app_id, source)

    assert File.read!(Path.join([data_dir, "images", "apps", app_id, "banner.jpg"])) ==
             "jpg-bytes"
  end

  test "delete/1 removes the app's art directory", %{data_dir: data_dir} do
    app_id = Ecto.UUID.generate()
    dir = Path.join([data_dir, "images", "apps", app_id])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "banner.jpg"), "jpg")

    assert :ok = Artwork.delete(app_id)
    refute File.dir?(dir)
  end

  test "delete/1 is a no-op for an app with no art" do
    assert :ok = Artwork.delete(Ecto.UUID.generate())
  end
end
