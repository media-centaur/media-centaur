defmodule MediaCentaurWeb.Storybook.Composites.AddTile do
  @moduledoc """
  The picker's add tile (UIDR-053): the place in the row that becomes a
  person — a dashed circle with a plus over "Add profile", the profile
  tile's column. The picker wraps it in the button that opens the name
  field in its place.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ProfileTile.add_tile/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "Under the cap of eight profiles, the last place in the row"
      }
    ]
  end
end
