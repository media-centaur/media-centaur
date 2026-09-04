defmodule MediaCentaur.IntegrationHealth.Verifier do
  @moduledoc """
  Pure dispatch from an integration id to the function that actually
  hits the network and answers "does this integration work?". One clause
  per supported integration. Each clause returns `:ok | {:error, term()}`.

  Kept separate from `IntegrationHealth` so the network calls are
  mockable in tests via `Application.put_env(:media_centaur,
  :integration_health_verifier, MyMock)` (see the `verifier/0` getter).
  """

  alias MediaCentaur.Downloads.DownloadClient.Dispatcher

  @type id :: MediaCentaur.IntegrationHealth.Status.id()

  @callback run(id()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl __MODULE__
  def run(:tmdb) do
    case MediaCentaur.TMDB.Client.configuration() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def run(:prowlarr) do
    case MediaCentaur.Acquisition.test_prowlarr() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Route through the two-slot Dispatcher rather than hardcoding one
  # driver: a usenet-only install has no torrent client, so probing
  # qBittorrent would always error. Healthy = every configured slot
  # tests :ok; unconfigured = no slot at all.
  def run(:download_client) do
    case Dispatcher.drivers() do
      [] ->
        {:error, :not_configured}

      drivers ->
        Enum.reduce_while(drivers, :ok, fn {config, module}, :ok ->
          case module.test_connection(config) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end
end
