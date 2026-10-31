defmodule MediaCentaurWeb.Components.FeatureOff do
  @moduledoc """
  The one drawing of a feature that is off (ADR-081): what a gated page, a
  hidden Settings section reached by its URL, a Status drill-in or the
  pairing page shows in place of its content.

  Composed from `empty_state/1` (UIDR-034): the headline is the fact
  ("Social is off"), the body what the feature is — its registry line, or
  the caller's own sentence when the reader cannot act here — and the
  action the one way out, **Turn on <name>**, which pushes
  `"turn_on_feature"` to `Live.FeaturesAware`. The pairing page, a device
  that is not the host, renders it without the action: the flag is the
  host's to set.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Features.Feature

  attr :feature, Feature, required: true, doc: "the registry entry (`Features.get/1`)"
  attr :id, :string, default: nil
  attr :action?, :boolean, default: true, doc: "whether the reader can turn the feature on from here"

  slot :inner_block, doc: "the body, in place of the feature's registry line"

  def feature_off(assigns) do
    ~H"""
    <.empty_state id={@id} icon="hero-power" headline={"#{@feature.name} is off"}>
      <%= if @inner_block == [] do %>
        {@feature.description}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
      <:action :if={@action?}>
        <.button
          id={@id && "#{@id}-turn-on"}
          variant="primary"
          size="sm"
          phx-click="turn_on_feature"
          phx-value-feature={@feature.id}
          data-nav-item
          tabindex="0"
        >
          Turn on {@feature.name}
        </.button>
      </:action>
    </.empty_state>
    """
  end
end
