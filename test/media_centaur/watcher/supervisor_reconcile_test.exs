defmodule MediaCentaur.Watcher.SupervisorReconcileTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Watcher.ConfigListener
  alias MediaCentaur.Watcher.Supervisor, as: WatcherSup

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :ok = Config.put_media_dirs([])
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  defp tmp_dir(label) do
    tmp = Path.join(System.tmp_dir!(), "watcher-#{label}-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    tmp
  end

  describe "while watchers are off" do
    # Nothing has called `start_watchers/0` (config/test.exs keeps the
    # service off at boot) — the state a user who toggled watchers off on
    # the Settings page is in.
    test "media-dir edits start nothing" do
      tmp = tmp_dir("off")

      :ok = Config.put_media_dirs([%{"id" => "off1", "dir" => tmp, "images_dir" => nil, "name" => nil}])
      ConfigListener.__sync_for_test__()

      refute WatcherSup.running?()
      assert Registry.lookup(MediaCentaur.Watcher.Registry, tmp) == []
    end
  end

  describe "while watchers are on" do
    setup do
      # No media dirs yet, so this starts no child — it turns watching on.
      WatcherSup.start_watchers()
      on_exit(fn -> WatcherSup.stop_watchers() end)
      :ok
    end

    test "name-only change keeps the same watcher pid (no stop/start)" do
      tmp = Path.join(System.tmp_dir!(), "watcher-name-only-test-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      :ok =
        Config.put_media_dirs([
          %{"id" => "u1", "dir" => tmp, "images_dir" => nil, "name" => nil}
        ])

      ConfigListener.__sync_for_test__()
      [{pid1, _}] = Registry.lookup(MediaCentaur.Watcher.Registry, tmp)

      :ok =
        Config.put_media_dirs([
          %{"id" => "u1", "dir" => tmp, "images_dir" => nil, "name" => "Movies"}
        ])

      ConfigListener.__sync_for_test__()
      [{pid2, _}] = Registry.lookup(MediaCentaur.Watcher.Registry, tmp)

      assert pid1 == pid2, "name-only change should not restart the watcher"
    end

    test "put_media_dirs triggers reconcile that starts and stops watchers" do
      tmp = Path.join(System.tmp_dir!(), "watcher-reconcile-test-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      :ok =
        Config.put_media_dirs([
          %{"id" => "t1", "dir" => tmp, "images_dir" => nil, "name" => nil}
        ])

      ConfigListener.__sync_for_test__()

      dirs = Enum.map(WatcherSup.statuses(), & &1.dir)
      assert tmp in dirs

      :ok = Config.put_media_dirs([])
      ConfigListener.__sync_for_test__()

      refute tmp in Enum.map(WatcherSup.statuses(), & &1.dir)
    end
  end
end
