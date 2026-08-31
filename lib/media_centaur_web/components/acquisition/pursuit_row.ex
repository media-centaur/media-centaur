defmodule MediaCentaurWeb.Components.Acquisition.PursuitRow do
  @moduledoc """
  Renders one pursuit row on the Incoming page's in-flight zone.

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

  import MediaCentaurWeb.LiveHelpers, only: [banner_hue: 1]

  import MediaCentaurWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary
  alias MediaCentaur.Acquisition.ViewModels.{DownloadProgress, PursuitRow}
  alias MediaCentaur.Format
  alias MediaCentaurWeb.IncomingLive.Logic
  alias MediaCentaurWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitRow, required: true

  attr :download, :any,
    default: nil,
    doc:
      "Matched `DownloadProgress.t()` or `nil`. When non-nil, the status line is hidden and the download footer renders instead. Forces `:full` density."

  attr :downloads, :list,
    default: [],
    doc:
      "`PursuitWithDownload.paired_download()` maps — every claimed torrent; composite pursuits render one strip each."

  attr :queue_item_id, :string,
    default: nil,
    doc: "Queue-client id (qBittorrent hash) for the matched torrent. Required to fire cancel."

  attr :telemetry_age, :string,
    default: nil,
    doc:
      "Staleness qualifier from `Logic.telemetry_age_label/1` (e.g. \"last seen 4m ago\"), or nil when telemetry is fresh. Appended to the download footer so its live figures aren't presented as current when the client is lagging/offline."

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
    assigns = assign(assigns, :paired_downloads, paired_downloads(assigns))

    ~H"""
    <div
      :if={@density == :full && @vm.door == :media}
      id={"pursuit-#{@vm.id}"}
      class="identity-banner block hover:brightness-110 transition-[filter] cursor-pointer"
      style={"--banner-hue: #{banner_hue(@vm.title)}"}
      data-nav-item
      tabindex="0"
      role="button"
      data-pursuit-id={@vm.id}
      phx-click="select_pursuit"
      phx-value-id={@vm.id}
    >
      <div class="relative p-4 space-y-2">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <div class="identity-logotype truncate text-lg leading-tight">
              {display_title(@vm)}
            </div>
            <div
              :if={is_nil(@download)}
              class={"mt-1 text-xs text-on-image #{PursuitStyle.severity_text_class(@vm.status.severity)}"}
            >
              {@vm.status.verb} — {@vm.status.description}
            </div>
          </div>
          <PursuitStyle.state_badge state={@vm.state} awaiting_decision?={@vm.awaiting_decision?} />
        </div>

        <.segmented_units vm={@vm} />
      </div>

      <div :if={@paired_downloads != []} class="identity-banner-strip px-4 pt-2 pb-3 space-y-2">
        <.download_footer
          :for={paired <- @paired_downloads}
          download={paired.download}
          queue_item_id={paired.queue_item_id}
          cancel_title={@vm.release_title || @vm.title}
          telemetry_age={@telemetry_age}
          bare
        />
      </div>
    </div>

    <div
      :if={@density == :full && @vm.door == :query}
      id={"pursuit-#{@vm.id}"}
      class="identity-row rounded-xl p-4 space-y-2 block hover:brightness-110 transition-[filter] cursor-pointer"
      style={"--banner-hue: #{banner_hue(@vm.title)}"}
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
        <.unit_progress_chip vm={@vm} />
        <PursuitStyle.state_badge state={@vm.state} awaiting_decision?={@vm.awaiting_decision?} />
      </div>

      <div
        :if={is_nil(@download)}
        class={"text-xs #{PursuitStyle.severity_text_class(@vm.status.severity)}"}
      >
        {@vm.status.verb} — {@vm.status.description}
      </div>

      <.download_footer
        :for={paired <- @paired_downloads}
        download={paired.download}
        queue_item_id={paired.queue_item_id}
        cancel_title={@vm.release_title || @vm.title}
        telemetry_age={@telemetry_age}
      />
    </div>

    <div
      :if={@density == :compact}
      id={"pursuit-#{@vm.id}"}
      class={[
        "px-3 py-2 flex items-baseline gap-3 cursor-pointer",
        @framed && "identity-row rounded-lg hover:brightness-110 transition-[filter]",
        !@framed && "hover:bg-base-content/[0.03] transition-colors"
      ]}
      style={@framed && "--banner-hue: #{banner_hue(@vm.title)}"}
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
      <span
        :if={@vm.door == :query}
        class="flex-shrink-0 text-[10px] uppercase tracking-wider text-base-content/30"
      >
        release search
      </span>
      <.unit_progress_chip vm={@vm} />
      <div class={"flex-shrink-0 max-w-[50%] truncate text-xs #{PursuitStyle.severity_text_class(@vm.status.severity)}"}>
        {@vm.status.verb} — {@vm.status.description}
      </div>
    </div>
    """
  end

  # Composite progress (ADR-055): progress is units satisfied / units
  # wanted. Single-unit pursuits render no chip — their state badge
  # already says everything.
  attr :vm, PursuitRow, required: true

  defp unit_progress_chip(%{vm: %PursuitRow{units_wanted: wanted}} = assigns) when wanted > 1 do
    ~H"""
    <.badge variant="ghost" class="flex-shrink-0 tabular-nums">
      {@vm.units_satisfied} of {@vm.units_wanted}
    </.badge>
    """
  end

  defp unit_progress_chip(assigns), do: ~H""

  # `Format.episode_label/2` returns "" when both season and episode are
  # nil — strip the trailing space so movies render cleanly.
  defp display_title(%PursuitRow{title: title, season_number: season, episode_number: episode}) do
    case Format.episode_label(season, episode) do
      "" -> title
      label -> "#{title} #{label}"
    end
  end

  # Segmented unit progress (UIDR-014): the shape of completion, not a
  # percentage — one square per unit (landed / in flight / failed),
  # the same cell vocabulary as the plan board and the UnitBoard.
  # Hidden for singles; very large composites fall back to the chip.
  attr :vm, PursuitRow, required: true

  defp segmented_units(%{vm: %PursuitRow{units_wanted: wanted, unit_states: states}} = assigns)
       when wanted > 1 and length(states) > 1 and length(states) <= 30 do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <span
        :for={{state, index} <- Enum.with_index(@vm.unit_states)}
        id={"unit-segment-#{@vm.id}-#{index}"}
        class={[
          "w-2 h-2 rounded-sm",
          state |> CellVocabulary.from_unit_state() |> CellVocabulary.segment_treatment()
        ]}
      >
      </span>
    </div>
    """
  end

  defp segmented_units(assigns), do: ~H""

  attr :download, DownloadProgress, required: true
  attr :queue_item_id, :string, required: true
  attr :cancel_title, :string, required: true
  attr :telemetry_age, :string, default: nil

  attr :bare, :boolean,
    default: false,
    doc: "Skips the top border/padding — the identity-banner strip provides its own framing."

  defp download_footer(assigns) do
    ~H"""
    <div class={[@bare && "space-y-1.5", !@bare && "border-t border-base-content/5 pt-2 space-y-1.5"]}>
      <div class="flex items-center gap-3">
        <span class={[
          "text-xs font-medium uppercase tracking-wider",
          Logic.state_text_class(@download.state)
        ]}>
          {Logic.state_label(@download.state)}
        </span>
        <%!-- The release name is what tells three otherwise-identical
              strips apart on a multi-download pursuit. --%>
        <span :if={@download.title} class="min-w-0 truncate text-xs text-base-content/50">
          {@download.title}
        </span>
        <%!-- Facts cluster right, beside the cancel affordance — a
              left-glued cluster leaves the row's width as dead span on
              wide viewports. --%>
        <div class="flex-1" />
        <span :if={@download.progress_pct} class="text-xs text-base-content/60 tabular-nums">
          {round(@download.progress_pct)}%
        </span>
        <span :if={@download.eta} class="text-xs text-base-content/40 tabular-nums">
          ETA {@download.eta}
        </span>
        <span
          :if={@download.size_bytes}
          class="flex-shrink-0 text-xs text-base-content/40 tabular-nums"
        >
          {Format.format_size_decimal(@download.size_bytes)}
        </span>
        <span :if={@download.client} class="flex-shrink-0 text-xs text-base-content/40">
          {@download.client}
        </span>
        <%!-- When the download client is lagging/offline these figures are
              last-known, not live — qualify them so the user isn't misled
              into thinking the bar is updating in real time. --%>
        <span :if={@telemetry_age} class="text-xs text-warning/80 tabular-nums">
          · {@telemetry_age}
        </span>
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

  # The LV passes every claimed torrent via `downloads`; single-download
  # callers (stories, older call sites) pass just `download` — normalize
  # to one list so the footer renders identically either way.
  defp paired_downloads(%{downloads: [_ | _] = downloads}), do: downloads

  defp paired_downloads(%{download: %{} = download, queue_item_id: queue_item_id}),
    do: [%{download: download, queue_item_id: queue_item_id}]

  defp paired_downloads(_assigns), do: []
end
