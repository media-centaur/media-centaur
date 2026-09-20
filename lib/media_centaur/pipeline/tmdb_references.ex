defmodule MediaCentaur.Pipeline.TmdbReferences do
  @moduledoc """
  Every title the library owns references its TMDB record — an owned
  title is a standing interest, so its record and artwork never age out
  while the entity exists, and its release facts are checked while it is
  unsettled, so `MediaCentaur.Pipeline.TmdbProjection` has something to
  follow: a returning series' next season lands in its episode lists, a
  movie's home release in its dates. A settled title costs nothing.

  In the pipeline, the library's TMDB-facing side: `Library` depends on
  nothing TMDB-shaped (ADR-029).
  """
  @behaviour MediaCentaur.TMDB.References.Provider

  alias MediaCentaur.Library.ExternalIds

  @impl true
  def references, do: MapSet.new(ExternalIds.list_tmdb_refs())

  @impl true
  def schedules_checks?, do: true
end
