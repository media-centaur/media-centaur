defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc """
  Function components for the Subsystem Health Board (Phase 4). Identity is
  name + a neutral monochrome glyph + type; color is reserved exclusively for
  health/severity (see the Phase 4 design spec, D7). Presentation only — the
  view-model logic lives in `MediaCentaurWeb.StatusLive.HealthBoard`.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.StatusLive.HealthBoard
  alias MediaCentaurWeb.StatusLive.SubsystemView

  @doc "One subsystem tile: name + neutral glyph + type; color only for health."
  attr :view, SubsystemView, required: true
  attr :selected, :boolean, default: false
  attr :on_select, :string, default: "select_subsystem"

  def subsystem_tile(assigns) do
    ~H"""
    <button
      id={"subsystem-tile-#{@view.component}"}
      type="button"
      phx-click={@on_select}
      phx-value-subsystem={@view.component}
      data-nav-item
      tabindex="0"
      class={[
        "glass-surface rounded-xl p-4 text-left w-full flex items-start gap-3 transition-colors",
        @view.state == :error && "border-l-2 border-error",
        @view.state == :warning && "border-l-2 border-warning",
        @selected && "ring-1 ring-primary/40"
      ]}
    >
      <.icon name={@view.glyph} class="size-5 shrink-0 text-base-content/65 mt-0.5" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <span class="font-medium truncate">{@view.label}</span>
          <span class={[
            "size-2 rounded-full shrink-0",
            @view.state == :ok && "bg-success/55",
            @view.state == :warning && "bg-warning",
            @view.state == :error && "bg-error"
          ]} />
        </div>
        <p class="text-sm text-base-content/55 mt-1">{HealthBoard.tile_summary(@view)}</p>
      </div>
    </button>
    """
  end
end
