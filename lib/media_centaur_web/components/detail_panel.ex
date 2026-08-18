defmodule MediaCentaurWeb.Components.DetailPanel do
  @moduledoc """
  The library detail modal — the library tenant of
  `MediaCentaurWeb.Components.CinematicShell`.

  The frame (modal shell, panel-fixed backdrop, scrollport, sticky
  orientation wrapper + backing replica, body sheet) belongs to
  `CinematicShell`; this module fills its slots with the library
  subject's content: the identity lockup + hairline + metadata + play
  controls + synopsis in the pinned block, the tracking bell in the hero
  window, and the type-dependent dispatch of the scrolling body —
  `Detail.SeasonList` (TV), `Detail.ExtrasSection` (leaves and
  collections with bonus content), plus the Cast and Manage sub-views.
  Row-level rendering lives in those modules; shared row chrome in
  `Detail.PlayableRow`.

  ## The subject (UIDR-023)

  For a movie collection the panel's *subject* is the selected member
  movie, composed as a `:movie`-shaped map by
  `MediaCentaurWeb.ViewModel.CollectionDetail.member_subject/1` and
  handed in via `:member_view`. Identity, playback, synopsis and Cast
  all render from the subject through the same components a standalone
  movie uses — one component family, no collection fork. The collection
  itself keeps the collection-scoped surfaces (Manage, extras,
  tracking bell) and contributes the `Detail.CollectionRail` picker.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers

  import MediaCentaurWeb.LibraryFormatters,
    only: [format_type: 1, format_human_duration: 1]

  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.CastPanel
  alias MediaCentaurWeb.Components.Detail.CastSelection
  alias MediaCentaurWeb.Components.Detail.CollectionRail
  alias MediaCentaurWeb.Components.Detail.ExtrasSection
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.ManagePanel
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.PlayableRow
  alias MediaCentaurWeb.Components.Detail.PlayCard
  alias MediaCentaurWeb.Components.Detail.SeasonList
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Detail.ViewControls
  alias MediaCentaurWeb.Components.ProgressHairline
  alias MediaCentaurWeb.ViewModel.Orientation

  # --- Public API ---

  # Shared doc strings for the recurring loose-attr shapes in this module.
  # Each points at the typed producer in the data layer (Library) so the
  # contract stays inspectable without exporting internal schemas across
  # the boundary.
  @doc_entity "polymorphic entity-map produced by `MediaCentaur.Library.Views.DetailItem.to_entity_map/1` (Phase 3.2 Task D). Carries the same `:type | :name | :images | :seasons | :movies | :extras | :external_ids | :cast | :crew | :content_url` shape the pre-Phase-3.2 `Library.Browser` preload chain produced — kept as a map (not a typed struct) until the typed-attr migration (Phase 3.3 / component-contracts campaign)."
  @doc_progress "`MediaCentaur.Library.ProgressSummary.t() | nil` — composed at `Library.ModalEntry.load/1` from `list_progress_records_for_container/2` (Phase 3.2)."
  @doc_progress_records "list of `MediaCentaur.Library.WatchProgress.t()` rows for the entity's leaves; each carries a synthesised `:playable_item` `(container_type, container_id)` so `EpisodeList.progress_container_id/1` resolves to the leaf UUID."
  @doc_resume "resume target map `%{kind, season, episode, ...} | nil` — see `LibraryProgress.resume_target_for/1`."
  @doc_detail_files "list of file-info maps (`%{file: KnownFile.t(), entity_id, role, ...}`) built by `LibraryLive.list_files_for_entity/2`."
  @doc_delete_confirm "pending inline-confirm target: `nil` | `:all` | `{:file, path}` | `{:folder, path}`. The host's `delete_*_prompt` handlers compare against this to decide whether the click is the first (set pending) or second (execute). `:any` is intentional — it's a sum type, not a single shape."
  @doc_deleting "in-flight delete target (same sum type as `delete_confirm`): `nil` | `:all` | `{:file, path}` | `{:folder, path}`. Set while the async deletion runs so the matching button shows \"Deleting…\" and all delete buttons disable. Distinct from `delete_confirm` (armed-but-not-yet-running) — see `delete_gesture_state/3`."

  # --- Main Component ---

  attr :open, :boolean, default: false

  attr :entity, :map,
    default: nil,
    doc: "#{@doc_entity} `nil` renders the closed shell (no subject loaded)."

  attr :progress, :map, default: nil, doc: @doc_progress
  attr :resume, :map, default: nil, doc: @doc_resume
  attr :progress_records, :list, default: [], doc: @doc_progress_records
  attr :expanded_seasons, MapSet, default: nil

  attr :expanded_item_details, MapSet,
    default: nil,
    doc:
      "leaf container ids of content rows whose synopsis disclosure is open — one key space for episodes and collection movies alike. Owned by the host modal (`toggle_item_details`)."

  attr :all_episode_details_open, :boolean,
    default: false,
    doc:
      "list-level episode-details toggle — opens every episode row's synopsis/thumbnail block at once. ORed with `expanded_item_details`, so per-row disclosures survive turning it off. Owned by the host modal (`toggle_all_episode_details`)."

  attr :available, :boolean, default: true
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_detail"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main

  attr :cast_filter, :string,
    default: "",
    doc: "current Cast-view filter query; forwarded to the cast grid."

  attr :cast_limit, :integer,
    default: nil,
    doc:
      "how many cast matches the Cast view renders; forwarded to the cast grid. `nil` falls back to one page."

  attr :detail_files, :list, default: [], doc: @doc_detail_files

  attr :expanded_file_groups, :any,
    default: nil,
    doc:
      "forwarded to `ManagePanel.manage_panel/1` as `:expanded_groups` — `MapSet.t()` of expanded folder dirs, or `nil` for its automatic default."

  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :deleting, :any, default: nil, doc: @doc_deleting
  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil
  attr :tmdb_ready, :boolean, default: true

  attr :letterboxd_links, :boolean,
    default: true,
    doc:
      "the `letterboxd_links` setting — whether a movie subject's hero shows the Letterboxd page link."

  attr :watchlisted?, :boolean,
    default: false,
    doc:
      "whether the panel's subject is on the watchlist — forwarded to the view controls' bookmark toggle. Compute via `EntityModal.watchlisted?/3`."

  attr :seasons_view, :list,
    default: nil,
    doc:
      "`[%MediaCentaurWeb.ViewModel.SeasonView{}]` typed view-model for the TV-series " <>
        "content list. Required when `entity.type == :tv_series`. Built by " <>
        "`MediaCentaurWeb.ViewModel.SeriesDetail.compose/1`. Each `SeasonView` carries " <>
        "tagged `EpisodeListItem.{Library, Missing, Upcoming}` items the renderer " <>
        "pattern-matches on — no tuple ADTs, no shape-guessing inside the component."

  attr :movies_view, :list,
    default: nil,
    doc:
      "`[%MediaCentaurWeb.ViewModel.MovieListItem{}]` typed view-model for the " <>
        "movie-collection poster rail. Required when `entity.type == :movie_series`. " <>
        "Built by `MediaCentaurWeb.ViewModel.CollectionDetail.compose/1`. Tagged " <>
        "`MovieListItem.{Library, Upcoming}` items the rail pattern-matches on — " <>
        "the collection counterpart of `:seasons_view`."

  attr :member_view, :any,
    default: nil,
    doc:
      "`%{member, subject}` from `MediaCentaurWeb.Live.EntityModal.member_view/2`, " <>
        "or `nil` for non-collection entities. When present, the pinned block renders the " <>
        "member `subject` (a `:movie`-shaped map) through the same components a standalone " <>
        "movie uses — UIDR-023's one-component-family rule — plus the poster rail."

  # No subject loaded: the bare frame stays in the DOM (closed) so the
  # blur compositing layer keeps warm — same reason the frame itself is
  # always-in-DOM.
  def detail_panel(%{entity: nil} = assigns) do
    ~H"""
    <CinematicShell.cinematic_shell
      id="detail-modal"
      open={false}
      dismiss={:ephemeral}
      on_close={@on_close}
    />
    """
  end

  def detail_panel(assigns) do
    # Which seasons render open is the host modal's call — it seeds the
    # set from `Orientation.initial_expanded_seasons/1` on selection and
    # then owns it through toggle_season (2026-08-05 auto-orient design).
    expanded_seasons = assigns.expanded_seasons || MapSet.new()

    # The panel's subject: the entity itself, except in a collection,
    # where it is the selected member composed as a `:movie`-shaped map
    # (UIDR-023). Every identity/playback/cast component below reads the
    # subject, so a member renders through exactly the components a
    # standalone movie does. Collection-scoped concerns (Manage, extras,
    # tracking) keep reading `@entity`.
    member_view = if assigns.entity.type == :movie_series, do: assigns.member_view
    subject = if member_view, do: member_view.subject, else: assigns.entity

    # TV keeps its orientation (hairline fraction + autoscroll).
    # Collections don't build one — saga state lives on the poster rail;
    # the hero hairline reads the *subject's* fraction (UIDR-024).
    orientation =
      if assigns.entity.type == :tv_series and is_list(assigns.seasons_view) do
        Orientation.for_series(assigns.seasons_view, assigns.resume)
      end

    resume_episode_key =
      resume_episode_key(assigns.resume) || progress_episode_key(assigns.progress)

    extra_progress_by_id = index_extra_progress(assigns.entity)

    has_scrollable_content = scrollable_content?(assigns.entity, assigns.detail_view)

    playback =
      if member_view do
        Logic.member_playback(member_view.member)
      else
        build_playback(assigns)
      end

    # UIDR-024: every subject carries its watched fraction in the hero
    # hairline — TV the series', a movie or member its own — and the
    # remaining time is a metadata-line item, not card-row copy. The
    # remaining item displaces the status while it exists: a title you
    # are 75% through is self-evidently released.
    hairline_fraction = if orientation, do: orientation.fraction, else: playback.percent / 100
    metadata_remaining = if !orientation, do: playback.remaining_text

    metadata_items = build_metadata_items(subject, metadata_remaining)
    tagline = tagline_for(subject)

    # The view control's destination logic wants the subject's cast (the
    # Cast view shows the member) but the *collection's* extras (the
    # body below the rail shows those) — a subject that answers for the
    # whole page structure.
    controls_entity =
      if member_view do
        Map.put(subject, :extras, Logic.entity_extras(assigns.entity))
      else
        subject
      end

    description_right? = subject.type in [:movie, :tv_series] && subject.description not in [nil, ""]

    backdrop_url =
      if assigns.available do
        # Subject art first, entity art as the ladder's next rungs
        # (UIDR-021): a member movie rarely carries its own backdrop, so
        # a collection usually frames its members in collection art.
        image_url(subject, "backdrop") || image_url(assigns.entity, "backdrop") ||
          image_url(subject, "poster") || image_url(assigns.entity, "poster")
      end

    assigns =
      assigns
      |> assign(:expanded_seasons, expanded_seasons)
      |> assign(:expanded_item_details, assigns.expanded_item_details || MapSet.new())
      |> assign(:member_view, member_view)
      |> assign(:subject, subject)
      |> assign(:controls_entity, controls_entity)
      |> assign(:orientation, orientation)
      |> assign(:hairline_fraction, hairline_fraction)
      |> assign(:hairline_label, hairline_label(subject))
      |> assign(:metadata_remaining, metadata_remaining)
      |> assign(:autoscroll_resume?, autoscroll_resume?(orientation))
      |> assign(:backdrop_url, backdrop_url)
      |> assign(:description_right?, description_right?)
      |> assign(
        :cast_filter_in_header?,
        assigns.detail_view == :cast && description_right? &&
          CastSelection.show_filter?(subject[:cast] || [])
      )
      |> assign(:resume_episode_key, resume_episode_key)
      |> assign(:extra_progress_by_id, extra_progress_by_id)
      |> assign(:has_scrollable_content, has_scrollable_content)
      |> assign(:playback, playback)
      |> assign(:metadata_items, metadata_items)
      |> assign(:tagline, tagline)

    ~H"""
    <CinematicShell.cinematic_shell
      id="detail-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      present
      full={@has_scrollable_content}
      backdrop_url={@backdrop_url}
      scroll_key={@entity.id}
      view_key={@detail_view}
      scroll_to_resume={@autoscroll_resume?}
      data-detail-mode={@open && "modal"}
      data-detail-nested={@open && to_string(Logic.nested_view?(@entity, @detail_view))}
      data-nav-overlay={@open && "detail"}
    >
      <:hero_actions :if={@tracking_status}>
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
      </:hero_actions>
      <%!-- The pinned block's content: identity lockup + hairline +
            metadata + play controls + synopsis. The sticky wrapper and
            its backdrop backing belong to the frame (CinematicShell).
            Same block for every entity type: movies simply never scroll
            enough to pin it. --%>
      <:orientation>
        <div class="px-6">
          <TitleLayer.lockup
            title={@subject.name}
            logo_url={(@available && image_url(@subject, "logo")) || nil}
            tagline={@tagline}
          />
        </div>
        <ProgressHairline.progress_hairline
          fraction={@hairline_fraction}
          label={@hairline_label}
          class="mt-4"
        />
        <%!-- pt-6 (vs the p-4 sides): the progress hairline sits flush on
              the hero window's bottom edge, so the block below needs
              extra clearance to read as separate from the progress
              track. Bottom padding is two different distances: against a
              content list below (TV, collections) it is internal rhythm
              and stays tight; on a content-fit panel (bare movie) it is
              the clearance between the synopsis and the panel's rounded
              bottom edge, which needs real breathing room. --%>
        <div class={["px-4 pt-6", (@has_scrollable_content && "pb-4") || "pb-8"]}>
          <%!-- Two real columns sharing one top line: identity facts +
                play controls on the left, prose (or the movie-series
                facet strip) on the right. The metadata row lives INSIDE
                the left column — as a full-width line above the grid it
                left the buttons alone with dead space while the synopsis
                floated anchorless at mid-page. Catalog facts (network /
                rating / genres / language) were dropped from the modal
                with the Cast view (2026-08-08); the main view is for
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
            @description_right? && "xl:space-y-0 xl:grid xl:grid-cols-5 xl:gap-8 xl:items-start"
          ]}>
            <div class="space-y-4 min-w-0 xl:col-span-2 xl:col-start-1 xl:row-start-1">
              <MetadataRow.metadata_row
                badge_text={format_type(@subject.type)}
                items={@metadata_items}
                remaining_text={@metadata_remaining}
              />
              <PlayCard.play_card
                on_play={@on_play}
                target_id={@playback.target_id}
                label={@playback.label}
                available={@available}
              >
                <:controls>
                  <ViewControls.view_controls
                    entity={@controls_entity}
                    detail_view={@detail_view}
                    letterboxd_links={@letterboxd_links}
                    watchlisted?={@watchlisted?}
                  />
                  <%!-- Member watched toggle: acting on the *selected*
                        movie is what the movie-first modal is for, and
                        Play's line is the one place every input method
                        reaches (UIDR-023 — a per-tile toggle on the rail
                        is the deferred graft). Far right with its label,
                        away from the play cluster; a first-class nav
                        item so the toolbar walk reaches it. --%>
                  <span :if={@member_view} class="ml-auto flex items-center gap-2">
                    <span class="text-xs text-base-content/40">Watched</span>
                    <PlayableRow.watched_toggle
                      event="toggle_watched"
                      state={@member_view.member.state}
                      progress={@member_view.member.progress}
                      duration_seconds={Map.get(@member_view.member.movie, :duration_seconds)}
                      show_duration={false}
                      nav_item
                      phx-value-entity-id={@entity.id}
                      phx-value-container-type="movie"
                      phx-value-container-id={@member_view.member.movie.id}
                    />
                  </span>
                </:controls>
              </PlayCard.play_card>
              <p
                :if={@subject.description && !@description_right?}
                class="text-sm text-base-content/70 line-clamp-8 xl:max-w-[50ch]"
              >
                {@subject.description}
              </p>
            </div>
            <div
              :if={@description_right?}
              class="min-w-0 xl:col-span-3 xl:col-start-3 xl:row-start-1"
            >
              <p class="text-[15px] leading-relaxed text-base-content/75 line-clamp-6 max-w-[72ch]">
                {@subject.description}
              </p>
              <%!-- Cast-view only: the filter lives here, in the pinned
                    orientation block, rather than in the scrolling sheet —
                    it fills the slack under the synopsis and stays reachable
                    however deep the grid is scrolled. cast_panel renders its
                    own inline fallback when this column doesn't exist. --%>
              <CastPanel.cast_filter_form
                :if={@cast_filter_in_header?}
                filter={@cast_filter}
                class="mt-4 flex justify-end"
              />
            </div>
          </div>
        </div>
        <%!-- The saga picker (UIDR-023): selection + collection state in
              one strip, below the member's own panel content. Rendered in
              the pinned block so the picker never scrolls away. --%>
        <CollectionRail.collection_rail
          :if={@member_view}
          movie_items={@movies_view || []}
          selected_id={@member_view.member.movie.id}
          saga_label={@entity.name}
          available={@available}
        />
      </:orientation>
      <%!-- The modal's second nav region — the body of the title, whichever
            sub-view is showing. DOWN from the action row lands here and BACK
            climbs back to it. The zone follows the sub-view: the season /
            film / extras lists are a `detail_list` tree (LEFT and RIGHT are
            depth — collapse a season, step into an episode's controls),
            Manage brings its own pair of zones (`manage_tools` +
            `manage_list`, declared inside ManagePanel — distinct from
            `detail_list` so ledger activity can't clobber the episode
            list's cursor memory), while Cast is a
            `detail_cast` photo grid navigated by
            geometry. One body zone at a time — nav zones must never nest.
            See UIDR-019. --%>
      <:body :if={@has_scrollable_content}>
        <%= case @detail_view do %>
          <% :cast -> %>
            <div data-nav-zone="detail_cast">
              <CastPanel.cast_panel
                entity={@subject}
                cast_filter={@cast_filter}
                cast_limit={@cast_limit}
                resume_episode_key={@resume_episode_key}
                filter_in_header?={@cast_filter_in_header?}
              />
            </div>
          <% :info -> %>
            <%!-- ManagePanel declares its own nav zones — the toolbar card
                  is a `manage_tools` TOOLBAR beside a `detail_list` tree for
                  the ledger (sibling zones; see its moduledoc). --%>
            <ManagePanel.manage_panel
              entity={@entity}
              files={@detail_files}
              rematch_confirm={@rematch_confirm}
              delete_confirm={@delete_confirm}
              deleting={@deleting}
              tmdb_ready={@tmdb_ready}
              expanded_groups={@expanded_file_groups}
            />
          <% _ -> %>
            <div data-nav-zone="detail_list">
              <.content_list
                entity={@entity}
                seasons_view={@seasons_view}
                movies_view={@movies_view}
                expanded_seasons={@expanded_seasons}
                expanded_item_details={@expanded_item_details}
                all_episode_details_open={@all_episode_details_open}
                extra_progress_by_id={@extra_progress_by_id}
                on_play={@on_play}
                spoiler_free={@spoiler_free}
                available={@available}
              />
            </div>
        <% end %>
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  # Whether the detail document opens scrolled to its resume target —
  # the sole signal the `DetailBodyScroll` hook reads.
  #
  # Containers ask their `Orientation`: an unstarted title has a *first*
  # item, not a next one — no position to return to — so it must not
  # scroll even though its first row still carries `data-resume-target`
  # (that attribute drives the next-up highlight, so it can't double as
  # the scroll signal).
  #
  # Leaves (no orientation) answer true — a bare movie renders no target
  # row, so the hook finds nothing to scroll to anyway.
  defp autoscroll_resume?(%Orientation{autoscroll?: autoscroll?}), do: autoscroll?
  defp autoscroll_resume?(nil), do: true

  # --- Header content builders (used in detail_panel/1) ---

  # Same shape as `Logic.member_playback/1`: label + target for the Play
  # button, percent + remaining for the hero hairline and the metadata
  # line (UIDR-024). Titles with an orientation override percent with
  # their series fraction at the call site.
  defp build_playback(assigns) do
    {label, target_id} =
      Logic.playback_props(assigns.entity, assigns.resume, assigns.progress)

    %{
      label: label,
      target_id: target_id,
      percent: overall_progress_percent(assigns.progress, assigns.entity),
      remaining_text: progress_remaining_text(assigns.progress, assigns.entity)
    }
  end

  defp build_metadata_items(entity, remaining_text) do
    [
      year_or_nil(entity),
      season_count_or_nil(entity),
      duration_or_nil(entity),
      Map.get(entity, :content_rating),
      country_or_nil(entity),
      # The remaining item displaces the status while it exists
      # (UIDR-024) — mid-watch, "Released" is noise.
      if(is_nil(remaining_text), do: status_or_nil(entity))
    ]
  end

  # The hairline names its subject (UIDR-024): the unit is always the
  # subject's own watched fraction, so the label follows the subject's
  # type — a member subject is a `:movie`-shaped map.
  defp hairline_label(%{type: :tv_series}), do: "Series progress"
  defp hairline_label(%{type: :movie}), do: "Movie progress"
  defp hairline_label(_subject), do: "Watch progress"

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

  # Leaf-only (movie / video_object): containers derive their hairline
  # fraction from `ViewModel.Orientation`; a leaf's comes from its
  # progress summary via this percent (UIDR-024).
  def overall_progress_percent(nil, _entity), do: 0

  def overall_progress_percent(progress, _entity) do
    if progress.episode_duration_seconds > 0 do
      min(round(progress.episode_position_seconds / progress.episode_duration_seconds * 100), 100)
    else
      if progress.episodes_completed > 0, do: 100, else: 0
    end
  end

  # The metadata line's remaining item (UIDR-024). Completed titles
  # yield nil — the full hairline and the watched toggle carry that
  # state; the metadata line goes back to showing the status.
  def progress_remaining_text(nil, _entity), do: nil

  def progress_remaining_text(progress, _entity) do
    if progress.episodes_completed == 0 && progress.episode_duration_seconds > 0 &&
         progress.episode_position_seconds > 0 do
      remaining_seconds = progress.episode_duration_seconds - progress.episode_position_seconds
      "#{format_human_duration(trunc(remaining_seconds))} left"
    end
  end

  # --- Content List (type-dependent) ---
  #
  # Thin dispatch on entity type: each branch hands the typed view-model
  # list to its dedicated list component. Entity-level extras are
  # filtered here (`Logic.entity_extras/1`) so the lists never see
  # season-owned ones.

  defp content_list(%{entity: %{type: :tv_series}} = assigns) do
    ~H"""
    <SeasonList.season_list
      seasons={@seasons_view || []}
      entity_id={@entity.id}
      expanded_seasons={@expanded_seasons}
      expanded_item_details={@expanded_item_details}
      all_episode_details_open={@all_episode_details_open}
      extras={Logic.entity_extras(@entity)}
      extra_progress_by_id={@extra_progress_by_id}
      on_play={@on_play}
      spoiler_free={@spoiler_free}
      available={@available}
    />
    """
  end

  # Collections deliberately fall through to the extras fallback: the
  # member list is the poster rail in the pinned block (UIDR-023), so a
  # collection's scrolling body carries only its entity-level extras —
  # the same idiom as a bare movie with bonus content.
  defp content_list(assigns) do
    ~H"""
    <ExtrasSection.extras_section
      extras={Logic.entity_extras(@entity)}
      extra_progress_by_id={@extra_progress_by_id}
      entity_id={@entity.id}
      on_play={@on_play}
    />
    """
  end

  @doc """
  Whether the detail modal's content region scrolls — TV / movie-series
  lists, entity-level extras, or the Manage / Cast sub-views.

  Drives the frame's `full` attr, which tags scrollable entries with
  `.modal-panel--full`: those panels get a constant backdrop box
  (sized in `--modal-panel-h` units, not a panel percentage) and a
  top-anchored position, so the panel can grow and shrink with the
  season accordion without re-cropping or shifting the backdrop
  image. Content-fit panels (bare movies) instead center with an
  upward optical bias. See the app.css comments on
  `.modal-panel--full` / `.modal-panel--cinematic`.
  """
  @spec scrollable_content?(map(), atom()) :: boolean()
  def scrollable_content?(entity, detail_view) do
    detail_view in [:info, :cast] ||
      entity.type == :tv_series ||
      Logic.entity_extras(entity) != []
  end

  defp index_extra_progress(%{extra_progress: progress}) when is_list(progress) do
    Map.new(progress, fn record -> {record.extra_id, record} end)
  end

  defp index_extra_progress(_), do: %{}

  # --- Resume keys (Cast view) ---

  defp resume_episode_key(%{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode) do
    {season, episode}
  end

  defp resume_episode_key(_), do: nil

  defp progress_episode_key(%{current_episode: %{season: season, episode: episode}})
       when is_integer(season) and is_integer(episode), do: {season, episode}

  defp progress_episode_key(_), do: nil
end
