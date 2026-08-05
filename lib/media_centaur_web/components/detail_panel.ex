defmodule MediaCentaurWeb.Components.DetailPanel do
  @moduledoc """
  Shared entity detail content component, rendered inside ModalShell.

  Displays hero (21:9 backdrop), identity (logo/title), metadata, description,
  playback actions (Play/Resume button + progress bar), and type-specific content
  lists (episodes for TV, movies for movie series).
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers

  import MediaCentaurWeb.LibraryFormatters,
    only: [format_type: 1, extract_year: 1, format_human_duration: 1]

  alias MediaCentaur.Library.EpisodeList
  alias MediaCentaur.Library.MovieList
  alias MediaCentaurWeb.Components.Detail.FacetStrip
  alias MediaCentaurWeb.Components.Detail.Hero
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.MoreInfoPanel
  alias MediaCentaurWeb.Components.Detail.PlayCard
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.Orientation

  # --- Public API ---

  # Shared doc strings for the recurring loose-attr shapes in this module.
  # Each points at the typed producer in the data layer (Library) so the
  # contract stays inspectable without exporting internal schemas across
  # the boundary.
  @doc_entity "polymorphic entity-map produced by `MediaCentaur.Library.Views.DetailItem.to_entity_map/1` (Phase 3.2 Task D). Carries the same `:type | :name | :images | :seasons | :movies | :extras | :external_ids | :cast | :crew | :content_url` shape the pre-Phase-3.2 `Library.Browser` preload chain produced — kept as a map (not a typed struct) until the typed-attr migration (Phase 3.3 / component-contracts campaign)."
  @doc_progress "`MediaCentaur.Library.ProgressSummary.t() | nil` — composed at `Library.load_modal_entry/1` from `list_progress_records_for_container/2` (Phase 3.2)."
  @doc_progress_records "list of `MediaCentaur.Library.WatchProgress.t()` rows for the entity's leaves; each carries a synthesised `:playable_item` `(container_type, container_id)` so `EpisodeList.progress_container_id/1` resolves to the leaf UUID."
  @doc_resume "resume target map `%{kind, season, episode, ...} | nil` — see `LibraryProgress.resume_target_for/1`."
  @doc_resume_episode_key "`{season_number, episode_number}` tuple | `nil` — derived from `:resume`."
  @doc_extra_progress_by_id "`%{Ecto.UUID.t() => WatchProgress.t()}` keyed by extra id."
  @doc_detail_files "list of file-info maps (`%{file: KnownFile.t(), entity_id, role, ...}`) built by `LibraryLive.list_files_for_entity/2`."
  @doc_delete_confirm "pending inline-confirm target: `nil` | `:all` | `{:file, path}` | `{:folder, path}`. The host's `delete_*_prompt` handlers compare against this to decide whether the click is the first (set pending) or second (execute). `:any` is intentional — it's a sum type, not a single shape."
  @doc_deleting "in-flight delete target (same sum type as `delete_confirm`): `nil` | `:all` | `{:file, path}` | `{:folder, path}`. Set while the async deletion runs so the matching button shows \"Deleting…\" and all delete buttons disable. Distinct from `delete_confirm` (armed-but-not-yet-running) — see `delete_gesture_state/3`."
  @doc_movie "A movie row inside a `MovieSeries` content list. Either a `MediaCentaur.Library.Movie.t()` or the lean projection map from `DetailItem.movie_entry_to_map/1`. Required keys: `:id`, `:name`, `:date_published`. Optional (read via `Map.get`): `:images`, `:description`, `:duration_seconds`."
  @doc_extra "`MediaCentaur.Library.Extra.t()` (Ecto schema) — TV bonus content."
  @doc_files_list "list of file-info maps — same shape as `:detail_files`."
  @doc_file_info "single file-info map — `%{file: KnownFile.t(), entity_id, role, …}`."

  # --- Main Component ---

  attr :entity, :map, required: true, doc: @doc_entity
  attr :progress, :map, default: nil, doc: @doc_progress
  attr :resume, :map, default: nil, doc: @doc_resume
  attr :progress_records, :list, default: [], doc: @doc_progress_records
  attr :expanded_seasons, MapSet, default: nil

  attr :expanded_episode_details, MapSet,
    default: nil,
    doc:
      "`{season_number, episode_number}` keys of episode rows whose synopsis/thumbnail disclosure is open. Owned by the host modal (`toggle_episode_details`)."

  attr :all_episode_details_open, :boolean,
    default: false,
    doc:
      "list-level episode-details toggle — opens every episode row's synopsis/thumbnail block at once. ORed with `expanded_episode_details`, so per-row disclosures survive turning it off. Owned by the host modal (`toggle_all_episode_details`)."

  attr :available, :boolean, default: true
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main
  attr :detail_files, :list, default: [], doc: @doc_detail_files
  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :deleting, :any, default: nil, doc: @doc_deleting
  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil
  attr :tmdb_ready, :boolean, default: true

  attr :seasons_view, :list,
    default: nil,
    doc:
      "`[%MediaCentaurWeb.ViewModel.SeasonView{}]` typed view-model for the TV-series " <>
        "content list. Required when `entity.type == :tv_series`. Built by " <>
        "`MediaCentaurWeb.ViewModel.SeriesDetail.compose/1`. Each `SeasonView` carries " <>
        "tagged `EpisodeListItem.{Library, Missing, Upcoming}` items the renderer " <>
        "pattern-matches on — no tuple ADTs, no shape-guessing inside the component."

  def detail_panel(assigns) do
    # Which seasons render open is the host modal's call — it seeds the
    # set from `Orientation.initial_expanded_seasons/1` on selection and
    # then owns it through toggle_season (2026-08-05 auto-orient design).
    expanded_seasons = assigns.expanded_seasons || MapSet.new()

    orientation =
      if assigns.entity.type == :tv_series and is_list(assigns.seasons_view) do
        Orientation.build(assigns.seasons_view, assigns.resume)
      end

    progress_by_key = EpisodeList.index_progress_by_key(assigns.progress_records)

    resume_episode_key =
      resume_episode_key(assigns.resume) || progress_episode_key(assigns.progress)

    extra_progress_by_id = index_extra_progress(assigns.entity)

    has_scrollable_content = scrollable_content?(assigns.entity, assigns.detail_view)

    playback = build_playback(assigns)
    facets = build_facets(assigns.entity)
    metadata_items = build_metadata_items(assigns.entity)
    tagline = tagline_for(assigns.entity)

    assigns =
      assigns
      |> assign(:expanded_seasons, expanded_seasons)
      |> assign(:expanded_episode_details, assigns.expanded_episode_details || MapSet.new())
      |> assign(:orientation, orientation)
      |> assign(:season_fraction, orientation && Orientation.season_fraction(orientation))
      |> assign(:autoscroll_resume?, autoscroll_resume?(orientation))
      |> assign(
        :block_backdrop_url,
        assigns.available &&
          (image_url(assigns.entity, "backdrop") || image_url(assigns.entity, "poster"))
      )
      |> assign(
        :description_right?,
        assigns.entity.type in [:movie, :tv_series] && assigns.entity.description not in [nil, ""]
      )
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
      <%!-- Hero window: transparent 21:9 frame the fixed panel-level
            backdrop shows through. Scrolls away; the orientation block
            below overlaps its lower edge at rest (negative margin, see
            .detail-orientation) and pins to the scrollport top. --%>
      <Hero.hero entity={@entity} available={@available}>
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
      <%!-- Orientation block: identity lockup + hairline + metadata +
            play controls + synopsis, pinned as one unit once scrolled
            to the top. Must be a direct child of .detail-panel — a
            wrapper that ends before #detail-content would release the
            sticky early. Same block for every entity type: movies
            simply never scroll enough to pin it. --%>
      <div
        class="detail-orientation"
        data-role="detail-orientation"
        style={@block_backdrop_url && "--detail-backdrop: url('#{@block_backdrop_url}')"}
      >
        <%!-- Opaque backing while pinned: clip window + an image layer
              that rebuilds the panel backdrop's exact box, so the copy
              renders pixel-identical to the backdrop behind it (see
              .orientation-backing in app.css). --%>
        <div class="orientation-backing" aria-hidden="true">
          <div class="orientation-backing-image"></div>
        </div>
        <div class="px-6">
          <TitleLayer.lockup
            title={@entity.name}
            logo_url={(@available && image_url(@entity, "logo")) || nil}
            tagline={@tagline}
          />
        </div>
        <div
          :if={@season_fraction}
          class="season-hairline mt-4"
          role="progressbar"
          aria-valuenow={round(@season_fraction * 100)}
          aria-valuemin="0"
          aria-valuemax="100"
          aria-label="Season progress"
        >
          <div class="season-hairline-fill" style={"width: #{@season_fraction * 100}%"} />
        </div>
        <%!-- pt-6 (vs the p-4 sides): the season hairline sits flush on
              the hero window's bottom edge, so the block below needs
              extra clearance to read as separate from the progress
              track. --%>
        <div class="px-4 pb-4 pt-6">
          <%!-- Two real columns sharing one top line: identity facts +
                play controls on the left, prose (or the movie-series
                facet strip) on the right. The metadata row lives INSIDE
                the left column — as a full-width line above the grid it
                left the buttons alone with dead space while the synopsis
                floated anchorless at mid-page. Catalog facts (network /
                rating / genres / language) live in the More info view,
                not here (2026-08-04 split): the main view is for
                deciding to press Play, not for reference lookup. An
                up-next marquee block was tried in the right column and
                removed — it duplicated the Play button's own label; the
                hero hairline is the only orientation element. Entities
                without a description (or movie-series facets) collapse
                to a single full-width stack. Below xl everything is one
                column, metadata and controls first.
                File paths are intentionally NOT rendered here — they
                live in the Manage view's Files section, grouped by
                directory with delete affordances. --%>
          <%!-- Asymmetric split: the controls row is a fixed-size cluster,
                the prose wants measure — 2/5 vs 3/5 keeps the description
                column from wasting half the panel on a button row's
                worth of content. --%>
          <div class={[
            "space-y-4",
            (@description_right? || @facets != []) &&
              "xl:space-y-0 xl:grid xl:grid-cols-5 xl:gap-8 xl:items-start"
          ]}>
            <div class="space-y-4 min-w-0 xl:col-span-2 xl:col-start-1 xl:row-start-1">
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
                show_more_info={@entity.type in [:movie, :tv_series]}
              />
              <p
                :if={@entity.description && !@description_right?}
                class="text-sm text-base-content/70 line-clamp-8 xl:max-w-[50ch]"
              >
                {@entity.description}
              </p>
            </div>
            <div
              :if={@description_right?}
              class="min-w-0 xl:col-span-3 xl:col-start-3 xl:row-start-1"
            >
              <p class="text-[15px] leading-relaxed text-base-content/75 line-clamp-6 max-w-[72ch]">
                {@entity.description}
              </p>
            </div>
            <div
              :if={@facets != []}
              class="min-w-0 space-y-3 xl:col-span-3 xl:col-start-3 xl:row-start-1"
            >
              <FacetStrip.facet_strip facets={@facets} layout={:row} class="xl:hidden" />
              <FacetStrip.facet_strip facets={@facets} layout={:stacked} class="hidden xl:grid" />
            </div>
          </div>
        </div>
      </div>
      <div
        :if={@has_scrollable_content}
        id="detail-content"
        class="detail-content-slab px-4 pb-5"
        phx-hook="ScrollToResume"
        data-entity-id={@entity.id}
        data-scroll-to-resume={@autoscroll_resume? || nil}
      >
        <%= case @detail_view do %>
          <% :credits -> %>
            <MoreInfoPanel.more_info_panel entity={@entity} />
          <% :info -> %>
            <.info_view
              entity={@entity}
              files={@detail_files}
              rematch_confirm={@rematch_confirm}
              delete_confirm={@delete_confirm}
              deleting={@deleting}
              tmdb_ready={@tmdb_ready}
            />
          <% _ -> %>
            <.content_list
              entity={@entity}
              seasons_view={@seasons_view}
              expanded_seasons={@expanded_seasons}
              expanded_episode_details={@expanded_episode_details}
              all_episode_details_open={@all_episode_details_open}
              progress_by_key={@progress_by_key}
              resume_episode_key={@resume_episode_key}
              extra_progress_by_id={@extra_progress_by_id}
              on_play={@on_play}
              spoiler_free={@spoiler_free}
              available={@available}
            />
        <% end %>
      </div>
    </div>
    """
  end

  # Whether the detail document opens scrolled to its resume target —
  # the sole signal the `ScrollToResume` hook reads.
  #
  # TV asks `Orientation`: an unstarted series expands season 1 but has
  # no position to return to, so it must not scroll even though its E1
  # row still carries `data-resume-target` (that attribute drives the
  # next-up highlight, so it can't double as the scroll signal).
  #
  # Everything else answers true, matching the behaviour that was
  # implicit before this flag existed — a movie-series with nothing
  # watched renders no target row, so the hook finds nothing to scroll
  # to. The default lives here rather than in a view model because
  # movie-series has no `SeriesDetail` equivalent yet; when it gets one
  # (playable-item-versions campaign), this derivation moves there.
  defp autoscroll_resume?(%Orientation{} = orientation), do: Orientation.autoscroll?(orientation)
  defp autoscroll_resume?(nil), do: true

  # --- Header content builders (used in detail_panel/1) ---

  defp build_playback(assigns) do
    {label, target_id} =
      Logic.playback_props(assigns.entity, assigns.resume, assigns.progress)

    # TV series carry their progress in the hero orientation block
    # (hairline + subline), so the PlayCard's percent/remaining row is
    # suppressed (percent 0 hides it). Other types keep the card row.
    {percent, remaining} =
      if assigns.entity.type == :tv_series do
        {0, nil}
      else
        {
          overall_progress_percent(assigns.progress, assigns.entity),
          progress_remaining_text(assigns.progress, assigns.entity)
        }
      end

    %{
      label: label,
      target_id: target_id,
      percent: percent,
      remaining_text: remaining
    }
  end

  # Only movie series still render a facet strip on the main view —
  # movies and TV carry their catalog facts in the More info view
  # (movie series has no More info button yet, so removing its strip
  # would orphan the data; joins the deferred movie-series analog).
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

  defp year_or_nil(%{date_published: %Date{} = date}), do: MediaCentaur.Format.year(date)
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

  defp duration_or_nil(%{duration_seconds: seconds}) when is_integer(seconds) and seconds > 0,
    do: format_human_duration(seconds)

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

  # No :tv_series clause — TV progress lives in the hero orientation
  # block (`ViewModel.Orientation`), not on the PlayCard (2026-08-04).

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
    season_views = assigns.seasons_view || []
    assigns = assign(assigns, :season_views, season_views)

    ~H"""
    <div :if={@season_views != []} class="pt-3 space-y-3">
      <div class="flex justify-end">
        <button
          type="button"
          phx-click="toggle_all_episode_details"
          data-role="episode-details-toggle"
          aria-pressed={to_string(@all_episode_details_open)}
          data-nav-item
          tabindex="0"
          class={[
            "flex items-center gap-1.5 text-xs cursor-pointer rounded-md px-2 py-1 -my-1 transition-colors hover:bg-base-content/10",
            if(@all_episode_details_open,
              do: "text-base-content/70",
              else: "text-base-content/40 hover:text-base-content/70"
            )
          ]}
        >
          <.icon name="hero-bars-3-bottom-left-mini" class="size-3.5" />
          {if @all_episode_details_open, do: "Hide details", else: "Show details"}
        </button>
      </div>
      <.season_section
        :for={season_view <- @season_views}
        season={season_view}
        expanded={MapSet.member?(@expanded_seasons, season_view.season_number)}
        expanded_episode_details={@expanded_episode_details}
        all_episode_details_open={@all_episode_details_open}
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

  attr :season, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.SeasonView{}` — typed season bucket."

  attr :expanded, :boolean, required: true

  attr :expanded_episode_details, MapSet,
    default: nil,
    doc: "`{season_number, episode_number}` keys with open synopsis disclosures."

  attr :all_episode_details_open, :boolean,
    default: false,
    doc: "list-level episode-details toggle — ORed with `expanded_episode_details` per row."

  attr :extra_progress_by_id, :map, default: %{}, doc: @doc_extra_progress_by_id
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  defp season_section(assigns) do
    ~H"""
    <div>
      <button
        phx-click="toggle_season"
        phx-value-season={@season.season_number}
        class="flex items-baseline gap-2 w-full text-sm font-medium text-base-content/70 hover:text-base-content cursor-pointer"
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4 self-center"
        />
        <span>{@season.name || "Season #{@season.season_number}"}</span>
        <span class="flex-1" />
        <span
          :if={@season.kind == :library && !season_complete?(@season)}
          class="text-xs text-base-content/40 tabular-nums"
        >
          {season_progress_label(@season.watched_count, @season.total_count)}
        </span>
        <.icon
          :if={@season.kind == :library && season_complete?(@season)}
          name="hero-check-mini"
          class="size-3.5 self-center text-success"
        />
        <span :if={@season.kind == :future} class="text-xs text-base-content/40">
          upcoming
        </span>
      </button>

      <div :if={@expanded} class="mt-1">
        <.season_item
          :for={item <- @season.items}
          item={item}
          details_open={
            @all_episode_details_open ||
              MapSet.member?(
                @expanded_episode_details || MapSet.new(),
                {@season.season_number, item_episode_number(item)}
              )
          }
          entity_id={@entity_id}
          on_play={@on_play}
          spoiler_free={@spoiler_free}
          available={@available}
        />
        <.season_extras
          extras={@season.extras || []}
          extra_progress_by_id={@extra_progress_by_id}
          entity_id={@entity_id}
          on_play={@on_play}
        />
      </div>
    </div>
    """
  end

  # --- Season item dispatch ---
  #
  # Pattern-matches on the `EpisodeListItem` struct type. No tuple
  # ADTs, no shape-guessing — the typed contract IS the dispatch
  # criterion.

  attr :item, :map, required: true, doc: "%EpisodeListItem.{Library | Missing | Upcoming}{}"
  attr :details_open, :boolean, default: false
  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  defp season_item(%{item: %EpisodeListItem.Library{}} = assigns) do
    ~H"""
    <.episode_row
      item={@item}
      details_open={@details_open}
      entity_id={@entity_id}
      on_play={@on_play}
      spoiler_free={@spoiler_free}
      available={@available}
    />
    """
  end

  defp season_item(%{item: %EpisodeListItem.Missing{}} = assigns) do
    ~H"""
    <.missing_episode_row item={@item} />
    """
  end

  defp season_item(%{item: %EpisodeListItem.Upcoming{}} = assigns) do
    ~H"""
    <.upcoming_episode_row item={@item} />
    """
  end

  # --- Episode Row ---

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Library{}` — typed library episode."

  attr :details_open, :boolean,
    default: false,
    doc: "whether the synopsis/thumbnail disclosure below the dense row is open."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, default: false
  attr :available, :boolean, default: true

  # Dense one-line row (2026-08-04 orientation design): number · title ·
  # runtime · watched toggle. Synopsis + thumbnail render only behind the
  # per-row disclosure — the list is an index, not a reading surface.
  defp episode_row(assigns) do
    assigns =
      assigns
      |> assign(:episode, assigns.item.episode)
      |> assign(:season_number, assigns.item.season_number)
      |> assign(:progress, assigns.item.progress)
      |> assign(:state, assigns.item.state)
      |> assign(:is_resume_target, assigns.item.is_resume_target)
      |> assign(:thumbnail, image_url(assigns.item.episode, "thumb"))

    ~H"""
    <div
      class={[
        "px-2 py-1.5 rounded cursor-pointer hover:bg-base-content/5",
        episode_row_class(@state, @is_resume_target)
      ]}
      data-role="episode-row"
      data-resume-target={@is_resume_target || nil}
      phx-click={@on_play}
      phx-value-id={@episode.id}
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/50 font-mono text-xs tabular-nums">
          {@episode.episode_number}
        </span>
        <span class={[
          "flex-1 min-w-0 truncate text-base-content/90",
          blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
        ]}>
          {@episode.name || "—"}
        </span>
        <button
          :if={@episode.description || @thumbnail}
          type="button"
          phx-click="toggle_episode_details"
          phx-value-season={@season_number}
          phx-value-episode={@episode.episode_number}
          data-nav-sub-item
          class="flex-shrink-0 p-1.5 -m-1 rounded-md cursor-pointer text-base-content/30 hover:text-base-content/70 hover:bg-base-content/10 transition-colors"
          aria-expanded={to_string(@details_open)}
          aria-label={if @details_open, do: "Hide episode details", else: "Show episode details"}
        >
          <.icon
            name={if @details_open, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
            class="size-4"
          />
        </button>
        <.watched_toggle
          event="toggle_watched"
          state={@state}
          progress={@progress}
          duration_seconds={@episode.duration_seconds}
          phx-value-entity-id={@entity_id}
          phx-value-season={@season_number}
          phx-value-episode={@episode.episode_number}
        />
      </div>
      <div :if={@details_open} class="mt-2 ml-9 mb-1 flex items-start gap-3">
        <img
          :if={@thumbnail && @available}
          src={sized_image_url(@thumbnail, 240)}
          class={[
            "w-28 aspect-video rounded object-cover object-top flex-shrink-0",
            blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
          ]}
        />
        <p
          :if={@episode.description}
          class={[
            "text-xs text-base-content/50 leading-relaxed",
            blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
          ]}
        >
          {@episode.description}
        </p>
      </div>
      <div
        :if={@state == :current}
        class="mt-1 ml-9 h-0.5 rounded-full bg-base-content/10 overflow-hidden"
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

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Missing{}`"

  defp missing_episode_row(assigns) do
    ~H"""
    <div
      class="p-2 rounded opacity-30"
      data-role="missing-episode-row"
      data-nav-item
      tabindex="0"
    >
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/40 font-mono text-xs tabular-nums">
          {@item.episode_number}
        </span>
        <span class="flex-1 min-w-0 truncate text-base-content/70 italic">
          Episode {@item.episode_number}
        </span>
      </div>
    </div>
    """
  end

  # --- Upcoming Episode Row ---
  #
  # Visual contract (per `defaults/storybook` `:tv_series_with_upcoming_inline`
  # and siblings): muted opacity, no thumbnail, no description, no
  # watched toggle, no `phx-click` (not actionable in v1). Right-side
  # date pill carries the air-date copy. `data-nav-item` is omitted —
  # the row isn't focusable until it becomes clickable.

  attr :item, :map,
    required: true,
    doc: "`%MediaCentaurWeb.ViewModel.EpisodeListItem.Upcoming{}`"

  defp upcoming_episode_row(assigns) do
    ~H"""
    <div class="p-2 rounded opacity-60" data-role="upcoming-episode-row">
      <div class="flex items-center gap-3 text-sm">
        <span class="w-6 flex-shrink-0 text-right text-base-content/40 font-mono text-xs tabular-nums">
          {@item.episode_number}
        </span>
        <span class="flex-1 min-w-0 truncate text-base-content/70">
          {@item.title || "Episode #{@item.episode_number}"}
        </span>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.badge variant="ghost" size="sm" class="gap-1">
            <.icon name="hero-calendar-mini" class="size-3" />
            {upcoming_pill_copy(@item)}
          </.badge>
        </div>
      </div>
    </div>
    """
  end

  defdelegate episode_state(progress),
    to: MediaCentaur.Library.EpisodeList,
    as: :state_from_progress

  @doc """
  Pill copy for an upcoming-episode row. Past dates read
  "aired Xd ago"; future dates read "in Xd" (or the bare formatted
  date for further-out releases). `nil` air_date renders "TBA".

  Pure: extracted for unit testing without LiveView render.
  """
  @spec upcoming_pill_copy(map(), Date.t()) :: String.t()
  def upcoming_pill_copy(item, today \\ Date.utc_today())

  def upcoming_pill_copy(%{air_date: nil}, _today), do: "TBA"

  def upcoming_pill_copy(%{air_date: %Date{} = air_date}, today) do
    days = Date.diff(air_date, today)

    cond do
      days == 0 -> "today"
      days > 0 and days <= 14 -> "in #{days}d"
      days < 0 and days >= -14 -> "aired #{abs(days)}d ago"
      true -> Calendar.strftime(air_date, "%b %-d")
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

  defp episode_duration_text(%{duration_seconds: seconds} = assigns)
       when is_integer(seconds) and seconds > 0 do
    ~H"""
    <span class="text-base-content/40 text-xs">
      {format_human_duration(@duration_seconds)}
    </span>
    """
  end

  defp episode_duration_text(assigns) do
    ~H"""
    """
  end

  # Note: the `group-hover/toggle:` classes below depend on the toggle
  # button carrying `group/toggle` (set by `watched_toggle_button_class/0`).
  # Any caller that bypasses `watched_toggle/1` and renders this circle
  # directly must include `group/toggle` on the wrapping click target,
  # or the hover-preview check silently breaks with no test failure.
  defp watched_circle_class(:watched), do: "bg-success group-hover/toggle:bg-success/70"

  defp watched_circle_class(_),
    do: "border border-base-content/20 group-hover/toggle:border-base-content/50"

  # Layout + hover styling for the watched/unwatched toggle button. The
  # button wraps ONLY the state circle — the duration/remaining text is a
  # sibling outside it (in `watched_toggle/1`) so a click on that
  # informational text falls through to the row's play handler rather than
  # toggling watched state. Padding (`p-1.5`) with a cancelling negative
  # margin keeps the circle's click/focus target comfortably larger than
  # the 20px dot (UIDR-003) without affecting layout or reaching the text.
  defp watched_toggle_button_class do
    [
      "group/toggle flex items-center flex-shrink-0 cursor-pointer",
      "p-1.5 -m-1.5 rounded-md transition-colors",
      "hover:bg-base-content/10"
    ]
  end

  # Shared watched/unwatched toggle button. Used by episode, movie, and
  # extra rows — the only per-call differences are the `phx-click`
  # event name and the `phx-value-*` attributes (forwarded via the
  # `:rest` global). Keeping all three call sites on one component
  # prevents the hover/state styling from drifting between row types.
  attr :event, :string, required: true
  attr :state, :atom, required: true, values: [:watched, :current, :unwatched]

  attr :progress, :map,
    default: nil,
    doc:
      "`MediaCentaur.Library.WatchProgress.t() | nil` — passed through to `episode_duration_text/1` to render the remaining time in the `:current` state."

  attr :duration_seconds, :integer, default: nil

  attr :rest, :global,
    doc:
      "`phx-value-*` attributes that identify the toggle target (entity/season/episode for `toggle_watched`, entity/extra for `toggle_extra_watched`).",
    include: ~w(phx-value-entity-id phx-value-season phx-value-episode phx-value-extra-id)

  defp watched_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-2 flex-shrink-0">
      <.episode_duration_text
        state={@state}
        progress={@progress}
        duration_seconds={@duration_seconds}
      />
      <button
        type="button"
        phx-click={@event}
        data-nav-sub-item
        class={watched_toggle_button_class()}
        aria-label={if @state == :watched, do: "Mark unwatched", else: "Mark watched"}
        {@rest}
      >
        <span class={[
          "size-5 rounded-full flex items-center justify-center transition-all",
          watched_circle_class(@state)
        ]}>
          <.icon
            :if={@state == :watched}
            name="hero-check-mini"
            class="size-3 text-success-content"
          />
          <.icon
            :if={@state != :watched}
            name="hero-check-mini"
            class="size-3 opacity-0 group-hover/toggle:opacity-60 transition-opacity"
          />
        </span>
      </button>
    </div>
    """
  end

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
    doc: "`MediaCentaur.Library.WatchProgress.t() | nil` for this movie."

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
      # `description` / `duration_seconds` are optional display fields. The
      # movie_series projection map (`DetailItem.movie_entry_to_map/1`)
      # omits them, so read via `Map.get` — a bare dot-access raises
      # `KeyError` on the missing key and crashes the whole panel render.
      |> assign(:description, Map.get(assigns.movie, :description))
      |> assign(:duration_seconds, Map.get(assigns.movie, :duration_seconds))

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
            src={sized_image_url(@thumbnail, 160)}
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
            :if={@description}
            class={[
              "line-clamp-2 text-xs text-base-content/50",
              blur_spoilers?(@spoiler_free, @state) && "spoiler-blur"
            ]}
          >
            {@description}
          </p>
        </div>
        <.watched_toggle
          event="toggle_watched"
          state={@state}
          progress={@progress}
          duration_seconds={@duration_seconds}
          phx-value-entity-id={@entity_id}
          phx-value-season="0"
          phx-value-episode={@ordinal}
        />
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
    doc: "`MediaCentaur.Library.WatchProgress.t() | nil` for this extra."

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
        <.watched_toggle
          event="toggle_extra_watched"
          state={@state}
          progress={@progress}
          phx-value-entity-id={@entity_id}
          phx-value-extra-id={@extra.id}
        />
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

  @doc """
  Whether the detail modal's content region scrolls — TV / movie-series
  lists, entity-level extras, or the Manage / More info sub-views.

  Shared with `ModalShell`, which pins the panel at its full height for
  scrollable entries (`.modal-panel--full`): the season accordion then
  changes only the inner scroll, never the panel geometry — otherwise
  the backdrop (sized against the panel, `object-fit: cover`) re-crops
  on every toggle and the transition jars.
  """
  @spec scrollable_content?(map(), atom()) :: boolean()
  def scrollable_content?(entity, detail_view) do
    detail_view in [:info, :credits] ||
      entity.type in [:tv_series, :movie_series] ||
      entity_extras(entity) != []
  end

  defp entity_extras(%{extras: extras}) when is_list(extras) do
    # Surface only entity-level extras (not season-owned ones); season
    # extras are rendered next to their season elsewhere in the panel.
    Enum.reject(extras, &(&1.owner_type == :season))
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
  attr :deleting, :any, default: nil, doc: @doc_deleting
  attr :tmdb_ready, :boolean, default: true

  defp info_view(assigns) do
    total_size = Enum.reduce(assigns.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)
    file_count = length(assigns.files)

    external_ids =
      if is_list(assigns.entity.external_ids), do: assigns.entity.external_ids, else: []

    media_dirs = MapSet.new(MediaCentaur.Config.get(:media_dirs) || [])
    file_groups = build_file_groups(assigns.files, media_dirs)

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
            button never appears for the media_dir itself — deleting a
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
            disabled={delete_in_flight?(@deleting)}
            data-nav-item
            tabindex="0"
            aria-label={delete_all_aria_label(@file_count)}
          >
            <.icon name="hero-trash-mini" class="size-4" />
            <%= case delete_gesture_state(:all, @deleting, @delete_confirm) do %>
              <% :deleting -> %>
                Deleting… {delete_all_label(@file_count)} ({format_file_size(@total_size)})
              <% :confirm -> %>
                Click again to confirm — {delete_all_label(@file_count)} ({format_file_size(
                  @total_size
                )})
              <% :idle -> %>
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
                :if={!group.is_media_dir}
                variant="destructive_inline"
                size="xs"
                disabled={delete_in_flight?(@deleting)}
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
                <%= case delete_gesture_state({:folder, group.dir}, @deleting, @delete_confirm) do %>
                  <% :deleting -> %>
                    Deleting…
                  <% :confirm -> %>
                    Click again to confirm
                  <% :idle -> %>
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
                deleting={@deleting}
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
          <.button
            :if={@tmdb_ready}
            variant="neutral"
            size="sm"
            phx-click="refresh_artwork"
            phx-value-id={@entity.id}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-photo-mini" class="size-4" /> Refresh artwork
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

  attr :ext_id, :map, required: true, doc: "`MediaCentaur.Library.ExternalId.t()`"
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

  attr :deleting, :any, default: nil, doc: @doc_deleting

  defp file_row(assigns) do
    file = assigns.file_info.file
    size = assigns.file_info.size
    absent = is_nil(size)
    filename = Path.basename(file.file_path)
    badges = parse_quality_badges(filename)
    added_at = Map.get(file, :inserted_at)
    gesture = delete_gesture_state({:file, file.file_path}, assigns.deleting, assigns.delete_confirm)

    assigns =
      assigns
      |> assign(:file_path, file.file_path)
      |> assign(:filename, filename)
      |> assign(:size, size)
      |> assign(:absent, absent)
      |> assign(:badges, badges)
      |> assign(:added_at, added_at)
      |> assign(:gesture, gesture)
      |> assign(:is_pending, gesture == :confirm)
      |> assign(:is_deleting, gesture == :deleting)
      |> assign(:delete_in_flight, delete_in_flight?(assigns.deleting))

    ~H"""
    <div class={[
      "text-sm rounded p-2",
      @absent && "opacity-60",
      if(@is_pending or @is_deleting,
        do: "bg-error/15 ring-1 ring-error/40",
        else: "bg-base-content/5"
      )
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
          disabled={@delete_in_flight}
          class={[
            "min-h-0 flex-shrink-0",
            if(@is_pending or @is_deleting,
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
          <span :if={@is_deleting}>Deleting…</span>
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
  Returns a list of `%{dir, name, files, is_media_dir}` maps.
  """
  def build_file_groups(files, media_dirs) do
    files
    |> Enum.group_by(fn %{file: file} -> Path.dirname(file.file_path) end)
    |> Enum.sort_by(fn {dir, _files} -> dir end)
    |> Enum.map(fn {dir, dir_files} ->
      %{dir: dir, name: Path.basename(dir), files: dir_files, is_media_dir: dir in media_dirs}
    end)
  end

  @doc """
  Builds the payload for the "Delete All" confirmation modal.
  Returns `%{file_groups, total_size, file_count}` where each group has
  `%{dir, name, is_media_dir, files}` with files as `%{path, name, size}` maps.
  """
  def build_delete_all_payload(detail_files, media_dirs) do
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
          is_media_dir: dir in media_dirs,
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

  # `delete_gesture_state/3` and `delete_in_flight?/1` moved to
  # `MediaCentaurWeb.LiveHelpers` (imported above) — shared with
  # `ReviewLive`'s delete gesture rather than duplicated here.

  @doc """
  Whether an episode's thumbnail, title and synopsis should be spoiler-blurred:
  only when spoiler-free mode is on *and* the episode is fully unwatched. A
  watched or in-progress episode is never blurred (the user has already started
  it), and nothing blurs when spoiler-free mode is off.
  """
  @spec blur_spoilers?(boolean(), atom()) :: boolean()
  def blur_spoilers?(spoiler_free, state), do: spoiler_free and state == :unwatched

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

  # --- Helpers ---

  # A complete season shows only the check icon — no "watched" label
  # next to it (the label renders exclusively for incomplete seasons).
  defp season_complete?(%{watched_count: watched, total_count: total}),
    do: watched == total and (total || 0) > 0

  defp season_progress_label(watched, total), do: "#{total - watched} remaining"

  # Episode number across the EpisodeListItem variants — Library nests it
  # on the episode struct; Missing/Upcoming carry it directly.
  defp item_episode_number(%EpisodeListItem.Library{episode: episode}), do: episode.episode_number

  defp item_episode_number(%{episode_number: episode_number}), do: episode_number

  defp resume_episode_key(%{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode) do
    {season, episode}
  end

  defp resume_episode_key(_), do: nil

  defp progress_episode_key(%{current_episode: %{season: season, episode: episode}})
       when is_integer(season) and is_integer(episode), do: {season, episode}

  defp progress_episode_key(_), do: nil
end
