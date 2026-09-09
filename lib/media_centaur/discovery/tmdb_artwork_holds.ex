defmodule MediaCentaur.Discovery.TmdbArtworkHolds do
  @moduledoc """
  Every title intent at List or above holds its TMDB artwork cache entry
  — such a record is a standing interest in the title, so its artwork
  never ages out while the record exists. An Ignored record is the
  opposite of an interest and holds nothing.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(i in TitleIntent, where: i.rung != :ignored, select: {i.media_type, i.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
