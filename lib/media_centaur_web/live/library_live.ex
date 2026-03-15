defmodule MediaCentaurWeb.LibraryLive do
  @moduledoc """
  Two-zone library page with Continue Watching and Library Browse.

  **Continue Watching** shows in-progress entities as backdrop cards. Selecting
  one opens a ModalShell detail overlay.

  **Library Browse** shows the full entity catalog as a poster grid with
  type tabs, sort, and text filter. Selecting an entity opens a ModalShell
  detail overlay (same as Continue Watching).

  Zone switching uses URL params (`?zone=library`) via `push_patch` so data
  stays loaded across tab changes.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{
    Library,
    LibraryBrowser,
    Playback.ProgressBroadcaster,
    Playback.Resume,
    Playback.ResumeTarget
  }

  alias MediaCentaurWeb.Components.{DetailPanel, LibraryCards, ModalShell}

  import MediaCentaurWeb.LibraryHelpers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())
    end

    {:ok,
     assign(socket,
       entries: [],
       entries_by_id: %{},
       continue_watching: [],
       resume_targets: %{},
       playback: %{},
       zone: :watching,
       selected_entity_id: nil,
       detail_presentation: nil,
       active_tab: :all,
       sort_order: :recent,
       sort_open: false,
       sort_highlight: 0,
       filter_text: "",
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       reload_timer: nil,
       pending_entity_ids: MapSet.new(),
       rematch_confirm: nil,
       detail_view: :main,
       detail_files: []
     )
     |> stream_configure(:grid, dom_id: &"entity-#{&1.entity.id}")
     |> stream(:grid, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) && socket.assigns.entries == [] do
        load_library(socket)
      else
        socket
      end

    zone = parse_zone(params["zone"])
    tab = parse_tab(params["tab"])
    sort = parse_sort(params["sort"])
    filter_text = params["filter"] || ""
    selected_id = params["selected"]

    presentation =
      case {selected_id, zone} do
        {nil, _} -> nil
        {_, :watching} -> :modal
        {_, :library} -> :modal
      end

    grid_changed =
      zone != socket.assigns.zone ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text

    selection_changed = selected_id != socket.assigns.selected_entity_id

    socket =
      socket
      |> assign(
        zone: zone,
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text,
        selected_entity_id: selected_id,
        detail_presentation: presentation
      )
      |> then(fn s ->
        if selection_changed, do: assign(s, detail_view: :main, detail_files: []), else: s
      end)
      |> then(fn s -> if grid_changed, do: reset_stream(s), else: s end)

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("select_cw_entity", %{"id" => id}, socket) do
    entry = socket.assigns.entries_by_id[id]

    expanded_seasons =
      if entry,
        do: DetailPanel.auto_expand_season(entry.entity, entry.progress),
        else: MapSet.new()

    socket = assign(socket, expanded_seasons: expanded_seasons)
    {:noreply, push_patch(socket, to: build_path(socket, %{selected: id}))}
  end

  def handle_event("select_entity", %{"id" => id}, socket) do
    new_id = if socket.assigns.selected_entity_id == id, do: nil, else: id

    socket =
      if new_id != socket.assigns.selected_entity_id do
        entry = socket.assigns.entries_by_id[new_id]

        expanded_seasons =
          if entry,
            do: DetailPanel.auto_expand_season(entry.entity, entry.progress),
            else: MapSet.new()

        assign(socket, expanded_seasons: expanded_seasons)
      else
        socket
      end

    {:noreply, push_patch(socket, to: build_path(socket, %{selected: new_id}))}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(rematch_confirm: nil, detail_view: :main, detail_files: [])
     |> push_patch(to: build_path(socket, %{selected: nil}))}
  end

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

  def handle_event("play", %{"id" => id}, socket) do
    LibraryBrowser.play(id)
    {:noreply, socket}
  end

  def handle_event(
        "toggle_watched",
        %{"entity-id" => entity_id, "season" => season_str, "episode" => episode_str},
        socket
      ) do
    season_number = String.to_integer(season_str)
    episode_number = String.to_integer(episode_str)

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      toggle_watched(entity_id, season_number, episode_number)
    end)

    {:noreply, socket}
  end

  def handle_event("rematch", %{"id" => entity_id}, socket) do
    if socket.assigns.rematch_confirm == entity_id do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        MediaCentaur.Review.Rematch.rematch_entity(entity_id)
      end)

      {:noreply,
       socket
       |> assign(rematch_confirm: nil)
       |> push_navigate(to: ~p"/review")}
    else
      {:noreply, assign(socket, rematch_confirm: entity_id)}
    end
  end

  def handle_event("toggle_detail_view", _params, socket) do
    case socket.assigns.detail_view do
      :main ->
        files =
          if socket.assigns.detail_files == [] && socket.assigns.selected_entity_id do
            load_entity_files(socket.assigns.selected_entity_id)
          else
            socket.assigns.detail_files
          end

        {:noreply, assign(socket, detail_view: :info, detail_files: files)}

      :info ->
        {:noreply, assign(socket, detail_view: :main)}
    end
  end

  def handle_event("toggle_season", %{"season" => season_str}, socket) do
    season_number = String.to_integer(season_str)
    expanded = socket.assigns[:expanded_seasons] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, season_number),
        do: MapSet.delete(expanded, season_number),
        else: MapSet.put(expanded, season_number)

    {:noreply, assign(socket, expanded_seasons: expanded)}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    if socket.assigns[:reload_timer] do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    pending = MapSet.union(socket.assigns.pending_entity_ids, MapSet.new(entity_ids))
    timer = Process.send_after(self(), :reload_entities, 500)
    {:noreply, assign(socket, reload_timer: timer, pending_entity_ids: pending)}
  end

  def handle_info(:reload_entities, socket) do
    changed_ids = socket.assigns.pending_entity_ids
    {updated_entries, gone_ids} = LibraryBrowser.fetch_entries_by_ids(MapSet.to_list(changed_ids))
    updated_map = Map.new(updated_entries, fn entry -> {entry.entity.id, entry} end)

    entries =
      socket.assigns.entries
      |> Enum.reject(fn entry -> MapSet.member?(gone_ids, entry.entity.id) end)
      |> Enum.map(fn entry -> Map.get(updated_map, entry.entity.id, entry) end)

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
      |> recompute_continue_watching()
      |> recompute_counts()

    # Structural changes need full stream reset
    socket =
      if MapSet.size(gone_ids) > 0 || new_entries != [] do
        reset_stream(socket)
      else
        touch_stream_entries(socket, MapSet.to_list(changed_ids))
      end

    if selection_deleted do
      {:noreply, push_patch(socket, to: build_path(socket, %{selected: nil}))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:entity_progress_updated, entity_id, summary, resume_target, _child_targets_delta,
         progress_records, _last_activity_at},
        socket
      ) do
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary, progress_records)
    resume_targets = Map.put(socket.assigns.resume_targets, entity_id, resume_target)

    {:noreply,
     socket
     |> assign_entries(entries)
     |> assign(resume_targets: resume_targets)
     |> recompute_continue_watching()
     |> touch_stream_entries([entity_id])}
  end

  def handle_info(
        {:playback_state_changed, entity_id, new_state, now_playing, _started_at},
        socket
      ) do
    playback =
      case new_state do
        :stopped ->
          Map.delete(socket.assigns.playback, entity_id)

        _ ->
          Map.put(socket.assigns.playback, entity_id, %{
            state: new_state,
            now_playing: now_playing
          })
      end

    {:noreply,
     socket
     |> assign(playback: playback)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    selected_entry = assigns.entries_by_id[assigns.selected_entity_id]

    assigns =
      assigns
      |> assign(:selected_entry, selected_entry)
      |> assign(:watching_path, ~p"/")
      |> assign(:library_path, ~p"/?zone=library")

    ~H"""
    <Layouts.app flash={@flash} current_path="/" full_width>
      <div data-page-behavior="library">
        <%!-- Zone tabs --%>
        <div role="tablist" class="tabs tabs-boxed library-tabs w-fit mb-6" data-nav-zone="zone-tabs">
          <.link
            patch={@watching_path}
            role="tab"
            class={["tab", @zone == :watching && "tab-active"]}
            data-nav-item
            data-nav-zone-value="watching"
            tabindex="0"
          >
            Continue Watching
          </.link>
          <.link
            patch={@library_path}
            role="tab"
            class={["tab", @zone == :library && "tab-active"]}
            data-nav-item
            data-nav-zone-value="library"
            tabindex="0"
          >
            Library
          </.link>
        </div>

        <%!-- Continue Watching zone --%>
        <section :if={@zone == :watching} id="continue-watching" data-nav-zone="grid">
          <LibraryCards.cw_empty :if={@continue_watching == []} />
          <div
            :if={@continue_watching != []}
            class="grid grid-cols-[repeat(auto-fill,minmax(360px,520px))] gap-4"
            data-nav-grid
          >
            <LibraryCards.cw_card
              :for={entry <- @continue_watching}
              entry={entry}
              resume={Map.get(@resume_targets, entry.entity.id)}
              playing={playing?(@playback, entry.entity.id)}
            />
          </div>
        </section>

        <%!-- Library Browse zone --%>
        <section :if={@zone == :library} id="browse">
          <LibraryCards.toolbar
            active_tab={@active_tab}
            counts={@counts}
            sort_order={@sort_order}
            sort_open={@sort_open}
            sort_highlight={@sort_highlight}
            filter_text={@filter_text}
          />

          <div :if={@grid_count == 0} class="text-base-content/60 py-8 text-center empty-state-enter">
            No entities found.
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
              />
            </div>
          </div>
        </section>

        <%!-- Detail modal (always in DOM for smooth backdrop-filter) --%>
        <ModalShell.modal_shell
          open={@selected_entry != nil && @detail_presentation == :modal}
          entity={(@selected_entry && @selected_entry.entity) || nil}
          progress={@selected_entry && @selected_entry.progress}
          resume={@selected_entry && Map.get(@resume_targets, @selected_entry.entity.id)}
          progress_records={(@selected_entry && @selected_entry.progress_records) || []}
          expanded_seasons={assigns[:expanded_seasons]}
          rematch_confirm={@rematch_confirm == @selected_entity_id}
          detail_view={@detail_view}
          detail_files={@detail_files}
          on_play="play"
          on_close="close_detail"
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  defp load_entity_files(entity_id) do
    Library.list_watched_files_for_entity!(entity_id)
    |> Enum.map(fn file ->
      size =
        case File.stat(file.file_path) do
          {:ok, %{size: size}} -> size
          _ -> nil
        end

      %{file: file, size: size}
    end)
  end

  defp load_library(socket) do
    entries = LibraryBrowser.fetch_entities()
    resume_targets = compute_resume_targets(entries)

    playback =
      MediaCentaur.Playback.Sessions.list()
      |> Map.new(fn session -> {session.entity_id, session} end)

    socket
    |> assign_entries(entries)
    |> assign(
      resume_targets: resume_targets,
      playback: playback
    )
    |> recompute_continue_watching()
    |> recompute_counts()
  end

  defp recompute_continue_watching(socket) do
    continue_watching =
      socket.assigns.entries
      |> Enum.filter(fn entry ->
        entry.progress_records != [] &&
          case Resume.resolve(entry.entity, entry.progress_records) do
            {:resume, _, _} -> true
            {:play_next, _, _} -> true
            _ -> false
          end
      end)
      |> Enum.sort_by(&max_last_watched_at/1, {:desc, DateTime})

    assign(socket, continue_watching: continue_watching)
  end

  defp max_last_watched_at(entry) do
    Enum.max_by(entry.progress_records, & &1.last_watched_at, DateTime, fn -> nil end).last_watched_at
  end

  defp compute_resume_targets(entries) do
    Map.new(entries, fn entry ->
      {entry.entity.id, ResumeTarget.compute(entry.entity, entry.progress_records)}
    end)
  end

  defp recompute_counts(socket) do
    assign(socket, counts: tab_counts(socket.assigns.entries))
  end

  # --- Entry Index ---

  defp assign_entries(socket, entries) do
    assign(socket,
      entries: entries,
      entries_by_id: Map.new(entries, fn entry -> {entry.entity.id, entry} end)
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
    filtered_ids = compute_filtered(socket) |> MapSet.new(& &1.entity.id)
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
    socket.assigns.entries
    |> filtered_by_tab(socket.assigns.active_tab)
    |> filtered_by_text(socket.assigns.filter_text)
    |> sorted_by(socket.assigns.sort_order)
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

  defp parse_zone("library"), do: :library
  defp parse_zone(_), do: :watching

  defp parse_tab("movies"), do: :movies
  defp parse_tab("tv"), do: :tv
  defp parse_tab(_), do: :all

  defp parse_sort("alpha"), do: :alpha
  defp parse_sort("year"), do: :year
  defp parse_sort(_), do: :recent

  # Build a URL path preserving current socket state with overrides
  defp build_path(socket, overrides) do
    assigns = socket.assigns

    zone = Map.get(overrides, :zone, assigns.zone)
    tab = Map.get(overrides, :tab, assigns.active_tab)
    sort = Map.get(overrides, :sort, assigns.sort_order)
    filter = Map.get(overrides, :filter, assigns.filter_text)
    selected = Map.get(overrides, :selected, assigns.selected_entity_id)

    params = %{}
    params = if zone == :library, do: Map.put(params, :zone, :library), else: params
    params = if zone == :library, do: Map.put(params, :tab, tab), else: params
    params = if zone == :library, do: Map.put(params, :sort, sort), else: params
    params = if filter != "", do: Map.put(params, :filter, filter), else: params
    params = if selected, do: Map.put(params, :selected, selected), else: params

    if params == %{}, do: ~p"/", else: ~p"/?#{params}"
  end

  # --- Helpers ---

  defp update_entry_progress(entries, entity_id, summary, progress_records) do
    sorted_records = Enum.sort_by(progress_records, &{&1.season_number, &1.episode_number})

    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry ->
        %{entry | progress: summary, progress_records: sorted_records}

      entry ->
        entry
    end)
  end

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  defp toggle_watched(entity_id, season_number, episode_number) do
    progress =
      Library.list_watch_progress_for_entity!(entity_id)
      |> Enum.find(&(&1.season_number == season_number && &1.episode_number == episode_number))

    case progress do
      %{completed: true} ->
        Library.mark_watch_incomplete!(progress)

      %{completed: false} ->
        Library.mark_watch_completed!(progress)

      nil ->
        params = %{
          entity_id: entity_id,
          season_number: season_number,
          episode_number: episode_number,
          position_seconds: 0.0,
          duration_seconds: 0.0
        }

        {:ok, record} = Library.upsert_watch_progress(params)
        Library.mark_watch_completed!(record)
    end

    ProgressBroadcaster.broadcast(entity_id, season_number, episode_number)
  end
end
