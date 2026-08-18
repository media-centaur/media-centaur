defmodule MediaCentaur.Discovery.TmdbArtworkHolds do
  @moduledoc """
  Every watchlist item holds its TMDB artwork cache entry — the item is
  a standing interest in the title, so its artwork never ages out while
  the item exists.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(w in WatchlistItem, select: {w.media_type, w.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
