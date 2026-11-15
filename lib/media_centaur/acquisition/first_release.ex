defmodule MediaCentaur.Acquisition.FirstRelease do
  @moduledoc """
  Stamps criteria with the date before which no release of the wanted
  unit can exist, so `Search.Assessment` rejects a candidate posted
  earlier (`:published_early`) — the fake uploaded under a film's name
  before the film is out, the pack encoded before the episode aired.

  A movie's date is the earliest TMDB knows for the film, of any kind
  (`TMDB.ReleaseWindow.first_release/1`): a festival premiere counts,
  because a genuine copy can follow one. An episode's date is its air
  date in the stored season.

  Both are read from the TMDB store without a request. A title or
  season the store does not hold, or one TMDB has no date for, is left
  unstamped: nothing is rejected on a date nobody knows. Criteria that
  already carry a date are returned as they are — a plan unit holds its
  episode's air date, and the caller sets `available_from` from it.
  """

  alias MediaCentaur.Search.Criteria
  alias MediaCentaur.TMDB.{Mapper, ReleaseWindow, Store}

  @spec stamp(Criteria.t()) :: Criteria.t()
  def stamp(%Criteria{type: :tmdb, tmdb_type: :movie, tmdb_id: tmdb_id, available_from: nil} = criteria)
      when is_binary(tmdb_id) do
    case Store.get({tmdb_id, :movie}) do
      %{payload: payload} when is_map(payload) ->
        window = ReleaseWindow.from_payload(payload, Date.utc_today())
        %{criteria | available_from: ReleaseWindow.first_release(window)}

      _not_stored ->
        criteria
    end
  end

  def stamp(
        %Criteria{
          type: :tmdb,
          tmdb_type: :tv,
          tmdb_id: tmdb_id,
          season_number: season,
          episode_number: episode,
          available_from: nil
        } = criteria
      )
      when is_binary(tmdb_id) and is_integer(season) and is_integer(episode) do
    with %{payload: %{"episodes" => episodes}} <- Store.get_season(tmdb_id, season),
         %{"air_date" => air_date} <- Enum.find(episodes, &(&1["episode_number"] == episode)) do
      %{criteria | available_from: Mapper.parse_date(air_date)}
    else
      _not_stored -> criteria
    end
  end

  def stamp(%Criteria{} = criteria), do: criteria
end
