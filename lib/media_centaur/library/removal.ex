defmodule MediaCentaur.Library.Removal do
  @moduledoc """
  Deletes media files and folders from disk and cleans up associated
  library records (WatchedFiles, child entities, cascading to entity
  deletion when the last file is removed).

  Calls `FileTracker.cleanup_removed_files/1` directly — does not rely
  on inotify. The cleanup is idempotent, so if the watcher also fires
  for the same paths, the second pass is a no-op.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.FileTracker
  alias MediaCentaur.Library.Helpers

  @doc """
  Deletes a single file from disk and cleans up its library records.

  Returns `{:ok, entity_ids}` on success or `{:error, reason}` on failure.
  `:enoent` (file already gone) is treated as success — the library cleanup
  still runs to remove DB records.
  """
  @spec delete_file(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def delete_file(file_path) do
    case File.rm(file_path) do
      :ok ->
        Log.info(:library, "deleted file: #{file_path}")
        cleanup_and_broadcast([file_path])

      {:error, :enoent} ->
        Log.info(:library, "file already absent, cleaning up records: #{file_path}")
        cleanup_and_broadcast([file_path])

      {:error, reason} ->
        Log.warning(:library, "failed to delete file #{file_path}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Deletes a folder and all its contents from disk, then cleans up library
  records for all WatchedFiles that were under that folder.

  `file_paths` is the list of WatchedFile paths under the folder — these
  must be collected *before* deletion because `rm -rf` does not generate
  per-file inotify events.

  Returns `{:ok, entity_ids}` on success or `{:error, reason}` on failure.
  """
  @spec delete_folder(String.t(), [String.t()]) :: {:ok, [String.t()]} | {:error, any()}
  def delete_folder(folder_path, file_paths) do
    case File.rm_rf(folder_path) do
      {:ok, _removed} ->
        Log.info(:library, "deleted folder: #{folder_path}")
        cleanup_and_broadcast(file_paths)

      {:error, reason, failed_path} ->
        Log.warning(
          :library,
          "failed to delete folder #{folder_path}: #{reason} (#{failed_path})"
        )

        {:error, reason}
    end
  end

  defp cleanup_and_broadcast(file_paths) do
    entity_ids = FileTracker.cleanup_removed_files(file_paths)
    Helpers.broadcast_entities_changed(entity_ids)
    {:ok, entity_ids}
  end
end
