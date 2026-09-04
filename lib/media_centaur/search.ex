defmodule MediaCentaur.Search do
  use Boundary,
    deps: [MediaCentaur.Capabilities, MediaCentaur.ErrorReports, MediaCentaur.Settings],
    exports: [
      CourCoverage,
      CourQueries,
      Criteria,
      IncidentContext,
      IndexerHealth,
      Prowlarr,
      QueryBuilder,
      QueryExpander,
      QueryTerm,
      Quality,
      ReleaseCoverage,
      ReleaseRedFlags,
      SearchProvider,
      SearchResult,
      TitleMatcher
    ]

  @moduledoc """
  Stateless Prowlarr-facing search boundary (ADR-043 Phase 2).

  Owns:

    * **Prowlarr client** — `Prowlarr` issues authenticated requests
      to the configured Prowlarr instance and parses indexer
      responses into `SearchResult` structs.
    * **Query construction** — `QueryBuilder` and `QueryExpander`
      assemble TMDB-derived inputs into the search-string variants
      that Prowlarr supports.
    * **Result classification** — `Quality` and `TitleMatcher` rank
      and filter results into the windows pursuits can act on.
    * **Provider abstraction** — `SearchProvider` is the seam for
      future indexer drivers (e.g. Jackett); every cross-boundary
      caller goes through this layer.

  In-flight search *UX* state is deliberately not here — it lives in
  `MediaCentaurWeb.IncomingLive.SearchSession` (web-layer UI
  infrastructure). This boundary stays pure operations.

  ## Where to start

  * `search/2`, `find_best/2` — the Prowlarr-facing entry points
    (delegated from `MediaCentaur.Acquisition` for grab callers).

  ## Boundary deps

  ```
  Search → Capabilities, Settings
  ```

  Search holds **no durable state** — every value flowing through
  this boundary is a runtime struct. `acquisition_grabs` and the
  Pursuits aggregate are Acquisition's concerns. Search's job is to
  answer "given these inputs, what Prowlarr results exist?" and
  hand the answer back.

  ## Topics

  Consumes nothing and emits nothing — `Topics.acquisition_search/0`
  broadcasts moved to the web layer with `SearchSession`.
  """
end
