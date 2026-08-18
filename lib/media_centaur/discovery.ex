defmodule MediaCentaur.Discovery do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork],
    exports: [WatchlistItem]

  @moduledoc """
  Bounded context for discovery: the local watchlist — title-level
  "I want to watch this" intent — and, in later iterations, the candidate
  sources that feed it (TMDB discover, list import, friend recommendations).
  """
end
