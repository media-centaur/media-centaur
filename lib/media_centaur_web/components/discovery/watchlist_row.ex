defmodule MediaCentaurWeb.Components.Discovery.WatchlistRow do
  @moduledoc """
  One watchlist entry: poster thumb, identity line, provenance note, and
  the single state-dependent primary action — link to the library detail
  when the library knows the title, Download (plan flow) when released
  and an indexer exists, Track release otherwise. Remove is the quiet
  secondary action. Pure rendering; `watchlist_remove` and
  `watchlist_track` bubble to the host, navigation is by link.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  attr :item, WatchlistItem, required: true

  attr :library_owner_id, :string,
    default: nil,
    doc: "owning container id when the library knows the title"

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host: local TmdbArtwork url or TMDB hotlink"

  attr :release_mode_available, :boolean, required: true

  attr :today, :any,
    default: nil,
    doc: "`Date.t()` for the released/upcoming split — nil means today (fixed in stories)."

  def watchlist_row(assigns) do
    today = assigns.today || Date.utc_today()
    assigns = assign(assigns, :status, MediaResults.release_status(assigns.item, today))

    ~H"""
    <div
      id={"watchlist-item-#{@item.media_type}-#{@item.tmdb_id}"}
      class="glass-surface flex w-full items-start gap-4 rounded-xl px-4 py-3"
      data-component="watchlist-row"
    >
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <%!-- The thumb paints at 48 CSS px (96 device px on the 4K 2×
              compose) — 128 clears that; hotlinked TMDB urls pass
              through `sized_image_url/2` untouched. --%>
        <img
          :if={@poster_url}
          src={sized_image_url(@poster_url, 128)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <.icon
          :if={!@poster_url}
          name={if @item.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>

      <span class="min-w-0 flex-1 space-y-0.5 self-center">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm font-semibold">{@item.name}</span>
          <%!-- Quiet text, not colored chips — type is metadata; color
                stays reserved for interaction and state. --%>
          <span class="shrink-0 text-xs text-base-content/50">
            {if @item.media_type == :movie, do: "Movie", else: "TV"}<span :if={@item.year}> · {@item.year}</span>
          </span>
        </span>
        <span :if={@item.note} class="line-clamp-2 block text-xs leading-relaxed text-base-content/55">
          {@item.note}
        </span>
        <span
          :if={!@item.note && @item.overview}
          class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
        >
          {@item.overview}
        </span>
      </span>

      <span class="flex shrink-0 items-center gap-3 self-center">
        <.primary_action
          item={@item}
          status={@status}
          library_owner_id={@library_owner_id}
          release_mode_available={@release_mode_available}
        />
        <button
          type="button"
          class="cursor-pointer text-xs text-base-content/30 transition-colors hover:text-base-content/60"
          phx-click="watchlist_remove"
          phx-value-tmdb-id={@item.tmdb_id}
          phx-value-media-type={@item.media_type}
          data-nav-item
          tabindex="0"
        >
          Remove
        </button>
      </span>
    </div>
    """
  end

  attr :item, WatchlistItem, required: true
  attr :status, :atom, required: true, values: [:upcoming, :released]
  attr :library_owner_id, :string, default: nil
  attr :release_mode_available, :boolean, required: true

  # The row's one primary action, honest per state: the library detail
  # when the title is already known there; the plan flow when a grab is
  # actually possible (released + indexer); release tracking otherwise.
  defp primary_action(%{library_owner_id: owner_id} = assigns) when not is_nil(owner_id) do
    ~H"""
    <.link
      navigate={"/library?selected=#{@library_owner_id}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70"
      data-nav-item
      tabindex="0"
    >
      In library <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </.link>
    """
  end

  defp primary_action(%{status: :released, release_mode_available: true} = assigns) do
    ~H"""
    <.link
      navigate={"/incoming?plan=new&tmdb_id=#{@item.tmdb_id}&tmdb_type=#{plan_type(@item.media_type)}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70"
      data-nav-item
      tabindex="0"
    >
      Download <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </.link>
    """
  end

  defp primary_action(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex cursor-pointer items-center gap-1 text-xs font-medium text-primary/70"
      phx-click="watchlist_track"
      phx-value-tmdb-id={@item.tmdb_id}
      phx-value-media-type={@item.media_type}
      data-nav-item
      tabindex="0"
    >
      Track release <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </button>
    """
  end

  defp plan_type(:movie), do: "movie"
  defp plan_type(:tv_series), do: "tv"
end
