defmodule MediaCentaurWeb.Components.Detail.ViewControls do
  @moduledoc """
  The modal's view controls — a soft button and a Manage cog, sharing Play's
  line.

  ## One control, named for where it goes

  Where the button leads is decided by `Logic.secondary_view/2`; this module
  only turns that destination into a label and a glyph:

  | destination | reads | glyph |
  |---|---|---|
  | `:main` | `Logic.body_label/1` — *Episodes*, *Movies*, *Extras*, *Overview* | list |
  | `:cast` | *Cast* | people |
  | `nil` | nothing — Play's line carries only the cog | — |

  It is never labelled *Back*. "Episodes" says where you are going; "Back"
  only says it is not here, and what it means depends on which view you
  happen to be in. Every entity opens on its main view — for a bare movie
  that is the hero page alone, so the control returning there from Cast or
  Manage reads "Overview".

  One control, in one slot. Until 2026-08-07 there were two, each
  relabelling itself to "Back" when its own view was open, so the word moved
  between the second and third slot depending on which sub-view was showing
  and no position in the row meant one thing.

  A tab strip was tried in between and reverted: it spans the panel and
  lands a band of chrome on the exact seam the eye crosses going from Play
  to the episode list, which is the worst place in the modal to put
  anything.

  ## Manage

  A quiet icon button, last, carrying `aria-pressed` rather than a label
  change — so the row's text never shifts. Files, external ids, rematch,
  refresh artwork: work a title needs once, not a third thing to do with
  it. Reachable from the couch because it is a `data-nav-item` of the
  enclosing `detail_actions` zone (UIDR-019); the hero's icon cluster, the
  other place it could live, is mouse-only.

  ## Letterboxd

  A movie subject with a TMDB id gets a second quiet icon button before
  the cog: the film's Letterboxd page, via the stable
  `letterboxd.com/tmdb/<id>` redirect (no API or scraping) — where a
  logged-in user logs a diary entry and reads community ratings. Movies
  only (Letterboxd has no TV), gated by the `letterboxd_links` setting.
  Deliberately NOT a `data-nav-item`: opening an external site from the
  couch shell is a trap, so the couch walk skips it and the pointer gets
  it.

  ## Watchlist

  A movie or TV subject with a TMDB id gets a bookmark toggle between the
  Letterboxd link and the cog — the same flip idiom as the search-row
  bookmark (`MediaResults`): outline off-list, solid + primary tint
  on-list, state carried by `aria-pressed`. Fires `modal_watchlist_toggle`,
  handled by the injected `EntityModal` clause; the rendered state comes
  from the host's `:watchlisted_refs` (`WatchlistAware`), threaded down as
  `watchlisted?`. In-app action, so unlike Letterboxd it IS a
  `data-nav-item`.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.Logic

  attr :entity, :map,
    required: true,
    doc:
      "entity-map from `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Read for `:type` and `:extras` (via `Detail.Logic`) to decide which control belongs here, and for `:tmdb_id` for the Letterboxd link."

  attr :detail_view, :atom,
    required: true,
    doc: "the showing view — `:main`, `:cast` or `:info`."

  attr :letterboxd_links, :boolean,
    default: true,
    doc: "the `letterboxd_links` setting — whether a movie subject gets the Letterboxd link."

  attr :watchlisted?, :boolean,
    default: false,
    doc:
      "whether the subject is on the watchlist — flips the bookmark toggle solid. Compute via `EntityModal.watchlisted?/3` so it matches what `modal_watchlist_toggle` acts on."

  def view_controls(assigns) do
    assigns = assign(assigns, :destination, Logic.secondary_view(assigns.entity, assigns.detail_view))

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
      :if={@letterboxd_links && @entity.type == :movie && @entity[:tmdb_id]}
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      href={Logic.letterboxd_url(@entity[:tmdb_id])}
      target="_blank"
      rel="noopener"
      title="Open on Letterboxd"
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
    <.button
      :if={@entity[:tmdb_id] && @entity.type in [:movie, :tv_series]}
      id="detail-watchlist-toggle"
      variant="dismiss"
      size="sm"
      shape="circle"
      class={[
        "ml-1 transition-opacity",
        if(@watchlisted?, do: "text-primary", else: "opacity-60 hover:opacity-100")
      ]}
      phx-click="modal_watchlist_toggle"
      data-nav-item
      tabindex="0"
      aria-pressed={to_string(@watchlisted?)}
      title={if @watchlisted?, do: "Remove from watchlist", else: "Add to watchlist"}
      aria-label={if @watchlisted?, do: "Remove from watchlist", else: "Add to watchlist"}
    >
      <.icon name={if @watchlisted?, do: "hero-bookmark-solid", else: "hero-bookmark"} class="size-5" />
    </.button>
    <.button
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      phx-click="select_detail_view"
      phx-value-view={if @detail_view == :info, do: "main", else: "info"}
      data-role="manage-toggle"
      data-nav-item
      tabindex="0"
      aria-pressed={to_string(@detail_view == :info)}
      aria-label="Manage"
      title="Manage"
    >
      <.icon name="hero-cog-6-tooth-mini" class="size-5" />
    </.button>
    """
  end

  attr :view, :string, required: true, doc: "`detail_view` this button selects, as a URL value."
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
