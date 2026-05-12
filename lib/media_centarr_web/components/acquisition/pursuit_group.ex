defmodule MediaCentarrWeb.Components.Acquisition.PursuitGroup do
  @moduledoc """
  Collapsible group row for N pursuits of the same show in the same
  state. Used on the Downloads page in the Active Pursuits and History
  zones when multiple episodes share a `{title, state}` bucket — without
  grouping, the page becomes a wall of near-identical compact rows.

  The header renders a single dense line:

      [chevron] <Title> · <N> episodes · <severity-colored verb>

  Clicking the header fires `toggle_pursuit_group` with
  `phx-value-title` and `phx-value-state`. The parent `AcquisitionLive`
  toggles membership of `{title, state}` in its `expanded_pursuit_groups`
  `MapSet` and re-renders.

  When `@expanded?` is true, the per-episode compact `PursuitRow` list
  renders below the header in a slightly inset container.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [icon: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow, as: PursuitRowVM
  alias MediaCentarrWeb.Components.Acquisition.PursuitRow
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :title, :string, required: true
  attr :state, :atom, required: true
  attr :count, :integer, required: true
  attr :verb, :string, required: true
  attr :severity, :atom, required: true, values: [:info, :success, :warning, :error]

  attr :vms, :list,
    required: true,
    doc: "List of `PursuitRow.t()` view-models, one per pursuit in the group."

  attr :expanded?, :boolean, default: false

  def pursuit_group(assigns) do
    ~H"""
    <div class="glass-surface rounded-lg overflow-hidden">
      <div
        class="px-3 py-2 flex items-baseline gap-3 hover:bg-base-content/[0.03] transition-colors cursor-pointer"
        data-nav-item
        tabindex="0"
        role="button"
        phx-click="toggle_pursuit_group"
        phx-value-title={@title}
        phx-value-state={Atom.to_string(@state)}
      >
        <.icon
          name={if @expanded?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4 text-base-content/40 flex-shrink-0"
        />
        <div class="min-w-0 flex-1 truncate text-sm font-medium">
          {@title}
        </div>
        <div class="flex-shrink-0 text-xs text-base-content/50 tabular-nums">
          {@count} {episode_word(@count)}
        </div>
        <div class={"flex-shrink-0 text-xs truncate max-w-[35%] #{PursuitStyle.severity_text_class(@severity)}"}>
          {@verb}
        </div>
      </div>

      <div
        :if={@expanded?}
        class="divide-y divide-base-content/5 border-t border-base-content/5"
      >
        <PursuitRow.pursuit_row
          :for={%PursuitRowVM{} = vm <- @vms}
          vm={vm}
          density={:compact}
          framed={false}
        />
      </div>
    </div>
    """
  end

  defp episode_word(1), do: "episode"
  defp episode_word(_), do: "episodes"
end
