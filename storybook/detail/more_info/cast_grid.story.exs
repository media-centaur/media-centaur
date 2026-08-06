defmodule MediaCentaurWeb.Storybook.Detail.MoreInfo.CastGrid do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person

  def function, do: &MediaCentaurWeb.Components.Detail.MoreInfo.CastGrid.cast_grid/1

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
          "60 cast entries — exceeds the 24-card cap, so the filter input appears " <>
            "above the grid. Only the first 24 render; the rest are never sent. " <>
            "Typing is a `phx-change` the host LiveView answers, so the input is " <>
            "inert here in isolation — the two variations below stand in for its " <>
            "filtered states.",
        attributes: %{cast: @long_cast}
      },
      %Variation{
        id: :long_cast_filtered,
        description:
          "The same 60 entries with a filter applied. Selection happens server-side " <>
            "in `visible_cast/3`, so the grid renders only the matches — still " <>
            "capped at 24.",
        attributes: %{cast: @long_cast, filter: "Member 1"}
      },
      %Variation{
        id: :long_cast_filtered_no_matches,
        description:
          "A filter matching nobody. The grid renders no cards and the empty-state " <>
            "line takes over.",
        attributes: %{cast: @long_cast, filter: "nobody by that name"}
      }
    ]
  end
end
