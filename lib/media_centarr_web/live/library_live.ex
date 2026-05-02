defmodule MediaCentarrWeb.LibraryLive do
  @moduledoc """
  Library Browse page — the full entity catalog as a poster grid with type
  tabs, sort, and text filter. Selecting an entity opens a ModalShell detail
  overlay. Mounted at `/library`.

  The Continue Watching and Upcoming zones formerly here have moved:
  - Continue Watching → HomeLive (`/`)
  - Upcoming → UpcomingLive (`/upcoming`)
  """
  use MediaCentarrWeb, :live_view
  use MediaCentarrWeb.Live.EntityModal
  use MediaCentarrWeb.Live.SpoilerFreeAware
  use MediaCentarrWeb.Live.CapabilitiesAware

  alias MediaCentarr.{
    Capabilities,
    Library,
    Library.Availability,
    Playback,
    Settings
  }

  alias MediaCentarrWeb.Components.LibraryCards

  import MediaCentarrWeb.LibraryHelpers
  import MediaCentarrWeb.LibraryFormatters
  import MediaCentarrWeb.LibraryProgress
  import MediaCentarrWeb.LibraryAvailability

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Library.subscribe()
      Playback.subscribe()
      Settings.subscribe()
      Availability.subscribe()
      Capabilities.subscribe()
      MediaCentarr.Config.subscribe()
    end

    {:ok,
     socket
     |> assign(
       loaded?: false,
       entries: [],
       entries_by_id: %{},
       visible_ids: MapSet.new(),
       playback: %{},
       active_tab: :all,
       sort_order: :recent,
       sort_open: false,
       sort_highlight: 0,
       filter_text: "",
       in_progress_filter: false,
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       reload_timer: nil,
       pending_entity_ids: MapSet.new(),
       unavailable_count: 0,
       availability_map: %{},
       watch_dirs: MediaCentarr.Config.get(:watch_dirs) || [],
       watch_dirs_configured: watch_dirs_configured?(),
       dir_status: Availability.dir_status()
     )
     |> assign_tmdb_ready()
     |> assign_spoiler_free()
     |> assign_modal_defaults()
     |> stream_configure(:grid, dom_id: &"entity-#{&1.entity.id}")
     |> stream(:grid, [])}
  end

  @doc """
  True when at least one `watch_dirs` entry is configured — used by the
  empty-state branch to decide between "no media yet" (user hasn't set up
  a library root) and "watch_dirs configured but no files found".
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

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    pending = MapSet.union(socket.assigns.pending_entity_ids, MapSet.new(entity_ids))

    {:noreply,
     socket
     |> assign(pending_entity_ids: pending)
     |> debounce(:reload_timer, :reload_entities, 500)}
  end

  def handle_info(:reload_entities, socket) do
    changed_ids = socket.assigns.pending_entity_ids

    {updated_entries, gone_ids} =
      Library.Browser.fetch_typed_entries_by_ids(MapSet.to_list(changed_ids))

    updated_map = Map.new(updated_entries, fn entry -> {entry.entity.id, entry} end)

    entries =
      for entry <- socket.assigns.entries,
          not MapSet.member?(gone_ids, entry.entity.id),
          do: Map.get(updated_map, entry.entity.id, entry)

    existing_ids = MapSet.new(entries, fn entry -> entry.entity.id end)

    new_entries =
      Enum.reject(updated_entries, fn entry -> MapSet.member?(existing_ids, entry.entity.id) end)

    entries = entries ++ new_entries

    selection_deleted =
      socket.assigns.selected_entity_id != nil &&
        MapSet.member?(gone_ids, socket.assigns.selected_entity_id)

    socket =
      socket
      |> assign_entries(entries)
      |> assign(reload_timer: nil, pending_entity_ids: MapSet.new())
      |> recompute_counts()

    selected_id = socket.assigns.selected_entity_id

    socket =
      if selected_id && MapSet.member?(changed_ids, selected_id) do
        refresh_selected_entry(socket)
      else
        sync_selected_entry(socket)
      end

    # Additions need a full reset so new entries land in the correct sort
    # position — stream_insert without :at appends. Deletions and in-place
    # updates are handled surgically by touch_stream_entries (the `entry == nil`
    # branch issues stream_delete_by_dom_id for IDs no longer in entries_by_id).
    socket =
      case reload_strategy(%{new_entries: new_entries, changed_ids: changed_ids}) do
        :reset -> reset_stream(socket)
        {:touch, ids} -> touch_stream_entries(socket, ids)
      end

    if selection_deleted do
      {:noreply, push_patch(socket, to: build_path(socket, %{selected: nil}))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:entity_progress_updated,
         %{
           entity_id: entity_id,
           summary: summary,
           resume_target: resume_target,
           changed_record: changed_record
         }},
        socket
      ) do
    socket =
      case apply_entry_update(
             socket.assigns.entries,
             socket.assigns.entries_by_id,
             entity_id,
             fn entry ->
               records = merge_progress_record(entry.progress_records, changed_record)

               Map.put(
                 %{entry | progress: summary, progress_records: records},
                 :resume_target,
                 resume_target
               )
             end
           ) do
        {:ok, {new_entries, new_by_id}} ->
          socket
          |> assign(entries: new_entries, entries_by_id: new_by_id)
          |> sync_selected_entry()

        :not_found ->
          socket
      end

    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:playback_state_changed, entity_id, new_state, now_playing, _started_at}, socket) do
    playback = apply_playback_change(socket.assigns.playback, entity_id, new_state, now_playing)

    {:noreply,
     socket
     |> assign(playback: playback)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:playback_failed, _entity_id, _reason, payload}, socket) do
    {:noreply, put_flash(socket, :error, playback_failed_flash(payload))}
  end

  def handle_info(
        {:extra_progress_updated, %{entity_id: entity_id, extra_id: _extra_id, progress: progress}},
        socket
      ) do
    socket =
      case apply_entry_update(
             socket.assigns.entries,
             socket.assigns.entries_by_id,
             entity_id,
             fn %{entity: entity} = entry ->
               extra_progress = merge_extra_progress(entity.extra_progress || [], progress)
               %{entry | entity: %{entity | extra_progress: extra_progress}}
             end
           ) do
        {:ok, {new_entries, new_by_id}} ->
          socket
          |> assign(entries: new_entries, entries_by_id: new_by_id)
          |> sync_selected_entry()

        :not_found ->
          socket
      end

    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:availability_changed, dir, state}, socket) do
    availability_map =
      MediaCentarrWeb.LibraryAvailability.availability_for_dir(
        socket.assigns.entries,
        dir,
        socket.assigns.availability_map
      )

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
    <Layouts.app flash={@flash} current_path="/library" full_width>
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
            <div :if={@watch_dirs_configured} class="text-base-content/60">
              No entities found.
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
                selected={@selected_entity_id == entry.entity.id}
                playing={playing?(@playback, entry.entity.id)}
                available={Map.get(@availability_map, entry.entity.id, true)}
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
    socket
    |> assign_entries(Library.Browser.fetch_all_typed_entries())
    |> assign(playback: load_playback_sessions())
    |> recompute_counts()
  end

  # Re-snap `:selected_entry` from the in-memory `entries_by_id` so the
  # detail modal reflects PubSub-driven progress updates without a DB hit.
  # Stamping the resume target on the entry keeps the modal decoupled
  # from how this LiveView tracks state for the rest of its UI (ADR-038).
  defp sync_selected_entry(%{assigns: %{selected_entity_id: nil}} = socket), do: socket

  defp sync_selected_entry(socket) do
    case Map.get(socket.assigns.entries_by_id, socket.assigns.selected_entity_id) do
      nil -> socket
      entry -> assign(socket, :selected_entry, EntityModal.put_resume_target(entry))
    end
  end

  defp recompute_counts(socket) do
    assign(socket, counts: tab_counts(socket.assigns.entries))
  end

  # --- Entry Index ---

  defp assign_entries(socket, entries) do
    availability_map = MediaCentarrWeb.LibraryAvailability.availability_map(entries)

    socket
    |> assign(
      entries: entries,
      entries_by_id: Map.new(entries, fn entry -> {entry.entity.id, entry} end),
      availability_map: availability_map,
      unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end)
    )
    |> cache_visible_ids()
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
    by_id = socket.assigns.entries_by_id

    Enum.reduce(entity_ids, socket, fn id, sock ->
      entry = by_id[id]

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

  defp compute_filtered(socket) do
    assigns = socket.assigns

    entries =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> filtered_by_in_progress(assigns.in_progress_filter)

    if assigns.in_progress_filter do
      sorted_by_last_watched(entries)
    else
      sorted_by(entries, assigns.sort_order)
    end
  end

  # Caches the filtered visible-ID set so subsequent `touch_stream_entries`
  # calls (one per PubSub event burst) read O(1) from assigns instead of
  # rescanning `entries`. Invalidate by calling this whenever `entries` or
  # any filter assign (active_tab, filter_text, in_progress_filter) changes.
  defp cache_visible_ids(socket) do
    assigns = socket.assigns

    visible_ids =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> filtered_by_in_progress(assigns.in_progress_filter)
      |> MapSet.new(& &1.entity.id)

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
    params = if selected && view == :info, do: Map.put(params, :view, :info), else: params

    if params == %{}, do: ~p"/library", else: ~p"/library?#{params}"
  end

  # --- Helpers ---

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)
end
