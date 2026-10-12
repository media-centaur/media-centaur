defmodule MediaCentaurWeb.IncomingLive.OrphanQueue do
  @moduledoc """
  "Other downloads" residual section — jobs in the download clients that
  did not pair with any tracked pursuit.

  Rare in normal use (auto-grabs and manual grabs both create pursuits),
  but kept visible so a sideloaded job or a title-match miss is not
  invisible. Each row is the download strip (`DownloadStrip.download_strip/1`),
  so an unclaimed job is drawn exactly as a claimed one, cancel included —
  the house arm gesture (MC0027 tier 2), dispatched to the parent LiveView,
  which owns `cancel_armed_id`.
  """

  use Phoenix.Component

  alias MediaCentaur.Acquisition.QueueMatcher
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaurWeb.Components.Acquisition.DownloadStrip

  attr :items, :list,
    required: true,
    doc: "List of unmatched `MediaCentaur.Downloads.QueueItem.t()` — render `nil`/empty as no section."

  attr :cancel_armed_id, :string,
    default: nil,
    doc: "Host-owned: the queue-item id whose cancel is one click from firing (MC0027 tier 2)."

  def orphan_zone(%{items: []} = assigns), do: ~H""

  def orphan_zone(assigns) do
    ~H"""
    <section data-nav-zone="other_downloads" class="scrim-surface rounded-xl overflow-hidden">
      <div class="px-4 py-2 border-b border-base-content/5">
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Other downloads
        </h2>
        <p class="mt-0.5 text-[11px] text-base-content/55">
          Downloads in your clients that no pursuit claims.
        </p>
      </div>

      <div>
        <.orphan_row :for={item <- @items} item={item} cancel_armed_id={@cancel_armed_id} />
      </div>
    </section>
    """
  end

  attr :item, QueueItem, required: true
  attr :cancel_armed_id, :string, default: nil

  defp orphan_row(assigns) do
    assigns = assign(assigns, :download, QueueMatcher.to_download(assigns.item))

    ~H"""
    <div id={"orphan-#{@item.id}"} class="px-4 py-3 border-b border-base-content/5 last:border-0">
      <DownloadStrip.download_strip
        download={@download}
        queue_item_id={@item.id}
        cancel_title={@item.title}
        cancel_armed_id={@cancel_armed_id}
        bare
      />
    </div>
    """
  end
end
