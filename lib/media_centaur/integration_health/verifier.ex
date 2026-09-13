defmodule MediaCentaur.IntegrationHealth.Verifier do
  @moduledoc """
  Pure dispatch from an integration id to the function that actually
  hits the network and answers "does this integration work?". One clause
  per supported integration. Each clause returns `:ok | {:error, term()}`.

  Kept separate from `IntegrationHealth` so the network calls are
  mockable in tests via `Application.put_env(:media_centaur,
  :integration_health_verifier, MyMock)` (see the `verifier/0` getter).
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Search.Prowlarr

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

  # Gate on configuration here rather than through `Acquisition`: the
  # probe is Search's client plus Capabilities' predicate, and pulling
  # in the whole Acquisition context for that one gate was the only
  # reason IntegrationHealth depended on it.
  def run(:prowlarr) do
    if Capabilities.configured?(:prowlarr), do: Prowlarr.ping(), else: {:error, :not_configured}
  end

  # One slot, one integration (UIDR-041 §7): each probe resolves its own
  # protocol's driver through the Dispatcher; an empty slot is not
  # configured, never an error to report.
  def run(:download_client), do: run_slot(:torrent)
  def run(:usenet_download_client), do: run_slot(:usenet)

  defp run_slot(protocol) do
    case Dispatcher.driver_for(protocol) do
      {:ok, {config, module}} -> module.test_connection(config)
      {:error, _empty_slot} -> {:error, :not_configured}
    end
  end
end
