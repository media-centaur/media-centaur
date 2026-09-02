defmodule MediaCentaur.Recommendations.TmdbArtworkHolds do
  @moduledoc """
  Every recommendation holds its TMDB artwork cache entry — sent or
  received, the row is a standing interest in the title, so its artwork
  never ages out while the row exists.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Recommendations.Recommendation
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(r in Recommendation, select: {r.media_type, r.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
