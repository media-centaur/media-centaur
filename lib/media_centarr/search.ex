defmodule MediaCentarr.Search do
  use Boundary,
    deps: [MediaCentarr.Capabilities, MediaCentarr.Settings],
    exports: [
      Criteria,
      Prowlarr,
      QueryBuilder,
      QueryExpander,
      Quality,
      QualityWindow,
      SearchProvider,
      SearchResult,
      SearchSession,
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
    * **Result classification** — `Quality`, `QualityWindow`, and
      `TitleMatcher` rank and filter results into the windows
      pursuits can act on.
    * **In-flight search UX state** — `SearchSession` GenServer holds
      transient state for the AcquisitionLive search form (Pillar 2,
      desktop-rearchitecture).
    * **Provider abstraction** — `SearchProvider` is the seam for
      future indexer drivers (e.g. Jackett); every cross-boundary
      caller goes through this layer.

  ## Where to start

  * `search/2`, `find_best/2` — the Prowlarr-facing entry points
    (delegated from `MediaCentarr.Acquisition` for grab callers).
  * `SearchSession` — the LiveView-facing GenServer for the manual
    search UX.

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

  Currently consumes nothing; emits on `Topics.acquisition_search/0`
  (legacy topic name — kept for compatibility with `acquisition:*`
  subscribers; rename to `search:results` is a planned cosmetic
  follow-up). See ADR-043 §"PubSub topic implications".
  """
end
