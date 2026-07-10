defmodule MediaCentaur.Downloads.QueueState do
  @moduledoc """
  Versioned snapshot of the download-client queue plus liveness
  metadata. Owned and mutated only by `QueueMonitor`; consumed
  read-only by LiveViews and other subscribers via PubSub or
  `Acquisition.queue_state/0`.

  Carries the client-neutral list of items plus the producer-graded
  `connectivity` (see `MediaCentaur.Downloads.Connectivity`) — the
  snapshot is self-describing, so consumers never re-derive client
  health from timestamps. `last_successful_poll_at` is display
  metadata ("last seen 3m ago" qualifiers), not a health input.
  Driver-native sync internals (qBittorrent's `rid` conversation, the
  torrent mirror) are NOT here — they live behind
  `DownloadClient.sync/1` as the opaque driver state.
  """

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.Connectivity
  alias MediaCentaur.Downloads.QueueItem

  @typedoc """
  `items` merges every configured client's queue (torrent slot first),
  including `:completed` entries — usenet completion is only observable
  from SABnzbd's history, and the completed entry's `content_path` is
  what pursuit matching pins. `connectivity` is the merged worst-grade
  across clients (a true "something needs attention" signal for
  existing consumers); `client_connectivity` carries the per-slot
  grades so a healthy client isn't painted with the other's outage.
  """
  @type t :: %__MODULE__{
          items: [QueueItem.t()],
          last_polled_at: DateTime.t() | nil,
          last_successful_poll_at: DateTime.t() | nil,
          connectivity: Connectivity.t(),
          client_connectivity: %{ClientConfig.protocol() => Connectivity.t()}
        }

  defstruct items: [],
            last_polled_at: nil,
            last_successful_poll_at: nil,
            connectivity: :initializing,
            client_connectivity: %{}
end
