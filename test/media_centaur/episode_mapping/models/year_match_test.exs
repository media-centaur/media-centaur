defmodule MediaCentaur.EpisodeMapping.Models.YearMatchTest do
  @moduledoc """
  A file of a known series whose name carries no episode number but a year
  — a yearly special named for its year — is placed on the one episode the
  year identifies: by the year in the episode's title first, by its air
  date otherwise. Two candidates, or none, place nothing. Ported from
  `Review.EpisodeChoice` (2026-09-29), when choosing a position left Review.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.EpisodeMapping.{Artifact, SpineNode}
  alias MediaCentaur.EpisodeMapping.Models.YearMatch

  defp spine do
    [
      %SpineNode{season: 0, episode: 3, title: "Sample Special Unseen Bits", air_date: ~D[2025-11-02]},
      %SpineNode{season: 1, episode: 21, title: "Sample Special 2024", air_date: ~D[2024-12-27]},
      %SpineNode{season: 1, episode: 22, title: "Sample Special 2025", air_date: ~D[2025-12-26]}
    ]
  end

  defp special(year), do: %Artifact{id: "special", claimed_year: year}

  defp placements(interpretations) do
    for interpretation <- interpretations,
        placement <- interpretation.placements,
        do: {interpretation.model, placement.artifact_id, placement.season, placement.episode}
  end

  describe "propose/2" do
    test "places a file on the one episode whose title carries its year" do
      assert placements(YearMatch.propose(spine(), [special(2025)])) ==
               [{:year_in_title, "special", 1, 22}]
    end

    test "places a file on the one episode aired in its year when no title carries it" do
      spine = [
        %SpineNode{season: 1, episode: 1, title: "Opening Night", air_date: ~D[2024-03-01]},
        %SpineNode{season: 1, episode: 2, title: "Closing Night", air_date: ~D[2025-03-01]}
      ]

      assert placements(YearMatch.propose(spine, [special(2025)])) ==
               [{:air_date_year, "special", 1, 2}]
    end

    test "the title reads stronger than the air date" do
      spine = [
        %SpineNode{season: 1, episode: 1, title: "Opening Night", air_date: ~D[2025-03-01]},
        %SpineNode{season: 1, episode: 2, title: "Closing Night", air_date: ~D[2024-03-01]}
      ]

      [by_date] = YearMatch.propose(spine, [special(2025)])
      [by_title] = YearMatch.propose(spine(), [special(2025)])

      assert by_title.confidence > by_date.confidence
    end

    test "places nothing when the year fits more than one episode" do
      # By air date, 2025 fits S01E22 and S00E03; neither title decides it
      # once the title match is taken away.
      spine = List.update_at(spine(), 2, &%{&1 | title: "Finale"})

      assert YearMatch.propose(spine, [special(2025)]) == []
    end

    test "places nothing without a year" do
      assert YearMatch.propose(spine(), [special(nil)]) == []
    end

    test "reads the year only as a whole number in the title" do
      spine = [%SpineNode{season: 1, episode: 1, title: "Room 20251", air_date: nil}]

      assert YearMatch.propose(spine, [special(2025)]) == []
    end

    test "leaves a file that numbers its episode to the numbering models" do
      numbered = %Artifact{id: "numbered", claimed_season: 2, claimed_episode: 1, claimed_year: 2025}

      assert YearMatch.propose(spine(), [numbered]) == []
    end
  end
end
