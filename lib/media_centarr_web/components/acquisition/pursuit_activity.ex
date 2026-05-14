defmodule MediaCentarrWeb.Components.Acquisition.PursuitActivity do
  @moduledoc """
  Live status card for the pursuit detail page.

  Renders the current_action verb + description, an optional download
  progress bar, the next_step sentence, manual action buttons (driven by
  `vm.available_actions`), and a staleness footnote.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [button: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus

  attr :vm, PursuitStatus, required: true
  attr :on_cancel, :string, default: nil
  attr :on_change_target, :string, default: nil
  attr :on_request_decision, :string, default: nil

  def pursuit_activity(assigns) do
    ~H"""
    <section class="glass-inset rounded-xl p-5 space-y-4">
      <div class="space-y-1">
        <div class={"text-base font-medium #{severity_class(@vm.current_action.severity)}"}>
          {@vm.current_action.verb}
        </div>
        <div class="text-sm text-base-content/80">{@vm.current_action.description}</div>
        <%!-- For search-related verbs ("Searching", "Stopped" after an
              auto-search), surface the literal Prowlarr queries inline
              so "Looking for an acceptable release" is anchored to the
              actual strings being tried. Header carries the canonical
              listing — this is a quick reference next to the verb. --%>
        <ul
          :if={search_related?(@vm.current_action.verb) && @vm.recipe.search_queries != []}
          class="text-xs text-base-content/60 space-y-0.5 pt-1"
        >
          <li
            :for={query <- @vm.recipe.search_queries}
            class="font-mono text-base-content/70 truncate"
            title={query}
          >
            {query}
          </li>
        </ul>
      </div>

      <div :if={@vm.download && @vm.download.progress_pct} class="space-y-1">
        <div class="h-2 rounded-full bg-base-content/10 overflow-hidden">
          <div
            class="h-full bg-primary transition-all duration-300"
            style={"width: #{progress_width(@vm.download.progress_pct)}%"}
          />
        </div>
      </div>

      <div :if={@vm.next_step} class="text-xs text-base-content/60">
        Next: {@vm.next_step.description}
      </div>

      <div :if={@vm.available_actions != []} class="flex flex-wrap gap-2 justify-end pt-1">
        <.button
          :if={:change_target in @vm.available_actions and @on_change_target}
          variant="neutral"
          size="sm"
          phx-click={@on_change_target}
        >
          Change target
        </.button>
        <.button
          :if={:request_decision in @vm.available_actions and @on_request_decision}
          variant="neutral"
          size="sm"
          phx-click={@on_request_decision}
        >
          Pick a different release
        </.button>
        <.button
          :if={:cancel in @vm.available_actions and @on_cancel}
          variant="dismiss"
          size="sm"
          phx-click={@on_cancel}
        >
          Cancel pursuit
        </.button>
      </div>

      <div :if={staleness_message(@vm)} class={"text-xs #{staleness_class(@vm.staleness)}"}>
        {staleness_message(@vm)}
      </div>
    </section>
    """
  end

  defp severity_class(:success), do: "text-success"
  defp severity_class(:warning), do: "text-warning"
  defp severity_class(:error), do: "text-error"
  defp severity_class(_), do: "text-base-content"

  # Verbs the PursuitStatus VM uses for search-flavored states. Kept as a
  # small allow-list to avoid the query list trailing every verb.
  defp search_related?(verb) when verb in ["Searching", "Seeking", "Stopped"], do: true
  defp search_related?(_), do: false

  defp staleness_class(:very_stale), do: "text-error"
  defp staleness_class(:stale), do: "text-warning"
  defp staleness_class(_), do: "text-base-content/40"

  defp staleness_message(%{staleness: :fresh}), do: nil
  defp staleness_message(%{last_activity_at: nil}), do: nil

  defp staleness_message(%{last_activity_at: ts}) do
    "Last activity: #{relative_time(ts)}"
  end

  defp relative_time(%DateTime{} = ts) do
    diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86_400)}d ago"
    end
  end

  defp progress_width(pct) when is_number(pct), do: max(0, min(100, round(pct)))
end
