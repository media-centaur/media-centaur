defmodule MediaCentaur.Library.Rematch do
  @moduledoc """
  Releases an entity for re-matching: its watched files and the entity
  cascade are destroyed, and the files it held are returned for the caller
  to put back in front of a person. `Review.RematchJob` calls it inside the
  transaction that adds those files to Review, so a rematch lands whole or
  not at all (campaign durable-work, F9).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library.{EntityCascade, Files, Helpers, WatchedFile}

  @type released_file :: %{file_path: String.t(), media_dir: String.t()}

  @doc """
  Destroys `entity_id`'s watched files and the entity, broadcasting the
  change, and returns the files it held. `{:ok, []}` for an entity with no
  watched files, or one already gone.
  """
  @spec release(String.t()) :: {:ok, [released_file()]}
  def release(entity_id) do
    case Files.list_by_entity_id(entity_id) do
      [] ->
        {:ok, []}

      files ->
        released = Enum.map(files, &%{file_path: &1.file_path, media_dir: &1.media_dir})

        EntityCascade.bulk_destroy(files, WatchedFile)
        EntityCascade.destroy!(entity_id)
        Helpers.broadcast_entities_changed([entity_id])

        Log.info(
          :library,
          "rematch — released #{Format.short_id(entity_id)}, #{length(released)} file(s) for review"
        )

        {:ok, released}
    end
  end
end
