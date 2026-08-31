defmodule MediaCentaur.Acquisition.ViewModels.GapVerdictTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.{GapEvidence, GapVerdict}
  alias MediaCentaur.Search.IndexerHealth

  @now ~U[2026-08-11 12:00:00Z]

  defp evidence(overrides) do
    searched_at = Map.get(overrides, :checked_at, DateTime.add(@now, -60, :second))

    struct!(
      %GapEvidence{
        searches: [
          %GapEvidence.Search{term: "Sample Movie 1990", searched_at: searched_at, result_count: 2},
          %GapEvidence.Search{term: "Sample Movie", searched_at: searched_at, result_count: 1}
        ],
        rejected: [],
        raw_total: 0,
        checked_at: searched_at
      },
      overrides
    )
  end

  defp rejected(guid, reason) do
    %GapEvidence.Rejected{
      guid: guid,
      title: "Another.Picture.1990.1080p.WEB-DL.x264",
      reason: reason,
      quality: "1080p",
      seeders: 5,
      size_bytes: 2_000_000_000
    }
  end

  defp build(evidence, overrides \\ []) do
    GapVerdict.build(
      evidence,
      Keyword.merge([gaps: ["Sample Movie"], movie?: true, search_health: nil, now: @now], overrides)
    )
  end

  describe "movie worlds" do
    test "rejected results name the count and offer the escape hatch" do
      evidence =
        evidence(%{
          raw_total: 3,
          rejected: [rejected("a", :identity), rejected("b", :red_flag), rejected("c", :identity)]
        })

      verdict = build(evidence)

      assert verdict.world == :rejected
      assert verdict.headline == "3 results came back, but none looked like this movie."

      assert verdict.evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — checked 1 minute ago."

      assert verdict.show_rejected?
    end

    test "a single rejected result reads in the singular" do
      evidence = evidence(%{raw_total: 1, rejected: [rejected("a", :identity)]})

      assert build(evidence).headline == "1 result came back, but it didn't look like this movie."
    end

    test "zero results within the freshness window is a live nothing" do
      searched_at = DateTime.add(@now, -60, :second)
      verdict = build(evidence(%{checked_at: searched_at}))

      assert verdict.world == :nothing_live
      assert verdict.headline == "No indexer had anything for this title."

      assert verdict.evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — checked 1 minute ago."

      refute verdict.show_rejected?
    end

    test "a very recent check reads as just now" do
      searched_at = DateTime.add(@now, -30, :second)

      assert build(evidence(%{checked_at: searched_at})).evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — checked just now."
    end

    test "zero results beyond the freshness window is stale knowledge" do
      searched_at = DateTime.add(@now, -6 * 3600, :second)
      verdict = build(evidence(%{checked_at: searched_at}))

      assert verdict.world == :nothing_stale
      assert verdict.headline == "Nothing in the last known results (from 6 hours ago)."

      assert verdict.evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — Search again asks your indexers live."
    end

    test "no search records at all is an unknown, not a verdict" do
      verdict = build(%GapEvidence{searches: [], rejected: [], raw_total: 0, checked_at: nil})

      assert verdict.world == :no_evidence
      assert verdict.headline == "No recent search results on record for this title."
      assert verdict.evidence_line == "Search again checks your indexers live."
      refute verdict.show_rejected?
    end

    test "nil evidence behaves like no evidence" do
      assert build(nil).world == :no_evidence
    end
  end

  describe "TV aggregate" do
    test "rejected world names the episodes and offers no escape hatch" do
      searches =
        for term <- ["Sample Show", "Sample Show Season 1", "Sample Show S01"] do
          %GapEvidence.Search{
            term: term,
            searched_at: DateTime.add(@now, -720, :second),
            result_count: 3
          }
        end

      evidence =
        evidence(%{
          searches: searches,
          raw_total: 9,
          checked_at: DateTime.add(@now, -720, :second)
        })

      verdict = build(evidence, gaps: ["S01E03", "S01E05"], movie?: false)

      assert verdict.world == :rejected
      assert verdict.headline == "9 results came back, but none worked for these episodes."

      assert verdict.evidence_line ==
               "3 searches — checked 12 minutes ago. Still missing: S01E03, S01E05."

      refute verdict.show_rejected?
    end

    test "live nothing names the episodes" do
      verdict = build(evidence(%{}), gaps: ["S01E03"], movie?: false)

      assert verdict.headline == "No indexer had anything for these episodes."
      assert verdict.evidence_line == "2 searches — checked 1 minute ago. Still missing: S01E03."
    end
  end

  describe "blind precedence (UIDR-016)" do
    defp blind_health(state) do
      %IndexerHealth{state: state, checked_at: @now}
    end

    test "an unreachable Prowlarr outranks every other world" do
      evidence = evidence(%{raw_total: 3, rejected: [rejected("a", :identity)]})

      verdict = build(evidence, search_health: blind_health(:unreachable))

      assert verdict.world == :blind
      assert verdict.headline == "Couldn't check availability — Prowlarr is unreachable — Sample Movie"
      assert verdict.evidence_line == nil
      refute verdict.show_rejected?
    end

    test "every indexer backed off never claims unavailability" do
      verdict = build(evidence(%{}), search_health: blind_health(:blind))

      assert verdict.world == :blind
      assert verdict.headline == "Couldn't check availability — no indexers are answering — Sample Movie"
    end

    test "a degraded search still ran, so the verdict stands" do
      assert build(evidence(%{}), search_health: blind_health(:degraded)).world == :nothing_live
    end
  end

  describe "below-preference world (UIDR-029)" do
    test "gapless below-preference TV plan gets the lower-quality verdict" do
      verdict =
        build(evidence(%{raw_total: 97}),
          gaps: [],
          movie?: false,
          below: %{units: 21, releases: 97},
          wanted: 22,
          covered: 1
        )

      assert verdict.world == :below_preference
      assert verdict.headline =~ "1 episode was found at your quality preference"
      assert verdict.headline =~ "21 are available only in lower quality"
      assert verdict.evidence_line =~ "97 lower-quality releases"
    end

    test "nothing covered reads as an all-lower-quality verdict" do
      verdict =
        build(evidence(%{raw_total: 40}),
          gaps: [],
          movie?: false,
          below: %{units: 8, releases: 40},
          wanted: 8,
          covered: 0
        )

      assert verdict.world == :below_preference
      assert verdict.headline =~ "Nothing at your quality preference"
      assert verdict.headline =~ "8 episodes are available only in lower quality"
    end

    test "a movie below-preference plan names the movie, not episodes" do
      verdict =
        build(evidence(%{raw_total: 3}),
          gaps: [],
          movie?: true,
          below: %{units: 1, releases: 3},
          wanted: 1,
          covered: 0
        )

      assert verdict.world == :below_preference
      assert verdict.headline =~ "This movie is available only in lower quality"
    end

    test "bare gaps keep their diagnosis even when below-preference units exist" do
      verdict =
        build(evidence(%{raw_total: 14}),
          gaps: ["S01E05"],
          movie?: false,
          below: %{units: 3, releases: 9},
          wanted: 5,
          covered: 1
        )

      assert verdict.world == :rejected
    end

    test "the word floor never appears in verdict copy" do
      verdict =
        build(evidence(%{raw_total: 97}),
          gaps: [],
          movie?: false,
          below: %{units: 21, releases: 97},
          wanted: 22,
          covered: 1
        )

      refute String.downcase(verdict.headline) =~ "floor"
      refute String.downcase(verdict.evidence_line || "") =~ "floor"
    end
  end
end
