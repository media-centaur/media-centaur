defmodule MediaCentarr.Acquisition.ViewModels.PursuitWithDownload do
  @moduledoc """
  Index-row VM pairing a `PursuitRow` with its currently-matched live
  queue item (or `nil` when nothing is downloading for that pursuit).

  Built per render by `MediaCentarr.Acquisition.QueueMatcher.match/2` —
  the matching is a pure helper over two independent socket assigns
  (`@pursuit_rows`, `@active_queue`), so the DB-backed pursuit list is
  not rebuilt on every queue snapshot.
  """

  alias MediaCentarr.Acquisition.ViewModels.{DownloadProgress, PursuitRow}

  @enforce_keys [:row]
  defstruct [:row, :download, :queue_item_id]

  @type t :: %__MODULE__{
          row: PursuitRow.t(),
          download: DownloadProgress.t() | nil,
          queue_item_id: String.t() | nil
        }
end
