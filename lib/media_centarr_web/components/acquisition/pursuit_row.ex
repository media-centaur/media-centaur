defmodule MediaCentarrWeb.Components.Acquisition.PursuitRow do
  @moduledoc """
  Renders one pursuit row on the Downloads index (`/download`).

  Three surfaces per card:

  1. **Title** — show/movie name with an `S01E03`-style suffix for TV
     pursuits (`Format.episode_label/2`).
  2. **Status line** — one severity-colored sentence built from
     `vm.status` (`%CurrentAction{verb, description, severity}`).
     Hidden when a download footer is attached — the live torrent
     state already conveys "what's happening".
  3. **Download footer** — progress bar, ETA, client, cancel button.
     Only when `:download` is non-nil.

  The whole card is a `phx-click="select_pursuit"` button-shaped div that
  opens the pursuit detail modal on `/download`. The cancel button is
  its own `data-nav-item` so keyboard/gamepad input can target it
  independently.
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
    doc:
      "Matched `DownloadProgress.t()` or `nil`. When non-nil, the status line is hidden and the download footer renders instead. Forces `:full` density."

  attr :queue_item_id, :string,
    default: nil,
    doc: "Queue-client id (qBittorrent hash) for the matched torrent. Required to fire cancel."

  attr :density, :atom,
    default: :full,
    values: [:full, :compact],
    doc:
      "`:full` is the original two-line card with state badge and (optionally) a download footer. `:compact` collapses the row to a single dense line — title left, severity-colored status right, no badge. Compact is the default in Active Pursuits and History zones where no download is paired; full is used when a torrent is matched (so the download footer fits)."

  attr :framed, :boolean,
    default: true,
    doc:
      "Compact mode only — when true (default), the row wraps in its own glass-surface rounded card. When false, it renders as a flat row meant to sit inside a parent container that provides framing (e.g. inside `PursuitGroup`, where the group itself is the card and per-episode rows are flat dividers within it). Ignored in `:full` density."

  def pursuit_row(assigns) do
    ~H"""
    <div
      :if={@density == :full}
      class="glass-surface rounded-xl p-4 space-y-2 block hover:bg-base-content/[0.03] transition-colors cursor-pointer"
      data-nav-item
      tabindex="0"
      role="button"
      data-pursuit-id={@vm.id}
      phx-click="select_pursuit"
      phx-value-id={@vm.id}
    >
      <div class="flex items-baseline justify-between gap-3">
        <div class="min-w-0 flex-1 truncate text-sm font-medium">
          {display_title(@vm)}
        </div>
        <PursuitStyle.state_badge state={@vm.state} />
      </div>

      <div
        :if={is_nil(@download)}
        class={"text-xs #{PursuitStyle.severity_text_class(@vm.status.severity)}"}
      >
        {@vm.status.verb} — {@vm.status.description}
      </div>

      <.download_footer
        :if={@download}
        download={@download}
        queue_item_id={@queue_item_id}
        cancel_title={@vm.release_title || @vm.title}
      />
    </div>

    <div
      :if={@density == :compact}
      class={[
        "px-3 py-2 flex items-baseline gap-3 hover:bg-base-content/[0.03] transition-colors cursor-pointer",
        @framed && "glass-surface rounded-lg"
      ]}
      data-nav-item
      tabindex="0"
      role="button"
      data-pursuit-id={@vm.id}
      phx-click="select_pursuit"
      phx-value-id={@vm.id}
    >
      <div class="min-w-0 flex-1 truncate text-sm font-medium">
        {display_title(@vm)}
      </div>
      <div class={"flex-shrink-0 max-w-[50%] truncate text-xs #{PursuitStyle.severity_text_class(@vm.status.severity)}"}>
        {@vm.status.verb} — {@vm.status.description}
      </div>
    </div>
    """
  end

  # `Format.episode_label/2` returns "" when both season and episode are
  # nil — strip the trailing space so movies render cleanly.
  defp display_title(%PursuitRow{title: title, season_number: season, episode_number: episode}) do
    case Format.episode_label(season, episode) do
      "" -> title
      label -> "#{title} #{label}"
    end
  end

  attr :download, DownloadProgress, required: true
  attr :queue_item_id, :string, required: true
  attr :cancel_title, :string, required: true

  defp download_footer(assigns) do
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

  defp progress_width(pct) when is_number(pct), do: max(0, min(100, round(pct)))
  defp progress_width(_), do: 0
end
