defmodule MediaCentaurWeb.Components.TMDB.TitleSummary do
  @moduledoc """
  The one identity block for a TMDB title that is not necessarily a
  library entry: poster thumb, name, quiet type/year text, and a
  secondary line (the overview by default). Search rows, watchlist rows
  and feed rows render this and add their own decorations through the
  `markers` slot (Tracked, In library) and the `secondary` slot (a
  watchlist note). Owns no state and no actions; renders as spans so a
  host may wrap it in a button or a link.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.TMDB.Title

  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`; nil shows the icon fallback"

  slot :markers, doc: "quiet text markers after the type/year (Tracked, In library)"
  slot :secondary, doc: "displaces the overview line — a watchlist note, a friend's reason"

  def title_summary(assigns) do
    ~H"""
    <span class="flex min-w-0 flex-1 items-start gap-4" data-component="title-summary">
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <%!-- The thumb paints at 48 CSS px (96 device px on the 4K 2×
              compose) — 160 is the shared thumb derivative width, so
              local artwork reuses the warm derivative; hotlinked TMDB
              urls pass through `sized_image_url/2` untouched. --%>
        <img
          :if={@poster_url}
          src={sized_image_url(@poster_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <.icon
          :if={!@poster_url}
          name={if @title.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>

      <span class="min-w-0 flex-1 space-y-0.5 self-center">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm font-semibold">{@title.name}</span>
          <%!-- Quiet text, not colored chips — type is metadata; color
                stays reserved for interaction and state. --%>
          <span class="shrink-0 text-xs text-base-content/55">
            {if @title.media_type == :movie, do: "Movie", else: "TV"}<span :if={@title.year}> · {@title.year}</span>
          </span>
          {render_slot(@markers)}
        </span>
        <span
          :if={@secondary != []}
          class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
        >
          {render_slot(@secondary)}
        </span>
        <span
          :if={@secondary == [] && @title.overview}
          class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
        >
          {@title.overview}
        </span>
      </span>
    </span>
    """
  end
end
