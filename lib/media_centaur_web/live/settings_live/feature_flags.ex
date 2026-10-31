defmodule MediaCentaurWeb.SettingsLive.FeatureFlags do
  @moduledoc """
  The Feature flags section of the Settings page (ADR-081): one toggle row
  per feature in the registry (`MediaCentaur.Features.all/0`), in its
  order. The label is the feature's name, the description its one line —
  with "In development." after it for a feature at that stage, which is
  what tells a reader why a default-off row exists. `SettingsLive`
  delegates to `render/1` and hosts the `toggle_feature` handler.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Features
  alias MediaCentaur.Features.Feature

  attr :features, MapSet, required: true, doc: "the enabled set (`Live.FeaturesAware`)"

  def render(assigns) do
    ~H"""
    <.settings_card title="Features" data-nav-grid>
      <div class="space-y-0.5">
        <.settings_row
          :for={feature <- Features.all()}
          label={feature.name}
          description={description(feature)}
          checked={feature.id in @features}
          event="toggle_feature"
          event_value={%{"feature" => Atom.to_string(feature.id)}}
        />
      </div>
    </.settings_card>
    """
  end

  @doc "The row's description: the registry line, and the stage when it is not finished."
  @spec description(Feature.t()) :: String.t()
  def description(%Feature{stage: :development, description: description}),
    do: description <> " In development."

  def description(%Feature{description: description}), do: description
end
