defmodule MediaCentaurWeb.LibraryLive do
  @moduledoc """
  Two-zone library page with Continue Watching and Library Browse.

  **Continue Watching** shows in-progress entities as backdrop cards. Selecting
  one opens a ModalShell detail overlay.

  **Library Browse** shows the full entity catalog as a poster grid with
  type tabs, sort, and text filter. Selecting an entity opens a DrawerShell
  detail sidebar (space is always reserved to prevent grid reflow).

  Zone switching uses URL params (`?zone=library`) via `push_patch` so data
  stays loaded across tab changes.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{DateUtil, LibraryBrowser, Playback.Resume, Playback.ResumeTarget}
  alias MediaCentaurWeb.Components.{DrawerShell, ModalShell}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")
    end

    {:ok,
     assign(socket,
       entries: [],
       entries_by_id: %{},
       continue_watching: [],
       resume_targets: %{},
       playback: %{state: :idle, now_playing: nil},
       zone: :watching,
       selected_entity_id: nil,
       detail_presentation: nil,
       active_tab: :all,
       sort_order: :recent,
       filter_text: "",
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       watch_dirs: [],
       reload_timer: nil,
       pending_entity_ids: MapSet.new()
     )}
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
        {_, :library} -> :drawer
      end

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
      |> reset_stream()

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("select_cw_entity", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{selected: id}))}
  end

  def handle_event("select_entity", %{"id" => id}, socket) do
    new_id = if socket.assigns.selected_entity_id == id, do: nil, else: id

    socket =
      if new_id != socket.assigns.selected_entity_id do
        assign(socket, expanded_seasons: nil, expanded_episodes: MapSet.new())
      else
        socket
      end

    {:noreply, push_patch(socket, to: build_path(socket, %{selected: new_id}))}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{selected: nil}))}
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

  def handle_event("sort", %{"sort" => sort}, socket) do
    sort = parse_sort(sort)

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

  def handle_event("toggle_season", %{"season" => season_str}, socket) do
    season_number = String.to_integer(season_str)
    expanded = socket.assigns[:expanded_seasons] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, season_number),
        do: MapSet.delete(expanded, season_number),
        else: MapSet.put(expanded, season_number)

    {:noreply, assign(socket, expanded_seasons: expanded)}
  end

  def handle_event("toggle_episode_detail", %{"id" => id}, socket) do
    expanded = socket.assigns[:expanded_episodes] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded_episodes: expanded)}
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
         _last_activity_at},
        socket
      ) do
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary)
    resume_targets = Map.put(socket.assigns.resume_targets, entity_id, resume_target)

    {:noreply,
     socket
     |> assign_entries(entries)
     |> assign(resume_targets: resume_targets)
     |> recompute_continue_watching()
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    old_playing_id = playing_entity_id(socket.assigns.playback)
    socket = assign(socket, playback: %{state: new_state, now_playing: now_playing})
    new_playing_id = playing_entity_id(socket.assigns.playback)

    ids_to_touch = [old_playing_id, new_playing_id] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    {:noreply, touch_stream_entries(socket, ids_to_touch)}
  end

  @impl true
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
      |> assign(:watching_path, ~p"/library")
      |> assign(:library_path, ~p"/library?zone=library")

    ~H"""
    <Layouts.app flash={@flash} current_path="/library" full_width>
      <div id="library-input" phx-hook="InputSystem">
        <%!-- Zone tabs --%>
        <div role="tablist" class="tabs tabs-boxed w-fit mb-6" data-nav-zone="zone-tabs">
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
          <.cw_empty :if={@continue_watching == []} />
          <div
            :if={@continue_watching != []}
            class="grid grid-cols-[repeat(auto-fill,minmax(480px,1fr))] gap-4"
            data-nav-grid
          >
            <.cw_card
              :for={entry <- @continue_watching}
              entry={entry}
              resume={Map.get(@resume_targets, entry.entity.id)}
              playing={playing_entity_id(@playback) == entry.entity.id}
            />
          </div>
        </section>

        <%!-- Library Browse zone --%>
        <section :if={@zone == :library} id="browse">
          <.toolbar
            active_tab={@active_tab}
            counts={@counts}
            sort_order={@sort_order}
            filter_text={@filter_text}
          />

          <div :if={@grid_count == 0} class="text-base-content/60 py-8 text-center">
            No entities found.
          </div>

          <div :if={@grid_count > 0} class="flex gap-4 mt-4">
            <%!-- Poster grid --%>
            <div class="flex-1 min-w-0" data-nav-zone="grid">
              <div
                id="library-grid"
                phx-update="stream"
                class="grid grid-cols-[repeat(auto-fill,minmax(155px,1fr))] gap-3"
                data-nav-grid
              >
                <.poster_card
                  :for={{dom_id, entry} <- @streams.grid}
                  id={dom_id}
                  entry={entry}
                  selected={@selected_entity_id == entry.entity.id}
                  playing={playing_entity_id(@playback) == entry.entity.id}
                />
              </div>
            </div>

            <%!-- Drawer column — always reserved to prevent grid reflow --%>
            <div class="w-[480px] flex-shrink-0 hidden lg:block">
              <DrawerShell.drawer_shell
                :if={@selected_entry && @detail_presentation == :drawer}
                entity={@selected_entry.entity}
                progress={@selected_entry.progress}
                resume={Map.get(@resume_targets, @selected_entry.entity.id)}
                progress_records={@selected_entry.progress_records}
                watch_dirs={@watch_dirs}
                expanded_seasons={assigns[:expanded_seasons]}
                expanded_episodes={assigns[:expanded_episodes] || MapSet.new()}
                on_play="play"
                on_close="close_detail"
              />
            </div>
          </div>
        </section>

        <%!-- Detail modal (CW uses modal presentation) --%>
        <ModalShell.modal_shell
          :if={@selected_entry && @detail_presentation == :modal}
          entity={@selected_entry.entity}
          progress={@selected_entry.progress}
          resume={Map.get(@resume_targets, @selected_entry.entity.id)}
          progress_records={@selected_entry.progress_records}
          watch_dirs={@watch_dirs}
          expanded_seasons={assigns[:expanded_seasons]}
          expanded_episodes={assigns[:expanded_episodes] || MapSet.new()}
          on_play="play"
          on_close="close_detail"
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Toolbar ---

  defp toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-4 flex-wrap" data-nav-zone="toolbar">
      <div role="tablist" class="tabs tabs-boxed w-fit">
        <button
          :for={{tab, label} <- [{:all, "All"}, {:movies, "Movies"}, {:tv, "TV"}]}
          role="tab"
          class={["tab", @active_tab == tab && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab={tab}
          data-nav-item
          tabindex="0"
        >
          {label}
          <span class="badge badge-sm ml-1">{@counts[tab] || 0}</span>
        </button>
      </div>

      <select
        phx-change="sort"
        name="sort"
        value={to_string(@sort_order)}
        class="select select-sm select-bordered w-auto"
        data-nav-item
        tabindex="0"
      >
        <option value="recent">Recently Added</option>
        <option value="alpha">A–Z</option>
        <option value="year">Year</option>
      </select>

      <form phx-change="filter" class="ml-auto">
        <input
          id="library-filter"
          type="text"
          name="filter_text"
          value={@filter_text}
          placeholder="Filter by name…"
          phx-debounce="150"
          class="input input-sm input-bordered w-48"
        />
      </form>
    </div>
    """
  end

  # --- Poster Card ---

  defp poster_card(assigns) do
    entity = assigns.entry.entity
    poster = image_url(entity, "poster")
    assigns = assign(assigns, :poster, poster)

    ~H"""
    <div
      id={@id}
      phx-click="select_entity"
      phx-value-id={@entry.entity.id}
      data-nav-item
      data-entity-id={@entry.entity.id}
      tabindex="0"
      class={[
        "card glass-surface cursor-pointer overflow-hidden transition-all",
        "hover:ring-1 hover:ring-base-content/20",
        @selected && "ring-2 ring-primary",
        @playing && "ring-2 ring-primary"
      ]}
    >
      <%!-- Poster --%>
      <div class="aspect-[2/3] glass-inset relative">
        <img :if={@poster} src={@poster} class="w-full h-full object-cover" loading="lazy" />
        <div :if={!@poster} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-8 text-base-content/20" />
        </div>

        <%!-- Now-playing pulse --%>
        <div
          :if={@playing}
          class="absolute top-2 right-2 size-3 rounded-full bg-primary animate-pulse"
        />

        <%!-- Progress bar --%>
        <.card_progress_bar progress={@entry.progress} />
      </div>

      <%!-- Card footer --%>
      <div class="p-2">
        <div class="text-sm font-medium leading-tight line-clamp-2">
          {@entry.entity.name || "Untitled"}
        </div>
        <div class="mt-0.5 text-xs text-base-content/50">
          {format_type(@entry.entity.type)}<span :if={@entry.entity.date_published}> · {extract_year(@entry.entity.date_published)}</span>
        </div>
      </div>
    </div>
    """
  end

  defp card_progress_bar(%{progress: nil} = assigns) do
    ~H"""
    """
  end

  defp card_progress_bar(%{progress: progress} = assigns) do
    fraction = compute_progress_fraction(progress)
    assigns = assign(assigns, :fraction, fraction)

    ~H"""
    <div :if={@fraction > 0} class="absolute bottom-0 left-0 right-0 h-[3px] bg-base-content/20">
      <div class="h-full bg-primary" style={"width: #{@fraction}%"} />
    </div>
    """
  end

  # --- Continue Watching Card ---

  defp cw_card(assigns) do
    entity = assigns.entry.entity
    backdrop = image_url(entity, "backdrop")
    background = backdrop || image_url(entity, "poster")
    logo = image_url(entity, "logo")
    progress_fraction = compute_progress_fraction(assigns.entry.progress)
    resume_label = format_resume_label(assigns.resume, entity)

    assigns =
      assign(assigns,
        background: background,
        logo: logo,
        progress_fraction: progress_fraction,
        resume_label: resume_label
      )

    ~H"""
    <div
      phx-click="select_cw_entity"
      phx-value-id={@entry.entity.id}
      data-nav-item
      data-entity-id={@entry.entity.id}
      tabindex="0"
      class={[
        "relative rounded-lg overflow-hidden cursor-pointer group",
        "hover:scale-[1.02] hover:shadow-xl transition-transform",
        @playing && "ring-2 ring-primary"
      ]}
    >
      <div class="aspect-video glass-inset relative">
        <img
          :if={@background}
          src={@background}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>

        <div class="absolute inset-0 bg-gradient-to-t from-black/88 via-black/40 via-40% to-transparent" />

        <div class="absolute bottom-10 left-4 right-4">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-12 max-w-[60%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)]"
          />
          <h3
            :if={!@logo}
            class="text-lg font-bold text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          >
            {@entry.entity.name}
          </h3>
        </div>

        <div class="absolute bottom-4 left-4 right-4 flex items-center justify-between">
          <span :if={@resume_label} class="text-sm text-primary font-medium drop-shadow">
            {@resume_label}
          </span>
        </div>

        <div
          :if={@playing}
          class="absolute top-3 right-3 size-3 rounded-full bg-primary animate-pulse"
        />

        <div
          :if={@progress_fraction > 0}
          class="absolute bottom-0 left-0 right-0 h-1 bg-base-content/20"
        >
          <div class="h-full bg-primary" style={"width: #{@progress_fraction}%"} />
        </div>
      </div>
    </div>
    """
  end

  defp cw_empty(assigns) do
    ~H"""
    <div class="text-base-content/50 py-6 text-center text-sm">
      Nothing in progress. Switch to the Library tab to start watching.
    </div>
    """
  end

  # --- Data Loading ---

  defp load_library(socket) do
    entries = LibraryBrowser.fetch_entities()
    resume_targets = compute_resume_targets(entries)

    socket
    |> assign_entries(entries)
    |> assign(
      resume_targets: resume_targets,
      playback: MediaCentaur.Playback.Manager.current_state(),
      watch_dirs: MediaCentaur.Config.get(:watch_dirs) || []
    )
    |> recompute_continue_watching()
    |> recompute_counts()
  end

  defp recompute_continue_watching(socket) do
    continue_watching =
      Enum.filter(socket.assigns.entries, fn entry ->
        # Must have actual watch history — excludes the entire unwatched library
        # (Resume.resolve returns :play_next for entities with zero progress)
        entry.progress_records != [] &&
          case Resume.resolve(entry.entity, entry.progress_records) do
            {:resume, _, _} -> true
            {:play_next, _, _} -> true
            _ -> false
          end
      end)

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
    |> stream(:grid, filtered, reset: true, dom_id: &"entity-#{&1.entity.id}")
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

  # --- Filtering ---

  defp filtered_by_tab(entries, :all), do: entries

  defp filtered_by_tab(entries, :movies) do
    Enum.filter(entries, fn %{entity: entity} ->
      entity.type in [:movie, :movie_series, :video_object]
    end)
  end

  defp filtered_by_tab(entries, :tv) do
    Enum.filter(entries, fn %{entity: entity} -> entity.type == :tv_series end)
  end

  defp filtered_by_text(entries, ""), do: entries

  defp filtered_by_text(entries, text) do
    needle = String.downcase(text)

    Enum.filter(entries, fn %{entity: entity} ->
      name_matches?(entity.name, needle) || nested_matches?(entity, needle)
    end)
  end

  defp name_matches?(nil, _needle), do: false
  defp name_matches?(name, needle), do: String.contains?(String.downcase(name), needle)

  defp nested_matches?(%{type: :tv_series, seasons: seasons}, needle) when is_list(seasons) do
    Enum.any?(seasons, fn season ->
      Enum.any?(season.episodes || [], fn episode -> name_matches?(episode.name, needle) end)
    end)
  end

  defp nested_matches?(%{type: :movie_series, movies: movies}, needle) when is_list(movies) do
    Enum.any?(movies, fn movie -> name_matches?(movie.name, needle) end)
  end

  defp nested_matches?(_entity, _needle), do: false

  # --- Sorting ---

  defp sorted_by(entries, :alpha) do
    Enum.sort_by(entries, fn entry -> (entry.entity.name || "") |> String.downcase() end)
  end

  defp sorted_by(entries, :year) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.date_published || "" end,
      :desc
    )
  end

  defp sorted_by(entries, :recent) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.inserted_at || ~U[2000-01-01 00:00:00Z] end,
      {:desc, DateTime}
    )
  end

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
    params = if tab != :all, do: Map.put(params, :tab, tab), else: params
    params = if sort != :recent, do: Map.put(params, :sort, sort), else: params
    params = if filter != "", do: Map.put(params, :filter, filter), else: params
    params = if selected, do: Map.put(params, :selected, selected), else: params

    if params == %{}, do: ~p"/library", else: ~p"/library?#{params}"
  end

  # --- Helpers ---

  defp tab_counts(entries) do
    Enum.reduce(entries, %{all: 0, movies: 0, tv: 0}, fn %{entity: entity}, counts ->
      counts = %{counts | all: counts.all + 1}

      cond do
        entity.type in [:movie, :movie_series, :video_object] ->
          %{counts | movies: counts.movies + 1}

        entity.type == :tv_series ->
          %{counts | tv: counts.tv + 1}

        true ->
          counts
      end
    end)
  end

  defp update_entry_progress(entries, entity_id, summary) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry -> %{entry | progress: summary}
      entry -> entry
    end)
  end

  defp playing_entity_id(%{now_playing: %{entity_id: id}}), do: id
  defp playing_entity_id(_), do: nil

  defp compute_progress_fraction(nil), do: 0

  defp compute_progress_fraction(%{
         episode_position_seconds: position,
         episode_duration_seconds: duration
       })
       when duration > 0 do
    Float.round(position / duration * 100, 1)
  end

  defp compute_progress_fraction(_), do: 0

  defp format_resume_label(nil, _entity), do: nil

  defp format_resume_label(%{"action" => "resume"} = resume, _entity) do
    case resume do
      %{"seasonNumber" => season, "episodeNumber" => episode, "positionSeconds" => position} ->
        "Resume S#{season} E#{episode} at #{format_seconds(position)}"

      %{"positionSeconds" => position} ->
        "Resume at #{format_seconds(position)}"

      _ ->
        "Resume"
    end
  end

  defp format_resume_label(%{"action" => "begin"} = resume, _entity) do
    case resume do
      %{"seasonNumber" => season, "episodeNumber" => episode} ->
        "Play S#{season} E#{episode}"

      _ ->
        "Play"
    end
  end

  defp format_resume_label(_resume, _entity), do: nil

  defp format_type(:movie), do: "Movie"
  defp format_type(:movie_series), do: "Movie Series"
  defp format_type(:tv_series), do: "TV Series"
  defp format_type(:video_object), do: "Video"
  defp format_type(type), do: type |> to_string() |> String.capitalize()

  defp extract_year(date_string), do: DateUtil.extract_year(date_string) || ""
end
