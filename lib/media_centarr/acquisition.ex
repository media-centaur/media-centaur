defmodule MediaCentarr.Acquisition do
  use Boundary,
    deps: [
      MediaCentarr.Capabilities,
      MediaCentarr.Downloads,
      MediaCentarr.Library,
      MediaCentarr.ReleaseTracking,
      MediaCentarr.Search,
      MediaCentarr.Settings
    ],
    exports: [
      AutoGrabSettings,
      CancelReasons,
      Pursuits,
      Pursuits.Commands.Cancel,
      Pursuits.Commands.ChangeTarget,
      Pursuits.Commands.RequestDecision,
      Pursuits.Events,
      Pursuits.InboundListener,
      Pursuits.Pursuit,
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
      ViewModels.DownloadProgress,
      ViewModels.PursuitHeader,
      ViewModels.PursuitRow,
      ViewModels.PursuitStatus,
      ViewModels.PursuitWithDownload,
      ViewModels.Timeline,
      ViewModels.TimelineEntry
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

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.{
    AutoGrabService,
    Config,
    Target,
    TargetEvents,
    Targets
  }

  alias MediaCentarr.Search.{Prowlarr, QueryExpander, SearchResult}

  alias MediaCentarr.Acquisition.Pursuits.Commands.{Arm, ArmAll, PickTarget, StartFromPick}
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Recipe}
  alias MediaCentarr.Acquisition.Pursuits, as: PursuitsContext

  alias MediaCentarr.Downloads.DownloadClient.Dispatcher
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

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
  `MediaCentarrWeb.AcquisitionLive`'s moduledoc).
  """
  @type queue_message ::
          {:queue_state, MediaCentarr.Downloads.QueueState.t()}

  @typedoc """
  Messages broadcast on `Topics.acquisition_search/0`. Subscribe with
  `subscribe_search/0`. Each broadcast carries the entire current
  session — there are no incremental deltas.
  """
  @type search_message ::
          {:search_session, MediaCentarr.Search.SearchSession.t()}

  @doc "Subscribes the caller to target lifecycle events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
  end

  @doc """
  Subscribes the caller to download-client queue snapshots. Also
  registers the caller with `QueueMonitor` so the next poll uses the
  watched cadence (1 s vs. 5 s when nobody is rendering the queue).
  """
  @spec subscribe_queue() :: :ok
  def subscribe_queue do
    :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_queue())
    MediaCentarr.Downloads.QueueMonitor.register_subscriber(self())
  end

  @doc "Subscribes the caller to search session updates."
  @spec subscribe_search() :: :ok
  def subscribe_search do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_search())
  end

  @doc "Returns the current search session struct (always present; may be empty)."
  @spec current_search_session() :: MediaCentarr.Search.SearchSession.t()
  defdelegate current_search_session,
    to: MediaCentarr.Search.SearchSession,
    as: :current

  @doc """
  Starts a new search session, replacing any existing one. Returns
  `{:ok, %{session: ..., queries: [...]}}` so the caller (the LiveView)
  can spawn Tasks for each expanded query.
  """
  @spec start_search(String.t()) ::
          {:ok, %{session: MediaCentarr.Search.SearchSession.t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  defdelegate start_search(query), to: MediaCentarr.Search.SearchSession

  @doc "Records a per-query Prowlarr result against the current session."
  @spec record_search_result(
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  defdelegate record_search_result(term, outcome),
    to: MediaCentarr.Search.SearchSession

  @doc """
  Updates the query input box value and recomputes the expansion preview.
  Returns the updated session so the caller can assign it directly.
  """
  @spec set_query_preview(String.t()) :: MediaCentarr.Search.SearchSession.t()
  defdelegate set_query_preview(query), to: MediaCentarr.Search.SearchSession

  @doc "Sets `term => guid` in the session selections map. Returns the new session."
  @spec set_selection(String.t(), String.t()) :: MediaCentarr.Search.SearchSession.t()
  defdelegate set_selection(term, guid), to: MediaCentarr.Search.SearchSession

  @doc "Removes `term` from the session selections map. Returns the new session."
  @spec clear_selection(String.t()) :: MediaCentarr.Search.SearchSession.t()
  defdelegate clear_selection(term), to: MediaCentarr.Search.SearchSession

  @doc "Empties the session selections map. Returns the new session."
  @spec clear_selections() :: MediaCentarr.Search.SearchSession.t()
  defdelegate clear_selections(), to: MediaCentarr.Search.SearchSession

  @doc "Toggles `expanded?` on the named group. Returns the new session."
  @spec toggle_group(String.t()) :: MediaCentarr.Search.SearchSession.t()
  defdelegate toggle_group(term), to: MediaCentarr.Search.SearchSession

  @doc "Sets the boolean `grabbing?` flag on the session. Returns the new session."
  @spec set_grabbing(boolean()) :: MediaCentarr.Search.SearchSession.t()
  defdelegate set_grabbing(value), to: MediaCentarr.Search.SearchSession

  @doc "Sets the last-grab outcome message on the session. Returns the new session."
  @spec set_grab_message({:ok | :partial | :error, String.t()}) ::
          MediaCentarr.Search.SearchSession.t()
  defdelegate set_grab_message(message), to: MediaCentarr.Search.SearchSession

  @doc "Resets the entire search session to the default empty state. Returns the new session."
  @spec clear_search_session() :: MediaCentarr.Search.SearchSession.t()
  defdelegate clear_search_session(), to: MediaCentarr.Search.SearchSession, as: :clear

  @doc """
  Clears search results (groups + selections) but preserves the user's
  query string and expansion preview. Used after a grab batch completes.
  Returns the new session.
  """
  @spec clear_search_results() :: MediaCentarr.Search.SearchSession.t()
  defdelegate clear_search_results(),
    to: MediaCentarr.Search.SearchSession,
    as: :clear_results

  @doc """
  Re-arms named groups (`:abandoned` / `{:failed, _}` -> `:loading`).
  The caller's pid becomes the monitored `searching_pid`. The caller is
  responsible for spawning Tasks for these terms. Returns the new session.
  """
  @spec retry_search_terms([String.t()]) :: MediaCentarr.Search.SearchSession.t()
  defdelegate retry_search_terms(terms), to: MediaCentarr.Search.SearchSession

  @doc """
  Returns the latest cached download-client queue snapshot (items only).
  Synchronous; reads `:persistent_term`. Returns `[]` before the first
  successful poll or when no download client is configured. Prefer
  `queue_state/0` when freshness/error metadata matters.
  """
  @spec queue_snapshot() :: [MediaCentarr.Downloads.QueueItem.t()]
  defdelegate queue_snapshot, to: MediaCentarr.Downloads.QueueMonitor, as: :snapshot

  @doc """
  Returns the latest cached `%QueueState{}` — items plus liveness
  metadata. Synchronous; reads `:persistent_term`.
  """
  @spec queue_state() :: MediaCentarr.Downloads.QueueState.t()
  defdelegate queue_state, to: MediaCentarr.Downloads.QueueMonitor, as: :state

  @doc """
  Asks the QueueMonitor to poll the download client immediately. Use
  when external state (e.g. a freshly configured download client) means
  the cached snapshot is likely stale and waiting up to 30 s for the
  next idle-cadence tick is too slow.
  """
  @spec poll_queue_now() :: :ok
  defdelegate poll_queue_now, to: MediaCentarr.Downloads.QueueMonitor, as: :poll_now

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
        results =
          queries
          |> Task.async_stream(
            fn q -> Prowlarr.search(q, opts) end,
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
    if available?() do
      with :ok <- Prowlarr.grab(result),
           {:ok, pursuit} <-
             StartFromPick.execute(%{
               result: result,
               manual_query: trim_query(query),
               origin: "manual"
             }) do
        target = Repo.get(Target, pursuit.current_target_id)
        broadcast(%TargetEvents.Picked{target: target})
        Log.info(:library, "manual pick submitted — #{result.title}")
        {:ok, target}
      end
    else
      {:error, :not_configured}
    end
  end

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

  defp do_pick_alternative(%Pursuit{} = pursuit, %SearchResult{} = result, label) do
    with :ok <- Prowlarr.grab(result),
         {:ok, updated} <-
           PickTarget.execute(%{
             pursuit_id: pursuit.id,
             result: result,
             choice_label: label
           }) do
      target = Repo.get(Target, updated.current_target_id)
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
  type/year opts, brace expansion) lives in one place and can't drift.
  """
  @spec list_alternatives_for(Pursuit.t()) :: [SearchResult.t()]
  def list_alternatives_for(%Pursuit{} = pursuit) do
    case do_search_for_pursuit(pursuit) do
      {:ok, results} ->
        excluded = MapSet.new(pursuit.tried_release_guids)

        results
        |> Enum.reject(&MapSet.member?(excluded, &1.guid))
        |> Enum.take(8)

      {:error, _} ->
        []
    end
  end

  # Single source of truth for "search Prowlarr the way THIS pursuit
  # wants to be searched". Brace-aware, type-aware, year-aware. Adding
  # a new consumer just calls `list_alternatives_for/1` (filtered) or
  # `do_search_for_pursuit/1` (raw, internal-only) — the recipe can't
  # drift between call sites.
  defp do_search_for_pursuit(%Pursuit{} = pursuit) do
    pursuit |> Recipe.from() |> do_search_for_recipe()
  end

  defp do_search_for_recipe(%Recipe{type: :tmdb} = recipe) do
    opts =
      []
      |> put_when_present(:type, recipe.tmdb_type)
      |> put_when_present(:year, recipe.year)

    search_expanded(recipe.title, opts)
  end

  defp do_search_for_recipe(%Recipe{type: :prowlarr_query, manual_query: query, title: title}) do
    search_expanded(query || title, [])
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

  @doc "Returns true when a download client is configured (type + URL set)."
  @spec download_client_available?() :: boolean()
  def download_client_available?, do: Config.download_client_available?()

  @doc """
  Lists downloads from the configured download client.

  Returns `{:error, :not_configured}` when no driver is configured, or
  `{:error, {:unknown_driver, type}}` when the configured type has no
  driver in this build.

  `filter` is one of `:active | :completed | :all`.
  """
  @spec list_downloads(:active | :completed | :all) ::
          {:ok, list()} | {:error, term()}
  def list_downloads(filter \\ :all) do
    with {:ok, driver} <- Dispatcher.driver() do
      driver.list_downloads(filter)
    end
  end

  @doc """
  Cancels a download by id. Destructive — the torrent and any
  downloaded files are removed from the client.
  """
  @spec cancel_download(String.t()) :: :ok | {:error, term()}
  def cancel_download(id) do
    with {:ok, driver} <- Dispatcher.driver() do
      driver.cancel_download(id)
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

  @doc "Tests connectivity and credentials against the configured download client."
  @spec test_download_client() :: :ok | {:error, term()}
  def test_download_client do
    with {:ok, driver} <- Dispatcher.driver() do
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
  Enqueues an automated acquisition for a TMDB target.

  Idempotent on the four-tuple `(tmdb_id, tmdb_type, season_number,
  episode_number)` — a second call for the same tuple returns the
  existing pursuit's current target without re-enqueueing the job
  (the Oban worker is unique-keyed too).

  Options:
  - `:season_number` — integer season (TV episodes/season packs)
  - `:episode_number` — integer episode (TV episodes only)
  - `:year` — integer release year (movies — used in the Prowlarr query)
  - `:min_quality`, `:max_quality`, `:quality_4k_patience_hours` —
    recorded on the pursuit's `criteria` map for the worker to read
  """
  @spec enqueue(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Target.t()} | {:error, term()}
  def enqueue(tmdb_id, tmdb_type, title, opts \\ []) do
    criteria =
      %{
        "min_quality" => Keyword.get(opts, :min_quality),
        "max_quality" => Keyword.get(opts, :max_quality),
        "quality_4k_patience_hours" => Keyword.get(opts, :quality_4k_patience_hours)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Arm.execute(%{
      tmdb_id: tmdb_id,
      tmdb_type: tmdb_type,
      title: title,
      year: Keyword.get(opts, :year),
      season_number: Keyword.get(opts, :season_number),
      episode_number: Keyword.get(opts, :episode_number),
      origin: Keyword.get(opts, :origin, "auto"),
      criteria: criteria
    })
  end

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple →
  `{pursuit, current_target | nil}`.

  Used by the upcoming-zone renderer to decorate each release card
  with its acquisition status without N+1ing the DB.
  """
  @spec statuses_for_releases([ArmAll.key()]) ::
          %{ArmAll.key() => {Pursuit.t(), Target.t() | nil}}
  defdelegate statuses_for_releases(keys), to: ArmAll

  @doc """
  Bulk-enqueues acquisitions for every release of a tracked item that
  is released, not in the library, and of an acquirable type. Behaviour
  by pursuit/target state:

  - **No pursuit** → enqueue a new one (`queued`)
  - **Cancelled / failed target** → re-arm via `ChangeTarget` (`rearmed`)
  - **In flight** (`seeking`) or **acquired** → skip (`in_progress`)
  - **Succeeded** → skip (`already_acquired`)
  """
  @spec enqueue_all_pending_for_item(item_id :: String.t()) ::
          {:ok, ArmAll.summary()} | {:error, :not_found}
  def enqueue_all_pending_for_item(item_id) do
    with {:ok,
          %{
            tmdb_id: tmdb_id,
            tmdb_type: tmdb_type,
            name: name,
            pending_releases: pending
          }} <- ReleaseTracking.list_pending_acquirable_releases_for_item(item_id) do
      ArmAll.execute(%{
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type,
        name: name,
        releases: pending
      })
    end
  end

  @doc "See `Acquisition.Targets.list_auto_targets/1`."
  defdelegate list_auto_targets(filter \\ :all), to: Targets

  @doc "See `Acquisition.Targets.rearm_target/1`."
  defdelegate rearm_target(target_id), to: Targets

  @doc "See `Acquisition.Targets.cancel_target/2`."
  defdelegate cancel_target(target_id, reason), to: Targets

  @doc "See `Acquisition.Targets.cancel_active_targets_for/3`."
  defdelegate cancel_active_targets_for(tmdb_id, tmdb_type, reason), to: Targets

  @doc """
  Broadcasts an update message on `Topics.acquisition_updates/0`. Used
  by every Acquisition writer so there is one PubSub call site for the
  topic.
  """
  @spec broadcast_update(term()) :: :ok | {:error, term()}
  def broadcast_update(message) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.acquisition_updates(),
      message
    )
  end

  defp broadcast(message), do: broadcast_update(message)
end
