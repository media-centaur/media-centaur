defmodule MediaCentaur.Library do
  @moduledoc """
  The media library domain — entities, images, identifiers, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  use Ash.Domain

  resources do
    resource MediaCentaur.Library.Entity
    resource MediaCentaur.Library.WatchedFile
    resource MediaCentaur.Library.Image
    resource MediaCentaur.Library.Identifier
    resource MediaCentaur.Library.Movie
    resource MediaCentaur.Library.Extra
    resource MediaCentaur.Library.Season
    resource MediaCentaur.Library.Episode
    resource MediaCentaur.Library.WatchProgress
    resource MediaCentaur.Library.Setting
  end
end
