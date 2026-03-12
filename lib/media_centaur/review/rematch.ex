defmodule MediaCentaur.Review.Rematch do
  @moduledoc """
  Rematches an entity — destroys it and sends its files back through Review
  for correct matching.

  Steps:
  1. Load entity and its WatchedFiles
  2. Parse each file path to extract metadata
  3. Create PendingFiles (upsert-safe) for Review UI
  4. Destroy WatchedFiles and entity cascade
  5. Broadcast to library and review PubSub topics
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.EntityCascade
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Parser
  alias MediaCentaur.Review
  alias MediaCentaur.Topics

  @spec rematch_entity(String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found | :no_files}
  def rematch_entity(entity_id) do
    with {:ok, _entity} <- load_entity(entity_id),
         {:ok, watched_files} <- load_watched_files(entity_id) do
      pending_files = create_pending_files(watched_files)
      destroy_watched_files(watched_files)
      EntityCascade.destroy!(entity_id)

      Helpers.broadcast_entities_changed([entity_id])
      broadcast_pending_files(pending_files)

      Log.info(
        :library,
        "rematched entity #{entity_id}, created #{length(pending_files)} pending files"
      )

      {:ok, length(pending_files)}
    end
  end

  defp load_entity(entity_id) do
    case Library.get_entity_with_associations(entity_id) do
      {:ok, entity} -> {:ok, entity}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp load_watched_files(entity_id) do
    case Library.list_watched_files_for_entity!(entity_id) do
      [] -> {:error, :no_files}
      files -> {:ok, files}
    end
  end

  defp create_pending_files(watched_files) do
    Enum.map(watched_files, fn file ->
      attrs = build_pending_attrs(file)
      {:ok, pending_file} = Review.find_or_create_pending_file(attrs)
      pending_file
    end)
  end

  defp build_pending_attrs(watched_file) do
    parsed = Parser.parse(watched_file.file_path)

    {search_title, search_year} = search_params(parsed)

    %{
      file_path: watched_file.file_path,
      watch_directory: watched_file.watch_dir,
      parsed_title: search_title,
      parsed_year: search_year,
      parsed_type: type_to_string(parsed.type),
      season_number: parsed.season,
      episode_number: parsed.episode
    }
  end

  defp search_params(%{type: :extra, parent_title: title, parent_year: year}), do: {title, year}
  defp search_params(%{title: title, year: year}), do: {title, year}

  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)

  defp destroy_watched_files(watched_files) do
    EntityCascade.bulk_destroy(watched_files, Library.WatchedFile)
  end

  defp broadcast_pending_files(pending_files) do
    Enum.each(pending_files, fn pending_file ->
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.review_updates(),
        {:file_added, pending_file.id}
      )
    end)
  end
end
