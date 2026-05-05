defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo.CastGrid do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfo.CastGrid.cast_grid/1

  @populated Enum.map(0..7, fn i ->
               %{
                 "name" => "Sample Actor #{i + 1}",
                 "character" => "Sample Role #{i + 1}",
                 "tmdb_person_id" => 1000 + i,
                 "profile_path" => nil,
                 "order" => i
               }
             end)

  @no_links [
    %{
      "name" => "Plain Name A",
      "character" => "Role A",
      "tmdb_person_id" => nil,
      "profile_path" => nil,
      "order" => 0
    },
    %{
      "name" => "Plain Name B",
      "character" => "Role B",
      "tmdb_person_id" => nil,
      "profile_path" => nil,
      "order" => 1
    }
  ]

  def variations do
    [
      %PhoenixStorybook.Variation{
        id: :populated,
        description: "Eight cast cards with TMDB person ids — each card is a TMDB link.",
        attributes: %{cast: @populated}
      },
      %PhoenixStorybook.Variation{
        id: :empty,
        description: "Empty cast — entire grid (heading + cards) is hidden.",
        attributes: %{cast: []}
      },
      %PhoenixStorybook.Variation{
        id: :no_tmdb_person_ids,
        description: "Cards without `tmdb_person_id` render as plain text instead of links.",
        attributes: %{cast: @no_links}
      }
    ]
  end
end
