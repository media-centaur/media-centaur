defmodule MediaManager.Library do
  use Ash.Domain

  resources do
    resource MediaManager.Library.Entity
    resource MediaManager.Library.WatchedFile
    resource MediaManager.Library.Image
    resource MediaManager.Library.Identifier
    resource MediaManager.Library.Season
    resource MediaManager.Library.Episode
  end
end
