defmodule MediaCentaurWeb.Storybook.Review.EpisodePicker do
  @moduledoc """
  Story for the episode picker — the reviewer's choice of which episode a
  file is, for a file matched to a series whose name does not number it.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.EpisodePicker.episode_picker/1
  def render_source, do: :function

  defp seasons do
    [
      %{
        season_number: 1,
        name: "Season 1",
        episodes: [
          %{episode_number: 20, name: "Sample Special 2023", air_date: "2023-12-26"},
          %{episode_number: 21, name: "Sample Special 2024", air_date: "2024-12-27"},
          %{episode_number: 22, name: "Sample Special 2025", air_date: "2025-12-26"}
        ]
      },
      %{
        season_number: 0,
        name: "Specials",
        episodes: [
          %{episode_number: 1, name: "Sample Special Unseen Bits", air_date: "2025-11-02"},
          %{episode_number: 2, name: nil, air_date: nil}
        ]
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :preselected,
        description:
          "The file's year identifies one episode, so it is offered first; the reviewer approves it or chooses another",
        attributes: %{id: "picker-preselected", file_id: "file-1", seasons: seasons(), selected: {1, 22}}
      },
      %Variation{
        id: :unchosen,
        description: "No episode fits the file's year: the reviewer chooses one before Approve appears",
        attributes: %{id: "picker-unchosen", file_id: "file-2", seasons: seasons(), selected: nil}
      },
      %Variation{
        id: :loading,
        description: "The series' episodes are still loading",
        attributes: %{id: "picker-loading", file_id: "file-3", seasons: nil}
      },
      %Variation{
        id: :no_episodes,
        description: "TMDB lists no episodes for the series",
        attributes: %{id: "picker-empty", file_id: "file-4", seasons: []}
      }
    ]
  end
end
