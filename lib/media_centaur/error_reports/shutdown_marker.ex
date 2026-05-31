defmodule MediaCentaur.ErrorReports.ShutdownMarker do
  @moduledoc """
  A durable on-disk marker that detects an unclean shutdown (an out-of-band BEAM
  death — SIGKILL, OOM, power loss) where `terminate/2` never ran.

  The contract is simple: **arm on boot, disarm on graceful shutdown.** If the
  marker is still present on the next boot, the previous run died uncleanly —
  the only signal we get for a crash that left no log line. Pure filesystem
  functions, best-effort (a write/delete failure never raises), so the caller
  (`ShutdownMonitor`) stays trivial.
  """
  require Logger

  @doc """
  Records that a run is in progress and reports whether the previous run left
  the marker armed: `:unclean` if it did (crash), `:clean` otherwise. Always
  leaves the marker armed for this run.
  """
  @spec check_and_arm(Path.t()) :: :clean | :unclean
  def check_and_arm(path) do
    was_armed? = armed?(path)
    arm(path)
    if was_armed?, do: :unclean, else: :clean
  end

  @doc "Whether a marker is currently present."
  @spec armed?(Path.t()) :: boolean()
  def armed?(path), do: File.exists?(path)

  @doc "Writes the marker (best-effort)."
  @spec arm(Path.t()) :: :ok
  def arm(path) do
    File.mkdir_p(Path.dirname(path))
    File.write(path, DateTime.to_iso8601(DateTime.utc_now()))
    :ok
  rescue
    _ -> :ok
  end

  @doc "Removes the marker (best-effort) — called on graceful shutdown."
  @spec disarm(Path.t()) :: :ok
  def disarm(path) do
    File.rm(path)
    :ok
  rescue
    _ -> :ok
  end
end
