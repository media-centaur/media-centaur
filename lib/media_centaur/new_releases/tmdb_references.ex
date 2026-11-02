defmodule MediaCentaur.NewReleases.TmdbReferences do
  @moduledoc """
  Every member of the New Releases shelf references its title, so the
  store's record and the referenced artwork stay alive while the title is
  on the shelf, and its checks are scheduled — the check job is the net
  for a refresh TMDB held mid-run. A member that leaves the shelf is
  swept by the first daily retention sweep that finds it unreferenced
  with its last fetch over seven days old.
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  alias MediaCentaur.NewReleases

  @impl true
  def references, do: MapSet.new(NewReleases.refs())

  @impl true
  def schedules_checks?, do: true
end
