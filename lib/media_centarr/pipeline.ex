defmodule MediaCentarr.Pipeline do
  use Boundary,
    deps: [MediaCentarr.TMDB, MediaCentarr.Library, MediaCentarr.Watcher],
    exports: [Discovery, Supervisor, Stats, ImageQueue, Image.Supervisor, Image.Stats]

  @moduledoc """
  Boundary anchor for the ingestion Pipeline context.

  The pipeline is implemented as a Broadway topology under
  `MediaCentarr.Pipeline.*` (Discovery, Import, Stages, Image). This module
  exists to host the `use Boundary` declaration; there is no public facade
  function — pipeline interaction is exclusively via PubSub topics declared
  in `MediaCentarr.Topics`.
  """
end
