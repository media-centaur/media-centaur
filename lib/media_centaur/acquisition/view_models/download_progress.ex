defmodule MediaCentaur.Acquisition.ViewModels.DownloadProgress do
  @moduledoc "Live download state for the matched QueueItem."

  @enforce_keys [:state]
  defstruct [:state, :progress_pct, :size_bytes, :size_left_bytes, :eta, :client]

  # Mirrors the queue item's state exactly — `to_download/1` passes it
  # through unchanged, so any drift here is a lie about what can render.
  @type state :: MediaCentaur.Downloads.QueueItem.state()

  @type t :: %__MODULE__{
          state: state(),
          progress_pct: float() | nil,
          size_bytes: integer() | nil,
          size_left_bytes: integer() | nil,
          eta: String.t() | nil,
          client: String.t() | nil
        }
end
