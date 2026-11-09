defmodule MediaCentaur.Acquisition do
  use Boundary,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.Watchlist,
      MediaCentaur.Downloads,
      MediaCentaur.ErrorReports,
      MediaCentaur.HttpClient,
      MediaCentaur.IntegrationAvailability,
      MediaCentaur.Library,
      MediaCentaur.ReleaseTracking,
      MediaCentaur.Retention,
      MediaCentaur.Review,
      MediaCentaur.Search,
      MediaCentaur.Settings,
      MediaCentaur.Settings.Preferences,
      MediaCentaur.TMDB,
      MediaCentaur.TmdbArtwork,
      MediaCentaur.Watcher
    ],
    exports: [
      Supervisor,
      AutoGrabSettings,
      CancelReasons,
      DownloadParams,
      PlanEvents,
      PlanEvents.Changed,
      PlanEvents.SearchProgress,
      PlanEvents.SearchActivity,
      GrabProvenance,
      Plans,
      Plans.DownloadScope,
      Plans.Alternatives,
      Plans.Board,
      Plans.Plan,
      Plans.PlanUnit,
      Targeting,
      TitleDownloadParams,
      TitleStates,
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
      ViewModels.SearchProgressPanel,
      ViewModels.SearchProgressPanel.Row,
      ViewModels.SearchProgressPanel.View,
      ViewModels.DownloadProgress,
      ViewModels.GapEvidence,
      ViewModels.GapEvidence.Rejected,
      ViewModels.GapEvidence.Search,
      ViewModels.GapVerdict,
      ViewModels.Rejection,
      ViewModels.NextStep,
      ViewModels.PlanBoard,
      ViewModels.PlanBoard.Alternative,
      ViewModels.PlanBoard.BelowPreference,
      ViewModels.PlanBoard.Cell,
      ViewModels.PlanBoard.Line,
      ViewModels.PlanBoard.Offer,
      ViewModels.PlanBoard.Overlap,
      ViewModels.PlanBoard.SeasonRow,
      ViewModels.PlanBoard.Release,
      ViewModels.PursuitHeader,
      ViewModels.PursuitRow,
      ViewModels.PursuitStatus,
      ViewModels.PursuitWithDownload,
      ViewModels.SearchOutage,
      ViewModels.Timeline,
      # History's rows and the pointer resolver: the component draws a Run,
      # stories and tests build a Resolver (pursuit-window M4).
      ViewModels.Timeline.Run,
      ViewModels.Timeline.Resolver,
      ViewModels.TimelineEntry,
      ViewModels.UnitBoard,
      ViewModels.UnitBoard.Group,
      ViewModels.UnitBoard.Row,
      # The board's attempts and its fold: the component draws an Attempt,
      # stories build them (pursuit-window M5).
      ViewModels.UnitBoard.Attempt,
      ViewModels.UnitBoard.Fold
    ]

  @moduledoc """
  Public facade for the Acquisition bounded context.

  Acquisition is optional — call `available?/0` before exposing any UI
  surfaces. When Prowlarr is not configured, `available?/0` returns
  false and search/pick return `{:error, :not_configured}`.

  ## Domain shape

  - **Pursuit** — the intent. Owns the recipe (`tmdb` or
    `prowlarr_query`) and the lifecycle.
  - **Target** — one grab attempt of one release. A pursuit's units each
    point at their current attempt (`unit.current_target_id`, ADR-055);
    a pursuit has many targets over its lifetime.
  - **Recipe** — `pursuit.recipe_type` discriminator plus the variant
    columns (TMDB metadata for `tmdb`, `manual_query` for
    `prowlarr_query`).

  ## Manual search

  Call `search/2` with a query string. Pass the chosen `%SearchResult{}`
  to `pick_target/2` to start a pursuit with it; the release is recorded
  as a `grabbing` target and `Jobs.GrabTarget` hands it to Prowlarr.

  ## PubSub broadcasts

  Subscribe with `subscribe/0` to receive (on `acquisition:updates`):

  - `%TargetEvents.Acquired{}` — Prowlarr accepted the release
  - `%TargetEvents.Picked{}` — user picked a release
  - `%TargetEvents.Armed{}` — target re-armed into seeking
  - `%TargetEvents.Snoozed{}` — search ran, no acceptable result, will retry
  - `%TargetEvents.Failed{}` — max attempts reached, or Prowlarr refused a
    chosen release; no longer retrying that target
  - `%TargetEvents.Cancelled{}` — target cancelled
  - `Pursuits.Events.*` typed structs — persisted timeline events

  All broadcasts are typed structs; pattern-match on the struct
  module. Use `TargetEvents.event?/1` and `Pursuits.Events.event?/1`
  in a catch-all clause to recognise the family without enumerating
  every kind.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities

  alias MediaCentaur.Acquisition.{
    AutoGrabService,
    CancelReasons,
    Corpus,
    Cours,
    FirstRelease,
    Target,
    TargetEvents,
    Targets
  }

  alias MediaCentaur.Search.{Assessment, Criteria, Prowlarr, QueryBuilder, QueryExpander, SearchResult}

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Cancel, PickTarget, StartFromPick}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Recipe, Units}
  alias MediaCentaur.Acquisition.Pursuits, as: PursuitsContext

  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Topics

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available?, do: Capabilities.configured?(:prowlarr)

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
  `MediaCentaurWeb.DownloadsLive`'s moduledoc).
  """
  @type queue_message ::
          {:queue_state, MediaCentaur.Downloads.QueueState.t()}

  @doc "Subscribes the caller to target lifecycle events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.acquisition_updates())
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
    :ok = Topics.subscribe(Topics.acquisition_queue())
    MediaCentaur.Downloads.QueueMonitor.register_subscriber(self())
  end

  @doc """
  Returns the latest cached `%QueueState{}` — items plus liveness
  metadata. Synchronous; reads `:persistent_term`.
  """
  @spec queue_state() :: MediaCentaur.Downloads.QueueState.t()
  defdelegate queue_state, to: MediaCentaur.Downloads.QueueMonitor, as: :state

  @doc """
  The download-client condition as the Downloads Heads-up glyph reads it:
  the worse of the app's own link to the client
  (`Downloads.IncidentContext`) and Prowlarr's own, read from
  `IntegrationAvailability` (`Pursuits.IncidentContext`). `:ok` while
  both are healthy. The same
  probes the Status page's acquisition incident is built from (ADR-054),
  read live — the glyph shows a condition while it holds, never a
  history.
  """
  @spec client_health() :: MediaCentaur.Acquisition.IncidentContext.assessment()
  def client_health do
    MediaCentaur.Acquisition.IncidentContext.worst([
      MediaCentaur.Downloads.IncidentContext.assess(),
      MediaCentaur.Acquisition.Pursuits.IncidentContext.assess()
    ])
  end

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
  `opts` are `Prowlarr.search/2`'s.
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
  Runs `search/1` for one query on the context's task supervisor, owned by
  the caller: the returned task is unlinked, and the caller receives
  `{ref, {:ok, results} | {:error, reason}}` and then the task's `:DOWN`
  (`Task.Supervisor.async_nolink/2`). The spawn stays in the context layer
  (ADR-049); the owner is whoever shows the search —
  `MediaCentaurWeb.DownloadsLive.SearchSession`, which outlives the LiveView
  that asked. A user-initiated search always hits the indexers live, and its
  findings still feed the durable corpus (ADR-055).
  """
  @spec search_async(String.t()) :: Task.t()
  def search_async(query) when is_binary(query) do
    Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn ->
      outcome = search(query)
      with {:ok, results} <- outcome, do: Corpus.record!(query, [], results)
      outcome
    end)
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
    with {:ok, outcomes} <- search_terms(query, opts) do
      {:ok,
       outcomes
       |> Enum.flat_map(fn
         %{outcome: {:ok, results}} -> results
         %{outcome: {:error, _reason}} -> []
       end)
       |> Enum.uniq_by(& &1.guid)}
    end
  end

  @doc """
  Expands braces and searches each term in parallel, reporting every term's
  own outcome in term order, so a caller can tell a term that failed from
  one that found nothing. Per-term searches go through the corpus
  (consult-first, ADR-055); `force: true` bypasses its freshness window.

  `{:error, :invalid_syntax}` for malformed braces, `{:error,
  :not_configured}` when Prowlarr isn't ready.
  """
  @spec search_terms(String.t(), keyword()) ::
          {:ok, [%{term: String.t(), outcome: {:ok, [SearchResult.t()]} | {:error, term()}}]}
          | {:error, term()}
  def search_terms(query, opts \\ []) when is_binary(query) do
    if available?() do
      with {:ok, terms} <- QueryExpander.expand(query) do
        outcomes =
          terms
          |> Task.async_stream(
            fn term -> Corpus.search(term, opts) end,
            max_concurrency: 5,
            timeout: 15_000,
            on_timeout: :kill_task
          )
          |> Enum.zip(terms)
          |> Enum.map(fn {task_result, term} -> %{term: term, outcome: term_outcome(task_result)} end)

        {:ok, outcomes}
      end
    else
      {:error, :not_configured}
    end
  end

  defp term_outcome({:ok, {:ok, results}}) when is_list(results), do: {:ok, results}
  defp term_outcome({:ok, {:error, reason}}), do: {:error, reason}
  defp term_outcome({:exit, reason}), do: {:error, reason}

  @doc """
  Submits a manual pick: a pursuit with `recipe_type = "prowlarr_query"`
  and the user's typed query, and the release as a `grabbing` target
  (`StartFromPick`); `Jobs.GrabTarget` performs the grab. Broadcasts
  `%TargetEvents.Picked{}`. The Prowlarr GUID is recorded on the target so
  the duplicate-guid check in `ChangeTarget` works.

  Returns `{:error, :not_configured}` when Prowlarr is not configured. A
  release Prowlarr then refuses is reported on the pursuit, which searches
  its query again.
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

  Every pick is recorded as a `grabbing` target in one transaction, and
  each grab runs in its own `Jobs.GrabTarget` — nothing here asks
  Prowlarr, so a page may call it from its handler. Returns `{:ok, pairs}`
  where `pairs` aligns with the input picks as `{pick, {:ok, target}}`.
  Broadcasts `%TargetEvents.Picked{}` per pick.

  Returns `{:error, :not_configured}` when Prowlarr is not configured.
  """
  @spec pick_targets([%{term: String.t() | nil, result: SearchResult.t()}], String.t()) ::
          {:ok, [{map(), {:ok, Target.t()} | {:error, term()}}]} | {:error, :not_configured}
  def pick_targets(picks, query) when is_list(picks) and is_binary(query) do
    if available?() do
      with {:ok, targets_by_guid} <- start_from_picks(picks, query) do
        {:ok, Enum.map(picks, &pair_outcome(&1, targets_by_guid))}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Grabs releases earlier searches found, by guid, as one composite pursuit
  (`pick_targets/2`). A guid named twice is grabbed once. Every guid must be
  known to the corpus: an unknown one grabs nothing and answers
  `{:error, {:release_unavailable, guid}}`.
  """
  @spec grab_releases([%{guid: String.t(), term: String.t()}], String.t()) ::
          {:ok, [Target.t()]} | {:error, term()}
  def grab_releases(picks, query) when is_list(picks) and is_binary(query) do
    with {:ok, resolved} <- resolve_picks(Enum.uniq_by(picks, & &1.guid)),
         {:ok, pairs} <- pick_targets(resolved, query) do
      {:ok, Enum.map(pairs, fn {_pick, {:ok, target}} -> target end)}
    end
  end

  defp resolve_picks(picks) do
    Enum.reduce_while(picks, {:ok, []}, fn %{guid: guid, term: term}, {:ok, resolved} ->
      case fetch_release(guid) do
        {:ok, result} -> {:cont, {:ok, resolved ++ [%{term: term, result: result}]}}
        {:error, :release_unavailable} -> {:halt, {:error, {:release_unavailable, guid}}}
      end
    end)
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
        :acquisition,
        "manual pick recorded — #{pursuit.title} (#{length(targets)} release(s))"
      )

      {:ok, Map.new(targets, &{&1.prowlarr_guid, &1})}
    end
  end

  defp pair_outcome(pick, targets_by_guid) do
    case Map.get(targets_by_guid, pick.result.guid) do
      %Target{} = target -> {pick, {:ok, target}}
      nil -> {pick, {:error, :not_persisted}}
    end
  end

  defp trim_query(query) do
    case String.trim(query) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Picks an alternative release on an existing pursuit — the decision
  card. The pick is recorded at once — a grabbing target on the units it
  covers, with its `Jobs.GrabTarget` (`Commands.PickTarget`) — and the grab
  follows in the job, so nothing here asks Prowlarr and a page may call it
  from its handler.

  Accepts either the `%SearchResult{}` the card showed, or its `guid`, read
  back from the corpus the card's search recorded it in (`Corpus.find/1`).

  Returns `{:error, :not_found}` when the pursuit is gone, or
  `{:error, :release_unavailable}` when the corpus no longer knows the
  guid.
  """
  @spec pick_alternative(Ecto.UUID.t(), SearchResult.t() | String.t(), String.t()) ::
          {:ok, Pursuit.t()} | {:error, term()}
  def pick_alternative(pursuit_id, %SearchResult{} = result, label) when is_binary(label) do
    with {:ok, %Pursuit{} = pursuit} <- PursuitsContext.fetch(pursuit_id) do
      do_pick_alternative(pursuit, result, label)
    end
  end

  def pick_alternative(pursuit_id, guid, label) when is_binary(guid) and is_binary(label) do
    with {:ok, %Pursuit{} = pursuit} <- PursuitsContext.fetch(pursuit_id),
         {:ok, result} <- fetch_release(guid) do
      do_pick_alternative(pursuit, result, label)
    end
  end

  @doc """
  Picks a release a search recorded, by guid, labelled with its title as
  the decision card labels it. `pick_alternative/3`'s errors, except that
  an unknown guid is named: `{:error, {:release_unavailable, guid}}`.
  """
  @spec pick_alternative(Ecto.UUID.t(), String.t()) :: {:ok, Pursuit.t()} | {:error, term()}
  def pick_alternative(pursuit_id, guid) when is_binary(guid) do
    case fetch_release(guid) do
      {:ok, result} -> pick_alternative(pursuit_id, result, result.title)
      {:error, :release_unavailable} -> {:error, {:release_unavailable, guid}}
    end
  end

  defp do_pick_alternative(%Pursuit{} = pursuit, %SearchResult{} = result, label) do
    with {:ok, updated} <-
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
  The releases a pursuit could pivot to, for its decision card: every
  release its recipe's search finds, judged for the awaiting-or-lead
  unit (ADR-055).

    * `offered` — up to 8 releases with their assessments. A release of
      the title that contains the unit is offered; a flagged one too,
      after the clean ones, so the card can mark it instead of hiding it.
    * `left_out` — `[{reason, count}]` for the rest, by the first gate
      each failed, in gate order. A release the unit already tried is
      `:excluded`.

  A TMDB pursuit searches exactly as the plan side and the retry loop
  do: its own terms first (`QueryBuilder.build/1`), then, for a TV unit,
  the wider terms that can only offer a pack (`QueryBuilder.fallback/1`),
  and each result is judged by `Search.Assessment` (`:covering`). A
  user-typed query searches its phrasing — the unit's own term when it
  has one — and only what was already tried is left out.

  Searches consult the corpus first (ADR-055 citizenship); pass
  `force: true` for the user-initiated "Search Prowlarr again" refresh.
  """
  @spec assess_alternatives_for(Pursuit.t(), keyword()) :: %{
          offered: [{SearchResult.t(), Assessment.t()}],
          left_out: [{Assessment.reason(), pos_integer()}]
        }
  def assess_alternatives_for(%Pursuit{} = pursuit, search_opts \\ []) do
    unit = Units.lead(pursuit.id)
    excluded = MapSet.new((unit && unit.tried_release_guids) || [])

    assessed =
      case Recipe.for_unit(pursuit, unit) do
        %Recipe{type: :tmdb} = recipe ->
          criteria =
            recipe |> Recipe.to_criteria() |> Cours.with_run(pursuit.tmdb_id) |> FirstRelease.stamp()

          criteria
          |> search_for_title(search_opts)
          |> Enum.map(&{&1, Assessment.assess(&1, criteria, excluded: excluded, scope: :covering)})

        %Recipe{type: :prowlarr_query, manual_query: query, title: title} ->
          (query || title)
          |> search_typed(search_opts)
          |> Enum.map(
            &{&1, %Assessment{reasons: if(MapSet.member?(excluded, &1.guid), do: [:excluded], else: [])}}
          )
      end

    {offered, left_out} =
      Enum.split_with(assessed, fn {_result, assessment} ->
        Assessment.accepted?(assessment, ignoring: [:red_flag])
      end)

    %{
      offered:
        offered
        |> Enum.sort_by(fn {_result, assessment} -> :red_flag in assessment.reasons end)
        |> Enum.take(8),
      left_out:
        left_out
        |> Enum.frequencies_by(fn {_result, assessment} -> first_bar(assessment) end)
        |> Enum.sort_by(fn {reason, _count} ->
          Enum.find_index(Assessment.reasons(), &(&1 == reason))
        end)
    }
  end

  # The gate that kept a release off the card: the first it failed other
  # than the bait gate, which the card reads past.
  defp first_bar(%Assessment{reasons: reasons}), do: List.first(reasons -- [:red_flag])

  @doc "The releases `assess_alternatives_for/2` offers, without their assessments."
  @spec list_alternatives_for(Pursuit.t(), keyword()) :: [SearchResult.t()]
  def list_alternatives_for(%Pursuit{} = pursuit, search_opts \\ []) do
    pursuit
    |> assess_alternatives_for(search_opts)
    |> Map.fetch!(:offered)
    |> Enum.map(fn {result, _assessment} -> result end)
  end

  # Every release the title's terms find, unjudged. Nothing when the
  # search provider is not configured.
  defp search_for_title(%Criteria{} = criteria, search_opts) do
    if available?() do
      force? = Keyword.get(search_opts, :force, false)

      (QueryBuilder.build(criteria) ++ QueryBuilder.fallback(criteria))
      |> Enum.flat_map(fn {term, opts} ->
        case Corpus.search(term, Keyword.put(opts, :force, force?)) do
          {:ok, results} -> results
          {:error, _reason} -> []
        end
      end)
      |> Enum.uniq_by(& &1.guid)
    else
      []
    end
  end

  defp search_typed(query, search_opts) do
    case search_expanded(query, search_opts) do
      {:ok, results} -> results
      {:error, _reason} -> []
    end
  end

  @doc "A release an earlier search recorded, by guid, without searching again."
  @spec fetch_release(String.t()) :: {:ok, SearchResult.t()} | {:error, :release_unavailable}
  def fetch_release(guid) when is_binary(guid) do
    case Corpus.find(guid) do
      nil -> {:error, :release_unavailable}
      result -> {:ok, result}
    end
  end

  @doc """
  Closes a pursuit at the person's request (`Pursuits.Commands.Cancel`).
  `{:error, :not_found}` when there is no such pursuit, `{:error,
  :not_eligible}` when it is already over.
  """
  @spec cancel_pursuit(String.t()) :: {:ok, Pursuit.t()} | {:error, term()}
  def cancel_pursuit(id) do
    with {:ok, %Pursuit{} = pursuit} <- PursuitsContext.fetch(id) do
      Cancel.execute(%{
        pursuit_id: pursuit.id,
        cancelled_by: :user,
        reason: CancelReasons.user_request()
      })
    end
  end

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
    with {:ok, {config, driver}} <- Dispatcher.driver_for(protocol_for_download(id)),
         :ok <- driver.cancel_download(config, id) do
      Targets.cancel_for_download(id, CancelReasons.user_request())
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
    Topics.publish(
      Topics.acquisition_updates(),
      message
    )
  end

  defp broadcast(message), do: broadcast_update(message)
end
