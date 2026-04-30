defmodule MediaCentarr.Acquisition do
  use Boundary,
    deps: [
      MediaCentarr.Capabilities,
      MediaCentarr.Library,
      MediaCentarr.ReleaseTracking,
      MediaCentarr.Settings
    ],
    exports: [
      AutoGrabSettings,
      Grab,
      Quality,
      QueryExpander,
      QueueItem,
      Prowlarr,
      DownloadClient.QBittorrent
    ]

  @moduledoc """
  Public facade for the Acquisition bounded context.

  Acquisition is optional — call `available?/0` before exposing any UI surfaces.
  When Prowlarr is not configured, `available?/0` returns false and search/grab
  return `{:error, :not_configured}`.

  ## Automated acquisition

  This module is also a `GenServer` that subscribes to release-tracking
  PubSub events:

  - `{:release_ready, item, release}` — a tracked release is now available.
    The capability gate is enforced via `Capabilities.prowlarr_ready?/0` —
    if false, the message is dropped (logged) and nothing is enqueued.
    Otherwise the message is translated through `AutoGrabPolicy.decide/3`
    into either a grab enqueue, a no-op skip, or a cancellation.
  - `{:item_removed, tmdb_id, tmdb_type}` — a tracked item was removed.
    Active (`searching`/`snoozed`) grabs for that key are cancelled.

  ## Manual search

  Call `search/2` with a query string. Pass the chosen `%SearchResult{}` to
  `grab/1` to submit it to Prowlarr.

  ## PubSub broadcasts

  Subscribe with `Acquisition.subscribe/0` to receive (on `acquisition:updates`):

  - `{:grab_submitted, grab}` — Prowlarr accepted the release
  - `{:auto_grab_snoozed, grab}` — search ran, no acceptable result, will retry
  - `{:auto_grab_abandoned, grab}` — max attempts reached, no longer retrying
  - `{:auto_grab_cancelled, grab}` — `cancel_grab/2` was called
  """

  use GenServer

  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.{
    AutoGrabPolicy,
    AutoGrabSettings,
    Config,
    Grab,
    Jobs.SearchAndGrab,
    Prowlarr,
    SearchResult
  }

  alias MediaCentarr.Acquisition.DownloadClient.Dispatcher
  alias MediaCentarr.Capabilities
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  @cancellable_statuses ["searching", "snoozed"]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available?, do: Config.available?()

  @doc "Subscribes to acquisition PubSub updates."
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
  end

  @doc """
  Subscribes to download-client queue snapshots. Receivers get
  `{:queue_snapshot, [QueueItem.t()]}` whenever the QueueMonitor polls
  successfully (every 5s with a configured download client, 30s when
  the client is offline).
  """
  def subscribe_queue do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_queue())
  end

  @doc """
  Subscribes the calling process to search session updates. Receivers get
  `{:search_session, %SearchSession{}}` on every state change.
  """
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

  @doc "Updates the query input box value and recomputes the expansion preview."
  @spec set_query_preview(String.t()) :: :ok
  defdelegate set_query_preview(query), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets `term => guid` in the session selections map."
  @spec set_selection(String.t(), String.t()) :: :ok
  defdelegate set_selection(term, guid), to: MediaCentarr.Acquisition.SearchSession

  @doc "Removes `term` from the session selections map."
  @spec clear_selection(String.t()) :: :ok
  defdelegate clear_selection(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Empties the session selections map."
  @spec clear_selections() :: :ok
  defdelegate clear_selections(), to: MediaCentarr.Acquisition.SearchSession

  @doc "Toggles `expanded?` on the named group."
  @spec toggle_group(String.t()) :: :ok
  defdelegate toggle_group(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the boolean `grabbing?` flag on the session."
  @spec set_grabbing(boolean()) :: :ok
  defdelegate set_grabbing(value), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the last-grab outcome message on the session."
  @spec set_grab_message({:ok | :partial | :error, String.t()}) :: :ok
  defdelegate set_grab_message(message), to: MediaCentarr.Acquisition.SearchSession

  @doc "Resets the entire search session to the default empty state."
  @spec clear_search_session() :: :ok
  defdelegate clear_search_session(), to: MediaCentarr.Acquisition.SearchSession, as: :clear

  @doc """
  Re-arms named groups (`:abandoned` / `{:failed, _}` -> `:loading`). The
  caller's pid becomes the monitored `searching_pid`. The caller is
  responsible for spawning Tasks for these terms.
  """
  @spec retry_search_terms([String.t()]) :: :ok
  defdelegate retry_search_terms(terms), to: MediaCentarr.Acquisition.SearchSession

  @doc """
  Returns the latest cached download-client queue snapshot. Synchronous;
  reads `:persistent_term`, no GenServer call. Returns `[]` before the
  first successful poll or when no download client is configured.
  """
  @spec queue_snapshot() :: [MediaCentarr.Acquisition.QueueItem.t()]
  defdelegate queue_snapshot, to: MediaCentarr.Acquisition.QueueMonitor, as: :snapshot

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
  Submits a manual grab request to Prowlarr and records it in the
  unified activity timeline.

  On Prowlarr success, inserts an `acquisition_grabs` row in terminal
  `"grabbed"` state with `origin: "manual"` and broadcasts
  `{:grab_submitted, grab}` so the activity list refreshes. The
  Prowlarr GUID doubles as the row's `tmdb_id` (with `tmdb_type: "manual"`)
  so the unique index naturally prevents double-grabbing the same release.

  `query` is the search string the user typed — stored on the row for the
  "where did this come from?" surface in the activity list.

  Returns `{:error, :not_configured}` when Prowlarr is not configured,
  or `{:error, reason}` when Prowlarr rejects the grab.
  """
  @spec grab(SearchResult.t(), String.t()) :: {:ok, Grab.t()} | {:error, term()}
  def grab(%SearchResult{} = result, query) when is_binary(query) do
    if available?() do
      with :ok <- Prowlarr.grab(result),
           {:ok, grab} <- Repo.insert(Grab.manual_grabbed_changeset(result, query)) do
        broadcast({:grab_submitted, grab})
        Log.info(:library, "manual grab submitted — #{result.title}")
        {:ok, grab}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Returns true when a download client is configured (type + URL set).
  """
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
  Cancels a download by id. Destructive — the torrent and any downloaded
  files are removed from the client.

  Returns `{:error, :not_configured}` when no driver is configured.
  """
  @spec cancel_download(String.t()) :: :ok | {:error, term()}
  def cancel_download(id) do
    with {:ok, driver} <- Dispatcher.driver() do
      driver.cancel_download(id)
    end
  end

  @doc """
  Tests connectivity and credentials against Prowlarr.

  Returns `{:error, :not_configured}` when Prowlarr is not configured.
  """
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
  episode_number)`. A second call for the same tuple returns the existing
  grab without re-enqueueing the job (the Oban worker is unique-keyed too).

  Options:
  - `:season_number` — integer season (TV episodes/season packs)
  - `:episode_number` — integer episode (TV episodes only)
  - `:year` — integer release year (movies — used in the Prowlarr query)
  """
  @spec enqueue(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Grab.t()} | {:error, term()}
  def enqueue(tmdb_id, tmdb_type, title, opts \\ []) do
    season = Keyword.get(opts, :season_number)
    episode = Keyword.get(opts, :episode_number)
    year = Keyword.get(opts, :year)
    min_quality = Keyword.get(opts, :min_quality)
    max_quality = Keyword.get(opts, :max_quality)
    patience_hours = Keyword.get(opts, :quality_4k_patience_hours)
    origin = Keyword.get(opts, :origin, "auto")

    snapshot = %{
      min_quality: min_quality,
      max_quality: max_quality,
      quality_4k_patience_hours: patience_hours,
      origin: origin
    }

    case get_or_create_grab(tmdb_id, tmdb_type, title, season, episode, year, snapshot) do
      {:ok, %Grab{status: status} = grab} when status in ["grabbed", "abandoned", "cancelled"] ->
        # Terminal — don't re-enqueue an Oban job. Caller decides whether
        # to call cancel_grab/2 or accept the existing terminal state.
        {:ok, grab}

      {:ok, grab} ->
        Oban.insert(SearchAndGrab.new(%{"grab_id" => grab.id}))
        {:ok, grab}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple → the
  matching `Grab` row. Keys with no matching row are absent from the map.

  Single SQL query — used by the upcoming-zone renderer to decorate each
  release card with its grab status without N+1ing the DB.

  Manual-origin grabs use synthetic `tmdb_id = guid, tmdb_type = "manual"`
  keys, so they only match callers that pass that exact shape — release
  tracker callers passing real TMDB ids never accidentally hit them.
  """
  @spec statuses_for_releases([{String.t(), String.t(), integer() | nil, integer() | nil}]) ::
          %{
            {String.t(), String.t(), integer() | nil, integer() | nil} => Grab.t()
          }
  def statuses_for_releases([]), do: %{}

  def statuses_for_releases(keys) when is_list(keys) do
    {tmdb_ids, tmdb_types} =
      keys
      |> Enum.map(fn {id, type, _, _} -> {id, type} end)
      |> Enum.unzip()

    tmdb_ids = Enum.uniq(tmdb_ids)
    tmdb_types = Enum.uniq(tmdb_types)

    rows =
      Repo.all(
        from(g in Grab,
          where: g.tmdb_id in ^tmdb_ids and g.tmdb_type in ^tmdb_types
        )
      )

    requested = MapSet.new(keys)

    rows
    |> Enum.map(fn grab ->
      {{grab.tmdb_id, grab.tmdb_type, grab.season_number, grab.episode_number}, grab}
    end)
    |> Enum.filter(fn {key, _grab} -> MapSet.member?(requested, key) end)
    |> Map.new()
  end

  @doc """
  Bulk-enqueues grabs for every release of a tracked item that is released,
  not in the library, and of an acquirable type, skipping any that already
  have a grab row (in any state — terminal grabs are intentionally not
  re-armed by this path; the user must re-arm them individually).

  Returns a summary so the caller can decide what to flash:

      {:ok, %{queued: 3, skipped_in_flight: 1, failed: []}}

  Idempotent — calling twice for the same item without intervening state
  changes yields `queued: 0, skipped_in_flight: N` on the second call.
  """
  @spec enqueue_all_pending_for_item(item_id :: String.t()) ::
          {:ok,
           %{
             queued: non_neg_integer(),
             skipped_in_flight: non_neg_integer(),
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
        Enum.map(pending, fn r -> {tmdb_id, tmdb_type, r.season_number, r.episode_number} end)

      grab_map = statuses_for_releases(keys)

      summary =
        Enum.reduce(pending, %{queued: 0, skipped_in_flight: 0, failed: []}, fn release, acc ->
          key = {tmdb_id, tmdb_type, release.season_number, release.episode_number}

          case Map.get(grab_map, key) do
            nil ->
              case enqueue(tmdb_id, tmdb_type, name,
                     season_number: release.season_number,
                     episode_number: release.episode_number
                   ) do
                {:ok, _grab} -> %{acc | queued: acc.queued + 1}
                {:error, reason} -> %{acc | failed: [{key, reason} | acc.failed]}
              end

            _grab ->
              %{acc | skipped_in_flight: acc.skipped_in_flight + 1}
          end
        end)

      {:ok, summary}
    end
  end

  @doc """
  Lists `acquisition_grabs` filtered by lifecycle stage.

  - `:all` — every row, newest-updated first
  - `:active` — `searching` or `snoozed` (the live job set)
  - `:abandoned` — gave up after max attempts
  - `:cancelled` — explicitly cancelled
  - `:grabbed` — completed successfully
  """
  @spec list_auto_grabs(:all | :active | :abandoned | :cancelled | :grabbed) :: [Grab.t()]
  def list_auto_grabs(filter \\ :all) do
    Grab
    |> auto_grabs_filter(filter)
    |> order_by([g], desc: g.updated_at)
    |> Repo.all()
  end

  defp auto_grabs_filter(query, :all), do: query
  defp auto_grabs_filter(query, :active), do: where(query, [g], g.status in ^@cancellable_statuses)
  defp auto_grabs_filter(query, status), do: where(query, [g], g.status == ^to_string(status))

  @doc """
  Re-arms a cancelled or abandoned grab back to `searching` and
  re-enqueues a `SearchAndGrab` Oban job. No-op (returns the grab as-is)
  if the grab is in any other state — including already-searching, where
  there's nothing to re-arm.

  Resets `attempt_count` to 0 so the snooze schedule starts fresh.
  Broadcasts `{:auto_grab_armed, grab}` so the UI refreshes.
  """
  @spec rearm_grab(Ecto.UUID.t()) :: {:ok, Grab.t()} | {:error, :not_found}
  def rearm_grab(grab_id) do
    case Repo.get(Grab, grab_id) do
      nil ->
        {:error, :not_found}

      %Grab{status: status} = grab when status in ["cancelled", "abandoned"] ->
        {:ok, rearmed} =
          grab
          |> Ecto.Changeset.change(
            status: "searching",
            attempt_count: 0,
            cancelled_at: nil,
            cancelled_reason: nil,
            last_attempt_outcome: nil
          )
          |> Repo.update()

        Oban.insert(SearchAndGrab.new(%{"grab_id" => rearmed.id}))
        broadcast({:auto_grab_armed, rearmed})
        Log.info(:library, "auto-grab re-armed — #{rearmed.title}")
        {:ok, rearmed}

      grab ->
        # Already active or already grabbed — nothing to re-arm.
        {:ok, grab}
    end
  end

  @doc """
  Cancels an active grab (status `searching` or `snoozed`). No-op for
  terminal-state grabs; broadcasts `{:auto_grab_cancelled, grab}` only
  when the row was actually flipped.

  `reason` is a short string stored on the grab row for visibility
  (`"item_removed"`, `"user_disabled"`, `"in_library"`, etc.).
  """
  @spec cancel_grab(Ecto.UUID.t(), String.t()) ::
          {:ok, Grab.t()} | {:error, :not_found}
  def cancel_grab(grab_id, reason) when is_binary(reason) do
    case Repo.get(Grab, grab_id) do
      nil ->
        {:error, :not_found}

      %Grab{status: status} = grab when status not in @cancellable_statuses ->
        # Already terminal — nothing to do.
        {:ok, grab}

      grab ->
        {:ok, cancelled} = Repo.update(Grab.cancelled_changeset(grab, reason))
        broadcast({:auto_grab_cancelled, cancelled})
        Log.info(:library, "acquisition cancelled — #{grab.title} (#{reason})")
        {:ok, cancelled}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer — subscribes to release_tracking:updates
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.release_tracking_updates())
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:release_ready, item, release}, state) do
    handle_release_ready(item, release)
    {:noreply, state}
  end

  def handle_info({:item_removed, tmdb_id, tmdb_type}, state) do
    cancel_active_grabs_for(tmdb_id, tmdb_type, "item_removed")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp handle_release_ready(item, release) do
    settings = AutoGrabSettings.load()

    existing_grab =
      find_grab(
        to_string(item.tmdb_id),
        to_string(item.media_type),
        release.season_number,
        release.episode_number
      )

    existing_status = existing_grab && existing_grab.status

    effective_mode = AutoGrabSettings.effective_mode(item.auto_grab_mode, settings)

    decision =
      AutoGrabPolicy.decide(release.in_library, existing_status,
        prowlarr_ready: Capabilities.prowlarr_ready?(),
        mode: effective_mode
      )

    apply_decision(decision, item, release, settings, existing_grab)
  end

  defp apply_decision(:enqueue, item, release, settings, _existing_grab) do
    case enqueue(to_string(item.tmdb_id), to_string(item.media_type), item.name,
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
      {:ok, _grab} ->
        Log.info(:library, "auto-grab armed — #{item.name} #{describe_release(release)}")

      {:error, reason} ->
        Log.warning(:library, "auto-grab enqueue failed — #{inspect(reason)}")
    end
  end

  defp apply_decision({:cancel, :user_disabled}, item, _release, _settings, existing_grab) do
    cancel_grab(existing_grab.id, "user_disabled")
    Log.info(:library, "auto-grab cancelled (user disabled) — #{item.name}")
  end

  defp apply_decision({:skip, :acquisition_unavailable}, item, _release, _settings, _grab) do
    Log.info(:library, "auto-grab skipped (prowlarr not ready) — #{item.name}")
  end

  defp apply_decision({:skip, :mode_off}, _item, _release, _settings, _grab), do: :ok
  defp apply_decision({:skip, :already_in_library}, _item, _release, _settings, _grab), do: :ok
  defp apply_decision({:skip, :already_active}, _item, _release, _settings, _grab), do: :ok

  defp describe_release(%{season_number: nil, episode_number: nil}), do: ""
  defp describe_release(%{season_number: season, episode_number: nil}), do: "S#{season}"

  defp describe_release(%{season_number: season, episode_number: episode}),
    do: "S#{pad2(season)}E#{pad2(episode)}"

  defp pad2(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp pad2(n), do: Integer.to_string(n)

  defp cancel_active_grabs_for(tmdb_id, tmdb_type, reason) do
    grabs =
      Repo.all(
        from(g in Grab,
          where:
            g.tmdb_id == ^tmdb_id and g.tmdb_type == ^tmdb_type and
              g.status in ^@cancellable_statuses
        )
      )

    Enum.each(grabs, fn grab -> cancel_grab(grab.id, reason) end)
  end

  defp get_or_create_grab(tmdb_id, tmdb_type, title, season, episode, year, snapshot) do
    case find_grab(tmdb_id, tmdb_type, season, episode) do
      nil ->
        attrs =
          Map.merge(
            %{
              tmdb_id: tmdb_id,
              tmdb_type: tmdb_type,
              title: title,
              year: year,
              season_number: season,
              episode_number: episode
            },
            snapshot
          )

        Repo.insert(Grab.create_changeset(attrs))

      grab ->
        {:ok, grab}
    end
  end

  # Ecto's `get_by/2` rejects nil in equality clauses; nullable fields need
  # `is_nil/1` in a query. This helper applies the right matcher per field.
  defp find_grab(tmdb_id, tmdb_type, season, episode) do
    Grab
    |> where([g], g.tmdb_id == ^tmdb_id and g.tmdb_type == ^tmdb_type)
    |> where_match(:season_number, season)
    |> where_match(:episode_number, episode)
    |> Repo.one()
  end

  defp where_match(query, field, nil), do: where(query, [g], is_nil(field(g, ^field)))
  defp where_match(query, field, value), do: where(query, [g], field(g, ^field) == ^value)

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.acquisition_updates(),
      message
    )
  end
end
