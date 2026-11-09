defmodule MediaCentaurWeb.Api.ReleaseJSON do
  @moduledoc """
  The JSON view of a release. Prowlarr's download link is left out on
  purpose: it can carry Prowlarr's API key.
  """

  alias MediaCentaur.Search.SearchResult

  def release(%SearchResult{} = result) do
    Map.take(result, [
      :guid,
      :title,
      :indexer_id,
      :indexer_name,
      :protocol,
      :quality,
      :size_bytes,
      :seeders,
      :leechers,
      :grabs,
      :publish_date,
      :imdb_id,
      :tmdb_id,
      :tvdb_id
    ])
  end

  def term(%{term: term, outcome: {:ok, results}}) do
    %{term: term, status: :ok, releases: Enum.map(results, &release/1)}
  end

  def term(%{term: term, outcome: {:error, _reason}}) do
    %{term: term, status: :failed, releases: []}
  end
end
