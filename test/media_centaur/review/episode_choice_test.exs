defmodule MediaCentaur.Review.EpisodeChoiceTest do
  @moduledoc """
  A file matched to a series without a season and episode in its name needs
  a person to say which episode it is. When the name carries a year that
  identifies exactly one episode, that episode is offered first — a yearly
  special named for its year is the common case. It is never chosen for the
  reviewer: two candidates, or none, offer nothing.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Review.EpisodeChoice

  defp seasons do
    [
      %{
        season_number: 1,
        name: "Season 1",
        episodes: [
          %{episode_number: 21, name: "Sample Special 2024", air_date: "2024-12-27"},
          %{episode_number: 22, name: "Sample Special 2025", air_date: "2025-12-26"}
        ]
      },
      %{
        season_number: 0,
        name: "Specials",
        episodes: [
          %{episode_number: 3, name: "Sample Special Unseen Bits", air_date: "2025-11-02"}
        ]
      }
    ]
  end

  describe "preselect/2" do
    test "offers the one episode whose name carries the year" do
      assert EpisodeChoice.preselect(seasons(), 2025) == {1, 22}
    end

    test "offers the one episode aired that year when no name carries it" do
      seasons = [
        %{
          season_number: 1,
          name: "Season 1",
          episodes: [
            %{episode_number: 1, name: "Opening Night", air_date: "2024-03-01"},
            %{episode_number: 2, name: "Closing Night", air_date: "2025-03-01"}
          ]
        }
      ]

      assert EpisodeChoice.preselect(seasons, 2025) == {1, 2}
    end

    test "offers nothing when the year fits more than one episode" do
      # By air date, 2025 fits S01E22 and S00E03; neither name decides it once
      # the name match is taken away.
      seasons =
        update_in(seasons(), [Access.at(0), :episodes, Access.at(1), :name], fn _ -> "Finale" end)

      assert EpisodeChoice.preselect(seasons, 2025) == nil
    end

    test "offers nothing without a year" do
      assert EpisodeChoice.preselect(seasons(), nil) == nil
    end

    test "reads the year only as a whole number in the name" do
      seasons = [
        %{
          season_number: 1,
          name: "Season 1",
          episodes: [%{episode_number: 1, name: "Room 20251", air_date: nil}]
        }
      ]

      assert EpisodeChoice.preselect(seasons, 2025) == nil
    end
  end
end
