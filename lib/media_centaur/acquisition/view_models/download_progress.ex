defmodule MediaCentaur.Acquisition.ViewModels.DownloadProgress do
  @moduledoc "Live download state for the matched QueueItem."

  @enforce_keys [:state]
  # `protocol` mirrors the queue item's owning slot (`:torrent` /
  # `:usenet`) — it keys `Downloads.client_web_url/1` so error surfaces
  # can link to the client's own web UI.
  # `title` is the client's release name — the identifying line when a
  # pursuit carries several otherwise-identical transfer strips.
  defstruct [:state, :title, :progress_pct, :size_bytes, :size_left_bytes, :eta, :client, :protocol]

  # Mirrors the queue item's state exactly — `to_download/1` passes it
  # through unchanged, so any drift here is a lie about what can render.
  @type state :: MediaCentaur.Downloads.QueueItem.state()

  @type t :: %__MODULE__{
          state: state(),
          title: String.t() | nil,
          progress_pct: float() | nil,
          size_bytes: integer() | nil,
          size_left_bytes: integer() | nil,
          eta: String.t() | nil,
          client: String.t() | nil,
          protocol: :torrent | :usenet | nil
        }
end
