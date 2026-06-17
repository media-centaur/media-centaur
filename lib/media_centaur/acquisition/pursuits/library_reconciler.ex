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
  alias MediaCentaur.Acquisition.Pursuits.Commands.{AutoCancel, Satisfy}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Pursuits.Identity
  alias MediaCentaur.Acquisition.Pursuits.Unit
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.{Format, Library, Repo}

  # How long an episode-identity unit's grabbed release must be observed
  # landed-without-its-episode before we re-search. Longer than any
  # realistic library import so a legit pack satisfies via tmdb_match
  # first; for a genuine wrong-cour grab it just delays the pivot.
  @no_coverage_confirm_seconds 600

  @spec reconcile_active(DateTime.t()) :: :ok
  def reconcile_active(now \\ DateTime.utc_now()) do
    triples = Pursuits.list_active_units_with_context()
    present_paths = Library.list_present_file_paths()
    present_set = MapSet.new(present_paths)
    segment_index = segment_index(present_paths)

    Enum.each(triples, fn {pursuit, unit, target} ->
      case landed_file(pursuit, unit, target, present_set, segment_index) do
        {:ok, path} -> satisfy(pursuit, unit, path)
        :not_found -> reconcile_no_coverage(pursuit, unit, target, present_set, segment_index, now)
      end
    end)

    :ok
  end

  defp satisfy(%Pursuit{} = pursuit, unit, path) do
    Log.info(
      :acquisition,
      "library reconciler — file present, satisfying #{pursuit.title} (#{pursuit.id})"
    )

    Satisfy.execute(%{
      pursuit_id: pursuit.id,
      final_target_id: unit.current_target_id,
      final_release_title: Path.basename(path)
    })
  end

  # An episode-identity unit whose own episode isn't present. If the release
  # it grabbed has nonetheless landed (its files are in the library), that
  # release didn't deliver this episode → re-search. Observe-then-confirm
  # guards the import-window race (a legit pack's episodes are briefly
  # on-disk-but-unlinked); a legit pack satisfies via `tmdb_match` well
  # within the window, which clears the observation. Identity-less units
  # (movies, prowlarr_query) have no per-episode identity to re-search
  # against, so they're left as-is.
  defp reconcile_no_coverage(pursuit, unit, target, present_set, segment_index, now) do
    cond do
      not episode_identity?(pursuit, unit) ->
        :ok

      release_landed?(target, present_set, segment_index) ->
        observe_or_re_search(pursuit, unit, now)

      is_nil(unit.no_coverage_first_seen_at) ->
        :ok

      true ->
        # Nothing landed (still downloading / release gone) — reset the observation.
        {:ok, _} = Repo.update(Unit.clear_no_coverage_changeset(unit))
        :ok
    end
  end

  defp observe_or_re_search(pursuit, unit, now) do
    case unit.no_coverage_first_seen_at do
      nil ->
        {:ok, _} = Repo.update(Unit.observe_no_coverage_changeset(unit, now))
        :ok

      seen_at ->
        if DateTime.diff(now, seen_at) >= @no_coverage_confirm_seconds do
          Log.info(
            :acquisition,
            "library reconciler — #{pursuit.title} " <>
              "#{Format.episode_label(unit.season_number, unit.episode_number)}: grabbed release " <>
              "landed without this episode, re-searching"
          )

          case AutoCancel.execute(%{pursuit_id: pursuit.id, reason: :no_coverage, unit_id: unit.id}) do
            {:ok, _pursuit} ->
              :ok

            {:error, reason} ->
              Log.warning(:acquisition, "no-coverage re-search failed: #{inspect(reason)}")
          end
        else
          :ok
        end
    end
  end

  # Did the unit's grabbed release land in the library at all? Reuses the
  # coarse matchers (content-path under-dir, release-folder name) that
  # Phase 1 forbade from *satisfying* an episode-identity unit — here they
  # mean "the release is present but this episode wasn't in it."
  defp release_landed?(%Target{} = target, present_set, segment_index) do
    content_path_match(target, present_set) != :not_found or
      release_match(target, segment_index) != :not_found
  end

  defp landed_file(pursuit, unit, target, present_set, segment_index) do
    if episode_identity?(pursuit, unit) do
      # Coverage-by-contents (ADR-058): a unit with a canonical episode
      # identity is satisfied ONLY by the authoritative per-episode match.
      # The coarse fallbacks (content-path under-directory, release-folder
      # name) witness "the release landed somewhere", not "this episode
      # landed" — a wrong-cour pack (Frieren `Season 01 COMPLETE` delivering
      # E1–E28 while the unit wants E29) would otherwise satisfy the unit
      # with a file it never contained. Those fallbacks stay valid for
      # identity-less units (movies, prowlarr_query) below.
      tmdb_match(pursuit, unit)
    else
      with :not_found <- content_path_match(target, present_set),
           :not_found <- tmdb_match(pursuit, unit) do
        release_match(target, segment_index)
      end
    end
  end

  # A TMDB-tv unit carries a per-episode canonical identity; anything else
  # (movies, prowlarr_query packs) has no episode-level identity to verify
  # against, so it still relies on the coarse landing witnesses.
  defp episode_identity?(%Pursuit{tmdb_type: "tv"}, %Unit{season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode), do: true

  defp episode_identity?(_pursuit, _unit), do: false

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

  # Episode identity lives on the unit (ADR-055 retirement): the
  # reconciler runs per (pursuit, unit, target), so multi-unit tmdb
  # pursuits get an authoritative per-episode match — previously this
  # read the parent's season/episode, which is nil on plan-created
  # pursuits (campaign risk #6 residual, now closed).
  defp tmdb_match(%Pursuit{tmdb_type: "tv", tmdb_id: tmdb_id}, %Unit{
         season_number: season,
         episode_number: episode
       })
       when is_binary(tmdb_id) and is_integer(season) and is_integer(episode) do
    Library.find_present_episode(tmdb_id, season, episode)
  end

  defp tmdb_match(%Pursuit{tmdb_type: "movie", tmdb_id: tmdb_id}, _unit) when is_binary(tmdb_id) do
    Library.find_present_movie(tmdb_id)
  end

  defp tmdb_match(_pursuit, _unit), do: :not_found

  # Tries every name the pursuit knows its release by — the prowlarr
  # `release_title` and the basename of the captured `content_path`
  # (which is the on-disk release folder/file name, intact even when the
  # path prefix is the stale incomplete dir) — against the segment index.
  # First normalized hit wins.
  defp release_match(%Target{} = target, segment_index) do
    [target.release_title, content_path_name(target.content_path)]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(:not_found, fn name ->
      case Map.get(segment_index, Identity.normalize_title(name)) do
        nil -> nil
        path -> {:ok, path}
      end
    end)
  end

  defp content_path_name(path) when is_binary(path), do: Path.rootname(Path.basename(path))
  defp content_path_name(_), do: nil

  # Maps the normalized form of every path segment (ancestor directories
  # plus the leaf, indexed both with and without its extension) of each
  # present file to that file's path. Indexing ancestors — not just the
  # leaf basename — is what lets a pack's release-folder name match: the
  # folder is an ancestor of every episode file, so the release name
  # resolves in a single lookup even though it never equals an individual
  # episode basename. Indexing the leaf *with* its extension covers the
  # mirror case: an indexer that bakes the container into the release name
  # as a trailing token ("…x264-FS mkv") normalizes to a name that equals
  # the full basename, never the extension-stripped one. `put_new` keeps
  # the first path seen for a segment; any present file under the matched
  # release folder is an equally valid landing witness.
  defp segment_index(present_paths) do
    Enum.reduce(present_paths, %{}, fn path, acc ->
      path
      |> path_segments()
      |> Enum.reduce(acc, fn segment, inner ->
        Map.put_new(inner, Identity.normalize_title(segment), path)
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
        dirs ++ Enum.uniq([Path.rootname(leaf), leaf])
    end
  end
end
