defmodule MediaCentarr.Library.Availability do
  @moduledoc """
  Single source of truth for "is this entity's file reachable right now?".

  Cross-cutting capability consumed by every surface that cares whether a
  library entity's backing file is online: image rendering (placeholders vs
  artwork), the play button (active vs "offline" pill), and any future
  delete / move actions. Pioneered as `Images.Availability`, promoted here
  once the same signal was needed beyond image rendering.

  Reads are backed by `:persistent_term` so they cost nothing at grid-render
  scale; writes happen in a serialised GenServer that subscribes to the
  watcher's state broadcasts.

  ## Granularity

  Availability is per-entity: we find the entity's watch directory via
  a longest-prefix match on its file path, then consult the per-dir
  state the watcher is publishing. An entity whose watch dir is
  `:unavailable` is considered unreachable; anything else (`:watching`,
  `:initializing`, or no matching dir) is considered available.

  The optimistic `:initializing` bias is deliberate — that state is
  transient during app boot; treating it as unavailable would flash
  placeholders for a second at every startup.
  """
  use GenServer

  @topic "library:availability"

  # --- Public reads (zero message-passing cost) ---

  @doc """
  Returns true if the entity's artwork cache is currently reachable.
  Safe to call at render time — reads a single `:persistent_term` key.
  """
  @spec available?(map()) :: boolean()
  def available?(entity) do
    case entity_watch_dir(entity) do
      nil -> true
      dir -> Map.get(dir_status(), dir) != :unavailable
    end
  end

  @doc "Current per-dir state map (`%{dir_path => state_atom}`)."
  @spec dir_status() :: %{String.t() => atom()}
  def dir_status, do: :persistent_term.get({__MODULE__, :state}, %{})

  @doc """
  Subscribe the calling process to `{:availability_changed, dir, state}`
  messages broadcast whenever a watch dir's availability changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, @topic)

  @doc false
  # Public test-only helpers (hidden from docs). They exist so tests
  # can reset the cache between cases without reaching into `:sys.*`
  # (banned per ADR-026 `NoSysIntrospection`). NOT intended for
  # runtime use — production state is driven by watcher broadcasts.
  @spec __reset_for_test__() :: :ok
  def __reset_for_test__, do: GenServer.call(__MODULE__, :__reset_for_test__)

  @doc false
  # Sync point for tests: any prior PubSub message in this GenServer's
  # mailbox is guaranteed processed before the call returns.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  # --- GenServer (serialises writes, fans out notifications) ---

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    # Seed synchronously from the current watcher snapshot so the map is
    # correct before our first `available?/1` read, then subscribe for
    # live updates. `WatcherStatus` is a boundary-neutral helper that
    # wraps `Watcher.Supervisor.statuses/0` — it exists specifically so
    # Library can consult Watcher state without a Boundary cycle (Watcher
    # already depends on Library).
    :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.dir_state())

    state =
      Map.new(MediaCentarr.WatcherStatus.statuses(), fn %{dir: dir, state: state} ->
        {dir, state}
      end)

    :persistent_term.put({__MODULE__, :state}, state)
    {:ok, state}
  end

  @impl true
  def handle_info({:dir_state_changed, dir, :watch_dir, new_state}, state) do
    updated = Map.put(state, dir, new_state)
    :persistent_term.put({__MODULE__, :state}, updated)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      @topic,
      {:availability_changed, dir, new_state}
    )

    {:noreply, updated}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:__reset_for_test__, _from, _state) do
    :persistent_term.put({__MODULE__, :state}, %{})
    {:reply, :ok, %{}}
  end

  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}

  # --- Entity → watch-dir lookup ---

  defp entity_watch_dir(entity) do
    case entity_file_path(entity) do
      nil -> nil
      path -> longest_prefix(path, Map.keys(dir_status()))
    end
  end

  defp entity_file_path(%{files: [%{path: path} | _]}) when is_binary(path), do: path
  defp entity_file_path(%{file_path: path}) when is_binary(path), do: path
  defp entity_file_path(_), do: nil

  defp longest_prefix(_path, []), do: nil

  defp longest_prefix(path, dirs) do
    dirs
    |> Enum.filter(fn dir -> String.starts_with?(path, dir <> "/") end)
    |> Enum.max_by(&String.length/1, fn -> nil end)
  end
end
