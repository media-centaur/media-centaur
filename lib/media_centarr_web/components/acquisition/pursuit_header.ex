defmodule MediaCentarrWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Header for the `/download/:pursuit_id` detail page."

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, button: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader

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
        <.state_badge state={@vm.state} />
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

      <div :if={@on_cancel && @vm.state in [:active, :needs_decision]} class="flex justify-end">
        <.button variant="dismiss" size="sm" phx-click={@on_cancel}>
          Cancel pursuit
        </.button>
      </div>
    </header>
    """
  end

  attr :state, :atom, required: true

  defp state_badge(%{state: :active} = assigns), do: ~H|<.badge variant="info">Active</.badge>|

  defp state_badge(%{state: :needs_decision} = assigns),
    do: ~H|<.badge variant="warning">Needs decision</.badge>|

  defp state_badge(%{state: :satisfied} = assigns), do: ~H|<.badge variant="success">Satisfied</.badge>|

  defp state_badge(%{state: :exhausted} = assigns), do: ~H|<.badge variant="error">Exhausted</.badge>|

  defp state_badge(%{state: :cancelled} = assigns), do: ~H|<.badge variant="ghost">Cancelled</.badge>|

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
