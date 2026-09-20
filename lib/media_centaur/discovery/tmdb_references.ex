defmodule MediaCentaur.Discovery.TmdbReferences do
  @moduledoc """
  Every title intent at List or above references its title — such a
  record is a standing interest, so the title's record and artwork never
  age out while the record exists, and its checks are scheduled: the
  watchlist paints from the store (ADR-071), so what it shows is what
  the checker keeps current. An Ignored record is the opposite of an
  interest and references nothing.
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
  def schedules_checks?, do: true
end
