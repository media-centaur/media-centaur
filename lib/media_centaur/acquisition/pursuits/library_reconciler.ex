defmodule MediaCentaur.Acquisition.Pursuits.LibraryReconciler do
  @moduledoc """
  Safety-net that satisfies an active pursuit once the file it was
  chasing has landed in the library.

  The primary completion path is the PubSub-driven chain:

      Pipeline.Ingest.broadcast → Pursuits.InboundListener →
        Pursuits.IdentityVerifier (Oban) → Commands.Satisfy

  Every link in that chain is in-memory and best-effort. If any step
  drops the message (supervisor restart between broadcast and Oban
  insert, listener crash before `dispatch/1` runs, etc.) the pursuit is
  orphaned indefinitely — active, with the file it was chasing already
  on disk. It is also keyed entirely on TMDB id, so it never fires for a
  manual `prowlarr_query` grab.

  This reconciler closes both gaps. For every active pursuit it resolves
  the landed file by trying, in order of authority:

    1. **Content path** — the download's `content_path`, captured on the
       `Target` by `DownloadIdentity`. The pipeline carries this path
       unchanged into the library, so an exact (or under-directory) match
       against the present `WatchedFile` paths is decisive and survives
       the download client dropping the completed torrent.
    2. **TMDB id** — for TMDB-recipe pursuits, `(tmdb_id[, season,
       episode])` against the library. Authoritative; no title-matching.
    3. **Release name** — the path-less fallback for `prowlarr_query`
       pursuits (and any grab from before content paths were captured):
       the normalized release name — both the `Target.release_title` and
       the basename of the (possibly stale) `content_path` — matched
       against **every path segment** of the present files, not just the
       leaf basename. A multi-file pack imports its episodes under a
       top-level folder named after the release; that folder survives as
       an *ancestor segment* of every episode path, so the release name
       matches it even though it can never equal a per-episode basename.
       This is the same normalization `QueueMatcher` uses to pair a
       pursuit with its live download. An exact normalized match against
       a segment only — a miss leaves the pursuit active (safe; the user
       can cancel), where a false positive would wrongly close a pursuit
       whose file isn't present. Release names are long and specific, so
       they never collide with generic ancestor folders.

  Invoked by `Pursuits.Watcher` once per tick. Worst-case satisfaction
  latency for this safety-net is one tick; the primary PubSub path
  remains the seconds-latency happy case for TMDB pursuits.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Commands.Satisfy
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.QueueMatcher
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Library

  @spec reconcile_active() :: :ok
  def reconcile_active do
    pairs = Pursuits.list_active_with_current_targets()
    present_paths = Library.list_present_file_paths()
    present_set = MapSet.new(present_paths)
    segment_index = segment_index(present_paths)

    Enum.each(pairs, fn {pursuit, target} ->
      case landed_file(pursuit, target, present_set, segment_index) do
        {:ok, path} -> satisfy(pursuit, path)
        :not_found -> :ok
      end
    end)

    :ok
  end

  defp satisfy(%Pursuit{} = pursuit, path) do
    Log.info(
      :acquisition,
      "library reconciler — file present, satisfying #{pursuit.title} (#{pursuit.id})"
    )

    Satisfy.execute(%{
      pursuit_id: pursuit.id,
      final_target_id: pursuit.current_target_id,
      final_release_title: Path.basename(path)
    })
  end

  defp landed_file(pursuit, target, present_set, segment_index) do
    with :not_found <- content_path_match(target, present_set),
         :not_found <- tmdb_match(pursuit) do
      release_match(target, segment_index)
    end
  end

  defp content_path_match(%Target{content_path: content_path}, present_set)
       when is_binary(content_path) do
    cond do
      MapSet.member?(present_set, content_path) ->
        {:ok, content_path}

      under = Enum.find(present_set, &String.starts_with?(&1, content_path <> "/")) ->
        {:ok, under}

      true ->
        :not_found
    end
  end

  defp content_path_match(_target, _present_set), do: :not_found

  defp tmdb_match(%Pursuit{
         tmdb_type: "tv",
         tmdb_id: tmdb_id,
         season_number: season,
         episode_number: episode
       })
       when is_binary(tmdb_id) and is_integer(season) and is_integer(episode) do
    Library.find_present_episode(tmdb_id, season, episode)
  end

  defp tmdb_match(%Pursuit{tmdb_type: "movie", tmdb_id: tmdb_id}) when is_binary(tmdb_id) do
    Library.find_present_movie(tmdb_id)
  end

  defp tmdb_match(_pursuit), do: :not_found

  # Tries every name the pursuit knows its release by — the prowlarr
  # `release_title` and the basename of the captured `content_path`
  # (which is the on-disk release folder/file name, intact even when the
  # path prefix is the stale incomplete dir) — against the segment index.
  # First normalized hit wins.
  defp release_match(%Target{} = target, segment_index) do
    [target.release_title, content_path_name(target.content_path)]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(:not_found, fn name ->
      case Map.get(segment_index, QueueMatcher.normalize_title(name)) do
        nil -> nil
        path -> {:ok, path}
      end
    end)
  end

  defp content_path_name(path) when is_binary(path), do: Path.rootname(Path.basename(path))
  defp content_path_name(_), do: nil

  # Maps the normalized form of every path segment (ancestor directories
  # plus the extension-stripped leaf) of each present file to that file's
  # path. Indexing ancestors — not just the leaf basename — is what lets a
  # pack's release-folder name match: the folder is an ancestor of every
  # episode file, so the release name resolves in a single lookup even
  # though it never equals an individual episode basename. `put_new` keeps
  # the first path seen for a segment; any present file under the matched
  # release folder is an equally valid landing witness.
  defp segment_index(present_paths) do
    Enum.reduce(present_paths, %{}, fn path, acc ->
      path
      |> path_segments()
      |> Enum.reduce(acc, fn segment, inner ->
        Map.put_new(inner, QueueMatcher.normalize_title(segment), path)
      end)
    end)
  end

  defp path_segments(path) do
    path
    |> Path.split()
    |> Enum.reject(&(&1 in ["/", ""]))
    |> case do
      [] ->
        []

      parts ->
        {dirs, [leaf]} = Enum.split(parts, length(parts) - 1)
        dirs ++ [Path.rootname(leaf)]
    end
  end
end
