defmodule MediaManager.Library.WatchedFile.Changes.FetchMetadata do
  @moduledoc """
  Ash change that fetches TMDB metadata and resolves the watched file
  to an entity. Delegates all entity creation logic to `EntityResolver`.
  """
  use Ash.Resource.Change

  alias MediaManager.Library.EntityResolver

  def change(changeset, _opts, _context) do
    tmdb_id = Ash.Changeset.get_attribute(changeset, :tmdb_id)
    parsed_type = Ash.Changeset.get_attribute(changeset, :parsed_type)
    file_path = Ash.Changeset.get_attribute(changeset, :file_path)
    season_number = Ash.Changeset.get_attribute(changeset, :season_number)
    episode_number = Ash.Changeset.get_attribute(changeset, :episode_number)

    file_context = %{
      file_path: file_path,
      season_number: season_number,
      episode_number: episode_number
    }

    case EntityResolver.resolve(tmdb_id, parsed_type, file_context) do
      {:ok, entity, status} when status in [:new, :new_child] ->
        changeset
        |> Ash.Changeset.change_attribute(:entity_id, entity.id)
        |> Ash.Changeset.change_attribute(:state, :fetching_images)

      {:ok, entity, :existing} ->
        changeset
        |> Ash.Changeset.change_attribute(:entity_id, entity.id)
        |> Ash.Changeset.change_attribute(:state, :complete)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(:error_message, inspect(reason))
    end
  end
end
