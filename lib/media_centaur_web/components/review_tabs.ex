defmodule MediaCentaurWeb.Components.ReviewTabs do
  @moduledoc """
  Tab strip joining the two review surfaces — identity review (`/review`,
  "which show is this file?") and episode mapping (`/reconcile`, "which
  episode is this file?"). Both pages render it under a shared "Review"
  heading, so the sidebar's single Review entry fans out here.

  A composition over `MediaCentaurWeb.Components.TabStrip` that names the
  review dimensions.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]

  alias MediaCentaurWeb.Components.TabStrip.Tab

  attr :active, :atom,
    required: true,
    values: [:identity, :mapping],
    doc: "which review dimension the current page renders"

  attr :identity_count, :integer,
    required: true,
    doc: "files awaiting identity review (`Review.count_pending/0`)"

  attr :mapping_count, :integer,
    required: true,
    doc: "files awaiting an episode-mapping decision (`Reconciliation.count_awaiting/0`)"

  def review_tabs(assigns) do
    assigns =
      assign(assigns, :tabs, [
        %Tab{id: :identity, label: "Identity", navigate: "/review", count: assigns.identity_count},
        %Tab{
          id: :mapping,
          label: "Episode mapping",
          navigate: "/reconcile",
          count: assigns.mapping_count
        }
      ])

    ~H"""
    <.tab_strip tabs={@tabs} active={@active} />
    """
  end
end
