defmodule MediaCentarr.Acquisition do
  use Boundary,
    deps: [
      MediaCentarr.Capabilities,
      MediaCentarr.Downloads,
      MediaCentarr.Library,
      MediaCentarr.ReleaseTracking,
      MediaCentarr.Settings
    ],
    exports: [
      AutoGrabSettings,
      CancelReasons,
      Prowlarr,
      Pursuits,
      Pursuits.Commands.Cancel,
      Pursuits.Commands.ChangeTarget,
      Pursuits.Commands.PickTarget,
      Pursuits.Commands.RequestDecision,
      Pursuits.Events,
      Pursuits.InboundListener,
      Pursuits.Pursuit,
      Quality,
      QueryExpander,
      QueueMatcher,
      Reactor,
      SearchSession,
      Target,
      TargetStatus,
      ViewModels.Alternative,
      ViewModels.CurrentAction,
      ViewModels.DecisionCard,
      ViewModels.DownloadProgress,
      ViewModels.NextStep,
      ViewModels.PursuitHeader,
      ViewModels.PursuitRow,
      ViewModels.PursuitStatus,
      ViewModels.PursuitWithDownload,
      ViewModels.Recipe,
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

  - `{:target_acquired, target}` — Prowlarr accepted the release
  - `{:target_picked, target}` — user picked a release
  - `{:target_armed, target}` — target re-armed into seeking
  - `{:target_snoozed, target}` — search ran, no acceptable result, will retry
  - `{:target_failed, target}` — max attempts reached, no longer retrying
  - `{:target_cancelled, target}` — target cancelled
  """

  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.{
    AutoGrabPolicy,
    AutoGrabService,
    AutoGrabSettings,
    CancelReasons,
    Config,
    Jobs.PursueTarget,
    Prowlarr,
    QueryExpander,
    SearchResult,
    Target,
    TargetStatus
  }

  alias MediaCentarr.Acquisition.Pursuits.Commands.{ChangeTarget, PickTarget, Start, StartFromPick}
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Recipe}
  alias MediaCentarr.Acquisition.Pursuits, as: PursuitsContext

  alias MediaCentarr.Downloads.DownloadClient.Dispatcher
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Format
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
  `subscribe/0`. Every payload carries the affected `Target.t()` so
  the receiver can re-render without an extra DB round-trip.
  """
  @type updates_message ::
          {:target_picked, Target.t()}
          | {:target_acquired, Target.t()}
          | {:target_armed, Target.t()}
          | {:target_snoozed, Target.t()}
          | {:target_failed, Target.t()}
          | {:target_cancelled, Target.t()}

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
          {:search_session, MediaCentarr.Acquisition.SearchSession.t()}

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
  @spec current_search_session() :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate current_search_session,
    to: MediaCentarr.Acquisition.SearchSession,
    as: :current

  @doc """
  Starts a new search session, replacing any existing one. Returns
  `{:ok, %{session: ..., queries: [...]}}` so the caller (the LiveView)
  can spawn Tasks for each expanded query.
  """
  @spec start_search(String.t()) ::
          {:ok, %{session: MediaCentarr.Acquisition.SearchSession.t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  defdelegate start_search(query), to: MediaCentarr.Acquisition.SearchSession

  @doc "Records a per-query Prowlarr result against the current session."
  @spec record_search_result(
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  defdelegate record_search_result(term, outcome),
    to: MediaCentarr.Acquisition.SearchSession

  @doc """
  Updates the query input box value and recomputes the expansion preview.
  Returns the updated session so the caller can assign it directly.
  """
  @spec set_query_preview(String.t()) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate set_query_preview(query), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets `term => guid` in the session selections map. Returns the new session."
  @spec set_selection(String.t(), String.t()) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate set_selection(term, guid), to: MediaCentarr.Acquisition.SearchSession

  @doc "Removes `term` from the session selections map. Returns the new session."
  @spec clear_selection(String.t()) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate clear_selection(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Empties the session selections map. Returns the new session."
  @spec clear_selections() :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate clear_selections(), to: MediaCentarr.Acquisition.SearchSession

  @doc "Toggles `expanded?` on the named group. Returns the new session."
  @spec toggle_group(String.t()) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate toggle_group(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the boolean `grabbing?` flag on the session. Returns the new session."
  @spec set_grabbing(boolean()) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate set_grabbing(value), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the last-grab outcome message on the session. Returns the new session."
  @spec set_grab_message({:ok | :partial | :error, String.t()}) ::
          MediaCentarr.Acquisition.SearchSession.t()
  defdelegate set_grab_message(message), to: MediaCentarr.Acquisition.SearchSession

  @doc "Resets the entire search session to the default empty state. Returns the new session."
  @spec clear_search_session() :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate clear_search_session(), to: MediaCentarr.Acquisition.SearchSession, as: :clear

  @doc """
  Clears search results (groups + selections) but preserves the user's
  query string and expansion preview. Used after a grab batch completes.
  Returns the new session.
  """
  @spec clear_search_results() :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate clear_search_results(),
    to: MediaCentarr.Acquisition.SearchSession,
    as: :clear_results

  @doc """
  Re-arms named groups (`:abandoned` / `{:failed, _}` -> `:loading`).
  The caller's pid becomes the monitored `searching_pid`. The caller is
  responsible for spawning Tasks for these terms. Returns the new session.
  """
  @spec retry_search_terms([String.t()]) :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate retry_search_terms(terms), to: MediaCentarr.Acquisition.SearchSession

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
        broadcast({:target_picked, target})
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
      broadcast({:target_picked, target})
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
    season = Keyword.get(opts, :season_number)
    episode = Keyword.get(opts, :episode_number)
    year = Keyword.get(opts, :year)
    origin = Keyword.get(opts, :origin, "auto")

    criteria =
      %{
        "min_quality" => Keyword.get(opts, :min_quality),
        "max_quality" => Keyword.get(opts, :max_quality),
        "quality_4k_patience_hours" => Keyword.get(opts, :quality_4k_patience_hours)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    with {:ok, pursuit} <-
           find_or_create_tmdb_pursuit(%{
             tmdb_id: tmdb_id,
             tmdb_type: tmdb_type,
             title: title,
             year: year,
             season_number: season,
             episode_number: episode,
             origin: origin,
             criteria: criteria
           }) do
      ensure_active_target(pursuit)
    end
  end

  defp find_or_create_tmdb_pursuit(attrs) do
    target = %{
      tmdb_id: attrs.tmdb_id,
      tmdb_type: attrs.tmdb_type,
      season_number: attrs.season_number,
      episode_number: attrs.episode_number
    }

    case PursuitsContext.find_by_tmdb_recipe(target) do
      nil ->
        Start.execute(Map.put(attrs, :recipe_type, "tmdb"))

      %Pursuit{} = pursuit ->
        {:ok, pursuit}
    end
  end

  defp ensure_active_target(%Pursuit{} = pursuit) do
    case PursuitsContext.current_target(pursuit) do
      %Target{status: status} = target ->
        if TargetStatus.terminal?(status) and status != "succeeded" do
          # Existing terminal-non-success — start a fresh seeking target.
          new_seeking_target(pursuit)
        else
          {:ok, target}
        end

      nil ->
        new_seeking_target(pursuit)
    end
  end

  defp new_seeking_target(%Pursuit{} = pursuit) do
    with {:ok, target} <-
           %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
           |> Target.create_changeset()
           |> Repo.insert(),
         {:ok, _pursuit} <-
           Repo.update(Pursuit.set_current_target_changeset(pursuit, target.id)) do
      Oban.insert(PursueTarget.new(%{"target_id" => target.id}))
      {:ok, target}
    end
  end

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple →
  `{pursuit, current_target | nil}`.

  Used by the upcoming-zone renderer to decorate each release card
  with its acquisition status without N+1ing the DB.
  """
  @spec statuses_for_releases([{String.t(), String.t(), integer() | nil, integer() | nil}]) ::
          %{
            {String.t(), String.t(), integer() | nil, integer() | nil} => {Pursuit.t(), Target.t() | nil}
          }
  def statuses_for_releases([]), do: %{}

  def statuses_for_releases(keys) when is_list(keys) do
    {tmdb_ids, tmdb_types} =
      keys
      |> Enum.map(fn {id, type, _, _} -> {id, type} end)
      |> Enum.unzip()

    tmdb_ids = Enum.uniq(tmdb_ids)
    tmdb_types = Enum.uniq(tmdb_types)

    pursuits =
      Repo.all(
        from(p in Pursuit,
          where: p.recipe_type == "tmdb" and p.tmdb_id in ^tmdb_ids and p.tmdb_type in ^tmdb_types
        )
      )

    target_ids = Enum.reject(Enum.map(pursuits, & &1.current_target_id), &is_nil/1)
    targets_by_id = targets_by_id(target_ids)
    requested = MapSet.new(keys)

    pursuits
    |> Enum.map(fn pursuit ->
      key = {pursuit.tmdb_id, pursuit.tmdb_type, pursuit.season_number, pursuit.episode_number}
      target = Map.get(targets_by_id, pursuit.current_target_id)
      {key, {pursuit, target}}
    end)
    |> Enum.filter(fn {key, _} -> MapSet.member?(requested, key) end)
    |> Map.new()
  end

  defp targets_by_id([]), do: %{}

  defp targets_by_id(ids) do
    Target
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(fn target -> {target.id, target} end)
  end

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
          {:ok,
           %{
             queued: non_neg_integer(),
             rearmed: non_neg_integer(),
             in_progress: non_neg_integer(),
             already_grabbed: non_neg_integer(),
             failed: [{tuple(), term()}]
           }}
          | {:error, :not_found}
  def enqueue_all_pending_for_item(item_id) do
    with {:ok,
          %{
            tmdb_id: tmdb_id,
            tmdb_type: tmdb_type,
            name: name,
            pending_releases: pending
          }} <- ReleaseTracking.list_pending_acquirable_releases_for_item(item_id) do
      keys =
        Enum.map(pending, fn release ->
          {tmdb_id, tmdb_type, release.season_number, release.episode_number}
        end)

      status_map = statuses_for_releases(keys)

      empty_summary = %{
        queued: 0,
        rearmed: 0,
        in_progress: 0,
        already_grabbed: 0,
        failed: []
      }

      summary =
        Enum.reduce(pending, empty_summary, fn release, acc ->
          key = {tmdb_id, tmdb_type, release.season_number, release.episode_number}
          classify_and_apply(acc, key, release, tmdb_id, tmdb_type, name, Map.get(status_map, key))
        end)

      {:ok, summary}
    end
  end

  defp classify_and_apply(acc, key, release, tmdb_id, tmdb_type, name, nil) do
    case enqueue(tmdb_id, tmdb_type, name,
           season_number: release.season_number,
           episode_number: release.episode_number
         ) do
      {:ok, _target} -> %{acc | queued: acc.queued + 1}
      {:error, reason} -> %{acc | failed: [{key, reason} | acc.failed]}
    end
  end

  defp classify_and_apply(acc, key, _release, _tmdb_id, _tmdb_type, _name, {pursuit, target}) do
    classify_target(acc, key, pursuit, target)
  end

  defp classify_target(acc, _key, _pursuit, %Target{status: "succeeded"}),
    do: %{acc | already_grabbed: acc.already_grabbed + 1}

  defp classify_target(acc, _key, _pursuit, %Target{status: "acquired"}),
    do: %{acc | in_progress: acc.in_progress + 1}

  defp classify_target(acc, _key, _pursuit, %Target{status: "seeking"}),
    do: %{acc | in_progress: acc.in_progress + 1}

  defp classify_target(acc, key, pursuit, _target) do
    # Failed, cancelled, or nil — pivot the pursuit to a new target.
    case ChangeTarget.execute(%{pursuit_id: pursuit.id}) do
      {:ok, _pursuit} -> %{acc | rearmed: acc.rearmed + 1}
      {:error, reason} -> %{acc | failed: [{key, reason} | acc.failed]}
    end
  end

  @doc """
  Lists `acquisition_targets` filtered by lifecycle stage.

  - `:all` — every row, newest-updated first
  - `:active` — `seeking` (the live job set)
  - `:failed` — terminal failure
  - `:cancelled` — explicitly cancelled
  - `:acquired` — release picked and submitted
  - `:succeeded` — file landed
  """
  @spec list_auto_targets(:all | :active | :failed | :cancelled | :acquired | :succeeded) ::
          [Target.t()]
  def list_auto_targets(filter \\ :all) do
    Target
    |> auto_targets_filter(filter)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  defp auto_targets_filter(query, :all), do: query

  defp auto_targets_filter(query, :active), do: where(query, [t], t.status in ^TargetStatus.in_flight())

  defp auto_targets_filter(query, status), do: where(query, [t], t.status == ^to_string(status))

  @doc """
  Re-arms a terminal target back to `seeking` and re-enqueues a
  `PursueTarget` Oban job. Resets `attempt_count` to 0 so the snooze
  schedule starts fresh. Broadcasts `{:target_armed, target}`.

  No-op for already-active targets (returns the target as-is). Use
  `ChangeTarget` when the pursuit's `current_target_id` should pivot
  to a freshly-inserted row — `rearm_target/1` flips this row in
  place.
  """
  @spec rearm_target(Ecto.UUID.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def rearm_target(target_id) do
    case Repo.get(Target, target_id) do
      nil ->
        {:error, :not_found}

      %Target{} = target ->
        if TargetStatus.rearmable?(target.status) do
          {:ok, restart_target(target, "target re-armed")}
        else
          {:ok, target}
        end
    end
  end

  defp restart_target(%Target{} = target, log_label) do
    {:ok, restarted} =
      target
      |> Ecto.Changeset.change(
        status: "seeking",
        attempt_count: 0,
        acquired_at: nil,
        cancelled_at: nil,
        cancelled_reason: nil,
        last_attempt_outcome: nil
      )
      |> Repo.update()

    Oban.insert(PursueTarget.new(%{"target_id" => restarted.id}))
    broadcast({:target_armed, restarted})
    Log.info(:library, "#{log_label} — #{restarted.title}")
    restarted
  end

  @doc """
  Cancels an active target (status `seeking`). No-op for terminal-state
  targets; broadcasts `{:target_cancelled, target}` only when the row
  was actually flipped.
  """
  @spec cancel_target(Ecto.UUID.t(), String.t()) ::
          {:ok, Target.t()} | {:error, :not_found}
  def cancel_target(target_id, reason) when is_binary(reason) do
    case Repo.get(Target, target_id) do
      nil ->
        {:error, :not_found}

      %Target{} = target ->
        if TargetStatus.in_flight?(target.status) do
          {:ok, cancelled} = Repo.update(Target.cancelled_changeset(target, reason))
          broadcast({:target_cancelled, cancelled})
          Log.info(:library, "target cancelled — #{target.title} (#{reason})")
          {:ok, cancelled}
        else
          {:ok, target}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Reactor entrypoints — driven by `Acquisition.Reactor` from PubSub
  # ---------------------------------------------------------------------------

  @doc """
  Processes a `{:release_ready, item, release}` event. Looks up any
  existing pursuit, asks `AutoGrabPolicy.decide/3`, and applies the
  resulting decision (enqueue / skip / cancel).
  """
  @spec handle_release_ready_event(struct(), struct()) :: :ok
  def handle_release_ready_event(item, release) do
    if auto_grab_running?() do
      do_handle_release_ready_event(item, release)
    end

    :ok
  end

  defp do_handle_release_ready_event(item, release) do
    settings = AutoGrabSettings.load()

    tmdb_id = to_string(item.tmdb_id)
    tmdb_type = ReleaseTracking.tmdb_type_for(item.media_type)

    existing_pursuit =
      PursuitsContext.find_by_tmdb_recipe(%{
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type,
        season_number: release.season_number,
        episode_number: release.episode_number
      })

    existing_target = existing_pursuit && PursuitsContext.current_target(existing_pursuit)
    existing_status = existing_target && existing_target.status

    effective_mode = AutoGrabSettings.effective_mode(item.auto_grab_mode, settings)

    decision =
      AutoGrabPolicy.decide(release.in_library, existing_status,
        prowlarr_ready: Capabilities.prowlarr_ready?(),
        mode: effective_mode
      )

    apply_decision(decision, item, release, settings, existing_target)
    :ok
  end

  defp apply_decision(:enqueue, item, release, settings, _existing_target) do
    case enqueue(
           to_string(item.tmdb_id),
           ReleaseTracking.tmdb_type_for(item.media_type),
           item.name,
           season_number: release.season_number,
           episode_number: release.episode_number,
           min_quality: AutoGrabSettings.effective_min_quality(item.min_quality, settings),
           max_quality: AutoGrabSettings.effective_max_quality(item.max_quality, settings),
           quality_4k_patience_hours:
             AutoGrabSettings.effective_patience_hours(
               item.quality_4k_patience_hours,
               settings
             )
         ) do
      {:ok, _target} ->
        Log.info(:library, "auto-acquisition armed — #{item.name} #{describe_release(release)}")

      {:error, reason} ->
        Log.warning(:library, "auto-acquisition enqueue failed — #{inspect(reason)}")
    end
  end

  defp apply_decision({:cancel, :user_disabled}, item, _release, _settings, existing_target) do
    if existing_target do
      cancel_target(existing_target.id, CancelReasons.user_disabled())
      Log.info(:library, "auto-acquisition cancelled (user disabled) — #{item.name}")
    end
  end

  defp apply_decision({:skip, :acquisition_unavailable}, item, _release, _settings, _target) do
    Log.info(:library, "auto-acquisition skipped (prowlarr not ready) — #{item.name}")
  end

  defp apply_decision({:skip, :mode_off}, _item, _release, _settings, _target), do: :ok
  defp apply_decision({:skip, :already_in_library}, _item, _release, _settings, _target), do: :ok
  defp apply_decision({:skip, :already_active}, _item, _release, _settings, _target), do: :ok

  defp describe_release(%{season_number: season, episode_number: episode}),
    do: Format.episode_label(season, episode)

  @doc """
  Cancels every active target whose pursuit matches `(tmdb_id, tmdb_type)`.
  Used by the `Reactor` when a tracked item is removed.

  The cancellation is one `update_all` regardless of how many targets
  match — broadcasts still fire per-target so existing subscribers
  (LiveViews, decision-card refreshers) receive the same
  `{:target_cancelled, target}` shape they always have.
  """
  @spec cancel_active_targets_for(String.t(), String.t(), String.t()) :: :ok
  def cancel_active_targets_for(tmdb_id, tmdb_type, reason) when is_binary(reason) do
    pursuits =
      Repo.all(
        from(p in Pursuit,
          where: p.recipe_type == "tmdb" and p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type
        )
      )

    target_ids = pursuits |> Enum.map(& &1.current_target_id) |> Enum.reject(&is_nil/1)

    case target_ids do
      [] ->
        :ok

      ids ->
        bulk_cancel_targets(ids, reason)
        :ok
    end
  end

  # Single SQL update for all in-flight targets, then per-target
  # broadcast off the returning rows so subscribers see the same shape
  # as the single-target `cancel_target/2` path.
  defp bulk_cancel_targets(target_ids, reason) do
    now = DateTime.utc_now(:second)

    {_count, updated} =
      Repo.update_all(
        from(t in Target,
          where: t.id in ^target_ids and t.status in ^TargetStatus.in_flight(),
          select: t
        ),
        set: [
          status: "cancelled",
          cancelled_at: now,
          cancelled_reason: reason,
          next_attempt_at: nil,
          updated_at: now
        ]
      )

    Enum.each(updated, fn %Target{} = target ->
      broadcast({:target_cancelled, target})
      Log.info(:library, "target cancelled — #{target.title} (#{reason})")
    end)
  end

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
