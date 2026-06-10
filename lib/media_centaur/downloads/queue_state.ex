defmodule MediaCentaur.Downloads.QueueState do
  @moduledoc """
  Versioned snapshot of the download-client queue plus liveness
  metadata. Owned and mutated only by `QueueMonitor`; consumed
  read-only by LiveViews and other subscribers via PubSub or
  `Acquisition.queue_state/0`.

  Carries the client-neutral list of items plus the timestamps and
  error flag needed to derive a freshness status. Driver-native sync
  internals (qBittorrent's `rid` conversation, the torrent mirror) are
  NOT here — they live behind `DownloadClient.sync/1` as the opaque
  driver state.
  """

  alias MediaCentaur.Downloads.QueueItem

  @type error_reason ::
          nil
          | :not_configured
          | :auth_failed
          | :unreachable
          | {:offline, DateTime.t()}

  @type t :: %__MODULE__{
          items: [QueueItem.t()],
          last_polled_at: DateTime.t() | nil,
          last_successful_poll_at: DateTime.t() | nil,
          last_error: error_reason()
        }

  defstruct items: [],
            last_polled_at: nil,
            last_successful_poll_at: nil,
            last_error: nil
end
