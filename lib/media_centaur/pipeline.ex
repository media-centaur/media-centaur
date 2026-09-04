defmodule MediaCentaur.Pipeline do
  use Boundary,
    deps: [
      MediaCentaur.TMDB,
      MediaCentaur.Library,
      MediaCentaur.Retention,
      MediaCentaur.Watcher,
      MediaCentaur.Reconciliation,
      MediaCentaur.Review
    ],
    exports: [
      Discovery,
      ExtraRederive,
      Image.Stats,
      Image.Supervisor,
      ImageQueue,
      ImageRefresh,
      ImageRepair,
      Stats,
      Supervisor
    ]

  @moduledoc """
  Boundary anchor for the ingestion Pipeline context.

  The pipeline is implemented as a Broadway topology under
  `MediaCentaur.Pipeline.*` (Discovery, Import, Stages, Image). This module
  exists to host the `use Boundary` declaration; there is no public facade
  function — pipeline interaction is exclusively via PubSub topics declared
  in `MediaCentaur.Topics`.
  """
end
