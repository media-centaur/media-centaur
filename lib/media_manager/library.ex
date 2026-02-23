defmodule MediaManager.Library do
  @moduledoc """
  The media library domain — entities, images, identifiers, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  use Ash.Domain

  resources do
    resource MediaManager.Library.Entity
    resource MediaManager.Library.WatchedFile
    resource MediaManager.Library.Image
    resource MediaManager.Library.Identifier
    resource MediaManager.Library.Movie
    resource MediaManager.Library.Extra
    resource MediaManager.Library.Season
    resource MediaManager.Library.Episode
    resource MediaManager.Library.WatchProgress
    resource MediaManager.Library.Setting
  end
end
