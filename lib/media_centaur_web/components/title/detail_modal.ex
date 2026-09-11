defmodule MediaCentaurWeb.Components.Title.DetailModal do
  @moduledoc """
  The title detail modal — the one depth surface for a title without
  files (UIDR-035): watchlisted, tracked, in flight, or merely
  recommended, on Discovery and on Incoming alike. A tenant of the
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
  arming is the ladder control's job (ADR-065). A series Download is a
  split control — "Download season 1" plus a chevron opening "Download
  all" — reusing the `glass-menu` idiom. Neither follows the series: a
  scope covers episodes that have aired, and what is still to come is
  the ladder's business, never a download's (ADR-066). Delete <noun> is
  the one tertiary verb, on an own activity the
  modal was opened from (the You card), named by its kind
  (`ActivityWords.noun/1`).

  The strip's bookmark lists a title and the tracking block below shows
  the controls once it is listed (UIDR-039): two acts, in order, on the
  same view. That is where a title gets listed and then armed, and where
  an owned one is stopped; Coming up and the watchlist open owned titles
  here, so the control cannot live only on the library detail. An owned
  title's files stay the library's — `In library` bridges to them.

  Pure rendering; every control bubbles to the `TitleDetailHost`:
  `close_title`, `title_download` (`scope` for a series),
  `title_scope_toggle`, `title_scope_close`, `title_activity_delete`,
  `set_rung`, `reset_lower_quality`.

  Nav: the backdrop is the `title_detail` overlay
  (`config.overlays.title_detail`): the action strip is the
  `title_detail_body` TOOLBAR, the open scope menu the
  `title_detail_menu` TREE beneath it, and the ladder strip the
  `title_detail_tracking` TOOLBAR in the body — siblings in the DOM,
  because nav zones must not nest.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.FacetStrip
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Title.Pennant
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.ReleaseTimeline
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.IntentControl
  alias MediaCentaurWeb.Components.Title.WatchlistToggle
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.TitleRef

  attr :detail, TitleDetail, default: nil, doc: "the open title; nil = closed"
  attr :scope_menu_open, :boolean, default: false, doc: "the series scope menu is showing"
  attr :today, Date, required: true

  attr :recommend?, :boolean,
    default: false,
    doc:
      "whether the Recommend control is offered — the hosts pass `show_discovery`, the preference that gates the whole friend-network preview."

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
          <%!-- The scope menu is a sibling of the action strip, not a child:
                nav zones must not nest, and the menu is its own region
                (`title_detail_menu`, reached by DOWN from the strip). The
                wrapper is the `.glass-menu` anchor, so the list opens under
                the strip's first control — the split Download button. --%>
          <div class="mt-4 pb-5">
            <div class="glass-menu" phx-click-away="title_scope_close">
              <%!-- After the primary, the same icon cluster the library
                    panel's view controls wear: the bookmark (UIDR-039 — the
                    listing act, and the only verb a title not on the list
                    has) and the paper-plane Recommend. Then the `ml-auto`
                    tertiary group. --%>
              <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
                <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
                <WatchlistToggle.watchlist_toggle
                  id="title-watchlist"
                  rung={@detail.rung}
                  event="set_rung"
                  phx-value-ref={@ref}
                />
                <.button
                  :if={@recommend?}
                  id="title-recommend"
                  variant="dismiss"
                  size="sm"
                  shape="circle"
                  class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
                  phx-click="title_recommend_open"
                  data-nav-item
                  tabindex="0"
                  title="Recommend"
                  aria-label="Recommend"
                >
                  <.icon name="hero-paper-airplane" class="size-5" />
                </.button>
                <.tertiary detail={@detail} />
              </div>
              <ul
                :if={@scope_menu_open}
                id="title-scope-menu"
                class="glass-menu-list glass-menu-list--content glass-surface"
                data-nav-zone="title_detail_menu"
              >
                <li
                  class="glass-menu-item"
                  phx-click="title_download"
                  phx-value-scope="everything"
                  data-nav-item
                  tabindex="0"
                >
                  Download all
                </li>
              </ul>
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

          <div data-nav-zone="title_detail_tracking">
            <IntentControl.intent_control
              id="title-tracking-mode"
              ref={@ref}
              rung={@detail.rung}
              default_grab_mode={@detail.default_grab_mode}
              acquisition?={@detail.acquisition?}
              lower_quality_accepted?={@detail.lower_quality_accepted?}
            />
          </div>

          <ReleaseTimeline.release_timeline
            :if={followed?(@tracking)}
            id="title-release-timeline"
            timeline={@tracking.timeline}
            today={@today}
          />

          <section :if={followed?(@tracking) and @tracking.activity != []} class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
              Recent activity
            </h3>
            <ul class="space-y-1.5">
              <li
                :for={entry <- @tracking.activity}
                class="flex items-baseline justify-between gap-3 text-sm"
              >
                <span class="text-base-content/70">{entry.text}</span>
                <span class="shrink-0 text-xs tabular-nums text-base-content/55">{entry.at}</span>
              </li>
            </ul>
          </section>
        </div>
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  attr :detail, TitleDetail, required: true
  attr :scope_menu_open, :boolean, required: true

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

  defp primary(%{detail: %{primary: :download, scoped?: true}} = assigns) do
    ~H"""
    <span class="inline-flex">
      <.button
        id="title-download"
        variant="primary"
        size="sm"
        class="rounded-r-none"
        phx-click="title_download"
        phx-value-scope="first_season"
        data-nav-item
        tabindex="0"
      >
        Download season 1
      </.button>
      <.button
        id="title-scope-toggle"
        variant="primary"
        size="sm"
        shape="square"
        class="rounded-l-none border-l border-primary-content/20"
        phx-click="title_scope_toggle"
        aria-label="More download options"
        aria-expanded={to_string(@scope_menu_open)}
        data-nav-item
        tabindex="0"
      >
        <span class={["glass-menu-chevron", @scope_menu_open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </.button>
    </span>
    """
  end

  defp primary(%{detail: %{primary: :download}} = assigns) do
    ~H"""
    <.button
      id="title-download"
      variant="primary"
      size="sm"
      phx-click="title_download"
      data-nav-item
      tabindex="0"
    >
      Download
    </.button>
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
end
