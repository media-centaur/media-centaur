defmodule MediaCentaur.Downloads do
  use Boundary,
    deps: [MediaCentaur.Capabilities],
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

  alias MediaCentaur.Downloads.ClientConfig

  @doc """
  The configured download-client slots as `ClientConfig` values —
  torrent slot first, then usenet. A slot counts as configured when
  both its type and URL are set. Empty list when nothing is configured.

  This is the single read-side seam over the flat `download_client_*`
  (torrent) and `usenet_download_client_*` (usenet) config keys; the
  dispatcher and the queue monitor enumerate clients through it rather
  than reading `MediaCentaur.Config` directly.
  """
  @spec configured_clients() :: [ClientConfig.t()]
  def configured_clients do
    Enum.reject([torrent_slot(), usenet_slot()], &is_nil/1)
  end

  # The flat `MediaCentaur.Config` keys backing the two client slots.
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

  defp torrent_slot do
    case slot_identity(:download_client_type, :download_client_url) do
      nil ->
        nil

      {type, url} ->
        %ClientConfig{
          protocol: :torrent,
          type: type,
          url: url,
          username: MediaCentaur.Config.get(:download_client_username),
          password: MediaCentaur.Config.get(:download_client_password)
        }
    end
  end

  defp usenet_slot do
    case slot_identity(:usenet_download_client_type, :usenet_download_client_url) do
      nil ->
        nil

      {type, url} ->
        %ClientConfig{
          protocol: :usenet,
          type: type,
          url: url,
          api_key: MediaCentaur.Config.get(:usenet_download_client_api_key)
        }
    end
  end

  defp slot_identity(type_key, url_key) do
    type = MediaCentaur.Config.get(type_key)
    url = MediaCentaur.Config.get(url_key)

    if is_binary(type) and type != "" and is_binary(url) and url != "" do
      {type, url}
    end
  end
end
