defmodule MediaCentarr.Acquisition do
  use Boundary,
    deps: [],
    exports: [Quality, QueryExpander, QueueItem, Prowlarr, DownloadClient.QBittorrent]

  @moduledoc """
  Public facade for the Acquisition bounded context.

  Acquisition is optional — call `available?/0` before exposing any UI surfaces.
  When Prowlarr is not configured, `available?/0` returns false and search/grab
  return `{:error, :not_configured}`.

  ## Automated acquisition

  Subscribe to `"release_tracking:updates"` PubSub events. When
  `{:release_ready, item}` arrives, this module creates an `acquisition_grabs`
  record and enqueues a `SearchAndGrab` Oban job.

  ## Manual search

  Call `search/2` with a query string. Pass the chosen `%SearchResult{}` to
  `grab/1` to submit it to Prowlarr.

  ## PubSub

  Subscribe with `Acquisition.subscribe/0` to receive:
  - `{:grab_submitted, grab}` — a grab was sent to Prowlarr
  - `{:grab_failed, reason}` — a grab attempt failed
  - `{:search_retry_scheduled, grab}` — nothing found, will retry in 4h
  """

  use GenServer

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.{Config, Grab, Jobs.SearchAndGrab, Prowlarr}
  alias MediaCentarr.Acquisition.DownloadClient.Dispatcher
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

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
  Tests connectivity and credentials against the configured download client.
  """
  @spec test_download_client() :: :ok | {:error, term()}
  def test_download_client do
    with {:ok, driver} <- Dispatcher.driver() do
      driver.test_connection()
    end
  end

  @doc """
  Asks Prowlarr for the list of download clients it has configured.

  Returns a list of `%{name, type, url, username, enabled}` maps used by
  the Settings UI to pre-fill the download-client form. Passwords are
  not exposed by Prowlarr and the user must enter them manually.
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
  Enqueues an automated acquisition job for a TMDB item.

  Creates an `acquisition_grabs` record (idempotent — skips if already exists)
  and enqueues a `SearchAndGrab` Oban job.
  """
  @spec enqueue(String.t(), String.t(), String.t()) :: {:ok, Grab.t()} | {:error, term()}
  def enqueue(tmdb_id, tmdb_type, title) do
    case get_or_create_grab(tmdb_id, tmdb_type, title) do
      {:ok, %Grab{status: "grabbed"} = grab} ->
        {:ok, grab}

      {:ok, grab} ->
        Oban.insert(SearchAndGrab.new(%{"grab_id" => grab.id}))
        {:ok, grab}

      {:error, reason} ->
        {:error, reason}
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
  def handle_info({:release_ready, item}, state) do
    if available?() do
      tmdb_id = to_string(item.tmdb_id)
      tmdb_type = to_string(item.media_type)
      title = item.name

      case enqueue(tmdb_id, tmdb_type, title) do
        {:ok, _grab} ->
          Log.info(:library, "acquisition enqueued for #{title}")

        {:error, reason} ->
          Log.warning(:library, "acquisition enqueue failed — #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_or_create_grab(tmdb_id, tmdb_type, title) do
    case Repo.get_by(Grab, tmdb_id: tmdb_id, tmdb_type: tmdb_type) do
      nil ->
        Repo.insert(Grab.create_changeset(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type, title: title}))

      grab ->
        {:ok, grab}
    end
  end
end
