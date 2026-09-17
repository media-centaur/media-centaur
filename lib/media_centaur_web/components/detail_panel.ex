defmodule MediaCentaurWeb.Components.DetailPanel do
  @moduledoc """
  The title detail modal (UIDR-043) — the tenant of
  `MediaCentaurWeb.Components.CinematicShell` that renders one
  `Title.Detail` for one TMDB identity, owned or not, its sections
  present by what the facts say.

  The frame (modal shell, panel-fixed backdrop, scrollport, sticky
  orientation wrapper + backing replica, body sheet) belongs to
  `CinematicShell`; this module fills its slots: the pennants on the
  hero's mast (UIDR-037); the pinned block — the identity lockup, the
  progress hairline for an owned title (UIDR-024), the metadata row, the
  action row and the prose; the collection rail (UIDR-023); and the
  scrolling body — the content list, Cast or Manage for an owned title,
  with the tracking card under it for any title that has something to
  say (UIDR-042).

  ## The section header is not pinned anywhere

  Nine components under `components/detail/` render the same small
  uppercase section header at four sizes (`0.65rem`, `0.7rem`, `text-xs`,
  `text-sm`) and two opacities. A `Detail.Section` wrapper existed to pin
  that rhythm and nothing ever adopted it, so it was removed rather than
  left as an unused promise. Which treatment is canonical is an open design
  question — settle it before adding a tenth.

  ## The subject (UIDR-023)

  For an owned title the panel speaks of the library half's `subject`:
  the entity itself, or for a collection the selected member composed
  as a `:movie`-shaped map by `ViewModel.CollectionDetail.member_subject/1`.
  Identity, playback, synopsis and Cast render from the subject through
  the same components a standalone movie uses — one component family, no
  collection fork; the collection keeps the collection-scoped surfaces
  (Manage, extras) and contributes the `Detail.CollectionRail` picker.
  An unowned title speaks of its snapshot, dressed by the live preview
  when it lands: the overview and metadata from the preview until then
  from the snapshot, the type and year. No facet strip on either: the
  main view is for deciding to press Play or Download, not for reference
  lookup.

  ## The action row

  One row — the `detail_actions` nav zone — whose primary is
  `Detail.Logic.primary_action/2`: Play (`Detail.PlayCard`) for an owned
  title; the Download split control (`GlassMenu.split_button`, its main
  segment the person's default planning mode, its menu the other) with
  the scope select beside it for a series, when the title is out and an
  indexer is ready; the acquisition state as a fact (Needs review links
  to Incoming); or nothing — arming is the tracking switches' job
  (ADR-066). The view controls follow (`Detail.ViewControls`), then the
  member Watched toggle for a collection, and at the far end Delete
  <noun> for an own activity the modal was opened from.

  ## Events

  Pure rendering; every control bubbles to the host: `play`,
  `close_title` (`on_close`), `select_detail_view`, `select_entity` (a
  rail tile), `set_rung`, `review_open`, `download` (`mode` from the
  menu, none from the main segment), `download_mode_toggle`,
  `download_scope_toggle`, `download_menu_close`, `download_scope`
  (`choice`), `activity_delete`, `reset_lower_quality`, and the library
  sections' own (`toggle_watched`, `toggle_season`, the delete prompts,
  …).

  Nav: the backdrop is the `detail` overlay; the action row is the
  `detail_actions` toolbar, an open glass menu the `detail_menu` tree
  nested inside it (BACK closes it), and the body the second region
  below — `detail_list`, `detail_cast`, `manage_tools` + `manage_list`,
  `detail_tracking` — as the sub-view dictates (UIDR-019).
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers

  import MediaCentaurWeb.LibraryFormatters, only: [format_type: 1, format_human_duration: 1]

  alias MediaCentaur.Settings.Preferences.PlanningMode
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
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Detail.ViewControls
  alias MediaCentaurWeb.Components.GlassMenu
  alias MediaCentaurWeb.Components.ProgressHairline
  alias MediaCentaurWeb.Components.ReleaseTracking.ReleaseDates
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Logic, as: TitleLogic
  alias MediaCentaurWeb.Components.Title.LowerQualityNote
  alias MediaCentaurWeb.Components.Title.ModalState
  alias MediaCentaurWeb.Components.Title.Pennant
  alias MediaCentaurWeb.Components.Title.TrackingControls
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef
  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.Orientation
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  attr :detail, TitleDetail, default: nil, doc: "the open title; `nil` renders the closed shell."

  attr :state, ModalState,
    default: nil,
    doc: "the per-opening state the host owns; `nil` is a fresh `ModalState.new/1`."

  attr :today, Date, required: true, doc: "the host's date — for the download and tracking rules."
  attr :spoiler_free, :boolean, default: false
  attr :letterboxd_links, :boolean, default: true
  attr :tmdb_ready, :boolean, default: true

  attr :review?, :boolean,
    default: false,
    doc: "whether the Review control is offered — the host passes `show_discovery`."

  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_title"

  # No subject loaded: the bare frame stays in the DOM (closed) so the
  # blur compositing layer keeps warm — same reason the frame itself is
  # always-in-DOM.
  def detail_panel(%{detail: nil} = assigns) do
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
    detail = assigns.detail
    state = assigns.state || ModalState.new()
    half = library_facts(detail.library)
    # An unowned title has one view; the host narrows an owned title's.
    view = if half.library, do: state.view, else: :main
    orientation = orientation(half.entry)
    action = Logic.primary_action(detail, assigns.today)
    hero = hero_facts(detail, half, action, orientation)
    prose = prose_facts(detail, half.subject)
    body? = body?(detail, view)
    ref = detail.ref && TitleRef.param(detail.ref)
    {files, files_status} = files(half.library)

    cast_filter_in_header? =
      view == :cast && prose.prose? &&
        CastSelection.show_filter?(Map.get(half.subject, :cast) || [])

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(half)
      |> assign(hero)
      |> assign(prose)
      |> assign(:view, view)
      |> assign(:action, action)
      |> assign(:cast_filter_in_header?, cast_filter_in_header?)
      |> assign(:backdrop_url, backdrop_url(detail))
      |> assign(:body?, body?)
      |> assign(:ref, ref)
      |> assign(:files, files)
      |> assign(:files_status, files_status)
      |> assign(:seasons, seasons(half.entry))
      |> assign(:movies, movies(half.entry))
      |> assign(:resume_episode_key, resume_episode_key(half.entry))
      |> assign(:extra_progress_by_id, index_extra_progress(half.entity))
      |> assign(:autoscroll_resume?, autoscroll_resume?(orientation))
      |> assign(
        :nested?,
        half.library != nil and Logic.nested_view?(Logic.controls_entity(half.library), view)
      )
      |> assign(:scroll_key, if(half.entity, do: half.entity.id, else: ref))

    ~H"""
    <CinematicShell.cinematic_shell
      id="detail-modal"
      open
      dismiss={:ephemeral}
      on_close={@on_close}
      present
      full={@body?}
      backdrop_url={@backdrop_url}
      scroll_key={@scroll_key}
      view_key={@view}
      scroll_to_resume={@autoscroll_resume?}
      data-detail-nested={to_string(@nested?)}
      data-nav-overlay="detail"
    >
      <:hero_mast :if={@detail.friend_activity != []}>
        <Pennant.pennants activity={@detail.friend_activity} on_image />
      </:hero_mast>
      <%!-- The pinned block's content: identity lockup + hairline +
            metadata + action row + prose. The sticky wrapper and its
            backdrop backing belong to the frame (CinematicShell). Same
            block for every title: movies simply never scroll enough to
            pin it. --%>
      <:orientation>
        <div class="px-6">
          <TitleLayer.lockup title={@name} logo_url={@logo_url} tagline={@tagline} />
        </div>
        <ProgressHairline.progress_hairline
          :if={@hairline_fraction != nil}
          fraction={@hairline_fraction}
          label={@hairline_label}
          class="mt-4"
        />
        <%!-- An unowned title has no track; the same box keeps the
              lockup-to-metadata rhythm of an owned one. --%>
        <div :if={@hairline_fraction == nil} class="mt-4 h-0.5" aria-hidden="true"></div>
        <%!-- pt-6 (vs the p-4 sides): the progress hairline sits flush on
              the hero window's bottom edge, so the block below needs
              extra clearance to read as separate from the progress
              track. Bottom padding is two different distances: against a
              body below it is internal rhythm and stays tight; on a
              content-fit panel it is the clearance between the prose and
              the panel's rounded bottom edge, which needs real breathing
              room. --%>
        <div class={["px-4 pt-6", (@body? && "pb-4") || "pb-8"]}>
          <%!-- One column, three stacked bands: identity facts, the
                action row, then the prose across the panel's full
                width. It was a 2/5–3/5 split until 2026-09-15, which
                gave the synopsis ~62ch and cut a 546-character series
                overview mid-sentence at `line-clamp-6`. The panel is
                the measure now, so the same clamp holds about twice the
                words and a typical overview lands whole. --%>
          <div class="space-y-4 min-w-0">
            <MetadataRow.metadata_row
              badge_text={@badge_text}
              items={@metadata_items}
              remaining_text={@metadata_remaining}
            />
            <%!-- The action row. The Download control's menus are zones
                  nested inside it: the input system counts an item for
                  its nearest zone, and BACK out of an open list closes
                  it (`data-nav-dismiss-event`). data-nav-enter-scroll-top:
                  arrowing up out of the body list glides the modal back
                  to the hero; BACK lands here without moving it. --%>
            <div
              class="flex items-center gap-2 pt-1"
              data-nav-zone="detail_actions"
              data-nav-enter-scroll-top
            >
              <.primary
                detail={@detail}
                action={@action}
                state={@state}
                on_play={@on_play}
                available={@available}
              />
              <ViewControls.view_controls
                detail={@detail}
                view={@view}
                letterboxd_links={@letterboxd_links}
                review?={@review?}
              />
              <%!-- Member watched toggle: acting on the *selected*
                    movie is what the movie-first modal is for, and
                    Play's line is the one place every input method
                    reaches (UIDR-023). Far right with its label, away
                    from the play cluster; a first-class nav item so the
                    toolbar walk reaches it. --%>
              <span :if={@member} class="ml-auto flex items-center gap-2">
                <span class="text-xs text-base-content/55">Watched</span>
                <PlayableRow.watched_toggle
                  event="toggle_watched"
                  state={@member.state}
                  progress={@member.progress}
                  duration_seconds={Map.get(@member.movie, :duration_seconds)}
                  show_duration={false}
                  nav_item
                  phx-value-entity-id={@entity.id}
                  phx-value-container-type="movie"
                  phx-value-container-id={@member.movie.id}
                />
              </span>
              <.activity_delete detail={@detail} />
            </div>
            <div :if={@prose?}>
              <.note_line note={@note} />
              <p
                :if={@description}
                class="text-[15px] leading-relaxed text-base-content/75 line-clamp-6"
              >
                {@description}
              </p>
              <%!-- Cast-view only: the filter lives here, in the pinned
                    orientation block, rather than in the scrolling sheet —
                    it fills the slack under the synopsis and stays reachable
                    however deep the grid is scrolled. cast_panel renders its
                    own inline fallback when this band doesn't exist. --%>
              <CastPanel.cast_filter_form
                :if={@cast_filter_in_header?}
                filter={@state.cast_filter}
                class="mt-4 flex justify-end"
              />
            </div>
          </div>
        </div>
        <%!-- The saga picker (UIDR-023): selection + collection state in
              one strip, below the member's own panel content. Rendered in
              the pinned block so the picker never scrolls away. --%>
        <CollectionRail.collection_rail
          :if={@member}
          movie_items={@movies || []}
          selected_id={@member.movie.id}
          saga_label={@entity.name}
          available={@available}
        />
      </:orientation>
      <%!-- The modal's second nav region — the body of the title, whichever
            sub-view is showing. DOWN from the action row lands here and BACK
            climbs back to it. The zone follows the sub-view: the season /
            film / extras lists are a `detail_list` tree, Manage brings its
            own pair of zones (`manage_tools` + `manage_list`, declared inside
            ManagePanel), while Cast is a `detail_cast` photo grid navigated
            by geometry. The tracking card under the list is its own
            `detail_tracking` strip — a sibling, because nav zones must never
            nest. See UIDR-019. --%>
      <:body :if={@body?}>
        <%= case {@library, @view} do %>
          <% {nil, _view} -> %>
          <% {_library, :cast} -> %>
            <div data-nav-zone="detail_cast">
              <CastPanel.cast_panel
                entity={@subject}
                cast_filter={@state.cast_filter}
                cast_limit={@state.cast_limit}
                resume_episode_key={@resume_episode_key}
                filter_in_header?={@cast_filter_in_header?}
              />
            </div>
          <% {_library, :info} -> %>
            <ManagePanel.manage_panel
              entity={@entity}
              files={@files}
              files_status={@files_status}
              rematch_confirm={@state.rematch_confirm}
              delete_confirm={@state.delete_confirm}
              deleting={@state.deleting}
              tmdb_ready={@tmdb_ready}
              expanded_groups={@state.expanded_file_groups}
              title_ref={@ref}
              lower_quality_accepted?={@detail.lower_quality_accepted?}
            />
          <% {_library, _main} -> %>
            <div data-nav-zone="detail_list">
              <.content_list
                entity={@entity}
                seasons={@seasons}
                state={@state}
                extra_progress_by_id={@extra_progress_by_id}
                on_play={@on_play}
                spoiler_free={@spoiler_free}
                available={@available}
                acquisition?={@detail.acquisition?}
              />
            </div>
        <% end %>
        <.tracking_card
          :if={@view == :main and Logic.tracking_card?(@detail)}
          detail={@detail}
          ref={@ref}
          today={@today}
        />
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  # --- Derivations (kept out of the render function for its own sake) ---

  # What the library half unpacks to, or the same keys as nil.
  defp library_facts(nil),
    do: %{library: nil, entry: nil, entity: nil, subject: nil, member: nil, available: true}

  defp library_facts(library) do
    %{
      library: library,
      entry: library.entry,
      entity: library.entry.entity,
      subject: library.subject,
      member: library.member,
      available: library.available
    }
  end

  # TV keeps its orientation (hairline fraction + autoscroll).
  # Collections don't build one — saga state lives on the poster rail;
  # the hero hairline reads the *subject's* fraction (UIDR-024).
  defp orientation(%SeriesDetail{seasons: seasons, resume_target: resume}),
    do: Orientation.for_series(seasons, resume)

  defp orientation(_entry), do: nil

  # The hero block's facts. UIDR-024: every owned subject carries its
  # watched fraction in the hairline — TV the series', a movie or member
  # its own — and the remaining time is a metadata-line item, not
  # card-row copy. An unowned title has no track.
  defp hero_facts(detail, half, action, orientation) do
    playback =
      case action do
        {:play, props} -> props
        _other -> nil
      end

    hairline_fraction =
      cond do
        orientation -> orientation.fraction
        playback -> playback.percent / 100
        true -> nil
      end

    metadata_remaining = if playback && !orientation, do: playback.remaining_text
    {badge_text, metadata_items} = metadata(detail, half.subject, metadata_remaining)

    %{
      hairline_fraction: hairline_fraction,
      hairline_label: half.subject && hairline_label(half.subject),
      metadata_remaining: metadata_remaining,
      badge_text: badge_text,
      metadata_items: metadata_items,
      name: if(half.subject, do: half.subject.name, else: detail.title.name),
      logo_url: logo_url(detail, half.available, detail.preview),
      tagline: tagline(detail, half.subject, detail.preview)
    }
  end

  # The prose band under the action row: the synopsis and the note, and
  # whether there is a band at all. The Cast view's filter form rides in
  # the band when there is one, so `prose?` answers for both.
  defp prose_facts(detail, subject) do
    description = prose(detail, subject)
    note = note_words(detail)

    %{
      description: description,
      note: note,
      prose?: description != nil or note != nil
    }
  end

  # --- The action row's primary ---

  attr :detail, TitleDetail, required: true
  attr :action, :any, required: true, doc: "`Detail.Logic.primary_action/2`"
  attr :state, ModalState, required: true
  attr :on_play, :string, required: true
  attr :available, :boolean, required: true

  defp primary(%{action: {:play, props}} = assigns) do
    assigns = assign(assigns, :props, props)

    ~H"""
    <PlayCard.play_card
      on_play={@on_play}
      target_id={@props.target_id}
      label={@props.label}
      available={@available}
    />
    """
  end

  defp primary(%{action: {:state, :needs_review}} = assigns) do
    ~H"""
    <.link
      id="detail-needs-review"
      navigate="/incoming"
      class="inline-flex items-center gap-1 text-sm text-warning"
      data-nav-item
      tabindex="0"
    >
      Needs review <.icon name="hero-chevron-right-mini" class="size-4" />
    </.link>
    """
  end

  defp primary(%{action: {:state, state}} = assigns) do
    assigns = assign(assigns, :marker, TitleLogic.acquisition_marker(state))

    ~H"""
    <span id="detail-acquisition-state" class="text-sm text-base-content/70">{@marker}</span>
    """
  end

  # The split's main segment performs the person's default planning
  # mode; the menu names the other. A series adds the scope select.
  # Neither follows the series: a scope covers episodes that have aired,
  # and what is still to come is the tracking switches' business, never
  # a download's (ADR-066).
  defp primary(%{action: {:download, scoped?}} = assigns) do
    assigns =
      assigns
      |> assign(:other_mode, PlanningMode.other(assigns.detail.planning_mode))
      |> assign(:scoped?, scoped?)
      |> assign(:pending?, match?({:download, _name}, assigns.state.pending))

    ~H"""
    <GlassMenu.split_button
      id="detail-download"
      open={@state.open_menu == :mode}
      on_toggle="download_mode_toggle"
      on_close="download_menu_close"
      menu_zone="detail_menu"
      menu_label="More download options"
      disabled={@pending?}
      phx-click="download"
    >
      {if @pending?, do: "Planning…", else: "Download"}
      <:item
        id="detail-download-other"
        event="download"
        values={%{"mode" => Atom.to_string(@other_mode)}}
      >
        {TitleLogic.planning_mode_label(@other_mode)}
      </:item>
    </GlassMenu.split_button>
    <GlassMenu.menu_select
      :if={@scoped?}
      id="detail-scope"
      open={@state.open_menu == :scope}
      on_toggle="download_scope_toggle"
      on_close="download_menu_close"
      menu_zone="detail_menu"
      value_label={TitleLogic.download_scope_label(@state.download_scope)}
      label="Download scope"
    >
      <:item
        :for={scope <- [:first_season, :everything]}
        id={"detail-scope-" <> Atom.to_string(scope)}
        event="download_scope"
        values={%{"choice" => Atom.to_string(scope)}}
        active={scope == @state.download_scope}
      >
        {TitleLogic.download_scope_label(scope)}
      </:item>
    </GlassMenu.menu_select>
    """
  end

  # Nothing to download yet: the tracking switches below are the act.
  defp primary(%{action: :none} = assigns), do: ~H""

  attr :detail, TitleDetail, required: true

  # The one quiet tertiary verb: Delete, for an own activity the modal
  # was opened from (the You card), named by its kind.
  defp activity_delete(assigns) do
    assigns = assign(assigns, :own, own_activity(assigns.detail))

    ~H"""
    <span :if={@own} class="ml-auto flex items-center gap-3">
      <button
        id="detail-activity-delete"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="activity_delete"
        data-nav-item
        tabindex="0"
      >
        Delete {ActivityWords.noun(@own.kind)}
      </button>
    </span>
    """
  end

  defp own_activity(%TitleDetail{activity: %{activity: activity, own?: true}}), do: activity
  defp own_activity(_detail), do: nil

  attr :note, :any, required: true, doc: "`%{sender, text}` or nil"

  # The one thing a pennant cannot hold: a friend's words, in the list
  # row's note idiom — name, then text.
  defp note_line(%{note: nil} = assigns), do: ~H""

  defp note_line(assigns) do
    ~H"""
    <p id="detail-note" class="mb-3 text-sm text-base-content/80">
      <span :if={@note.sender} class="font-medium text-base-content/70">{@note.sender}</span>
      {@note.text}
    </p>
    """
  end

  # --- Tracking (UIDR-042) ---

  attr :detail, TitleDetail, required: true
  attr :ref, :string, required: true
  attr :today, Date, required: true

  # One card, one rule (`Detail.Logic.tracking_card?/1`): the switches on
  # the left once the title is listed, what the calendar or TMDB knows of
  # its dates on the right. The card sits under the list so choosing a
  # rung adds content below it and never moves it.
  defp tracking_card(assigns) do
    assigns =
      assigns
      |> assign(
        :controls?,
        TrackingControls.control_form(assigns.detail.rung) != :none or
          Logic.lower_quality_note?(assigns.detail)
      )
      |> assign(:lower_quality_note?, Logic.lower_quality_note?(assigns.detail))

    ~H"""
    <div
      id="detail-tracking"
      class="space-y-6 border-t border-base-content/10 px-6 pb-6 pt-6"
      data-nav-zone="detail_tracking"
    >
      <div class="glass-inset flex flex-wrap gap-x-8 gap-y-4 rounded-lg p-4">
        <div :if={@controls?} class="w-64 shrink-0 space-y-3">
          <TrackingControls.tracking_controls
            id="detail-tracking-controls"
            ref={@ref}
            rung={@detail.rung}
            media_type={@detail.title.media_type}
            release_ahead?={TitleLogic.release_ahead?(@detail.title, @detail.release_window, @today)}
            complete?={@detail.complete?}
            approval_policy={PlanningMode.approval_policy(@detail.planning_mode)}
            acquisition?={@detail.acquisition?}
          />
          <%!-- Only for a title with no Manage sheet: an owned one carries
                the acceptance behind the cog and nowhere else. --%>
          <LowerQualityNote.lower_quality_note
            id="detail-lower-quality"
            ref={@ref}
            accepted?={@lower_quality_note?}
          />
        </div>
        <ReleaseDates.release_dates
          :if={Logic.release_dates?(@detail)}
          id="detail-release-dates"
          media_type={@detail.title.media_type}
          release_window={@detail.release_window}
          timeline={timeline(@detail.tracking)}
          today={@today}
          class="min-w-[14rem] max-w-sm flex-1"
        />
      </div>
    </div>
    """
  end

  defp timeline(%{timeline: timeline}), do: timeline
  defp timeline(_untracked), do: []

  # --- Content list (type-dependent) ---
  #
  # Thin dispatch on entity type: each branch hands the typed view-model
  # list to its dedicated list component. Entity-level extras are
  # filtered here (`Logic.entity_extras/1`) so the lists never see
  # season-owned ones.

  attr :entity, :map,
    required: true,
    doc: "the container `Library.EntityView` — a `:tv_series` lists seasons, anything else its extras."

  attr :seasons, :any, required: true, doc: "`[%ViewModel.SeasonView{}]` for a series, nil otherwise."
  attr :state, ModalState, required: true

  attr :extra_progress_by_id, :map,
    required: true,
    doc: "`%{extra_id => ExtraProgress}` indexed from the entity."

  attr :on_play, :string, required: true
  attr :spoiler_free, :boolean, required: true
  attr :available, :boolean, required: true
  attr :acquisition?, :boolean, required: true

  defp content_list(%{entity: %{type: :tv_series}} = assigns) do
    ~H"""
    <SeasonList.season_list
      seasons={@seasons || []}
      entity_id={@entity.id}
      expanded_seasons={@state.expanded_seasons}
      expanded_item_details={@state.expanded_item_details}
      all_episode_details_open={@state.all_episode_details_open}
      extras={Logic.entity_extras(@entity)}
      extra_progress_by_id={@extra_progress_by_id}
      on_play={@on_play}
      spoiler_free={@spoiler_free}
      available={@available}
      series_tmdb_id={@entity.tmdb_id}
      acquisition?={@acquisition?}
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

  # --- Rules ---

  @doc """
  Whether the detail document scrolls — an owned title's seasons,
  entity-level extras, Manage or Cast sub-views, or any title's tracking
  card (`Detail.Logic.tracking_card?/1`).

  Drives the frame's `full` attr, which tags scrollable documents with
  `.modal-panel--full`: those panels get a constant backdrop box and a
  top-anchored position, so the panel can grow and shrink with the
  season accordion without re-cropping or shifting the backdrop image.
  Content-fit panels (a bare movie, an unowned title with nothing under
  its hero) instead center with an upward optical bias.
  """
  @spec body?(TitleDetail.t(), ModalState.view()) :: boolean()
  def body?(%TitleDetail{library: nil} = detail, _view), do: Logic.tracking_card?(detail)

  def body?(%TitleDetail{library: %{entry: entry}} = detail, view) do
    view in [:info, :cast] or match?(%SeriesDetail{}, entry) or
      Logic.entity_extras(entry.entity) != [] or Logic.tracking_card?(detail)
  end

  # Whether the detail document opens scrolled to its resume target —
  # the sole signal the `DetailBodyScroll` hook reads. Containers ask
  # their `Orientation`: an unstarted title has a *first* item, not a
  # next one — no position to return to — so it must not scroll. Leaves
  # (no orientation) answer true — a bare movie renders no target row, so
  # the hook finds nothing to scroll to anyway.
  defp autoscroll_resume?(%Orientation{autoscroll?: autoscroll?}), do: autoscroll?
  defp autoscroll_resume?(nil), do: true

  # The metadata row: from the subject for an owned title
  # (`build_metadata_items/2`); from the preview for an unowned one, and
  # until it lands the snapshot's type and year.
  defp metadata(%TitleDetail{library: %{}}, subject, remaining),
    do: {format_type(subject.type), build_metadata_items(subject, remaining)}

  defp metadata(%TitleDetail{preview: %TitlePreview{} = preview}, nil, _remaining),
    do: {TitlePreview.badge_text(preview), preview.metadata_items}

  defp metadata(%TitleDetail{title: title}, nil, _remaining),
    do: {format_type(title.media_type), [title.year]}

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

  defp year_or_nil(subject), do: MediaCentaur.Format.year(Map.get(subject, :date_published))

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

  # The lockup's logo: the library's for an owned title (when storage is
  # online), the preview's then the artwork cache's for an unowned one.
  defp logo_url(%TitleDetail{library: %{subject: subject}}, available, _preview),
    do: (available && image_url(subject, "logo")) || nil

  defp logo_url(%TitleDetail{logo_url: cached}, _available, preview),
    do: (preview && preview.logo_url) || cached

  defp tagline(_detail, subject, _preview) when is_map(subject),
    do: blank_to_nil(Map.get(subject, :tagline))

  defp tagline(_detail, nil, preview), do: preview && blank_to_nil(preview.tagline)

  # The prose: the subject's synopsis for an owned title; the live
  # preview's overview when it has landed, else the snapshot's.
  defp prose(_detail, subject) when is_map(subject), do: blank_to_nil(Map.get(subject, :description))

  defp prose(%TitleDetail{preview: %TitlePreview{overview: overview}}, nil) when is_binary(overview),
    do: blank_to_nil(overview)

  defp prose(%TitleDetail{title: %{overview: overview}}, nil), do: blank_to_nil(overview)

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  # The words under the hero: the activity's text attributed to its
  # nickname when it has any, else the person's own watchlist note.
  defp note_words(%TitleDetail{activity: %{activity: %{text: text}, nickname: nickname}})
       when is_binary(text) and text != "", do: %{sender: nickname, text: text}

  defp note_words(%TitleDetail{intent_note: note}) when is_binary(note) and note != "",
    do: %{sender: nil, text: note}

  defp note_words(_detail), do: nil

  # The artwork ladder (UIDR-021). Owned: subject art first, entity art
  # as the ladder's next rungs — a member movie rarely carries its own
  # backdrop, so a collection usually frames its members in collection
  # art; nothing while storage is offline. Unowned: the cached tier the
  # host resolved, else the live preview's backdrop (poster as its
  # fallback), else nothing — the frame paints its placeholder.
  defp backdrop_url(%TitleDetail{library: %{available: false}}), do: nil

  defp backdrop_url(%TitleDetail{library: %{subject: subject, entry: %{entity: entity}}}) do
    image_url(subject, "backdrop") || image_url(entity, "backdrop") ||
      image_url(subject, "poster") || image_url(entity, "poster")
  end

  defp backdrop_url(%TitleDetail{backdrop_url: url}) when is_binary(url), do: url
  defp backdrop_url(%TitleDetail{preview: %{backdrop_url: url}}) when is_binary(url), do: url
  defp backdrop_url(%TitleDetail{preview: %{poster_url: url}}) when is_binary(url), do: url
  defp backdrop_url(_detail), do: nil

  defp files(%{files: {:ok, files}}), do: {files, :loaded}
  defp files(%{files: :failed}), do: {[], :failed}
  defp files(_loading_or_none), do: {[], :loading}

  defp seasons(%SeriesDetail{seasons: seasons}), do: seasons
  defp seasons(_entry), do: nil

  defp movies(%CollectionDetail{movies: movies}), do: movies
  defp movies(_entry), do: nil

  defp index_extra_progress(%{extra_progress: progress}) when is_list(progress) do
    Map.new(progress, fn record -> {record.extra_id, record} end)
  end

  defp index_extra_progress(_), do: %{}

  # --- Resume keys (Cast view) ---

  defp resume_episode_key(nil), do: nil

  defp resume_episode_key(%{resume_target: resume, progress: progress}),
    do: resume_hint_key(resume) || progress_episode_key(progress)

  defp resume_hint_key(%{"seasonNumber" => season, "episodeNumber" => episode})
       when is_integer(season) and is_integer(episode) do
    {season, episode}
  end

  defp resume_hint_key(_), do: nil

  defp progress_episode_key(%{current_episode: %{season: season, episode: episode}})
       when is_integer(season) and is_integer(episode), do: {season, episode}

  defp progress_episode_key(_), do: nil
end
