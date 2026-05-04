defmodule MediaCentarrWeb.Components.DetailPanel do
  @moduledoc """
  Shared entity detail content component, rendered inside ModalShell.

  Displays hero (21:9 backdrop), identity (logo/title), metadata, description,
  playback actions (Play/Resume button + progress bar), and type-specific content
  lists (episodes for TV, movies for movie series).
  """

  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers

  import MediaCentarrWeb.LibraryFormatters,
    only: [format_type: 1, extract_year: 1, format_human_duration: 1]

  alias MediaCentarr.Library.EpisodeList
  alias MediaCentarr.Library.MovieList
  alias MediaCentarrWeb.Components.Detail.FacetStrip
  alias MediaCentarrWeb.Components.Detail.Hero
  alias MediaCentarrWeb.Components.Detail.Logic
  alias MediaCentarrWeb.Components.Detail.MetadataRow
  alias MediaCentarrWeb.Components.Detail.PlayCard

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

  # Shared doc strings for the recurring loose-attr shapes in this module.
  # Each points at the typed producer in the data layer (Library) so the
  # contract stays inspectable without exporting internal schemas across
  # the boundary.
  @doc_entity "polymorphic Library schema — `Movie | TVSeries | MovieSeries | VideoObject` (see `MediaCentarr.Library`). Reads `:type`, `:name`, `:images`, `:seasons`/`:movies`/`:extras` per branch. Tightening to a typed Subject struct is deferred until shared `MediaCentarrWeb.ViewModels.*` lands."
  @doc_progress "`MediaCentarr.Library.ProgressSummary.t() | nil` — produced by `Library.Browser`."
  @doc_progress_records "list of `MediaCentarr.Library.ProgressRecord.t()` rows preloaded from the entity."
  @doc_resume "resume target map `%{kind, season, episode, ...} | nil` — see `LibraryProgress.resume_target_for/1`."
  @doc_resume_episode_key "`{season_number, episode_number}` tuple | `nil` — derived from `:resume`."
  @doc_progress_by_key "`%{{season_number, episode_number} => ProgressRecord.t()}` — built by `EpisodeList.index_progress_by_key/1`."
  @doc_extra_progress_by_id "`%{Ecto.UUID.t() => ProgressRecord.t()}` keyed by extra id."
  @doc_detail_files "list of file-info maps (`%{file: KnownFile.t(), entity_id, role, ...}`) built by `LibraryLive.list_files_for_entity/2`."
  @doc_delete_confirm "pending inline-confirm target: `nil` | `:all` | `{:file, path}` | `{:folder, path}`. The host's `delete_*_prompt` handlers compare against this to decide whether the click is the first (set pending) or second (execute). `:any` is intentional — it's a sum type, not a single shape."
  @doc_season "`MediaCentarr.Library.Season.t()` (Ecto schema) preloaded with `:episodes`."
  @doc_episode "`MediaCentarr.Library.Episode.t()` (Ecto schema)."
  @doc_movie "`MediaCentarr.Library.Movie.t()` (Ecto schema) — used inside `MovieSeries` content lists."
  @doc_extra "`MediaCentarr.Library.Extra.t()` (Ecto schema) — TV bonus content."
  @doc_files_list "list of file-info maps — same shape as `:detail_files`."
  @doc_file_info "single file-info map — `%{file: KnownFile.t(), entity_id, role, …}`."

  # --- Main Component ---

  attr :entity, :map, required: true, doc: @doc_entity
  attr :progress, :map, default: nil, doc: @doc_progress
  attr :resume, :map, default: nil, doc: @doc_resume
  attr :progress_records, :list, default: [], doc: @doc_progress_records
  attr :expanded_seasons, MapSet, default: nil
  attr :available, :boolean, default: true
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main
  attr :detail_files, :list, default: [], doc: @doc_detail_files
  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil
  attr :tmdb_ready, :boolean, default: true

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

    playback = build_playback(assigns)
    facets = build_facets(assigns.entity)
    metadata_items = build_metadata_items(assigns.entity)
    tagline = tagline_for(assigns.entity)

    assigns =
      assigns
      |> assign(:expanded_seasons, expanded_seasons)
      |> assign(:progress_by_key, progress_by_key)
      |> assign(:resume_episode_key, resume_episode_key)
      |> assign(:extra_progress_by_id, extra_progress_by_id)
      |> assign(:has_scrollable_content, has_scrollable_content)
      |> assign(:playback, playback)
      |> assign(:facets, facets)
      |> assign(:metadata_items, metadata_items)
      |> assign(:tagline, tagline)

    ~H"""
    <div class="detail-panel">
      <div id="detail-header">
        <Hero.hero entity={@entity} tagline={@tagline} available={@available}>
          <:actions :if={@tracking_status}>
            <.button
              variant="dismiss"
              size="sm"
              shape="circle"
              class="opacity-60 hover:opacity-100 transition-opacity"
              phx-click="toggle_tracking"
              title={tracking_title(@tracking_status)}
            >
              <.icon
                name={tracking_icon(@tracking_status)}
                class={"size-5 #{tracking_color(@tracking_status)}"}
              />
            </.button>
          </:actions>
        </Hero.hero>
        <div class="p-4 space-y-4">
          <MetadataRow.metadata_row
            badge_text={format_type(@entity.type)}
            items={@metadata_items}
          />
          <PlayCard.play_card
            on_play={@on_play}
            target_id={@playback.target_id}
            label={@playback.label}
            percent={@playback.percent}
            remaining_text={@playback.remaining_text}
            available={@available}
            detail_view={@detail_view}
          />
          <%!-- Synopsis + structured-metadata sidebar.
                Below xl: stacks single-column (synopsis full width, then
                facet strip horizontal).
                At xl:+ reflows to two columns: synopsis capped at a
                readable measure on the left, facets stacked on the right —
                keeps prose at a comfortable line length on wide displays
                without leaving the right side empty.
                File paths are intentionally NOT rendered here — they
                live in the Manage view's Files section, grouped by
                directory with delete affordances. The main view stays
                focused on what to watch, not where it lives on disk. --%>
          <div class="space-y-4 xl:space-y-0 xl:grid xl:grid-cols-[minmax(0,65ch)_minmax(0,1fr)] xl:gap-8 xl:items-start">
            <p :if={@entity.description} class="text-sm text-base-content/70 line-clamp-4">
              {@entity.description}
            </p>
            <div class="min-w-0">
              <FacetStrip.facet_strip facets={@facets} layout={:row} class="xl:hidden" />
              <FacetStrip.facet_strip facets={@facets} layout={:stacked} class="hidden xl:grid" />
            </div>
          </div>
        </div>
      </div>
      <div
        :if={@has_scrollable_content}
        id="detail-content"
        class="px-4 pb-4"
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
            available={@available}
          />
        <% else %>
          <.info_view
            entity={@entity}
            files={@detail_files}
            rematch_confirm={@rematch_confirm}
            delete_confirm={@delete_confirm}
            tmdb_ready={@tmdb_ready}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Header content builders (used in detail_panel/1) ---

  defp build_playback(assigns) do
    {label, target_id} =
      Logic.playback_props(assigns.entity, assigns.resume, assigns.progress)

    percent = overall_progress_percent(assigns.progress, assigns.entity)
    remaining = progress_remaining_text(assigns.progress, assigns.entity)

    %{
      label: label,
      target_id: target_id,
      percent: percent,
      remaining_text: remaining
    }
  end

  defp build_facets(%{type: :movie} = movie), do: Logic.facets_for(:movie, movie)
  defp build_facets(%{type: :tv_series} = tv), do: Logic.facets_for(:tv_series, tv)

  defp build_facets(%{type: :movie_series, movies: movies} = ms) when is_list(movies),
    do: Logic.facets_for(:movie_series, ms, movies)

  defp build_facets(_), do: []

  defp build_metadata_items(entity) do
    [
      year_or_nil(entity),
      season_count_or_nil(entity),
      movie_count_or_nil(entity),
      duration_or_nil(entity),
      Map.get(entity, :content_rating),
      country_or_nil(entity),
      status_or_nil(entity)
    ]
  end

  defp year_or_nil(%{date_published: date}) when is_binary(date) and date != "", do: extract_year(date)

  defp year_or_nil(_), do: nil

  defp season_count_or_nil(%{type: :tv_series, seasons: seasons}) when is_list(seasons) do
    case length(seasons) do
      0 -> nil
      1 -> "1 season"
      n -> "#{n} seasons"
    end
  end

  defp season_count_or_nil(_), do: nil

  defp movie_count_or_nil(%{type: :movie_series, movies: movies}) when is_list(movies) do
    case length(movies) do
      0 -> nil
      1 -> "1 movie"
      n -> "#{n} movies"
    end
  end

  defp movie_count_or_nil(_), do: nil

  defp duration_or_nil(%{duration: duration}), do: Logic.format_duration(duration)
  defp duration_or_nil(_), do: nil

  defp country_or_nil(entity) do
    case Map.get(entity, :country_code) do
      code when is_binary(code) and code != "" -> code
      _ -> nil
    end
  end

  defp status_or_nil(entity) do
    case Map.get(entity, :status) do
      nil -> nil
      status -> Logic.humanize_status(status)
    end
  end

  defp tagline_for(entity) do
    case Map.get(entity, :tagline) do
      tagline when is_binary(tagline) and tagline != "" -> tagline
      _ -> nil
    end
  end

  # --- Tracking Status Helpers (used in Hero :actions slot) ---

  defp tracking_icon(:watching), do: "hero-bell-solid"
  defp tracking_icon(:ignored), do: "hero-bell-slash"
  defp tracking_icon(_), do: "hero-bell"

  defp tracking_color(:watching), do: "text-info"
  defp tracking_color(:ignored), do: "text-base-content/30"
  defp tracking_color(_), do: "text-base-content/20"

  defp tracking_title(:watching), do: "Tracking new releases — click to ignore"
  defp tracking_title(:ignored), do: "Ignoring new releases — click to track"
  defp tracking_title(_), do: "Not tracking"

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
        available={@available}
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
          available={@available}
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

  attr :season, :map, required: true, doc: @doc_season
  attr :expanded, :boolean, required: true
  attr :progress_by_key, :map, required: true, doc: @doc_progress_by_key
  attr :resume_episode_key, :any, default: nil, doc: @doc_resume_episode_key
  attr :extra_progress_by_id, :map, default: %{}, doc: @doc_extra_progress_by_id
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

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
                available={@available}
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

  attr :episode, :map, required: true, doc: @doc_episode
  attr :season_number, :integer, required: true

  attr :progress, :map,
    default: nil,
    doc: "`MediaCentarr.Library.ProgressRecord.t() | nil` for this episode."

  attr :resume_episode_key, :any, default: nil, doc: @doc_resume_episode_key
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

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
            :if={@thumbnail && @available}
            src={@thumbnail}
            class="w-20 aspect-video rounded object-cover object-top"
          />
          <div
            :if={(@thumbnail && !@available) || !@thumbnail}
            class="w-20 aspect-video rounded bg-base-300/30"
          />
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

  attr :movie, :map, required: true, doc: @doc_movie
  attr :ordinal, :integer, required: true

  attr :progress, :map,
    default: nil,
    doc: "`MediaCentarr.Library.ProgressRecord.t() | nil` for this movie."

  attr :available, :boolean, default: true
  attr :resume_episode_key, :any, default: nil, doc: @doc_resume_episode_key
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
            :if={@thumbnail && @available}
            src={@thumbnail}
            class="w-12 aspect-[2/3] rounded object-cover"
          />
          <div
            :if={(@thumbnail && !@available) || !@thumbnail}
            class="w-12 aspect-[2/3] rounded bg-base-300/30"
          />
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

  attr :extra, :map, required: true, doc: @doc_extra

  attr :progress, :map,
    default: nil,
    doc: "`MediaCentarr.Library.ProgressRecord.t() | nil` for this extra."

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

  defp season_extras(%{extras: %Ecto.Association.NotLoaded{}} = assigns) do
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

  attr :entity, :map, required: true, doc: @doc_entity
  attr :files, :list, default: [], doc: @doc_files_list
  attr :rematch_confirm, :boolean, default: false
  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :tmdb_ready, :boolean, default: true

  defp info_view(assigns) do
    total_size = Enum.reduce(assigns.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)
    file_count = length(assigns.files)

    external_ids =
      if is_list(assigns.entity.external_ids), do: assigns.entity.external_ids, else: []

    watch_dirs = MapSet.new(MediaCentarr.Config.get(:watch_dirs) || [])
    file_groups = build_file_groups(assigns.files, watch_dirs)

    assigns =
      assigns
      |> assign(:total_size, total_size)
      |> assign(:file_count, file_count)
      |> assign(:external_ids, external_ids)
      |> assign(:file_groups, file_groups)

    ~H"""
    <div class="pt-3 space-y-5">
      <%!-- Files section. Layout intent: a prominent entity-wide delete
            sits at the top so the user can see the "nuke everything"
            option without hunting; underneath, per-folder and per-file
            delete affordances stay always-visible (not hover-gated) so
            granular cleanup is equally discoverable. The folder-level
            button never appears for the watch_dir itself — deleting a
            watch root would be catastrophic.

            Confirmation is INLINE — first click on any delete button
            sets `@delete_confirm` to that target and the button flips
            its label to "Confirm?". Second click executes. Clicking a
            different delete button re-targets. There is no separate
            confirmation modal (we deliberately killed it because
            modal-on-modal noise is uglier than the in-place gesture). --%>
      <div :if={@files != []}>
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
            Files
          </span>
          <span class="text-xs text-base-content/40">
            {file_summary(@file_count, @total_size)}
          </span>
        </div>
        <div class="mb-3 flex items-center gap-2">
          <.button
            variant="danger"
            size="sm"
            phx-click="delete_all_prompt"
            data-nav-item
            tabindex="0"
            aria-label={delete_all_aria_label(@file_count)}
          >
            <.icon name="hero-trash-mini" class="size-4" />
            <%= if @delete_confirm == :all do %>
              Click again to confirm — {delete_all_label(@file_count)} ({format_file_size(@total_size)})
            <% else %>
              {delete_all_label(@file_count)} ({format_file_size(@total_size)})
            <% end %>
          </.button>
          <.button
            :if={@delete_confirm == :all}
            variant="dismiss"
            size="sm"
            phx-click="delete_cancel"
            data-nav-item
            tabindex="0"
          >
            Cancel
          </.button>
        </div>
        <div class="space-y-3">
          <div :for={group <- @file_groups}>
            <div class="flex items-center gap-1.5 mb-1.5">
              <.icon name="hero-folder-mini" class="size-3.5 text-base-content/40 flex-shrink-0" />
              <span
                class="text-xs font-medium text-base-content/60 truncate"
                title={group.dir}
              >
                {group.name}
              </span>
              <.button
                :if={!group.is_watch_dir}
                variant="destructive_inline"
                size="xs"
                class={[
                  "ml-auto flex-shrink-0",
                  if(@delete_confirm == {:folder, group.dir},
                    do: "text-error font-medium",
                    else: "text-error/70 hover:text-error"
                  )
                ]}
                phx-click="delete_folder_prompt"
                phx-value-path={group.dir}
                phx-value-count={length(group.files)}
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-folder-minus-mini" class="size-3.5" />
                <%= if @delete_confirm == {:folder, group.dir} do %>
                  Click again to confirm
                <% else %>
                  Delete ({length(group.files)} {if length(group.files) == 1,
                    do: "file",
                    else: "files"})
                <% end %>
              </.button>
            </div>
            <div class="space-y-1.5">
              <.file_row
                :for={file_info <- group.files}
                file_info={file_info}
                delete_confirm={@delete_confirm}
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- External IDs section. One row per known external source.
            TMDB row's URL comes from `@entity.url` (built by the mapper
            with type-aware path /movie vs /tv). Unknown sources render
            without a link rather than guessing a URL shape. --%>
      <div :if={@external_ids != []}>
        <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
          External IDs
        </span>
        <div class="mt-2 space-y-1">
          <.external_id_row
            :for={ext_id <- @external_ids}
            ext_id={ext_id}
            entity_url={@entity.url}
          />
        </div>
      </div>

      <%!-- Actions section --%>
      <div>
        <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
          Actions
        </span>
        <div class="mt-2 flex items-center gap-2">
          <.button
            :if={@tmdb_ready}
            variant={if @rematch_confirm, do: "danger", else: "risky"}
            size="sm"
            phx-click="rematch"
            phx-value-id={@entity.id}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" />
            {if @rematch_confirm, do: "Confirm?", else: "Rematch"}
          </.button>
          <p :if={!@tmdb_ready} class="text-xs text-base-content/50">
            Rematch needs a working TMDB connection. Test it in <.link
              navigate="/settings?section=tmdb"
              class="link link-primary"
            >Settings</.link>.
          </p>
        </div>
      </div>

      <%!-- UUID footer — debug-y, kept for support workflows but
            visually demoted so it doesn't compete with real metadata. --%>
      <div class="pt-1 flex items-center gap-1.5 text-xs text-base-content/30">
        <.icon name="hero-finger-print-mini" class="size-3" />
        <span class="uppercase tracking-wide">UUID</span>
        <span class="font-mono select-all">{@entity.id}</span>
      </div>
    </div>
    """
  end

  attr :ext_id, :map, required: true, doc: "`MediaCentarr.Library.ExternalId.t()`"
  attr :entity_url, :string, default: nil

  defp external_id_row(assigns) do
    url = external_id_url(assigns.ext_id.source, assigns.ext_id.external_id, assigns.entity_url)
    label = external_id_label(assigns.ext_id.source)
    assigns = assigns |> assign(:url, url) |> assign(:label, label)

    ~H"""
    <div class="flex items-baseline gap-2 text-sm">
      <span class="text-base-content/50 w-16 flex-shrink-0 text-xs uppercase tracking-wide">
        {@label}
      </span>
      <%= if @url do %>
        <a
          href={@url}
          target="_blank"
          rel="noopener"
          class="inline-flex items-baseline gap-1 link link-primary font-mono text-xs"
          data-nav-item
          tabindex="0"
        >
          {@ext_id.external_id}
          <.icon name="hero-arrow-top-right-on-square-mini" class="size-3 self-center" />
        </a>
      <% else %>
        <span class="text-base-content/80 font-mono text-xs">{@ext_id.external_id}</span>
      <% end %>
    </div>
    """
  end

  defp external_id_url("tmdb", _id, entity_url) when is_binary(entity_url), do: entity_url
  defp external_id_url("imdb", id, _), do: "https://www.imdb.com/title/#{id}/"
  defp external_id_url("tvdb", id, _), do: "https://www.thetvdb.com/dereferrer/series/#{id}"
  defp external_id_url(_, _, _), do: nil

  defp external_id_label("tmdb"), do: "TMDB"
  defp external_id_label("imdb"), do: "IMDb"
  defp external_id_label("tvdb"), do: "TVDB"
  defp external_id_label(source) when is_binary(source), do: String.upcase(source)
  defp external_id_label(_), do: "—"

  attr :file_info, :map, required: true, doc: @doc_file_info

  attr :delete_confirm, :any,
    default: nil,
    doc:
      "current pending-delete target — `{:file, path}` flips this row's trash button into confirm state."

  defp file_row(assigns) do
    file = assigns.file_info.file
    size = assigns.file_info.size
    absent = is_nil(size)
    filename = Path.basename(file.file_path)
    badges = parse_quality_badges(filename)
    added_at = Map.get(file, :inserted_at)
    is_pending = assigns.delete_confirm == {:file, file.file_path}

    assigns =
      assigns
      |> assign(:file_path, file.file_path)
      |> assign(:filename, filename)
      |> assign(:size, size)
      |> assign(:absent, absent)
      |> assign(:badges, badges)
      |> assign(:added_at, added_at)
      |> assign(:is_pending, is_pending)

    ~H"""
    <div class={[
      "text-sm rounded p-2",
      @absent && "opacity-60",
      if(@is_pending, do: "bg-error/15 ring-1 ring-error/40", else: "bg-base-content/5")
    ]}>
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
        <.button
          variant="destructive_inline"
          size="xs"
          class={[
            "min-h-0 flex-shrink-0",
            if(@is_pending,
              do: "px-2 text-error font-medium",
              else: "size-6 p-0 text-error/70 hover:text-error"
            )
          ]}
          phx-click="delete_file_prompt"
          phx-value-path={@file_path}
          aria-label={if @is_pending, do: "Click again to confirm delete", else: "Delete file"}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-trash-mini" class="size-3.5" />
          <span :if={@is_pending}>Click to confirm</span>
        </.button>
      </div>
      <div
        :if={@badges != [] || @added_at}
        class="mt-1 ml-5 flex items-center gap-1.5 text-xs text-base-content/40"
      >
        <%!-- Highlight HDR (a quality users actively care about) with the
              info-blue tint; everything else stays a quiet ghost chip. --%>
        <.badge
          :for={badge <- @badges}
          variant={if badge == "HDR", do: "info", else: "ghost"}
          size="xs"
        >
          {badge}
        </.badge>
        <span :if={@added_at} class="ml-auto">added {time_ago(@added_at)}</span>
      </div>
    </div>
    """
  end

  @doc """
  Extracts a small, ordered list of quality/format badges from a release filename.

  Returns at most one badge per category: resolution, HDR, source, codec.
  Order is fixed (resolution → HDR → source → codec) so the row reads the same
  shape across files. Unknown filenames return `[]` — the row simply hides the
  badge strip.
  """
  def parse_quality_badges(filename) when is_binary(filename) do
    down = String.downcase(filename)

    Enum.reject(
      [resolution_badge(down), hdr_badge(down), source_badge(down), codec_badge(down)],
      &is_nil/1
    )
  end

  def parse_quality_badges(_), do: []

  defp resolution_badge(down) do
    cond do
      String.contains?(down, "2160p") or String.contains?(down, "4k") or
          String.contains?(down, "uhd") ->
        "4K"

      String.contains?(down, "1080p") ->
        "1080p"

      String.contains?(down, "720p") ->
        "720p"

      String.contains?(down, "480p") ->
        "480p"

      true ->
        nil
    end
  end

  defp hdr_badge(down) do
    cond do
      String.contains?(down, "dolby.vision") or String.contains?(down, "dolbyvision") or
          String.contains?(down, ".dv.") ->
        "DV"

      String.contains?(down, "hdr") ->
        "HDR"

      true ->
        nil
    end
  end

  defp source_badge(down) do
    cond do
      String.contains?(down, "remux") ->
        "REMUX"

      String.contains?(down, "bluray") or String.contains?(down, "blu-ray") or
          String.contains?(down, "bdrip") ->
        "BluRay"

      String.contains?(down, "web-dl") or String.contains?(down, "webrip") or
        String.contains?(down, ".web.") or String.contains?(down, "-web-") ->
        "WEB"

      String.contains?(down, "hdtv") ->
        "HDTV"

      String.contains?(down, "dvdrip") ->
        "DVDRip"

      true ->
        nil
    end
  end

  defp codec_badge(down) do
    cond do
      String.contains?(down, "h265") or String.contains?(down, "h.265") or
        String.contains?(down, "hevc") or String.contains?(down, "x265") ->
        "H265"

      String.contains?(down, "h264") or String.contains?(down, "h.264") or
          String.contains?(down, "x264") ->
        "H264"

      String.contains?(down, "av1") ->
        "AV1"

      true ->
        nil
    end
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
    # Single pass: group by directory and accumulate the total size. The
    # earlier two-pass version traversed `detail_files` once for the
    # group/sort/map chain and again via Enum.reduce just to sum sizes.
    {groups_by_dir, total_size, file_count} =
      Enum.reduce(detail_files, {%{}, 0, 0}, fn %{file: file, size: size}, {acc, total, count} ->
        dir = Path.dirname(file.file_path)

        entry = %{
          path: file.file_path,
          name: Path.basename(file.file_path),
          size: size
        }

        {Map.update(acc, dir, [entry], &[entry | &1]), total + (size || 0), count + 1}
      end)

    file_groups =
      groups_by_dir
      |> Enum.sort_by(fn {dir, _files} -> dir end)
      |> Enum.map(fn {dir, files} ->
        %{
          dir: dir,
          name: Path.basename(dir),
          is_watch_dir: dir in watch_dirs,
          files: Enum.reverse(files)
        }
      end)

    %{file_groups: file_groups, total_size: total_size, file_count: file_count}
  end

  def file_summary(count, total_size) do
    size_str = format_file_size(total_size)
    "#{count} #{if count == 1, do: "file", else: "files"}, #{size_str}"
  end

  @doc """
  Label for the prominent entity-wide delete button. Single-file
  entities read "Delete this file" because "Delete all" reads as
  awkward when there's only one.
  """
  def delete_all_label(1), do: "Delete this file"
  def delete_all_label(_), do: "Delete all files"

  defp delete_all_aria_label(1), do: "Delete the file for this entry"
  defp delete_all_aria_label(_), do: "Delete all files for this entry"

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
