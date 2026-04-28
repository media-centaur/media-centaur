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

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.{
    Capabilities,
    Format,
    Library,
    Library.Availability,
    Library.FileEventHandler,
    Playback,
    Playback.ProgressBroadcaster,
    Playback.ResumeTarget,
    Settings
  }

  alias MediaCentarrWeb.Components.{
    DetailPanel,
    LibraryCards,
    ModalShell
  }

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
     assign(socket,
       entries: [],
       entries_by_id: %{},
       resume_targets: %{},
       playback: %{},
       selected_entity_id: nil,
       detail_presentation: nil,
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
       rematch_confirm: nil,
       delete_confirm: nil,
       detail_view: :main,
       detail_files: [],
       spoiler_free: load_spoiler_free_setting(),
       tmdb_ready: Capabilities.tmdb_ready?(),
       unavailable_count: 0,
       availability_map: %{},
       tracking_status: nil,
       watch_dirs: MediaCentarr.Config.get(:watch_dirs) || [],
       watch_dirs_configured: watch_dirs_configured?(),
       dir_status: Availability.dir_status()
     )
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
    {socket, just_loaded} =
      if connected?(socket) && socket.assigns.entries == [] do
        {load_library(socket), true}
      else
        {socket, false}
      end

    tab = parse_tab(params["tab"])
    sort = parse_sort(params["sort"])
    filter_text = params["filter"] || ""
    in_progress_filter = params["in_progress"] == "1"
    selected_id = params["selected"]
    detail_view = parse_view(params["view"])

    presentation = if selected_id, do: :modal

    grid_changed =
      just_loaded ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text ||
        in_progress_filter != socket.assigns.in_progress_filter

    selection_changed = selected_id != socket.assigns.selected_entity_id

    # Reset to main view when switching entities, but not on initial mount
    # (nil → id) so the URL's view param is honored on reload.
    entity_switched =
      selection_changed && socket.assigns.selected_entity_id != nil

    detail_view = if entity_switched, do: :main, else: detail_view

    detail_files =
      if selection_changed do
        []
      else
        socket.assigns.detail_files
      end

    detail_files =
      if detail_view == :info && detail_files == [] && selected_id do
        load_entity_files(selected_id)
      else
        detail_files
      end

    tracking_status =
      if selection_changed do
        selected_entry = socket.assigns.entries_by_id[selected_id]
        if selected_entry, do: load_tracking_status(selected_entry)
      else
        socket.assigns.tracking_status
      end

    entries_by_id =
      if selection_changed && selected_id do
        load_extras_into_entry(socket.assigns.entries_by_id, selected_id)
      else
        socket.assigns.entries_by_id
      end

    socket =
      socket
      |> assign(
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text,
        in_progress_filter: in_progress_filter,
        selected_entity_id: selected_id,
        detail_presentation: presentation,
        detail_view: detail_view,
        detail_files: detail_files,
        tracking_status: tracking_status,
        entries_by_id: entries_by_id
      )
      |> then(fn socket -> if grid_changed, do: reset_stream(socket), else: socket end)

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("select_entity", %{"id" => id}, socket) do
    new_id = if socket.assigns.selected_entity_id != id, do: id

    socket =
      if new_id == socket.assigns.selected_entity_id do
        socket
      else
        entry = socket.assigns.entries_by_id[new_id]

        expanded_seasons =
          if entry,
            do: DetailPanel.auto_expand_season(entry.entity, entry.progress),
            else: MapSet.new()

        assign(socket, expanded_seasons: expanded_seasons)
      end

    {:noreply, push_patch(socket, to: build_path(socket, %{selected: new_id}))}
  end

  def handle_event("close_detail", _params, socket) do
    if socket.assigns.detail_view == :info do
      {:noreply, push_patch(socket, to: build_path(socket, %{view: :main}))}
    else
      {:noreply,
       socket
       |> assign(rematch_confirm: nil)
       |> push_patch(to: build_path(socket, %{selected: nil, view: :main}))}
    end
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
    case Playback.play(id) do
      :ok ->
        {:noreply, socket}

      {:error, :file_not_found} ->
        {:noreply, put_flash(socket, :error, "File not available — is your media drive mounted?")}

      {:error, :already_playing} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start playback.")}
    end
  end

  def handle_event(
        "toggle_watched",
        %{"entity-id" => entity_id, "season" => season_str, "episode" => episode_str},
        socket
      ) do
    season_number = String.to_integer(season_str)
    episode_number = String.to_integer(episode_str)

    # Resolve the FK in the LiveView process using the cached entity from
    # `entries_by_id` — avoiding a redundant deep preload inside the async
    # task. The task body now only has to hit the (indexed) watch_progress
    # row and broadcast the result.
    {fk_key, fk_id} =
      resolve_progress_fk(
        socket.assigns.entries_by_id,
        entity_id,
        season_number,
        episode_number
      )

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      update_watch_progress(entity_id, fk_key, fk_id)
    end)

    {:noreply, socket}
  end

  def handle_event("toggle_extra_watched", %{"extra-id" => extra_id, "entity-id" => entity_id}, socket) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      toggle_extra_watched(entity_id, extra_id)
    end)

    {:noreply, socket}
  end

  def handle_event("rematch", %{"id" => entity_id}, socket) do
    if socket.assigns.rematch_confirm == entity_id do
      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        MediaCentarr.Review.Rematch.rematch_entity(entity_id)
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
    new_view = if socket.assigns.detail_view == :main, do: :info, else: :main
    {:noreply, push_patch(socket, to: build_path(socket, %{view: new_view}))}
  end

  def handle_event("toggle_tracking", _params, socket) do
    selected_entry = socket.assigns.entries_by_id[socket.assigns.selected_entity_id]

    case {socket.assigns.tracking_status, find_tmdb_id(selected_entry)} do
      {:watching, {tmdb_id, media_type}} ->
        item = MediaCentarr.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
        if item, do: MediaCentarr.ReleaseTracking.ignore_item(item)
        {:noreply, assign(socket, tracking_status: :ignored)}

      {:ignored, {tmdb_id, media_type}} ->
        item = MediaCentarr.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
        if item, do: MediaCentarr.ReleaseTracking.watch_item(item)
        {:noreply, assign(socket, tracking_status: :watching)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_file_prompt", %{"path" => file_path}, socket) do
    if playing?(socket.assigns.playback, socket.assigns.selected_entity_id) do
      {:noreply, put_flash(socket, :error, "Stop playback before deleting")}
    else
      file_info =
        Enum.find(socket.assigns.detail_files, fn %{file: file} -> file.file_path == file_path end)

      size = if file_info, do: file_info.size

      {:noreply,
       assign(socket,
         delete_confirm: {:file, %{path: file_path, name: Path.basename(file_path), size: size}}
       )}
    end
  end

  def handle_event("delete_folder_prompt", %{"path" => folder_path, "count" => _count}, socket) do
    cond do
      playing?(socket.assigns.playback, socket.assigns.selected_entity_id) ->
        {:noreply, put_flash(socket, :error, "Stop playback before deleting")}

      folder_path in socket.assigns.watch_dirs ->
        {:noreply, put_flash(socket, :error, "Cannot delete a watch directory")}

      true ->
        folder_files =
          socket.assigns.detail_files
          |> Enum.filter(fn %{file: file} -> Path.dirname(file.file_path) == folder_path end)
          |> Enum.map(fn %{file: file, size: size} ->
            %{name: Path.basename(file.file_path), size: size}
          end)

        total_size = Enum.reduce(folder_files, 0, fn %{size: size}, acc -> acc + (size || 0) end)

        {:noreply,
         assign(socket,
           delete_confirm:
             {:folder,
              %{
                path: folder_path,
                name: Path.basename(folder_path),
                files: folder_files,
                total_size: total_size
              }}
         )}
    end
  end

  def handle_event("delete_all_prompt", _params, socket) do
    if playing?(socket.assigns.playback, socket.assigns.selected_entity_id) do
      {:noreply, put_flash(socket, :error, "Stop playback before deleting")}
    else
      payload =
        DetailPanel.build_delete_all_payload(
          socket.assigns.detail_files,
          MapSet.new(socket.assigns.watch_dirs)
        )

      {:noreply, assign(socket, delete_confirm: {:all, payload})}
    end
  end

  def handle_event("delete_confirm", _params, socket) do
    entity_id = socket.assigns.selected_entity_id

    result =
      case socket.assigns.delete_confirm do
        {:file, %{path: file_path}} ->
          FileEventHandler.delete_file(file_path)

        {:folder, %{path: folder_path}} ->
          file_paths =
            socket.assigns.detail_files
            |> Enum.map(& &1.file.file_path)
            |> Enum.filter(&String.starts_with?(&1, folder_path <> "/"))

          FileEventHandler.delete_folder(folder_path, file_paths)

        {:all, %{file_groups: file_groups}} ->
          Enum.each(file_groups, fn group ->
            if group.is_watch_dir do
              Enum.each(group.files, fn %{path: path} -> FileEventHandler.delete_file(path) end)
            else
              file_paths = Enum.map(group.files, & &1.path)
              FileEventHandler.delete_folder(group.dir, file_paths)
            end
          end)

          {:ok, []}

        nil ->
          {:ok, []}
      end

    socket = assign(socket, delete_confirm: nil)

    case result do
      {:ok, _entity_ids} ->
        # Check if entity still exists (cascade may have deleted it)
        files = Library.list_watched_files_by_entity_id(entity_id)

        if files == [] do
          # Entity was cascade-deleted — close modal
          {:noreply, push_patch(socket, to: build_path(socket, %{selected: nil, view: :main}))}
        else
          detail_files = load_entity_files(entity_id)
          {:noreply, assign(socket, detail_files: detail_files)}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Delete failed: #{reason}")}
    end
  end

  def handle_event("delete_cancel", _params, socket) do
    {:noreply, assign(socket, delete_confirm: nil)}
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

    # If the selected entity was among the updated entries, re-apply on-demand
    # extras so the detail panel stays correct after a PubSub-triggered reload.
    selected_id = socket.assigns.selected_entity_id

    socket =
      if selected_id && MapSet.member?(changed_ids, selected_id) do
        updated_by_id = load_extras_into_entry(socket.assigns.entries_by_id, selected_id)
        assign(socket, entries_by_id: updated_by_id)
      else
        socket
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
    resume_targets = Map.put(socket.assigns.resume_targets, entity_id, resume_target)

    socket =
      case apply_entry_update(
             socket.assigns.entries,
             socket.assigns.entries_by_id,
             entity_id,
             fn entry ->
               records = merge_progress_record(entry.progress_records, changed_record)
               %{entry | progress: summary, progress_records: records}
             end
           ) do
        {:ok, {new_entries, new_by_id}} ->
          assign(socket, entries: new_entries, entries_by_id: new_by_id)

        :not_found ->
          socket
      end

    {:noreply,
     socket
     |> assign(resume_targets: resume_targets)
     |> touch_stream_entries([entity_id])}
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
          assign(socket, entries: new_entries, entries_by_id: new_by_id)

        :not_found ->
          socket
      end

    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:setting_changed, "spoiler_free_mode", enabled}, socket) do
    {:noreply, assign(socket, spoiler_free: enabled)}
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

  def handle_info(:capabilities_changed, socket) do
    {:noreply, assign(socket, tmdb_ready: Capabilities.tmdb_ready?())}
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
    selected_entry = assigns.entries_by_id[assigns.selected_entity_id]
    offline_summary = offline_summary(assigns.dir_status, assigns.unavailable_count)

    assigns =
      assigns
      |> assign(:selected_entry, selected_entry)
      |> assign(:offline_summary, offline_summary)

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
            <span class="badge badge-neutral gap-1">
              In progress
              <.link
                patch={~p"/library"}
                class="opacity-60 hover:opacity-100"
                aria-label="Clear filter"
              >
                ×
              </.link>
            </span>
          </div>

          <div :if={@grid_count == 0} class="py-8 text-center empty-state-enter space-y-3">
            <div :if={@watch_dirs_configured} class="text-base-content/60">
              No entities found.
            </div>
            <div :if={not @watch_dirs_configured} class="max-w-md mx-auto space-y-2">
              <p class="text-base-content/80">
                No media yet — tell Media Centarr where your files live.
              </p>
              <.link
                navigate={~p"/settings?section=library"}
                class="btn btn-primary btn-sm"
                data-nav-item
              >
                Configure library
              </.link>
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
          delete_confirm={@delete_confirm}
          spoiler_free={@spoiler_free}
          tracking_status={@tracking_status}
          available={
            @selected_entry == nil ||
              Map.get(@availability_map, @selected_entry.entity.id, true)
          }
          tmdb_ready={@tmdb_ready}
          on_play="play"
          on_close="close_detail"
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  defp load_entity_files(entity_id) do
    Enum.map(Library.list_watched_files_by_entity_id(entity_id), fn file ->
      size =
        case File.stat(file.file_path) do
          {:ok, %{size: size}} -> size
          _ -> nil
        end

      %{file: file, size: size}
    end)
  end

  defp load_library(socket) do
    entries = Library.Browser.fetch_all_typed_entries()
    resume_targets = compute_resume_targets(entries)

    playback =
      Map.new(MediaCentarr.Playback.Sessions.list(), fn session ->
        {session.entity_id, session}
      end)

    socket
    |> assign_entries(entries)
    |> assign(
      resume_targets: resume_targets,
      playback: playback
    )
    |> recompute_counts()
  end

  defp load_tracking_status(entry) do
    case find_tmdb_id(entry) do
      {tmdb_id, media_type} ->
        MediaCentarr.ReleaseTracking.tracking_status({tmdb_id, media_type})

      nil ->
        nil
    end
  end

  defp find_tmdb_id(%{entity: %{type: :tv_series} = entity}) do
    case Enum.find(entity.external_ids, &(&1.source == "tmdb")) do
      nil -> nil
      ext_id -> {String.to_integer(ext_id.external_id), :tv_series}
    end
  end

  defp find_tmdb_id(%{entity: %{type: :movie_series} = entity}) do
    case Enum.find(entity.external_ids, &(&1.source == "tmdb_collection")) do
      nil -> nil
      ext_id -> {String.to_integer(ext_id.external_id), :movie}
    end
  end

  defp find_tmdb_id(_), do: nil

  defp compute_resume_targets(entries) do
    Map.new(entries, fn entry ->
      {entry.entity.id, ResumeTarget.compute(entry.entity, entry.progress_records)}
    end)
  end

  # Loads extras for a selected entity and merges them into entries_by_id so
  # the detail panel can render them without a full catalog reload. Called
  # on-demand when the selection changes to avoid loading extras for every
  # entity during catalog scan.
  defp load_extras_into_entry(entries_by_id, entity_id) do
    case entries_by_id[entity_id] do
      nil ->
        entries_by_id

      entry ->
        entity_with_extras = Library.load_extras_for_entity(entry.entity)
        Map.put(entries_by_id, entity_id, %{entry | entity: entity_with_extras})
    end
  end

  defp recompute_counts(socket) do
    assign(socket, counts: tab_counts(socket.assigns.entries))
  end

  # --- Entry Index ---

  defp assign_entries(socket, entries) do
    availability_map = MediaCentarrWeb.LibraryAvailability.availability_map(entries)

    assign(socket,
      entries: entries,
      entries_by_id: Map.new(entries, fn entry -> {entry.entity.id, entry} end),
      availability_map: availability_map,
      unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end)
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
    filtered_ids = compute_visible_ids(socket)
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

  defp compute_visible_ids(socket) do
    assigns = socket.assigns

    assigns.entries
    |> filtered_by_tab(assigns.active_tab)
    |> filtered_by_text(assigns.filter_text)
    |> filtered_by_in_progress(assigns.in_progress_filter)
    |> MapSet.new(& &1.entity.id)
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

  defp parse_view("info"), do: :info
  defp parse_view(_), do: :main

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

  defp load_spoiler_free_setting do
    case Settings.get_by_key("spoiler_free_mode") do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end

  # Runs inside Task.Supervisor — socket is not available here. The caller
  # resolved {fk_key, fk_id} from the cached entity via
  # LibraryHelpers.resolve_progress_fk/4 before spawning the task.
  defp update_watch_progress(entity_id, fk_key, fk_id) do
    progress = load_progress_by_fk(fk_key, fk_id)
    changed_record = apply_progress_transition(progress, fk_key, fk_id)
    ProgressBroadcaster.broadcast(entity_id, changed_record)
  end

  defp load_progress_by_fk(_fk_key, nil), do: nil

  defp load_progress_by_fk(fk_key, fk_id) do
    case Library.get_watch_progress_by_fk(fk_key, fk_id) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp apply_progress_transition(%{completed: true} = progress, _fk_key, _fk_id) do
    Log.info(
      :library,
      "toggled incomplete — was completed, position #{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)}"
    )

    Library.mark_watch_incomplete!(progress)
  end

  defp apply_progress_transition(%{completed: false} = progress, _fk_key, _fk_id) do
    Log.info(:library, fn ->
      "toggled completed — was #{completion_percentage(progress)} through (#{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)})"
    end)

    Library.mark_watch_completed!(progress)
  end

  defp apply_progress_transition(nil, fk_key, fk_id) when not is_nil(fk_id) do
    Log.info(:library, "toggled completed — no prior progress, created fresh record")

    params = %{fk_key => fk_id, position_seconds: 0.0, duration_seconds: 0.0}
    {:ok, record} = create_progress_by_fk(fk_key, params)
    Library.mark_watch_completed!(record)
  end

  defp apply_progress_transition(nil, _fk_key, nil), do: nil

  defp create_progress_by_fk(:movie_id, params),
    do: Library.find_or_create_watch_progress_for_movie(params)

  defp create_progress_by_fk(:episode_id, params),
    do: Library.find_or_create_watch_progress_for_episode(params)

  defp toggle_extra_watched(entity_id, extra_id) do
    progress =
      case Library.get_extra_progress_by_extra(extra_id) do
        {:ok, record} -> record
      end

    case progress do
      %{completed: true} ->
        Log.info(:library, "extra toggled incomplete")
        Library.mark_extra_incomplete!(progress)

      %{completed: false} ->
        Log.info(:library, "extra toggled completed")
        Library.mark_extra_completed!(progress)

      nil ->
        Log.info(:library, "extra toggled completed — no prior progress, created fresh record")

        {:ok, record} =
          Library.find_or_create_extra_progress(%{
            extra_id: extra_id,
            entity_id: entity_id,
            position_seconds: 0.0,
            duration_seconds: 0.0
          })

        Library.mark_extra_completed!(record)
    end

    ProgressBroadcaster.broadcast_extra(entity_id, extra_id)
  end
end
