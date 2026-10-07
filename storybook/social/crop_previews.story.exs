defmodule MediaCentaurWeb.Storybook.Social.CropPreviews do
  @moduledoc """
  The crop stage's two preview frames (*How it will look*): the filled
  tile's picture recipe at 48 and 40, each holding the canvas the
  `ImageCrop` hook paints. Empty here, since no hook runs in the catalog.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Social.IdentityTile.crop_previews/1
  def render_source, do: :function

  def variations do
    [
      %Variation{id: :frames, attributes: %{}},
      %Variation{
        id: :in_a_hue,
        description: "The hue rides the enclosing field's root and reaches the frames by inheritance",
        attributes: %{},
        template: ~s|<div style="--hue: 195"><.psb-variation/></div>|
      }
    ]
  end
end
