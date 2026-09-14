defmodule MediaCentaurWeb.Components.Title.DetailModal do
  @moduledoc """
  The title detail modal — the one depth surface for a title without
  files (UIDR-035): watchlisted, tracked, in flight, or merely
  reviewed, on Discovery and on Incoming alike. A tenant of the
  cinematic frame. Rendered from the embedded `TMDB.Title` snapshot plus
  the local artwork cache, with no network call on open; the live TMDB
  preview dresses it when it lands.

  Top to bottom: the hero with the pennants on its mast — the one place
  friend provenance shows (UIDR-037); the lockup; the metadata row once
  the preview has landed (type, year, runtime or seasons, country — the
  library detail's row, in the same place), until then the type and
  year from the snapshot; the action strip; then the body — a friend's
  note when there is one, the overview, the facet strip, the ladder
  control, and beneath it what the ladder produces: the release
  timeline and recent activity, while the title is followed. The
  control sits above everything it derives, so choosing a rung adds
  content below it and never moves it. No cast strip: the faces confirm
  a pick on the plan modal; here the ladder is the point.

  The action strip is the watchlist row's honest rule with the
  acquisition state folded in: In library → the library detail;
  Planning / Downloading / Needs review → a stated fact (Needs review
  links to Incoming); Download when the title is out and an indexer is
  ready; otherwise no primary verb — there is no `Track`, because
  arming is the ladder control's job (ADR-066). Download is a split
  button (`GlassMenu.split_button`): its main segment performs the
  person's default planning mode (`Settings.Preferences.PlanningMode`)
  and its menu names the other; a series adds a scope select beside it
  (`GlassMenu.menu_select`, Season 1 or All seasons). Neither follows
  the series: a scope covers episodes that have aired, and what is still
  to come is the ladder's business, never a download's (ADR-066). Delete
  <noun> is the one tertiary verb, on an own activity the modal was
  opened from (the You card), named by its kind
  (`ActivityWords.noun/1`).

  The strip's bookmark lists a title and the tracking block below shows
  the controls once it is listed (UIDR-039): two acts, in order, on the
  same view. That is where a title gets listed and then armed, and where
  an owned one is stopped; Coming up and the watchlist open owned titles
  here, so the control cannot live only on the library detail. An owned
  title's files stay the library's — `In library` bridges to them.

  Pure rendering; every control bubbles to the `TitleDetailHost`:
  `close_title`, `title_download` (`mode` from the menu, none from the
  main segment), `title_mode_toggle`, `title_scope_toggle`,
  `title_menu_close`, `title_scope` (`choice`), `title_activity_delete`,
  `set_rung`, `reset_lower_quality`.

  Nav: the backdrop is the `title_detail` overlay
  (`config.overlays.title_detail`): the action strip is the
  `title_detail_body` TOOLBAR, whichever Download menu is open the
  `title_detail_menu` TREE nested inside it (BACK closes it), and the
  ladder strip the `title_detail_tracking` TOOLBAR in the body.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.FacetStrip
  alias MediaCentaurWeb.Components.GlassMenu
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Title.Pennant
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.ReleaseDates
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.TrackingControls
  alias MediaCentaurWeb.Components.Title.LowerQualityNote
  alias MediaCentaurWeb.Components.Title.WatchlistToggle
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.TitleRef

  attr :detail, TitleDetail, default: nil, doc: "the open title; nil = closed"

  attr :open_menu, :atom,
    default: nil,
    values: [nil, :mode, :scope],
    doc: "which of the Download control's menus is open: the other planning mode, or the scope"

  attr :download_scope, :atom, default: :first_season, values: [:first_season, :everything]

  attr :download_pending?, :boolean,
    default: false,
    doc: "a manual plan is being created — the split button is disabled and says so"

  attr :today, Date, required: true

  attr :review?, :boolean,
    default: false,
    doc:
      "whether the Review control is offered — the hosts pass `show_discovery`, the preference that gates the whole friend-network preview."

  def title_detail_modal(assigns) do
    assigns =
      assigns
      |> assign(:preview, assigns.detail && assigns.detail.preview)
      |> assign(:ref, assigns.detail && TitleRef.param(assigns.detail.ref))
      |> assign(:tracking, assigns.detail && assigns.detail.tracking)

    ~H"""
    <CinematicShell.cinematic_shell
      id="title-detail-modal"
      open={@detail != nil}
      dismiss={:ephemeral}
      on_close="close_title"
      present={@detail != nil}
      backdrop_url={backdrop_url(@detail, @preview)}
      scroll_key={@ref}
      view_key={:main}
      data-nav-overlay={@detail != nil && "title_detail"}
      data-dismiss-event="close_title"
    >
      <:hero_mast :if={@detail && @detail.friend_activity != []}>
        <Pennant.pennants activity={@detail.friend_activity} on_image />
      </:hero_mast>
      <:orientation>
        <div :if={@detail} class="px-6">
          <TitleLayer.lockup
            title={@detail.title.name}
            logo_url={(@preview && @preview.logo_url) || @detail.logo_url}
            tagline={@preview && @preview.tagline}
          />
          <div :if={@preview} class="mt-3 text-on-image">
            <MetadataRow.metadata_row
              badge_text={TitlePreview.badge_text(@preview)}
              items={@preview.metadata_items}
            />
          </div>
          <p
            :if={!@preview}
            class="mt-3 flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/55 text-on-image"
          >
            <.icon name={media_icon(@detail.title.media_type)} class="size-4" />
            <span>{media_label(@detail.title.media_type)}</span>
            <span :if={@detail.title.year} class="normal-case tracking-normal">
              · {@detail.title.year}
            </span>
          </p>
          <%!-- The action strip. The Download control's menus are zones
                nested inside it: the input system counts an item for its
                nearest zone, and BACK out of an open list closes it
                (`data-nav-dismiss-event`). After the primary, the same
                icon cluster the library panel's view controls wear: the
                bookmark (UIDR-039 — the listing act, and the only verb a
                title not on the list has) and the pencil Review. Then
                the `ml-auto` tertiary group. --%>
          <div class="mt-4 pb-5">
            <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
              <.primary
                detail={@detail}
                open_menu={@open_menu}
                download_scope={@download_scope}
                download_pending?={@download_pending?}
              />
              <WatchlistToggle.watchlist_toggle
                id="title-watchlist"
                rung={@detail.rung}
                event="set_rung"
                phx-value-ref={@ref}
              />
              <.button
                :if={@review?}
                id="title-review"
                variant="dismiss"
                size="sm"
                shape="circle"
                class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
                phx-click="title_review_open"
                data-nav-item
                tabindex="0"
                data-tip="Review"
                aria-label="Review"
              >
                <.icon name="hero-pencil-square" class="size-5" />
              </.button>
              <.tertiary detail={@detail} />
            </div>
          </div>
        </div>
      </:orientation>
      <:body>
        <div :if={@detail} class="space-y-6 px-1 pt-2">
          <%!-- The one thing a pennant cannot hold: a friend's words, in
                the list row's note idiom — name, then text. --%>
          <p :if={@detail.note} id="title-note" class="text-sm text-base-content/80">
            <span :if={@detail.sender} class="font-medium text-base-content/70">
              {@detail.sender}
            </span>
            {@detail.note}
          </p>

          <p :if={overview(@detail, @preview)} class="text-sm text-base-content/70">
            {overview(@detail, @preview)}
          </p>

          <FacetStrip.facet_strip :if={@preview && @preview.facets != []} facets={@preview.facets} />

          <%!-- One card: the switches on the left, what TMDB knows of the
                title's dates on the right (spec 2026-09-14, iteration 3).
                The switches show once the title is listed; the dates read
                out as soon as there is a calendar or a release window. --%>
          <div
            :if={tracking_block?(@detail, @tracking)}
            class="glass-inset flex flex-wrap gap-x-8 gap-y-4 rounded-lg p-4"
            data-nav-zone="title_detail_tracking"
          >
            <div
              :if={
                TrackingControls.control_form(@detail.rung) != :none or
                  @detail.lower_quality_accepted?
              }
              class="w-64 shrink-0 space-y-3"
            >
              <TrackingControls.tracking_controls
                id="title-tracking-controls"
                ref={@ref}
                rung={@detail.rung}
                media_type={@detail.title.media_type}
                release_ahead?={Logic.release_ahead?(@detail.title, @detail.release_window, @today)}
                complete?={@detail.complete?}
                approval_policy={PlanningMode.approval_policy(@detail.planning_mode)}
                acquisition?={@detail.acquisition?}
              />
              <LowerQualityNote.lower_quality_note
                id="title-lower-quality"
                ref={@ref}
                accepted?={@detail.lower_quality_accepted?}
              />
            </div>
            <ReleaseDates.release_dates
              :if={dates?(@detail, @tracking)}
              id="title-release-dates"
              media_type={@detail.title.media_type}
              release_window={@detail.release_window}
              timeline={timeline(@tracking)}
              today={@today}
              class="min-w-[14rem] max-w-sm flex-1"
            />
          </div>
        </div>
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  attr :detail, TitleDetail, required: true
  attr :open_menu, :atom, required: true, values: [nil, :mode, :scope]
  attr :download_scope, :atom, required: true, values: [:first_season, :everything]
  attr :download_pending?, :boolean, required: true

  defp primary(%{detail: %{primary: {:in_library, owner_id}}} = assigns) do
    assigns = assign(assigns, :owner_id, owner_id)

    ~H"""
    <.button
      id="title-in-library"
      navigate={"/library?selected=#{@owner_id}"}
      variant="primary"
      size="sm"
      data-nav-item
      tabindex="0"
    >
      In library <.icon name="hero-chevron-right-mini" class="size-4" />
    </.button>
    """
  end

  defp primary(%{detail: %{primary: {:state, :needs_review}}} = assigns) do
    ~H"""
    <.link
      id="title-needs-review"
      navigate="/incoming"
      class="inline-flex items-center gap-1 text-sm text-warning"
      data-nav-item
      tabindex="0"
    >
      Needs review <.icon name="hero-chevron-right-mini" class="size-4" />
    </.link>
    """
  end

  defp primary(%{detail: %{primary: {:state, state}}} = assigns) do
    assigns = assign(assigns, :marker, Logic.acquisition_marker(state))

    ~H"""
    <span id="title-acquisition-state" class="text-sm text-base-content/70">{@marker}</span>
    """
  end

  # The split's main segment performs the person's default planning
  # mode; the menu names the other. A series adds the scope select.
  defp primary(%{detail: %{primary: :download}} = assigns) do
    assigns = assign(assigns, :other_mode, PlanningMode.other(assigns.detail.planning_mode))

    ~H"""
    <GlassMenu.split_button
      id="title-download"
      open={@open_menu == :mode}
      on_toggle="title_mode_toggle"
      on_close="title_menu_close"
      menu_zone="title_detail_menu"
      menu_label="More download options"
      disabled={@download_pending?}
      phx-click="title_download"
    >
      {if @download_pending?, do: "Planning…", else: "Download"}
      <:item
        id="title-download-other"
        event="title_download"
        values={%{"mode" => Atom.to_string(@other_mode)}}
      >
        {Logic.planning_mode_label(@other_mode)}
      </:item>
    </GlassMenu.split_button>
    <GlassMenu.menu_select
      :if={@detail.scoped?}
      id="title-scope"
      open={@open_menu == :scope}
      on_toggle="title_scope_toggle"
      on_close="title_menu_close"
      menu_zone="title_detail_menu"
      value_label={Logic.download_scope_label(@download_scope)}
      label="Download scope"
    >
      <:item
        :for={scope <- [:first_season, :everything]}
        id={"title-scope-" <> Atom.to_string(scope)}
        event="title_scope"
        values={%{"choice" => Atom.to_string(scope)}}
        active={scope == @download_scope}
      >
        {Logic.download_scope_label(scope)}
      </:item>
    </GlassMenu.menu_select>
    """
  end

  # Nothing to download yet: the tracking-mode control below is the act.
  defp primary(%{detail: %{primary: nil}} = assigns), do: ~H""

  attr :detail, TitleDetail, required: true

  # The one quiet tertiary verb: Delete, for an own activity the modal
  # was opened from. Listing and de-listing were here as separate verbs
  # until the ladder made them two rungs of the control below.
  defp tertiary(assigns) do
    ~H"""
    <span class="ml-auto flex items-center gap-3">
      <button
        :if={@detail.own?}
        id="title-activity-delete"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="title_activity_delete"
        data-nav-item
        tabindex="0"
      >
        Delete {ActivityWords.noun(@detail.kind)}
      </button>
    </span>
    """
  end

  @doc "Whether the title is tracked above Off — the timeline and activity are only worth showing then."
  @spec followed?(TrackingDetail.t() | nil) :: boolean()
  def followed?(nil), do: false
  def followed?(%TrackingDetail{}), do: true

  # The artwork ladder (UIDR-021): the local cached tier the host
  # resolved, else the live preview's backdrop (poster as its fallback),
  # else nothing — the frame paints its placeholder.
  defp backdrop_url(nil, _preview), do: nil
  defp backdrop_url(%{backdrop_url: url}, _preview) when is_binary(url), do: url
  defp backdrop_url(_detail, %{backdrop_url: url}) when is_binary(url), do: url
  defp backdrop_url(_detail, %{poster_url: url}) when is_binary(url), do: url
  defp backdrop_url(_detail, _preview), do: nil

  # The live preview's overview when it has landed, else the snapshot's.
  defp overview(_detail, %TitlePreview{overview: overview}) when is_binary(overview), do: overview
  defp overview(%{title: %{overview: overview}}, _preview), do: overview

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"

  # The readout has something to say once there is a calendar, or a movie's
  # live release window; the card renders when it has that or a listed
  # title's switches to show.
  defp dates?(%TitleDetail{title: %{media_type: :movie}, release_window: %{}}, _tracking), do: true
  defp dates?(_detail, tracking), do: followed?(tracking)

  defp tracking_block?(%TitleDetail{} = detail, tracking) do
    dates?(detail, tracking) or TrackingControls.control_form(detail.rung) != :none or
      detail.lower_quality_accepted?
  end

  defp timeline(%{timeline: timeline}), do: timeline
  defp timeline(_untracked), do: []
end
