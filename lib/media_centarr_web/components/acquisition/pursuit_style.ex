defmodule MediaCentarrWeb.Components.Acquisition.PursuitStyle do
  @moduledoc """
  Shared style helpers for pursuit-related components.

  Two pieces of presentation are reused across the row, header, and
  timeline components — the state badge mapping and the severity class
  mapping. Centralising them here keeps the rendering of one pursuit
  state consistent everywhere it appears.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Internal helper; every variant is exercised through the PursuitRow, PursuitHeader, and PursuitTimeline stories that consume it."

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [badge: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow
  alias MediaCentarr.Acquisition.ViewModels.TimelineEntry

  @doc """
  Renders the badge for a pursuit `state` atom. Used by both the
  detail-page header and the activity-zone row so the colour and label
  for a given state are identical across surfaces.
  """
  attr :state, :atom, required: true

  def state_badge(%{state: :active} = assigns), do: ~H|<.badge variant="info">Active</.badge>|

  def state_badge(%{state: :needs_decision} = assigns),
    do: ~H|<.badge variant="warning">Decision</.badge>|

  def state_badge(%{state: :satisfied} = assigns), do: ~H|<.badge variant="success">Satisfied</.badge>|

  def state_badge(%{state: :exhausted} = assigns), do: ~H|<.badge variant="error">Exhausted</.badge>|

  def state_badge(%{state: :cancelled} = assigns), do: ~H|<.badge variant="ghost">Cancelled</.badge>|

  @doc "Tailwind background-color class for a timeline-entry severity dot."
  @spec severity_dot_class(TimelineEntry.severity()) :: String.t()
  def severity_dot_class(:info), do: "bg-info"
  def severity_dot_class(:success), do: "bg-success"
  def severity_dot_class(:warning), do: "bg-warning"
  def severity_dot_class(:error), do: "bg-error"

  @doc "Tailwind text-color class for a timeline-entry summary line."
  @spec severity_text_class(TimelineEntry.severity()) :: String.t()
  def severity_text_class(:info), do: "text-base-content/80"
  def severity_text_class(:success), do: "text-success"
  def severity_text_class(:warning), do: "text-warning"
  def severity_text_class(:error), do: "text-error"

  @doc """
  Returns the set of pursuit states that show a "Cancel pursuit" affordance
  on the detail-page header. Wraps `Pursuits.State.in_flight()` for the web
  layer so the header doesn't need a dependency on the State module just
  to check membership.
  """
  @spec cancellable?(PursuitRow.state()) :: boolean()
  def cancellable?(state), do: state in [:active, :needs_decision]
end
