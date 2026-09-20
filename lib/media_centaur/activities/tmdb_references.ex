defmodule MediaCentaur.Activities.TmdbReferences do
  @moduledoc """
  Every activity references its title — sent or received, the row is a
  standing interest, so the title's record and artwork never age out
  while the row exists.

  Never schedules checks: a title known only through friends' activity
  would otherwise let the social feed drive unbounded checking
  (ADR-071 §4).
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  import Ecto.Query

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Repo

  @impl true
  def references do
    from(a in Activity, select: {a.tmdb_id, a.media_type})
    |> Repo.all()
    |> MapSet.new()
  end

  @impl true
  def schedules_checks?, do: false
end
