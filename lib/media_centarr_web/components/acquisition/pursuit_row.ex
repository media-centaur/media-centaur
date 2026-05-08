defmodule MediaCentarrWeb.Components.Acquisition.PursuitRow do
  @moduledoc """
  Renders one pursuit row in the activity zone of the `/download` page.

  Shows title, state, attempt count, and the last few timeline events
  inline. A `data-nav-item` wrapper makes the whole row navigable; the
  "Open full →" affordance navigates to the detail page.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [icon: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow
  alias MediaCentarr.Format
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

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
        <PursuitStyle.state_badge state={@vm.state} />
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
          <span class={"block size-1.5 rounded-full flex-shrink-0 #{PursuitStyle.severity_dot_class(entry.severity)}"} />
          <span class={"min-w-0 flex-1 truncate #{PursuitStyle.severity_text_class(entry.severity)}"}>
            {entry.summary}
          </span>
          <span class="text-base-content/40 whitespace-nowrap">
            {Format.relative_just_now(entry.occurred_at)}
          </span>
        </li>
      </ul>
    <% end %>
    """
  end
end
