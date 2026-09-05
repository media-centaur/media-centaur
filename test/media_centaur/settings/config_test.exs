defmodule MediaCentaur.Settings.ConfigTest do
  @moduledoc """
  Tests for Config: image_resolution/0, update-check keys, config_path/0
  and media_dirs parsing (plain strings, inline tables, legacy media_dir).
  """
  use ExUnit.Case, async: false

  alias MediaCentaur.Settings.Config

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    %{original_config: original}
  end

  # ---------------------------------------------------------------------------
  # image_resolution/0
  # ---------------------------------------------------------------------------

  describe "image_resolution/0" do
    test "defaults to 4k when unset" do
      :persistent_term.put({Config, :config}, %{})
      assert Config.image_resolution() == "4k"
    end

    test "returns the stored value when valid" do
      :persistent_term.put({Config, :config}, %{image_resolution: "1080p"})
      assert Config.image_resolution() == "1080p"
    end

    test "falls back to the default for an unrecognised stored value" do
      :persistent_term.put({Config, :config}, %{image_resolution: "8k"})
      assert Config.image_resolution() == "4k"
    end

    test "the process override wins (async-test seam)" do
      :persistent_term.put({Config, :config}, %{image_resolution: "4k"})
      Process.put(:image_resolution_override, "1080p")
      assert Config.image_resolution() == "1080p"
    after
      Process.delete(:image_resolution_override)
    end
  end

  # ---------------------------------------------------------------------------
  # Update checking / auto-update keys
  # ---------------------------------------------------------------------------

  describe "update-check / auto-update config" do
    test "the three keys are runtime-settable" do
      keys = Config.runtime_settable_keys()
      assert :update_check_enabled in keys
      assert :update_check_interval_minutes in keys
      assert :auto_update_enabled in keys
    end

    test "ships with current behaviour preserved as defaults" do
      assert Config.get(:update_check_enabled) == true
      assert Config.get(:auto_update_enabled) == false
      assert Config.get(:update_check_interval_minutes) == 360
    end

    test "update_check_interval_minutes/0 clamps to the 15-minute floor" do
      put_config(:update_check_interval_minutes, 5)
      assert Config.update_check_interval_minutes() == 15

      put_config(:update_check_interval_minutes, 15)
      assert Config.update_check_interval_minutes() == 15

      put_config(:update_check_interval_minutes, 600)
      assert Config.update_check_interval_minutes() == 600
    end

    test "update_check_interval_minutes/0 falls back to the default when unset" do
      put_config(:update_check_interval_minutes, nil)
      assert Config.update_check_interval_minutes() == 360
    end

    test "update_check_interval_floor_minutes/0 exposes the floor" do
      assert Config.update_check_interval_floor_minutes() == 15
    end
  end

  defp put_config(key, value) do
    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, key, value))
  end

  # ---------------------------------------------------------------------------
  # Config path resolution
  # ---------------------------------------------------------------------------

  describe "config_path/0" do
    setup do
      original = System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")

      on_exit(fn ->
        case original do
          nil -> System.delete_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")
          value -> System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", value)
        end
      end)

      :ok
    end

    test "returns compile-time default when MEDIA_CENTAUR_CONFIG_OVERRIDE is unset" do
      System.delete_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")
      # config/test.exs sets :default_config_path — proves per-env
      # routing works. In dev builds that same key points at the dev
      # TOML so `iex -S mix phx.server` never accidentally binds the
      # prod port.
      assert Config.config_path() ==
               Path.expand("~/.config/media-centaur/media-centaur-test.toml")
    end

    test "returns override path when set" do
      System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", "/tmp/custom-config.toml")
      assert Config.config_path() == "/tmp/custom-config.toml"
    end

    test "treats empty string as unset" do
      System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", "")

      assert Config.config_path() ==
               Path.expand("~/.config/media-centaur/media-centaur-test.toml")
    end
  end

  # ---------------------------------------------------------------------------
  # TOML parsing: media_dirs formats
  # ---------------------------------------------------------------------------

  describe "TOML parsing" do
    # Loads a real TOML through `Config.load!/0` by pointing the override
    # env var at it — the same path a `MEDIA_CENTAUR_CONFIG_OVERRIDE`
    # instance takes — with the test env's `:skip_user_config` lifted for
    # the duration.
    setup do
      toml_dir = Path.join(System.tmp_dir!(), "config_test_#{Ecto.UUID.generate()}")
      File.mkdir_p!(toml_dir)
      toml_path = Path.join(toml_dir, "media-centaur.toml")

      original_override = System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")
      original_skip = Application.get_env(:media_centaur, :skip_user_config)
      original_raw = Application.get_env(:media_centaur, :__raw_toml_media_dirs)

      System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", toml_path)
      Application.put_env(:media_centaur, :skip_user_config, false)

      on_exit(fn ->
        File.rm_rf!(toml_dir)

        case original_override do
          nil -> System.delete_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")
          value -> System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", value)
        end

        Application.put_env(:media_centaur, :skip_user_config, original_skip)
        Application.put_env(:media_centaur, :__raw_toml_media_dirs, original_raw)
      end)

      %{toml_path: toml_path}
    end

    test "plain string media_dirs", %{toml_path: toml_path} do
      File.write!(toml_path, ~s(media_dirs = ["/mnt/movies", "/mnt/tv"]\n))
      :ok = Config.load!()

      assert Config.get(:media_dirs) == ["/mnt/movies", "/mnt/tv"]
      # Only explicit `images_dir` overrides are stored; the default layout
      # is `Library.ImageCache`'s.
      assert Config.get(:media_dir_images) == %{}
    end

    test "inline table with images_dir", %{toml_path: toml_path} do
      toml = """
      [[media_dirs]]
      dir = "/mnt/movies"
      images_dir = "/mnt/cache/movie-images"

      [[media_dirs]]
      dir = "/mnt/tv"
      """

      File.write!(toml_path, toml)
      :ok = Config.load!()

      assert Config.get(:media_dirs) == ["/mnt/movies", "/mnt/tv"]
      assert Config.get(:media_dir_images) == %{"/mnt/movies" => "/mnt/cache/movie-images"}
    end
  end
end
