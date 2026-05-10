defmodule MediaCentarr.Downloads.QueueState do
  @moduledoc """
  Versioned snapshot of the download-client queue plus liveness
  metadata. Owned and mutated only by `QueueMonitor`; consumed
  read-only by LiveViews and other subscribers via PubSub or
  `Acquisition.queue_state/0`.

  Phase 1 carries the existing list of items plus the timestamps and
  error flag needed to derive a freshness status. Phase 2 will add
  `:rid` and a `torrents` map keyed by hash for incremental sync.
  """

  alias MediaCentarr.Downloads.QueueItem

  @type error_reason ::
          nil
          | :not_configured
          | :auth_failed
          | :unreachable
          | {:offline, DateTime.t()}

  @type t :: %__MODULE__{
          items: [QueueItem.t()],
          torrents: %{required(String.t()) => map()},
          rid: non_neg_integer(),
          server_state: map(),
          last_polled_at: DateTime.t() | nil,
          last_successful_poll_at: DateTime.t() | nil,
          last_error: error_reason()
        }

  defstruct items: [],
            torrents: %{},
            rid: 0,
            server_state: %{},
            last_polled_at: nil,
            last_successful_poll_at: nil,
            last_error: nil
end
