defmodule MediaCentarr.Acquisition.DownloadClient do
  @moduledoc """
  Behaviour implemented by drivers that talk to a torrent or usenet
  download client (qBittorrent, Transmission, SABnzbd, …).

  Drivers are pluggable: add a module that implements this behaviour and
  a `MediaCentarr.Acquisition.DownloadClient.Dispatcher` clause mapping
  the configured `:download_client_type` string to the module.

  ## Filter values

    * `:active`    — currently downloading or in-flight
    * `:completed` — finished
    * `:all`       — both

  Drivers translate these to whatever filter shape the underlying client
  understands.
  """

  alias MediaCentarr.Acquisition.QueueItem

  @type filter :: :active | :completed | :all

  @callback list_downloads(filter()) :: {:ok, [QueueItem.t()]} | {:error, term()}
  @callback test_connection() :: :ok | {:error, term()}
end
