defmodule MediaCentaur.Reconciliation.EngineTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Reconciliation.{Artifact, Engine, Placement, SpineNode}

  # Season 1 spine; each entry is `{title_or_nil}`. `present` leading episodes
  # are already placed (E1..present).
  defp titled_spine(titles, present) do
    titles
    |> Enum.with_index(1)
    |> Enum.map(fn {title, episode} ->
      %SpineNode{season: 1, episode: episode, title: title, present?: episode <= present}
    end)
  end

  defp artifact(claimed_episode, title) do
    %Artifact{
      id: "S02E#{claimed_episode}",
      claimed_season: 2,
      claimed_episode: claimed_episode,
      claimed_title: title
    }
  end

  defp targets(interpretation) do
    Map.new(interpretation.placements, &{&1.artifact_id, &1.episode})
  end

  describe "resolve/3" do
    test "two models corroborating an exact-fit batch links automatically" do
      spine = titled_spine(["A", "B", "C", "D"], 2)
      artifacts = [artifact(1, "C"), artifact(2, "D")]

      resolution = Engine.resolve(spine, artifacts)

      assert resolution.auto?
      assert resolution.unplaced == []
      assert targets(resolution.recommended) == %{"S02E1" => 3, "S02E2" => 4}
    end

    test "title evidence disagreeing with gap-fill is proposed, and title-match wins the recommendation" do
      # Gap is E3..E6; gap-fill would head-fill (E3, E4), titles say (E4, E5).
      spine = titled_spine(["A", "B", "C", "D", "E", "F"], 2)
      artifacts = [artifact(1, "D"), artifact(2, "E")]

      resolution = Engine.resolve(spine, artifacts)

      refute resolution.auto?
      assert targets(resolution.recommended) == %{"S02E1" => 4, "S02E2" => 5}
    end

    test "partial title coverage blends title-match with gap-fill and is not auto" do
      spine = titled_spine(["A", "B", "C", "D"], 1)
      # Gap E2..E4. Two files carry titles (B, C); the third does not.
      artifacts = [artifact(1, "B"), artifact(2, "C"), artifact(3, nil)]

      resolution = Engine.resolve(spine, artifacts)

      refute resolution.auto?
      assert resolution.unplaced == []
      # B/C land by title; the untitled file falls to gap-fill's ordinal slot.
      assert targets(resolution.recommended) == %{"S02E1" => 2, "S02E2" => 3, "S02E3" => 4}
    end

    test "an overflow batch reports the unplaceable artifacts and is not auto" do
      spine = titled_spine(["A", "B", "C", "D"], 2)
      # Gap is E3..E4 (2 nodes); four untitled files arrive.
      artifacts = Enum.map(1..4, &artifact(&1, nil))

      resolution = Engine.resolve(spine, artifacts)

      refute resolution.auto?
      assert resolution.unplaced == ["S02E3", "S02E4"]
      assert map_size(targets(resolution.recommended)) == 2
    end

    test "a single model (no corroboration) is proposed, never auto" do
      spine = titled_spine(["A", "B", "C", "D"], 2)
      artifacts = [artifact(1, nil), artifact(2, nil)]

      resolution = Engine.resolve(spine, artifacts)

      # Exact-fit gap-fill, but only one model spoke → proposed, not auto.
      refute resolution.auto?
      assert targets(resolution.recommended) == %{"S02E1" => 3, "S02E2" => 4}
      assert Enum.map(resolution.alternatives, & &1.model) == [:gap_fill]
    end

    test "alternatives are the raw per-model interpretations, ranked by confidence" do
      spine = titled_spine(["A", "B", "C", "D"], 2)
      artifacts = [artifact(1, "C"), artifact(2, "D")]

      resolution = Engine.resolve(spine, artifacts)

      assert Enum.map(resolution.alternatives, & &1.model) == [:title_match, :gap_fill]
    end

    test "a pinned placement is honored and models re-propose around it" do
      spine = titled_spine([nil, nil, nil, nil, nil, nil], 2)
      pinned = [%Placement{artifact_id: "pin1", season: 1, episode: 4}]

      artifacts = [
        artifact(1, nil),
        artifact(2, nil),
        %Artifact{id: "pin1", claimed_season: 2, claimed_episode: 9, claimed_title: nil}
      ]

      resolution = Engine.resolve(spine, artifacts, pinned: pinned)

      assert resolution.pinned == pinned
      # E4 is taken by the pin; the gap is E3, E5, E6 — re-proposed around it.
      assert targets(resolution.recommended) == %{"S02E1" => 3, "S02E2" => 5}
      refute 4 in Map.values(targets(resolution.recommended))
    end

    test "an artifact no model can place is reported unplaced with no recommendation" do
      spine = titled_spine(["A", "B"], 2)

      resolution = Engine.resolve(spine, [artifact(1, "Nowhere")])

      assert resolution.recommended == nil
      assert resolution.unplaced == ["S02E1"]
      refute resolution.auto?
    end

    test "an empty batch yields an empty resolution" do
      spine = titled_spine(["A", "B", "C"], 1)

      resolution = Engine.resolve(spine, [])

      assert resolution.recommended == nil
      assert resolution.alternatives == []
      assert resolution.unplaced == []
      refute resolution.auto?
    end
  end
end
