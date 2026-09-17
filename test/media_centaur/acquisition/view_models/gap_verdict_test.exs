defmodule MediaCentaur.Acquisition.ViewModels.GapVerdictTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.{GapEvidence, GapVerdict}
  alias MediaCentaur.Search.IndexerHealth

  @now ~U[2026-08-11 12:00:00Z]

  alias MediaCentaur.Acquisition.PlanEvents.SearchProgress

  defp step(scope, state, attrs \\ []) do
    %{
      scope: scope,
      kind: Keyword.get(attrs, :kind, :primary),
      state: state,
      term_count: Keyword.get(attrs, :term_count),
      residual_after: Keyword.get(attrs, :residual_after)
    }
  end

  defp progress(steps, wanted), do: %SearchProgress{plan_id: "plan-1", wanted: wanted, steps: steps}

  describe "the searching world (a planning board's one verdict slot — UIDR-029, audit DS24)" do
    test "before any event lands it narrates the strategy" do
      verdict = GapVerdict.searching_initial(6)

      assert verdict.world == :searching
      assert verdict.headline =~ "Planning the search"
      assert verdict.evidence_line == nil
    end

    test "an active step headlines what's happening with the live residual" do
      status =
        progress(
          [
            step(:series, :done, residual_after: 4),
            step(:season, :active, term_count: 2),
            step(:episode, :pending)
          ],
          6
        )

      assert GapVerdict.searching(status).headline ==
               "Searching for season packs — 4 episodes still missing…"
    end

    test "a single-episode residual reads grammatically" do
      status = progress([step(:series, :done, residual_after: 1), step(:season, :active)], 6)

      assert GapVerdict.searching(status).headline ==
               "Searching for season packs — 1 episode still missing…"
    end

    test "the primary series scope names the whole-show search" do
      status = progress([step(:series, :active, term_count: 1), step(:episode, :pending)], 6)

      assert GapVerdict.searching(status).headline ==
               "Searching for a complete-series release…"
    end

    test "the episode scope names the singles" do
      status =
        progress(
          [
            step(:series, :done, residual_after: 3),
            step(:season, :done, residual_after: 2),
            step(:episode, :active, term_count: 2)
          ],
          6
        )

      assert GapVerdict.searching(status).headline ==
               "Searching for the 2 missing episodes one by one…"
    end

    test "a single missing episode reads without a count" do
      status = progress([step(:episode, :active, term_count: 1)], 1)

      assert GapVerdict.searching(status).headline == "Searching for the missing episode…"
    end

    test "a fallback season step says it is looking for a pack to offer" do
      status =
        progress(
          [
            step(:episode, :done, residual_after: 1),
            step(:season, :active, term_count: 2, kind: :fallback)
          ],
          1
        )

      assert GapVerdict.searching(status).headline ==
               "Looking for a season pack to offer for the 1 episode still missing…"
    end

    test "a fallback series step says the same for the whole show" do
      status =
        progress(
          [
            step(:episode, :done, residual_after: 2),
            step(:season, :done, residual_after: 2, kind: :fallback),
            step(:series, :active, term_count: 1, kind: :fallback)
          ],
          2
        )

      assert GapVerdict.searching(status).headline ==
               "Looking for a complete-series pack to offer…"
    end

    test "the planning headline promises right-sized releases first" do
      assert GapVerdict.searching_initial(6).headline ==
               "Planning the search — right-sized releases first, wider packs only for what's still missing."
    end

    test "all steps pending narrates the strategy" do
      status =
        progress([step(:series, :pending), step(:season, :pending), step(:episode, :pending)], 6)

      assert GapVerdict.searching(status).headline =~ "Planning the search"
    end

    test "a finished search has no searching verdict — the ready board's verdict takes over" do
      status = progress([step(:series, :done, residual_after: 0), step(:season, :skipped)], 6)
      assert GapVerdict.searching(status) == nil
    end
  end

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

  describe "calendar worlds (spec 2026-09-14)" do
    alias MediaCentaur.TMDB.ReleaseWindow

    # @now is 2026-08-11: the window is read at that date.
    defp window(stage, dates) do
      struct!(%ReleaseWindow{stage: stage}, dates)
    end

    test "a movie still in theaters with a digital date ahead headlines the calendar" do
      verdict =
        build(evidence(%{raw_total: 0}),
          release_window: window(:theatrical, theatrical: ~D[2026-07-24], digital: ~D[2026-10-14])
        )

      assert verdict.world == :in_theaters
      assert verdict.headline == "In theaters since Jul 24 — digital release Oct 14."
      # The receipts are the search diagnosis's, carried through.
      assert verdict.evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — checked 1 minute ago."
    end

    test "a disc-only home date reads as on disc" do
      verdict =
        build(evidence(%{raw_total: 0}),
          release_window: window(:theatrical, theatrical: ~D[2026-07-24], physical: ~D[2026-11-03])
        )

      assert verdict.headline == "In theaters since Jul 24 — on disc Nov 3."
    end

    test "the earlier home date carries when both are known" do
      verdict =
        build(evidence(%{raw_total: 0}),
          release_window:
            window(:theatrical,
              theatrical: ~D[2026-07-24],
              digital: ~D[2026-11-03],
              physical: ~D[2026-10-14]
            )
        )

      assert verdict.headline == "In theaters since Jul 24 — on disc Oct 14."
    end

    test "no home date says so, naming the source" do
      verdict =
        build(evidence(%{raw_total: 0}), release_window: window(:theatrical, theatrical: ~D[2026-07-24]))

      assert verdict.headline == "In theaters since Jul 24 — TMDB has no home release date yet."
    end

    test "an unreleased movie names the theatrical opening and the home date when known" do
      verdict =
        build(evidence(%{raw_total: 0}),
          release_window: window(:unreleased, theatrical: ~D[2026-10-03], digital: ~D[2026-12-12])
        )

      assert verdict.world == :unreleased
      assert verdict.headline == "Not out yet — in theaters from Oct 3, digital release Dec 12."
    end

    test "an unreleased movie with only a theatrical date" do
      verdict =
        build(evidence(%{raw_total: 0}), release_window: window(:unreleased, theatrical: ~D[2026-10-03]))

      assert verdict.headline == "Not out yet — in theaters from Oct 3."
    end

    test "an unreleased movie going straight to digital" do
      verdict =
        build(evidence(%{raw_total: 0}), release_window: window(:unreleased, digital: ~D[2026-10-14]))

      assert verdict.headline == "Not out yet — digital release Oct 14."
    end

    test "an unreleased movie with only TMDB's primary date" do
      verdict =
        build(evidence(%{raw_total: 0}), release_window: window(:unreleased, primary: ~D[2027-03-05]))

      assert verdict.headline == "Not out yet — releases Mar 5, 2027."
    end

    test "a date outside this year carries its year" do
      verdict =
        build(evidence(%{raw_total: 0}),
          release_window: window(:theatrical, theatrical: ~D[2025-12-25], digital: ~D[2027-01-08])
        )

      assert verdict.headline == "In theaters since Dec 25, 2025 — digital release Jan 8, 2027."
    end

    test "the calendar outranks rejected results but keeps the escape hatch" do
      verdict =
        build(evidence(%{raw_total: 2, rejected: [rejected("a", :identity), rejected("b", :red_flag)]}),
          release_window: window(:theatrical, theatrical: ~D[2026-07-24])
        )

      assert verdict.world == :in_theaters
      assert verdict.rejected_count == 2
      assert verdict.show_rejected?

      assert verdict.evidence_line ==
               "Searched “Sample Movie 1990” and “Sample Movie” — checked 1 minute ago."
    end

    test "the calendar outranks stale and absent evidence" do
      stale =
        build(evidence(%{raw_total: 0, checked_at: DateTime.add(@now, -7200, :second)}),
          release_window: window(:unreleased, theatrical: ~D[2026-10-03])
        )

      assert stale.world == :unreleased

      absent = build(nil, release_window: window(:unreleased, theatrical: ~D[2026-10-03]))
      assert absent.world == :unreleased
      assert absent.evidence_line == "Search again checks your indexers live."
    end

    test "blind outranks the calendar" do
      verdict =
        build(evidence(%{raw_total: 0}),
          search_health: %IndexerHealth{state: :unreachable, checked_at: @now},
          release_window: window(:unreleased, theatrical: ~D[2026-10-03])
        )

      assert verdict.world == :blind
    end

    test "below-preference outranks the calendar — real releases exist" do
      verdict =
        build(evidence(%{raw_total: 5}),
          gaps: [],
          below: %{units: 1, releases: 5},
          release_window: window(:theatrical, theatrical: ~D[2026-07-24])
        )

      assert verdict.world == :below_preference
    end

    test "a home-released or unknown window changes nothing" do
      for stage <- [:home, :unknown] do
        verdict =
          build(evidence(%{raw_total: 0}), release_window: window(stage, theatrical: ~D[2026-01-09]))

        assert verdict.world == :nothing_live
      end
    end

    test "a series plan ignores the window" do
      verdict =
        build(evidence(%{raw_total: 0}),
          movie?: false,
          gaps: ["S01E01 · Pilot"],
          release_window: window(:unreleased, theatrical: ~D[2026-10-03])
        )

      assert verdict.world == :nothing_live
    end

    test "no window at all is the search diagnosis" do
      assert build(evidence(%{raw_total: 0})).world == :nothing_live
      assert build(evidence(%{raw_total: 0}), release_window: nil).world == :nothing_live
    end
  end
end
