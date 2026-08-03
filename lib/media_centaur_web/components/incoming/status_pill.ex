defmodule MediaCentaurWeb.Components.Incoming.StatusPill do
  @moduledoc """
  The Incoming page's shared status vocabulary — one pill component
  rendered by both zoom levels of an incoming item: the Coming-up shelf
  card and the in-flight torrent row. Speaking the same pill on both is
  what welds the pair together (DDR-015).

  Color is state/health only (never identity): will-grab (`:armed`)
  and landed read success, in-pursuit reads info, failed reads error,
  cancelled reads muted; the watch-only and waiting statuses (in
  theaters, tracked, searching) stay neutral.

  Copy states what happens (UIDR-017): the `:armed` status reads
  "Will grab" — the internal atom keeps its name, the user never
  sees it.

  An `:in_pursuit` pill can carry a `percent` ("In pursuit · 62%") and
  an `anchor` — when set, the pill renders as a link to that fragment
  (the pursuit row's DOM id) so the shelf card jumps to its own torrent
  row.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  @statuses [:armed, :in_pursuit, :in_theaters, :tracked, :searching, :landed, :failed, :cancelled]

  attr :status, :atom, required: true, values: @statuses

  attr :percent, :integer,
    default: nil,
    doc: "Download progress — rendered only for `:in_pursuit` (\"In pursuit · 62%\")."

  attr :anchor, :string,
    default: nil,
    doc: "Fragment href (e.g. `#pursuit-<id>`) — when set, the pill is a link to that anchor."

  def status_pill(assigns) do
    assigns = assign(assigns, :label, label(assigns.status, assigns.percent))

    ~H"""
    <%!-- stopPropagation: the pill sits inside a phx-click card — jumping to
          the torrent row must not also open the card's detail slide-over
          (same guard as the event card's downloads deep-link). --%>
    <a
      :if={@anchor}
      href={@anchor}
      class={[base_class(), tone_class(@status), anchor_hover_class(@status)]}
      title="Jump to the live download"
      onclick="event.stopPropagation()"
    >
      <.icon name={icon_name(@status)} class="size-3 shrink-0" /> {@label}
    </a>
    <span :if={!@anchor} class={[base_class(), tone_class(@status)]}>
      <.icon name={icon_name(@status)} class="size-3 shrink-0" /> {@label}
    </span>
    """
  end

  defp base_class do
    "inline-flex items-center gap-1 whitespace-nowrap rounded-full border bg-base-300/80 px-2 py-0.5 text-[11px] font-semibold"
  end

  defp label(:in_pursuit, percent) when is_integer(percent), do: "In pursuit · #{percent}%"
  defp label(:in_pursuit, _percent), do: "In pursuit"
  defp label(:armed, _percent), do: "Will grab"
  defp label(:in_theaters, _percent), do: "In theaters"
  defp label(:tracked, _percent), do: "Tracked"
  defp label(:searching, _percent), do: "Searching"
  defp label(:landed, _percent), do: "Landed"
  defp label(:failed, _percent), do: "Failed"
  defp label(:cancelled, _percent), do: "Cancelled"

  defp icon_name(:armed), do: "hero-bolt-mini"
  defp icon_name(:in_pursuit), do: "hero-arrow-down-mini"
  defp icon_name(:in_theaters), do: "hero-eye-mini"
  defp icon_name(:tracked), do: "hero-bookmark-mini"
  defp icon_name(:searching), do: "hero-magnifying-glass-mini"
  defp icon_name(:landed), do: "hero-check-mini"
  defp icon_name(:failed), do: "hero-x-mark-mini"
  defp icon_name(:cancelled), do: "hero-no-symbol-mini"

  defp tone_class(:armed), do: "text-success border-success/35"
  defp tone_class(:landed), do: "text-success border-success/35"
  defp tone_class(:in_pursuit), do: "text-info border-info/35"
  defp tone_class(:failed), do: "text-error border-error/40"
  defp tone_class(:cancelled), do: "text-base-content/40 border-base-content/15"
  defp tone_class(_neutral), do: "text-base-content/65 border-base-content/15"

  defp anchor_hover_class(:in_pursuit), do: "transition-colors hover:border-info/60 hover:text-info"
  defp anchor_hover_class(_status), do: "transition-colors hover:border-base-content/30"
end
