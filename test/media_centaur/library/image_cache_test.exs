defmodule MediaCentaur.Library.ImageCacheTest do
  # `async: false` — writes the shared Config persistent_term.
  use ExUnit.Case, async: false

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Settings.Config

  setup do
    original = :persistent_term.get({Config, :config})
    on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # dir_for/1
  # ---------------------------------------------------------------------------

  describe "dir_for/1" do
    test "returns configured images_dir when media dir is in the map" do
      config = %{media_dir_images: %{"/mnt/media" => "/mnt/cache/images"}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.dir_for("/mnt/media") == "/mnt/cache/images"
    end

    test "returns default when media dir is not in the map" do
      config = %{media_dir_images: %{}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.dir_for("/mnt/media") == "/mnt/media/.media-centaur/images"
    end

    test "returns default for unknown dir even when map has other entries" do
      config = %{media_dir_images: %{"/mnt/movies" => "/mnt/movies/.cache"}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.dir_for("/mnt/tv") == "/mnt/tv/.media-centaur/images"
    end
  end

  # ---------------------------------------------------------------------------
  # staging_dir_for/1
  # ---------------------------------------------------------------------------

  describe "staging_dir_for/1" do
    test "returns sibling of images dir" do
      config = %{media_dir_images: %{"/mnt/media" => "/mnt/media/.media-centaur/images"}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.staging_dir_for("/mnt/media") ==
               "/mnt/media/.media-centaur/images/partial-downloads"
    end

    test "works with custom images_dir" do
      config = %{media_dir_images: %{"/mnt/media" => "/mnt/cache/artwork/images"}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.staging_dir_for("/mnt/media") ==
               "/mnt/cache/artwork/images/partial-downloads"
    end

    test "works for unconfigured media dir using default" do
      config = %{media_dir_images: %{}}
      :persistent_term.put({Config, :config}, config)

      assert ImageCache.staging_dir_for("/mnt/media") ==
               "/mnt/media/.media-centaur/images/partial-downloads"
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_path/1
  # ---------------------------------------------------------------------------

  describe "resolve_path/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "image_cache_resolve_#{Ecto.UUID.generate()}")
      images_dir = Path.join(tmp_dir, ".media-centaur/images")
      File.mkdir_p!(images_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, images_dir: images_dir}
    end

    test "returns nil for nil input" do
      assert ImageCache.resolve_path(nil) == nil
    end

    test "returns absolute path when file exists in media dir", %{
      tmp_dir: tmp_dir,
      images_dir: images_dir
    } do
      uuid = Ecto.UUID.generate()
      entity_dir = Path.join(images_dir, uuid)
      File.mkdir_p!(entity_dir)
      image_path = Path.join(entity_dir, "poster.jpg")
      File.write!(image_path, "fake image")

      config = %{
        media_dirs: [tmp_dir],
        media_dir_images: %{tmp_dir => images_dir}
      }

      :persistent_term.put({Config, :config}, config)

      assert ImageCache.resolve_path("#{uuid}/poster.jpg") == image_path
    end

    test "returns nil when file does not exist" do
      config = %{
        media_dirs: ["/nonexistent/dir"],
        media_dir_images: %{"/nonexistent/dir" => "/nonexistent/dir/.media-centaur/images"}
      }

      :persistent_term.put({Config, :config}, config)

      assert ImageCache.resolve_path("missing-uuid/poster.jpg") == nil
    end

    test "finds file in correct media dir among multiple", %{images_dir: images_dir} do
      second_dir = Path.join(System.tmp_dir!(), "image_cache_resolve_second_#{Ecto.UUID.generate()}")
      second_images = Path.join(second_dir, ".media-centaur/images")
      File.mkdir_p!(second_images)

      uuid = Ecto.UUID.generate()
      entity_dir = Path.join(second_images, uuid)
      File.mkdir_p!(entity_dir)
      image_path = Path.join(entity_dir, "backdrop.jpg")
      File.write!(image_path, "fake image")

      on_exit(fn -> File.rm_rf!(second_dir) end)

      # The first media dir's images_dir won't have this file
      first_dir = Path.dirname(Path.dirname(images_dir))

      config = %{
        media_dirs: [first_dir, second_dir],
        media_dir_images: %{first_dir => images_dir, second_dir => second_images}
      }

      :persistent_term.put({Config, :config}, config)

      assert ImageCache.resolve_path("#{uuid}/backdrop.jpg") == image_path
    end
  end

  describe "dirs_outside_media_dir/0" do
    test "lists only the media dirs whose cache is not beneath them" do
      :persistent_term.put({Config, :config}, %{
        media_dirs: ["/mnt/movies", "/mnt/tv"],
        media_dir_images: %{"/mnt/tv" => "/mnt/cache/tv-images"}
      })

      assert ImageCache.dirs_outside_media_dir() == [{"/mnt/tv", "/mnt/cache/tv-images"}]
    end
  end
end
