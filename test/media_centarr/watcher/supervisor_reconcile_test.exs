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

  test "put_watch_dirs triggers reconcile that starts and stops watchers" do
    tmp = Path.join(System.tmp_dir!(), "watcher-reconcile-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "t1", "dir" => tmp, "images_dir" => nil, "name" => nil}
      ])

    # ConfigListener processes the broadcast asynchronously.
    Process.sleep(100)

    dirs = Enum.map(WatcherSup.statuses(), & &1.dir)
    assert tmp in dirs

    :ok = Config.put_watch_dirs([])
    Process.sleep(100)

    refute tmp in Enum.map(WatcherSup.statuses(), & &1.dir)
  end
end
