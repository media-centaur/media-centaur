defmodule MediaCentaur.Discovery.TmdbReferences do
  @moduledoc """
  Every title intent at List or above references its title — such a
  record is a standing interest, so the title's record and artwork never
  age out while the record exists. An Ignored record is the opposite of
  an interest and references nothing.

  Listed titles do not yet schedule checks: the watchlist still paints
  from the intent's own snapshot until Phase 3 of `tmdb-fetch-policy`
  moves it onto the store.
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  import Ecto.Query

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Repo

  @impl true
  def references do
    from(i in TitleIntent, where: i.rung != :ignored, select: {i.tmdb_id, i.media_type})
    |> Repo.all()
    |> MapSet.new()
  end

  @impl true
  def schedules_checks?, do: false
end
