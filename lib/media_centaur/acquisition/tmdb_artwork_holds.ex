defmodule MediaCentaur.Acquisition.TmdbArtworkHolds do
  @moduledoc """
  Every non-terminal pursuit holds the TMDB artwork cache entry for its
  identity — while the app is still acquiring a title, its artwork must
  not age out. Terminal pursuits (satisfied / partial / exhausted /
  cancelled) release the hold; the TTL takes it from there.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork

  @impl true
  def holds do
    from(p in Pursuit,
      where: p.state in ^State.in_flight() and not is_nil(p.tmdb_id) and not is_nil(p.tmdb_type),
      select: {p.tmdb_type, p.tmdb_id}
    )
    |> Repo.all()
    |> Enum.reduce(MapSet.new(), fn {type, id}, acc ->
      case TmdbArtwork.normalize_id(id) do
        nil -> acc
        parsed -> MapSet.put(acc, {TmdbArtwork.normalize_type(type), parsed})
      end
    end)
  end
end
