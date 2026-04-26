defmodule MediaCentarr.Acquisition do
  use Boundary,
    deps: [MediaCentarr.Capabilities, MediaCentarr.Library, MediaCentarr.ReleaseTracking],
    exports: [Quality, QueryExpander, QueueItem, Prowlarr, DownloadClient.QBittorrent]

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
    Config,
    Grab,
    Jobs.SearchAndGrab,
    Prowlarr
  }

  alias MediaCentarr.Acquisition.DownloadClient.Dispatcher
  alias MediaCentarr.Capabilities
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
  Submits a grab request for a search result to Prowlarr.

  Returns `{:error, :not_configured}` when Prowlarr is not configured.
  """
  @spec grab(map()) :: :ok | {:error, term()}
  def grab(result) do
    if available?() do
      Prowlarr.grab(result)
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

    case get_or_create_grab(tmdb_id, tmdb_type, title, season, episode, year) do
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
    existing_status =
      case find_grab(
             to_string(item.tmdb_id),
             to_string(item.media_type),
             release.season_number,
             release.episode_number
           ) do
        nil -> nil
        grab -> grab.status
      end

    decision =
      AutoGrabPolicy.decide(release.in_library, existing_status,
        prowlarr_ready: Capabilities.prowlarr_ready?()
      )

    case decision do
      :enqueue ->
        case enqueue(to_string(item.tmdb_id), to_string(item.media_type), item.name,
               season_number: release.season_number,
               episode_number: release.episode_number
             ) do
          {:ok, _grab} ->
            Log.info(:library, "auto-grab armed — #{item.name} #{describe_release(release)}")

          {:error, reason} ->
            Log.warning(:library, "auto-grab enqueue failed — #{inspect(reason)}")
        end

      {:skip, :acquisition_unavailable} ->
        Log.info(:library, "auto-grab skipped (prowlarr not ready) — #{item.name}")

      {:skip, :already_in_library} ->
        :ok

      {:skip, :already_active} ->
        :ok
    end
  end

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

  defp get_or_create_grab(tmdb_id, tmdb_type, title, season, episode, year) do
    case find_grab(tmdb_id, tmdb_type, season, episode) do
      nil ->
        Repo.insert(
          Grab.create_changeset(%{
            tmdb_id: tmdb_id,
            tmdb_type: tmdb_type,
            title: title,
            year: year,
            season_number: season,
            episode_number: episode
          })
        )

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
