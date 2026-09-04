defmodule MediaCentaur.Downloads.DownloadClient do
  @moduledoc """
  Behaviour implemented by drivers that talk to a torrent or usenet
  download client (qBittorrent, Transmission, SABnzbd, …).

  Drivers are pluggable: add a module that implements this behaviour and
  a `MediaCentaur.Downloads.DownloadClient.Dispatcher` type→module
  entry so its protocol slot resolves to the new driver.

  Every callback takes the slot's `MediaCentaur.Downloads.ClientConfig`
  first: a driver is a function of its configuration and holds no
  connection settings of its own. The Dispatcher hands each driver the
  config it was resolved for.
  """

  alias MediaCentaur.Downloads.ClientConfig
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

  @typedoc "Opaque per-driver sync bookmark. `nil` means start fresh (full update)."
  @type driver_state :: term()

  @callback test_connection(ClientConfig.t()) :: :ok | {:error, term()}

  @doc """
  One incremental-sync tick: given the previous tick's opaque
  `driver_state` (or `nil` to start fresh), returns the full current
  queue as `SyncResult.t()`. On error, returns the driver state the
  caller should hand back next tick — drivers use this to reset their
  conversation so the next successful poll is a full update.
  """
  @callback sync(ClientConfig.t(), driver_state()) ::
              {:ok, SyncResult.t()} | {:error, term(), driver_state()}

  @doc """
  Cancels a download by its client-specific id. Destructive — the driver
  is expected to remove both the queue entry and the downloaded files.
  """
  @callback cancel_download(ClientConfig.t(), id :: String.t()) :: :ok | {:error, term()}
end
