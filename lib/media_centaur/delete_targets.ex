defmodule MediaCentaur.DeleteTargets do
  use Boundary, deps: [MediaCentaur.Acquisition, MediaCentaur.Library]

  @moduledoc """
  Resolves whether a set of files can be deleted as a whole folder, or
  only individually — shared by the entity detail page and the Review
  page so neither reinvents (or, worse, diverges on) the safety check.

  `safe_to_delete_folder?/2` is the one thing that makes recursively
  deleting a folder safe: the folder must not be a configured media
  directory root, and nothing already in the library outside the files
  being deleted may live under it. Both call sites gate their `rm -rf`
  on this.

  `resolve_folder_target/1` is Review-specific *discovery* on top of
  that: given a set of not-yet-imported file paths, it finds a folder
  candidate — preferring `Acquisition.Target.content_path` (the exact
  footprint a download client reported, resolved fresh from each file's
  current path so a later move can only ever stop it matching, never
  falsely widen it) and falling back to the files' common parent
  directory — then runs it through the same safety check. The entity
  page doesn't need this half: its folders are already known, real
  `WatchedFile` directories.
  """

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Library

  @doc """
  True when `dir` can be safely `rm -rf`'d given that `file_paths` are
  the only files inside it this operation intends to remove: `dir` is
  not a configured media directory root, and no other already-imported
  file lives under it.
  """
  @spec safe_to_delete_folder?(String.t(), [String.t()]) :: boolean()
  def safe_to_delete_folder?(dir, file_paths) do
    media_dirs = MediaCentaur.Settings.Config.get(:media_dirs) || []

    dir not in media_dirs and
      Library.Files.paths_under(dir) -- file_paths == []
  end

  @doc """
  Resolves the delete target for a set of not-yet-imported file paths
  (e.g. a Review pending group): `{:folder, dir}` when a safe folder
  boundary can be established, `:file_only` otherwise. Never guesses —
  when nothing establishes a safe folder, only the individual files are
  offered for deletion.
  """
  @spec resolve_folder_target([String.t()]) :: {:folder, String.t()} | :file_only
  def resolve_folder_target([]), do: :file_only

  def resolve_folder_target(file_paths) do
    with candidate when not is_nil(candidate) <- folder_candidate(file_paths),
         true <- safe_to_delete_folder?(candidate, file_paths) do
      {:folder, candidate}
    else
      _ -> :file_only
    end
  end

  defp folder_candidate(file_paths) do
    content_path_candidate(file_paths) || common_parent_candidate(file_paths)
  end

  # The most precise boundary: a `Target.content_path` that every file in
  # `file_paths` currently falls under. Looked up from the first file and
  # verified against the rest — a mismatch (e.g. the files were split
  # across separate downloads) falls through to the weaker heuristic
  # rather than deleting more than one download's worth of content.
  defp content_path_candidate([first | _] = file_paths) do
    with content_path when not is_nil(content_path) <- Acquisition.find_content_path_for(first),
         true <- File.dir?(content_path),
         true <- Enum.all?(file_paths, &String.starts_with?(&1, content_path <> "/")) do
      content_path
    else
      _ -> nil
    end
  end

  # No confirmed download boundary — only safe to guess a folder when
  # every file in the group shares one immediate parent directory. A
  # group spanning multiple directories (e.g. episodes under separate
  # season folders) has no single folder that represents just this
  # group, so it's left to `common_parent_candidate` returning `nil`,
  # which `resolve_folder_target/1` turns into `:file_only`.
  defp common_parent_candidate(file_paths) do
    file_paths
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> case do
      [dir] -> dir
      _ -> nil
    end
  end
end
