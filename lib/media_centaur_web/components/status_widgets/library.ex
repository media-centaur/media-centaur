defmodule MediaCentaurWeb.Components.StatusWidgets.Library do
  @moduledoc """
  Library subsystem Activity widget: the "Your library" overview.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.LibraryOverviewComponents

  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Status.LibraryOverview

  @doc """
  Library subsystem Activity widget: the "Your library" overview — counts,
  size and recently-added (glance), pending review + in-flight acquisitions,
  completeness gaps, and storage outlook. Composes the library-overview cards
  from the `LibraryOverview` view-model the bundle carries.
  """
  attr :overview, LibraryOverview,
    default: nil,
    doc: "Status.load_overview/0 result, or nil while the async load is in flight"

  attr :storage_drives, :list,
    required: true,
    doc: "Storage.measure_all/0 drive maps for the storage-outlook card"

  attr :at_risk_summary, :map,
    required: true,
    doc: "AbsenceSweeper.at_risk_summary/0 result, summarized for the storage card"

  attr :ttl_days, :integer, required: true

  def library_widget(assigns) do
    at_risk =
      summarize_at_risk(
        assigns.at_risk_summary,
        Availability.dir_status(),
        DateTime.utc_now(),
        assigns.ttl_days
      )

    assigns = Map.put(assigns, :at_risk, at_risk)

    ~H"""
    <div :if={@overview} class="space-y-3" data-testid="library-widget">
      <.glance_card overview={@overview} />
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <.pending_work_card overview={@overview} />
        <.completeness_card overview={@overview} />
        <.storage_outlook_card drives={@storage_drives} at_risk={@at_risk} />
      </div>
    </div>
    <p :if={!@overview} class="text-sm text-base-content/40">Loading library overview…</p>
    """
  end
end
