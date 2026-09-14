defmodule MediaCentaurWeb.Components.Detail.ViewControls do
  @moduledoc """
  The controls sharing the action row with the primary (UIDR-043): the
  one view control, the Letterboxd link, the bookmark, Review and the
  Manage cog — each present by what the detail's facts say.

  ## The view control

  One slot, named for its destination, never "Back". `Detail.Logic.secondary_view/2`
  decides where it leads from the subject's type and extras: Cast on
  the main view when the subject has a cast; back to the body from
  anywhere else, labelled for that body (`body_label/1` — "Episodes",
  "Movies", "Extras", "Overview"); nothing when the current view is the
  only one. An unowned title has no views, so no control.

  ## Manage

  The cog after everything else, only for an owned title (its files).
  It keeps its label while Manage is open (`aria-pressed`); the way out
  is the view control named for its destination.

  ## Letterboxd, bookmark, Review

  A movie with a TMDB identity gets the Letterboxd link (gated by the
  `letterboxd_links` setting). Any title with a TMDB identity gets the
  bookmark (`Title.WatchlistToggle`, UIDR-039) firing `set_rung` with
  the `choice` the control decided and the title's `ref`, and, when the
  friend network is on (`review?`), the pencil that opens the Review
  modal (`review_open`). The residue — an owned entity with no TMDB
  identity — gets none of the three.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.WatchlistToggle
  alias MediaCentaurWeb.TitleRef

  attr :detail, TitleDetail, required: true

  attr :view, :atom,
    required: true,
    values: [:main, :cast, :info],
    doc: "the showing view."

  attr :letterboxd_links, :boolean,
    default: true,
    doc:
      "the `letterboxd_links` setting — whether a movie with a TMDB identity gets the Letterboxd link."

  attr :review?, :boolean,
    default: false,
    doc:
      "whether the Review control is offered — the hosts pass `show_discovery`, the preference that gates the whole friend-network preview."

  def view_controls(assigns) do
    detail = assigns.detail
    entity = detail.library && Logic.controls_entity(detail.library)

    assigns =
      assigns
      |> assign(:entity, entity)
      |> assign(:destination, entity && Logic.secondary_view(entity, assigns.view))
      |> assign(:ref, detail.ref && TitleRef.param(detail.ref))
      |> assign(:letterboxd?, assigns.letterboxd_links and match?({_id, :movie}, detail.ref))
      |> assign(:tmdb_id, detail.ref && elem(detail.ref, 0))

    ~H"""
    <.view_button
      :if={@destination == :main}
      view="main"
      icon="hero-bars-3-bottom-left-mini"
    >
      {Logic.body_label(@entity)}
    </.view_button>
    <.view_button :if={@destination == :cast} view="cast" icon="hero-user-group-mini">
      Cast
    </.view_button>
    <.button
      :if={@letterboxd?}
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      href={Logic.letterboxd_url(@tmdb_id)}
      target="_blank"
      rel="noopener"
      data-tip="Open on Letterboxd"
      aria-label="Open on Letterboxd"
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        class="size-5"
        aria-hidden="true"
      >
        <circle cx="6.5" cy="12" r="4.25" /><circle cx="12" cy="12" r="4.25" /><circle
          cx="17.5"
          cy="12"
          r="4.25"
        />
      </svg>
    </.button>
    <WatchlistToggle.watchlist_toggle
      :if={@ref}
      id="detail-watchlist-toggle"
      rung={@detail.rung}
      event="set_rung"
      phx-value-ref={@ref}
    />
    <.button
      :if={@review? && @ref}
      id="detail-review"
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      phx-click="review_open"
      data-nav-item
      tabindex="0"
      data-tip="Review"
      aria-label="Review"
    >
      <.icon name="hero-pencil-square" class="size-5" />
    </.button>
    <.button
      :if={@entity}
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      phx-click="select_detail_view"
      phx-value-view={if @view == :info, do: "main", else: "info"}
      data-role="manage-toggle"
      data-nav-item
      tabindex="0"
      aria-pressed={to_string(@view == :info)}
      aria-label="Manage"
      data-tip="Manage"
    >
      <.icon name="hero-cog-6-tooth-mini" class="size-5" />
    </.button>
    """
  end

  attr :view, :string, required: true, doc: "the view this button selects, as a URL value."
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp view_button(assigns) do
    ~H"""
    <.button
      variant="secondary"
      size="sm"
      phx-click="select_detail_view"
      phx-value-view={@view}
      data-role="view-control"
      data-nav-item
      tabindex="0"
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.button>
    """
  end
end
