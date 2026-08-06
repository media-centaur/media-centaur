defmodule MediaCentaur.Library.Relink do
  @moduledoc """
  Relink-on-move: recognising that a newly-seen file is one the library
  already tracks at a different path, and re-pointing the existing rows
  instead of importing a duplicate entity.

  Pairs with `Library.MoveMatcher`, which owns the *decision* (does this
  path+size correspond to a file we know?). This module owns the
  *consequence* — rewriting `WatchedFile`, `ExtraFile` and the
  `FilePresence` ledger to the new location, in one transaction, and
  telling the rest of the system which entities moved.

  A match is acted on only when the old path is actually gone from disk.
  That is what distinguishes a move from a copy: if both paths exist, the
  new one is a genuinely new file and belongs in the import pipeline.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{ExtraFile, FilePresence, Files, Helpers, MoveMatcher, WatchedFile}
  alias MediaCentaur.Repo

  @doc """
  Given newly-seen `{path, size}` pairs under `new_media_dir`, re-points
  any that `MoveMatcher` recognises as a moved file.

  The `:exists?` option (default `&File.regular?/1`) is the move-vs-copy
  test. Returns `%{relinked: [path], still_new: [path]}`; the caller
  dispatches only `still_new` to the import pipeline.
  """
  @spec moved_files([{String.t(), non_neg_integer() | nil}], String.t(), keyword()) ::
          %{relinked: [String.t()], still_new: [String.t()]}
  def moved_files(new_files, new_media_dir, opts \\ [])

  def moved_files([], _new_media_dir, _opts), do: %{relinked: [], still_new: []}

  def moved_files(new_files, new_media_dir, opts) do
    exists? = Keyword.get(opts, :exists?, &File.regular?/1)

    sizes = new_files |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    candidates = FilePresence.list_relink_candidates(sizes)

    {moves, still_new} =
      Enum.reduce(new_files, {[], []}, fn {path, size}, {moves, still_new} ->
        case MoveMatcher.match(%{path: path, media_dir: new_media_dir, size: size}, candidates) do
          {:move, old} ->
            # Old path still on disk → a copy, not a move. Let it import.
            if exists?.(old.file_path),
              do: {moves, [path | still_new]},
              else: {[{old, path, size} | moves], still_new}

          :no_match ->
            {moves, [path | still_new]}
        end
      end)

    %{
      relinked: moves |> Enum.reverse() |> perform(new_media_dir),
      still_new: Enum.reverse(still_new)
    }
  end

  defp perform([], _new_media_dir), do: []

  defp perform(moves, new_media_dir) do
    now = DateTime.utc_now()
    now_seconds = DateTime.truncate(now, :second)

    {:ok, {relinked, entity_ids}} =
      Repo.transaction(fn ->
        Enum.reduce(moves, {[], []}, fn {old, new_path, new_size}, {paths, ids} ->
          # Resolve the affected entities *before* the rewrite — after it,
          # the old path no longer matches anything.
          moved_entity_ids =
            [old.file_path]
            |> Files.list_by_paths()
            |> Enum.map(&Files.top_level_entity_id/1)
            |> Enum.reject(&is_nil/1)

          Repo.update_all(from(w in WatchedFile, where: w.file_path == ^old.file_path),
            set: [file_path: new_path, media_dir: new_media_dir]
          )

          Repo.update_all(from(ef in ExtraFile, where: ef.file_path == ^old.file_path),
            set: [file_path: new_path, media_dir: new_media_dir]
          )

          Repo.update_all(from(p in FilePresence, where: p.id == ^old.id),
            set: [
              file_path: new_path,
              media_dir: new_media_dir,
              size: new_size,
              last_seen_at: now,
              updated_at: now_seconds
            ]
          )

          {[new_path | paths], ids ++ moved_entity_ids}
        end)
      end)

    Helpers.broadcast_entities_changed(Enum.uniq(entity_ids))
    Enum.reverse(relinked)
  end
end
