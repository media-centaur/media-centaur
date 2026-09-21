defmodule MediaCentaur.Settings.ConfigTomlBootstrapTest do
  @moduledoc """
  TOML only carries bootstrap state (`database_path`, `port`, `media_dirs`).
  Runtime preferences live exclusively in the Settings database — a value
  for a runtime key in the TOML must be ignored, never read into
  `:persistent_term` and never imported into Settings.

  These tests exercise the real `Config.load!/0` path (the existing
  `ConfigTest` "TOML parsing" cases reimplement `merge_toml` privately,
  so they can't catch a regression where the loader reads a runtime key).
  To do that we temporarily disable the test-env `:skip_user_config`
  short-circuit and point `MEDIA_CENTAUR_CONFIG_OVERRIDE` at a temp file.
  """
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Settings.Config

  setup do
    original_override = System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")

    toml_dir = Path.join(System.tmp_dir!(), "config_bootstrap_#{Ecto.UUID.generate()}")
    File.mkdir_p!(toml_dir)
    toml_path = Path.join(toml_dir, "media-centaur.toml")

    Application.put_env(:media_centaur, :skip_user_config, false)
    System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", toml_path)

    on_exit(fn ->
      case original_override do
        nil -> System.delete_env("MEDIA_CENTAUR_CONFIG_OVERRIDE")
        value -> System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", value)
      end

      File.rm_rf!(toml_dir)
    end)

    %{toml_path: toml_path}
  end

  describe "Config.load!/0 with a TOML carrying both bootstrap and runtime keys" do
    setup %{toml_path: toml_path} do
      # A TOML in the old, fully-populated format: bootstrap keys mixed
      # with runtime keys under their legacy nested tables.
      File.write!(toml_path, """
      port = 9999
      database_path = "/tmp/bootstrap-test/library.db"
      file_absence_ttl_days = 99

      media_dirs = ["/mnt/bootstrap-movies"]

      [pipeline]
      skip_dirs = ["IgnoreMe"]
      auto_approve_threshold = 0.99

      [playback]
      socket_timeout_ms = 12345

      [status]
      recent_changes_days = 77
      """)

      :ok = Config.load!()
      :ok
    end

    test "loads bootstrap keys from the TOML" do
      assert Config.get(:port) == 9999
      assert Config.get(:database_path) == "/tmp/bootstrap-test/library.db"
      assert Config.get(:media_dirs) == ["/mnt/bootstrap-movies"]
    end

    test "ignores runtime keys present in the TOML, keeping defaults" do
      # The claim is that the TOML's value lost, not what the default
      # happens to contain — pinning the default's folder names here made
      # this test fail on a change to the shipped list, which is content
      # rather than behaviour.
      refute "IgnoreMe" in Config.get(:skip_dirs)
      assert Config.get(:recent_changes_days) == 3
      assert Config.get(:file_absence_ttl_days) == 30
      assert Config.get(:mpv_socket_timeout_ms) == 5000
    end

    test "does not snapshot runtime keys for migration into Settings" do
      assert Application.get_env(:media_centaur, :__raw_toml_runtime_keys) == nil
    end
  end

  describe "showcase_mode" do
    # Showcase mode is not a preference — it is a property of *which
    # instance this is*, decided by MEDIA_CENTAUR_CONFIG_OVERRIDE before
    # the VM starts. The supervision tree reads it to decide whether to
    # start the demo's generators at all, which happens long before the
    # Settings database is reachable, so it is bootstrap state.
    test "reads from the TOML", %{toml_path: toml_path} do
      File.write!(toml_path, """
      showcase_mode = true
      """)

      :ok = Config.load!()

      assert Config.get(:showcase_mode) == true
    end

    test "defaults to false when the TOML is silent", %{toml_path: toml_path} do
      File.write!(toml_path, """
      port = 9999
      """)

      :ok = Config.load!()

      assert Config.get(:showcase_mode) == false
    end

    test "is not runtime-settable — no Settings UI may turn an install into a demo" do
      refute :showcase_mode in Config.runtime_settable_keys()
    end
  end

  describe "Config.load!/0 with the retired `watch_dirs` TOML key" do
    # The key was renamed to `media_dirs` in 2026-06. A file still using the
    # old spelling must fail loudly with the fix named, never boot with no
    # media directories.
    test "raises naming the rename", %{toml_path: toml_path} do
      File.write!(toml_path, """
      watch_dirs = ["/mnt/legacy-movies"]
      """)

      assert_raise ArgumentError, ~r/`watch_dirs`; rename it to `media_dirs`/, fn ->
        Config.load!()
      end
    end
  end
end
