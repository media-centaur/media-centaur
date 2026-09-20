defmodule MediaCentaur.ReleaseTracking.TmdbReferences do
  @moduledoc """
  Every tracked item references its title — tracking is a standing
  interest, so the title's record and artwork never age out while the
  item exists, and the title is checked while it is unsettled.
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  import Ecto.Query

  alias MediaCentaur.ReleaseTracking.Item
  alias MediaCentaur.Repo

  @impl true
  def references do
    from(i in Item, select: {i.tmdb_id, i.media_type})
    |> Repo.all()
    |> MapSet.new()
  end

  @impl true
  def schedules_checks?, do: true
end
