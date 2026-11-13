defmodule MediaCentaur.Acquisition.FirstRelease do
  @moduledoc """
  Stamps a movie's criteria with the date before which no release of it
  can exist, so `Search.Assessment` rejects a candidate posted earlier
  (`:published_early`) — the fake uploaded under a film's name before
  the film is out.

  The date is the earliest TMDB knows for the film, of any kind
  (`TMDB.ReleaseWindow.first_release/1`): a festival premiere counts,
  because a genuine copy can follow one. It is read from the stored
  title record (`TMDB.Store`, no request). A film the store does not
  hold, or one TMDB has no date for, is left unstamped and nothing is
  rejected on a date nobody knows.

  The TV counterpart needs no lookup: a plan unit carries its episode's
  air date, and the caller sets `available_from` from it.
  """

  alias MediaCentaur.Search.Criteria
  alias MediaCentaur.TMDB.{ReleaseWindow, Store}

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

  def stamp(%Criteria{} = criteria), do: criteria
end
