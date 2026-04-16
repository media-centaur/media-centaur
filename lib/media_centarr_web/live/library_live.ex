defmodule MediaCentarrWeb.LibraryLive do
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
  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.{
    Format,
    Library,
    Library.FileEventHandler,
    LibraryBrowser,
    Playback,
    Playback.ProgressBroadcaster,
    Playback.ResumeTarget,
    ReleaseTracking,
    Settings
  }

  alias MediaCentarrWeb.Components.{
    DetailPanel,
    LibraryCards,
    ModalShell,
    TrackModal,
    UpcomingCards
  }

  import MediaCentarrWeb.LibraryHelpers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Library.subscribe()
      Playback.subscribe()
      Settings.subscribe()
      ReleaseTracking.subscribe()
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
       delete_confirm: nil,
       detail_view: :main,
       detail_files: [],
       spoiler_free: load_spoiler_free_setting(),
       upcoming_path: ~p"/?zone=upcoming",
       upcoming_releases: %{upcoming: [], released: []},
       upcoming_events: [],
       upcoming_images: %{},
       calendar_month: {Date.utc_today().year, Date.utc_today().month},
       selected_day: nil,
       track_modal_open: false,
       track_suggestions: [],
       track_suggestions_loading: false,
       track_search_query: "",
       track_search_results: [],
       track_search_loading: false,
       track_scope_item: nil,
       track_collection_item: nil,
       track_confirmed_ids: MapSet.new(),
       tracking_status: nil,
       confirm_stop_item: nil,
       tracked_items: []
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
    detail_view = parse_view(params["view"])

    presentation =
      case {selected_id, zone} do
        {nil, _} -> nil
        {_, :watching} -> :modal
        {_, :library} -> :modal
        {_, :upcoming} -> nil
      end

    grid_changed =
      zone != socket.assigns.zone ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text

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
        if selected_entry, do: load_tracking_status(selected_entry), else: nil
      else
        socket.assigns.tracking_status
      end

    socket =
      socket
      |> assign(
        zone: zone,
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text,
        selected_entity_id: selected_id,
        detail_presentation: presentation,
        detail_view: detail_view,
        detail_files: detail_files,
        tracking_status: tracking_status
      )
      |> then(fn s -> if grid_changed, do: reset_stream(s), else: s end)

    socket =
      if zone == :upcoming do
        load_upcoming(socket)
      else
        socket
      end

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

  def handle_event(
        "toggle_extra_watched",
        %{"extra-id" => extra_id, "entity-id" => entity_id},
        socket
      ) do
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

  def handle_event("open_track_modal", _params, socket) do
    socket =
      assign(socket,
        track_modal_open: true,
        track_suggestions_loading: true,
        track_search_query: "",
        track_search_results: [],
        track_scope_item: nil,
        track_collection_item: nil
      )

    send(self(), :load_track_suggestions)
    {:noreply, socket}
  end

  def handle_event("close_track_modal", _params, socket) do
    {:noreply,
     assign(socket,
       track_modal_open: false,
       track_suggestions: [],
       track_suggestions_loading: false,
       track_search_query: "",
       track_search_results: [],
       track_search_loading: false,
       track_scope_item: nil,
       track_collection_item: nil,
       track_confirmed_ids: MapSet.new()
     )}
  end

  def handle_event("track_search", %{"query" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
     assign(socket,
       track_search_query: query,
       track_search_results: [],
       track_search_loading: false
     )}
  end

  def handle_event("track_search", %{"query" => query}, socket) do
    socket = assign(socket, track_search_query: query, track_search_loading: true)
    send(self(), {:do_track_search, query})
    {:noreply, socket}
  end

  def handle_event("track_suggestion", params, socket) do
    tmdb_id = String.to_integer(params["tmdb-id"])
    tmdb_id_str = to_string(tmdb_id)
    confirmed = socket.assigns.track_confirmed_ids

    if MapSet.member?(confirmed, tmdb_id_str) do
      # Untrack — find and delete the tracking item
      case MediaCentarr.ReleaseTracking.get_item_by_tmdb(tmdb_id, :tv_series) do
        nil -> :ok
        item -> MediaCentarr.ReleaseTracking.delete_item(item)
      end

      {:noreply, assign(socket, track_confirmed_ids: MapSet.delete(confirmed, tmdb_id_str))}
    else
      # Track
      tv_series_id = params["tv-series-id"]
      name = params["name"]

      {last_season, last_episode} =
        MediaCentarr.ReleaseTracking.Helpers.find_last_library_episode(tv_series_id)

      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        MediaCentarr.ReleaseTracking.track_from_search(
          %{tmdb_id: tmdb_id, media_type: :tv_series, name: name, poster_path: nil},
          %{start_season: last_season, start_episode: last_episode}
        )
      end)

      {:noreply, assign(socket, track_confirmed_ids: MapSet.put(confirmed, tmdb_id_str))}
    end
  end

  def handle_event("select_search_result", params, socket) do
    tmdb_id = String.to_integer(params["tmdb-id"])
    media_type = String.to_existing_atom(params["media-type"])
    name = params["name"]
    poster_path = params["poster-path"]

    result = %{tmdb_id: tmdb_id, media_type: media_type, name: name, poster_path: poster_path}

    case media_type do
      :tv_series ->
        {:noreply, assign(socket, track_scope_item: result, track_collection_item: nil)}

      :movie ->
        # Track immediately for movies (collection detection deferred to future iteration)
        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          MediaCentarr.ReleaseTracking.track_from_search(result, %{})
        end)

        results =
          Enum.map(socket.assigns.track_search_results, fn r ->
            if r.tmdb_id == tmdb_id, do: Map.put(r, :already_tracked, true), else: r
          end)

        {:noreply, assign(socket, track_search_results: results, track_collection_item: nil)}
    end
  end

  def handle_event("confirm_track", params, socket) do
    tmdb_id = String.to_integer(params["tmdb_id"])
    name = params["name"]
    poster_path = params["poster_path"]

    {start_season, start_episode} =
      case params["scope"] do
        "custom" ->
          {String.to_integer(params["start_season"] || "1"),
           String.to_integer(params["start_episode"] || "1")}

        _ ->
          {0, 0}
      end

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      MediaCentarr.ReleaseTracking.track_from_search(
        %{tmdb_id: tmdb_id, media_type: :tv_series, name: name, poster_path: poster_path},
        %{start_season: start_season, start_episode: start_episode}
      )
    end)

    results =
      Enum.map(socket.assigns.track_search_results, fn r ->
        if r.tmdb_id == tmdb_id, do: Map.put(r, :already_tracked, true), else: r
      end)

    {:noreply, assign(socket, track_search_results: results, track_scope_item: nil)}
  end

  def handle_event("dismiss_release", %{"release-id" => release_id}, socket) do
    MediaCentarr.ReleaseTracking.dismiss_release(release_id)
    {:noreply, socket}
  end

  def handle_event("stop_tracking", %{"item-id" => item_id}, socket) do
    case MediaCentarr.ReleaseTracking.get_item(item_id) do
      nil -> {:noreply, socket}
      item -> {:noreply, assign(socket, confirm_stop_item: item)}
    end
  end

  def handle_event("confirm_stop_tracking", _params, socket) do
    case socket.assigns.confirm_stop_item do
      nil ->
        {:noreply, socket}

      item ->
        MediaCentarr.ReleaseTracking.create_event!(%{
          item_id: item.id,
          item_name: item.name,
          event_type: :stopped_tracking,
          description: "Stopped tracking #{item.name}"
        })

        MediaCentarr.ReleaseTracking.delete_item(item)

        {:noreply, assign(socket, confirm_stop_item: nil)}
    end
  end

  def handle_event("cancel_stop_tracking", _params, socket) do
    {:noreply, assign(socket, confirm_stop_item: nil)}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = socket.assigns.calendar_month
    date = Date.new!(year, month, 1) |> Date.add(-1)
    {:noreply, assign(socket, calendar_month: {date.year, date.month}, selected_day: nil)}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = socket.assigns.calendar_month
    last_day = Date.new!(year, month, 1) |> Date.end_of_month()
    date = Date.add(last_day, 1)
    {:noreply, assign(socket, calendar_month: {date.year, date.month}, selected_day: nil)}
  end

  def handle_event("jump_today", _params, socket) do
    today = Date.utc_today()
    {:noreply, assign(socket, calendar_month: {today.year, today.month}, selected_day: nil)}
  end

  def handle_event("select_day", %{"date" => ""}, socket) do
    {:noreply, assign(socket, selected_day: nil)}
  end

  def handle_event("select_day", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        selected = if socket.assigns.selected_day == date, do: nil, else: date
        {:noreply, assign(socket, selected_day: selected)}

      _ ->
        {:noreply, socket}
    end
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
        Enum.find(socket.assigns.detail_files, fn %{file: f} -> f.file_path == file_path end)

      size = if file_info, do: file_info.size

      {:noreply,
       assign(socket,
         delete_confirm: {:file, %{path: file_path, name: Path.basename(file_path), size: size}}
       )}
    end
  end

  def handle_event("delete_folder_prompt", %{"path" => folder_path, "count" => _count}, socket) do
    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

    cond do
      playing?(socket.assigns.playback, socket.assigns.selected_entity_id) ->
        {:noreply, put_flash(socket, :error, "Stop playback before deleting")}

      folder_path in watch_dirs ->
        {:noreply, put_flash(socket, :error, "Cannot delete a watch directory")}

      true ->
        folder_files =
          socket.assigns.detail_files
          |> Enum.filter(fn %{file: f} -> Path.dirname(f.file_path) == folder_path end)
          |> Enum.map(fn %{file: f, size: size} ->
            %{name: Path.basename(f.file_path), size: size}
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
      watch_dirs = MapSet.new(MediaCentarr.Config.get(:watch_dirs) || [])
      payload = DetailPanel.build_delete_all_payload(socket.assigns.detail_files, watch_dirs)
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

        if files != [] do
          detail_files = load_entity_files(entity_id)
          {:noreply, assign(socket, detail_files: detail_files)}
        else
          # Entity was cascade-deleted — close modal
          {:noreply, push_patch(socket, to: build_path(socket, %{selected: nil, view: :main}))}
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
      LibraryBrowser.fetch_typed_entries_by_ids(MapSet.to_list(changed_ids))

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
      |> recompute_continue_watching()
      |> recompute_counts()

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
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary, changed_record)
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
    playback = apply_playback_change(socket.assigns.playback, entity_id, new_state, now_playing)

    {:noreply,
     socket
     |> assign(playback: playback)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info(
        {:extra_progress_updated,
         %{entity_id: entity_id, extra_id: _extra_id, progress: progress}},
        socket
      ) do
    entries = update_entry_extra_progress(socket.assigns.entries, entity_id, progress)

    {:noreply,
     socket
     |> assign_entries(entries)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:setting_changed, "spoiler_free_mode", enabled}, socket) do
    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  def handle_info({:releases_updated, _item_ids}, socket) do
    socket =
      if socket.assigns.zone == :upcoming do
        load_upcoming(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_track_suggestions, socket) do
    suggestions = MediaCentarr.ReleaseTracking.suggest_trackable_items()

    {:noreply, assign(socket, track_suggestions: suggestions, track_suggestions_loading: false)}
  end

  @impl true
  def handle_info({:do_track_search, query}, socket) do
    if query == socket.assigns.track_search_query do
      results = MediaCentarr.ReleaseTracking.search_tmdb(query)
      {:noreply, assign(socket, track_search_results: results, track_search_loading: false)}
    else
      {:noreply, socket}
    end
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
    <Layouts.console_mount socket={@socket} />
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
          <.link
            patch={@upcoming_path}
            role="tab"
            class={["tab", @zone == :upcoming && "tab-active"]}
            data-nav-item
            data-nav-zone-value="upcoming"
            tabindex="0"
          >
            Upcoming
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

        <%!-- Upcoming Releases zone --%>
        <section :if={@zone == :upcoming} id="upcoming" class="max-w-7xl space-y-6 pb-8">
          <UpcomingCards.upcoming_zone
            releases={@upcoming_releases}
            events={@upcoming_events}
            images={@upcoming_images}
            calendar_month={@calendar_month}
            selected_day={@selected_day}
            tracked_items={@tracked_items}
            confirm_stop_item={@confirm_stop_item}
          />
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
          on_play="play"
          on_close="close_detail"
        />

        <%!-- Track New Show modal (always in DOM) --%>
        <TrackModal.track_modal
          open={@track_modal_open}
          suggestions={@track_suggestions}
          suggestions_loading={@track_suggestions_loading}
          search_query={@track_search_query}
          search_results={@track_search_results}
          search_loading={@track_search_loading}
          scope_item={@track_scope_item}
          collection_item={@track_collection_item}
          confirmed_ids={@track_confirmed_ids}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  defp load_entity_files(entity_id) do
    Library.list_watched_files_by_entity_id(entity_id)
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
    entries = LibraryBrowser.fetch_all_typed_entries()
    resume_targets = compute_resume_targets(entries)

    playback =
      MediaCentarr.Playback.Sessions.list()
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

  defp load_upcoming(socket) do
    releases = MediaCentarr.ReleaseTracking.list_releases()
    events = MediaCentarr.ReleaseTracking.list_recent_events(10)
    image_map = load_tracking_images(releases)
    tracked_items = build_tracked_items_from_watching()

    assign(socket,
      upcoming_releases: releases,
      upcoming_events: events,
      upcoming_images: image_map,
      tracked_items: tracked_items
    )
  end

  defp build_tracked_items_from_watching do
    MediaCentarr.ReleaseTracking.list_watching_items()
    |> Enum.map(fn item ->
      releases = item.releases || []
      upcoming_count = Enum.count(releases, &(not &1.released and not &1.in_library))
      released_count = Enum.count(releases, &(&1.released and not &1.in_library))

      status_text =
        case {upcoming_count, released_count} do
          {0, 0} -> "tracking"
          {u, 0} -> "#{u} upcoming"
          {0, r} -> "#{r} released"
          {u, r} -> "#{u} upcoming, #{r} released"
        end

      %{
        item_id: item.id,
        name: item.name,
        media_type: item.media_type,
        status_text: status_text
      }
    end)
  end

  defp load_tracking_images(%{upcoming: upcoming, released: released}) do
    (upcoming ++ released)
    |> Enum.map(& &1.item)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reduce(%{}, fn item, acc ->
      images =
        %{}
        |> maybe_put_image(:backdrop, item.backdrop_path)
        |> maybe_put_image(:poster, item.poster_path)

      if images == %{}, do: acc, else: Map.put(acc, item.id, images)
    end)
  end

  defp maybe_put_image(map, _role, nil), do: map
  defp maybe_put_image(map, role, path), do: Map.put(map, role, "/media-images/#{path}")

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

  # Sentinel for entries whose progress summary reports in-progress but have no
  # loaded progress records (e.g. immediately after a first mark-watched broadcast
  # on a stale entry). Sinks them to the bottom of the sort rather than crashing.
  @epoch_datetime ~U[1970-01-01 00:00:00Z]

  defp recompute_continue_watching(socket) do
    continue_watching =
      socket.assigns.entries
      |> Enum.filter(&in_progress?/1)
      |> Enum.sort_by(
        fn entry -> max_last_watched_at(entry) || @epoch_datetime end,
        {:desc, DateTime}
      )

    assign(socket, continue_watching: continue_watching)
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
    socket.assigns.entries
    |> filtered_by_tab(socket.assigns.active_tab)
    |> filtered_by_text(socket.assigns.filter_text)
    |> sorted_by(socket.assigns.sort_order)
  end

  defp compute_visible_ids(socket) do
    socket.assigns.entries
    |> filtered_by_tab(socket.assigns.active_tab)
    |> filtered_by_text(socket.assigns.filter_text)
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

  defp parse_zone("library"), do: :library
  defp parse_zone("upcoming"), do: :upcoming
  defp parse_zone(_), do: :watching

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

    zone = Map.get(overrides, :zone, assigns.zone)
    tab = Map.get(overrides, :tab, assigns.active_tab)
    sort = Map.get(overrides, :sort, assigns.sort_order)
    filter = Map.get(overrides, :filter, assigns.filter_text)
    selected = Map.get(overrides, :selected, assigns.selected_entity_id)
    view = Map.get(overrides, :view, assigns.detail_view)

    params = %{}
    params = if zone == :library, do: Map.put(params, :zone, :library), else: params
    params = if zone == :upcoming, do: Map.put(params, :zone, :upcoming), else: params
    params = if zone == :library, do: Map.put(params, :tab, tab), else: params
    params = if zone == :library, do: Map.put(params, :sort, sort), else: params
    params = if filter != "", do: Map.put(params, :filter, filter), else: params
    params = if selected, do: Map.put(params, :selected, selected), else: params
    params = if selected && view == :info, do: Map.put(params, :view, :info), else: params

    if params == %{}, do: ~p"/", else: ~p"/?#{params}"
  end

  # --- Helpers ---

  defp update_entry_progress(entries, entity_id, summary, changed_record) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry ->
        records = merge_progress_record(entry.progress_records, changed_record)
        %{entry | progress: summary, progress_records: records}

      entry ->
        entry
    end)
  end

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  defp load_spoiler_free_setting do
    case Settings.get_by_key("spoiler_free_mode") do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end

  # Runs inside Task.Supervisor — socket is not available here. The caller
  # has already resolved {fk_key, fk_id} from the cached entity, so this
  # function only hits the (now-indexed) watch_progress row and broadcasts
  # the result.
  defp update_watch_progress(entity_id, fk_key, fk_id) do
    progress =
      if fk_id do
        case Library.get_watch_progress_by_fk(fk_key, fk_id) do
          {:ok, record} -> record
          _ -> nil
        end
      end

    changed_record =
      case progress do
        %{completed: true} ->
          Log.info(
            :library,
            "toggled incomplete — was completed, position #{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)}"
          )

          Library.mark_watch_incomplete!(progress)

        %{completed: false} ->
          Log.info(:library, fn ->
            pct =
              if progress.duration_seconds > 0,
                do:
                  "#{Float.round(progress.position_seconds / progress.duration_seconds * 100, 0)}%",
                else: "unknown"

            "toggled completed — was #{pct} through (#{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)})"
          end)

          Library.mark_watch_completed!(progress)

        nil ->
          if fk_id do
            Log.info(:library, "toggled completed — no prior progress, created fresh record")

            params = %{
              fk_key => fk_id,
              position_seconds: 0.0,
              duration_seconds: 0.0
            }

            {:ok, record} = create_progress_by_fk(fk_key, params)
            Library.mark_watch_completed!(record)
          end
      end

    ProgressBroadcaster.broadcast(entity_id, changed_record)
  end

  # Resolve the {fk_key, fk_id} tuple from the cached entity map. The
  # LibraryLive mount loads every entity with full preloads via
  # LibraryBrowser — seasons, episodes, and movies are already attached
  # to the normalized entity map in `entries_by_id`, so this is a cheap
  # in-memory walk with no DB queries. Called synchronously from the
  # event handler BEFORE spawning the async task.
  #
  # Note: `entry.entity` is a normalized map (not an Ecto struct) with a
  # `:type` field. Inner `seasons`/`episodes`/`movies` are still Ecto
  # structs, so we can match on their fields directly.
  defp resolve_progress_fk(entries_by_id, entity_id, 0, ordinal) do
    case Map.get(entries_by_id, entity_id) do
      %{entity: %{type: :movie_series, movies: movies}} when is_list(movies) ->
        available = MediaCentarr.Playback.MovieList.list_available(%{movies: movies})

        case Enum.find(available, fn {ord, _id, _url} -> ord == ordinal end) do
          {_ord, movie_id, _url} -> {:movie_id, movie_id}
          nil -> {:movie_id, nil}
        end

      %{entity: %{type: :movie, id: id}} ->
        # Standalone movie — the entity id IS the movie id.
        {:movie_id, id}

      _ ->
        # Fallback: not in cache or wrong type. Treat entity_id as a movie
        # id and let the downstream get_watch_progress_by_fk handle
        # :not_found gracefully.
        {:movie_id, entity_id}
    end
  end

  defp resolve_progress_fk(entries_by_id, entity_id, season_number, episode_number) do
    case Map.get(entries_by_id, entity_id) do
      %{entity: %{type: :tv_series, seasons: seasons}} when is_list(seasons) ->
        episode_id =
          seasons
          |> Enum.find(&(&1.season_number == season_number))
          |> case do
            %{episodes: episodes} when is_list(episodes) ->
              case Enum.find(episodes, &(&1.episode_number == episode_number)) do
                %{id: id} -> id
                _ -> nil
              end

            _ ->
              nil
          end

        {:episode_id, episode_id}

      _ ->
        {:episode_id, nil}
    end
  end

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

  defp update_entry_extra_progress(entries, entity_id, progress) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id} = entity} = entry ->
        extra_progress = merge_extra_progress(entity.extra_progress || [], progress)
        %{entry | entity: %{entity | extra_progress: extra_progress}}

      entry ->
        entry
    end)
  end
end
