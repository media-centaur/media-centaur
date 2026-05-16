defmodule MediaCentarrWeb.LibraryLive do
  @moduledoc """
  Library Browse page — the full entity catalog as a poster grid with
  type tabs, sort, and text filter. Selecting an entity opens a
  ModalShell detail overlay. Mounted at `/library`.

  ## Read path (Library Schema v2 Phase 3.1)

  The grid reads from the `Library.Views.Browse` ETS projection
  (ADR-041) — pre-shaped `BrowseItem` structs in recent-first
  (`inserted_at desc`) order. Progress and availability live in
  separate per-id maps populated via the bulk context functions
  `Library.list_progress_summaries/1` and
  `Library.Availability.available_for_ids/1`. The mount issues a
  bounded number of queries that does not scale with catalog size.

  ## Update path

  Subscriptions split by concern:

    * `library:views` — projection refresh broadcasts. On
      `{:library_view_updated, :browse}` the LiveView re-reads
      `Views.browse/0` (microsecond ETS lookup) and refreshes the
      progress + availability maps.
    * `library:updates` — wired by the EntityModal hook for the
      selected modal state; the grid no longer reacts directly.
    * `playback:events` — pulse dot + flash on `playback_state_changed`
      / `playback_failed`.
    * `library:availability` — drive-mount / unmount events.
  """
  use MediaCentarrWeb, :live_view
  use MediaCentarrWeb.Live.EntityModal
  use MediaCentarrWeb.Live.SpoilerFreeAware

  alias MediaCentarr.{
    Library,
    Library.Availability
  }

  alias MediaCentarr.Pipeline.Stats

  alias MediaCentarrWeb.Components.LibraryCards

  import MediaCentarrWeb.LibraryHelpers
  import MediaCentarrWeb.LibraryFormatters
  import MediaCentarrWeb.LibraryAvailability

  @impl true
  def mount(_params, _session, socket) do
    # `Library.subscribe()` and `Playback.subscribe()` are auto-wired
    # by the EntityModal on_mount callback; `Settings.subscribe()` by
    # SpoilerFreeAware; `Capabilities.subscribe()` by CapabilitiesAware.
    # Do not duplicate any of them here.
    if connected?(socket) do
      Library.Views.subscribe()
      Availability.subscribe()
      MediaCentarr.Config.subscribe()
      Process.send_after(self(), :tick_pipeline, 1_000)
    end

    {:ok,
     socket
     |> assign(
       loaded?: false,
       entries: [],
       progress_by_id: %{},
       availability_map: %{},
       visible_ids: MapSet.new(),
       active_tab: :all,
       sort_order: :recent,
       sort_open: false,
       sort_highlight: 0,
       filter_text: "",
       in_progress_filter: false,
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       unavailable_count: 0,
       watch_dirs: MediaCentarr.Config.get(:watch_dirs) || [],
       watch_dirs_configured: watch_dirs_configured?(),
       dir_status: Availability.dir_status(),
       pipeline_queue_depth: 0,
       scanning: false,
       scan_task: nil
     )
     |> stream_configure(:grid, dom_id: &"entity-#{&1.id}")
     |> stream(:grid, [])}
  end

  @doc """
  True when at least one `watch_dirs` entry is configured — used by
  the empty-state branch to decide between "no media yet" (user hasn't
  set up a library root) and "watch_dirs configured but no files found".
  """
  def watch_dirs_configured?(dirs \\ MediaCentarr.Config.get(:watch_dirs)) do
    case dirs do
      list when is_list(list) and list != [] -> true
      _ -> false
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    was_loaded? = socket.assigns.loaded?
    socket = ensure_loaded(socket)
    just_loaded = not was_loaded? and socket.assigns.loaded?

    tab = parse_tab(params["tab"])
    sort = parse_sort(params["sort"])
    filter_text = params["filter"] || ""
    in_progress_filter = params["in_progress"] == "1"

    grid_changed =
      just_loaded ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text ||
        in_progress_filter != socket.assigns.in_progress_filter

    socket =
      socket
      |> assign(
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text,
        in_progress_filter: in_progress_filter
      )
      |> then(fn socket -> if grid_changed, do: cache_visible_ids(socket), else: socket end)
      |> apply_modal_params(params)
      |> then(fn socket -> if grid_changed, do: reset_stream(socket), else: socket end)

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(
           %{socket | assigns: Map.put(socket.assigns, :active_tab, parse_tab(tab))},
           %{}
         )
     )}
  end

  @sort_options [:recent, :alpha, :year]

  def handle_event("toggle_sort", _params, socket) do
    if socket.assigns.sort_open do
      {:noreply, assign(socket, sort_open: false)}
    else
      highlight = Enum.find_index(@sort_options, &(&1 == socket.assigns.sort_order)) || 0
      {:noreply, assign(socket, sort_open: true, sort_highlight: highlight)}
    end
  end

  def handle_event("close_sort", _params, socket) do
    {:noreply, assign(socket, sort_open: false)}
  end

  def handle_event("sort_key", %{"key" => key}, socket) do
    sort_key(key, socket)
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    sort = parse_sort(sort)

    socket = assign(socket, sort_open: false)

    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :sort_order, sort)}, %{})
     )}
  end

  def handle_event("filter", %{"filter_text" => text}, socket) do
    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :filter_text, text)}, %{}),
       replace: true
     )}
  end

  # Run on a supervised Task so the socket stays responsive — a
  # synchronous call would block render and the "Scanning…" label would
  # never appear. Same pattern as `SettingsLive.handle_event("scan", ...)`.
  def handle_event("scan", _params, socket) do
    task =
      Task.Supervisor.async_nolink(MediaCentarr.TaskSupervisor, fn ->
        MediaCentarr.Watcher.Supervisor.scan()
      end)

    {:noreply, assign(socket, scanning: true, scan_task: task)}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:library_view_updated, :browse}, socket) do
    # The Browse projection refreshed; re-read everything from scratch.
    # The projection itself broadcasts coalesced events upstream, so we
    # do not need to debounce here.
    {:noreply,
     socket
     |> load_library()
     |> cache_visible_ids()
     |> reset_stream()}
  end

  def handle_info({:entity_progress_updated, %{entity_id: entity_id}}, socket) do
    # The EntityModal hook keeps `:selected_entry`'s progress fresh on
    # its own. Here we refresh just the affected card's progress
    # summary so the bar / completion overlay reflects the change.
    updated_summaries = Library.list_progress_summaries([entity_id])

    progress_by_id =
      case Map.get(updated_summaries, entity_id) do
        nil -> Map.delete(socket.assigns.progress_by_id, entity_id)
        summary -> Map.put(socket.assigns.progress_by_id, entity_id, summary)
      end

    {:noreply,
     socket
     |> assign(progress_by_id: progress_by_id)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:playback_state_changed, %{entity_id: entity_id}}, socket) do
    # The EntityModal hook owns the `:playback` map. Here we only
    # re-render the affected poster card so the "playing" badge
    # appears/disappears.
    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:playback_failed, %{payload: payload}}, socket) do
    {:noreply, put_flash(socket, :error, playback_failed_flash(payload))}
  end

  def handle_info({:availability_changed, _dir, state}, socket) do
    availability_map = availability_map(socket.assigns.entries)

    socket =
      assign(socket,
        dir_status: Availability.dir_status(),
        availability_map: availability_map,
        unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end)
      )

    # When storage comes back online, reset the grid stream so the
    # browser re-requests images instead of serving cached 404s.
    socket =
      if state == :watching do
        stream(socket, :grid, socket.assigns.entries, reset: true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:config_updated, :watch_dirs, _entries}, socket) do
    {:noreply,
     assign(socket,
       watch_dirs: MediaCentarr.Config.get(:watch_dirs) || [],
       watch_dirs_configured: watch_dirs_configured?()
     )}
  end

  # Polled once per second so the empty-state can show "Ingesting N
  # files…" while the pipeline drains. Same cadence StatusLive uses.
  # Cheap: Pipeline.Stats keeps the snapshot in ETS, no DB query.
  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 1_000)
    snapshot = Stats.get_snapshot()
    depth = snapshot.discovery_queue_depth + snapshot.import_queue_depth
    {:noreply, assign(socket, pipeline_queue_depth: depth)}
  end

  # Reply from the async scan Task. Matches on the stored ref so we
  # don't confuse it with any other async_nolink result on this socket.
  def handle_info({ref, {:ok, _count}}, %{assigns: %{scan_task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, scanning: false, scan_task: nil)}
  end

  # Scan task exit — either after its result was reaped above or after
  # a future Task.shutdown. Clear the ref either way.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{scan_task: %Task{ref: ref}}} = socket
      ) do
    {:noreply, assign(socket, scan_task: nil)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    offline_summary = offline_summary(assigns.dir_status, assigns.unavailable_count)

    assigns = assign(assigns, :offline_summary, offline_summary)

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/library"
      full_width
      acquisition_ready={@acquisition_ready}
    >
      <div data-page-behavior="library">
        <%!-- Storage offline banner --%>
        <LibraryCards.storage_offline_banner :if={@offline_summary} summary={@offline_summary} />

        <%!-- Library Browse zone --%>
        <section id="browse">
          <LibraryCards.toolbar
            active_tab={@active_tab}
            counts={@counts}
            sort_order={@sort_order}
            sort_open={@sort_open}
            sort_highlight={@sort_highlight}
            filter_text={@filter_text}
          />

          <div :if={@in_progress_filter} class="mt-3 flex items-center gap-2">
            <.badge size="md" class="gap-1">
              In progress
              <.link
                patch={~p"/library"}
                class="opacity-60 hover:opacity-100"
                aria-label="Clear filter"
              >
                ×
              </.link>
            </.badge>
          </div>

          <div :if={@grid_count == 0} class="py-8 text-center empty-state-enter space-y-3">
            <div :if={@watch_dirs_configured} class="max-w-md mx-auto space-y-3">
              <p class="text-base-content/80">No media yet.</p>
              <p :if={@pipeline_queue_depth > 0} class="text-sm opacity-70">
                Ingesting {@pipeline_queue_depth} file{if @pipeline_queue_depth == 1,
                  do: "",
                  else: "s"}…
              </p>
              <.button
                variant="primary"
                size="sm"
                phx-click="scan"
                disabled={@scanning}
                data-nav-item
              >
                {if @scanning, do: "Scanning…", else: "Scan watch directories"}
              </.button>
            </div>
            <div :if={not @watch_dirs_configured} class="max-w-md mx-auto space-y-2">
              <p class="text-base-content/80">
                No media yet — tell Media Centarr where your files live.
              </p>
              <.button
                variant="primary"
                size="sm"
                navigate={~p"/settings?section=library"}
                data-nav-item
              >
                Configure library
              </.button>
            </div>
          </div>

          <div :if={@grid_count > 0} data-nav-zone="grid" class="mt-4">
            <div
              id="library-grid"
              phx-update="stream"
              class="grid grid-cols-[repeat(auto-fill,minmax(155px,1fr))] gap-3"
              data-nav-grid
            >
              <LibraryCards.poster_card
                :for={{dom_id, entry} <- @streams.grid}
                id={dom_id}
                entry={entry}
                progress={Map.get(@progress_by_id, entry.id)}
                selected={@selected_entity_id == entry.id}
                playing={playing?(@playback, entry.id)}
                available={Map.get(@availability_map, entry.id, true)}
              />
            </div>
          </div>
        </section>

        <%!-- Detail modal (always in DOM for smooth backdrop-filter) --%>
        <.entity_modal
          selected_entry={@selected_entry}
          selected_entity_id={@selected_entity_id}
          detail_presentation={@detail_presentation}
          detail_view={@detail_view}
          detail_files={@detail_files}
          expanded_seasons={@expanded_seasons}
          rematch_confirm={@rematch_confirm}
          delete_confirm={@delete_confirm}
          tracking_status={@tracking_status}
          availability_map={@availability_map}
          tmdb_ready={@tmdb_ready}
          spoiler_free={@spoiler_free}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See AGENTS.md → LiveView callbacks (Iron Law).
  defp ensure_loaded(socket) do
    if connected?(socket) and not socket.assigns.loaded? do
      socket
      |> load_library()
      |> assign(loaded?: true)
    else
      socket
    end
  end

  defp load_library(socket) do
    entries = Library.Views.browse()
    ids = Enum.map(entries, & &1.id)
    progress_by_id = Library.list_progress_summaries(ids)
    availability_map = Availability.available_for_ids(ids)

    assign(socket,
      entries: entries,
      progress_by_id: progress_by_id,
      availability_map: availability_map,
      unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end),
      counts: tab_counts(entries),
      playback: load_playback_sessions()
    )
  end

  # --- Stream Management ---

  defp reset_stream(socket) do
    filtered = compute_filtered(socket)

    socket
    |> stream(:grid, filtered, reset: true)
    |> assign(grid_count: length(filtered))
  end

  defp touch_stream_entries(socket, entity_ids) do
    filtered_ids = socket.assigns.visible_ids
    by_id = entries_index(socket.assigns.entries)

    Enum.reduce(entity_ids, socket, fn id, sock ->
      entry = Map.get(by_id, id)

      cond do
        entry == nil ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")

        MapSet.member?(filtered_ids, id) ->
          stream_insert(sock, :grid, entry)

        true ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")
      end
    end)
  end

  defp entries_index(entries), do: Map.new(entries, &{&1.id, &1})

  defp compute_filtered(socket) do
    assigns = socket.assigns

    entries =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> filtered_by_in_progress(assigns.progress_by_id, assigns.in_progress_filter)

    if assigns.in_progress_filter do
      sorted_by_last_watched(entries, assigns.progress_by_id)
    else
      sorted_by(entries, assigns.sort_order)
    end
  end

  # Caches the filtered visible-ID set so subsequent
  # `touch_stream_entries` calls (one per PubSub event burst) read O(1)
  # from assigns instead of rescanning `entries`. Invalidate by calling
  # this whenever `entries` or any filter assign (active_tab,
  # filter_text, in_progress_filter) changes.
  defp cache_visible_ids(socket) do
    assigns = socket.assigns

    visible_ids =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> filtered_by_in_progress(assigns.progress_by_id, assigns.in_progress_filter)
      |> MapSet.new(& &1.id)

    assign(socket, visible_ids: visible_ids)
  end

  # --- Sort Dropdown Keyboard ---

  defp sort_key("Enter", socket) do
    if socket.assigns.sort_open do
      selected = Enum.at(@sort_options, socket.assigns.sort_highlight)
      socket = assign(socket, sort_open: false)

      {:noreply,
       push_patch(socket,
         to: build_path(%{socket | assigns: Map.put(socket.assigns, :sort_order, selected)}, %{})
       )}
    else
      highlight = Enum.find_index(@sort_options, &(&1 == socket.assigns.sort_order)) || 0
      {:noreply, assign(socket, sort_open: true, sort_highlight: highlight)}
    end
  end

  defp sort_key("Escape", socket) do
    {:noreply, assign(socket, sort_open: false)}
  end

  defp sort_key("ArrowDown", socket) do
    if socket.assigns.sort_open do
      max = length(@sort_options) - 1
      highlight = min(socket.assigns.sort_highlight + 1, max)
      {:noreply, assign(socket, sort_highlight: highlight)}
    else
      {:noreply, socket}
    end
  end

  defp sort_key("ArrowUp", socket) do
    if socket.assigns.sort_open do
      highlight = max(socket.assigns.sort_highlight - 1, 0)
      {:noreply, assign(socket, sort_highlight: highlight)}
    else
      {:noreply, socket}
    end
  end

  defp sort_key(_key, socket), do: {:noreply, socket}

  # --- URL Params ---

  defp parse_tab("movies"), do: :movies
  defp parse_tab("tv"), do: :tv
  defp parse_tab(_), do: :all

  defp parse_sort("alpha"), do: :alpha
  defp parse_sort("year"), do: :year
  defp parse_sort(_), do: :recent

  @impl true
  def build_modal_path(socket, overrides), do: build_path(socket, overrides)

  # Build a URL path preserving current socket state with overrides
  defp build_path(socket, overrides) do
    assigns = socket.assigns

    tab = Map.get(overrides, :tab, assigns.active_tab)
    sort = Map.get(overrides, :sort, assigns.sort_order)
    filter = Map.get(overrides, :filter, assigns.filter_text)
    in_progress = Map.get(overrides, :in_progress, assigns.in_progress_filter)
    selected = Map.get(overrides, :selected, assigns.selected_entity_id)
    view = Map.get(overrides, :view, assigns.detail_view)

    params = %{}
    params = if tab == :all, do: params, else: Map.put(params, :tab, tab)
    params = if sort == :recent, do: params, else: Map.put(params, :sort, sort)
    params = if filter == "", do: params, else: Map.put(params, :filter, filter)
    params = if in_progress, do: Map.put(params, :in_progress, 1), else: params
    params = if selected, do: Map.put(params, :selected, selected), else: params
    params = if selected && view in [:info, :credits], do: Map.put(params, :view, view), else: params

    if params == %{}, do: ~p"/library", else: ~p"/library?#{params}"
  end

  # --- Helpers ---

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)
end
