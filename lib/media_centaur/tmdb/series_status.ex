defmodule MediaCentaur.TMDB.SeriesStatus do
  @moduledoc """
  TMDB's status of each series in a set, read from the store's records —
  a projection over stored payloads (ADR-071), no request: `:returning`,
  `:ended`, `:canceled`, `:in_production`, `:planned`, or `:unknown` when
  the payload says nothing the app names (`Mapper.tv_status/1`). The
  Watchlist page reads it for a followed series with no episode out and
  none dated: *Returning* or *Ended* is then the one thing known.
  """

  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.TMDB.Store

  @type status :: :returning | :ended | :canceled | :in_production | :planned | :unknown

  @doc "The status of every series ref the store holds; a movie ref or one the store lacks is absent."
  @spec for_refs([Store.ref()]) :: %{Store.ref() => status()}
  def for_refs(refs) when is_list(refs) do
    refs
    |> Enum.filter(&match?({_id, :tv_series}, &1))
    |> Store.get_many()
    |> Map.new(fn {ref, record} -> {ref, read(record.payload)} end)
  end

  @doc "One payload's status, for a caller holding the record already."
  @spec read(map()) :: status()
  def read(payload) when is_map(payload), do: Mapper.tv_status(payload["status"]) || :unknown
end
