defmodule MediaCentaur.Reconciliation.Models.TitleMatchTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Reconciliation.{Artifact, SpineNode}
  alias MediaCentaur.Reconciliation.Models.{GapFill, TitleMatch}

  # Synthetic spine: one TMDB season, every node carrying a generic title.
  # `present` of the leading episodes are already placed (E1..present).
  defp titled_spine(titles, present) do
    titles
    |> Enum.with_index(1)
    |> Enum.map(fn {title, episode} ->
      %SpineNode{season: 1, episode: episode, title: title, present?: episode <= present}
    end)
  end

  # An artifact claiming its own (untrusted) "Season 2" numbering, optionally
  # carrying the episode title a release embedded in the filename.
  defp artifact(claimed_episode, title) do
    %Artifact{
      id: "S02E#{claimed_episode}",
      claimed_season: 2,
      claimed_episode: claimed_episode,
      claimed_title: title
    }
  end

  describe "propose/2" do
    test "maps artifacts to the title-matching spine node, ignoring claimed numbering" do
      spine = titled_spine(["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"], 2)

      assert [interpretation] =
               TitleMatch.propose(spine, [artifact(1, "Gamma"), artifact(2, "Epsilon")])

      targets = Enum.map(interpretation.placements, &{&1.artifact_id, &1.season, &1.episode})

      assert {"S02E1", 1, 3} in targets
      assert {"S02E2", 1, 5} in targets
      assert length(interpretation.placements) == 2
    end

    test "abstains when no artifact carries a title" do
      spine = titled_spine(["Alpha", "Beta", "Gamma"], 1)

      assert TitleMatch.propose(spine, [artifact(1, nil), artifact(2, nil)]) == []
    end

    test "abstains when the spine carries no titles" do
      spine = [
        %SpineNode{season: 1, episode: 1, title: nil, present?: true},
        %SpineNode{season: 1, episode: 2, title: nil, present?: false}
      ]

      assert TitleMatch.propose(spine, [artifact(1, "Beta")]) == []
    end

    test "places only the artifacts whose titles match, skipping the rest" do
      spine = titled_spine(["Alpha", "Beta", "Gamma", "Delta"], 1)

      assert [interpretation] =
               TitleMatch.propose(spine, [artifact(1, "Gamma"), artifact(2, nil)])

      assert length(interpretation.placements) == 1
      assert [%{artifact_id: "S02E1", episode: 3}] = interpretation.placements
    end

    test "skips an artifact whose title is absent from the spine" do
      spine = titled_spine(["Alpha", "Beta", "Gamma"], 1)

      assert TitleMatch.propose(spine, [artifact(1, "Nowhere")]) == []
    end

    test "matches case- and punctuation-insensitively" do
      spine = titled_spine(["Shall We Go, Then?", "Logistics"], 0)

      assert [interpretation] = TitleMatch.propose(spine, [artifact(1, "shall we go then")])

      assert [%{episode: 1}] = interpretation.placements
    end

    test "skips an ambiguous title that matches more than one spine node" do
      spine = titled_spine(["Recap", "Beta", "Recap"], 0)

      assert TitleMatch.propose(spine, [artifact(1, "Recap")]) == []
    end

    test "corrects an off-by-one that gap-fill would make" do
      # Gap is E3..E6. Gap-fill orders the batch by its claim and zips it onto
      # the gap head-first → S02E1→E3, S02E2→E4. The titles say otherwise.
      spine = titled_spine(["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"], 2)
      artifacts = [artifact(1, "Delta"), artifact(2, "Epsilon")]

      [gap_fill] = GapFill.propose(spine, artifacts)
      gap_targets = Map.new(gap_fill.placements, &{&1.artifact_id, &1.episode})
      assert gap_targets == %{"S02E1" => 3, "S02E2" => 4}

      [title_match] = TitleMatch.propose(spine, artifacts)
      title_targets = Map.new(title_match.placements, &{&1.artifact_id, &1.episode})
      assert title_targets == %{"S02E1" => 4, "S02E2" => 5}
    end

    test "title evidence reads stronger than gap-fill's ordinal inference" do
      spine = titled_spine(["Alpha", "Beta", "Gamma", "Delta"], 1)
      artifacts = [artifact(1, "Beta"), artifact(2, "Gamma"), artifact(3, "Delta")]

      [gap_fill] = GapFill.propose(spine, artifacts)
      [title_match] = TitleMatch.propose(spine, artifacts)

      assert title_match.confidence > gap_fill.confidence
    end

    test "rationale names the matched canonical episodes" do
      spine = titled_spine(["Alpha", "Beta", "Gamma"], 0)

      assert [interpretation] = TitleMatch.propose(spine, [artifact(1, "Gamma")])
      assert interpretation.model == :title_match
      assert interpretation.rationale =~ "E3"
    end
  end
end
