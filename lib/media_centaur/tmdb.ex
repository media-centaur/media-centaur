defmodule MediaCentaur.TMDB do
  use Boundary,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.ErrorReports,
      MediaCentaur.HttpClient,
      MediaCentaur.IntegrationAvailability
    ],
    exports: [
      Availability,
      Client,
      Confidence,
      Identifiers,
      Mapper,
      MetadataStats,
      ProbeJob,
      RateLimiter,
      References,
      References.Provider,
      ReleaseWindow,
      Schedule,
      Store,
      Store.SeasonRecord,
      Store.TitleRecord,
      Title,
      TitleIdentity,
      TitleSearch
    ]

  @moduledoc """
  Boundary anchor for the TMDB external-integration adapter.

  TMDB owns the store — one record per title the app knows (`Store`,
  ADR-071), with `Schedule` deciding when a stored title is next due a
  check — and publishes `{:tmdb_title_changed, ref}` on
  `MediaCentaur.Topics.tmdb_titles/0` when a stored payload changes. It
  exposes `Client` (HTTP), `Confidence` (scoring), `Mapper` (TMDB →
  domain attrs), `Identifiers` (how a title spells itself on IMDb /
  TVDB), and `MetadataStats` for use by Pipeline, Library, and Review. `Title` is the
  app-wide title value — an embedded schema every title-carrying context
  (release tracking, discovery (watchlist), and the web layer) reuses — and
  `TitleSearch` is the normalized title search built on it, for the omnibox
  and track flow. `ReleaseWindow` reads where a movie stands in its release
  sequence from a payload, for the surfaces that diagnose an empty search.
  `RateLimiter` is internal.
  """
end
