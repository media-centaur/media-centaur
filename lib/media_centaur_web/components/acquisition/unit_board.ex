defmodule MediaCentaurWeb.Components.Acquisition.UnitBoard do
  @moduledoc """
  The coverage board — the window's units as attempt threads (ADR-055).

  One row per unit: its label, the release covering it, and its outcome
  line (`UnitBoard.Row.outcome_line/1` — the one word for its state with
  the thread's cost: "Landed · 28th release", "Cancelled · 48 releases
  failed"), plain coloured text per the badge convention. Each row is a
  disclosure over the releases tried for it — the cause when every one
  failed the same way, then each release's facts (`ReleaseFacts`), how it
  ended and when — owned by the page's `DisclosureState` under
  `unit-board-row-<unit id>`. An in-flight row not already awaiting a
  pick carries the swap control ("Pick a different release"), which opens
  the release picker.

  Every pursuit renders its board, a single film included; the Coverage
  count and bar draw for multi-unit goals only. When the view model
  carries season `groups`, rows roll up into collapsible season headers
  (counts by word, the shared covering release; a season with an unlanded
  exception opens by default), each a `disclosure/1` under the page's
  `DisclosureState` keyed by pursuit and season.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.Components.Disclosure

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard
  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.{Attempt, Row}
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts
  alias MediaCentaurWeb.Live.DisclosureState

  attr :vm, UnitBoard, default: nil, doc: "%UnitBoard{} | nil — nil renders nothing."

  attr :disclosures, MapSet,
    default: MapSet.new(),
    doc: "the page's `DisclosureState` — the season groups and each row's attempts."

  attr :on_change_target, :string,
    default: nil,
    doc:
      "Event fired with `phx-value-unit-id` when the user opens the release picker for one unit. Nil hides the affordance."

  def unit_board(%{vm: nil} = assigns), do: ~H""

  def unit_board(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-3 space-y-2">
      <div :if={@vm.wanted > 1} class="flex items-baseline justify-between gap-3">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">
          Coverage
        </h3>
        <span class="text-xs text-base-content/60 tabular-nums">
          {@vm.satisfied} of {@vm.wanted} landed
        </span>
      </div>

      <div :if={@vm.wanted > 1} class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div
          class="progress-fill h-full bg-primary rounded-full"
          style={"width: #{progress_width(@vm)}%"}
        >
        </div>
      </div>

      <div :if={@vm.groups} class="space-y-1">
        <.disclosure
          :for={group <- @vm.groups}
          id={group_id(@vm, group)}
          open={DisclosureState.open?(@disclosures, group_id(@vm, group), group.expanded_default?)}
          variant={:bare}
          head_class="w-full py-1.5 flex items-baseline gap-2 text-left hover:bg-base-content/5 rounded-md px-1 -mx-1"
        >
          <:head>
            <span class="text-sm font-medium">{group.label}</span>
            <span class="text-xs text-base-content/60 tabular-nums">
              {group.satisfied} of {group.wanted} landed
            </span>
            <span :if={group.awaiting > 0} class="text-xs text-warning">
              {group.awaiting} {if group.awaiting == 1, do: "needs", else: "need"} a pick
            </span>
            <span :if={group.exhausted > 0} class="text-xs text-error">
              {group.exhausted} gave up
            </span>
            <span :if={group.cancelled > 0} class="text-xs text-base-content/60">
              {group.cancelled} cancelled
            </span>
            <span
              :if={group.shared_release_title}
              class="hidden sm:block ml-auto max-w-[40%] truncate text-xs text-base-content/55"
              data-tip={group.shared_release_title}
            >
              {group.shared_release_title}
            </span>
          </:head>
          <ul class="divide-y divide-base-content/5 pl-5">
            <.unit_row
              :for={unit <- group.rows}
              unit={unit}
              hoisted_release={group.shared_release_title}
              disclosures={@disclosures}
              on_change_target={@on_change_target}
            />
          </ul>
        </.disclosure>
      </div>

      <ul :if={is_nil(@vm.groups)} class="divide-y divide-base-content/5">
        <.unit_row
          :for={unit <- @vm.units}
          unit={unit}
          disclosures={@disclosures}
          on_change_target={@on_change_target}
        />
      </ul>
    </div>
    """
  end

  attr :unit, Row, required: true

  attr :hoisted_release, :string,
    default: nil,
    doc: "Release already shown on the group header — suppressed on the row."

  attr :disclosures, MapSet, required: true
  attr :on_change_target, :string, default: nil

  defp unit_row(assigns) do
    row_id = "unit-board-row-#{assigns.unit.id}"

    assigns =
      assign(assigns,
        row_id: row_id,
        open?: DisclosureState.open?(assigns.disclosures, row_id),
        cause: Row.cause(assigns.unit)
      )

    ~H"""
    <li class="py-0.5">
      <.disclosure
        id={@row_id}
        open={@open?}
        variant={:bare}
        head_class="w-full py-1.5 flex items-baseline gap-3 text-left hover:bg-base-content/5 rounded-md px-1 -mx-1"
        row_class="flex items-center gap-2"
      >
        <:head>
          <span class="min-w-0 flex-1 truncate text-sm">{@unit.label}</span>
          <span
            :if={@unit.release_title && @unit.release_title != @hoisted_release}
            class="hidden sm:block max-w-[40%] truncate text-xs text-base-content/55"
            data-tip={@unit.release_title}
          >
            {@unit.release_title}
          </span>
          <span class={"flex-shrink-0 text-xs #{severity_class(Row.severity(@unit))}"}>
            {Row.outcome_line(@unit)}
          </span>
        </:head>
        <:trailing>
          <.button
            :if={@unit.actionable? && @on_change_target}
            variant="neutral"
            size="xs"
            shape="circle"
            class="flex-shrink-0"
            phx-click={@on_change_target}
            phx-value-unit-id={@unit.id}
            data-tip="Pick a different release for this episode"
            aria-label="Pick a different release"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-arrow-path-mini" class="size-3" />
          </.button>
        </:trailing>

        <div class="pl-5 pb-2 space-y-1.5">
          <p :if={@cause} class="text-xs text-base-content/80">{@cause}</p>
          <p :if={@unit.attempts == []} class="text-xs text-base-content/55">No release tried yet.</p>
          <ul :if={@unit.attempts != []} class="divide-y divide-base-content/5">
            <li
              :for={{attempt, index} <- Enum.with_index(@unit.attempts)}
              id={"#{@row_id}-attempt-#{index}"}
              class="flex flex-wrap items-baseline gap-2 py-1 text-xs"
            >
              <ReleaseFacts.release_facts entry={
                %ReleaseFacts.Entry{
                  title: attempt.release_title,
                  quality: attempt.quality,
                  size_bytes: attempt.size_bytes,
                  indexer: attempt.indexer
                }
              } />
              <span class={"flex-shrink-0 #{attempt_class(attempt.outcome)}"}>
                {Attempt.word(attempt.outcome)}
              </span>
              <span
                :if={attempt.ended_at || attempt.started_at}
                class="flex-shrink-0 text-base-content/55 tabular-nums"
                data-tip={exact_time(attempt.ended_at || attempt.started_at)}
              >
                {Format.relative_ago(attempt.ended_at || attempt.started_at)}
              </span>
            </li>
          </ul>
        </div>
      </.disclosure>
    </li>
    """
  end

  # Keyed by pursuit too: season keys repeat across pursuits, and one
  # pursuit's toggles must not open another's groups.
  defp group_id(%UnitBoard{pursuit_id: pursuit_id}, group), do: "unit-board-#{pursuit_id}-#{group.key}"

  defp progress_width(%UnitBoard{wanted: wanted, satisfied: satisfied}) when wanted > 0 do
    max(0, min(100, round(satisfied / wanted * 100)))
  end

  defp progress_width(_vm), do: 0

  # Plain coloured text per the badge convention — colour is reserved for
  # outcomes that need attention; the routine in-flight state stays muted.
  defp severity_class(:success), do: "text-success"
  defp severity_class(:warning), do: "text-warning"
  defp severity_class(:error), do: "text-error"
  defp severity_class(:info), do: "text-base-content/60"
  defp severity_class(:muted), do: "text-base-content/55"

  defp attempt_class(:landed), do: "text-success"
  defp attempt_class(:trying), do: "text-base-content/60"
  defp attempt_class(:failed), do: "text-warning"
  defp attempt_class(_abandoned_or_stopped), do: "text-base-content/55"

  defp exact_time(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
end
