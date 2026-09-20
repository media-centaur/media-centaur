defmodule MediaCentaur.Acquisition.TmdbReferences do
  @moduledoc """
  Every non-terminal pursuit references its identity — while the app is
  still acquiring a title, its record and artwork must not age out.
  Terminal pursuits (satisfied / partial / exhausted / cancelled) release
  the reference; retention takes it from there.

  Planned titles do not yet schedule checks: the plan board still reads
  TMDB for itself until Phase 3 of `tmdb-fetch-policy` moves it onto the
  store, and a check nothing reads is a request spent for nothing.
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork

  @impl true
  def references do
    from(p in Pursuit,
      where: p.state in ^State.in_flight() and not is_nil(p.tmdb_id) and not is_nil(p.tmdb_type),
      select: {p.tmdb_type, p.tmdb_id}
    )
    |> Repo.all()
    |> Enum.reduce(MapSet.new(), fn {type, id}, acc ->
      case TmdbArtwork.normalize_id(id) do
        nil -> acc
        parsed -> MapSet.put(acc, {parsed, TmdbArtwork.normalize_type(type)})
      end
    end)
  end

  @impl true
  def schedules_checks?, do: false
end
