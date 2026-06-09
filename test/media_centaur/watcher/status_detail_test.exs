defmodule MediaCentaur.Watcher.StatusDetailTest do
  # async: false — starts real Watcher GenServers that register in the
  # application-wide Watcher.Registry. A unique non-existent dir per test keeps
  # registrations from colliding.
  use ExUnit.Case, async: false

  alias MediaCentaur.Watcher

  defp start_watcher_on_missing_dir do
    dir = "/nonexistent/media_centaur_status_detail_#{:erlang.unique_integer([:positive])}"
    pid = start_supervised!({Watcher, dir})
    %{pid: pid, dir: dir}
  end

  describe "status_detail/1 for an unreachable directory" do
    test "reports :unavailable with a concrete failure reason" do
      %{pid: pid} = start_watcher_on_missing_dir()

      detail = Watcher.status_detail(pid)

      assert detail.state == :unavailable
      # The exact reason depends on the FileSystem backend's behaviour for a
      # missing path; what matters is that a concrete cause is carried through
      # rather than a bare nil — that is the user-facing observability win.
      assert detail.reason in [:never_mounted, :backend_error, :inotify_missing]
    end

    test "carries zeroed in-flight counters when nothing is settling or pending" do
      %{pid: pid} = start_watcher_on_missing_dir()

      detail = Watcher.status_detail(pid)

      assert detail.settling_count == 0
      assert detail.pending_deletions == 0
    end
  end
end
