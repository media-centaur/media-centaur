defmodule MediaCentarr.Platform.DriveProbe do
  @moduledoc """
  Drive-capacity probe — behaviour + facade.

  Decouples `MediaCentarr.Storage` from the OS-specific way to ask
  "how much space is on the filesystem containing this path?":

  * **Linux** uses GNU `df --output=...` with explicit columns
    (`Platform.DriveProbe.GnuDf`).
  * **macOS** uses BSD `df -k -P` (POSIX format, 1024-block units)
    — `Platform.DriveProbe.BsdDf`, landing in a future campaign
    phase.

  ## Usage

      iex> MediaCentarr.Platform.DriveProbe.available_bytes("/tmp")
      {:ok, _bytes}

  The facade reads the configured impl from
  `Application.get_env(:media_centarr, __MODULE__, ...)`, defaulting
  to `GnuDf` when nothing is configured. Tests override via
  `Application.put_env/3`.
  """

  @type drive_info :: %{
          device: String.t(),
          mount_point: String.t(),
          used_bytes: non_neg_integer(),
          total_bytes: non_neg_integer(),
          usage_percent: non_neg_integer()
        }

  @callback available_bytes(path :: String.t()) :: {:ok, non_neg_integer()} | :error
  @callback measure(path :: String.t()) :: {:ok, drive_info()} | :error

  @doc "Available bytes on the filesystem containing `path`."
  @spec available_bytes(String.t()) :: {:ok, non_neg_integer()} | :error
  def available_bytes(path), do: impl().available_bytes(path)

  @doc "Drive-capacity info for the filesystem containing `path`."
  @spec measure(String.t()) :: {:ok, drive_info()} | :error
  def measure(path), do: impl().measure(path)

  defp impl do
    Application.get_env(:media_centarr, __MODULE__, MediaCentarr.Platform.DriveProbe.GnuDf)
  end
end
