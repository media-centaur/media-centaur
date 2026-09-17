defmodule MediaCentaur.Acquisition.ViewModels.Alternative do
  @moduledoc """
  Display contract for one re-search alternative on the decision card.

  `scope` is what the release contains, read from its name
  (`Search.ReleaseCoverage.classify/1`): a single episode needs no
  label on the card, a pack is shown as one so the user knows a pick
  downloads more than the episode.
  """

  alias MediaCentaur.Search.{Quality, ReleaseCoverage, SearchResult}

  @enforce_keys [:guid, :title, :indexer]
  defstruct [:guid, :title, :indexer, :quality, :size_bytes, :seeders, :indexer_id, :scope]

  @type t :: %__MODULE__{
          guid: String.t(),
          title: String.t(),
          indexer: String.t(),
          quality: String.t() | nil,
          size_bytes: integer() | nil,
          seeders: integer() | nil,
          indexer_id: integer() | nil,
          scope: ReleaseCoverage.t() | nil
        }

  @doc "The card row for one search result."
  @spec from(SearchResult.t()) :: t()
  def from(%SearchResult{} = result) do
    %__MODULE__{
      guid: result.guid,
      title: result.title,
      indexer: result.indexer_name || "Unknown",
      quality: if(is_atom(result.quality), do: Quality.label(result.quality)),
      size_bytes: result.size_bytes,
      seeders: result.seeders,
      indexer_id: result.indexer_id,
      scope: ReleaseCoverage.classify(result.title)
    }
  end
end
