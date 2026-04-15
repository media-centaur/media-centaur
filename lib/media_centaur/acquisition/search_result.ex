defmodule MediaCentaur.Acquisition.SearchResult do
  @moduledoc """
  A single result returned by a search provider.

  `quality` is parsed from the title via `Acquisition.Quality.parse/1` at
  construction time so callers can rank and filter without re-parsing.
  """

  alias MediaCentaur.Acquisition.Quality

  @enforce_keys [:title, :guid, :indexer_id]
  defstruct [
    :title,
    :guid,
    :indexer_id,
    :quality,
    :size_bytes,
    :seeders,
    :leechers,
    :indexer_name,
    :publish_date
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          guid: String.t(),
          indexer_id: integer(),
          quality: Quality.t(),
          size_bytes: integer() | nil,
          seeders: integer() | nil,
          leechers: integer() | nil,
          indexer_name: String.t() | nil,
          publish_date: String.t() | nil
        }

  @doc "Builds a SearchResult from a raw Prowlarr API result map."
  @spec from_prowlarr(map()) :: t()
  def from_prowlarr(raw) do
    title = raw["title"] || ""

    %__MODULE__{
      title: title,
      guid: raw["guid"],
      indexer_id: raw["indexerId"],
      quality: Quality.parse(title),
      size_bytes: raw["size"],
      seeders: raw["seeders"],
      leechers: raw["leechers"],
      indexer_name: raw["indexer"],
      publish_date: raw["publishDate"]
    }
  end
end
