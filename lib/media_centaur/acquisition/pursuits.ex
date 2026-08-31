defmodule MediaCentaur.Acquisition.Pursuits do
  @moduledoc """
  Read-side queries over the pursuit aggregate.

  Write-side operations live in `Acquisition.Pursuits.Commands.*`. This
  module is intentionally read-only — it never mutates state, never
  broadcasts, never enqueues jobs. Callers that want to change the
  world go through a command. ViewModel assemblers also live here
  because shaping rows for the UI is a read concern.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.{Event, Identity, Pursuit, State, Unit, UnitState, Units}
  alias MediaCentaur.Acquisition.Pursuits.Recipe, as: PursuitRecipe
  alias MediaCentaur.Acquisition.{QueueMatcher, Target}
  alias MediaCentaur.Search.QueryBuilder

  alias MediaCentaur.Acquisition.ViewModels.{
    PursuitHeader,
    PursuitRow,
    PursuitStatus,
    Timeline,
    TimelineEntry,
    UnitBoard
  }

  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  @spec fetch(Ecto.UUID.t()) :: {:ok, Pursuit.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Pursuit, id) do
      nil -> {:error, :not_found}
      %Pursuit{} = pursuit -> {:ok, pursuit}
    end
  end

  @doc "Lists every in-flight (`active`) pursuit, newest-updated first."
  @spec list_active() :: [Pursuit.t()]
  def list_active do
    Pursuit
    |> where([p], p.state in ^State.in_flight())
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Every `active` unit of every in-flight pursuit, paired with its parent
  pursuit and its current target, as `[{pursuit, unit, target_or_nil}]`
  in three batched queries total. Used by `Pursuits.Watcher` so its
  per-tick pass cost is constant in the unit count (ADR-055 — the
  watcher loop runs per unit, not per pursuit).
  """
  @spec list_active_units_with_context() :: [{Pursuit.t(), Unit.t(), Target.t() | nil}]
  def list_active_units_with_context do
    pursuits = list_active()
    units_by_pursuit = Units.for_pursuits(Enum.map(pursuits, & &1.id))

    active_units =
      Enum.flat_map(pursuits, fn pursuit ->
        units_by_pursuit
        |> Map.get(pursuit.id, [])
        |> Enum.filter(&UnitState.in_flight?(&1.state))
        |> Enum.map(&{pursuit, &1})
      end)

    targets =
      active_units
      |> Enum.map(fn {_pursuit, unit} -> unit.current_target_id end)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    Enum.map(active_units, fn {pursuit, unit} ->
      {pursuit, unit, Map.get(targets, unit.current_target_id)}
    end)
  end

  @doc """
  Returns a map of `pursuit_id => latest_release_title` for every pursuit
  in `pursuit_ids` that has a target with a non-nil `release_title`.
  Pursuits with no acquired releases are absent from the map.

  Used by `Pursuits.Watcher` so the per-tick pass does one batched query
  for release-title lookups rather than one query per pursuit.
  """
  @spec latest_release_titles_for([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => String.t()}
  def latest_release_titles_for([]), do: %{}

  def latest_release_titles_for(pursuit_ids) when is_list(pursuit_ids) do
    Target
    |> where([t], t.pursuit_id in ^pursuit_ids and not is_nil(t.release_title))
    |> order_by([t], desc: t.inserted_at)
    |> select([t], {t.pursuit_id, t.release_title})
    |> Repo.all()
    # Newest-first ordering + `put_new` keeps only the latest release
    # title per pursuit_id without an O(n log n) group_by.
    |> Enum.reduce(%{}, fn {pid, title}, acc -> Map.put_new(acc, pid, title) end)
  end

  @typedoc "TMDB release identity: `{tmdb_id, tmdb_type, season_number, episode_number}`."
  @type release_key :: {String.t(), String.t(), integer() | nil, integer() | nil}

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple →
  `{pursuit, current_target | nil}`.

  Used by the upcoming-zone renderer to decorate each release card with
  its acquisition status without N+1ing the DB.
  """
  @spec statuses_for_releases([release_key()]) :: %{release_key() => {Pursuit.t(), Target.t() | nil}}
  def statuses_for_releases([]), do: %{}

  def statuses_for_releases(keys) when is_list(keys) do
    # SQL-side tuple filter: build an OR-chain of exact-tuple matches so
    # the DB returns only requested rows. Prior implementation widened
    # the WHERE to `tmdb_id in ^ids and tmdb_type in ^types`, then
    # dropped non-requested tuples in BEAM — a wasted round-trip when a
    # series has many pursuits but only a few requested episodes.
    predicate =
      Enum.reduce(keys, dynamic(false), fn key, acc ->
        dynamic([p], ^acc or ^key_predicate(key))
      end)

    pursuits =
      Pursuit
      |> where([p], p.recipe_type == "tmdb")
      |> where(^predicate)
      |> Repo.all()

    # Current targets live on the units (ADR-055); auto-grab pursuits
    # are single-unit, so the first unit's pointer is the pursuit's.
    units_by_pursuit = Units.for_pursuits(Enum.map(pursuits, & &1.id))

    current_target_id = fn pursuit ->
      case Map.get(units_by_pursuit, pursuit.id, []) do
        [unit | _] -> unit.current_target_id
        [] -> nil
      end
    end

    target_ids = pursuits |> Enum.map(current_target_id) |> Enum.reject(&is_nil/1)
    targets_by_id = fetch_targets_by_id(target_ids)

    Map.new(pursuits, fn pursuit ->
      key = {pursuit.tmdb_id, pursuit.tmdb_type, pursuit.season_number, pursuit.episode_number}
      target = Map.get(targets_by_id, current_target_id.(pursuit))
      {key, {pursuit, target}}
    end)
  end

  # One dynamic per nil/non-nil shape so Ecto sees only top-level
  # `^interpolation`s in the outer `dynamic`.
  defp key_predicate({id, type, nil, nil}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        is_nil(p.season_number) and is_nil(p.episode_number)
    )
  end

  defp key_predicate({id, type, season, nil}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        p.season_number == ^season and is_nil(p.episode_number)
    )
  end

  defp key_predicate({id, type, nil, episode}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        is_nil(p.season_number) and p.episode_number == ^episode
    )
  end

  defp key_predicate({id, type, season, episode}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        p.season_number == ^season and p.episode_number == ^episode
    )
  end

  @doc "Lists active pursuits as `PursuitRow` view-models for the Downloads index."
  @spec list_active_rows() :: [PursuitRow.t()]
  def list_active_rows, do: list_rows(:active)

  @doc """
  Lists pursuits as `PursuitRow` view-models, filtered by lifecycle bucket.

  - `:active`       — `state == :active` (in-flight; may or may not be awaiting decision)
  - `:failed`       — `state == :exhausted`
  - `:cancelled`    — `state == :cancelled`
  - `:succeeded`    — `state == :satisfied`
  - `:all_terminal` — every non-in-flight state (satisfied + exhausted + cancelled)

  Ordered newest-updated first. Each row pairs the pursuit with its
  `current_target` via `fetch_targets_by_id/1`, so `release_title` and
  `target_status` come from the most recent attempt.

  `limit:` caps the read (newest first) — the History window and the
  Incoming ledger glimpse only ever show a slice, so neither pays for
  the whole terminal table.

  `search:` narrows in SQL by case-insensitive substring (SQLite `LIKE`
  semantics — ASCII case folding) against the pursuit title or any of
  the pursuit's targets' `release_title`. LIKE wildcards in the needle
  are treated as literals. Searching the query keeps a bounded `limit:`
  window honest — the needle is matched against the whole archive, not
  the loaded slice.
  """
  @spec list_rows(:active | :failed | :cancelled | :succeeded | :all_terminal,
          limit: pos_integer(),
          search: String.t()
        ) :: [PursuitRow.t()]
  def list_rows(filter, opts \\ []) do
    states = states_for_filter(filter)

    pursuits =
      from(p in Pursuit, as: :pursuit)
      |> where([p], p.state in ^states)
      |> apply_search(opts[:search])
      |> order_by([p], desc: p.updated_at)
      |> maybe_limit(opts[:limit])
      |> Repo.all()

    units_by_pursuit = Units.for_pursuits(Enum.map(pursuits, & &1.id))

    current_targets =
      units_by_pursuit
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    pending_paths = Review.pending_file_paths()

    Enum.map(pursuits, fn pursuit ->
      units = Map.get(units_by_pursuit, pursuit.id, [])
      # The row renders the lead thread (Units.lead_of/1); per-unit
      # drill-down lands with campaign Phase 1c.
      lead_unit = Units.lead_of(units)
      target = lead_unit && Map.get(current_targets, lead_unit.current_target_id)

      build_row(
        pursuit,
        units,
        lead_unit,
        target,
        download_location(target, pending_paths),
        current_targets
      )
    end)
  end

  # Resolves the post-download lifecycle location of a target's file as a
  # batched membership test (no per-pursuit query). `:in_review` when the
  # captured `content_path` is sitting in the review queue, else `:none`.
  # Library-landing isn't checked here — the reconciler satisfies a landed
  # pursuit, so it leaves the active list rather than rendering a stage.
  defp download_location(%Target{content_path: content_path}, pending_paths)
       when is_binary(content_path) do
    if MapSet.member?(pending_paths, content_path), do: :in_review, else: :none
  end

  defp download_location(_target, _pending_paths), do: :none

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, cap), do: limit(query, ^cap)

  defp apply_search(query, search) when search in [nil, ""], do: query

  defp apply_search(query, search) when is_binary(search) do
    pattern = "%" <> escape_like(search) <> "%"

    release_match =
      from(t in Target,
        where:
          t.pursuit_id == parent_as(:pursuit).id and
            fragment("? LIKE ? ESCAPE '\\'", t.release_title, ^pattern)
      )

    where(
      query,
      [p],
      fragment("? LIKE ? ESCAPE '\\'", p.title, ^pattern) or exists(release_match)
    )
  end

  # LIKE metacharacters in the user's needle are literals, not wildcards.
  defp escape_like(needle) do
    String.replace(needle, ["\\", "%", "_"], fn char -> "\\" <> char end)
  end

  defp states_for_filter(:active), do: State.in_flight()
  defp states_for_filter(:failed), do: ["exhausted"]
  defp states_for_filter(:cancelled), do: ["cancelled"]
  defp states_for_filter(:succeeded), do: ["satisfied"]
  defp states_for_filter(:all_terminal), do: State.terminal()

  @doc "Returns a `PursuitHeader` view-model for the detail page."
  @spec header_for(Ecto.UUID.t()) :: {:ok, PursuitHeader.t()} | {:error, :not_found}
  def header_for(id) do
    case fetch(id) do
      {:ok, pursuit} -> {:ok, header_from(pursuit)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Like `header_for/1` but skips the DB read — for callers that already
  hold the `%Pursuit{}`. Used by `load_pursuit_detail/1` to assemble all
  three view-models from one fetch instead of three.
  """
  @spec header_from(Pursuit.t()) :: PursuitHeader.t()
  def header_from(%Pursuit{} = pursuit), do: build_header(pursuit)

  @doc """
  Returns the full `PursuitStatus` view-model for the detail page —
  identity + current activity + available manual triggers + staleness.
  """
  @spec status_for(Ecto.UUID.t()) :: {:ok, PursuitStatus.t()} | {:error, :not_found}
  def status_for(id) do
    case fetch(id) do
      {:error, :not_found} = error -> error
      {:ok, pursuit} -> {:ok, status_from(pursuit)}
    end
  end

  @doc """
  Refreshes only the queue-derived fields of an existing `PursuitStatus`
  view-model against a fresh queue snapshot, without re-reading the
  pursuit, target, or last-event row from the DB.

  Used on the LiveView's queue-tick path (1.5 s when subscribed) so the
  modal's download progress updates without firing three Repo queries on
  every snapshot. The static block (state, recipe, staleness, last
  activity) is unchanged — pursuit-lifecycle events still trigger a
  full reload via `status_for/1`.
  """
  @spec refresh_status_download(PursuitStatus.t(), [MediaCentaur.Downloads.QueueItem.t()]) ::
          PursuitStatus.t()
  def refresh_status_download(%PursuitStatus{pursuit: nil} = status, _items), do: status

  def refresh_status_download(%PursuitStatus{} = status, queue_items) when is_list(queue_items) do
    queue_item = find_queue_match(status.target, queue_items)
    download = QueueMatcher.to_download(queue_item)

    {current_action, next_step, actions} =
      PursuitStatus.derive(status.pursuit, status.unit, status.target, queue_item)

    {current_action, downloads, downloads_done} =
      PursuitStatus.compose_downloads(
        current_action,
        all_downloads(status.pursuit, status.target, queue_items)
      )

    if status.download == download and status.downloads == downloads and
         status.downloads_done == downloads_done do
      status
    else
      %{
        status
        | current_action: current_action,
          next_step: next_step,
          available_actions: actions,
          download: download,
          downloads: downloads,
          downloads_done: downloads_done
      }
    end
  end

  @doc """
  Like `status_for/1` but skips the DB read for the pursuit — for callers
  that already hold the `%Pursuit{}`. Uses the cached `QueueMonitor`
  snapshot for the live download field; pass a queue items list as the
  second argument to reuse a snapshot the caller already has (saves an
  ETS read on the LiveView's queue-tick path).

  The returned struct stashes the loaded pursuit + target so
  `refresh_status_download/2` can re-derive the dynamic fields without
  a second DB round-trip when a queue snapshot ticks in.
  """
  @spec status_from(Pursuit.t(), [MediaCentaur.Downloads.QueueItem.t()] | :persistent_term) ::
          PursuitStatus.t()
  def status_from(%Pursuit{} = pursuit, queue_items \\ :persistent_term) do
    unit = lead_unit(pursuit)
    target = (unit && Units.current_target(unit)) || nil
    queue_item = find_queue_match(target, queue_items)
    location = download_location(target, Review.pending_file_paths())

    {current_action, next_step, actions} =
      PursuitStatus.derive(pursuit, unit, target, queue_item, location)

    {current_action, downloads, downloads_done} =
      PursuitStatus.compose_downloads(current_action, all_downloads(pursuit, target, queue_items))

    last_activity_at = latest_event_at(pursuit.id)

    %PursuitStatus{
      pursuit_id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      origin: String.to_existing_atom(pursuit.origin),
      recipe: PursuitRecipe.from(pursuit),
      search_queries: search_queries_for(pursuit),
      criteria_summary: summarize_criteria(pursuit.criteria),
      current_action: current_action,
      next_step: next_step,
      download: QueueMatcher.to_download(queue_item),
      downloads: downloads,
      downloads_done: downloads_done,
      staleness: staleness_for(last_activity_at),
      last_activity_at: last_activity_at,
      available_actions: actions,
      pursuit: pursuit,
      unit: unit,
      target: target
    }
  end

  # The thread the detail modal renders — Units.lead_of/1 is the single
  # definition of "which unit a pursuit-scoped surface acts on" (ADR-055).
  defp lead_unit(%Pursuit{} = pursuit), do: Units.lead(pursuit.id)

  # Every distinct current target's live queue match, lead target first —
  # a composite pursuit has several torrents in flight at once and the
  # modal must show them all (same plural rule as the index pairing).
  defp all_downloads(%Pursuit{} = pursuit, lead_target, queue_items) do
    units = Units.for_pursuit(pursuit.id)

    targets =
      units
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    units
    |> Enum.map(&Map.get(targets, &1.current_target_id))
    |> Enum.reject(&is_nil/1)
    |> then(fn list -> if lead_target, do: [lead_target | list], else: list end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.flat_map(fn %Target{} = t ->
      case find_queue_match(t, queue_items) do
        nil ->
          []

        item ->
          [%{item_id: item.id, download: QueueMatcher.to_download(item), release_title: t.release_title}]
      end
    end)
    # Several targets can resolve to ONE torrent (a re-pick keeps the
    # durable infohash, so the old seeking target still matches) — one
    # bar per torrent, preferring the entry that knows its release name.
    |> Enum.sort_by(&is_nil(&1.release_title))
    |> Enum.uniq_by(& &1.item_id)
    |> Enum.map(&Map.delete(&1, :item_id))
  end

  @doc """
  Builds the `UnitBoard` view-model for a pursuit's per-unit drill-down
  (ADR-055): one row per unit in display order, each paired with the
  release its current target carries. Two queries total (units +
  batched targets).
  """
  @spec unit_board_for(Pursuit.t()) :: UnitBoard.t()
  def unit_board_for(%Pursuit{} = pursuit) do
    units = Units.for_pursuit(pursuit.id)

    targets =
      units
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    rows =
      Enum.map(units, fn unit ->
        target = Map.get(targets, unit.current_target_id)
        awaiting? = UnitState.awaiting_decision?(unit)

        %UnitBoard.Row{
          id: unit.id,
          label: unit.label || unit.query || pursuit.title,
          state: unit_state_to_atom(unit.state),
          season_number: unit.season_number,
          release_title: target && target.release_title,
          awaiting_decision?: awaiting?,
          # Awaiting units pivot through the decision card, not the
          # board — offering both would race the user against themselves.
          actionable?: unit.state == "active" and not awaiting?
        }
      end)

    %UnitBoard{
      pursuit_id: pursuit.id,
      wanted: max(length(units), 1),
      satisfied: Enum.count(units, &(&1.state == "satisfied")),
      units: rows,
      groups: UnitBoard.group_rows(rows)
    }
  end

  defp unit_state_to_atom("active"), do: :active
  defp unit_state_to_atom("satisfied"), do: :satisfied
  defp unit_state_to_atom("exhausted"), do: :exhausted
  defp unit_state_to_atom("cancelled"), do: :cancelled

  @doc "Returns a `Timeline` view-model containing every event for a pursuit."
  @spec timeline_for(Ecto.UUID.t()) :: Timeline.t()
  def timeline_for(pursuit_id) do
    entries =
      pursuit_id
      |> events_for()
      |> Enum.map(&TimelineEntry.from_event/1)

    %Timeline{pursuit_id: pursuit_id, entries: entries}
  end

  @doc """
  Returns events for a pursuit, newest first. Empty list for unknown
  pursuit_id — events with nilified `pursuit_id` are not surfaced here.
  """
  @spec events_for(Ecto.UUID.t()) :: [Event.t()]
  def events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  Returns active pursuits whose TMDB recipe matches the given map.

  Accepts `%{tmdb_id, tmdb_type}` and optional `:season_number` /
  `:episode_number`. TV pursuits without a season pin (e.g.,
  season-pack pursuits) match any episode for that series; movie
  pursuits match by `tmdb_id` alone.

  Only matches pursuits with `recipe_type = "tmdb"` — query-recipe
  pursuits have no TMDB metadata to match against. Used by
  `Pursuits.InboundListener` to dispatch identity verification when a
  file lands for a tracked target.
  """
  @spec find_active_for_target(map()) :: [Pursuit.t()]
  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "movie"}) when is_binary(tmdb_id) do
    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "movie")
    |> Repo.all()
  end

  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "tv"} = target) when is_binary(tmdb_id) do
    season = Map.get(target, :season_number)
    episode = Map.get(target, :episode_number)

    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "tv")
    |> match_season(season)
    |> match_episode(episode)
    |> Repo.all()
  end

  def find_active_for_target(_), do: []

  defp match_season(query, nil), do: query

  defp match_season(query, season) do
    where(query, [p], is_nil(p.season_number) or p.season_number == ^season)
  end

  defp match_episode(query, nil), do: query

  defp match_episode(query, episode) do
    where(query, [p], is_nil(p.episode_number) or p.episode_number == ^episode)
  end

  @doc """
  Returns the target the pursuit's lead unit is currently chasing, if
  any (ADR-055 — targets are unit-scoped; this is the pursuit-level
  convenience used by detail assembly).
  """
  @spec current_target(Pursuit.t()) :: Target.t() | nil
  def current_target(%Pursuit{} = pursuit) do
    case lead_unit(pursuit) do
      nil -> nil
      %Unit{} = unit -> Units.current_target(unit)
    end
  end

  @doc """
  True when any of the pursuit's units is awaiting a user decision —
  the pursuit-level read of the unit-level flag (ADR-055).
  """
  @spec awaiting_decision?(Pursuit.t()) :: boolean()
  def awaiting_decision?(%Pursuit{} = pursuit) do
    Unit
    |> where([u], u.pursuit_id == ^pursuit.id and not is_nil(u.awaiting_decision_at))
    |> Repo.exists?()
  end

  @doc """
  Returns the most recently inserted target linked to a pursuit
  (regardless of which is the pursuit's `current_target_id` — useful
  for history queries that want "the latest attempt").
  """
  @spec latest_target(Ecto.UUID.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def latest_target(pursuit_id) do
    target =
      Target
      |> where([t], t.pursuit_id == ^pursuit_id)
      |> order_by([t], desc: t.inserted_at)
      |> limit(1)
      |> Repo.one()

    case target do
      nil -> {:error, :not_found}
      %Target{} = target -> {:ok, target}
    end
  end

  @doc "Returns all targets for a pursuit, newest-inserted first."
  @spec targets_for(Ecto.UUID.t()) :: [Target.t()]
  def targets_for(pursuit_id) do
    Target
    |> where([t], t.pursuit_id == ^pursuit_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  # --- ViewModel assembly ----------------------------------------------------

  defp fetch_targets_by_id([]), do: %{}

  defp fetch_targets_by_id(ids) do
    Target
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(fn target -> {target.id, target} end)
  end

  defp build_row(%Pursuit{} = pursuit, units, lead_unit, target, location, current_targets) do
    {release_title, target_status, torrent_hash} =
      case target do
        %Target{release_title: rt, status: status, torrent_hash: hash} ->
          {rt, status_to_atom(status), hash}

        nil ->
          {nil, nil, nil}
      end

    # Status line for the index card. Queue-state-aware status takes
    # over at render time inside the row component when a download
    # footer is paired — derive here without a queue item so the row
    # is independent of QueueMonitor cadence. `location` resolves the
    # post-download stage when the torrent has left the client.
    {status, _next_step, _actions} = PursuitStatus.derive(pursuit, lead_unit, target, nil, location)

    %PursuitRow{
      id: pursuit.id,
      title: pursuit.title,
      state: state_to_atom(pursuit.state),
      updated_at: pursuit.updated_at,
      awaiting_decision?: Enum.any?(units, &UnitState.awaiting_decision?/1),
      season_number: pursuit.season_number,
      episode_number: pursuit.episode_number,
      release_title: release_title,
      target_status: target_status,
      status: status,
      normalized_release_title: release_title && Identity.normalize_title(release_title),
      torrent_hash: torrent_hash,
      pairing_keys: pairing_keys(units, target, current_targets),
      units_wanted: max(length(units), 1),
      units_satisfied: Enum.count(units, &(&1.state == "satisfied")),
      door: if(pursuit.recipe_type == "tmdb", do: :media, else: :query),
      unit_states: Enum.map(units, & &1.state)
    }
  end

  # One pairing identity per distinct current target across the units,
  # lead target first — a composite pursuit has several grabs in the
  # client at once and the queue matcher must claim them all.
  defp pairing_keys(units, lead_target, current_targets) do
    units
    |> Enum.map(&Map.get(current_targets, &1.current_target_id))
    |> Enum.reject(&is_nil/1)
    |> then(fn targets -> if lead_target, do: [lead_target | targets], else: targets end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(fn %Target{} = t -> {t.torrent_hash, t.release_title} end)
    |> Enum.reject(fn {hash, title} -> is_nil(hash) and is_nil(title) end)
  end

  # Explicit string→atom mapping for the row VM so the function doesn't
  # depend on atom-loading side effects from other modules being
  # compiled into the same release. The pursuit `state` column is
  # constrained by `Pursuits.State` to these five values.
  defp state_to_atom("active"), do: :active
  defp state_to_atom("satisfied"), do: :satisfied
  defp state_to_atom("partial"), do: :partial
  defp state_to_atom("exhausted"), do: :exhausted
  defp state_to_atom("cancelled"), do: :cancelled

  defp status_to_atom(nil), do: nil
  defp status_to_atom("seeking"), do: :seeking
  defp status_to_atom("acquired"), do: :acquired
  defp status_to_atom("succeeded"), do: :succeeded
  defp status_to_atom("failed"), do: :failed
  defp status_to_atom("cancelled"), do: :cancelled

  defp build_header(%Pursuit{} = pursuit) do
    artwork = header_artwork(pursuit)

    %PursuitHeader{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      awaiting_decision?: awaiting_decision?(pursuit),
      recipe: PursuitRecipe.from(pursuit),
      search_queries: search_queries_for(pursuit),
      criteria_summary: summarize_criteria(pursuit.criteria),
      backdrop_url: artwork.backdrop_url,
      logo_url: artwork.logo_url
    }
  end

  # Local-only (DB + disk) — the modal kicks the network `Artwork.ensure`
  # async when this comes back empty for a TMDB pursuit.
  defp header_artwork(%Pursuit{recipe_type: "tmdb", tmdb_id: tmdb_id} = pursuit)
       when not is_nil(tmdb_id) do
    MediaCentaur.Acquisition.Artwork.resolve(tmdb_id, pursuit.tmdb_type)
  end

  defp header_artwork(_pursuit), do: %{backdrop_url: nil, logo_url: nil}

  # User-facing copy lives with the view model (`PursuitStatus.criteria_summary/1`).
  defp summarize_criteria(map), do: PursuitStatus.criteria_summary(map)

  # --- status_for helpers ----------------------------------------------------

  # `QueryBuilder.build/1` returns `[{query, opts}]` ordered best-to-worst.
  # The UI only needs the query strings, so we strip the opts here. Kept
  # pure (no DB, no Prowlarr) — the same list the worker iterates over.
  defp search_queries_for(%Pursuit{} = pursuit) do
    pursuit
    |> PursuitRecipe.from()
    |> PursuitRecipe.to_criteria()
    |> QueryBuilder.build()
    |> Enum.map(fn {query, _opts} -> query end)
  end

  defp find_queue_match(nil, _items), do: nil

  defp find_queue_match(%Target{} = target, items) do
    items
    |> resolve_queue_items()
    |> QueueMatcher.find_item(target.torrent_hash, target.release_title)
  end

  defp resolve_queue_items(:persistent_term), do: QueueMonitor.snapshot()
  defp resolve_queue_items(items) when is_list(items), do: items

  defp latest_event_at(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> limit(1)
    |> select([e], e.occurred_at)
    |> Repo.one()
  end

  defp staleness_for(nil), do: :very_stale

  defp staleness_for(%DateTime{} = ts) do
    diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

    cond do
      diff_seconds < 3600 -> :fresh
      diff_seconds < 86_400 -> :stale
      true -> :very_stale
    end
  end
end
