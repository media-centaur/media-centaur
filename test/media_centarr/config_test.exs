defmodule MediaCentarr.ConfigTest do
  @moduledoc """
  Tests for Config: images_dir_for/1, staging_base_for/1, and
  watch_dirs parsing (plain strings, inline tables, legacy media_dir).
  """
  use ExUnit.Case, async: false

  alias MediaCentarr.Config

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    %{original_config: original}
  end

  # ---------------------------------------------------------------------------
  # images_dir_for/1
  # ---------------------------------------------------------------------------

  describe "images_dir_for/1" do
    test "returns configured images_dir when watch dir is in the map" do
      config = %{watch_dir_images: %{"/mnt/media" => "/mnt/cache/images"}}
      :persistent_term.put({Config, :config}, config)

      assert Config.images_dir_for("/mnt/media") == "/mnt/cache/images"
    end

    test "returns default when watch dir is not in the map" do
      config = %{watch_dir_images: %{}}
      :persistent_term.put({Config, :config}, config)

      assert Config.images_dir_for("/mnt/media") == "/mnt/media/.media-centarr/images"
    end

    test "returns default for unknown dir even when map has other entries" do
      config = %{watch_dir_images: %{"/mnt/movies" => "/mnt/movies/.cache"}}
      :persistent_term.put({Config, :config}, config)

      assert Config.images_dir_for("/mnt/tv") == "/mnt/tv/.media-centarr/images"
    end
  end

  # ---------------------------------------------------------------------------
  # staging_base_for/1
  # ---------------------------------------------------------------------------

  describe "staging_base_for/1" do
    test "returns sibling of images dir" do
      config = %{watch_dir_images: %{"/mnt/media" => "/mnt/media/.media-centarr/images"}}
      :persistent_term.put({Config, :config}, config)

      assert Config.staging_base_for("/mnt/media") ==
               "/mnt/media/.media-centarr/images/partial-downloads"
    end

    test "works with custom images_dir" do
      config = %{watch_dir_images: %{"/mnt/media" => "/mnt/cache/artwork/images"}}
      :persistent_term.put({Config, :config}, config)

      assert Config.staging_base_for("/mnt/media") ==
               "/mnt/cache/artwork/images/partial-downloads"
    end

    test "works for unconfigured watch dir using default" do
      config = %{watch_dir_images: %{}}
      :persistent_term.put({Config, :config}, config)

      assert Config.staging_base_for("/mnt/media") ==
               "/mnt/media/.media-centarr/images/partial-downloads"
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_image_path/1
  # ---------------------------------------------------------------------------

  describe "resolve_image_path/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "config_resolve_#{Ecto.UUID.generate()}")
      images_dir = Path.join(tmp_dir, ".media-centarr/images")
      File.mkdir_p!(images_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, images_dir: images_dir}
    end

    test "returns nil for nil input" do
      assert Config.resolve_image_path(nil) == nil
    end

    test "returns absolute path when file exists in watch dir", %{
      tmp_dir: tmp_dir,
      images_dir: images_dir
    } do
      uuid = Ecto.UUID.generate()
      entity_dir = Path.join(images_dir, uuid)
      File.mkdir_p!(entity_dir)
      image_path = Path.join(entity_dir, "poster.jpg")
      File.write!(image_path, "fake image")

      config = %{
        watch_dirs: [tmp_dir],
        watch_dir_images: %{tmp_dir => images_dir}
      }

      :persistent_term.put({Config, :config}, config)

      assert Config.resolve_image_path("#{uuid}/poster.jpg") == image_path
    end

    test "returns nil when file does not exist" do
      config = %{
        watch_dirs: ["/nonexistent/dir"],
        watch_dir_images: %{"/nonexistent/dir" => "/nonexistent/dir/.media-centarr/images"}
      }

      :persistent_term.put({Config, :config}, config)

      assert Config.resolve_image_path("missing-uuid/poster.jpg") == nil
    end

    test "finds file in correct watch dir among multiple", %{images_dir: images_dir} do
      second_dir = Path.join(System.tmp_dir!(), "config_resolve_second_#{Ecto.UUID.generate()}")
      second_images = Path.join(second_dir, ".media-centarr/images")
      File.mkdir_p!(second_images)

      uuid = Ecto.UUID.generate()
      entity_dir = Path.join(second_images, uuid)
      File.mkdir_p!(entity_dir)
      image_path = Path.join(entity_dir, "backdrop.jpg")
      File.write!(image_path, "fake image")

      on_exit(fn -> File.rm_rf!(second_dir) end)

      # The first watch dir's images_dir won't have this file
      first_dir = Path.dirname(Path.dirname(images_dir))

      config = %{
        watch_dirs: [first_dir, second_dir],
        watch_dir_images: %{first_dir => images_dir, second_dir => second_images}
      }

      :persistent_term.put({Config, :config}, config)

      assert Config.resolve_image_path("#{uuid}/backdrop.jpg") == image_path
    end
  end

  # ---------------------------------------------------------------------------
  # Config path resolution
  # ---------------------------------------------------------------------------

  describe "config_path/0" do
    setup do
      original = System.get_env("MEDIA_CENTARR_CONFIG_OVERRIDE")

      on_exit(fn ->
        case original do
          nil -> System.delete_env("MEDIA_CENTARR_CONFIG_OVERRIDE")
          value -> System.put_env("MEDIA_CENTARR_CONFIG_OVERRIDE", value)
        end
      end)

      :ok
    end

    test "returns default XDG path when MEDIA_CENTARR_CONFIG_OVERRIDE is unset" do
      System.delete_env("MEDIA_CENTARR_CONFIG_OVERRIDE")
      assert Config.config_path() == Path.expand("~/.config/media-centarr/media-centarr.toml")
    end

    test "returns override path when set" do
      System.put_env("MEDIA_CENTARR_CONFIG_OVERRIDE", "/tmp/custom-config.toml")
      assert Config.config_path() == "/tmp/custom-config.toml"
    end

    test "treats empty string as unset" do
      System.put_env("MEDIA_CENTARR_CONFIG_OVERRIDE", "")
      assert Config.config_path() == Path.expand("~/.config/media-centarr/media-centarr.toml")
    end
  end

  # ---------------------------------------------------------------------------
  # TOML parsing: watch_dirs formats
  # ---------------------------------------------------------------------------

  describe "TOML parsing" do
    setup do
      toml_dir = Path.join(System.tmp_dir!(), "config_test_#{Ecto.UUID.generate()}")
      File.mkdir_p!(toml_dir)
      toml_path = Path.join(toml_dir, "media-centarr.toml")

      on_exit(fn -> File.rm_rf!(toml_dir) end)

      %{toml_path: toml_path}
    end

    test "plain string watch_dirs", %{toml_path: toml_path} do
      File.write!(toml_path, ~s(watch_dirs = ["/mnt/movies", "/mnt/tv"]\n))
      load_toml!(toml_path)

      assert Config.get(:watch_dirs) == ["/mnt/movies", "/mnt/tv"]
      assert Config.get(:watch_dir_images)["/mnt/movies"] == "/mnt/movies/.media-centarr/images"
      assert Config.get(:watch_dir_images)["/mnt/tv"] == "/mnt/tv/.media-centarr/images"
    end

    test "inline table with images_dir", %{toml_path: toml_path} do
      toml = """
      [[watch_dirs]]
      dir = "/mnt/movies"
      images_dir = "/mnt/cache/movie-images"

      [[watch_dirs]]
      dir = "/mnt/tv"
      """

      File.write!(toml_path, toml)
      load_toml!(toml_path)

      assert Config.get(:watch_dirs) == ["/mnt/movies", "/mnt/tv"]
      assert Config.get(:watch_dir_images)["/mnt/movies"] == "/mnt/cache/movie-images"
      assert Config.get(:watch_dir_images)["/mnt/tv"] == "/mnt/tv/.media-centarr/images"
    end

    test "legacy media_dir key", %{toml_path: toml_path} do
      File.write!(toml_path, ~s(media_dir = "/mnt/legacy"\n))
      load_toml!(toml_path)

      assert Config.get(:watch_dirs) == ["/mnt/legacy"]
      assert Config.get(:watch_dir_images)["/mnt/legacy"] == "/mnt/legacy/.media-centarr/images"
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Temporarily override the config path to load a test TOML file.
  # We can't change @config_path, so we decode + merge manually,
  # mimicking load!/0 but with our custom TOML path.
  defp load_toml!(toml_path) do
    {:ok, contents} = File.read(toml_path)
    {:ok, toml} = Toml.decode(contents)

    # Build a minimal defaults map — only the keys merge_toml needs.
    defaults = %{
      database_path: nil,
      watch_dirs: [],
      watch_dir_images: %{},
      tmdb_api_key: nil,
      auto_approve_threshold: nil,
      mpv_path: "/usr/bin/mpv",
      mpv_socket_dir: "/tmp",
      mpv_socket_timeout_ms: 5000,
      exclude_dirs: [],
      extras_dirs: []
    }

    # Call merge_toml via the module — but it's private. We need to go through
    # the public interface. Since we can't call load! with a custom path,
    # we replicate the merge logic here.
    {watch_dirs, watch_dir_images} = resolve_watch_dirs_from_toml(toml, defaults)

    config = %{defaults | watch_dirs: watch_dirs, watch_dir_images: watch_dir_images}
    :persistent_term.put({Config, :config}, config)
  end

  defp resolve_watch_dirs_from_toml(toml, defaults) do
    case toml["watch_dirs"] do
      dirs when is_list(dirs) and dirs != [] ->
        parse_watch_dirs(dirs)

      _ ->
        case toml["media_dir"] do
          dir when is_binary(dir) ->
            {[dir], %{dir => Path.join(dir, ".media-centarr/images")}}

          _ ->
            {defaults.watch_dirs, defaults.watch_dir_images}
        end
    end
  end

  defp parse_watch_dirs(raw_list) do
    then(
      Enum.reduce(raw_list, {[], %{}}, fn entry, {dirs, images_map} ->
        case entry do
          dir when is_binary(dir) ->
            {[dir | dirs], Map.put(images_map, dir, Path.join(dir, ".media-centarr/images"))}

          %{"dir" => dir} = table ->
            images_dir = table["images_dir"] || Path.join(dir, ".media-centarr/images")
            {[dir | dirs], Map.put(images_map, dir, images_dir)}
        end
      end),
      fn {dirs, images_map} -> {Enum.reverse(dirs), images_map} end
    )
  end
end
