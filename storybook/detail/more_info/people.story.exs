defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo.People do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfo.People.people/1

  @linked [
    %{"tmdb_person_id" => 1, "name" => "Linked Person A"},
    %{"tmdb_person_id" => 2, "name" => "Linked Person B"}
  ]

  @plain [
    %{"tmdb_person_id" => nil, "name" => "Plain Name A"},
    %{"tmdb_person_id" => nil, "name" => "Plain Name B"}
  ]

  @mixed [
    %{"tmdb_person_id" => 1, "name" => "Linked Person"},
    %{"tmdb_person_id" => nil, "name" => "Plain Name"}
  ]

  def variations do
    [
      %PhoenixStorybook.Variation{
        id: :all_linked,
        description: "Every entry has a `tmdb_person_id` — all names are TMDB links.",
        attributes: %{people: @linked}
      },
      %PhoenixStorybook.Variation{
        id: :no_links,
        description: "No `tmdb_person_id` anywhere — names render as plain text.",
        attributes: %{people: @plain}
      },
      %PhoenixStorybook.Variation{
        id: :mixed,
        description: "Mix of linked and plain — comma-separator behaves the same regardless.",
        attributes: %{people: @mixed}
      }
    ]
  end
end
