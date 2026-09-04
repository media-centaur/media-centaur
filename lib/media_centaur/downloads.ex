defmodule MediaCentaur.Downloads do
  use Boundary,
    deps: [MediaCentaur.Capabilities, MediaCentaur.ErrorReports],
    exports: [
      ClientConfig,
      DownloadClient,
      DownloadClient.Dispatcher,
      DownloadClient.QBittorrent,
      DownloadClient.SABnzbd,
      Health,
      HealthHistory,
      IncidentContext,
      Connectivity,
      QueueItem,
      QueueMonitor,
      QueueState
    ]

  @moduledoc """
  Download-client integration boundary (ADR-043 Phase 1).

  Owns:

    * **Download-client driver** — `DownloadClient.QBittorrent` and its
      sibling `DownloadClient.QBittorrent.Sync`, dispatched through
      `DownloadClient.Dispatcher`. The dispatcher is the abstraction
      seam for future drivers (e.g. SABnzbd) — every cross-context
      call goes through it.
    * **Queue monitor** — `QueueMonitor` polls the active driver,
      snapshots the queue into `:persistent_term` + GenServer state,
      and broadcasts `acquisition:queue` events. (Topic name kept for
      now; rename deferred per ADR-043's "out of scope" list.)
    * **Health classification** — `Health.classify/3` interprets a
      `QueueItem` against its history (`HealthHistory`) to produce
      `:healthy | :soft_stall | :frozen`. Read by Acquisition's
      Pursuits subsystem on every tick.

  Does NOT own:

    * The target lifecycle (`MediaCentaur.Acquisition.Target`).
    * The Pursuits aggregate (`MediaCentaur.Acquisition.Pursuits`).
    * Prowlarr search or release matching
      (`MediaCentaur.Acquisition.Search.*` after Phase 2).

  The boundary is one-way: `Acquisition` calls into `Downloads` (via
  the exported modules above). `Downloads` knows nothing about targets
  or pursuits — its world is "what's the client doing right now."
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Downloads.ClientConfig

  @doc """
  The configured download-client slots as `ClientConfig` values —
  torrent slot first, then usenet. A slot counts as configured when
  both its type and URL are set. Empty list when nothing is configured.

  This is the single read-side seam over the flat `download_client_*`
  (torrent) and `usenet_download_client_*` (usenet) config keys; the
  dispatcher and the queue monitor enumerate clients through it rather
  than reading `MediaCentaur.Settings.Config` directly.
  """
  @spec configured_clients() :: [ClientConfig.t()]
  def configured_clients do
    Enum.reject([torrent_slot(), usenet_slot()], &is_nil/1)
  end

  # The flat `MediaCentaur.Settings.Config` keys backing the two client slots.
  # Owned here so consumers (e.g. `IntegrationHealth`, which re-derives
  # `configured?` on any of them) don't hardcode the set.
  @config_keys [
    :download_client_type,
    :download_client_url,
    :download_client_username,
    :download_client_password,
    :usenet_download_client_type,
    :usenet_download_client_url,
    :usenet_download_client_api_key
  ]

  @doc """
  True when `key` is one of the config keys backing a download-client
  slot — i.e. a change to it can flip `configured_clients/0`.
  """
  @spec config_key?(atom()) :: boolean()
  def config_key?(key), do: key in @config_keys

  @doc """
  The configured client's web-UI URL for a protocol slot, or nil when
  the slot isn't configured. The same URL the driver talks to — the UI
  renders it as an "Open SABnzbd / qBittorrent" link so the user can
  reach the client's own interface (job logs, failure details) from
  where Media Centaur reports a problem.
  """
  @spec client_web_url(:torrent | :usenet) :: String.t() | nil
  def client_web_url(protocol) when protocol in [:torrent, :usenet] do
    Enum.find_value(configured_clients(), fn %ClientConfig{} = client ->
      client.protocol == protocol && client.url
    end)
  end

  defp torrent_slot do
    if Capabilities.configured?(:download_client) do
      %ClientConfig{
        protocol: :torrent,
        type: Config.get(:download_client_type),
        url: Config.get(:download_client_url),
        username: Config.get(:download_client_username),
        password: Config.get(:download_client_password)
      }
    end
  end

  defp usenet_slot do
    if Capabilities.configured?(:usenet_download_client) do
      %ClientConfig{
        protocol: :usenet,
        type: Config.get(:usenet_download_client_type),
        url: Config.get(:usenet_download_client_url),
        api_key: Config.get(:usenet_download_client_api_key)
      }
    end
  end
end
