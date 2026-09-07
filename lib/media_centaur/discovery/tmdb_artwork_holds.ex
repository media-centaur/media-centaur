defmodule MediaCentaur.Discovery.TmdbArtworkHolds do
  @moduledoc """
  Every title intent holds its TMDB artwork cache entry — a record here
  is a standing interest in the title, so its artwork never ages out
  while the record exists, whatever rung it sits at.
  """
  @behaviour MediaCentaur.TmdbArtwork.HoldProvider

  import Ecto.Query

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Repo

  @impl true
  def holds do
    from(i in TitleIntent, select: {i.media_type, i.tmdb_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
