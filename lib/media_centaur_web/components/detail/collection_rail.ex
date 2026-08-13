defmodule MediaCentaurWeb.Components.Detail.CollectionRail do
  @moduledoc """
  The movie-first collection modal's picker (UIDR-023): one 16:9
  backdrop-and-logo tile per member movie — the continue-watching card
  idiom in miniature, previewing exactly the hero that selecting it
  installs — announced-but-unreleased parts as muted unpickable tiles,
  and a saga label line carrying the collection name and watched count.

  Picking a tile **selects** — it re-anchors the whole modal to that
  member via the host's `select_movie` event (URL patch). It never
  plays; Play stays the panel's only playback affordance.

  Renders from the same typed `[%MediaCentaurWeb.ViewModel.MovieListItem{}]`
  list `CollectionDetail.compose/1` builds. Per-member state rides the
  tile: watched check badge, progress underline on the in-progress
  member (`Detail.PlayableRow.progress_underline/1`, shared with the
  episode rows), date pill on upcoming parts. Collection-level extras
  are **not** a rail tile — they keep the leaf idiom and render as an
  `ExtrasSection` in the modal body.

  The tile strip is the `detail_rail` nav zone (TOOLBAR): LEFT/RIGHT
  walk it, DOWN from the action row enters it, A selects.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers
  import MediaCentaurWeb.LibraryFormatters, only: [extract_year: 1]

  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.PlayableRow
  alias MediaCentaurWeb.ViewModel.MovieListItem

  attr :movie_items, :list,
    required: true,
    doc:
      "`[%MediaCentaurWeb.ViewModel.MovieListItem{}]` from `CollectionDetail.compose/1` — tagged `Library` / `Upcoming` items in display order."

  attr :selected_id, :string,
    required: true,
    doc: "the selected member's movie id — its tile carries `data-selected` and the selection ring."

  attr :saga_label, :string, required: true, doc: "collection name for the rail's label line."

  attr :available, :boolean,
    default: true,
    doc: "storage availability — poster images are dropped when the media dir is offline."

  def collection_rail(assigns) do
    assigns = assign(assigns, :progress_note, Logic.saga_progress_note(assigns.movie_items))

    ~H"""
    <div class="px-4 pb-6" data-role="collection-rail">
      <div class="flex items-baseline justify-between mb-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
          {@saga_label}
        </h3>
        <span :if={@progress_note} class="text-xs text-base-content/40">{@progress_note}</span>
      </div>
      <div class="flex gap-3 overflow-x-auto thin-scrollbar pb-1" data-nav-zone="detail_rail">
        <.rail_tile
          :for={item <- @movie_items}
          item={item}
          selected={match?(%MovieListItem.Library{}, item) && item.movie.id == @selected_id}
          available={@available}
        />
      </div>
    </div>
    """
  end

  # --- Tile dispatch on the MovieListItem variant ---

  attr :item, :map, required: true, doc: "%MovieListItem.{Library | Upcoming}{}"
  attr :selected, :boolean, default: false
  attr :available, :boolean, default: true

  # A miniature of the hero the tile would install: 16:9 backdrop with
  # the member's logo art (title-text fallback), the continue-watching
  # card idiom scaled to the rail. The tile previews exactly what
  # selecting does.
  defp rail_tile(%{item: %MovieListItem.Library{}} = assigns) do
    movie = assigns.item.movie

    assigns =
      assigns
      |> assign(:movie, movie)
      |> assign(
        :backdrop_url,
        assigns.available && (image_url(movie, "backdrop") || image_url(movie, "poster"))
      )
      |> assign(:logo_url, assigns.available && image_url(movie, "logo"))

    ~H"""
    <button
      id={"rail-tile-#{@movie.id}"}
      type="button"
      phx-click="select_movie"
      phx-value-id={@movie.id}
      data-selected={@selected || nil}
      data-nav-item
      tabindex="0"
      title={@movie.name}
      class="group relative flex-shrink-0 w-48 aspect-[16/9] rounded-lg overflow-hidden glass-inset text-left cursor-pointer"
    >
      <img
        :if={@backdrop_url}
        src={sized_image_url(@backdrop_url, 480)}
        alt={@movie.name}
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="eager"
        decoding="sync"
      />
      <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent"></div>
      <%!-- Selection ring as an OVERLAY, never `outline` and never a
            box-shadow on the button itself: the input system pre-sets
            outline-color on every nav item in keyboard/gamepad mode
            (the cursor owns the outline channel, UIDR-020), and an
            inset box-shadow paints BEHIND children, so the backdrop img
            would swallow it. A topmost inset-0 div is the one place the
            ring is both visible and out of the cursor's way. --%>
      <div class={[
        "absolute inset-0 rounded-lg ring-2 ring-inset pointer-events-none transition-shadow",
        (@selected && "ring-white/90") || "ring-transparent group-hover:ring-white/30"
      ]}>
      </div>
      <div class="absolute bottom-2.5 left-3 right-3">
        <img
          :if={@logo_url}
          src={sized_image_url(@logo_url, 320)}
          alt={@movie.name}
          class="max-h-9 max-w-[85%] object-contain object-left text-on-image-lg"
          loading="eager"
          decoding="sync"
        />
        <div :if={!@logo_url} class="text-sm font-semibold text-white text-on-image-lg truncate">
          {@movie.name}
          <span :if={@movie.date_published} class="text-white/50 font-normal ml-0.5">
            {extract_year(@movie.date_published)}
          </span>
        </div>
      </div>
      <span
        :if={@item.state == :watched}
        data-rail-state="watched"
        class="absolute top-1.5 right-1.5 size-5 rounded-full bg-black/75 ring-1 ring-white/15 flex items-center justify-center"
      >
        <.icon name="hero-check-mini" class="size-3.5 text-success" />
      </span>
      <div :if={@item.state == :current} data-rail-state="current" class="absolute inset-x-0 bottom-0">
        <PlayableRow.progress_underline progress={@item.progress} class="mt-0 rounded-none" />
      </div>
    </button>
    """
  end

  # An announced part (release-tracking overlay): muted, unpickable —
  # same contract as the retired upcoming row, in tile form. Not a
  # nav item until it becomes selectable.
  defp rail_tile(%{item: %MovieListItem.Upcoming{}} = assigns) do
    ~H"""
    <div
      id={"rail-upcoming-#{@item.part_tmdb_id}"}
      data-role="rail-upcoming"
      title={@item.title}
      class="relative flex-shrink-0 w-48 aspect-[16/9] rounded-lg border border-dashed border-base-content/15 opacity-55"
    >
      <div class="absolute inset-0 flex items-center justify-center">
        <.badge variant="ghost" size="sm" class="gap-1">
          <.icon name="hero-calendar-mini" class="size-3" />
          {Logic.upcoming_pill_copy(@item)}
        </.badge>
      </div>
      <div class="absolute bottom-2.5 left-3 right-3 text-sm font-semibold text-base-content/60 truncate">
        {@item.title}
      </div>
    </div>
    """
  end
end
