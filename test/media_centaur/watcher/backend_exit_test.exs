defmodule MediaCentaur.Watcher.BackendExitTest do
  # async: false — a real Watcher registers in the application-wide registry,
  # and its state broadcasts reach processes (AbsenceSweeper) that write to
  # the database, so the sandbox must be shared.
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.Eventually

  alias MediaCentaur.Watcher

  test "a dying inotify backend makes the watcher unavailable, and the health check re-watches" do
    dir = Path.join(System.tmp_dir!(), "watcher_backend_exit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    pid = start_supervised!({Watcher, dir})
    assert eventually(fn -> Watcher.status(pid) == :watching end)

    Watcher.__stop_backend_for_test__(pid)

    assert eventually(fn -> Watcher.status_detail(pid).reason == :backend_exit end)
    assert Watcher.status(pid) == :unavailable

    # The fast health check (2 s) finds the directory accessible and re-runs
    # the backend start.
    assert eventually(fn -> Watcher.status(pid) == :watching end, timeout: 6_000)
  end
end
