defmodule MediaCentaurWeb.Components.Discovery.WatchlistRow do
  @moduledoc """
  One watchlist entry: the shared `title_summary/1` identity block (the
  provenance note displaces its overview line) plus the single
  state-dependent primary action — link to the library detail
  when the library knows the title, Download (plan flow) when released
  and an indexer exists, Track release otherwise. Recommend (send the
  title to your friends) and Remove are the quiet secondary actions.
  Pure rendering; `watchlist_remove`, `watchlist_track` and
  `watchlist_recommend` bubble to the host, navigation is by link.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  attr :item, WatchlistItem, required: true

  attr :library_owner_id, :string,
    default: nil,
    doc: "owning container id when the library knows the title"

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"

  attr :release_mode_available, :boolean, required: true

  attr :today, :any,
    default: nil,
    doc: "`Date.t()` for the released/upcoming split — nil means today (fixed in stories)."

  def watchlist_row(assigns) do
    today = assigns.today || Date.utc_today()
    assigns = assign(assigns, :status, MediaResults.release_status(assigns.item.title, today))

    ~H"""
    <div
      id={"watchlist-item-#{@item.media_type}-#{@item.tmdb_id}"}
      class="glass-surface flex w-full items-start gap-4 rounded-xl px-4 py-3"
      data-component="watchlist-row"
    >
      <.title_summary title={@item.title} poster_url={@poster_url}>
        <:secondary :if={@item.note}>{@item.note}</:secondary>
      </.title_summary>

      <%!-- The action strip is a real 3-track grid and carries
            `data-nav-grid`: the input system reads its computed column
            count, so DOWN/UP move row-to-row (primary → primary) and
            LEFT/RIGHT move within a row (primary ↔ Recommend ↔ Remove).
            Every row renders exactly these three nav items. --%>
      <span
        class="grid shrink-0 grid-cols-[auto_auto_auto] items-center gap-3 self-center"
        data-nav-grid
      >
        <.primary_action
          item={@item}
          status={@status}
          library_owner_id={@library_owner_id}
          release_mode_available={@release_mode_available}
        />
        <button
          type="button"
          class="cursor-pointer text-xs text-base-content/30 transition-colors hover:text-base-content/60"
          phx-click="watchlist_recommend"
          phx-value-tmdb-id={@item.tmdb_id}
          phx-value-media-type={@item.media_type}
          data-nav-item
          tabindex="0"
        >
          Recommend
        </button>
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
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70 transition-colors hover:text-primary"
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
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70 transition-colors hover:text-primary"
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
      class="inline-flex cursor-pointer items-center gap-1 text-xs font-medium text-primary/70 transition-colors hover:text-primary"
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
