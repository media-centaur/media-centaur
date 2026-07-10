defmodule MediaCentaur.Downloads.DownloadClient.Dispatcher do
  @moduledoc """
  Resolves configured download-client slots to their driver modules.

  Two protocol slots exist (see `MediaCentaur.Downloads.ClientConfig`):
  the torrent slot and the usenet slot. `drivers/0` enumerates the
  configured set for polling; `driver_for/1` resolves one protocol for
  targeted operations (per-slot connection tests, protocol-routed
  cancel). Add one entry to `module_for_type/1` per new driver.

  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Downloads
  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.QBittorrent
  alias MediaCentaur.Downloads.DownloadClient.SABnzbd

  @type error :: :not_configured | {:unknown_driver, String.t()}

  @doc """
  The configured client slots paired with their driver modules, torrent
  slot first. Slots whose type has no driver in this build are logged
  and skipped so a stale type string can't take the other slot down
  with it. Empty list when no slot is configured.
  """
  @spec drivers() :: [{ClientConfig.t(), module()}]
  def drivers do
    Downloads.configured_clients()
    |> Enum.map(fn client -> {client, module_for_type(client.type)} end)
    |> Enum.flat_map(fn
      {client, {:ok, module}} ->
        [{client, module}]

      {client, :unknown} ->
        Log.warning(
          :acquisition,
          "no #{client.protocol} driver for configured type #{inspect(client.type)} — slot skipped"
        )

        []
    end)
  end

  @doc "Resolves the driver module for one protocol slot."
  @spec driver_for(ClientConfig.protocol()) :: {:ok, module()} | {:error, error()}
  def driver_for(protocol) when protocol in [:torrent, :usenet] do
    case Enum.find(Downloads.configured_clients(), &(&1.protocol == protocol)) do
      nil ->
        {:error, :not_configured}

      client ->
        case module_for_type(client.type) do
          {:ok, module} -> {:ok, module}
          :unknown -> {:error, {:unknown_driver, client.type}}
        end
    end
  end

  defp module_for_type("qbittorrent"), do: {:ok, QBittorrent}
  defp module_for_type("sabnzbd"), do: {:ok, SABnzbd}
  defp module_for_type(_), do: :unknown
end
