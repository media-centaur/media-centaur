defmodule MediaManagerWeb.LibraryLive do
  use MediaManagerWeb, :live_view

  alias MediaManager.{DateUtil, LibraryBrowser}
  alias MediaManager.Playback.EpisodeList

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "playback:events")

        entries = LibraryBrowser.fetch_entities()

        socket
        |> assign(entries: entries)
        |> assign(counts: tab_counts(entries))
        |> assign(watch_dirs: MediaManager.Config.get(:watch_dirs) || [])
        |> assign(playback: MediaManager.Playback.Manager.current_state())
      else
        socket
        |> assign(entries: [])
        |> assign(counts: %{all: 0, movies: 0, tv: 0})
        |> assign(watch_dirs: [])
        |> assign(playback: %{state: :idle, now_playing: nil})
      end

    {:ok, assign(socket, active_tab: :all, expanded: MapSet.new(), reload_timer: nil)}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
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

  def handle_event("play", %{"entity-id" => entity_id}, socket) do
    LibraryBrowser.play_entity(entity_id)
    {:noreply, socket}
  end

  def handle_event("play_episode", params, socket) do
    %{"entity-id" => entity_id, "season" => season, "episode" => episode} = params
    LibraryBrowser.play_episode(entity_id, String.to_integer(season), String.to_integer(episode))
    {:noreply, socket}
  end

  def handle_event("play_movie", %{"entity-id" => entity_id, "movie-id" => movie_id}, socket) do
    LibraryBrowser.play_movie(entity_id, movie_id)
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

  def handle_info({:entity_progress_updated, entity_id, summary, progress_records}, socket) do
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
    filtered = filtered_entries(assigns.entries, assigns.active_tab)
    assigns = assign(assigns, filtered: filtered)

    ~H"""
    <Layouts.app flash={@flash} current_path="/library">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Library</h1>

        <.tab_bar active_tab={@active_tab} counts={@counts} />

        <div :if={@filtered == []} class="text-base-content/60 py-8 text-center">
          No entities found.
        </div>

        <div class="divide-y divide-base-200 rounded-lg overflow-hidden">
          <.entity_card
            :for={{entry, index} <- Enum.with_index(@filtered)}
            entry={entry}
            index={index}
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
  attr :index, :integer, required: true
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
    <div class={[
      "p-4",
      rem(@index, 2) == 0 && "bg-base-200/50",
      @playing && "ring-2 ring-primary ring-inset"
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <button phx-click="toggle_expand" phx-value-id={@entity.id} class="btn btn-ghost btn-xs">
            <.icon
              name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
              class="size-4"
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
          <button phx-click="play" phx-value-entity-id={@entity.id} class="btn btn-primary btn-sm">
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      </div>

      <div :if={@expanded} class="mt-4 space-y-4">
        <div :for={season <- @seasons}>
          <h3 class="text-sm font-semibold mb-2">
            {season.name || "Season #{season.season_number}"}
          </h3>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra">
              <thead>
                <tr>
                  <th class="w-12">#</th>
                  <th>Name</th>
                  <th>File</th>
                  <th>Progress</th>
                  <th class="w-16"></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={episode <- season.episodes}>
                  <td>{episode.episode_number}</td>
                  <td>{episode.name || "—"}</td>
                  <td class="font-mono text-xs max-w-xs truncate">
                    {strip_watch_dir(episode.content_url, @watch_dirs)}
                  </td>
                  <td>
                    <.episode_progress_badge progress={
                      Map.get(@progress_by_key, {season.season_number, episode.episode_number})
                    } />
                  </td>
                  <td>
                    <button
                      :if={episode.content_url}
                      phx-click="play_episode"
                      phx-value-entity-id={@entity.id}
                      phx-value-season={season.season_number}
                      phx-value-episode={episode.episode_number}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-play-mini" class="size-3" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
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
    <div class={[
      "p-4",
      rem(@index, 2) == 0 && "bg-base-200/50",
      @playing && "ring-2 ring-primary ring-inset"
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <button phx-click="toggle_expand" phx-value-id={@entity.id} class="btn btn-ghost btn-xs">
            <.icon
              name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
              class="size-4"
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
          <button phx-click="play" phx-value-entity-id={@entity.id} class="btn btn-primary btn-sm">
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      </div>

      <div :if={@expanded} class="mt-4">
        <div class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Name</th>
                <th>Year</th>
                <th>File</th>
                <th class="w-16"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={movie <- @movies}>
                <td>{movie.name || "—"}</td>
                <td>{extract_year(movie.date_published)}</td>
                <td class="font-mono text-xs max-w-xs truncate">
                  {strip_watch_dir(movie.content_url, @watch_dirs)}
                </td>
                <td>
                  <button
                    :if={movie.content_url}
                    phx-click="play_movie"
                    phx-value-entity-id={@entity.id}
                    phx-value-movie-id={movie.id}
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-play-mini" class="size-3" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
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
    <div class={[
      "p-4",
      rem(@index, 2) == 0 && "bg-base-200/50",
      @playing && "ring-2 ring-primary ring-inset"
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.thumbnail url={@poster} />
          <div>
            <span class="font-semibold">{@entity.name}</span>
            <span class="badge badge-outline badge-sm ml-2">{format_type(@entity.type)}</span>
            <span :if={@entity.date_published} class="text-base-content/60 text-sm ml-2">
              {extract_year(@entity.date_published)}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <span class="font-mono text-xs text-base-content/60 max-w-xs truncate hidden sm:inline">
            {strip_watch_dir(@entity.content_url, @watch_dirs)}
          </span>
          <.progress_badge progress={@entry.progress} type={@entity.type} />
          <button phx-click="play" phx-value-entity-id={@entity.id} class="btn btn-primary btn-sm">
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

  defp format_seconds(nil), do: "0:00"

  defp format_seconds(seconds) when is_number(seconds) do
    total = trunc(seconds)
    hours = div(total, 3600)
    mins = div(rem(total, 3600), 60)
    secs = rem(total, 60)
    pad_secs = String.pad_leading(Integer.to_string(secs), 2, "0")

    if hours > 0 do
      "#{hours}:#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{pad_secs}"
    else
      "#{mins}:#{pad_secs}"
    end
  end

  defp extract_year(date_string), do: DateUtil.extract_year(date_string) || ""
end
