defmodule MediaCentaurWeb.Components.Discovery.TitleDetailModal do
  @moduledoc """
  The title detail modal — the one depth surface for a title without
  files (UIDR-035): watchlisted, tracked, in flight, or merely
  recommended, on Discovery and on Incoming alike. A tenant of the
  cinematic frame: backdrop, lockup, type and year, the action strip,
  then — for a title the library does not own — the two shared tracking
  components, the recent per-title activity, and the overview. Rendered
  from the embedded `TMDB.Title` snapshot plus the local artwork cache,
  with no network call on open; the live TMDB preview dresses it when
  it lands.

  The action strip is the watchlist row's honest rule with the
  acquisition state folded in: In library → the library detail;
  Planning / Downloading / Needs review → a stated fact (Needs review
  links to Incoming); Download when the title is out and an indexer is
  ready; otherwise no primary verb — there is no `Track`, because
  arming is the tracking-mode control's job (ADR-065). A series
  Download is a split control — "Download season 1" plus a chevron
  opening "Download all" and "Download all and track" — reusing the
  `glass-menu` idiom. Only the last of the three follows the series:
  a scope covers episodes that have aired, and what is still to come is
  a separate act. Add to
  watchlist add/remove are gone as verbs: they were the bottom two rungs
  of the ladder wearing a different control, and the ladder is one
  control now. Delete <noun> is the one tertiary verb, on an own activity
  only, named by its kind (`ActivityWords.noun/1`).

  Below the strip, for every title: the release timeline
  (`ReleaseTimeline`, while the title is tracked and armed), the
  tracking-mode control (`TrackingModeControl`, always — it is where an
  untracked title gets armed, and where an owned one, tracked because
  the library owns it (ADR-065), is stopped; Coming up and the watchlist
  open owned titles here, so the control cannot live only on the library
  detail), recent activity, then the preview body or the snapshot
  overview. An owned title's files stay the library's — `In library`
  bridges to them.

  Pure rendering; every control bubbles to the `TitleDetailHost`:
  `close_title`, `title_download` (`scope` for a series),
  `title_scope_toggle`, `title_scope_close`, `title_watchlist_add`,
  `title_watchlist_remove`, `title_activity_delete`,
  `set_rung`, `reset_lower_quality`.

  Nav: the backdrop is the `title_detail` overlay
  (`config.overlays.title_detail`): the action strip is the
  `title_detail_body` TOOLBAR, the open scope menu the
  `title_detail_menu` TREE beneath it, and the tracking-mode strip the
  `title_detail_tracking` TOOLBAR in the body — siblings in the DOM,
  because nav zones must not nest.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.PreviewBody
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Discovery.RecommendationPennant
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.ReleaseTimeline
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Discovery.IntentControl
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.DiscoveryLive.Logic
  alias MediaCentaurWeb.TitleRef

  attr :detail, TitleDetail, default: nil, doc: "the open title; nil = closed"
  attr :scope_menu_open, :boolean, default: false, doc: "the series scope menu is showing"
  attr :today, Date, required: true

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
      <:hero_mast :if={@detail && @detail.recommendations != []}>
        <RecommendationPennant.recommendation_pennants
          recommendations={@detail.recommendations}
          on_image
        />
      </:hero_mast>
      <:orientation>
        <div :if={@detail} class="px-6">
          <TitleLayer.lockup
            title={@detail.title.name}
            logo_url={(@preview && @preview.logo_url) || @detail.logo_url}
            tagline={@preview && @preview.tagline}
          />
          <p class="mt-3 flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/55 text-on-image">
            <.icon name={media_icon(@detail.title.media_type)} class="size-4" />
            <span>{media_label(@detail.title.media_type)}</span>
            <span :if={@detail.title.year} class="normal-case tracking-normal">
              · {@detail.title.year}
            </span>
            <span :if={followed?(@tracking)} class="normal-case tracking-normal">
              · Tracking since {tracking_since_label(@tracking.tracking_since)}
            </span>
          </p>
          <%!-- The scope menu is a sibling of the action strip, not a child:
                nav zones must not nest, and the menu is its own region
                (`title_detail_menu`, reached by DOWN from the strip). The
                wrapper is the `.glass-menu` anchor, so the list opens under
                the strip's first control — the split Download button. --%>
          <div class="mt-4 pb-5">
            <div class="glass-menu" phx-click-away="title_scope_close">
              <div class="flex flex-wrap items-center gap-3" data-nav-zone="title_detail_body">
                <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
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
                <li
                  class="glass-menu-item"
                  phx-click="title_download"
                  phx-value-scope="everything"
                  phx-value-track="true"
                  data-nav-item
                  tabindex="0"
                >
                  Download all and track
                </li>
              </ul>
            </div>
          </div>
        </div>
      </:orientation>
      <:body>
        <div :if={@detail} class="space-y-6 px-1 pt-2">
          <div
            :if={@detail.own? || @detail.sender || @detail.note}
            class="space-y-2"
            id="title-provenance"
          >
            <p :if={@detail.own?} class="text-xs text-base-content/55">
              {ActivityWords.statement("You", @detail.kind, @detail.episode)} · {Format.relative_ago(
                @detail.acted_at
              )}
            </p>
            <p :if={@detail.sender} class="text-xs text-base-content/55">
              {ActivityWords.statement(@detail.sender, @detail.kind, @detail.episode)} · {Format.relative_ago(
                @detail.acted_at
              )}
            </p>
            <p :if={@detail.note} class="text-sm">{@detail.note}</p>
          </div>

          <ReleaseTimeline.release_timeline
            :if={followed?(@tracking)}
            id="title-release-timeline"
            timeline={@tracking.timeline}
            today={@today}
          />

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

          <PreviewBody.preview_body :if={@preview} preview={@preview} />
          <p :if={!@preview && @detail.title.overview} class="text-sm text-base-content/70">
            {@detail.title.overview}
          </p>
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

  # The one quiet tertiary verb: Delete, for an own activity. Listing and
  # de-listing were here as separate verbs until the ladder made them two
  # rungs of the control below.
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

  defp tracking_since_label(nil), do: "recently"
  defp tracking_since_label(datetime), do: Calendar.strftime(datetime, "%b %Y")

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"
end
