defmodule MediaCentarr.Acquisition.ViewModels.Alternative do
  @moduledoc "Display contract for one re-search alternative."

  @enforce_keys [:guid, :title, :indexer]
  defstruct [:guid, :title, :indexer, :quality, :size_bytes, :seeders, :indexer_id]

  @type t :: %__MODULE__{
          guid: String.t(),
          title: String.t(),
          indexer: String.t(),
          quality: String.t() | nil,
          size_bytes: integer() | nil,
          seeders: integer() | nil,
          indexer_id: integer() | nil
        }
end
