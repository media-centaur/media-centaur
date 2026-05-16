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
  import Ecto.Query

  alias MediaCentarr.Library.{Episode, PlayableItem, Season, WatchedFile}
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

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

  @doc """
  Bulk variant for projection consumers that hold container ids but not
  preloaded `entity.watched_files`. Returns `%{entity_id => boolean()}`
  for every id in the input.

  The function probes the four container kinds (`:movie`, `:tv_series`,
  `:movie_series`, `:video_object`) in one query each; per-id cost is
  amortised by the kind-grouped joins. Container ids that don't resolve
  to a known WatchedFile fall back to the same optimistic default as
  `available?/1` (true), so unknown ids never flash an offline pill.

  Used by `MediaCentarrWeb.LibraryLive` to populate the `availability_map`
  assign without forcing a Browser-style preload of every entity.
  """
  @spec available_for_ids([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => boolean()}
  def available_for_ids([]), do: %{}

  def available_for_ids(entity_ids) when is_list(entity_ids) do
    status = dir_status()
    watch_dirs_by_id = watch_dirs_by_entity_id(entity_ids)

    Map.new(entity_ids, fn id ->
      available? =
        case Map.get(watch_dirs_by_id, id) do
          nil -> true
          dir -> Map.get(status, dir) != :unavailable
        end

      {id, available?}
    end)
  end

  # Returns `%{entity_id => watch_dir}` for every entity id that has at
  # least one WatchedFile. Probes every container kind in a single
  # bounded set of queries; missing ids simply don't appear in the map.
  defp watch_dirs_by_entity_id(entity_ids) do
    # PlayableItem-keyed kinds (Movie, VideoObject) — one query each.
    movie_pairs = playable_item_watch_dirs(:movie, entity_ids)
    video_pairs = playable_item_watch_dirs(:video_object, entity_ids)

    # TV series: WatchedFile -> PlayableItem(:episode) -> Episode -> Season -> TVSeries.
    tv_pairs =
      Repo.all(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :episode,
          join: e in Episode,
          on: e.id == pi.container_id,
          join: s in Season,
          on: s.id == e.season_id,
          where: s.tv_series_id in ^entity_ids,
          select: {s.tv_series_id, wf.watch_dir}
        )
      )

    # Movie series: WatchedFile -> PlayableItem(:movie) -> Movie.movie_series_id.
    movie_series_pairs =
      Repo.all(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :movie,
          join: m in MediaCentarr.Library.Movie,
          on: m.id == pi.container_id,
          where: m.movie_series_id in ^entity_ids,
          select: {m.movie_series_id, wf.watch_dir}
        )
      )

    # First-wins for the optimistic default; if any file is on a
    # `:watching` dir but another is offline, `available?/1` would have
    # taken the per-entity worst case. Bulk callers consume the answer
    # as a boolean — picking the first non-nil watch_dir matches the
    # behavior of `available?/1`, which itself looks at the first file
    # in `entity.watched_files`.
    Enum.reduce(movie_pairs ++ video_pairs ++ tv_pairs ++ movie_series_pairs, %{}, fn {id, dir}, acc ->
      Map.put_new(acc, id, dir)
    end)
  end

  defp playable_item_watch_dirs(container_type, entity_ids) do
    Repo.all(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on:
          pi.id == wf.playable_item_id and pi.container_type == ^container_type and
            pi.container_id in ^entity_ids,
        select: {pi.container_id, wf.watch_dir}
      )
    )
  end

  @doc "Current per-dir state map (`%{dir_path => state_atom}`)."
  @spec dir_status() :: %{String.t() => atom()}
  def dir_status, do: :persistent_term.get({__MODULE__, :state}, %{})

  @doc """
  Subscribe the calling process to `{:availability_changed, dir, state}`
  messages broadcast whenever a watch dir's availability changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_availability())

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
    :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.dir_state())

    # Watcher.statuses/0 surfaces internal vocabulary (`:watching` /
    # `:initializing`); broadcasts emit `:available` / `:unavailable`.
    # Normalize to broadcast vocabulary so this module's state map and
    # `available?/1` predicate see only one set of values regardless of
    # whether the value came from the seed snapshot or a live update.
    state =
      Map.new(MediaCentarr.WatcherStatus.statuses(), fn %{dir: dir, state: status} ->
        {dir, broadcast_state(status)}
      end)

    :persistent_term.put({__MODULE__, :state}, state)
    {:ok, state}
  end

  defp broadcast_state(:watching), do: :available
  defp broadcast_state(:initializing), do: :available
  defp broadcast_state(other), do: other

  @impl true
  def handle_info({:dir_state_changed, dir, :watch_dir, new_state}, state) do
    updated = Map.put(state, dir, new_state)
    :persistent_term.put({__MODULE__, :state}, updated)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_availability(),
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
