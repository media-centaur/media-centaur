defmodule MediaCentaur.Acquisition do
  use Boundary,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.Downloads,
      MediaCentaur.Library,
      MediaCentaur.ReleaseTracking,
      MediaCentaur.Retention,
      MediaCentaur.Review,
      MediaCentaur.Search,
      MediaCentaur.Settings,
      MediaCentaur.TMDB
    ],
    exports: [
      Artwork,
      AutoGrabSettings,
      CancelReasons,
      PlanEvents,
      PlanEvents.Changed,
      PlanEvents.DescentStatus,
      PlanEvents.SearchActivity,
      Plans,
      Plans.Plan,
      Targeting,
      Targeting.Selection,
      Targeting.Season,
      Targeting.Episode,
      Pursuits,
      Pursuits.Throughput,
      Pursuits.Commands.Cancel,
      Pursuits.Commands.ChangeTarget,
      Pursuits.Commands.RequestDecision,
      Pursuits.Events,
      Pursuits.InboundListener,
      Pursuits.Pursuit,
      # Exported because the detail-header/status ViewModels embed it and the
      # web layer + its stories read it directly (complexity-retirement W4-2):
      # Recipe is a pure value-object projection, so exposing it is the ADR-039-
      # compatible way to collapse the duplicate ViewModels.Recipe.
      Pursuits.Recipe,
      QueueMatcher,
      Reactor,
      Target,
      TargetEvents,
      TargetEvents.Acquired,
      TargetEvents.Armed,
      TargetEvents.Cancelled,
      TargetEvents.Failed,
      TargetEvents.Picked,
      TargetEvents.Snoozed,
      TargetStatus,
      ViewModels.Alternative,
      ViewModels.CurrentAction,
      ViewModels.DecisionCard,
      ViewModels.DescentNarrative,
      ViewModels.DescentNarrative.Row,
      ViewModels.DescentNarrative.View,
      ViewModels.DownloadProgress,
      ViewModels.NextStep,
      ViewModels.PlanBoard,
      ViewModels.PlanBoard.Alternative,
      ViewModels.PlanBoard.Cell,
      ViewModels.PlanBoard.Offer,
      ViewModels.PlanBoard.Overlap,
      ViewModels.PlanBoard.SeasonRow,
      ViewModels.PlanBoard.Release,
      ViewModels.PursuitHeader,
      ViewModels.PursuitRow,
      ViewModels.PursuitStatus,
      ViewModels.PursuitWithDownload,
      ViewModels.Timeline,
      ViewModels.TimelineEntry,
      ViewModels.UnitBoard,
      ViewModels.UnitBoard.Group,
      ViewModels.UnitBoard.Row
    ]

  @moduledoc """
  Public facade for the Acquisition bounded context.

  Acquisition is optional — call `available?/0` before exposing any UI
  surfaces. When Prowlarr is not configured, `available?/0` returns
  false and search/pick return `{:error, :not_configured}`.

  ## Domain shape

  - **Pursuit** — the intent. Owns the recipe (`tmdb` or
    `prowlarr_query`) and the lifecycle.
  - **Target** — a specific release the pursuit is chasing right now.
    A pursuit has many targets over its lifetime; `current_target_id`
    refers to the active one.
  - **Recipe** — `pursuit.recipe_type` discriminator plus the variant
    columns (TMDB metadata for `tmdb`, `manual_query` for
    `prowlarr_query`).

  ## Manual search

  Call `search/2` with a query string. Pass the chosen `%SearchResult{}`
  to `pick_target/2` to submit it to Prowlarr and start (or pivot) the
  pursuit.

  ## PubSub broadcasts

  Subscribe with `subscribe/0` to receive (on `acquisition:updates`):

  - `%TargetEvents.Acquired{}` — Prowlarr accepted the release
  - `%TargetEvents.Picked{}` — user picked a release
  - `%TargetEvents.Armed{}` — target re-armed into seeking
  - `%TargetEvents.Snoozed{}` — search ran, no acceptable result, will retry
  - `%TargetEvents.Failed{}` — max attempts reached, no longer retrying
  - `%TargetEvents.Cancelled{}` — target cancelled
  - `Pursuits.Events.*` typed structs — persisted timeline events

  All broadcasts are typed structs; pattern-match on the struct
  module. Use `TargetEvents.event?/1` and `Pursuits.Events.event?/1`
  in a catch-all clause to recognise the family without enumerating
  every kind.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{
    AutoGrabService,
    Config,
    Corpus,
    DropPlanner,
    Target,
    TargetEvents,
    Targets,
    TrackingHandoffs
  }

  alias MediaCentaur.Search.{Prowlarr, QueryExpander, SearchResult}

  alias MediaCentaur.Acquisition.Pursuits.Commands.{PickTarget, StartFromPick}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Recipe, Units}
  alias MediaCentaur.Acquisition.Pursuits, as: PursuitsContext

  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Topics

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available?, do: Config.available?()

  @doc "True when auto-grab is enabled. Delegates to `AutoGrabService.running?/0`."
  @spec auto_grab_running?() :: boolean()
  defdelegate auto_grab_running?, to: AutoGrabService, as: :running?

  @doc "Pauses the auto-grab service. Delegates to `AutoGrabService.pause/0`."
  @spec pause_auto_grab() :: :ok
  defdelegate pause_auto_grab, to: AutoGrabService, as: :pause

  @doc "Resumes the auto-grab service. Delegates to `AutoGrabService.resume/0`."
  @spec resume_auto_grab() :: :ok
  defdelegate resume_auto_grab, to: AutoGrabService, as: :resume

  @typedoc """
  Messages broadcast on `Topics.acquisition_updates/0`. Subscribe with
  `subscribe/0`. TargetEvents structs carry the affected `Target.t()`;
  Pursuits.Events structs carry pursuit-level event facts. Subscribers
  pattern-match on the struct module.
  """
  @type updates_message ::
          TargetEvents.Picked.t()
          | TargetEvents.Acquired.t()
          | TargetEvents.Armed.t()
          | TargetEvents.Snoozed.t()
          | TargetEvents.Failed.t()
          | TargetEvents.Cancelled.t()
          | struct()

  @typedoc """
  Messages broadcast on `Topics.acquisition_queue/0`. Subscribe with
  `subscribe_queue/0`.

  Snapshots are AUTHORITATIVE — every poll overwrites the LiveView's
  notion of the queue. Subscribers that mirror queue state to UI must
  reconcile against in-flight optimistic mutations (see the
  "External-state reconciliation" section in
  `MediaCentaurWeb.IncomingLive`'s moduledoc).
  """
  @type queue_message ::
          {:queue_state, MediaCentaur.Downloads.QueueState.t()}

  @doc "Subscribes the caller to target lifecycle events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())
  end

  @doc """
  Subscribes the caller to download-client queue snapshots. Also
  registers the caller with `QueueMonitor`, which sends back the
  current snapshot immediately, polls right away if this is the first
  watcher, and keeps polling at the watched cadence (10 s vs. 30 s
  when nobody is rendering the queue).
  """
  @spec subscribe_queue() :: :ok
  def subscribe_queue do
    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_queue())
    MediaCentaur.Downloads.QueueMonitor.register_subscriber(self())
  end

  @doc """
  Returns the latest cached download-client queue snapshot (items only).
  Synchronous; reads `:persistent_term`. Returns `[]` before the first
  successful poll or when no download client is configured. Prefer
  `queue_state/0` when connectivity metadata matters.
  """
  @spec queue_snapshot() :: [MediaCentaur.Downloads.QueueItem.t()]
  defdelegate queue_snapshot, to: MediaCentaur.Downloads.QueueMonitor, as: :snapshot

  @doc """
  Returns the latest cached `%QueueState{}` — items plus liveness
  metadata. Synchronous; reads `:persistent_term`.
  """
  @spec queue_state() :: MediaCentaur.Downloads.QueueState.t()
  defdelegate queue_state, to: MediaCentaur.Downloads.QueueMonitor, as: :state

  @doc """
  Asks the QueueMonitor to poll the download client immediately. Use
  when external state (e.g. a freshly configured download client) means
  the cached snapshot is likely stale and waiting up to 30 s for the
  next idle-cadence tick is too slow.
  """
  @spec poll_queue_now() :: :ok
  defdelegate poll_queue_now, to: MediaCentaur.Downloads.QueueMonitor, as: :poll_now

  @doc """
  Searches Prowlarr for releases matching the query.

  Returns `{:error, :not_configured}` when Prowlarr is not configured.

  Options:
  - `:type` — `:movie` or `:tv`
  - `:year` — integer year
  """
  @spec search(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def search(query, opts \\ []) do
    if available?() do
      Prowlarr.search(query, opts)
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Fire-and-forget single-query search. Runs `search/1` on a supervised
  context-layer task and hands the outcome to `report` —
  `report.(query, {:ok, results} | {:error, reason})`. Per-query searches
  must outlive the triggering LiveView so a navigated-away user's
  in-flight fan-out still lands (ADR-049); the report callback is how the
  web layer's session state receives results without this context knowing
  it exists.
  """
  @spec run_search_one_async(
          String.t(),
          (String.t(), {:ok, [SearchResult.t()]} | {:error, term()} -> any())
        ) :: :ok
  def run_search_one_async(query, report) when is_function(report, 2) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      outcome =
        try do
          search(query)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      # User-initiated searches always hit the indexers live, but their
      # findings still feed the durable corpus (ADR-055) — the
      # citizenship gate and pivot fallbacks get to reuse them.
      with {:ok, results} <- outcome, do: Corpus.record!(query, [], results)

      report.(query, outcome)
    end)

    :ok
  end

  @doc """
  Like `search/2`, but first expands brace syntax in `query` (per
  `QueryExpander`), runs each concrete query against Prowlarr in
  parallel, and merges the results (deduped by guid). Use this when the
  caller may receive a user-typed query containing braces (e.g.
  `Sample Show S01E{01,02}`) and wants a single merged result list.

  Returns:
    - `{:ok, [SearchResult.t()]}` — merged results (possibly empty)
    - `{:error, :invalid_syntax}` — query has malformed braces
    - `{:error, :not_configured}` — Prowlarr isn't ready

  Queries without braces fan out to a single search and behave exactly
  like `search/2`.
  """
  @spec search_expanded(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def search_expanded(query, opts \\ []) when is_binary(query) do
    if available?() do
      with {:ok, queries} <- QueryExpander.expand(query) do
        # Per-term searches go through the corpus (consult-first,
        # ADR-055); pass `force: true` in opts for a user-initiated
        # refresh that must bypass the freshness gate.
        results =
          queries
          |> Task.async_stream(
            fn q -> Corpus.search(q, opts) end,
            max_concurrency: 5,
            timeout: 15_000,
            on_timeout: :kill_task
          )
          |> Enum.flat_map(fn
            {:ok, {:ok, list}} when is_list(list) -> list
            _ -> []
          end)
          |> Enum.uniq_by(& &1.guid)

        {:ok, results}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Submits a manual pick — Prowlarr.grab + pursuit/target creation —
  and records it on the activity timeline.

  Creates a pursuit with `recipe_type = "prowlarr_query"` and the
  user's typed query, then a target in `acquired`, atomically via
  `StartFromPick`. Broadcasts `{:target_picked, target}` on success.
  The Prowlarr GUID is recorded on the target so the duplicate-guid
  check in `ChangeTarget` works.

  Returns `{:error, :not_configured}` when Prowlarr is not configured,
  or `{:error, reason}` when Prowlarr rejects the grab.
  """
  @spec pick_target(SearchResult.t(), String.t()) :: {:ok, Target.t()} | {:error, term()}
  def pick_target(%SearchResult{} = result, query) when is_binary(query) do
    case pick_targets([%{term: trim_query(query), result: result}], query) do
      {:ok, [{_pick, outcome}]} -> outcome
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Submits a batch of manual picks as **one composite pursuit**
  (ADR-055): each pick is `%{term, result}` — the expanded query term
  and the chosen release — and becomes one unit of the pursuit, so a
  brace-expanded grab (`Sample Show S01E{01-03}` with three picks)
  lands as a single pursuit with three units instead of three
  pursuits.

  Each release is submitted to Prowlarr first; only successful grabs
  become units. Returns `{:ok, pairs}` where `pairs` aligns with the
  input picks as `{pick, {:ok, target} | {:error, reason}}`. When
  every grab fails, no pursuit is created (the pairs still report the
  per-pick errors). Broadcasts `{:target_picked, target}` per landed
  pick.

  Returns `{:error, :not_configured}` when Prowlarr is not configured.
  """
  @spec pick_targets([%{term: String.t() | nil, result: SearchResult.t()}], String.t()) ::
          {:ok, [{map(), {:ok, Target.t()} | {:error, term()}}]} | {:error, :not_configured}
  def pick_targets(picks, query) when is_list(picks) and is_binary(query) do
    if available?() do
      grabbed = Enum.map(picks, fn pick -> {pick, Prowlarr.grab(pick.result)} end)
      successful = for {pick, :ok} <- grabbed, do: pick

      case start_from_picks(successful, query) do
        {:ok, targets_by_guid} ->
          {:ok, Enum.map(grabbed, &pair_outcome(&1, targets_by_guid))}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_configured}
    end
  end

  defp start_from_picks([], _query), do: {:ok, %{}}

  defp start_from_picks(successful, query) do
    with {:ok, %{pursuit: pursuit, targets: targets}} <-
           StartFromPick.execute(%{
             picks: successful,
             manual_query: trim_query(query),
             origin: "manual"
           }) do
      Enum.each(targets, &broadcast(%TargetEvents.Picked{target: &1}))

      Log.info(
        :library,
        "manual pick submitted — #{pursuit.title} (#{length(targets)} release(s))"
      )

      {:ok, Map.new(targets, &{&1.prowlarr_guid, &1})}
    end
  end

  defp pair_outcome({pick, :ok}, targets_by_guid) do
    case Map.get(targets_by_guid, pick.result.guid) do
      %Target{} = target -> {pick, {:ok, target}}
      nil -> {pick, {:error, :not_persisted}}
    end
  end

  defp pair_outcome({pick, {:error, reason}}, _targets_by_guid), do: {pick, {:error, reason}}

  defp trim_query(query) do
    case String.trim(query) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Picks an alternative release on an existing pursuit — used by the
  decision card.

  Accepts either:

  - **`%SearchResult{}`** (fast path) — the LiveView passes the cached
    result that the user just clicked. Skips the Prowlarr search
    round-trip entirely; only `Prowlarr.grab/1` is called.
  - **`guid` string** (fallback) — when the cache was lost (modal
    re-mounted, session expired, race against `refresh_alternatives`).
    Re-runs the pursuit's search and locates the result by guid.

  Returns `{:error, :not_found}` when the pursuit is gone, or
  `{:error, :alternative_unavailable}` when a guid lookup no longer
  finds the result in fresh search results.
  """
  @spec pick_alternative(Ecto.UUID.t(), SearchResult.t() | String.t(), String.t()) ::
          {:ok, Pursuit.t()} | {:error, term()}
  def pick_alternative(pursuit_id, %SearchResult{} = result, label) when is_binary(label) do
    with {:ok, %Pursuit{} = pursuit} <- PursuitsContext.get(pursuit_id) do
      do_pick_alternative(pursuit, result, label)
    end
  end

  def pick_alternative(pursuit_id, guid, label) when is_binary(guid) and is_binary(label) do
    with {:ok, %Pursuit{} = pursuit} <- PursuitsContext.get(pursuit_id),
         {:ok, result} <- find_alternative(pursuit, guid) do
      do_pick_alternative(pursuit, result, label)
    end
  end

  @doc """
  Fire-and-forget `pick_alternative/3`. Runs the grab on a supervised
  context-layer task — the grab must complete regardless of the triggering
  LiveView's lifecycle (ADR-049: must-outlive background work lives in the
  context, not a web-layer `start_child`). The outcome is sent to `reply_to`
  as `{:alternative_picked, pursuit_id, outcome}` for an optional UI flash.
  """
  def pick_alternative_async(pursuit_id, arg, label, reply_to) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      outcome = pick_alternative(pursuit_id, arg, label)
      send(reply_to, {:alternative_picked, pursuit_id, outcome})
    end)

    :ok
  end

  defp do_pick_alternative(%Pursuit{} = pursuit, %SearchResult{} = result, label) do
    with :ok <- Prowlarr.grab(result),
         {:ok, updated} <-
           PickTarget.execute(%{
             pursuit_id: pursuit.id,
             result: result,
             choice_label: label
           }) do
      target = PursuitsContext.current_target(updated)
      broadcast(%TargetEvents.Picked{target: target})
      {:ok, updated}
    end
  end

  @doc """
  Lists the release alternatives for a pursuit's existing recipe —
  excluded by `tried_release_guids`, capped at 8, ready for display in
  the decision card.

  This is the single entry point for "show me the releases this pursuit
  could pivot to". Both the decision-card refresh path and the
  `pick_alternative` validation lookup go through the same private
  search helper, so the pursuit→Prowlarr translation (query selection,
  type/year opts, brace expansion, corpus consult) lives in one place
  and can't drift.

  Searches consult the corpus first (ADR-055 citizenship); pass
  `force: true` for the user-initiated "Search Prowlarr again" refresh.
  """
  @spec list_alternatives_for(Pursuit.t(), keyword()) :: [SearchResult.t()]
  def list_alternatives_for(%Pursuit{} = pursuit, search_opts \\ []) do
    # The decision card serves the awaiting-or-lead unit (ADR-055):
    # exclusions come from that unit's thread, and its concrete query
    # (when set) scopes the search to the unit's own term rather than
    # re-expanding the whole braced query.
    unit = Units.lead(pursuit.id)

    case do_search_for_pursuit(pursuit, unit, search_opts) do
      {:ok, results} ->
        excluded = MapSet.new((unit && unit.tried_release_guids) || [])

        results
        |> Enum.reject(&MapSet.member?(excluded, &1.guid))
        |> Enum.take(8)

      {:error, _} ->
        []
    end
  end

  # Single source of truth for "search Prowlarr the way THIS pursuit
  # wants to be searched". Brace-aware, type-aware, year-aware,
  # unit-aware, corpus-aware. Adding a new consumer just calls
  # `list_alternatives_for/2` (filtered) or `do_search_for_pursuit/3`
  # (raw, internal-only) — the recipe can't drift between call sites.
  defp do_search_for_pursuit(%Pursuit{} = pursuit, unit \\ nil, search_opts \\ []) do
    pursuit |> Recipe.for_unit(unit) |> do_search_for_recipe(search_opts)
  end

  defp do_search_for_recipe(%Recipe{type: :tmdb} = recipe, search_opts) do
    opts =
      search_opts
      |> put_when_present(:type, recipe.tmdb_type)
      |> put_when_present(:year, recipe.year)

    search_expanded(recipe.title, opts)
  end

  defp do_search_for_recipe(
         %Recipe{type: :prowlarr_query, manual_query: query, title: title},
         search_opts
       ) do
    search_expanded(query || title, search_opts)
  end

  defp find_alternative(%Pursuit{} = pursuit, guid) do
    case do_search_for_pursuit(pursuit) do
      {:ok, results} ->
        case Enum.find(results, &(&1.guid == guid)) do
          nil -> {:error, :alternative_unavailable}
          result -> {:ok, result}
        end

      {:error, _} = error ->
        error
    end
  end

  defp put_when_present(opts, _key, nil), do: opts
  defp put_when_present(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Cancels a download by id. Destructive — the download and any files
  are removed from the owning client.

  With two configured clients the cancel is routed to the one that owns
  the id: the live queue item's protocol tag is authoritative; when the
  item has already left the snapshot (cleanup cancels can arrive after
  completion or removal), the id shape decides — SABnzbd ids are always
  `SABnzbd_nzo_…`, torrent ids are bare infohashes.
  """
  @spec cancel_download(String.t()) :: :ok | {:error, term()}
  def cancel_download(id) do
    with {:ok, driver} <- Dispatcher.driver_for(protocol_for_download(id)) do
      driver.cancel_download(id)
    end
  end

  defp protocol_for_download(id) do
    case Enum.find(queue_state().items, &(&1.id == id)) do
      %MediaCentaur.Downloads.QueueItem{protocol: protocol}
      when protocol in [:torrent, :usenet] ->
        protocol

      _absent_or_untagged ->
        # Only a v1 infohash (40 hex chars) identifies a torrent. Usenet
        # ids vary by client version (SABnzbd 4: "SABnzbd_nzo_…",
        # SABnzbd 5: a bare UUID) — so anything non-infohash-shaped
        # routes to the usenet slot.
        if is_binary(id) and Regex.match?(~r/\A[0-9a-fA-F]{40}\z/, id),
          do: :torrent,
          else: :usenet
    end
  end

  @doc "Tests connectivity and credentials against Prowlarr."
  @spec test_prowlarr() :: :ok | {:error, term()}
  def test_prowlarr do
    if available?() do
      Prowlarr.ping()
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Tests connectivity and credentials against the download client in the
  given protocol slot (torrent slot by default).
  """
  @spec test_download_client(:torrent | :usenet) :: :ok | {:error, term()}
  def test_download_client(protocol \\ :torrent) do
    with {:ok, driver} <- Dispatcher.driver_for(protocol) do
      driver.test_connection()
    end
  end

  @doc """
  Asks Prowlarr for the list of download clients it has configured.
  Used by the Settings UI to pre-fill the download-client form.
  """
  @spec discover_download_clients() :: {:ok, [map()]} | {:error, term()}
  def discover_download_clients do
    if available?() do
      Prowlarr.list_download_clients()
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Fire-and-forget `discover_download_clients/0`. Runs the Prowlarr probe on
  a supervised context-layer task (ADR-049: no web-layer `start_child`) and
  sends `{:download_client_detect_result, result}` to `reply_to`.
  """
  def discover_download_clients_async(reply_to) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      send(reply_to, {:download_client_detect_result, discover_download_clients()})
    end)

    :ok
  end

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple →
  `{pursuit, current_target | nil}`.

  Used by the upcoming-zone renderer to decorate each release card
  with its acquisition status without N+1ing the DB.
  """
  @spec statuses_for_releases([PursuitsContext.release_key()]) ::
          %{PursuitsContext.release_key() => {Pursuit.t(), Target.t() | nil}}
  defdelegate statuses_for_releases(keys), to: PursuitsContext

  @doc """
  User-initiated "plan now" for a tracked item — plans all open
  unclaimed wants as a ready draft for the user to steer and approve.
  See `MediaCentaur.Acquisition.DropPlanner.plan_item_now/2`. The bulk
  gesture since ADR-056 (the legacy queue-everything path is gone).
  """
  defdelegate plan_tracked_item_now(item_id), to: DropPlanner, as: :plan_item_now

  @doc "See `MediaCentaur.Acquisition.TrackingHandoffs.track_plan_gaps_async/1`."
  defdelegate track_plan_gaps_async(plan_id), to: TrackingHandoffs

  @doc "See `Acquisition.Targets.list_auto_targets/1`."
  defdelegate list_auto_targets(filter \\ :all), to: Targets

  @doc "See `Acquisition.Targets.rearm_target/1`."
  defdelegate rearm_target(target_id), to: Targets

  @doc "See `Acquisition.Targets.cancel_target/2`."
  defdelegate cancel_target(target_id, reason), to: Targets

  @doc "See `Acquisition.Targets.cancel_active_targets_for/3`."
  defdelegate cancel_active_targets_for(tmdb_id, tmdb_type, reason), to: Targets

  @doc "See `Acquisition.Targets.find_content_path_for/1`."
  defdelegate find_content_path_for(file_path), to: Targets

  @doc """
  Broadcasts an update message on `Topics.acquisition_updates/0`. Used
  by every Acquisition writer so there is one PubSub call site for the
  topic.
  """
  @spec broadcast_update(term()) :: :ok | {:error, term()}
  def broadcast_update(message) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.acquisition_updates(),
      message
    )
  end

  defp broadcast(message), do: broadcast_update(message)
end
