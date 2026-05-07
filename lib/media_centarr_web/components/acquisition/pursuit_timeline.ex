defmodule MediaCentarrWeb.Components.Acquisition.PursuitTimeline do
  @moduledoc "Renders the full vertical event timeline for a pursuit."

  use Phoenix.Component

  alias MediaCentarr.Acquisition.ViewModels.Timeline

  attr :vm, Timeline, required: true

  def timeline(assigns) do
    ~H"""
    <div class="glass-surface rounded-xl p-4">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50 mb-3">Timeline</h3>
      <%= if @vm.entries == [] do %>
        <div class="text-sm text-base-content/50">No events yet.</div>
      <% else %>
        <ol class="space-y-3">
          <li :for={entry <- @vm.entries} class="flex items-start gap-3">
            <span class={"mt-1 block size-2 rounded-full flex-shrink-0 #{dot_class(entry.severity)}"} />
            <div class="min-w-0 flex-1">
              <div class={"text-sm #{summary_class(entry.severity)}"}>{entry.summary}</div>
              <div :if={entry.detail} class="text-xs text-base-content/50 truncate">
                {entry.detail}
              </div>
              <div class="text-xs text-base-content/40 mt-0.5">{format_time(entry.occurred_at)}</div>
            </div>
          </li>
        </ol>
      <% end %>
    </div>
    """
  end

  defp dot_class(:info), do: "bg-info"
  defp dot_class(:success), do: "bg-success"
  defp dot_class(:warning), do: "bg-warning"
  defp dot_class(:error), do: "bg-error"

  defp summary_class(:info), do: "text-base-content/80"
  defp summary_class(:success), do: "text-success"
  defp summary_class(:warning), do: "text-warning"
  defp summary_class(:error), do: "text-error"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
