defmodule MediaCentaurWeb.Components.Acquisition.UnitBoard do
  @moduledoc """
  Per-unit drill-down for a composite pursuit (ADR-055) — the coverage
  section of the pursuit detail modal.

  Renders one dense row per unit: the unit's label (the expanded term
  for a collapsed brace-expansion), the release its current target
  carries, a plain-colored state label (UIDR-002 — status labels are
  text, not badges), and a per-unit "Change target" affordance for
  in-flight units. A thin progress bar summarizes *units satisfied /
  units wanted* — never a count of targets.

  When the view model carries season `groups` (multi-season series or a
  big single season), rows roll up into collapsible season headers. The
  header carries the aggregate (counts, the shared covering release),
  so collapsed is the informative state; rows hoist nothing the header
  already says. Expansion state lives in the LiveView
  (`expanded_seasons`); `nil` means "use each group's exception-driven
  default".

  Renders nothing for single-unit pursuits — their one thread is
  already the whole modal (Activity card, decision card, timeline).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard

  attr :vm, UnitBoard,
    default: nil,
    doc: "%UnitBoard{} | nil — nil and single-unit boards render nothing."

  attr :expanded_seasons, MapSet,
    default: nil,
    doc:
      "Group keys currently expanded. Nil (no toggles yet) falls back to each group's `expanded_default?`. Ignored for flat boards."

  attr :on_toggle_season, :string,
    default: nil,
    doc:
      "Event fired with `phx-value-season` when a season header is clicked. Nil renders headers without the toggle affordance."

  attr :on_change_target, :string,
    default: nil,
    doc:
      "Event fired with `phx-value-unit-id` when the user pivots one unit to a fresh release. Nil hides the affordance."

  def unit_board(%{vm: nil} = assigns), do: ~H""
  def unit_board(%{vm: %UnitBoard{wanted: wanted}} = assigns) when wanted <= 1, do: ~H""

  def unit_board(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-3 space-y-2">
      <div class="flex items-baseline justify-between gap-3">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">
          Coverage
        </h3>
        <span class="text-xs text-base-content/60 tabular-nums">
          {@vm.satisfied} of {@vm.wanted}
        </span>
      </div>

      <div class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div
          class="progress-fill h-full bg-primary rounded-full"
          style={"width: #{progress_width(@vm)}%"}
        >
        </div>
      </div>

      <div :if={@vm.groups} class="space-y-1">
        <div :for={group <- @vm.groups} id={"unit-board-group-#{group.key}"}>
          <button
            type="button"
            id={"unit-board-season-#{group.key}"}
            class="w-full py-1.5 flex items-baseline gap-2 text-left hover:bg-base-content/5 rounded-md px-1 -mx-1"
            phx-click={@on_toggle_season}
            phx-value-season={group.key}
            data-nav-item
            tabindex="0"
          >
            <.icon
              name={
                if expanded?(group, @expanded_seasons),
                  do: "hero-chevron-down-mini",
                  else: "hero-chevron-right-mini"
              }
              class="size-3 flex-shrink-0 self-center text-base-content/40"
            />
            <span class="text-sm font-medium">{group.label}</span>
            <span class="text-xs text-base-content/60 tabular-nums">
              {group.satisfied}/{group.wanted}
            </span>
            <span :if={group.awaiting > 0} class="text-xs text-warning">
              {group.awaiting} need a decision
            </span>
            <span :if={group.exhausted > 0} class="text-xs text-error">
              {group.exhausted} exhausted
            </span>
            <span
              :if={group.shared_release_title}
              class="hidden sm:block ml-auto max-w-[40%] truncate text-xs text-base-content/55"
              title={group.shared_release_title}
            >
              {group.shared_release_title}
            </span>
          </button>

          <ul
            :if={expanded?(group, @expanded_seasons)}
            class="divide-y divide-base-content/5 pl-5"
          >
            <.unit_row
              :for={unit <- group.rows}
              unit={unit}
              hoisted_release={group.shared_release_title}
              on_change_target={@on_change_target}
            />
          </ul>
        </div>
      </div>

      <ul :if={is_nil(@vm.groups)} class="divide-y divide-base-content/5">
        <.unit_row :for={unit <- @vm.units} unit={unit} on_change_target={@on_change_target} />
      </ul>
    </div>
    """
  end

  attr :unit, UnitBoard.Row, required: true

  attr :hoisted_release, :string,
    default: nil,
    doc: "Release already shown on the group header — suppressed on the row."

  attr :on_change_target, :string, default: nil

  defp unit_row(assigns) do
    ~H"""
    <li id={"unit-board-row-#{@unit.id}"} class="py-1.5 flex items-baseline gap-3">
      <span class="min-w-0 flex-1 truncate text-sm">{@unit.label}</span>
      <span
        :if={@unit.release_title && @unit.release_title != @hoisted_release}
        class="hidden sm:block max-w-[40%] truncate text-xs text-base-content/55"
        title={@unit.release_title}
      >
        {@unit.release_title}
      </span>
      <span class={"flex-shrink-0 text-xs #{state_text_class(@unit)}"}>
        {state_label(@unit)}
      </span>
      <.button
        :if={@unit.actionable? && @on_change_target}
        variant="neutral"
        size="xs"
        shape="circle"
        class="flex-shrink-0 self-center"
        phx-click={@on_change_target}
        phx-value-unit-id={@unit.id}
        title="Change target — pick a fresh release for this item"
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-arrow-path-mini" class="size-3" />
      </.button>
    </li>
    """
  end

  defp expanded?(group, nil), do: group.expanded_default?
  defp expanded?(group, %MapSet{} = expanded_seasons), do: MapSet.member?(expanded_seasons, group.key)

  defp progress_width(%UnitBoard{wanted: wanted, satisfied: satisfied}) when wanted > 0 do
    max(0, min(100, round(satisfied / wanted * 100)))
  end

  defp progress_width(_vm), do: 0

  # Plain colored text per UIDR-002 — color is reserved for outcomes
  # that need attention; the routine in-flight state stays muted.
  defp state_label(%UnitBoard.Row{awaiting_decision?: true}), do: "Decision"
  defp state_label(%UnitBoard.Row{state: :active}), do: "Active"
  defp state_label(%UnitBoard.Row{state: :satisfied}), do: "Satisfied"
  defp state_label(%UnitBoard.Row{state: :exhausted}), do: "Exhausted"
  defp state_label(%UnitBoard.Row{state: :cancelled}), do: "Cancelled"

  defp state_text_class(%UnitBoard.Row{awaiting_decision?: true}), do: "text-warning"
  defp state_text_class(%UnitBoard.Row{state: :active}), do: "text-base-content/60"
  defp state_text_class(%UnitBoard.Row{state: :satisfied}), do: "text-success"
  defp state_text_class(%UnitBoard.Row{state: :exhausted}), do: "text-error"
  defp state_text_class(%UnitBoard.Row{state: :cancelled}), do: "text-base-content/55"
end
