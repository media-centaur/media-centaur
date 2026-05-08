defmodule MediaCentarrWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Header for the `/download/:pursuit_id` detail page."

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [button: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitHeader, required: true

  attr :on_cancel,
       :any,
       default: nil,
       doc:
         "phx-click event handler (atom or string) wired by the parent LiveView; bound only when the pursuit is in `:active` or `:needs_decision`"

  def pursuit_header(assigns) do
    ~H"""
    <header class="glass-surface rounded-xl p-5 space-y-3">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-lg font-medium truncate">{@vm.title}</h2>
        <PursuitStyle.state_badge state={@vm.state} />
      </div>

      <dl class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
        <div>
          <dt class="text-base-content/50 uppercase tracking-wider">Origin</dt>
          <dd class="text-base-content/80">{@vm.origin}</dd>
        </div>
        <div>
          <dt class="text-base-content/50 uppercase tracking-wider">Attempts</dt>
          <dd class="text-base-content/80">{@vm.attempt_count}</dd>
        </div>
        <div>
          <dt class="text-base-content/50 uppercase tracking-wider">Tried releases</dt>
          <dd class="text-base-content/80">{@vm.tried_count}</dd>
        </div>
        <div>
          <dt class="text-base-content/50 uppercase tracking-wider">Started</dt>
          <dd class="text-base-content/80">{format_time(@vm.inserted_at)}</dd>
        </div>
      </dl>

      <div :if={@vm.criteria_summary} class="text-xs text-base-content/60">
        Criteria: {@vm.criteria_summary}
      </div>

      <div :if={@on_cancel && PursuitStyle.cancellable?(@vm.state)} class="flex justify-end">
        <.button variant="dismiss" size="sm" phx-click={@on_cancel}>
          Cancel pursuit
        </.button>
      </div>
    </header>
    """
  end

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
