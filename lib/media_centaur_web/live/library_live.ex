defmodule MediaCentaurWeb.LibraryLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{DateUtil, LibraryBrowser}
  alias MediaCentaur.Playback.EpisodeList

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")

        entries = LibraryBrowser.fetch_entities()

        socket
        |> assign(entries: entries)
        |> assign(counts: tab_counts(entries))
        |> assign(watch_dirs: MediaCentaur.Config.get(:watch_dirs) || [])
        |> assign(playback: MediaCentaur.Playback.Manager.current_state())
      else
        socket
        |> assign(entries: [])
        |> assign(counts: %{all: 0, movies: 0, tv: 0})
        |> assign(watch_dirs: [])
        |> assign(playback: %{state: :idle, now_playing: nil})
      end

    {:ok,
     socket
     |> assign(
       active_tab: :all,
       selected_id: nil,
       metadata_expanded: false,
       expanded_episodes: MapSet.new(),
       reload_timer: nil,
       pending_entity_ids: MapSet.new(),
       filter_text: ""
     )
     |> reset_stream()}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> assign(active_tab: String.to_existing_atom(tab)) |> reset_stream()}
  end

  def handle_event("filter", %{"filter_text" => text}, socket) do
    {:noreply, socket |> assign(filter_text: text) |> reset_stream()}
  end

  def handle_event("select_entity", %{"id" => id}, socket) do
    if socket.assigns.selected_id == id do
      {:noreply, socket |> assign(selected_id: nil) |> assign_selected_entry()}
    else
      {:noreply,
       socket
       |> assign(
         selected_id: id,
         metadata_expanded: false,
         expanded_episodes: MapSet.new()
       )
       |> assign_selected_entry()}
    end
  end

  def handle_event("toggle_metadata", _params, socket) do
    {:noreply, assign(socket, metadata_expanded: !socket.assigns.metadata_expanded)}
  end

  def handle_event("toggle_episode_detail", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_episodes, id) do
        MapSet.delete(socket.assigns.expanded_episodes, id)
      else
        MapSet.put(socket.assigns.expanded_episodes, id)
      end

    {:noreply, assign(socket, expanded_episodes: expanded)}
  end

  def handle_event("play", %{"id" => uuid}, socket) do
    LibraryBrowser.play(uuid)
    {:noreply, socket}
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

    entries = Enum.sort_by(entries ++ new_entries, fn entry -> entry.entity.name || "" end)

    selected_id =
      if socket.assigns.selected_id && MapSet.member?(gone_ids, socket.assigns.selected_id),
        do: nil,
        else: socket.assigns.selected_id

    socket =
      socket
      |> assign(entries: entries, counts: tab_counts(entries))
      |> assign(reload_timer: nil, pending_entity_ids: MapSet.new())
      |> assign(selected_id: selected_id)

    # Structural changes (entities added/removed) need a full stream reset for correct ordering.
    # Pure updates get surgical stream_inserts for O(1) per changed card.
    if MapSet.size(gone_ids) > 0 || new_entries != [] do
      {:noreply, reset_stream(socket)}
    else
      {:noreply, touch_stream_entries(socket, MapSet.to_list(changed_ids))}
    end
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    old_playing_id = playing_entity_id(socket.assigns.playback)
    socket = assign(socket, playback: %{state: new_state, now_playing: now_playing})
    new_playing_id = playing_entity_id(socket.assigns.playback)

    ids_to_touch =
      [old_playing_id, new_playing_id] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {:noreply, touch_stream_entries(socket, ids_to_touch)}
  end

  def handle_info(
        {:entity_progress_updated, entity_id, summary, _resume_target, _child_targets_delta,
         _last_activity_at},
        socket
      ) do
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary)
    {:noreply, socket |> assign(entries: entries) |> touch_stream_entries([entity_id])}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/library">
      <div class="space-y-4">
        <h1 class="text-2xl font-bold">Library</h1>

        <div class="flex items-center gap-4">
          <.tab_bar active_tab={@active_tab} counts={@counts} />
          <form phx-change="filter" class="ml-auto">
            <input
              id="library-filter"
              type="text"
              name="filter_text"
              value={@filter_text}
              placeholder="Filter by name…"
              phx-debounce="150"
              phx-hook=".SlashFocus"
              class="input input-sm input-bordered w-48"
            />
          </form>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".SlashFocus">
            export default {
              mounted() {
                this.handler = (e) => {
                  if (e.key === "/" && !["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName)) {
                    e.preventDefault()
                    this.el.focus()
                  }
                }
                window.addEventListener("keydown", this.handler)
              },
              destroyed() {
                window.removeEventListener("keydown", this.handler)
              }
            }
          </script>
        </div>

        <div :if={@grid_count == 0} class="text-base-content/60 py-8 text-center">
          No entities found.
        </div>

        <div :if={@grid_count > 0} class="flex gap-4">
          <%!-- Grid area --%>
          <div class="flex-1 min-w-0">
            <div
              id="library-grid"
              phx-update="stream"
              class="grid grid-cols-[repeat(auto-fill,minmax(135px,1fr))] gap-3"
            >
              <.entity_card
                :for={{dom_id, entry} <- @streams.grid}
                id={dom_id}
                entry={entry}
                selected={@selected_id == entry.entity.id}
                playing={playing_entity_id(@playback) == entry.entity.id}
                attention={compute_attention(entry)}
              />
            </div>
          </div>

          <%!-- Drawer area --%>
          <div class="w-[360px] flex-shrink-0 hidden lg:block sticky top-0 self-start max-h-screen overflow-y-auto">
            <.side_drawer
              entry={@selected_entry}
              watch_dirs={@watch_dirs}
              metadata_expanded={@metadata_expanded}
              expanded_episodes={@expanded_episodes}
              playback={@playback}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Tab Bar ---

  defp tab_bar(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-boxed w-fit">
      <button
        :for={{tab, label} <- [{:all, "All"}, {:movies, "Movies"}, {:tv, "TV"}]}
        role="tab"
        class={["tab", @active_tab == tab && "tab-active"]}
        phx-click="switch_tab"
        phx-value-tab={tab}
      >
        {label}
        <span class="badge badge-sm ml-1">{@counts[tab] || 0}</span>
      </button>
    </div>
    """
  end

  # --- Entity Card (compact poster card) ---

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :selected, :boolean, required: true
  attr :playing, :boolean, required: true
  attr :attention, :atom, default: nil

  defp entity_card(assigns) do
    assigns = assign(assigns, poster: poster_url(assigns.entry.entity))

    ~H"""
    <div
      id={@id}
      phx-click="select_entity"
      phx-value-id={@entry.entity.id}
      class={[
        "card glass-surface cursor-pointer overflow-hidden transition-all",
        "hover:ring-1 hover:ring-base-content/20",
        @selected && "ring-2 ring-primary",
        @playing && "ring-2 ring-primary",
        @attention == :error && "border-l-3 border-l-error"
      ]}
    >
      <%!-- Poster --%>
      <div class="aspect-[2/3] glass-inset relative">
        <img
          :if={@poster}
          src={@poster}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div
          :if={!@poster}
          class="w-full h-full flex items-center justify-center"
        >
          <.icon name="hero-film" class="size-8 text-base-content/20" />
        </div>

        <%!-- Now-playing pulse --%>
        <div
          :if={@playing}
          class="absolute top-2 right-2 size-3 rounded-full bg-primary animate-pulse"
        />

        <%!-- Attention dot --%>
        <div
          :if={@attention == :error && !@playing}
          class="absolute top-2 right-2 size-2.5 rounded-full bg-error"
        />
      </div>

      <%!-- Card footer --%>
      <div class="p-2">
        <div class="text-sm font-medium leading-tight line-clamp-2">
          {@entry.entity.name || "Untitled"}
        </div>
        <div class="mt-0.5 text-xs text-base-content/50">
          {format_type(@entry.entity.type)}<span :if={@entry.entity.date_published}> · {extract_year(@entry.entity.date_published)}</span>
        </div>
        <.card_progress progress={@entry.progress} type={@entry.entity.type} />
      </div>
    </div>
    """
  end

  # --- Card Progress (compact text for grid cards) ---

  defp card_progress(%{progress: nil} = assigns) do
    ~H"""
    """
  end

  defp card_progress(%{type: :tv_series, progress: progress} = assigns) do
    assigns = assign(assigns, progress: progress)

    ~H"""
    <span
      :if={@progress.episodes_completed == @progress.episodes_total && @progress.episodes_total > 0}
      class="text-xs text-success"
    >
      Watched
    </span>
    <span
      :if={@progress.episodes_completed < @progress.episodes_total || @progress.episodes_total == 0}
      class="text-xs text-info"
    >
      {@progress.episodes_completed}/{@progress.episodes_total} eps
    </span>
    """
  end

  defp card_progress(%{progress: progress} = assigns) do
    completed = progress.episodes_completed > 0
    assigns = assign(assigns, progress: progress, completed: completed)

    ~H"""
    <span :if={@completed} class="text-xs text-success">Watched</span>
    <span
      :if={!@completed && @progress.episode_duration_seconds > 0}
      class="text-xs text-info"
    >
      {format_seconds(@progress.episode_position_seconds)}
    </span>
    """
  end

  # --- Side Drawer ---

  attr :entry, :map, default: nil
  attr :watch_dirs, :list, required: true
  attr :metadata_expanded, :boolean, required: true
  attr :expanded_episodes, :any, required: true
  attr :playback, :map, required: true

  defp side_drawer(%{entry: nil} = assigns) do
    ~H"""
    <div class="card glass-surface h-full min-h-[400px] flex items-center justify-center">
      <div class="text-center text-base-content/40">
        <.icon name="hero-cursor-arrow-rays" class="size-8 mx-auto mb-2" />
        <p class="text-sm">Select an item to view details</p>
      </div>
    </div>
    """
  end

  defp side_drawer(assigns) do
    entity = assigns.entry.entity
    episodes = if entity.type == :tv_series, do: EpisodeList.list_available(entity), else: []

    progress_by_key =
      if entity.type == :tv_series,
        do: EpisodeList.index_progress_by_key(assigns.entry.progress_records),
        else: %{}

    assigns =
      assign(assigns,
        entity: entity,
        episodes: episodes,
        progress_by_key: progress_by_key
      )

    ~H"""
    <div class="card glass-surface">
      <.drawer_header entity={@entity} progress={@entry.progress} />
      <div class="p-4 space-y-4">
        <.drawer_actions entity={@entity} />
        <.drawer_details entity={@entity} />
        <.drawer_status entity={@entity} />
        <.drawer_content_list
          entity={@entity}
          watch_dirs={@watch_dirs}
          expanded_episodes={@expanded_episodes}
          progress_by_key={@progress_by_key}
        />
        <.drawer_more_details
          entity={@entity}
          watch_dirs={@watch_dirs}
          expanded={@metadata_expanded}
        />
      </div>
    </div>
    """
  end

  # --- Drawer Header ---

  defp drawer_header(assigns) do
    backdrop = image_url(assigns.entity, "backdrop")
    background = backdrop || poster_url(assigns.entity)
    logo = image_url(assigns.entity, "logo")
    assigns = assign(assigns, background: background, logo: logo)

    ~H"""
    <div class="relative">
      <%!-- Backdrop / poster banner --%>
      <div class="aspect-[16/9] glass-inset overflow-hidden relative">
        <img
          :if={@background}
          src={@background}
          class="w-full h-full object-cover"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>
        <%!-- Logo overlay --%>
        <div :if={@logo} class="absolute inset-0 flex items-center justify-center p-6">
          <img
            src={@logo}
            class="max-h-full max-w-[70%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)]"
          />
        </div>
      </div>

      <%!-- Title overlay --%>
      <div class="p-4 pb-2">
        <h2 class="text-lg font-bold leading-snug">{@entity.name}</h2>
        <div class="flex items-center gap-2 mt-1 text-sm text-base-content/60">
          <span class="badge badge-outline badge-sm">{format_type(@entity.type)}</span>
          <span :if={@entity.date_published}>{extract_year(@entity.date_published)}</span>
          <span :if={@entity.type == :tv_series && is_list(@entity.seasons)}>
            <% season_count = length(@entity.seasons) %>
            {season_count} season{if season_count != 1, do: "s"}
          </span>
          <span :if={@entity.type == :movie_series && is_list(@entity.movies)}>
            <% movie_count = length(@entity.movies) %>
            {movie_count} movie{if movie_count != 1, do: "s"}
          </span>
        </div>
        <div class="mt-1">
          <.drawer_progress progress={@progress} type={@entity.type} />
        </div>
      </div>
    </div>
    """
  end

  # --- Drawer Progress ---

  defp drawer_progress(%{progress: nil} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/40">Unwatched</span>
    """
  end

  defp drawer_progress(%{type: :tv_series, progress: progress} = assigns) do
    assigns = assign(assigns, progress: progress)

    ~H"""
    <span
      :if={@progress.episodes_completed == @progress.episodes_total && @progress.episodes_total > 0}
      class="text-sm text-success"
    >
      Watched
    </span>
    <span
      :if={@progress.episodes_completed < @progress.episodes_total || @progress.episodes_total == 0}
      class="text-sm text-info"
    >
      {@progress.episodes_completed}/{@progress.episodes_total} episodes
    </span>
    """
  end

  defp drawer_progress(%{progress: progress} = assigns) do
    completed = progress.episodes_completed > 0
    assigns = assign(assigns, progress: progress, completed: completed)

    ~H"""
    <span :if={@completed} class="text-sm text-success">Watched</span>
    <span :if={!@completed && @progress.episode_duration_seconds > 0} class="text-sm text-info">
      {format_seconds(@progress.episode_position_seconds)} / {format_seconds(
        @progress.episode_duration_seconds
      )}
    </span>
    <span
      :if={!@completed && @progress.episode_duration_seconds == 0}
      class="text-sm text-base-content/40"
    >
      Unwatched
    </span>
    """
  end

  # --- Drawer Actions ---

  defp drawer_actions(assigns) do
    ~H"""
    <div class="flex gap-2">
      <button
        phx-click="play"
        phx-value-id={@entity.id}
        class="btn btn-soft btn-primary btn-sm flex-1"
      >
        <.icon name="hero-play-mini" class="size-4" /> Resume
      </button>
      <button class="btn btn-ghost btn-sm" disabled title="Re-match coming soon">
        <.icon name="hero-arrow-path-mini" class="size-4" /> Re-match
      </button>
    </div>
    """
  end

  # --- Drawer Status ---

  defp drawer_status(assigns) do
    tmdb_id = find_identifier(assigns.entity, "tmdb")
    has_poster = poster_url(assigns.entity) != nil
    assigns = assign(assigns, tmdb_id: tmdb_id, has_poster: has_poster)

    ~H"""
    <div class="space-y-1 text-sm">
      <div class="flex items-center justify-between">
        <span class="text-base-content/60">TMDB</span>
        <span :if={@tmdb_id} class="text-success">Matched</span>
        <span :if={!@tmdb_id} class="text-warning">Unmatched</span>
      </div>
      <div class="flex items-center justify-between">
        <span class="text-base-content/60">Poster</span>
        <span :if={@has_poster} class="text-success">Available</span>
        <span :if={!@has_poster} class="text-error">Missing</span>
      </div>
    </div>
    """
  end

  # --- Drawer Metadata (collapsible) ---

  attr :entity, :map, required: true

  defp drawer_details(assigns) do
    ~H"""
    <div :if={has_details?(@entity)} class="space-y-2 text-sm">
      <p :if={@entity.description} class="text-base-content/70 line-clamp-4">
        {@entity.description}
      </p>

      <div :if={@entity.genres && @entity.genres != []} class="flex flex-wrap gap-1">
        <span :for={genre <- @entity.genres} class="badge badge-outline badge-sm">
          {genre}
        </span>
      </div>

      <div class="flex items-center gap-4 text-base-content/60">
        <span :if={@entity.content_rating}>{@entity.content_rating}</span>
        <span :if={@entity.director}>{@entity.director}</span>
      </div>
    </div>
    """
  end

  defp has_details?(entity) do
    entity.description || (entity.genres && entity.genres != []) ||
      entity.content_rating || entity.director
  end

  # --- More Details (collapsible) ---

  attr :entity, :map, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true

  defp drawer_more_details(assigns) do
    ~H"""
    <div class="border-t border-base-300/50 pt-3">
      <button
        phx-click="toggle_metadata"
        class="flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content w-full"
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4"
        /> More details
      </button>

      <div :if={@expanded} class="mt-2 space-y-2 text-sm">
        <div :if={@entity.content_url} class="flex items-center justify-between gap-2">
          <span class="text-base-content/60 flex-shrink-0">File</span>
          <span
            title={strip_watch_dir(@entity.content_url, @watch_dirs)}
            class="font-mono text-xs text-base-content/50 truncate-left"
          >
            {strip_watch_dir(@entity.content_url, @watch_dirs)}
          </span>
        </div>

        <div class="pt-1">
          <span class="font-mono text-xs text-base-content/30 select-all">{@entity.id}</span>
        </div>
      </div>
    </div>
    """
  end

  # --- Drawer Content List ---

  attr :entity, :map, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded_episodes, :any, required: true
  attr :progress_by_key, :map, required: true

  defp drawer_content_list(%{entity: %{type: :tv_series}} = assigns) do
    assigns = assign(assigns, seasons: assigns.entity.seasons || [])

    ~H"""
    <div class="border-t border-base-300/50 pt-3 space-y-3">
      <div :for={season <- @seasons}>
        <div class="text-xs font-medium text-base-content/50 uppercase tracking-wide mb-1">
          {season.name || "Season #{season.season_number}"}
        </div>
        <div class="divide-y divide-base-300/30">
          <.episode_row
            :for={episode <- season.episodes}
            episode={episode}
            season_number={season.season_number}
            watch_dirs={@watch_dirs}
            expanded={MapSet.member?(@expanded_episodes, episode.id)}
            progress={Map.get(@progress_by_key, {season.season_number, episode.episode_number})}
          />
        </div>
      </div>
    </div>
    """
  end

  defp drawer_content_list(%{entity: %{type: :movie_series}} = assigns) do
    assigns = assign(assigns, movies: assigns.entity.movies || [])

    ~H"""
    <div class="border-t border-base-300/50 pt-3">
      <div class="divide-y divide-base-300/30">
        <.movie_row
          :for={movie <- @movies}
          movie={movie}
          watch_dirs={@watch_dirs}
          expanded={MapSet.member?(@expanded_episodes, movie.id)}
        />
      </div>
    </div>
    """
  end

  defp drawer_content_list(assigns) do
    ~H"""
    """
  end

  # --- Episode Row ---

  attr :episode, :map, required: true
  attr :season_number, :integer, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true
  attr :progress, :map, default: nil

  defp episode_row(assigns) do
    ~H"""
    <div class="py-1.5">
      <div
        class="flex items-center gap-2 text-sm cursor-pointer hover:bg-base-content/5 rounded px-1 -mx-1"
        phx-click="toggle_episode_detail"
        phx-value-id={@episode.id}
      >
        <span class="w-5 text-right text-base-content/50 flex-shrink-0 font-mono text-xs">
          {@episode.episode_number}
        </span>
        <span class="truncate flex-1">{@episode.name || "—"}</span>
        <.episode_progress_badge progress={@progress} />
        <button
          :if={@episode.content_url}
          phx-click="play"
          phx-value-id={@episode.id}
          class="btn btn-ghost btn-xs flex-shrink-0"
        >
          <.icon name="hero-play-mini" class="size-3" />
        </button>
      </div>

      <div :if={@expanded} class="ml-7 mt-1 space-y-1 text-xs text-base-content/50">
        <p :if={@episode.description} class="line-clamp-3 text-base-content/60">
          {@episode.description}
        </p>
        <div :if={@episode.duration} class="flex items-center gap-1">
          <.icon name="hero-clock-mini" class="size-3" />
          {@episode.duration}
        </div>
        <div :if={@episode.content_url} title={strip_watch_dir(@episode.content_url, @watch_dirs)}>
          <span class="font-mono truncate-left inline-block max-w-full">
            {strip_watch_dir(@episode.content_url, @watch_dirs)}
          </span>
        </div>
        <div class="font-mono text-base-content/30 select-all">{@episode.id}</div>
      </div>
    </div>
    """
  end

  # --- Movie Row (for movie_series) ---

  attr :movie, :map, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true

  defp movie_row(assigns) do
    ~H"""
    <div class="py-1.5">
      <div
        class="flex items-center gap-2 text-sm cursor-pointer hover:bg-base-content/5 rounded px-1 -mx-1"
        phx-click="toggle_episode_detail"
        phx-value-id={@movie.id}
      >
        <span class="truncate flex-1">
          {@movie.name || "—"}
          <span :if={@movie.date_published} class="text-base-content/50 ml-1">
            ({extract_year(@movie.date_published)})
          </span>
        </span>
        <button
          :if={@movie.content_url}
          phx-click="play"
          phx-value-id={@movie.id}
          class="btn btn-ghost btn-xs flex-shrink-0"
        >
          <.icon name="hero-play-mini" class="size-3" />
        </button>
      </div>

      <div :if={@expanded} class="ml-2 mt-1 space-y-1 text-xs text-base-content/50">
        <p :if={@movie.description} class="line-clamp-3 text-base-content/60">
          {@movie.description}
        </p>
        <div :if={@movie.duration} class="flex items-center gap-1">
          <.icon name="hero-clock-mini" class="size-3" />
          {@movie.duration}
        </div>
        <div :if={@movie.content_url} title={strip_watch_dir(@movie.content_url, @watch_dirs)}>
          <span class="font-mono truncate-left inline-block max-w-full">
            {strip_watch_dir(@movie.content_url, @watch_dirs)}
          </span>
        </div>
        <div class="font-mono text-base-content/30 select-all">{@movie.id}</div>
      </div>
    </div>
    """
  end

  # --- Episode Progress Badge ---

  defp episode_progress_badge(%{progress: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">—</span>
    """
  end

  defp episode_progress_badge(%{progress: progress} = assigns) do
    assigns = assign(assigns, progress: progress)

    ~H"""
    <span :if={@progress.completed} class="text-success text-xs">done</span>
    <span
      :if={!@progress.completed && @progress.position_seconds > 0}
      class="text-info text-xs"
    >
      {format_seconds(@progress.position_seconds)}
    </span>
    <span
      :if={!@progress.completed && (@progress.position_seconds || 0) == 0}
      class="text-base-content/40 text-xs"
    >
      —
    </span>
    """
  end

  # --- Derived Assigns ---

  defp reset_stream(socket) do
    filtered = compute_filtered(socket)

    socket
    |> stream(:grid, filtered, reset: true, dom_id: &"entity-#{&1.entity.id}")
    |> assign(grid_count: length(filtered))
    |> assign_selected_entry()
  end

  defp touch_stream_entries(socket, entity_ids) do
    filtered_ids = compute_filtered(socket) |> MapSet.new(& &1.entity.id)

    Enum.reduce(entity_ids, socket, fn id, sock ->
      entry = Enum.find(sock.assigns.entries, &(&1.entity.id == id))

      cond do
        entry == nil ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")

        MapSet.member?(filtered_ids, id) ->
          stream_insert(sock, :grid, entry)

        true ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")
      end
    end)
    |> assign_selected_entry()
  end

  defp assign_selected_entry(socket) do
    selected_entry =
      if socket.assigns.selected_id do
        Enum.find(socket.assigns.entries, &(&1.entity.id == socket.assigns.selected_id))
      end

    assign(socket, selected_entry: selected_entry)
  end

  defp compute_filtered(socket) do
    socket.assigns.entries
    |> filtered_entries(socket.assigns.active_tab)
    |> text_filtered_entries(socket.assigns.filter_text)
  end

  # --- Helpers ---

  defp compute_attention(%{entity: entity}) do
    if poster_url(entity) == nil, do: :error
  end

  defp find_identifier(entity, property_id) do
    Enum.find(entity.identifiers || [], fn id -> id.property_id == property_id end)
  end

  defp poster_url(entity), do: image_url(entity, "poster")

  defp image_url(entity, role) do
    image = Enum.find(entity.images || [], &(&1.role == role))

    cond do
      image && image.content_url ->
        "/media-images/#{image.content_url}"

      image && image.url ->
        image.url

      true ->
        nil
    end
  end

  defp filtered_entries(entries, :all), do: entries

  defp filtered_entries(entries, :movies) do
    Enum.filter(entries, fn %{entity: entity} ->
      entity.type in [:movie, :movie_series, :video_object]
    end)
  end

  defp filtered_entries(entries, :tv) do
    Enum.filter(entries, fn %{entity: entity} -> entity.type == :tv_series end)
  end

  defp text_filtered_entries(entries, ""), do: entries

  defp text_filtered_entries(entries, text) do
    needle = String.downcase(text)

    Enum.filter(entries, fn %{entity: entity} ->
      name_matches?(entity.name, needle) ||
        nested_matches?(entity, needle)
    end)
  end

  defp name_matches?(nil, _needle), do: false
  defp name_matches?(name, needle), do: String.contains?(String.downcase(name), needle)

  defp nested_matches?(%{type: :tv_series, seasons: seasons}, needle) when is_list(seasons) do
    Enum.any?(seasons, fn season ->
      Enum.any?(season.episodes || [], fn episode ->
        name_matches?(episode.name, needle)
      end)
    end)
  end

  defp nested_matches?(%{type: :movie_series, movies: movies}, needle) when is_list(movies) do
    Enum.any?(movies, fn movie -> name_matches?(movie.name, needle) end)
  end

  defp nested_matches?(_entity, _needle), do: false

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

  defp playing_entity_id(%{now_playing: %{entity_id: id}}), do: id
  defp playing_entity_id(_), do: nil

  defp update_entry_progress(entries, entity_id, summary) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry ->
        %{entry | progress: summary}

      entry ->
        entry
    end)
  end

  defp strip_watch_dir(nil, _watch_dirs), do: "—"

  defp strip_watch_dir(path, watch_dirs) do
    case Enum.find(watch_dirs, &String.starts_with?(path, &1)) do
      nil -> Path.basename(path)
      dir -> String.trim_leading(path, dir) |> String.trim_leading("/")
    end
  end

  defp format_type(:movie), do: "Movie"
  defp format_type(:movie_series), do: "Movie Series"
  defp format_type(:tv_series), do: "TV Series"
  defp format_type(:video_object), do: "Video"
  defp format_type(type), do: type |> to_string() |> String.capitalize()

  defp extract_year(date_string), do: DateUtil.extract_year(date_string) || ""
end
