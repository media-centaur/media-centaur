defmodule MediaCentaur.Activities.TmdbArtworkHolds do
  @moduledoc """
  Every recommendation holds its TMDB artwork cache entry — sent or
  received, the row is a standing interest in the title, so its artwork
  never ages out while the row exists.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(a in Activity, select: {a.media_type, a.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
