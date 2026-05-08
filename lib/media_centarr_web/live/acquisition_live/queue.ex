defmodule MediaCentarrWeb.AcquisitionLive.Queue do
  @moduledoc """
  Active-queue zone of the unified Downloads page — renders the live
  torrent activity from the configured download client, plus the
  "no client connected" empty state.

  Pure function component. Cancel-confirmation modal lives on the
  parent because the confirm/cancel events flip parent socket assigns
  (`pending_cancels`); the cancel button here just dispatches
  `cancel_download_prompt` to the parent.
  """
  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  alias MediaCentarr.Acquisition.Health
  alias MediaCentarrWeb.AcquisitionLive.Logic
  alias MediaCentarrWeb.Components.Acquisition.QueueStatusBadge

  attr :download_client_ready, :boolean, required: true
  attr :queue_loaded?, :boolean, required: true

  attr :queue_status, :any,
    default: :initializing,
    doc:
      "QueueStatus.status() from MediaCentarr.Acquisition.QueueStatus.derive/2 — drives the freshness badge"

  attr :active_queue, :list,
    required: true,
    doc: "List of `MediaCentarr.Acquisition.QueueItem.t()` (no Phoenix list-of-typed-structs validator)."

  attr :expanded_queue_groups, :any,
    required: true,
    doc: "MapSet of QueueItem.state() atoms the user has clicked open"

  def queue_zone(assigns) do
    ~H"""
    <section
      :if={@download_client_ready}
      data-nav-zone="queue"
      class="glass-surface rounded-xl overflow-hidden"
    >
      <div class="px-4 py-2 border-b border-base-content/5 flex items-center justify-between gap-3">
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          Downloading
        </h2>
        <div class="flex items-center gap-2">
          <QueueStatusBadge.queue_status_badge status={@queue_status} />
          <span :if={!@queue_loaded?} class="loading loading-spinner loading-xs text-base-content/30">
          </span>
        </div>
      </div>

      <p
        :if={@queue_loaded? && @active_queue == []}
        class="px-4 py-6 text-center text-sm text-base-content/40"
      >
        No active downloads
      </p>

      <div :if={@active_queue != []}>
        <%= for op <- Logic.prepare_queue_for_render(@active_queue, @expanded_queue_groups) do %>
          <.render_op op={op} />
        <% end %>
      </div>
    </section>

    <section
      :if={!@download_client_ready}
      class="glass-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/50"
    >
      Connect a download client in
      <.link navigate="/settings?section=acquisition" class="link link-primary">Settings</.link>
      to see the active queue.
    </section>
    """
  end

  attr :op, :any, required: true, doc: "render op tuple from `Logic.prepare_queue_for_render/2`"

  defp render_op(%{op: {:item, item}} = assigns) do
    assigns = Map.put(assigns, :item, item)

    ~H"""
    <.row item={@item} />
    """
  end

  defp render_op(%{op: {:summary, summary}} = assigns) do
    assigns = Map.put(assigns, :summary, summary)

    ~H"""
    <.summary_row summary={@summary} />
    """
  end

  attr :item, MediaCentarr.Acquisition.QueueItem, required: true

  defp row(assigns) do
    ~H"""
    <div
      id={"queue-item-#{@item.id}"}
      class="px-4 py-3 border-b border-base-content/5 last:border-0 space-y-1.5"
    >
      <div class="flex items-center gap-3">
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

      <div
        :if={Logic.render_health_line?(@item)}
        class={"text-xs #{Logic.health_text_class(@item.health)}"}
      >
        {Health.label(@item.health)}
      </div>

      <div :if={@item.progress} class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div class="progress-fill h-full bg-primary rounded-full" style={"width: #{@item.progress}%"}>
        </div>
      </div>

      <div class="flex items-center gap-3 text-xs text-base-content/40">
        <span :if={@item.download_client}>{@item.download_client}</span>
        <span :if={@item.indexer}>{@item.indexer}</span>
        <span :if={@item.progress} class="tabular-nums">{@item.progress}%</span>
      </div>
    </div>
    """
  end

  attr :summary, :any,
    required: true,
    doc: "group summary returned by `Logic.partition_collapsible_group/3`"

  defp summary_row(%{summary: %{kind: :collapsed}} = assigns) do
    ~H"""
    <button
      id={"queue-summary-#{@summary.state}"}
      type="button"
      phx-click="toggle_queue_group"
      phx-value-state={@summary.state}
      class="w-full px-4 py-2 border-b border-base-content/5 last:border-0 flex items-center gap-3 text-xs text-base-content/50 hover:bg-base-content/5"
      data-nav-item
      tabindex="0"
    >
      <.icon name="hero-chevron-down-mini" class="size-3.5 shrink-0" />
      <span class="flex-1 min-w-0 text-left">
        + {@summary.hidden_count} more {Logic.state_label(@summary.state) |> String.downcase()}
      </span>
      <.badge variant={Logic.state_badge_variant(@summary.state)} size="md" class="text-xs">
        {Logic.state_label(@summary.state)}
      </.badge>
    </button>
    """
  end

  defp summary_row(%{summary: %{kind: :expanded}} = assigns) do
    ~H"""
    <button
      id={"queue-summary-#{@summary.state}"}
      type="button"
      phx-click="toggle_queue_group"
      phx-value-state={@summary.state}
      class="w-full px-4 py-2 border-b border-base-content/5 last:border-0 flex items-center gap-3 text-xs text-base-content/50 hover:bg-base-content/5"
      data-nav-item
      tabindex="0"
    >
      <.icon name="hero-chevron-up-mini" class="size-3.5 shrink-0" />
      <span class="flex-1 min-w-0 text-left">Show fewer</span>
      <.badge variant={Logic.state_badge_variant(@summary.state)} size="md" class="text-xs">
        {@summary.total} {Logic.state_label(@summary.state) |> String.downcase()}
      </.badge>
    </button>
    """
  end
end
