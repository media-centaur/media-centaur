defmodule MediaCentarrWeb.Components.Acquisition.PursuitRow do
  @moduledoc """
  Renders one pursuit row on the Downloads index (`/download`).

  The footer attaches the matched live-queue download (or a derived
  status hint when no torrent is currently matched). The matching is
  computed by `MediaCentarr.Acquisition.QueueMatcher.match/2` at render
  time on the LiveView; this component just consumes `:download` and
  `:queue_item_id` directly.

  A `data-nav-item` wrapper makes the whole row navigable. The cancel
  button in the download footer is its own focusable `data-nav-item` so
  keyboard/gamepad users can target it independently of the card. The
  "Open full →" affordance navigates to the detail page.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  alias MediaCentarr.Acquisition.ViewModels.{DownloadProgress, PursuitRow}
  alias MediaCentarr.Format
  alias MediaCentarrWeb.AcquisitionLive.Logic
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitRow, required: true

  attr :download, :any,
    default: nil,
    doc: "Matched `DownloadProgress.t()` or `nil`. When nil, a hint is derived from `vm.target_status`."

  attr :queue_item_id, :string,
    default: nil,
    doc: "Queue-client id (qBittorrent hash) for the matched torrent. Required to fire cancel."

  def pursuit_row(assigns) do
    ~H"""
    <div
      class="glass-surface rounded-xl p-4 space-y-2"
      data-nav-item
      tabindex="0"
      data-pursuit-id={@vm.id}
    >
      <div class="flex items-baseline justify-between gap-3">
        <div class="min-w-0 flex-1 truncate text-sm font-medium">{@vm.title}</div>
        <PursuitStyle.state_badge state={@vm.state} />
      </div>

      <div class="flex items-center gap-3 text-xs text-base-content/60">
        <span>Attempts: {@vm.attempt_count}</span>
        <span>·</span>
        <span>Origin: {@vm.origin}</span>
      </div>

      <.recent_events entries={@vm.recent_events} />

      <.download_footer
        download={@download}
        queue_item_id={@queue_item_id}
        cancel_title={@vm.release_title || @vm.title}
        target_status={@vm.target_status}
      />

      <div class="flex justify-end pt-1">
        <.link navigate={@vm.detail_path} class="text-xs text-primary inline-flex items-center gap-1">
          Open full <.icon name="hero-arrow-right-mini" class="size-3" />
        </.link>
      </div>
    </div>
    """
  end

  attr :entries,
       :list,
       required: true,
       doc:
         "List of `Acquisition.ViewModels.TimelineEntry` structs (pre-shaped read-side data; no schema/struct enforced at the attr layer)"

  defp recent_events(assigns) do
    ~H"""
    <%= if @entries == [] do %>
      <div class="text-xs text-base-content/40 italic">No events yet.</div>
    <% else %>
      <ul class="space-y-1">
        <li :for={entry <- @entries} class="flex items-baseline gap-2 text-xs">
          <span class={"block size-1.5 rounded-full flex-shrink-0 #{PursuitStyle.severity_dot_class(entry.severity)}"} />
          <span class={"min-w-0 flex-1 truncate #{PursuitStyle.severity_text_class(entry.severity)}"}>
            {entry.summary}
          </span>
          <span class="text-base-content/40 whitespace-nowrap">
            {Format.relative_just_now(entry.occurred_at)}
          </span>
        </li>
      </ul>
    <% end %>
    """
  end

  attr :download, :any,
    required: true,
    doc:
      "`DownloadProgress.t() | nil` — the helper pattern-matches on `%DownloadProgress{}` for the download branch and falls through to the no-match-hint branch when nil. Phoenix attr typing doesn't carry the union, hence `:any`."

  attr :queue_item_id, :string, required: true
  attr :cancel_title, :string, required: true
  attr :target_status, :atom, required: true

  defp download_footer(%{download: %DownloadProgress{}} = assigns) do
    ~H"""
    <div class="border-t border-base-content/5 pt-2 space-y-1.5">
      <div class="flex items-center gap-3">
        <.badge variant={Logic.state_badge_variant(@download.state)} size="md" class="text-xs">
          {Logic.state_label(@download.state)}
        </.badge>
        <span :if={@download.progress_pct} class="text-xs text-base-content/60 tabular-nums">
          {round(@download.progress_pct)}%
        </span>
        <span :if={@download.eta} class="text-xs text-base-content/40 tabular-nums">
          ETA {@download.eta}
        </span>
        <span :if={@download.client} class="text-xs text-base-content/40 truncate">
          {@download.client}
        </span>
        <div class="flex-1" />
        <.button
          :if={@queue_item_id}
          variant="destructive_inline"
          size="xs"
          shape="circle"
          class="text-base-content/40 hover:text-error"
          phx-click="cancel_download_prompt"
          phx-value-id={@queue_item_id}
          phx-value-title={@cancel_title}
          title="Cancel and delete"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.button>
      </div>

      <div
        :if={@download.progress_pct}
        class="h-[3px] bg-base-content/10 rounded-full overflow-hidden"
      >
        <div
          class="progress-fill h-full bg-primary rounded-full"
          style={"width: #{progress_width(@download.progress_pct)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp download_footer(assigns) do
    assigns = assign(assigns, :hint, no_match_hint(assigns.target_status))

    ~H"""
    <div :if={@hint} class="border-t border-base-content/5 pt-2">
      <div class={"text-xs #{@hint.tone_class}"}>
        {@hint.label}
      </div>
    </div>
    """
  end

  defp no_match_hint(nil),
    do: %{label: "Searching — no target picked yet.", tone_class: "text-base-content/50"}

  defp no_match_hint(:seeking),
    do: %{label: "Searching for a release.", tone_class: "text-base-content/60"}

  defp no_match_hint(:acquired),
    do: %{label: "Waiting — not visible in your download client.", tone_class: "text-warning"}

  defp no_match_hint(:succeeded), do: %{label: "Acquired — file landed.", tone_class: "text-success"}

  defp no_match_hint(:failed), do: %{label: "Stopped — auto-search gave up.", tone_class: "text-warning"}

  defp no_match_hint(:cancelled),
    do: %{label: "Stopped — target was cancelled.", tone_class: "text-base-content/60"}

  defp no_match_hint(_), do: nil

  defp progress_width(pct) when is_number(pct), do: max(0, min(100, round(pct)))
  defp progress_width(_), do: 0
end
