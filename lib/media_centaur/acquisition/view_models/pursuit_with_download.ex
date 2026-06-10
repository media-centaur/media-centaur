defmodule MediaCentaur.Acquisition.ViewModels.PursuitWithDownload do
  @moduledoc """
  Index-row VM pairing a `PursuitRow` with its currently-matched live
  queue item (or `nil` when nothing is downloading for that pursuit).

  Built per render by `MediaCentaur.Acquisition.QueueMatcher.match/2` —
  the matching is a pure helper over two independent socket assigns
  (`@pursuit_rows`, `@active_queue`), so the DB-backed pursuit list is
  not rebuilt on every queue snapshot.
  """

  alias MediaCentaur.Acquisition.ViewModels.{DownloadProgress, PursuitRow}

  @enforce_keys [:row]
  defstruct [:row, :download, :queue_item_id, downloads: []]

  @typedoc "One claimed torrent — the card renders a strip per entry."
  @type paired_download :: %{download: DownloadProgress.t(), queue_item_id: String.t()}

  @type t :: %__MODULE__{
          row: PursuitRow.t(),
          # The lead pairing (first key's match) — status derivation and
          # single-download surfaces read these; `downloads` carries every
          # claimed torrent for composite pursuits (ADR-055).
          download: DownloadProgress.t() | nil,
          queue_item_id: String.t() | nil,
          downloads: [paired_download()]
        }
end
