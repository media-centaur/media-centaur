defmodule MediaCentaurWeb.Components.Incoming.Ledger do
  @moduledoc """
  The Recently-landed ledger — the Incoming page's quietest band
  (DDR-015): terminal pursuits as open rows on the page surface, no
  panel chrome, dissolving downward into the page bottom via a static
  CSS mask (a treatment, not an animation — ADR-012 applies).

  Each row is one terminal `PursuitRow`: a severity dot, the title with
  its status sentence, the outcome word, and relative time. "Show
  earlier" (`expand_ledger`) grows the ledger once; anything more is
  "View all history" (`toggle_history`, the existing full history
  disclosure). Storage sits as the ambient foot line, reusing
  `DownloadStorage.calm_summary/1`.

  With no rows and nothing hidden the component renders nothing at all
  — history that hasn't happened doesn't earn an empty box.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage

  attr :rows, :list,
    default: [],
    doc: "Terminal `PursuitRow.t()` rows, newest first (pre-capped by `HistoryLogic.ledger_rows/2`)."

  attr :hidden_count, :integer,
    default: 0,
    doc: "Rows behind the cap — gates the \"Show earlier\" disclosure."

  attr :expanded, :boolean,
    default: false,
    doc: "The ledger grows once; expanded hides \"Show earlier\" even when more rows remain."

  attr :storage_drives, :list,
    default: [],
    doc:
      "Media-dir drive maps (`Storage.measure_all/0` shape) — the foot line renders `DownloadStorage.calm_summary/1` when it has one to give."

  def ledger(assigns) do
    assigns = assign(assigns, :storage_summary, DownloadStorage.calm_summary(assigns.storage_drives))

    ~H"""
    <section
      :if={@rows != [] || @hidden_count > 0}
      data-component="incoming-ledger"
      data-nav-zone="ledger"
      class="space-y-3"
    >
      <div class="flex items-baseline justify-between">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
          Recently landed
        </h3>
        <button
          type="button"
          class="cursor-pointer text-xs text-base-content/50 transition-colors hover:text-base-content"
          phx-click="toggle_history"
          data-nav-item
          tabindex="0"
        >
          View all history
        </button>
      </div>

      <%!-- Static mask treatment: the last rows dissolve toward the page
            bottom. The fade zone is fixed-height, so expansion reveals
            older rows *into* the fade instead of washing the whole
            ledger out. --%>
      <div class="[mask-image:linear-gradient(to_bottom,black_0,black_calc(100%-5rem),oklch(0%_0_0/0.16)_100%)]">
        <div
          :for={row <- @rows}
          id={"ledger-row-#{row.id}"}
          class="grid grid-cols-[10px_minmax(0,1fr)_auto_auto] items-baseline gap-3 px-1 py-1.5 text-sm text-base-content/80"
        >
          <span class={["size-[7px] self-center rounded-full", dot_class(row.state)]} />
          <span class="min-w-0 truncate">
            {display_title(row)}
            <span class="ml-2 text-xs text-base-content/50">
              {row.status.verb} — {row.status.description}
            </span>
          </span>
          <span class={["whitespace-nowrap text-xs", outcome_class(row.state)]}>
            {outcome_label(row.state)}
          </span>
          <span class="min-w-20 whitespace-nowrap text-right text-xs text-base-content/35">
            {when_label(row)}
          </span>
        </div>
      </div>

      <div
        :if={(@hidden_count > 0 && !@expanded) || @storage_summary}
        class="flex items-center justify-between px-1"
      >
        <button
          :if={@hidden_count > 0 && !@expanded}
          type="button"
          class="flex cursor-pointer items-center gap-1.5 text-xs text-base-content/50 transition-colors hover:text-base-content"
          phx-click="expand_ledger"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-arrow-down-mini" class="size-3.5" /> Show earlier
        </button>
        <span
          :if={@storage_summary}
          class="ml-auto inline-flex items-center gap-1.5 text-xs text-base-content/35"
        >
          <.icon name="hero-circle-stack-mini" class="size-3.5" /> {@storage_summary}
        </span>
      </div>
    </section>
    """
  end

  defp dot_class(:satisfied), do: "bg-success"
  defp dot_class(:partial), do: "bg-warning"
  defp dot_class(:exhausted), do: "bg-error"
  defp dot_class(_state), do: "bg-base-content/25"

  defp outcome_label(:satisfied), do: "Landed"
  defp outcome_label(:partial), do: "Partly landed"
  defp outcome_label(:exhausted), do: "Failed"
  defp outcome_label(:cancelled), do: "Cancelled"
  defp outcome_label(state), do: Phoenix.Naming.humanize(state)

  defp outcome_class(:satisfied), do: "text-success/85"
  defp outcome_class(:partial), do: "text-warning/90"
  defp outcome_class(:exhausted), do: "text-error/90"
  defp outcome_class(_state), do: "text-base-content/35"

  defp when_label(%PursuitRow{updated_at: %DateTime{} = at}), do: Format.relative_ago(at)
  defp when_label(%PursuitRow{}), do: nil

  defp display_title(%PursuitRow{title: title, season_number: season, episode_number: episode}) do
    case Format.episode_label(season, episode) do
      "" -> title
      label -> "#{title} #{label}"
    end
  end
end
