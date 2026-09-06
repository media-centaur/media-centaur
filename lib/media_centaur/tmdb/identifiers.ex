defmodule MediaCentaur.TMDB.Identifiers do
  @moduledoc """
  How a TMDB title spells itself elsewhere — its IMDb and TVDB ids.

  TMDB puts them in two different places: a movie detail carries
  `imdb_id` at the top level, a series detail carries both under the
  appended `external_ids` block (`TMDB.Client.get_tv/2` requests it).
  This module is the single place that knows that, so `TMDB.Mapper`
  (library ingestion) and acquisition (indexer identity) read the same
  answer from the same code.

  Ids are normalized to the string spelling `Library.ExternalIds` uses —
  IMDb keeps its `tt` prefix, TVDB is the bare number as a string — and
  an absent, blank or zero id reads as `nil`. Indexers declare the same
  ids on their results, which is what makes `Search.TitleMatcher`'s
  exact identity check possible.
  """

  alias MediaCentaur.TMDB.Client

  @type t :: %{imdb_id: String.t() | nil, tvdb_id: String.t() | nil}

  @doc """
  The external ids carried by a TMDB movie or TV detail payload.
  `:tv_series` is accepted alongside `:tv` so the contexts that speak the
  library's media-type vocabulary don't each keep a translation.
  """
  @spec from_payload(:movie | :tv | :tv_series, map()) :: t()
  def from_payload(:movie, payload) when is_map(payload) do
    %{imdb_id: presence(payload["imdb_id"]), tvdb_id: nil}
  end

  def from_payload(:tv_series, payload), do: from_payload(:tv, payload)

  def from_payload(:tv, payload) when is_map(payload) do
    external = payload["external_ids"] || %{}

    %{imdb_id: presence(external["imdb_id"]), tvdb_id: presence(external["tvdb_id"])}
  end

  @doc """
  Fetches a title's external ids from TMDB. Best-effort: an unreachable
  or unhelpful TMDB yields empty ids rather than an error, because every
  consumer treats identity as optional evidence and falls back to
  matching on the release name.
  """
  @spec fetch(:movie | :tv, String.t() | integer(), keyword()) :: t()
  def fetch(type, tmdb_id, opts \\ []) do
    case fetch_payload(type, tmdb_id, opts) do
      {:ok, payload} -> from_payload(type, payload)
      {:error, _reason} -> %{imdb_id: nil, tvdb_id: nil}
    end
  end

  defp fetch_payload(:movie, tmdb_id, opts), do: Client.get_movie(tmdb_id, opts)
  defp fetch_payload(:tv, tmdb_id, opts), do: Client.get_tv(tmdb_id, opts)

  defp presence(id) when is_integer(id) and id > 0, do: Integer.to_string(id)
  defp presence(id) when is_binary(id), do: if(String.trim(id) != "", do: id)
  defp presence(_id), do: nil
end
