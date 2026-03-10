defmodule MediaCentaurWeb.Components.DetailPanel do
  @moduledoc """
  Shared entity detail content component, rendered inside ModalShell.

  Displays hero (21:9 backdrop), identity (logo/title), metadata, description,
  playback actions (Play/Resume button + progress bar), and type-specific content
  lists (episodes for TV, movies for movie series).
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers

  alias MediaCentaur.{DateUtil, Playback.EpisodeList}

  # --- Public API ---

  @doc """
  Computes which seasons should be auto-expanded based on current progress.

  Returns a MapSet of season numbers. If there's a current episode, expands that season.
  Otherwise expands Season 1 (if it exists).
  """
  def auto_expand_season(%{type: :tv_series, seasons: seasons}, %{
        current_episode: %{season: season_number}
      })
      when is_list(seasons) do
    if Enum.any?(seasons, &(&1.season_number == season_number)) do
      MapSet.new([season_number])
    else
      default_expand_season(seasons)
    end
  end

  def auto_expand_season(%{type: :tv_series, seasons: seasons}, _progress)
      when is_list(seasons) do
    default_expand_season(seasons)
  end

  def auto_expand_season(_entity, _progress), do: MapSet.new()

  defp default_expand_season(seasons) do
    if Enum.any?(seasons, &(&1.season_number == 1)) do
      MapSet.new([1])
    else
      case seasons do
        [first | _] -> MapSet.new([first.season_number])
        [] -> MapSet.new()
      end
    end
  end

  # --- Main Component ---

  attr :entity, :map, required: true
  attr :progress, :map, default: nil
  attr :resume, :map, default: nil
  attr :progress_records, :list, default: []
  attr :watch_dirs, :list, default: []
  attr :expanded_seasons, :any, default: nil
  attr :expanded_episodes, :any, default: nil
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close"

  def detail_panel(assigns) do
    expanded_seasons =
      assigns.expanded_seasons || auto_expand_season(assigns.entity, assigns.progress)

    expanded_episodes = assigns.expanded_episodes || MapSet.new()

    progress_by_key =
      if assigns.entity.type == :tv_series do
        EpisodeList.index_progress_by_key(assigns.progress_records)
      else
        %{}
      end

    assigns =
      assigns
      |> assign(:expanded_seasons, expanded_seasons)
      |> assign(:expanded_episodes, expanded_episodes)
      |> assign(:progress_by_key, progress_by_key)

    ~H"""
    <div class="detail-panel flex flex-col flex-1 min-h-0">
      <div
        class="flex-shrink-0"
        id="detail-header"
        phx-hook="ScrollForward"
        data-target="detail-content"
      >
        <.hero entity={@entity} />
        <div class="p-4 space-y-4">
          <.metadata_row entity={@entity} />
          <.description entity={@entity} />
          <.playback_actions
            entity={@entity}
            progress={@progress}
            resume={@resume}
            on_play={@on_play}
          />
        </div>
      </div>
      <div id="detail-content" class="flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 pb-4">
        <.content_list
          entity={@entity}
          watch_dirs={@watch_dirs}
          expanded_seasons={@expanded_seasons}
          expanded_episodes={@expanded_episodes}
          progress_by_key={@progress_by_key}
          on_play={@on_play}
        />
      </div>
    </div>
    """
  end

  # --- Hero Section (21:9) ---

  defp hero(assigns) do
    backdrop = image_url(assigns.entity, "backdrop")
    background = backdrop || image_url(assigns.entity, "poster")
    logo = image_url(assigns.entity, "logo")

    assigns =
      assigns
      |> assign(:background, background)
      |> assign(:logo, logo)

    ~H"""
    <div class="detail-hero relative overflow-hidden">
      <div class="aspect-[21/9] glass-inset relative">
        <img
          :if={@background}
          src={@background}
          class="w-full h-full object-cover"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-base-100 via-base-100/60 via-30% to-transparent" />
        <div class="absolute bottom-4 left-4 right-4">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-16 max-w-[80%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)]"
          />
          <h2
            :if={!@logo}
            class="text-xl font-bold leading-snug drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          >
            {@entity.name}
          </h2>
        </div>
      </div>
    </div>
    """
  end

  # --- Playback Actions (button + progress bar) ---

  defp playback_actions(assigns) do
    {label, color, target_id} = playback_button_props(assigns)
    percent = overall_progress_percent(assigns.progress, assigns.entity)
    has_progress = percent > 0
    remaining = progress_remaining_text(assigns.progress, assigns.entity)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:color, color)
      |> assign(:target_id, target_id)
      |> assign(:percent, percent)
      |> assign(:has_progress, has_progress)
      |> assign(:remaining, remaining)

    ~H"""
    <div class="space-y-3 pt-1">
      <div :if={@has_progress} class="space-y-1">
        <div class="flex items-center gap-3">
          <div class="flex-1 h-1 rounded-full bg-base-content/10 overflow-hidden">
            <div
              class={"h-full rounded-full #{if @percent >= 100, do: "bg-success", else: "bg-info"}"}
              style={"width: #{@percent}%"}
            />
          </div>
          <span :if={@remaining} class="text-xs text-base-content/40 flex-shrink-0">
            {@remaining}
          </span>
        </div>
      </div>
      <button
        phx-click={@on_play}
        phx-value-id={@target_id}
        class={"btn btn-soft btn-sm btn-#{@color}"}
        data-nav-item
        data-entity-id={@target_id}
        tabindex="0"
      >
        <.icon name="hero-play-mini" class="size-4" /> {@label}
      </button>
    </div>
    """
  end

  defp playback_button_props(%{resume: %{"action" => "resume"} = resume, entity: entity}) do
    {"Resume", "success", resume["targetId"] || entity.id}
  end

  defp playback_button_props(%{resume: %{"action" => "begin"} = resume, entity: entity}) do
    {"Play", "primary", resume["targetId"] || entity.id}
  end

  defp playback_button_props(%{entity: entity}) do
    {"Play", "primary", entity.id}
  end

  defp overall_progress_percent(nil, _entity), do: 0

  defp overall_progress_percent(progress, %{type: type})
       when type in [:tv_series, :movie_series] do
    if progress.episodes_total > 0 do
      min(round(progress.episodes_completed / progress.episodes_total * 100), 100)
    else
      0
    end
  end

  defp overall_progress_percent(progress, _entity) do
    if progress.episode_duration_seconds > 0 do
      min(round(progress.episode_position_seconds / progress.episode_duration_seconds * 100), 100)
    else
      if progress.episodes_completed > 0, do: 100, else: 0
    end
  end

  defp progress_remaining_text(nil, _entity), do: nil

  defp progress_remaining_text(progress, %{type: :tv_series}) do
    remaining = progress.episodes_total - progress.episodes_completed

    cond do
      remaining <= 0 -> "Watched"
      remaining == 1 -> "1 episode left"
      true -> "#{remaining} episodes left"
    end
  end

  defp progress_remaining_text(progress, %{type: :movie_series}) do
    remaining = progress.episodes_total - progress.episodes_completed

    cond do
      remaining <= 0 -> "Watched"
      remaining == 1 -> "1 movie left"
      true -> "#{remaining} movies left"
    end
  end

  defp progress_remaining_text(progress, _entity) do
    cond do
      progress.episodes_completed > 0 ->
        "Watched"

      progress.episode_duration_seconds > 0 && progress.episode_position_seconds > 0 ->
        remaining_seconds = progress.episode_duration_seconds - progress.episode_position_seconds
        "#{format_duration_human(remaining_seconds)} remaining"

      true ->
        nil
    end
  end

  # --- Metadata Row ---

  defp metadata_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm text-base-content/60">
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
      <span :if={@entity.content_rating}>{@entity.content_rating}</span>
    </div>
    """
  end

  # --- Description ---

  defp description(%{entity: %{description: nil}} = assigns) do
    ~H"""
    """
  end

  defp description(assigns) do
    ~H"""
    <p class="text-sm text-base-content/70 line-clamp-4">{@entity.description}</p>
    """
  end

  # --- Content List (type-dependent) ---

  defp content_list(%{entity: %{type: :tv_series}} = assigns) do
    seasons = assigns.entity.seasons || []
    assigns = assign(assigns, :seasons, seasons)

    ~H"""
    <div :if={@seasons != []} class="pt-3 space-y-3">
      <.season_section
        :for={season <- @seasons}
        season={season}
        watch_dirs={@watch_dirs}
        expanded={MapSet.member?(@expanded_seasons, season.season_number)}
        expanded_episodes={@expanded_episodes}
        progress_by_key={@progress_by_key}
        on_play={@on_play}
      />
      <.extras_section entity={@entity} on_play={@on_play} />
    </div>
    """
  end

  defp content_list(%{entity: %{type: :movie_series}} = assigns) do
    movies = assigns.entity.movies || []
    assigns = assign(assigns, :movies, movies)

    ~H"""
    <div class="pt-3">
      <div :if={@movies != []}>
        <.movie_row
          :for={movie <- @movies}
          movie={movie}
          watch_dirs={@watch_dirs}
          expanded={MapSet.member?(@expanded_episodes, movie.id)}
          on_play={@on_play}
        />
      </div>
      <.extras_section entity={@entity} on_play={@on_play} />
    </div>
    """
  end

  defp content_list(assigns) do
    ~H"""
    <.extras_section entity={@entity} on_play={@on_play} />
    """
  end

  # --- Season Section ---

  attr :season, :map, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true
  attr :expanded_episodes, :any, required: true
  attr :progress_by_key, :map, required: true
  attr :on_play, :string, required: true

  defp season_section(assigns) do
    episodes = assigns.season.episodes || []
    watched_count = count_watched_episodes(assigns.season, assigns.progress_by_key)
    total_count = length(episodes)

    assigns =
      assigns
      |> assign(:episodes, episodes)
      |> assign(:watched_count, watched_count)
      |> assign(:total_count, total_count)

    ~H"""
    <div>
      <button
        phx-click="toggle_season"
        phx-value-season={@season.season_number}
        class="flex items-center gap-2 w-full text-sm font-medium text-base-content/70 hover:text-base-content"
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4"
        />
        <span>{@season.name || "Season #{@season.season_number}"}</span>
        <span class="text-xs text-base-content/40">
          {season_progress_label(@watched_count, @total_count)}
        </span>
      </button>

      <div :if={@expanded} class="mt-1">
        <.episode_row
          :for={episode <- @episodes}
          episode={episode}
          season_number={@season.season_number}
          watch_dirs={@watch_dirs}
          expanded={MapSet.member?(@expanded_episodes, episode.id)}
          progress={Map.get(@progress_by_key, {@season.season_number, episode.episode_number})}
          on_play={@on_play}
        />
        <.season_extras extras={@season.extras} on_play={@on_play} />
      </div>
    </div>
    """
  end

  # --- Episode Row ---

  attr :episode, :map, required: true
  attr :season_number, :integer, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true
  attr :progress, :map, default: nil
  attr :on_play, :string, required: true

  defp episode_row(assigns) do
    state = episode_state(assigns.progress)
    assigns = assign(assigns, :state, state)

    thumbnail = image_url(assigns.episode, "thumb")
    assigns = assign(assigns, :thumbnail, thumbnail)

    ~H"""
    <div class={["py-1 pr-3", episode_row_class(@state)]} data-role="episode-row">
      <div
        class="flex items-start gap-3 text-sm cursor-pointer hover:bg-base-content/5 rounded-lg p-2 -mx-2"
        phx-click="toggle_episode_detail"
        phx-value-id={@episode.id}
        data-nav-item
        tabindex="0"
      >
        <div class="w-20 flex-shrink-0">
          <img
            :if={@thumbnail}
            src={@thumbnail}
            class="w-20 aspect-video rounded object-cover"
          />
          <div :if={!@thumbnail} class="w-20 aspect-video rounded bg-base-300/30" />
        </div>
        <div class="flex-1 min-w-0">
          <span class="truncate block text-base-content/90">
            <span class="text-base-content/50 font-mono text-xs">{@episode.episode_number}.</span>
            {@episode.name || "—"}
          </span>
          <p :if={@episode.description} class="line-clamp-2 text-xs text-base-content/50">
            {@episode.description}
          </p>
        </div>
        <.episode_right_info
          state={@state}
          progress={@progress}
          duration={@episode.duration}
        />
      </div>
      <div
        :if={@state == :current}
        class="ml-22 mt-0.5 h-0.5 rounded-full bg-base-content/10 overflow-hidden"
      >
        <div
          class="h-full bg-info rounded-full"
          style={"width: #{progress_percent(@progress)}%"}
        />
      </div>

      <div :if={@expanded} class="ml-22 mt-1 space-y-1 text-xs text-base-content/50">
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

  defp episode_state(nil), do: :unwatched

  defp episode_state(progress) do
    cond do
      progress.completed -> :watched
      (progress.position_seconds || 0.0) > 0.0 -> :current
      true -> :unwatched
    end
  end

  defp episode_row_class(:watched), do: "opacity-60"
  defp episode_row_class(:current), do: "bg-info/5 rounded"
  defp episode_row_class(:unwatched), do: ""

  defp episode_right_info(%{state: :watched} = assigns) do
    ~H"""
    <span class="text-success text-xs flex-shrink-0">
      <.icon name="hero-check-mini" class="size-3.5" />
    </span>
    """
  end

  defp episode_right_info(%{state: :current, progress: progress} = assigns) do
    remaining = max(progress.duration_seconds - progress.position_seconds, 0)
    assigns = assign(assigns, :remaining, remaining)

    ~H"""
    <span class="text-info text-xs flex-shrink-0">
      {format_duration_human(@remaining)} remaining
    </span>
    """
  end

  defp episode_right_info(%{duration: duration} = assigns) when is_binary(duration) do
    ~H"""
    <span class="text-base-content/40 text-xs flex-shrink-0">
      {format_iso_duration(@duration)}
    </span>
    """
  end

  defp episode_right_info(assigns) do
    ~H"""
    """
  end

  defp progress_percent(%{position_seconds: pos, duration_seconds: dur})
       when is_number(pos) and is_number(dur) and dur > 0 do
    min(round(pos / dur * 100), 100)
  end

  defp progress_percent(_), do: 0

  # --- Movie Row ---

  attr :movie, :map, required: true
  attr :watch_dirs, :list, required: true
  attr :expanded, :boolean, required: true
  attr :on_play, :string, required: true

  defp movie_row(assigns) do
    thumbnail = image_url(assigns.movie, "poster")
    assigns = assign(assigns, :thumbnail, thumbnail)

    ~H"""
    <div class="py-1 pr-3" data-role="movie-row">
      <div
        class="flex items-start gap-3 text-sm cursor-pointer hover:bg-base-content/5 rounded-lg p-2 -mx-2"
        phx-click="toggle_episode_detail"
        phx-value-id={@movie.id}
        data-nav-item
        tabindex="0"
      >
        <div class="w-12 flex-shrink-0">
          <img
            :if={@thumbnail}
            src={@thumbnail}
            class="w-12 aspect-[2/3] rounded object-cover"
          />
          <div :if={!@thumbnail} class="w-12 aspect-[2/3] rounded bg-base-300/30" />
        </div>
        <div class="flex-1 min-w-0">
          <span class="truncate block text-base-content/90">
            {@movie.name || "—"}
            <span :if={@movie.date_published} class="text-base-content/50 ml-1">
              ({extract_year(@movie.date_published)})
            </span>
          </span>
          <p :if={@movie.description} class="line-clamp-2 text-xs text-base-content/50">
            {@movie.description}
          </p>
        </div>
        <button
          :if={@movie.content_url}
          phx-click={@on_play}
          phx-value-id={@movie.id}
          class="btn btn-ghost btn-xs flex-shrink-0"
        >
          <.icon name="hero-play-mini" class="size-3" />
        </button>
      </div>

      <div :if={@expanded} class="ml-16 mt-1 space-y-1 text-xs text-base-content/50">
        <div :if={@movie.duration} class="flex items-center gap-1">
          <.icon name="hero-clock-mini" class="size-3" />
          {format_iso_duration(@movie.duration)}
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

  # --- Extra Row ---

  attr :extra, :map, required: true
  attr :on_play, :string, required: true

  defp extra_row(assigns) do
    ~H"""
    <div class="py-0.5 pr-3" data-role="extra-row">
      <div
        class="flex items-center gap-2 text-sm cursor-pointer hover:bg-base-content/5 rounded-lg p-2 -mx-2"
        phx-click={@on_play}
        phx-value-id={@extra.id}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-film-mini" class="size-4 text-base-content/40 flex-shrink-0" />
        <span class="flex-1 min-w-0 truncate text-base-content/70">{@extra.name || "—"}</span>
      </div>
    </div>
    """
  end

  defp extras_section(assigns) do
    extras = entity_extras(assigns.entity)
    assigns = assign(assigns, :extras, extras)

    ~H"""
    <div :if={@extras != []} class="pt-3">
      <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Extras</span>
      <.extra_row :for={extra <- @extras} extra={extra} on_play={@on_play} />
    </div>
    """
  end

  defp entity_extras(%{extras: extras}) when is_list(extras) do
    Enum.filter(extras, &is_nil(&1.season_id))
  end

  defp entity_extras(_), do: []

  defp season_extras(%{extras: nil} = assigns) do
    ~H"""
    """
  end

  defp season_extras(%{extras: []} = assigns) do
    ~H"""
    """
  end

  defp season_extras(assigns) do
    ~H"""
    <div class="pt-2">
      <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Extras</span>
      <.extra_row :for={extra <- @extras} extra={extra} on_play={@on_play} />
    </div>
    """
  end

  # --- More Details (collapsible) ---

  # --- Helpers ---

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

  defp format_duration_human(seconds) when is_number(seconds) and seconds >= 0 do
    hours = div(trunc(seconds), 3600)
    minutes = div(rem(trunc(seconds), 3600), 60)

    cond do
      hours > 0 && minutes > 0 -> "#{hours} hr #{minutes} mins"
      hours > 0 -> "#{hours} hr"
      minutes > 0 -> "#{minutes} mins"
      true -> "<1 min"
    end
  end

  defp count_watched_episodes(season, progress_by_key) do
    (season.episodes || [])
    |> Enum.count(fn episode ->
      case Map.get(progress_by_key, {season.season_number, episode.episode_number}) do
        %{completed: true} -> true
        _ -> false
      end
    end)
  end

  defp season_progress_label(watched, total) when watched == total and total > 0, do: "watched"
  defp season_progress_label(watched, total), do: "#{total - watched} remaining"
end
