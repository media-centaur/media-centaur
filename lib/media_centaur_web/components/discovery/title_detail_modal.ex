defmodule MediaCentaurWeb.Components.Discovery.TitleDetailModal do
  @moduledoc """
  The Discovery title detail modal (spec 2026-09-05 §12–16): the depth
  surface for a TMDB title the library does not own, opened by a
  whole-card click on a feed row or a watchlist row. A tenant of the
  cinematic frame like the tracking title modal — backdrop, lockup,
  type and year, overview, and on a feed-born detail the sender and
  their note — rendered from the embedded `TMDB.Title` snapshot with no
  network call on open.

  The action row is the watchlist row's honest three-state rule lifted
  into the modal, with the acquisition state folded in: In library →
  the library detail; Planning / Downloading / Needs review → a stated
  fact (Needs review links to Downloads); Download when the title is
  released and an indexer is ready; Track release otherwise. A series
  Download is a split control — "Download season 1" plus a chevron
  opening "Download all" — reusing the `glass-menu` idiom the library
  sort control wears. Add to watchlist is the secondary, replaced by a
  quiet On watchlist once saved, at which point Remove from watchlist
  appears as a quiet tertiary verb from either tab. Delete
  recommendation is the other tertiary verb, on an own recommendation
  only.

  Pure rendering; every control bubbles to `DiscoveryLive`:
  `close_title`, `title_download` (`scope` for a series),
  `title_scope_toggle`, `title_scope_close`, `title_track`,
  `title_watchlist_add`, `title_watchlist_remove`,
  `title_recommendation_delete`.

  Nav: the backdrop is the `title_detail` overlay with one body region
  (`config.overlays.title_detail`); every control is a nav item.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.DiscoveryLive.Logic

  attr :detail, TitleDetail, default: nil, doc: "the open title; nil = closed"
  attr :scope_menu_open, :boolean, default: false, doc: "the series scope menu is showing"

  def title_detail_modal(assigns) do
    ~H"""
    <CinematicShell.cinematic_shell
      id="title-detail-modal"
      open={@detail != nil}
      dismiss={:ephemeral}
      on_close="close_title"
      present={@detail != nil}
      backdrop_url={@detail && @detail.backdrop_url}
      scroll_key={@detail && Logic.title_ref_param(@detail.ref)}
      view_key={:main}
      data-nav-overlay={@detail != nil && "title_detail"}
      data-dismiss-event="close_title"
    >
      <:orientation>
        <div :if={@detail} class="px-6">
          <TitleLayer.lockup title={@detail.title.name} />
          <p class="mt-3 flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/55 text-on-image">
            <.icon name={media_icon(@detail.title.media_type)} class="size-4" />
            <span>{media_label(@detail.title.media_type)}</span>
            <span :if={@detail.title.year} class="normal-case tracking-normal">
              · {@detail.title.year}
            </span>
          </p>
          <div
            class="mt-4 flex flex-wrap items-center gap-3 pb-5"
            data-nav-zone="title_detail_body"
          >
            <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
            <.secondary detail={@detail} />
            <.tertiary detail={@detail} />
          </div>
        </div>
      </:orientation>
      <:body>
        <div :if={@detail} class="space-y-4 px-1 pt-2">
          <p :if={@detail.own?} class="text-xs text-base-content/55">
            You recommended this · {Format.relative_ago(@detail.recommended_at)}
          </p>
          <p :if={@detail.sender} class="text-xs text-base-content/55">
            Recommended by {@detail.sender} · {Format.relative_ago(@detail.recommended_at)}
          </p>
          <p :if={@detail.note} class="text-sm">{@detail.note}</p>
          <p :if={@detail.title.overview} class="text-sm text-base-content/70">
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
    <span class="glass-menu" phx-click-away="title_scope_close" data-captures-keys={@scope_menu_open}>
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
      <ul :if={@scope_menu_open} id="title-scope-menu" class="glass-menu-list glass-surface">
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

  defp primary(%{detail: %{primary: :track}} = assigns) do
    ~H"""
    <.button
      id="title-track"
      variant="primary"
      size="sm"
      phx-click="title_track"
      data-nav-item
      tabindex="0"
    >
      Track release
    </.button>
    """
  end

  attr :detail, TitleDetail, required: true

  defp secondary(%{detail: %{on_watchlist?: true}} = assigns) do
    ~H"""
    <span id="title-on-watchlist" class="text-sm text-base-content/55">On watchlist</span>
    """
  end

  defp secondary(assigns) do
    ~H"""
    <.button
      id="title-watchlist-add"
      variant="secondary"
      size="sm"
      phx-click="title_watchlist_add"
      data-nav-item
      tabindex="0"
    >
      Add to watchlist
    </.button>
    """
  end

  attr :detail, TitleDetail, required: true

  # Quiet tertiary verbs, each only when it applies: Remove when the
  # title is on the watchlist, Delete for an own recommendation.
  defp tertiary(assigns) do
    ~H"""
    <span class="ml-auto flex items-center gap-3">
      <button
        :if={@detail.on_watchlist?}
        id="title-watchlist-remove"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="title_watchlist_remove"
        data-nav-item
        tabindex="0"
      >
        Remove from watchlist
      </button>
      <button
        :if={@detail.own?}
        id="title-recommendation-delete"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="title_recommendation_delete"
        data-nav-item
        tabindex="0"
      >
        Delete recommendation
      </button>
    </span>
    """
  end

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"
end
