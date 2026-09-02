defmodule MediaCentaur.TMDB do
  use Boundary,
    deps: [MediaCentaur.ErrorReports],
    exports: [Client, Confidence, Mapper, MetadataStats, RateLimiter, Title]

  @moduledoc """
  Boundary anchor for the TMDB external-integration adapter.

  TMDB owns no domain data and broadcasts no PubSub events. It exposes
  `Client` (HTTP), `Confidence` (scoring), and `Mapper` (TMDB → domain attrs)
  for use by Pipeline, Library, and Review. `RateLimiter` is internal.
  """
end
