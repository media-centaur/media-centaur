defmodule MediaCentarrWeb.Components.DetailPanel do
  @moduledoc """
  Shared entity detail content component, rendered inside ModalShell.

  Displays hero (21:9 backdrop), identity (logo/title), metadata, description,
  playback actions (Play/Resume button + progress bar), and type-specific content
  lists (episodes for TV, movies for movie series).
  """
  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers

  import MediaCentarrWeb.LibraryHelpers,
    only: [format_type: 1, extract_year: 1, format_human_duration: 1]

  alias MediaCentarr.Playback.EpisodeList
  alias MediaCentarr.Playback.MovieList

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

  def auto_expand_season(%{type: :tv_series, seasons: seasons}, _progress) when is_list(seasons) do
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
  attr :expanded_seasons, :any, default: nil
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main
  attr :detail_files, :list, default: []
  attr :delete_confirm, :any, default: nil
  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil

  def detail_panel(assigns) do
    expanded_seasons =
      assigns.expanded_seasons || auto_expand_season(assigns.entity, assigns.progress)

    progress_by_key = EpisodeList.index_progress_by_key(assigns.progress_records)

    resume_episode_key =
      resume_episode_key(assigns.resume) || progress_episode_key(assigns.progress)

    extra_progress_by_id = index_extra_progress(assigns.entity)

    has_scrollable_content =
      assigns.detail_view == :info ||
        assigns.entity.type in [:tv_series, :movie_series] ||
        entity_extras(assigns.entity) != []

    assigns =
      assigns
      |> assign(:expanded_seasons, expanded_seasons)
      |> assign(:progress_by_key, progress_by_key)
      |> assign(:resume_episode_key, resume_episode_key)
      |> assign(:extra_progress_by_id, extra_progress_by_id)
      |> assign(:has_scrollable_content, has_scrollable_content)

    ~H"""
    <div class="detail-panel flex flex-col flex-1 min-h-0">
      <div
        class="flex-shrink-0"
        id="detail-header"
        phx-hook="ScrollForward"
        data-target="detail-content"
      >
        <.hero entity={@entity} tracking_status={@tracking_status} />
        <div class="p-4 space-y-4">
          <.metadata_row entity={@entity} />
          <div class="space-y-1">
            <.description entity={@entity} />
            <.genres entity={@entity} />
          </div>
          <.playback_actions
            entity={@entity}
            progress={@progress}
            resume={@resume}
            on_play={@on_play}
            detail_view={@detail_view}
          />
        </div>
      </div>
      <div
        :if={@has_scrollable_content}
        id="detail-content"
        class="flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 pb-4 bg-base-300/40 thin-scrollbar"
        phx-hook="ScrollToResume"
        data-entity-id={@entity.id}
      >
        <%= if @detail_view == :main do %>
          <.content_list
            entity={@entity}
            expanded_seasons={@expanded_seasons}
            progress_by_key={@progress_by_key}
            resume_episode_key={@resume_episode_key}
            extra_progress_by_id={@extra_progress_by_id}
            on_play={@on_play}
            spoiler_free={@spoiler_free}
          />
        <% else %>
          <.info_view
            entity={@entity}
            files={@detail_files}
            rematch_confirm={@rematch_confirm}
            delete_confirm={@delete_confirm}
          />
        <% end %>
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
        <button
          :if={@tracking_status}
          phx-click="toggle_tracking"
          class="absolute top-3 right-3 btn btn-circle btn-ghost btn-sm opacity-60 hover:opacity-100 transition-opacity"
          title={tracking_title(@tracking_status)}
        >
          <.icon
            name={tracking_icon(@tracking_status)}
            class={"size-5 #{tracking_color(@tracking_status)}"}
          />
        </button>
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

  # --- Tracking Status Helpers ---

  defp tracking_icon(:watching), do: "hero-bell-solid"
  defp tracking_icon(:ignored), do: "hero-bell-slash"
  defp tracking_icon(_), do: "hero-bell"

  defp tracking_color(:watching), do: "text-info"
  defp tracking_color(:ignored), do: "text-base-content/30"
  defp tracking_color(_), do: "text-base-content/20"

  defp tracking_title(:watching), do: "Tracking new releases — click to ignore"
  defp tracking_title(:ignored), do: "Ignoring new releases — click to track"
  defp tracking_title(_), do: "Not tracking"

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
      <div class="flex items-center gap-2">
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
        <button
          phx-click="toggle_detail_view"
          class={[
            "btn btn-sm",
            if(@detail_view == :info, do: "btn-soft btn-primary", else: "btn-ghost")
          ]}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-information-circle-mini" class="size-4" />
          {if @detail_view == :info, do: "Back", else: "More"}
        </button>
      </div>
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

  def overall_progress_percent(nil, _entity), do: 0

  def overall_progress_percent(progress, %{type: type}) when type in [:tv_series, :movie_series] do
    if progress.episodes_total > 0 do
      min(round(progress.episodes_completed / progress.episodes_total * 100), 100)
    else
      0
    end
  end

  def overall_progress_percent(progress, _entity) do
    if progress.episode_duration_seconds > 0 do
      min(round(progress.episode_position_seconds / progress.episode_duration_seconds * 100), 100)
    else
      if progress.episodes_completed > 0, do: 100, else: 0
    end
  end

  def progress_remaining_text(nil, _entity), do: nil

  def progress_remaining_text(progress, %{type: :tv_series}) do
    remaining = progress.episodes_total - progress.episodes_completed

    cond do
      remaining <= 0 -> "Watched"
      remaining == 1 -> "1 episode left"
      true -> "#{remaining} episodes left"
    end
  end

  def progress_remaining_text(progress, %{type: :movie_series}) do
    remaining = progress.episodes_total - progress.episodes_completed

    cond do
      remaining <= 0 -> "Watched"
      remaining == 1 -> "1 movie left"
      true -> "#{remaining} movies left"
    end
  end

  def progress_remaining_text(progress, _entity) do
    cond do
      progress.episodes_completed > 0 ->
        "Watched"

      progress.episode_duration_seconds > 0 && progress.episode_position_seconds > 0 ->
        remaining_seconds = progress.episode_duration_seconds - progress.episode_position_seconds
        "#{format_human_duration(trunc(remaining_seconds))} remaining"

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

  defp genres(%{entity: %{genres: genres}} = assigns) when is_list(genres) and genres != [] do
    ~H"""
    <p class="text-sm text-base-content/60">{Enum.join(@entity.genres, ", ")}</p>
    """
  end

  defp genres(assigns) do
    ~H"""
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
        expanded={MapSet.member?(@expanded_seasons, season.season_number)}
        progress_by_key={@progress_by_key}
        resume_episode_key={@resume_episode_key}
        extra_progress_by_id={@extra_progress_by_id}
        entity_id={@entity.id}
        on_play={@on_play}
        spoiler_free={@spoiler_free}
      />
      <.extras_section
        entity={@entity}
        extra_progress_by_id={@extra_progress_by_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  defp content_list(%{entity: %{type: :movie_series}} = assigns) do
    movies_with_ordinals =
      (assigns.entity.movies || [])
      |> MovieList.sort_movies()
      |> Enum.filter(& &1.content_url)
      |> Enum.with_index(1)

    assigns = assign(assigns, :movies_with_ordinals, movies_with_ordinals)

    ~H"""
    <div class="pt-3">
      <div :if={@movies_with_ordinals != []}>
        <.movie_row
          :for={{movie, ordinal} <- @movies_with_ordinals}
          movie={movie}
          ordinal={ordinal}
          progress={Map.get(@progress_by_key, movie.id)}
          resume_episode_key={@resume_episode_key}
          entity_id={@entity.id}
          on_play={@on_play}
          spoiler_free={@spoiler_free}
        />
      </div>
      <.extras_section
        entity={@entity}
        extra_progress_by_id={@extra_progress_by_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  defp content_list(assigns) do
    ~H"""
    <.extras_section entity={@entity} extra_progress_by_id={@extra_progress_by_id} on_play={@on_play} />
    """
  end

  # --- Season Section ---

  attr :season, :map, required: true
  attr :expanded, :boolean, required: true
  attr :progress_by_key, :map, required: true
  attr :resume_episode_key, :any, default: nil
  attr :extra_progress_by_id, :map, default: %{}
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false

  defp season_section(assigns) do
    episodes = assigns.season.episodes || []
    episode_list = build_episode_list(episodes, assigns.season.number_of_episodes)
    watched_count = count_watched_episodes(assigns.season, assigns.progress_by_key)
    total_count = max(length(episodes), assigns.season.number_of_episodes || 0)

    assigns =
      assigns
      |> assign(:episode_list, episode_list)
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
        <%= for item <- @episode_list do %>
          <%= case item do %>
            <% {:episode, episode} -> %>
              <.episode_row
                episode={episode}
                season_number={@season.season_number}
                progress={Map.get(@progress_by_key, episode.id)}
                resume_episode_key={@resume_episode_key}
                entity_id={@entity_id}
                on_play={@on_play}
                spoiler_free={@spoiler_free}
              />
            <% {:missing, episode_number} -> %>
              <.missing_episode_row
                episode_number={episode_number}
                season_number={@season.season_number}
              />
          <% end %>
        <% end %>
        <.season_extras
          extras={@season.extras}
          extra_progress_by_id={@extra_progress_by_id}
          entity_id={@entity_id}
          on_play={@on_play}
        />
      </div>
    </div>
    """
  end

  # --- Episode Row ---

  attr :episode, :map, required: true
  attr :season_number, :integer, required: true
  attr :progress, :map, default: nil
  attr :resume_episode_key, :any, default: nil
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false

  defp episode_row(assigns) do
    state = episode_state(assigns.progress)

    is_resume_target =
      assigns.resume_episode_key != nil and
        assigns.resume_episode_key == {assigns.season_number, assigns.episode.episode_number}

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(:is_resume_target, is_resume_target)
      |> assign(:thumbnail, image_url(assigns.episode, "thumb"))

    ~H"""
    <div
      class={[
        "p-2 rounded cursor-pointer hover:bg-base-content/5",
        episode_row_class(@state, @is_resume_target)
      ]}
      data-role="episode-row"
      data-resume-target={@is_resume_target || nil}
      phx-click={@on_play}
      phx-value-id={@episode.id}
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-start gap-3 text-sm">
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
          <p
            :if={@episode.description}
            class={[
              "line-clamp-2 text-xs text-base-content/50",
              @spoiler_free && @state != :watched && "spoiler-blur"
            ]}
          >
            {@episode.description}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.episode_duration_text state={@state} progress={@progress} duration={@episode.duration} />
          <button
            phx-click="toggle_watched"
            phx-value-entity-id={@entity_id}
            phx-value-season={@season_number}
            phx-value-episode={@episode.episode_number}
            data-nav-sub-item
            class={[
              "size-5 rounded-full flex items-center justify-center transition-all",
              watched_circle_class(@state)
            ]}
            aria-label={if @state == :watched, do: "Mark unwatched", else: "Mark watched"}
          >
            <.icon
              :if={@state == :watched}
              name="hero-check-mini"
              class="size-3 text-success-content"
            />
            <.icon
              :if={@state != :watched}
              name="hero-check-mini"
              class="size-3 opacity-0 group-hover/check:opacity-60 transition-opacity"
            />
          </button>
        </div>
      </div>
      <div
        :if={@state == :current}
        class="mt-1 ml-[calc(5rem+0.75rem)] h-0.5 rounded-full bg-base-content/10 overflow-hidden"
      >
        <div
          class="h-full bg-info rounded-full"
          style={"width: #{progress_percent(@progress)}%"}
        />
      </div>
    </div>
    """
  end

  # --- Missing Episode Row ---

  attr :episode_number, :integer, required: true
  attr :season_number, :integer, required: true

  defp missing_episode_row(assigns) do
    ~H"""
    <div
      class="p-2 rounded opacity-30"
      data-role="missing-episode-row"
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-start gap-3 text-sm">
        <div class="w-20 flex-shrink-0">
          <div class="w-20 aspect-video rounded bg-base-content/5 border border-dashed border-base-content/10" />
        </div>
        <div class="flex-1 min-w-0">
          <span class="truncate block text-base-content/70 italic">
            <span class="text-base-content/40 font-mono text-xs">{@episode_number}.</span>
            Episode {@episode_number}
          </span>
        </div>
      </div>
    </div>
    """
  end

  def episode_state(nil), do: :unwatched

  def episode_state(progress) do
    cond do
      progress.completed -> :watched
      (progress.position_seconds || 0.0) > 0.0 -> :current
      true -> :unwatched
    end
  end

  def episode_row_class(_state, true = _is_resume_target), do: "border-l-2 border-primary bg-primary/5"

  def episode_row_class(:watched, _), do: "opacity-60"
  def episode_row_class(:current, _), do: "bg-info/5"
  def episode_row_class(:unwatched, _), do: ""

  defp episode_duration_text(%{state: :watched} = assigns) do
    ~H"""
    """
  end

  defp episode_duration_text(%{state: :current, progress: progress} = assigns) do
    remaining = trunc(max(progress.duration_seconds - progress.position_seconds, 0))
    assigns = assign(assigns, :remaining, remaining)

    ~H"""
    <span class="text-info text-xs">
      {format_human_duration(@remaining)} remaining
    </span>
    """
  end

  defp episode_duration_text(%{duration: duration} = assigns) when is_binary(duration) do
    ~H"""
    <span class="text-base-content/40 text-xs">
      {format_iso_duration(@duration)}
    </span>
    """
  end

  defp episode_duration_text(assigns) do
    ~H"""
    """
  end

  defp watched_circle_class(:watched), do: "bg-success hover:bg-success/70"

  defp watched_circle_class(_),
    do: "group/check border border-base-content/20 hover:border-base-content/50"

  def progress_percent(%{position_seconds: pos, duration_seconds: dur})
      when is_number(pos) and is_number(dur) and dur > 0 do
    min(round(pos / dur * 100), 100)
  end

  def progress_percent(_), do: 0

  # --- Movie Row ---

  attr :movie, :map, required: true
  attr :ordinal, :integer, required: true
  attr :progress, :map, default: nil
  attr :resume_episode_key, :any, default: nil
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false

  defp movie_row(assigns) do
    state = episode_state(assigns.progress)

    is_resume_target =
      assigns.resume_episode_key != nil and
        assigns.resume_episode_key == {0, assigns.ordinal}

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(:is_resume_target, is_resume_target)
      |> assign(:thumbnail, image_url(assigns.movie, "poster"))

    ~H"""
    <div
      class={[
        "p-2 rounded cursor-pointer hover:bg-base-content/5",
        episode_row_class(@state, @is_resume_target)
      ]}
      data-role="movie-row"
      data-resume-target={@is_resume_target || nil}
      phx-click={@on_play}
      phx-value-id={@movie.id}
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-start gap-3 text-sm">
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
          <p
            :if={@movie.description}
            class={[
              "line-clamp-2 text-xs text-base-content/50",
              @spoiler_free && @state != :watched && "spoiler-blur"
            ]}
          >
            {@movie.description}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.episode_duration_text state={@state} progress={@progress} duration={@movie.duration} />
          <button
            phx-click="toggle_watched"
            phx-value-entity-id={@entity_id}
            phx-value-season="0"
            phx-value-episode={@ordinal}
            data-nav-sub-item
            class={[
              "size-5 rounded-full flex items-center justify-center transition-all",
              watched_circle_class(@state)
            ]}
            aria-label={if @state == :watched, do: "Mark unwatched", else: "Mark watched"}
          >
            <.icon
              :if={@state == :watched}
              name="hero-check-mini"
              class="size-3 text-success-content"
            />
            <.icon
              :if={@state != :watched}
              name="hero-check-mini"
              class="size-3 opacity-0 group-hover/check:opacity-60 transition-opacity"
            />
          </button>
        </div>
      </div>
      <div
        :if={@state == :current}
        class="mt-1 ml-[calc(3rem+0.75rem)] h-0.5 rounded-full bg-base-content/10 overflow-hidden"
      >
        <div
          class="h-full bg-info rounded-full"
          style={"width: #{progress_percent(@progress)}%"}
        />
      </div>
    </div>
    """
  end

  # --- Extra Row ---

  attr :extra, :map, required: true
  attr :progress, :map, default: nil
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true

  defp extra_row(assigns) do
    state = episode_state(assigns.progress)
    assigns = assign(assigns, :state, state)

    ~H"""
    <div class="py-0.5 pr-3" data-role="extra-row">
      <div
        class={[
          "flex items-center gap-2 text-sm cursor-pointer hover:bg-base-content/5 rounded-lg p-2 -mx-2",
          @state == :watched && "opacity-60"
        ]}
        phx-click={@on_play}
        phx-value-id={@extra.id}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-film-mini" class="size-4 text-base-content/40 flex-shrink-0" />
        <span class="flex-1 min-w-0 truncate text-base-content/70">{@extra.name || "—"}</span>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.episode_duration_text state={@state} progress={@progress} duration={nil} />
          <button
            phx-click="toggle_extra_watched"
            phx-value-extra-id={@extra.id}
            phx-value-entity-id={@entity_id}
            data-nav-sub-item
            class={[
              "size-5 rounded-full flex items-center justify-center transition-all",
              watched_circle_class(@state)
            ]}
            aria-label={if @state == :watched, do: "Mark unwatched", else: "Mark watched"}
          >
            <.icon
              :if={@state == :watched}
              name="hero-check-mini"
              class="size-3 text-success-content"
            />
            <.icon
              :if={@state != :watched}
              name="hero-check-mini"
              class="size-3 opacity-0 group-hover/check:opacity-60 transition-opacity"
            />
          </button>
        </div>
      </div>
      <div
        :if={@state == :current}
        class="mt-1 ml-6 h-0.5 rounded-full bg-base-content/10 overflow-hidden"
      >
        <div
          class="h-full bg-info rounded-full"
          style={"width: #{progress_percent(@progress)}%"}
        />
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
      <.extra_row
        :for={extra <- @extras}
        extra={extra}
        progress={Map.get(@extra_progress_by_id, extra.id)}
        entity_id={@entity.id}
        on_play={@on_play}
      />
    </div>
    """
  end

  defp entity_extras(%{extras: extras}) when is_list(extras) do
    Enum.filter(extras, &is_nil(&1.season_id))
  end

  defp entity_extras(_), do: []

  defp index_extra_progress(%{extra_progress: progress}) when is_list(progress) do
    Map.new(progress, fn record -> {record.extra_id, record} end)
  end

  defp index_extra_progress(_), do: %{}

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
      <.extra_row
        :for={extra <- @extras}
        extra={extra}
        progress={Map.get(@extra_progress_by_id, extra.id)}
        entity_id={@entity_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  # --- Info View ---

  attr :entity, :map, required: true
  attr :files, :list, default: []
  attr :rematch_confirm, :boolean, default: false
  attr :delete_confirm, :any, default: nil

  defp info_view(assigns) do
    total_size = Enum.reduce(assigns.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)
    file_count = length(assigns.files)
    genres = assigns.entity.genres || []

    external_ids =
      if is_list(assigns.entity.external_ids), do: assigns.entity.external_ids, else: []

    watch_dirs = MapSet.new(MediaCentarr.Config.get(:watch_dirs) || [])
    file_groups = build_file_groups(assigns.files, watch_dirs)

    assigns =
      assigns
      |> assign(:total_size, total_size)
      |> assign(:file_count, file_count)
      |> assign(:genres, genres)
      |> assign(:external_ids, external_ids)
      |> assign(:file_groups, file_groups)

    ~H"""
    <div class="pt-3 space-y-5">
      <%!-- Files section --%>
      <div :if={@files != []}>
        <div class="group/files flex items-center justify-between mb-2">
          <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
            Files
          </span>
          <div class="flex items-center gap-2">
            <span class="text-xs text-base-content/40">
              {file_summary(@file_count, @total_size)}
            </span>
            <button
              :if={@file_count > 1}
              phx-click="delete_all_prompt"
              class="btn btn-ghost btn-xs text-error/60 hover:text-error opacity-0 group-hover/files:opacity-100 focus:opacity-100 transition-opacity"
              data-nav-item
              tabindex="0"
              aria-label="Delete all files"
            >
              <.icon name="hero-trash-mini" class="size-3.5" /> Delete all
            </button>
          </div>
        </div>
        <div class="space-y-3">
          <div :for={group <- @file_groups}>
            <div class="group/folder flex items-center gap-1.5 mb-1.5">
              <.icon name="hero-folder-mini" class="size-3.5 text-base-content/40 flex-shrink-0" />
              <span
                class="text-xs font-medium text-base-content/60 truncate"
                title={group.dir}
              >
                {group.name}
              </span>
              <button
                :if={!group.is_watch_dir}
                phx-click="delete_folder_prompt"
                phx-value-path={group.dir}
                phx-value-count={length(group.files)}
                class="btn btn-ghost btn-xs text-error/60 hover:text-error ml-auto flex-shrink-0 opacity-0 group-hover/folder:opacity-100 focus:opacity-100 transition-opacity"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-folder-minus-mini" class="size-3.5" />
                Delete ({length(group.files)} {if length(group.files) == 1,
                  do: "file",
                  else: "files"})
              </button>
            </div>
            <div class="space-y-1.5">
              <.file_row :for={file_info <- group.files} file_info={file_info} />
            </div>
          </div>
        </div>
      </div>
      <%!-- Delete confirmation modal --%>
      <.delete_confirmation delete_confirm={@delete_confirm} />

      <%!-- Metadata section --%>
      <div
        :if={@genres != [] || @entity.director || @entity.aggregate_rating_value || @entity.duration}
        data-nav-item
        tabindex="0"
        class="rounded-xl outline-none"
      >
        <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
          Metadata
        </span>
        <div class="mt-2 space-y-2 text-sm">
          <div :if={@genres != []} class="flex items-start gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">Genres</span>
            <span class="text-base-content/80">{Enum.join(@genres, ", ")}</span>
          </div>
          <div :if={@entity.director} class="flex items-baseline gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">Director</span>
            <span class="text-base-content/80">{@entity.director}</span>
          </div>
          <div :if={@entity.aggregate_rating_value} class="flex items-baseline gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">Rating</span>
            <span class="text-base-content/80">{@entity.aggregate_rating_value}</span>
          </div>
          <div :if={@entity.duration} class="flex items-baseline gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">Duration</span>
            <span class="text-base-content/80">{format_iso_duration(@entity.duration)}</span>
          </div>
          <div :if={@entity.content_rating} class="flex items-baseline gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">Rated</span>
            <span class="text-base-content/80">{@entity.content_rating}</span>
          </div>
        </div>
      </div>

      <%!-- External IDs section --%>
      <div data-nav-item tabindex="0" class="rounded-xl outline-none">
        <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
          External IDs
        </span>
        <div class="mt-2 space-y-2 text-sm">
          <div :if={@entity.url} class="flex items-start gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">TMDB</span>
            <a
              href={@entity.url}
              target="_blank"
              rel="noopener"
              class="link link-primary text-sm truncate"
            >
              {@entity.url}
            </a>
          </div>
          <div :for={ext_id <- @external_ids} class="flex items-start gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0 truncate">
              {ext_id.source}
            </span>
            <span class="text-base-content/80 font-mono text-xs">{ext_id.external_id}</span>
          </div>
          <div class="flex items-start gap-2">
            <span class="text-base-content/50 w-16 flex-shrink-0">UUID</span>
            <span class="text-base-content/60 font-mono text-xs select-all">{@entity.id}</span>
          </div>
        </div>
      </div>

      <%!-- Actions section --%>
      <div>
        <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
          Actions
        </span>
        <div class="mt-2 flex items-center gap-2">
          <button
            phx-click="rematch"
            phx-value-id={@entity.id}
            class={"btn btn-soft btn-sm #{if @rematch_confirm, do: "btn-error", else: "btn-warning"}"}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" />
            {if @rematch_confirm, do: "Confirm?", else: "Rematch"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :file_info, :map, required: true

  defp file_row(assigns) do
    file = assigns.file_info.file
    size = assigns.file_info.size
    absent = is_nil(size)
    filename = Path.basename(file.file_path)

    assigns =
      assigns
      |> assign(:file_path, file.file_path)
      |> assign(:filename, filename)
      |> assign(:size, size)
      |> assign(:absent, absent)

    ~H"""
    <div class={["group text-sm rounded p-2 bg-base-content/5", @absent && "opacity-60"]}>
      <div class="flex items-center gap-2">
        <.icon
          name={if @absent, do: "hero-exclamation-triangle-mini", else: "hero-document-mini"}
          class={"size-3.5 flex-shrink-0 #{if @absent, do: "text-warning", else: "text-base-content/40"}"}
        />
        <span class="truncate font-mono text-xs text-base-content/80" title={@file_path}>
          {@filename}
        </span>
        <span :if={@size} class="text-xs text-base-content/40 flex-shrink-0 ml-auto">
          {format_file_size(@size)}
        </span>
        <span :if={@absent} class="text-xs text-warning flex-shrink-0">absent</span>
        <button
          phx-click="delete_file_prompt"
          phx-value-path={@file_path}
          class="btn btn-ghost btn-xs size-6 min-h-0 p-0 text-base-content/30 hover:text-error flex-shrink-0 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity"
          aria-label="Delete file"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-trash-mini" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Groups watched files by directory, sorted alphabetically.
  Returns a list of `%{dir, name, files, is_watch_dir}` maps.
  """
  def build_file_groups(files, watch_dirs) do
    files
    |> Enum.group_by(fn %{file: file} -> Path.dirname(file.file_path) end)
    |> Enum.sort_by(fn {dir, _files} -> dir end)
    |> Enum.map(fn {dir, dir_files} ->
      %{dir: dir, name: Path.basename(dir), files: dir_files, is_watch_dir: dir in watch_dirs}
    end)
  end

  @doc """
  Builds the payload for the "Delete All" confirmation modal.
  Returns `%{file_groups, total_size, file_count}` where each group has
  `%{dir, name, is_watch_dir, files}` with files as `%{path, name, size}` maps.
  """
  def build_delete_all_payload(detail_files, watch_dirs) do
    file_groups =
      detail_files
      |> Enum.group_by(fn %{file: file} -> Path.dirname(file.file_path) end)
      |> Enum.sort_by(fn {dir, _files} -> dir end)
      |> Enum.map(fn {dir, dir_files} ->
        %{
          dir: dir,
          name: Path.basename(dir),
          is_watch_dir: dir in watch_dirs,
          files:
            Enum.map(dir_files, fn %{file: file, size: size} ->
              %{path: file.file_path, name: Path.basename(file.file_path), size: size}
            end)
        }
      end)

    total_size = Enum.reduce(detail_files, 0, fn %{size: size}, acc -> acc + (size || 0) end)

    %{file_groups: file_groups, total_size: total_size, file_count: length(detail_files)}
  end

  def file_summary(count, total_size) do
    size_str = format_file_size(total_size)
    "#{count} #{if count == 1, do: "file", else: "files"}, #{size_str}"
  end

  def format_file_size(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  def format_file_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  def format_file_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  def format_file_size(bytes), do: "#{bytes} B"

  # --- Delete Confirmation ---

  attr :delete_confirm, :any, default: nil

  defp delete_confirmation(%{delete_confirm: nil} = assigns) do
    ~H"""
    """
  end

  defp delete_confirmation(%{delete_confirm: {:file, file}} = assigns) do
    assigns = assign(assigns, :file, file)

    ~H"""
    <div
      class="modal-backdrop"
      data-state="open"
      data-detail-mode="modal"
      data-dismiss-event="delete_cancel"
      phx-window-keydown="delete_cancel"
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel modal-panel-sm p-6" phx-click-away="delete_cancel">
        <h3 class="text-lg font-bold text-error">Delete file?</h3>
        <div class="mt-3 rounded-lg bg-base-content/5 p-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-document-mini" class="size-4 text-base-content/40 flex-shrink-0" />
            <span class="font-mono text-xs text-base-content/80 truncate">{@file.name}</span>
            <span :if={@file.size} class="text-xs text-base-content/40 flex-shrink-0 ml-auto">
              {format_file_size(@file.size)}
            </span>
          </div>
          <p class="mt-1 ml-6 text-xs text-base-content/30 truncate-left" title={@file.path}>
            <bdo dir="ltr">{@file.path}</bdo>
          </p>
        </div>
        <p class="mt-3 text-sm text-warning">This file will be permanently deleted from disk.</p>
        <p class="text-xs text-base-content/40 mt-1">This action cannot be undone.</p>
        <div class="mt-4 flex justify-end gap-2">
          <button phx-click="delete_cancel" class="btn btn-ghost btn-sm" data-nav-item tabindex="0">
            Cancel
          </button>
          <button
            phx-click="delete_confirm"
            class="btn btn-soft btn-error btn-sm"
            data-nav-item
            tabindex="0"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp delete_confirmation(%{delete_confirm: {:folder, folder}} = assigns) do
    assigns = assign(assigns, :folder, folder)

    ~H"""
    <div
      class="modal-backdrop"
      data-state="open"
      data-detail-mode="modal"
      data-dismiss-event="delete_cancel"
      phx-window-keydown="delete_cancel"
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel p-6" phx-click-away="delete_cancel">
        <h3 class="text-lg font-bold text-error">Delete folder?</h3>
        <div class="mt-3 rounded-lg bg-base-content/5 p-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-folder-mini" class="size-4 text-base-content/40 flex-shrink-0" />
            <span class="font-medium text-sm text-base-content/80">{@folder.name}</span>
            <span class="text-xs text-base-content/40 flex-shrink-0 ml-auto">
              {format_file_size(@folder.total_size)}
            </span>
          </div>
          <p class="mt-1 ml-6 text-xs text-base-content/30 truncate-left" title={@folder.path}>
            <bdo dir="ltr">{@folder.path}</bdo>
          </p>
          <div class="mt-2 ml-6 space-y-0.5">
            <div
              :for={file <- @folder.files}
              class="flex items-center gap-2 text-xs text-base-content/60"
            >
              <.icon name="hero-document-mini" class="size-3 text-base-content/30 flex-shrink-0" />
              <span class="truncate font-mono">{file.name}</span>
              <span :if={file.size} class="text-base-content/30 flex-shrink-0 ml-auto">
                {format_file_size(file.size)}
              </span>
            </div>
          </div>
        </div>
        <p class="mt-3 text-sm text-warning">
          The entire folder including {length(@folder.files)} media {if length(@folder.files) == 1,
            do: "file",
            else: "files"} and all other contents will be permanently deleted.
        </p>
        <p class="text-xs text-base-content/40 mt-1">This action cannot be undone.</p>
        <div class="mt-4 flex justify-end gap-2">
          <button phx-click="delete_cancel" class="btn btn-ghost btn-sm" data-nav-item tabindex="0">
            Cancel
          </button>
          <button
            phx-click="delete_confirm"
            class="btn btn-soft btn-error btn-sm"
            data-nav-item
            tabindex="0"
          >
            Delete folder
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp delete_confirmation(%{delete_confirm: {:all, all_info}} = assigns) do
    assigns = assign(assigns, :all_info, all_info)

    ~H"""
    <div
      class="modal-backdrop"
      data-state="open"
      data-detail-mode="modal"
      data-dismiss-event="delete_cancel"
      phx-window-keydown="delete_cancel"
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel p-6" phx-click-away="delete_cancel">
        <h3 class="text-lg font-bold text-error">Delete all files?</h3>
        <p class="mt-1 text-sm text-base-content/60">
          {file_summary(@all_info.file_count, @all_info.total_size)} across {length(
            @all_info.file_groups
          )} {if length(@all_info.file_groups) == 1,
            do: "folder",
            else: "folders"}
        </p>
        <div class="mt-3 rounded-lg bg-base-content/5 p-3 max-h-64 overflow-y-auto thin-scrollbar space-y-2">
          <div :for={group <- @all_info.file_groups}>
            <div class="flex items-center gap-1.5 mb-1">
              <.icon name="hero-folder-mini" class="size-3.5 text-base-content/40 flex-shrink-0" />
              <span class="text-xs font-medium text-base-content/60 truncate" title={group.dir}>
                {group.name}
              </span>
            </div>
            <div class="ml-5 space-y-0.5">
              <div
                :for={file <- group.files}
                class="flex items-center gap-2 text-xs text-base-content/60"
              >
                <.icon
                  name="hero-document-mini"
                  class="size-3 text-base-content/30 flex-shrink-0"
                />
                <span class="truncate font-mono">{file.name}</span>
                <span :if={file.size} class="text-base-content/30 flex-shrink-0 ml-auto">
                  {format_file_size(file.size)}
                </span>
              </div>
            </div>
          </div>
        </div>
        <p class="mt-3 text-sm text-warning">
          All files will be permanently deleted from disk.
        </p>
        <p class="text-xs text-base-content/40 mt-1">This action cannot be undone.</p>
        <div class="mt-4 flex justify-end gap-2">
          <button phx-click="delete_cancel" class="btn btn-ghost btn-sm" data-nav-item tabindex="0">
            Cancel
          </button>
          <button
            phx-click="delete_confirm"
            class="btn btn-soft btn-error btn-sm"
            data-nav-item
            tabindex="0"
          >
            Delete all
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Episode List Builder ---

  def build_episode_list(episodes, number_of_episodes) do
    episode_map = Map.new(episodes, &{&1.episode_number, &1})
    max_known = Enum.max_by(episodes, & &1.episode_number, fn -> nil end)

    upper = max(number_of_episodes || 0, if(max_known, do: max_known.episode_number, else: 0))

    if upper == 0 do
      []
    else
      for n <- 1..upper do
        case Map.get(episode_map, n) do
          nil -> {:missing, n}
          episode -> {:episode, episode}
        end
      end
    end
  end

  # --- Helpers ---

  def count_watched_episodes(season, progress_by_key) do
    Enum.count(season.episodes || [], fn episode ->
      case Map.get(progress_by_key, episode.id) do
        %{completed: true} -> true
        _ -> false
      end
    end)
  end

  defp season_progress_label(watched, total) when watched == total and total > 0, do: "watched"
  defp season_progress_label(watched, total), do: "#{total - watched} remaining"

  defp resume_episode_key(%{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode) do
    {season, episode}
  end

  defp resume_episode_key(_), do: nil

  defp progress_episode_key(%{current_episode: %{season: season, episode: episode}})
       when is_integer(season) and is_integer(episode), do: {season, episode}

  defp progress_episode_key(_), do: nil
end
