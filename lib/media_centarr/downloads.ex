defmodule MediaCentarr.Downloads do
  use Boundary,
    deps: [MediaCentarr.Capabilities],
    exports: [
      DownloadClient,
      DownloadClient.Dispatcher,
      DownloadClient.QBittorrent,
      Health,
      HealthHistory,
      QueueItem,
      QueueMonitor,
      QueueState,
      QueueStatus
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

    * The target lifecycle (`MediaCentarr.Acquisition.Target`).
    * The Pursuits aggregate (`MediaCentarr.Acquisition.Pursuits`).
    * Prowlarr search or release matching
      (`MediaCentarr.Acquisition.Search.*` after Phase 2).

  The boundary is one-way: `Acquisition` calls into `Downloads` (via
  the exported modules above). `Downloads` knows nothing about targets
  or pursuits — its world is "what's the client doing right now."
  """
end
