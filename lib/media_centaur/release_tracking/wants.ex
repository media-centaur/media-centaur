defmodule MediaCentaur.ReleaseTracking.Wants do
  @moduledoc """
  Maintains the want ledger (ADR-056): durable per-unit acquisition
  intent derived from the calendar (`Release` rows) and closed by
  library presence or dismissal.

  `sync_item/1` is the single idempotent entry point, called from every
  seam where calendar or library state changes (refresher sweep, refresh
  commit, track-from-search, library-arrival watermark updates). Because
  the sweep runs on a short interval, the ledger is self-backfilling and
  self-healing — a missed call is corrected on the next tick, which is
  also why the schema migration ships without a data backfill.

  ## Rules (settled in the convergence campaign's Phase-0 design)

  * A want opens for a unit that is **released and not in the library**
    (TV: any episode row; movies: at least one *acquirable* date passed
    — theatrical dates never open wants).
  * `wanted_since` anchors patience: the air date for units aired before
    today, the sync time for units airing today. Never reset.
  * Satisfaction is **real library presence** (episode row exists /
    movie with matching TMDB id exists), not the calendar's `in_library`
    flag and not the item watermark — a future gap-provenance want for
    an episode *below* the watermark must not be falsely satisfied.
  * Wants are never auto-dropped when a calendar row vanishes —
    collection refreshes drop past parts and the TV fetch window moves,
    neither of which means the unit stopped being wanted. Closing a
    want is satisfaction or dismissal, nothing else.
  * Ignored items are skipped (their wants freeze; re-watching resumes
    them) and `list_open_wants/0` filters to watching items.
  """

  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Repo
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Item, Want}
  alias MediaCentaur.Search.Quality

  @doc """
  Idempotently reconciles the item's wants against its calendar and the
  library: opens wants for newly acquirable units, satisfies open wants
  whose unit is now present in the library. No-op for ignored items.
  """
  @spec sync_item(Item.t()) :: :ok
  def sync_item(%Item{status: :ignored}), do: :ok

  def sync_item(%Item{} = item) do
    releases = ReleaseTracking.list_releases_for_item(item.id)

    open_missing_wants(item, releases)
    satisfy_present_wants(item)
    :ok
  end

  @doc "Open wants for one item, season/episode ordered."
  @spec open_wants_for_item(Ecto.UUID.t()) :: [Want.t()]
  def open_wants_for_item(item_id) do
    Repo.all(
      from(w in Want,
        where: w.item_id == ^item_id and w.status == :open,
        order_by: [asc: w.season_number, asc: w.episode_number, asc: w.part_tmdb_id]
      )
    )
  end

  @doc """
  Every open want across all *watching* items — the future drop
  planner's read surface. Ignored items' wants are frozen, not listed.
  """
  @spec list_open_wants() :: [Want.t()]
  def list_open_wants do
    Repo.all(
      from(w in Want,
        join: i in Item,
        on: i.id == w.item_id,
        where: w.status == :open and i.status == :watching,
        order_by: [asc: w.air_date]
      )
    )
  end

  @doc """
  Dismisses the item's open wants that aired before `cutoff`. Returns
  the dismissed count.
  """
  @spec dismiss_before(Item.t(), Date.t()) :: non_neg_integer()
  def dismiss_before(%Item{} = item, %Date{} = cutoff) do
    {count, _} =
      Repo.update_all(
        from(w in Want,
          where:
            w.item_id == ^item.id and w.status == :open and
              not is_nil(w.air_date) and w.air_date < ^cutoff
        ),
        set: [status: :dismissed, dismissed_at: DateTime.utc_now(:second)]
      )

    count
  end

  @doc """
  Opens gap-provenance wants on an item — the media-search gap handoff
  (ADR-056 Q15): units a plan couldn't find become standing intent on
  the track. Unit specs carry `season_number`/`episode_number` (TV) or
  `part_tmdb_id` (movies) plus an optional `title`. Idempotent against
  the ledger (existing wants of any status win); returns the number of
  wants actually opened. `wanted_since` is now — the gap is fresh
  intent even when the episode aired long ago, so patience and back-off
  start from the handoff.
  """
  @spec open_gap_wants(Item.t(), [map()]) :: non_neg_integer()
  def open_gap_wants(%Item{} = item, unit_specs) when is_list(unit_specs) do
    existing_keys =
      MapSet.new(Repo.all(from(w in Want, where: w.item_id == ^item.id, select: w.unit_key)))

    now = DateTime.utc_now(:second)

    unit_specs
    |> Enum.map(fn spec ->
      %{
        season_number: Map.get(spec, :season_number),
        episode_number: Map.get(spec, :episode_number),
        part_tmdb_id: Map.get(spec, :part_tmdb_id),
        title: Map.get(spec, :title)
      }
    end)
    |> Enum.reject(fn spec ->
      key = Want.unit_key(spec.season_number, spec.episode_number, spec.part_tmdb_id)
      is_nil(key) or MapSet.member?(existing_keys, key)
    end)
    |> Enum.reduce(0, fn spec, opened ->
      insert_result =
        spec
        |> Map.merge(%{item_id: item.id, provenance: :gap, wanted_since: now})
        |> Want.create_changeset()
        |> Repo.insert(on_conflict: :nothing)

      case insert_result do
        {:ok, _want} -> opened + 1
        {:error, _changeset} -> opened
      end
    end)
  end

  @doc """
  Stamps `last_searched_at` on the given wants — called by the drop
  planner when a plan run is about to search their terms. The stamp is
  the back-off anchor (ADR-056 Q6).
  """
  @spec mark_searched([Ecto.UUID.t()], DateTime.t()) :: non_neg_integer()
  def mark_searched(want_ids, %DateTime{} = searched_at) when is_list(want_ids) do
    {count, _} =
      Repo.update_all(
        from(w in Want, where: w.id in ^want_ids),
        set: [last_searched_at: searched_at]
      )

    count
  end

  @doc """
  Dismisses the item's open wants matching the given unit keys — the
  Q5 cancel-dismisses semantics: a *user* cancelling a tracking-born
  pursuit means "stop wanting these units". Returns the dismissed
  count.
  """
  @spec dismiss_units(Ecto.UUID.t(), [String.t()]) :: non_neg_integer()
  def dismiss_units(_item_id, []), do: 0

  def dismiss_units(item_id, unit_keys) when is_list(unit_keys) do
    {count, _} =
      Repo.update_all(
        from(w in Want,
          where: w.item_id == ^item_id and w.unit_key in ^unit_keys and w.status == :open
        ),
        set: [status: :dismissed, dismissed_at: DateTime.utc_now(:second)]
      )

    count
  end

  @doc """
  Dismisses the open want matching a calendar release row, if any. Used
  by per-release dismissal so "dismiss this release" also stops the
  want. Returns the dismissed count (0 or 1).
  """
  @spec dismiss_for_release(struct()) :: non_neg_integer()
  def dismiss_for_release(release) do
    case unit_key_for_release(release) do
      nil ->
        0

      unit_key ->
        {count, _} =
          Repo.update_all(
            from(w in Want,
              where: w.item_id == ^release.item_id and w.unit_key == ^unit_key and w.status == :open
            ),
            set: [status: :dismissed, dismissed_at: DateTime.utc_now(:second)]
          )

        count
    end
  end

  # --- Opening ---

  defp open_missing_wants(item, releases) do
    existing_keys =
      MapSet.new(Repo.all(from(w in Want, where: w.item_id == ^item.id, select: w.unit_key)))

    now = DateTime.utc_now(:second)

    item
    |> want_candidates(releases)
    |> Enum.reject(&MapSet.member?(existing_keys, &1.unit_key))
    |> Enum.each(fn candidate ->
      %{
        item_id: item.id,
        season_number: candidate.season_number,
        episode_number: candidate.episode_number,
        part_tmdb_id: candidate.part_tmdb_id,
        title: candidate.title,
        air_date: candidate.air_date,
        provenance: :calendar,
        wanted_since: wanted_since_for(candidate.air_date, now)
      }
      |> Want.create_changeset()
      # A concurrent sync racing on the unique (item_id, unit_key) index
      # is benign — the want already exists, which is all we need.
      |> Repo.insert(on_conflict: :nothing)
    end)
  end

  defp want_candidates(%Item{media_type: :tv_series} = item, releases) do
    releases
    |> Enum.filter(fn release ->
      release.released and not release.in_library and
        is_integer(release.season_number) and is_integer(release.episode_number) and
        not dismissed_by_cutoff?(item, release.air_date)
    end)
    |> Enum.uniq_by(&{&1.season_number, &1.episode_number})
    |> Enum.map(fn release ->
      %{
        unit_key: Want.unit_key(release.season_number, release.episode_number, nil),
        season_number: release.season_number,
        episode_number: release.episode_number,
        part_tmdb_id: nil,
        title: release.title,
        air_date: release.air_date
      }
    end)
  end

  defp want_candidates(%Item{media_type: :movie} = item, releases) do
    releases
    |> Enum.filter(fn release ->
      release.released and not release.in_library and
        ReleaseTracking.acquirable_release_type?(release.release_type)
    end)
    |> Enum.flat_map(fn release ->
      case resolve_part_tmdb_id(release, item) do
        nil -> []
        part_tmdb_id -> [{part_tmdb_id, release}]
      end
    end)
    |> Enum.group_by(fn {part_tmdb_id, _release} -> part_tmdb_id end)
    |> Enum.map(fn {part_tmdb_id, rows} ->
      # One want per film, anchored on its earliest acquirable date.
      release =
        rows
        |> Enum.map(fn {_part, release} -> release end)
        |> Enum.min_by(& &1.air_date, Date, fn -> nil end)

      %{
        unit_key: Want.unit_key(nil, nil, part_tmdb_id),
        season_number: nil,
        episode_number: nil,
        part_tmdb_id: part_tmdb_id,
        title: release.title,
        air_date: release.air_date
      }
    end)
    |> Enum.reject(&dismissed_by_cutoff?(item, &1.air_date))
  end

  # Movie rows carry their film's own TMDB id since the part_tmdb_id
  # column landed. Legacy rows: a *typed* row (theatrical/digital/...)
  # is a solo-movie row, so the item's tmdb_id IS the film's id; an
  # untyped legacy row is a collection part whose id we cannot know —
  # skip it and let the next refresher cycle stamp the column.
  defp resolve_part_tmdb_id(%{part_tmdb_id: part}, _item) when is_integer(part), do: part
  defp resolve_part_tmdb_id(%{release_type: type}, item) when is_binary(type), do: item.tmdb_id
  defp resolve_part_tmdb_id(_release, _item), do: nil

  defp dismissed_by_cutoff?(%Item{dismiss_released_before: nil}, _air_date), do: false
  defp dismissed_by_cutoff?(_item, nil), do: false

  defp dismissed_by_cutoff?(%Item{dismiss_released_before: cutoff}, air_date) do
    Date.before?(air_date, cutoff)
  end

  # Patience anchors at the air date for units aired before today (no
  # patience restart when the ledger first sees an old unit), at sync
  # time for units airing today (parity with the old arm-at-sweep
  # behavior).
  defp wanted_since_for(nil, now), do: now

  defp wanted_since_for(air_date, now) do
    if Date.before?(air_date, Date.utc_today()) do
      DateTime.new!(air_date, ~T[00:00:00], "Etc/UTC")
    else
      now
    end
  end

  # --- Satisfaction ---

  defp satisfy_present_wants(item) do
    case open_wants_for_item(item.id) do
      [] -> :ok
      open_wants -> satisfy_wants(item, open_wants)
    end
  end

  defp satisfy_wants(%Item{media_type: :tv_series} = item, open_wants) do
    case present_episodes(item) do
      empty when empty == %{} ->
        :ok

      present ->
        Enum.each(open_wants, fn want ->
          case Map.get(present, {want.season_number, want.episode_number}) do
            nil -> :ok
            episode_id -> satisfy!(want, quality_for_container(:episode, episode_id))
          end
        end)
    end
  end

  defp satisfy_wants(%Item{media_type: :movie}, open_wants) do
    present = present_movies(open_wants)

    Enum.each(open_wants, fn want ->
      case Map.get(present, want.part_tmdb_id) do
        nil -> :ok
        movie_id -> satisfy!(want, quality_for_container(:movie, movie_id))
      end
    end)
  end

  defp present_episodes(%Item{library_container_type: :tv_series, library_container_id: id})
       when is_binary(id) do
    Map.new(
      Repo.all(
        from(e in Library.Episode,
          join: s in Library.Season,
          on: e.season_id == s.id,
          where: s.tv_series_id == ^id,
          select: {s.season_number, e.episode_number, e.id}
        )
      ),
      fn {season, episode, episode_id} -> {{season, episode}, episode_id} end
    )
  end

  defp present_episodes(_unlinked_item), do: %{}

  defp present_movies(open_wants) do
    part_ids =
      open_wants
      |> Enum.map(& &1.part_tmdb_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    if part_ids == [] do
      %{}
    else
      Map.new(
        Repo.all(
          from(ext in Library.ExternalId,
            where:
              ext.owner_type == :movie and ext.source == "tmdb" and
                ext.external_id in ^part_ids,
            select: {ext.external_id, ext.owner_id}
          )
        ),
        fn {external_id, movie_id} -> {String.to_integer(external_id), movie_id} end
      )
    end
  end

  defp satisfy!(want, quality) do
    Repo.update_all(
      from(w in Want, where: w.id == ^want.id and w.status == :open),
      set: [
        status: :satisfied,
        satisfied_at: DateTime.utc_now(:second),
        satisfied_quality: quality
      ]
    )
  end

  # Best-effort quality of the file that satisfied the unit, read off
  # the playable chain and classified from the filename. Nil when the
  # chain is incomplete or the name carries no quality marker — the
  # column is a hook for the future upgrades campaign, not a guarantee.
  defp quality_for_container(container_type, container_id) do
    playable_item_id =
      Repo.one(
        from(p in Library.PlayableItem,
          where: p.container_type == ^container_type and p.container_id == ^container_id,
          order_by: [asc: p.position],
          limit: 1,
          select: p.id
        )
      )

    with id when is_binary(id) <- playable_item_id,
         path when is_binary(path) <- Library.playable_file_path(id),
         quality when not is_nil(quality) <- Quality.parse(Path.basename(path)) do
      Atom.to_string(quality)
    else
      _ -> nil
    end
  end

  defp unit_key_for_release(release) do
    part_tmdb_id =
      case Repo.get(Item, release.item_id) do
        nil -> nil
        item -> resolve_part_tmdb_id(release, item)
      end

    Want.unit_key(release.season_number, release.episode_number, part_tmdb_id)
  end
end
