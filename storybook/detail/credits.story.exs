defmodule MediaCentaurWeb.Storybook.Detail.Credits do
  @moduledoc """
  A title's credits line: Directed by, Written by, Created by. The Cast
  view's headline for an owned movie, and the body of an unowned title's
  detail.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.Credits.credits/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :movie,
        description: "A movie with a director and two writers: two lines.",
        attributes: %{
          id: "story-credits-movie",
          crew: [
            %Person{name: "Jane Director", job: "Director", tmdb_person_id: 1},
            %Person{name: "Writer A", job: "Screenplay", tmdb_person_id: 2},
            %Person{name: "Writer B", job: "Story"}
          ]
        }
      },
      %Variation{
        id: :director_only,
        description: "Only the directing crew is known — an unowned movie's usual case.",
        attributes: %{
          id: "story-credits-director",
          crew: [%Person{name: "Jane Director", job: "Director", tmdb_person_id: 1}]
        }
      },
      %Variation{
        id: :series,
        description: "A series: its creators.",
        attributes: %{
          id: "story-credits-series",
          crew: [
            %Person{name: "Creator A", job: "Creator", tmdb_person_id: 3},
            %Person{name: "Creator B", job: "Creator", tmdb_person_id: 4}
          ]
        }
      },
      %Variation{
        id: :none,
        description: "No one in the three roles: nothing is drawn.",
        attributes: %{id: "story-credits-none", crew: [%Person{name: "Editor A", job: "Editor"}]}
      }
    ]
  end
end
