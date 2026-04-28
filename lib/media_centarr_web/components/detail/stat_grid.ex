defmodule MediaCentarrWeb.Components.Detail.StatGrid do
  @moduledoc """
  4-cell "At a glance" stat grid. Takes a list of `{label, value}` tuples
  (already filtered for blanks by `Detail.Logic.stat_grid_for/2`) and
  renders one cell per pair. Renders nothing if the list is empty.
  """
  use MediaCentarrWeb, :html

  attr :stats, :list, required: true

  def stat_grid(assigns) do
    ~H"""
    <div :if={@stats != []} class="grid grid-cols-2 sm:grid-cols-4 gap-2">
      <div
        :for={{label, value} <- @stats}
        class="bg-base-content/[0.04] border border-base-content/[0.06] rounded-lg p-2.5"
      >
        <div class="text-[0.65rem] uppercase tracking-wider text-base-content/40 mb-0.5">
          {label}
        </div>
        <div class="text-sm text-base-content/90 truncate" title={value}>{value}</div>
      </div>
    </div>
    """
  end
end
