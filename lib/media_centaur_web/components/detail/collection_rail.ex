defmodule MediaCentaurWeb.Components.Detail.CollectionRail do
  @moduledoc """
  The movie-first collection modal's picker (UIDR-023): one 2:3 poster
  tile per member movie, announced-but-unreleased parts as muted
  unpickable tiles, and a saga label line carrying the collection name
  and watched count.

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

  defp rail_tile(%{item: %MovieListItem.Library{}} = assigns) do
    assigns =
      assigns
      |> assign(:movie, assigns.item.movie)
      |> assign(:poster_url, assigns.available && image_url(assigns.item.movie, "poster"))

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
      class="group flex-shrink-0 w-24 text-left cursor-pointer"
    >
      <div class={[
        "relative aspect-[2/3] rounded-lg overflow-hidden glass-inset",
        "outline-offset-2 transition-[outline-color]",
        (@selected && "outline-2 outline-white/90") ||
          "outline-2 outline-transparent group-hover:outline-white/30"
      ]}>
        <img
          :if={@poster_url}
          src={sized_image_url(@poster_url, 320)}
          alt={@movie.name}
          class="w-full h-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <div
          :if={!@poster_url}
          class="w-full h-full flex items-end p-1.5 bg-base-content/5"
        >
          <span class="text-[10px] font-semibold leading-tight text-base-content/70 line-clamp-4">
            {@movie.name}
          </span>
        </div>
        <span
          :if={@item.state == :watched}
          data-rail-state="watched"
          class="absolute top-1 right-1 size-5 rounded-full bg-black/75 ring-1 ring-white/15 flex items-center justify-center"
        >
          <.icon name="hero-check-mini" class="size-3.5 text-success" />
        </span>
        <div
          :if={@item.state == :current}
          data-rail-state="current"
          class="absolute inset-x-0 bottom-0"
        >
          <PlayableRow.progress_underline progress={@item.progress} class="mt-0 rounded-none" />
        </div>
      </div>
      <%!-- Two lines, not one-line truncation: sequels share their prefix,
            so cutting the tail erases exactly the distinguishing part. --%>
      <div class="mt-1.5 text-[11px] leading-tight line-clamp-2 text-base-content/60">
        {@movie.name}
        <span :if={@movie.date_published} class="text-base-content/30 ml-0.5">
          {extract_year(@movie.date_published)}
        </span>
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
      class="flex-shrink-0 w-24 opacity-55"
    >
      <div class="relative aspect-[2/3] rounded-lg border border-dashed border-base-content/15 flex flex-col items-center justify-center gap-1.5 px-1">
        <.icon name="hero-film-mini" class="size-4 text-base-content/30" />
        <.badge variant="ghost" size="sm" class="gap-1 text-[9px] px-1.5">
          {Logic.upcoming_pill_copy(@item)}
        </.badge>
      </div>
      <div class="mt-1.5 text-[11px] leading-tight line-clamp-2 text-base-content/50">
        {@item.title}
      </div>
    </div>
    """
  end
end
