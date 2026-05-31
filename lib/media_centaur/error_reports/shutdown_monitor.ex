defmodule MediaCentaur.ErrorReports.ShutdownMonitor do
  @moduledoc """
  Arms the `ShutdownMarker` on boot and disarms it on graceful shutdown, so a
  crash that left no log line still surfaces.

  If the marker is found already armed at boot, the previous run died uncleanly
  (out-of-band BEAM death), and this raises a `:subsystem` incident
  (`{:system, :unclean_shutdown}`) — the one place that condition can be
  detected. Traps exits so `terminate/2` can disarm on an orderly stop.

  Not started under `:test` (it writes to the data dir and raises an incident on
  boot); the marker logic is unit-tested via `ShutdownMarker`, and the
  raise-on-unclean wiring via a `:path`-injected instance.
  """
  use GenServer

  alias MediaCentaur.Config
  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.ShutdownMarker

  @marker_filename ".diagnostics_unclean_shutdown"

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.get(opts, :path, default_path())

    if ShutdownMarker.check_and_arm(path) == :unclean do
      ErrorReports.raise_fault(:system, :unclean_shutdown, :warning,
        message:
          "Media Centaur did not shut down cleanly last time (it may have crashed or been force-quit)."
      )
    end

    {:ok, %{path: path}}
  end

  @impl true
  def terminate(_reason, %{path: path}) do
    ShutdownMarker.disarm(path)
    :ok
  end

  defp default_path do
    base = Config.get(:data_dir) || System.tmp_dir!()
    Path.join(base, @marker_filename)
  end
end
