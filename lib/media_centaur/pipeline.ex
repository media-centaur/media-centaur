defmodule MediaCentaur.Pipeline do
  use Boundary,
    deps: [MediaCentaur.TMDB, MediaCentaur.Library, MediaCentaur.Watcher],
    exports: [
      Discovery,
      Image.Stats,
      Image.Supervisor,
      ImageQueue,
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
