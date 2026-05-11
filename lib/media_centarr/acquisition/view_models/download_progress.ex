defmodule MediaCentarr.Acquisition.ViewModels.DownloadProgress do
  @moduledoc "Live download state for the matched QueueItem."

  @enforce_keys [:state]
  defstruct [:state, :progress_pct, :size_bytes, :size_left_bytes, :eta, :client]

  @type state :: :downloading | :queued | :stalled | :paused | :completed | :error | :other

  @type t :: %__MODULE__{
          state: state(),
          progress_pct: float() | nil,
          size_bytes: integer() | nil,
          size_left_bytes: integer() | nil,
          eta: String.t() | nil,
          client: String.t() | nil
        }
end
