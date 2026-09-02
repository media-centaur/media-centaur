defmodule MediaCentaur.TMDB do
  use Boundary,
    deps: [MediaCentaur.ErrorReports],
    exports: [Client, Confidence, Mapper, MetadataStats, RateLimiter, Title, TitleSearch]

  @moduledoc """
  Boundary anchor for the TMDB external-integration adapter.

  TMDB owns no domain data and broadcasts no PubSub events. It exposes
  `Client` (HTTP), `Confidence` (scoring), `Mapper` (TMDB → domain attrs), and
  `MetadataStats` for use by Pipeline, Library, and Review. `Title` is the
  app-wide title value — an embedded schema every title-carrying context
  (release tracking, discovery (watchlist), and the web layer) reuses — and
  `TitleSearch` is the normalized title search built on it, for the omnibox
  and track flow. `RateLimiter` is internal.
  """
end
