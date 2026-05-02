defmodule MediaCentarrWeb.Components.Detail.Section do
  @moduledoc """
  Consistent section wrapper for the detail panel — small uppercase
  header followed by an `inner_block` slot for the section's body.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :pending
  @storybook_reason "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md"

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
