defmodule MediaCentarrWeb.AcquisitionLive.OrphanQueue do
  @moduledoc """
  "Other downloads" residual section — torrents in the download client
  that did not pair with any tracked pursuit.

  Rare in normal use (auto-grabs and manual grabs both create pursuits),
  but kept visible so a sideloaded torrent or a title-match miss is not
  invisible. Each row offers the same cancel affordance as the in-card
  download footer (dispatched as `cancel_download_prompt` to the parent
  LiveView).
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarrWeb.AcquisitionLive.Logic

  attr :items, :list,
    required: true,
    doc: "List of unmatched `MediaCentarr.Downloads.QueueItem.t()` — render `nil`/empty as no section."

  def orphan_zone(%{items: []} = assigns), do: ~H""

  def orphan_zone(assigns) do
    ~H"""
    <section data-nav-zone="other_downloads" class="glass-surface rounded-xl overflow-hidden">
      <div class="px-4 py-2 border-b border-base-content/5">
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          Other downloads
        </h2>
        <p class="mt-0.5 text-[11px] text-base-content/40">
          Torrents in your client that don't match any active pursuit.
        </p>
      </div>

      <div>
        <.orphan_row :for={item <- @items} item={item} />
      </div>
    </section>
    """
  end

  attr :item, QueueItem, required: true

  defp orphan_row(assigns) do
    ~H"""
    <div
      id={"orphan-#{@item.id}"}
      class="px-4 py-3 border-b border-base-content/5 last:border-0 flex items-center gap-3"
    >
      <span class="flex-1 min-w-0 text-sm truncate" title={@item.title}>{@item.title}</span>
      <.badge
        :if={@item.state}
        variant={Logic.state_badge_variant(@item.state)}
        size="md"
        class="text-xs"
      >
        {Logic.state_label(@item.state)}
      </.badge>
      <span :if={@item.timeleft} class="text-xs text-base-content/40 tabular-nums">
        {@item.timeleft}
      </span>
      <.button
        variant="destructive_inline"
        size="xs"
        shape="circle"
        class="text-base-content/40 hover:text-error"
        phx-click="cancel_download_prompt"
        phx-value-id={@item.id}
        phx-value-title={@item.title}
        title="Cancel and delete"
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </.button>
    </div>
    """
  end
end
