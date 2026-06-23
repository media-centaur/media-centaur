defmodule MediaCentaurWeb.ReconcileViewTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Reconciliation.{
    AwaitingFile,
    Interpretation,
    Placement,
    Resolution,
    ShowReview,
    SpineNode
  }

  alias MediaCentaurWeb.ReconcileView

  defp spine do
    [
      %SpineNode{season: 1, episode: 29, title: "Gamma", present?: false},
      %SpineNode{season: 1, episode: 30, title: nil, present?: false},
      %SpineNode{season: 1, episode: 1, title: "Alpha", present?: true}
    ]
  end

  describe "node encoding" do
    test "round-trips a node through encode/decode" do
      assert ReconcileView.encode_node(%{season: 1, episode: 29}) == "1-29"
      assert ReconcileView.decode_node("1-29") == {1, 29}
      assert ReconcileView.decode_node("skip") == :skip
    end
  end

  describe "episode_options/1" do
    test "leads with the skip sentinel, then sorted labelled nodes" do
      [skip | rest] = ReconcileView.episode_options(spine())

      assert {"— don't map yet —", "skip"} = skip
      assert {"S1 · E1 — Alpha", "1-1"} = hd(rest)
      # A title-less node shows only the number.
      assert {"S1 · E30", "1-30"} in rest
    end
  end

  describe "initial_targets/1 and included_targets/1" do
    test "seeds select values from the recommendation and drops skips on confirm" do
      resolution = %Resolution{
        recommended: %Interpretation{
          model: :recommended,
          confidence: 0.9,
          rationale: "x",
          placements: [%Placement{artifact_id: "a", season: 1, episode: 29}]
        },
        alternatives: []
      }

      targets = ReconcileView.initial_targets(resolution)
      assert targets == %{"a" => "1-29"}

      # A user excludes "a" and adds "b".
      adjusted = %{"a" => "skip", "b" => "1-30"}
      assert ReconcileView.included_targets(adjusted) == %{"b" => {1, 30}}
    end

    test "no recommendation seeds no targets" do
      assert ReconcileView.initial_targets(%Resolution{recommended: nil}) == %{}
    end
  end

  describe "file_rows/2" do
    test "builds a row per awaiting file with its claimed + current target labels" do
      review = %ShowReview{
        tmdb_id: 42,
        awaiting_files: [
          %AwaitingFile{id: "a", file_path: "/m/S02E01.mkv", claimed_season: 2, claimed_episode: 1},
          %AwaitingFile{id: "b", file_path: "/m/loose.mkv", claimed_season: nil, claimed_episode: nil}
        ],
        spine: spine(),
        resolution: %Resolution{recommended: nil, alternatives: []}
      }

      [row_a, row_b] = ReconcileView.file_rows(review, %{"a" => "1-29"})

      assert row_a.claimed == "S2 · E1"
      assert row_a.target_value == "1-29"
      assert row_a.target_label == "S1 · E29 — Gamma"

      assert row_b.claimed == "—"
      assert row_b.target_value == "skip"
      assert row_b.target_label == nil
    end
  end

  describe "show_summaries/1" do
    test "groups awaiting files by show with a count, sorted by title" do
      files = [
        %AwaitingFile{id: "1", tmdb_id: 42, series_title: "Beta Show"},
        %AwaitingFile{id: "2", tmdb_id: 42, series_title: "Beta Show"},
        %AwaitingFile{id: "3", tmdb_id: 7, series_title: "Alpha Show"}
      ]

      assert [alpha, beta] = ReconcileView.show_summaries(files)
      assert alpha.title == "Alpha Show" and alpha.count == 1
      assert beta.title == "Beta Show" and beta.count == 2 and beta.tmdb_id == 42
    end
  end

  describe "display helpers" do
    test "confidence_pct and humanize_model" do
      assert ReconcileView.confidence_pct(0.9) == "90%"
      assert ReconcileView.confidence_pct(nil) == nil
      assert ReconcileView.humanize_model(:title_match) == "Episode titles"
      assert ReconcileView.humanize_model(:gap_fill) == "Fills the gap, in order"
    end
  end
end
