defmodule MediaCentaur.ErrorReports.ShutdownMonitorTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.ShutdownMarker
  alias MediaCentaur.ErrorReports.ShutdownMonitor
  alias MediaCentaur.ErrorReports.Store

  describe "ShutdownMarker" do
    @tag :tmp_dir
    test "check_and_arm reports clean the first time, unclean while still armed", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "marker")

      assert ShutdownMarker.check_and_arm(path) == :clean
      assert ShutdownMarker.armed?(path)
      # Still armed (a crash never disarmed it) → next boot sees unclean.
      assert ShutdownMarker.check_and_arm(path) == :unclean
    end

    @tag :tmp_dir
    test "disarm clears the marker", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "marker")
      ShutdownMarker.arm(path)
      assert ShutdownMarker.armed?(path)

      ShutdownMarker.disarm(path)
      refute ShutdownMarker.armed?(path)
    end
  end

  describe "ShutdownMonitor" do
    @tag :tmp_dir
    test "raises an unclean_shutdown incident when the marker was already armed", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "marker")
      ShutdownMarker.arm(path)

      start_supervised!({ShutdownMonitor, name: :sm_unclean, path: path})

      assert %{severity: :warning, status: :open} =
               Store.get_open_subsystem_incident(:system, :unclean_shutdown)
    end

    @tag :tmp_dir
    test "raises nothing on a clean first boot and disarms on graceful stop", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "marker")

      start_supervised!({ShutdownMonitor, name: :sm_clean, path: path})

      assert Store.get_open_subsystem_incident(:system, :unclean_shutdown) == nil
      assert ShutdownMarker.armed?(path)

      stop_supervised!(ShutdownMonitor)
      refute ShutdownMarker.armed?(path)
    end
  end
end
