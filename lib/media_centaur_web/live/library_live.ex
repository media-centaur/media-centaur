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
     assign(socket,
       active_tab: :all,
       expanded: MapSet.new(),
       reload_timer: nil,
       filter_text: ""
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  def handle_event("filter", %{"filter_text" => text}, socket) do
    {:noreply, assign(socket, filter_text: text)}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("play", %{"id" => uuid}, socket) do
    LibraryBrowser.play(uuid)
    {:noreply, socket}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:entities_changed, _entity_ids}, socket) do
    if socket.assigns[:reload_timer] do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    timer = Process.send_after(self(), :reload_entities, 500)
    {:noreply, assign(socket, reload_timer: timer)}
  end

  def handle_info(:reload_entities, socket) do
    entries = LibraryBrowser.fetch_entities()

    {:noreply,
     socket
     |> assign(entries: entries)
     |> assign(counts: tab_counts(entries))
     |> assign(reload_timer: nil)}
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    {:noreply, assign(socket, playback: %{state: new_state, now_playing: now_playing})}
  end

  def handle_info(
        {:entity_progress_updated, entity_id, summary, _resume_target, progress_records},
        socket
      ) do
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary, progress_records)
    {:noreply, assign(socket, entries: entries)}
  end

  def handle_info({:playback_progress, progress}, socket) do
    playback = socket.assigns.playback

    now_playing =
      if playback.now_playing do
        playback.now_playing
        |> Map.put(:position_seconds, progress.position_seconds)
        |> Map.put(:duration_seconds, progress.duration_seconds)
      end

    {:noreply, assign(socket, playback: %{playback | now_playing: now_playing})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    filtered =
      assigns.entries
      |> filtered_entries(assigns.active_tab)
      |> text_filtered_entries(assigns.filter_text)

    assigns = assign(assigns, filtered: filtered)

    ~H"""
    <Layouts.app flash={@flash} current_path="/library">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Library</h1>

        <div class="flex items-center gap-4">
          <.tab_bar active_tab={@active_tab} counts={@counts} />
          <form phx-change="filter" class="ml-auto">
            <input
              type="text"
              name="filter_text"
              value={@filter_text}
              placeholder="Filter by name…"
              phx-debounce="150"
              class="input input-sm input-bordered w-48"
            />
          </form>
        </div>

        <div :if={@filtered == []} class="text-base-content/60 py-8 text-center">
          No entities found.
        </div>

        <div class="divide-y divide-base-300/50 rounded-lg overflow-hidden">
          <.entity_card
            :for={entry <- @filtered}
            entry={entry}
            expanded={MapSet.member?(@expanded, entry.entity.id)}
            playing_entity_id={playing_entity_id(@playback)}
            watch_dirs={@watch_dirs}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

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

  attr :entry, :map, required: true
  attr :expanded, :boolean, required: true
  attr :playing_entity_id, :string, default: nil
  attr :watch_dirs, :list, required: true

  defp entity_card(%{entry: %{entity: %{type: :tv_series}}} = assigns) do
    entity = assigns.entry.entity
    episodes = EpisodeList.list_available(entity)
    progress_by_key = EpisodeList.index_progress_by_key(assigns.entry.progress_records)
    playing = assigns.playing_entity_id == entity.id

    assigns =
      assign(assigns,
        entity: entity,
        seasons: entity.seasons || [],
        episodes: episodes,
        progress_by_key: progress_by_key,
        playing: playing,
        poster: poster_url(entity)
      )

    ~H"""
    <div class={["p-4", @playing && "ring-2 ring-primary ring-inset"]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <button
            phx-click="toggle_expand"
            phx-value-id={@entity.id}
            class="w-5 flex-shrink-0 flex items-center justify-center"
          >
            <.icon
              name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
              class="size-4 text-base-content/60"
            />
          </button>
          <.thumbnail url={@poster} />
          <div>
            <span class="font-semibold">{@entity.name}</span>
            <span class="badge badge-outline badge-sm ml-2">TV Series</span>
            <span :if={@entity.date_published} class="text-base-content/60 text-sm ml-2">
              {extract_year(@entity.date_published)}
            </span>
            <span class="text-base-content/60 text-sm ml-2">
              {length(@seasons)} season{if length(@seasons) != 1, do: "s"}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.progress_badge progress={@entry.progress} type={:tv_series} />
          <button phx-click="play" phx-value-id={@entity.id} class="btn btn-primary btn-sm">
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      </div>

      <div :if={@expanded} class="mt-3 ml-5 border-l-2 border-base-300 pl-4 space-y-3">
        <div :for={season <- @seasons}>
          <div class="text-sm font-medium text-base-content/70 mb-1">
            {season.name || "Season #{season.season_number}"}
          </div>
          <div class="divide-y divide-base-300/50">
            <div :for={episode <- season.episodes} class="flex items-center gap-3 py-1.5 text-sm">
              <span class="w-6 text-right text-base-content/50 flex-shrink-0 font-mono text-xs">
                {episode.episode_number}
              </span>
              <span class="truncate flex-1">{episode.name || "—"}</span>
              <span class="font-mono text-xs text-base-content/40 max-w-xs truncate hidden sm:inline flex-shrink-0">
                {strip_watch_dir(episode.content_url, @watch_dirs)}
              </span>
              <.episode_progress_badge progress={
                Map.get(@progress_by_key, {season.season_number, episode.episode_number})
              } />
              <button
                :if={episode.content_url}
                phx-click="play"
                phx-value-id={episode.id}
                class="btn btn-ghost btn-xs flex-shrink-0"
              >
                <.icon name="hero-play-mini" class="size-3" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp entity_card(%{entry: %{entity: %{type: :movie_series}}} = assigns) do
    entity = assigns.entry.entity
    playing = assigns.playing_entity_id == entity.id

    assigns =
      assign(assigns,
        entity: entity,
        movies: entity.movies || [],
        playing: playing,
        poster: poster_url(entity)
      )

    ~H"""
    <div class={["p-4", @playing && "ring-2 ring-primary ring-inset"]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <button
            phx-click="toggle_expand"
            phx-value-id={@entity.id}
            class="w-5 flex-shrink-0 flex items-center justify-center"
          >
            <.icon
              name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
              class="size-4 text-base-content/60"
            />
          </button>
          <.thumbnail url={@poster} />
          <div>
            <span class="font-semibold">{@entity.name}</span>
            <span class="badge badge-outline badge-sm ml-2">Movie Series</span>
            <span :if={@entity.date_published} class="text-base-content/60 text-sm ml-2">
              {extract_year(@entity.date_published)}
            </span>
            <span class="text-base-content/60 text-sm ml-2">
              {length(@movies)} movie{if length(@movies) != 1, do: "s"}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.progress_badge progress={@entry.progress} type={:movie_series} />
          <button phx-click="play" phx-value-id={@entity.id} class="btn btn-primary btn-sm">
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      </div>

      <div :if={@expanded} class="mt-3 ml-5 border-l-2 border-base-300 pl-4">
        <div class="divide-y divide-base-300/50">
          <div :for={movie <- @movies} class="flex items-center gap-3 py-1.5 text-sm">
            <span class="truncate flex-1">
              {movie.name || "—"}
              <span :if={movie.date_published} class="text-base-content/50 ml-1">
                ({extract_year(movie.date_published)})
              </span>
            </span>
            <span class="font-mono text-xs text-base-content/40 max-w-xs truncate hidden sm:inline flex-shrink-0">
              {strip_watch_dir(movie.content_url, @watch_dirs)}
            </span>
            <button
              :if={movie.content_url}
              phx-click="play"
              phx-value-id={movie.id}
              class="btn btn-ghost btn-xs flex-shrink-0"
            >
              <.icon name="hero-play-mini" class="size-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Movie / VideoObject — single-row card
  defp entity_card(assigns) do
    entity = assigns.entry.entity
    playing = assigns.playing_entity_id == entity.id

    assigns = assign(assigns, entity: entity, playing: playing, poster: poster_url(entity))

    ~H"""
    <div class={["p-4", @playing && "ring-2 ring-primary ring-inset"]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class="w-5 flex-shrink-0"></div>
          <.thumbnail url={@poster} />
          <div>
            <div>
              <span class="font-semibold">{@entity.name}</span>
              <span class="badge badge-outline badge-sm ml-2">{format_type(@entity.type)}</span>
              <span :if={@entity.date_published} class="text-base-content/60 text-sm ml-2">
                {extract_year(@entity.date_published)}
              </span>
            </div>
            <div class="font-mono text-xs text-base-content/40 mt-0.5 max-w-sm truncate hidden sm:block">
              {strip_watch_dir(@entity.content_url, @watch_dirs)}
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.progress_badge progress={@entry.progress} type={@entity.type} />
          <button phx-click="play" phx-value-id={@entity.id} class="btn btn-primary btn-sm">
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp progress_badge(%{progress: nil} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">Unwatched</span>
    """
  end

  defp progress_badge(%{type: :tv_series, progress: progress} = assigns) do
    assigns = assign(assigns, progress: progress)

    ~H"""
    <span
      :if={@progress.episodes_completed == @progress.episodes_total && @progress.episodes_total > 0}
      class="badge badge-success badge-sm"
    >
      Watched
    </span>
    <span
      :if={@progress.episodes_completed < @progress.episodes_total || @progress.episodes_total == 0}
      class="badge badge-info badge-sm"
    >
      {@progress.episodes_completed}/{@progress.episodes_total} episodes
    </span>
    """
  end

  defp progress_badge(%{progress: progress} = assigns) do
    completed = progress.episodes_completed > 0
    assigns = assign(assigns, progress: progress, completed: completed)

    ~H"""
    <span :if={@completed} class="badge badge-success badge-sm">Watched</span>
    <span
      :if={!@completed && @progress.episode_duration_seconds > 0}
      class="badge badge-info badge-sm"
    >
      {format_seconds(@progress.episode_position_seconds)} / {format_seconds(
        @progress.episode_duration_seconds
      )}
    </span>
    <span
      :if={!@completed && @progress.episode_duration_seconds == 0}
      class="badge badge-ghost badge-sm"
    >
      Unwatched
    </span>
    """
  end

  defp episode_progress_badge(%{progress: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">—</span>
    """
  end

  defp episode_progress_badge(%{progress: progress} = assigns) do
    assigns = assign(assigns, progress: progress)

    ~H"""
    <span :if={@progress.completed} class="badge badge-success badge-xs">done</span>
    <span
      :if={!@progress.completed && @progress.position_seconds > 0}
      class="badge badge-info badge-xs"
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

  # --- Thumbnail Component ---

  attr :url, :string, default: nil

  defp thumbnail(assigns) do
    ~H"""
    <div class="w-10 h-15 rounded overflow-hidden bg-base-200 flex-shrink-0 flex items-center justify-center">
      <img :if={@url} src={@url} class="w-full h-full object-cover" loading="lazy" />
      <.icon :if={!@url} name="hero-film" class="size-5 text-base-content/30" />
    </div>
    """
  end

  defp poster_url(entity) do
    poster = Enum.find(entity.images || [], &(&1.role == "poster"))

    cond do
      poster && poster.content_url ->
        "/media-images/#{poster.content_url}"

      poster && poster.url ->
        poster.url

      true ->
        nil
    end
  end

  # --- Helpers ---

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

  defp update_entry_progress(entries, entity_id, summary, progress_records) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry ->
        %{entry | progress: summary, progress_records: progress_records}

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
