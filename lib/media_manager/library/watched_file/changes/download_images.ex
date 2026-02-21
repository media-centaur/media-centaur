defmodule MediaManager.Library.WatchedFile.Changes.DownloadImages do
  use Ash.Resource.Change
  alias MediaManager.Library.Entity

  def change(changeset, _opts, _context) do
    entity_id = Ash.Changeset.get_attribute(changeset, :entity_id)
    entity = Ash.get!(Entity, entity_id, action: :with_associations)

    case MediaManager.ImageDownloader.download_all(entity) do
      :ok ->
        Ash.Changeset.change_attribute(changeset, :state, :complete)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(
          :error_message,
          "Image download failed: #{inspect(reason)}"
        )
    end
  end
end
