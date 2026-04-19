defmodule MediaCentarr.ConfigWatchDirsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Settings

  describe "watch_dirs_entries/0" do
    test "returns [] when the settings entry is absent" do
      assert Config.watch_dirs_entries() == []
    end

    test "returns the entries from the settings row" do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: "config:watch_dirs",
          value: %{
            "entries" => [
              %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => nil, "name" => nil}
            ]
          }
        })

      assert [%{"id" => "aaa", "dir" => "/mnt/a"}] = Config.watch_dirs_entries()
    end
  end

  describe "put_watch_dirs/1" do
    setup do
      original = :persistent_term.get({Config, :config})
      on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
      :ok
    end

    test "persists, updates :persistent_term, and broadcasts" do
      :ok = Config.subscribe()

      entries = [
        %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => nil, "name" => nil}
      ]

      assert :ok = Config.put_watch_dirs(entries)

      assert Config.get(:watch_dirs) == ["/mnt/a"]
      assert Config.get(:watch_dir_images) == %{"/mnt/a" => Path.join("/mnt/a", ".media-centarr/images")}

      assert_receive {:config_updated, :watch_dirs, ^entries}
    end

    test "honours explicit images_dir override" do
      entries = [
        %{"id" => "aaa", "dir" => "/mnt/a", "images_dir" => "/mnt/ssd/images", "name" => "Movies"}
      ]

      :ok = Config.put_watch_dirs(entries)

      assert Config.get(:watch_dir_images) == %{"/mnt/a" => "/mnt/ssd/images"}
    end
  end
end
