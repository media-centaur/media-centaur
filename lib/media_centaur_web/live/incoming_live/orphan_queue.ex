defmodule MediaCentaurWeb.IncomingLive.OrphanQueue do
  @moduledoc """
  "Other downloads" residual section — torrents in the download client
  that did not pair with any tracked pursuit.

  Rare in normal use (auto-grabs and manual grabs both create pursuits),
  but kept visible so a sideloaded torrent or a title-match miss is not
  invisible. Each row offers the same cancel affordance as the in-card
  download footer — the house arm gesture (MC0027 tier 2), dispatched as
  `cancel_download_prompt` then `cancel_download_confirm` to the parent
  LiveView, which owns `cancel_armed_id`.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [armed_button: 1, badge: 1, icon: 1]

  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaurWeb.IncomingLive.Logic

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
          Torrents in your client that don't match any active pursuit.
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
      <span :if={@item.timeleft} class="text-xs text-base-content/55 tabular-nums">
        {@item.timeleft}
      </span>
      <%!-- No `shape="circle"`: the armed state relabels the control,
            and a fixed circle would clip the label it grows into. --%>
      <.armed_button
        armed={@cancel_armed_id == @item.id}
        arm="cancel_download_prompt"
        fire="cancel_download_confirm"
        armed_label="Click again to cancel"
        variant="destructive_inline"
        size="xs"
        class="text-base-content/55 hover:text-error"
        phx-value-id={@item.id}
        phx-value-title={@item.title}
        title="Cancel and delete"
        aria-label="Cancel download"
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </.armed_button>
    </div>
    """
  end
end
