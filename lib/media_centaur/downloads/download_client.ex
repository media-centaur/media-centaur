defmodule MediaCentaur.Downloads.DownloadClient do
  @moduledoc """
  Behaviour implemented by drivers that talk to a torrent or usenet
  download client (qBittorrent, Transmission, SABnzbd, …).

  Drivers are pluggable: add a module that implements this behaviour and
  a `MediaCentaur.Downloads.DownloadClient.Dispatcher` clause mapping
  the configured `:download_client_type` string to the module.

  ## Filter values

    * `:active`    — currently downloading or in-flight
    * `:completed` — finished
    * `:all`       — both

  Drivers translate these to whatever filter shape the underlying client
  understands.
  """

  alias MediaCentaur.Downloads.QueueItem

  defmodule SyncResult do
    @moduledoc """
    One incremental-sync tick's outcome, in client-neutral terms.

    `driver_state` is opaque to everything above the driver — the
    caller (`QueueMonitor`) holds it between ticks and hands it back
    on the next `sync/1` call. Each driver keeps its own conversation
    bookmark inside (qBittorrent: the `rid` + torrent mirror; a usenet
    driver: whatever its delta API needs).
    """

    @enforce_keys [:items, :driver_state]
    defstruct [:items, :driver_state, movement?: false, summary: nil]

    @type t :: %__MODULE__{
            items: [QueueItem.t()],
            driver_state: term(),
            movement?: boolean(),
            summary: String.t() | nil
          }
  end

  @type filter :: :active | :completed | :all
  @typedoc "Opaque per-driver sync bookmark. `nil` means start fresh (full update)."
  @type driver_state :: term()

  @callback list_downloads(filter()) :: {:ok, [QueueItem.t()]} | {:error, term()}
  @callback test_connection() :: :ok | {:error, term()}

  @doc """
  One incremental-sync tick: given the previous tick's opaque
  `driver_state` (or `nil` to start fresh), returns the full current
  queue as `SyncResult.t()`. On error, returns the driver state the
  caller should hand back next tick — drivers use this to reset their
  conversation so the next successful poll is a full update.
  """
  @callback sync(driver_state()) ::
              {:ok, SyncResult.t()} | {:error, term(), driver_state()}

  @doc """
  Cancels a download by its client-specific id. Destructive — the driver
  is expected to remove both the queue entry and the downloaded files.
  """
  @callback cancel_download(id :: String.t()) :: :ok | {:error, term()}
end
