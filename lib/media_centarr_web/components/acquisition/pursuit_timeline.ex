defmodule MediaCentarrWeb.Components.Acquisition.PursuitTimeline do
  @moduledoc "Renders the full vertical event timeline for a pursuit."

  use Phoenix.Component

  alias MediaCentarr.Acquisition.ViewModels.Timeline
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :vm, Timeline, required: true

  def timeline(assigns) do
    ~H"""
    <%!-- Flat section inside the modal panel. See `pursuit_header.ex`
          for the rationale. --%>
    <div class="space-y-3">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">History</h3>
      <%= if @vm.entries == [] do %>
        <div class="text-sm text-base-content/50">No events yet.</div>
      <% else %>
        <ol class="space-y-3">
          <li :for={entry <- @vm.entries} class="flex items-start gap-3">
            <span class={"mt-1 block size-2 rounded-full flex-shrink-0 #{PursuitStyle.severity_dot_class(entry.severity)}"} />
            <div class="min-w-0 flex-1">
              <div class={"text-sm #{PursuitStyle.severity_text_class(entry.severity)}"}>
                {entry.summary}
              </div>
              <div
                :if={entry.detail}
                class="text-xs text-base-content/50 truncate"
                title={entry.detail}
              >
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

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
