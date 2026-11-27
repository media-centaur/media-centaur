defmodule MediaCentaurWeb.Storybook.Detail.CastStrip do
  @moduledoc """
  Top cast: round headshots with name and character, for a title the
  library does not own (the plan modal's confirm stage, the unowned
  title detail).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.CastStrip.cast_strip/1
  def render_source, do: :function
  def layout, do: :one_column

  defp cast(count) do
    for index <- 1..count do
      %Person{
        name: "Actor #{index}",
        character: "Character #{index}",
        order: index - 1,
        tmdb_person_id: index
      }
    end
  end

  def variations do
    [
      %Variation{
        id: :few,
        description: "Two people: the strip is as wide as they are.",
        attributes: %{id: "story-cast-few", cast: cast(2)}
      },
      %Variation{
        id: :full,
        description: "The cap of ten: wider than its column, it scrolls sideways.",
        attributes: %{id: "story-cast-full", cast: cast(10)}
      },
      %Variation{
        id: :no_character,
        description: "A person with no character credited: the name alone.",
        attributes: %{
          id: "story-cast-no-character",
          cast: [%Person{name: "Actor One", order: 0}]
        }
      }
    ]
  end
end
