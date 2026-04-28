defmodule MediaCentarrWeb.Components.Detail.Section do
  @moduledoc """
  Consistent section wrapper for the detail panel — small uppercase
  header followed by an `inner_block` slot for the section's body.
  """
  use MediaCentarrWeb, :html

  attr :title, :string, required: true
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="text-[0.7rem] uppercase tracking-wider text-base-content/50 font-semibold">
        {@title}
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
