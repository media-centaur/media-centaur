defmodule MediaManager.Library.WatchedFile.Changes.DownloadImages do
  @moduledoc """
  Ash change that downloads images for newly created entities.
  Delegates to `Pipeline.ImageDownloader` and transitions the file
  to `:complete` state. Individual image failures are logged as warnings
  but do not block completion.
  """
  use Ash.Resource.Change
  require MediaManager.Log, as: Log
  alias MediaManager.Library.Entity

  def change(changeset, _opts, _context) do
    entity_id = Ash.Changeset.get_attribute(changeset, :entity_id)
    entity = Ash.get!(Entity, entity_id, action: :with_images)

    Log.info(:pipeline, "downloading images for entity #{entity_id}")
    MediaManager.Pipeline.ImageDownloader.download_all(entity)

    Ash.Changeset.change_attribute(changeset, :state, :complete)
  end
end
