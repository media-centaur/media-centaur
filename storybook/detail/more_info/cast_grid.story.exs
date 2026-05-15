defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo.CastGrid do
  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Library.Person

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfo.CastGrid.cast_grid/1

  @populated Enum.map(0..7, fn i ->
               %Person{
                 name: "Sample Actor #{i + 1}",
                 character: "Sample Role #{i + 1}",
                 tmdb_person_id: 1000 + i,
                 profile_path: nil,
                 order: i
               }
             end)

  @no_links [
    %Person{
      name: "Plain Name A",
      character: "Role A",
      tmdb_person_id: nil,
      profile_path: nil,
      order: 0
    },
    %Person{
      name: "Plain Name B",
      character: "Role B",
      tmdb_person_id: nil,
      profile_path: nil,
      order: 1
    }
  ]

  @long_cast Enum.map(0..59, fn i ->
               %Person{
                 name: "Sample Cast Member #{i + 1}",
                 character: "Sample Role #{i + 1}",
                 tmdb_person_id: 2000 + i,
                 profile_path: nil,
                 order: i
               }
             end)

  def variations do
    [
      %Variation{
        id: :populated,
        description: "Eight cast cards with TMDB person ids — each card is a TMDB link.",
        attributes: %{cast: @populated}
      },
      %Variation{
        id: :empty,
        description: "Empty cast — entire grid (heading + cards) is hidden.",
        attributes: %{cast: []}
      },
      %Variation{
        id: :no_tmdb_person_ids,
        description: "Cards without `tmdb_person_id` render as plain text instead of links.",
        attributes: %{cast: @no_links}
      },
      %Variation{
        id: :long_cast_with_filter,
        description:
          "60 cast entries — exceeds the visible cap, so the inline filter input " <>
            "appears above the grid. Type to filter in real time; the visible count " <>
            "stays capped even after filtering. (JS hook runs in the storybook " <>
            "iframe — try typing 'Cast Member 4' or 'Role 12'.)",
        attributes: %{cast: @long_cast}
      }
    ]
  end
end
