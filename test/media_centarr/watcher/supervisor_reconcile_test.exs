defmodule MediaCentarr.Watcher.SupervisorReconcileTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Config
  alias MediaCentarr.Watcher.Supervisor, as: WatcherSup

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :ok = Config.put_watch_dirs([])
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  alias MediaCentarr.Watcher.ConfigListener

  test "name-only change keeps the same watcher pid (no stop/start)" do
    tmp = Path.join(System.tmp_dir!(), "watcher-name-only-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "u1", "dir" => tmp, "images_dir" => nil, "name" => nil}
      ])

    ConfigListener.__sync_for_test__()
    [{pid1, _}] = Registry.lookup(MediaCentarr.Watcher.Registry, tmp)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "u1", "dir" => tmp, "images_dir" => nil, "name" => "Movies"}
      ])

    ConfigListener.__sync_for_test__()
    [{pid2, _}] = Registry.lookup(MediaCentarr.Watcher.Registry, tmp)

    assert pid1 == pid2, "name-only change should not restart the watcher"
  end

  test "put_watch_dirs triggers reconcile that starts and stops watchers" do
    tmp = Path.join(System.tmp_dir!(), "watcher-reconcile-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "t1", "dir" => tmp, "images_dir" => nil, "name" => nil}
      ])

    ConfigListener.__sync_for_test__()

    dirs = Enum.map(WatcherSup.statuses(), & &1.dir)
    assert tmp in dirs

    :ok = Config.put_watch_dirs([])
    ConfigListener.__sync_for_test__()

    refute tmp in Enum.map(WatcherSup.statuses(), & &1.dir)
  end
end
