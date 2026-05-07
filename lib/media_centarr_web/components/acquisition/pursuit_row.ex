defmodule MediaCentarrWeb.Components.Acquisition.PursuitRow do
  @moduledoc """
  Renders one pursuit row in the activity zone of the `/download` page.

  Shows title, state, attempt count, and the last few timeline events
  inline. A `data-nav-item` wrapper makes the whole row navigable; the
  "Open full →" affordance navigates to the detail page.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1, icon: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow

  attr :vm, PursuitRow, required: true

  def pursuit_row(assigns) do
    ~H"""
    <div
      class="glass-surface rounded-xl p-4 space-y-2"
      data-nav-item
      tabindex="0"
      data-pursuit-id={@vm.id}
    >
      <div class="flex items-baseline justify-between gap-3">
        <div class="min-w-0 flex-1 truncate text-sm font-medium">{@vm.title}</div>
        <.state_badge state={@vm.state} />
      </div>

      <div class="flex items-center gap-3 text-xs text-base-content/60">
        <span>Attempts: {@vm.attempt_count}</span>
        <span>·</span>
        <span>Origin: {@vm.origin}</span>
      </div>

      <.recent_events entries={@vm.recent_events} />

      <div class="flex justify-end pt-1">
        <.link navigate={@vm.detail_path} class="text-xs text-primary inline-flex items-center gap-1">
          Open full <.icon name="hero-arrow-right-mini" class="size-3" />
        </.link>
      </div>
    </div>
    """
  end

  attr :state, :atom, required: true

  defp state_badge(%{state: :active} = assigns), do: ~H|<.badge variant="info">Active</.badge>|

  defp state_badge(%{state: :needs_decision} = assigns),
    do: ~H|<.badge variant="warning">Needs decision</.badge>|

  defp state_badge(%{state: :satisfied} = assigns), do: ~H|<.badge variant="success">Satisfied</.badge>|

  defp state_badge(%{state: :exhausted} = assigns), do: ~H|<.badge variant="error">Exhausted</.badge>|

  defp state_badge(%{state: :cancelled} = assigns), do: ~H|<.badge variant="ghost">Cancelled</.badge>|

  attr :entries,
       :list,
       required: true,
       doc:
         "List of `Acquisition.ViewModels.TimelineEntry` structs (pre-shaped read-side data; no schema/struct enforced at the attr layer)"

  defp recent_events(assigns) do
    ~H"""
    <%= if @entries == [] do %>
      <div class="text-xs text-base-content/40 italic">No events yet.</div>
    <% else %>
      <ul class="space-y-1">
        <li :for={entry <- @entries} class="flex items-baseline gap-2 text-xs">
          <span class={"block size-1.5 rounded-full flex-shrink-0 #{dot_class(entry.severity)}"} />
          <span class={"min-w-0 flex-1 truncate #{summary_class(entry.severity)}"}>
            {entry.summary}
          </span>
          <span class="text-base-content/40 whitespace-nowrap">
            {format_relative(entry.occurred_at)}
          </span>
        </li>
      </ul>
    <% end %>
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

  defp format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(:second), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
