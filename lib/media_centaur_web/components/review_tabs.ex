defmodule MediaCentaurWeb.Components.ReviewTabs do
  @moduledoc """
  Tab strip joining the two review surfaces — identity review (`/review`,
  "which show is this file?") and episode mapping (`/reconcile`, "which
  episode is this file?"). Both pages render it under a shared "Review"
  heading, so the sidebar's single Review entry fans out here.
  """

  use MediaCentaurWeb, :html

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
    ~H"""
    <div data-nav-zone="zone-tabs" class="flex items-baseline gap-5">
      <.link
        navigate="/review"
        class={["zone-tab", @active == :identity && "zone-tab-active"]}
        data-nav-item
        tabindex="0"
      >
        Identity
        <.badge :if={@identity_count > 0} variant="ghost" size="xs" class="ml-1">
          {@identity_count}
        </.badge>
      </.link>
      <.link
        navigate="/reconcile"
        class={["zone-tab", @active == :mapping && "zone-tab-active"]}
        data-nav-item
        tabindex="0"
      >
        Episode mapping
        <.badge :if={@mapping_count > 0} variant="ghost" size="xs" class="ml-1">
          {@mapping_count}
        </.badge>
      </.link>
    </div>
    """
  end
end
