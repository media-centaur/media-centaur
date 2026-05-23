defmodule MediaCentaur.IntegrationHealth.Verifier do
  @moduledoc """
  Pure dispatch from an integration id to the function that actually
  hits the network and answers "does this integration work?". One clause
  per supported integration. Each clause returns `:ok | {:error, term()}`.

  Kept separate from `IntegrationHealth` so the network calls are
  mockable in tests via `Application.put_env(:media_centaur,
  :integration_health_verifier, MyMock)` (see the `verifier/0` getter).
  """

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

  def run(:download_client) do
    case MediaCentaur.Downloads.DownloadClient.QBittorrent.test_connection() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
