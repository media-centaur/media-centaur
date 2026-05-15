defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo.People do
  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Library.Person

  def function, do: &MediaCentarrWeb.Components.Detail.MoreInfo.People.people/1

  @linked [
    %Person{tmdb_person_id: 1, name: "Linked Person A"},
    %Person{tmdb_person_id: 2, name: "Linked Person B"}
  ]

  @plain [
    %Person{tmdb_person_id: nil, name: "Plain Name A"},
    %Person{tmdb_person_id: nil, name: "Plain Name B"}
  ]

  @mixed [
    %Person{tmdb_person_id: 1, name: "Linked Person"},
    %Person{tmdb_person_id: nil, name: "Plain Name"}
  ]

  def variations do
    [
      %Variation{
        id: :all_linked,
        description: "Every entry has a `tmdb_person_id` — all names are TMDB links.",
        attributes: %{people: @linked}
      },
      %Variation{
        id: :no_links,
        description: "No `tmdb_person_id` anywhere — names render as plain text.",
        attributes: %{people: @plain}
      },
      %Variation{
        id: :mixed,
        description: "Mix of linked and plain — comma-separator behaves the same regardless.",
        attributes: %{people: @mixed}
      }
    ]
  end
end
