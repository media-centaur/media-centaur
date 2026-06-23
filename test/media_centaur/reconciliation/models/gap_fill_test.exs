defmodule MediaCentaur.Reconciliation.Models.GapFillTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Reconciliation.{Artifact, SpineNode}
  alias MediaCentaur.Reconciliation.Models.GapFill

  # Synthetic spine: one TMDB season of `total` episodes, `present` of them
  # already placed (E1..present). Mirrors Frieren — canonical single season,
  # the tail missing — without using a real title.
  defp spine(total, present) do
    for episode <- 1..total do
      %SpineNode{season: 1, episode: episode, title: nil, present?: episode <= present}
    end
  end

  # Artifacts claim their own (untrusted) "Season 2" numbering — the whole
  # point is gap-fill ignores the claim except for ordering.
  defp cour_artifacts(count) do
    for n <- 1..count do
      %Artifact{id: "S02E#{n}", claimed_season: 2, claimed_episode: n, claimed_title: nil}
    end
  end

  describe "propose/2" do
    test "maps the batch onto the contiguous missing tail, ignoring the claimed numbering" do
      # 38-episode season, E1–28 present → gap is E29–38; 9 cour files.
      assert [interpretation] = GapFill.propose(spine(38, 28), cour_artifacts(9))

      targets = Enum.map(interpretation.placements, &{&1.artifact_id, &1.season, &1.episode})

      assert {"S02E1", 1, 29} in targets
      assert {"S02E9", 1, 37} in targets
      assert length(interpretation.placements) == 9
      # 9 files into a 10-gap → partial fill, not full confidence.
      assert interpretation.confidence < 1.0
      assert interpretation.rationale =~ "29"
    end

    test "an exact count fill reads as higher confidence than a partial one" do
      [partial] = GapFill.propose(spine(38, 28), cour_artifacts(9))
      [exact] = GapFill.propose(spine(38, 28), cour_artifacts(10))

      assert exact.confidence > partial.confidence
      assert length(exact.placements) == 10
      assert Enum.any?(exact.placements, &(&1.season == 1 and &1.episode == 38))
    end

    test "more artifacts than the gap drops confidence (overflow signals a mismatch)" do
      [partial] = GapFill.propose(spine(38, 28), cour_artifacts(9))
      [overflow] = GapFill.propose(spine(38, 28), cour_artifacts(12))

      assert overflow.confidence < partial.confidence
    end

    test "no missing spine nodes yields no interpretation" do
      assert GapFill.propose(spine(38, 38), cour_artifacts(2)) == []
    end

    test "no artifacts yields no interpretation" do
      assert GapFill.propose(spine(38, 28), []) == []
    end
  end
end
