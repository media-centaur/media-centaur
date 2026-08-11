defmodule MediaCentaur.ReleaseTracking.TmdbArtworkHolds do
  @moduledoc """
  Every tracked item holds its TMDB artwork cache entry — tracking is a
  standing interest in the title, so its artwork never ages out while
  the item exists.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.ReleaseTracking.Item
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(i in Item, select: {i.media_type, i.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
