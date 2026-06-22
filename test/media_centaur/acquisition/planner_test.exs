defmodule MediaCentaur.Acquisition.PlannerTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Planner
  alias MediaCentaur.Search.SearchResult

  @prefs %{min_quality: "hd_1080p", max_quality: "uhd_4k"}

  defp option(guid, scope, attrs \\ []) do
    %Planner.Option{
      result:
        struct(
          %SearchResult{
            title: "Sample.Show.#{guid}",
            guid: guid,
            indexer_id: 1,
            quality: Keyword.get(attrs, :quality, :hd_1080p),
            seeders: Keyword.get(attrs, :seeders, 10)
          },
          %{}
        ),
      scope: scope,
      coverable: Keyword.get(attrs, :coverable, :all)
    }
  end

  defp assigned_guid_for(solution, unit) do
    Enum.find_value(solution.assignments, fn assignment ->
      if unit in assignment.units, do: assignment.result.guid
    end)
  end

  describe "solve/3 — singles" do
    test "each unit gets its best option; units nothing covers are unfound" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]

      options = [
        option("e1", {:episode, 1, 1}),
        option("e2", {:episode, 1, 2})
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert assigned_guid_for(solution, {1, 1}) == "e1"
      assert assigned_guid_for(solution, {1, 2}) == "e2"
      assert solution.unfound == [{1, 3}]
    end

    test "health tiebreak — equal quality picks more seeders" do
      wanted = [{1, 1}]

      options = [
        option("weak", {:episode, 1, 1}, seeders: 2),
        option("strong", {:episode, 1, 1}, seeders: 80)
      ]

      assert assigned_guid_for(Planner.solve(wanted, options, @prefs), {1, 1}) == "strong"
    end

    test "user preference — higher acceptable quality beats seeders" do
      wanted = [{1, 1}]

      options = [
        option("hd", {:episode, 1, 1}, quality: :hd_1080p, seeders: 500),
        option("uhd", {:episode, 1, 1}, quality: :uhd_4k, seeders: 5)
      ]

      assert assigned_guid_for(Planner.solve(wanted, options, @prefs), {1, 1}) == "uhd"
    end

    test "unacceptable quality is never assigned" do
      wanted = [{1, 1}]

      options = [option("low", {:episode, 1, 1}, quality: nil)]

      solution = Planner.solve(wanted, options, @prefs)
      assert solution.assignments == []
      assert solution.unfound == [{1, 1}]
    end
  end

  describe "solve/3 — the coverage ladder" do
    test "coverage first: a pack covering more wanted units beats higher-quality singles" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]

      options = [
        option("pack", {:season, 1}, quality: :hd_1080p),
        option("e1-uhd", {:episode, 1, 1}, quality: :uhd_4k),
        option("e2-uhd", {:episode, 1, 2}, quality: :uhd_4k)
        # No single for {1,3} — only the pack covers it.
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "pack"
      assert Enum.sort(assignment.units) == [{1, 1}, {1, 2}, {1, 3}]
      assert solution.unfound == []
    end

    test "consolidation beats per-unit quality upgrades: the pack wins even when every unit has a higher-quality single" do
      # Supersedes the original "user preference beats consolidation"
      # rule (campaign plan-solver-consolidation, 2026-06-10): within an
      # acceptable-quality span, the solver never fragments a
      # consolidation for quality — upgrades stay reachable through the
      # plan board's per-release alternatives picker.
      wanted = [{1, 1}, {1, 2}]

      options = [
        option("pack", {:season, 1}, quality: :hd_1080p),
        option("e1-uhd", {:episode, 1, 1}, quality: :uhd_4k),
        option("e2-uhd", {:episode, 1, 2}, quality: :uhd_4k)
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "pack"
      assert Enum.sort(assignment.units) == [{1, 1}, {1, 2}]
    end

    test "the Orville regression: one 4K single must not fragment a season into pack-plus-duplicating-singles" do
      # Real plan, 2026-06-10 (v0.88.1): S2+S3 wanted; both seasons had
      # 1080p packs, S3 also had a 4K E01 single and high-seeder 1080p
      # singles. The old summed-quality ensemble comparison let the lone
      # 4K single veto the S3 pack, then the per-unit pass scattered to
      # whatever had more seeders — 7 grabs, ~11.6 GB of duplicate
      # content. The plan must be exactly the two packs.
      wanted = for episode <- 1..3, do: {2, episode}
      wanted = wanted ++ for episode <- 1..4, do: {3, episode}

      options = [
        option("s2-pack", {:season, 2}, quality: :hd_1080p, seeders: 2),
        option("s3-pack", {:season, 3}, quality: :hd_1080p, seeders: 89),
        # The second S3 pack is load-bearing: it let the old ensemble
        # "cover" the holes between singles, so the singles+pack-b
        # fantasy lineup tied the pack on coverage and beat it on
        # summed quality via the lone 4K single.
        option("s3-pack-b", {:season, 3}, quality: :hd_1080p, seeders: 30),
        option("s3e1-uhd", {:episode, 3, 1}, quality: :uhd_4k, seeders: 2),
        option("s3e2", {:episode, 3, 2}, quality: :hd_1080p, seeders: 589),
        option("s3e4", {:episode, 3, 4}, quality: :hd_1080p, seeders: 531)
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert solution.unfound == []
      assert solution.assignments |> Enum.map(& &1.result.guid) |> Enum.sort() == ["s2-pack", "s3-pack"]

      # No unit is assigned twice — overlapping grabs are duplicate data.
      assigned_units = Enum.flat_map(solution.assignments, & &1.units)
      assert assigned_units == Enum.uniq(assigned_units)
      assert Enum.sort(assigned_units) == Enum.sort(wanted)
    end

    test "consolidation breaks quality ties: equal-quality pack beats equal-quality singles" do
      wanted = [{1, 1}, {1, 2}]

      options = [
        option("pack", {:season, 1}, quality: :hd_1080p, seeders: 5),
        option("e1", {:episode, 1, 1}, quality: :hd_1080p, seeders: 50),
        option("e2", {:episode, 1, 2}, quality: :hd_1080p, seeders: 50)
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "pack"
    end

    test "an unacceptable-quality pack is filtered; singles carry the season" do
      wanted = [{1, 1}, {1, 2}]

      options = [
        option("pack", {:season, 1}, quality: nil),
        option("e1", {:episode, 1, 1}),
        option("e2", {:episode, 1, 2})
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert assigned_guid_for(solution, {1, 1}) == "e1"
      assert assigned_guid_for(solution, {1, 2}) == "e2"
    end

    test "a pack only claims the wanted units of its own scope (partial want lists are normal)" do
      wanted = [{1, 2}, {2, 1}]

      options = [
        option("s1-pack", {:season, 1}, quality: :hd_1080p),
        option("s2e1", {:episode, 2, 1})
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert assigned_guid_for(solution, {1, 2}) == "s1-pack"
      assert assigned_guid_for(solution, {2, 1}) == "s2e1"

      pack_assignment = Enum.find(solution.assignments, &(&1.result.guid == "s1-pack"))
      assert pack_assignment.units == [{1, 2}]
    end

    test "a complete-series option covering everything wins over per-season composition" do
      wanted = [{1, 1}, {1, 2}, {2, 1}, {2, 2}]

      options = [
        option("series", :series, quality: :hd_1080p),
        option("s1-pack", {:season, 1}, quality: :hd_1080p),
        option("s2-pack", {:season, 2}, quality: :hd_1080p)
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "series"
      assert length(assignment.units) == 4
    end
  end

  describe "solve/3 — fit-aware pack gating" do
    # Gating activates only when prefs carry both `pack_min_fit` and a
    # non-empty `span_sizes` (the per-season aired-episode counts). The
    # legacy tests above pass neither, so their broad-first consolidation
    # is preserved; these tests opt in. `fit = wanted-in-span /
    # span-total`; a pack only consolidates/assigns when fit ≥ threshold.

    defp fit_prefs(span_sizes, threshold \\ 0.75) do
      Map.merge(@prefs, %{pack_min_fit: threshold, span_sizes: span_sizes})
    end

    test "one wanted episode of a large season prefers the single, never the series pack" do
      wanted = [{1, 1}]

      options = [
        option("series", :series, quality: :uhd_4k, seeders: 900),
        option("s1-pack", {:season, 1}, quality: :uhd_4k, seeders: 900),
        option("e1", {:episode, 1, 1}, quality: :hd_1080p, seeders: 3)
      ]

      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 24}))

      assert assigned_guid_for(solution, {1, 1}) == "e1"
      assert solution.unfound == []
      refute Enum.any?(solution.assignments, &(&1.result.guid in ["series", "s1-pack"]))
    end

    test "no single available: the unit is unfound and the covering pack is offered" do
      wanted = [{1, 1}]

      options = [option("s1-pack", {:season, 1}, quality: :hd_1080p)]

      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 24}))

      assert solution.unfound == [{1, 1}]
      assert solution.assignments == []
      assert solution.offers[{1, 1}].result.guid == "s1-pack"
    end

    test "the offer is the narrowest covering pack, not the broadest" do
      wanted = [{1, 1}]

      options = [
        option("series", :series, quality: :hd_1080p),
        option("s1-pack", {:season, 1}, quality: :hd_1080p)
      ]

      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 24}))

      assert solution.offers[{1, 1}].result.guid == "s1-pack"
    end

    test "wanting most of the span lets the season pack consolidate" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]

      options = [
        option("s1-pack", {:season, 1}, quality: :hd_1080p),
        option("e1", {:episode, 1, 1}, quality: :uhd_4k),
        option("e2", {:episode, 1, 2}, quality: :uhd_4k)
      ]

      # 3 of 3 aired → fit 1.0 ≥ 0.75: the pack wins its span.
      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 3}))

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "s1-pack"
      assert Enum.sort(assignment.units) == [{1, 1}, {1, 2}, {1, 3}]
    end

    test "wanting a sparse subset of a large season grabs singles, not the pack" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]

      options = [
        option("s1-pack", {:season, 1}, quality: :hd_1080p),
        option("e1", {:episode, 1, 1}),
        option("e2", {:episode, 1, 2}),
        option("e3", {:episode, 1, 3})
      ]

      # 3 of 24 aired → fit 0.125 < 0.75: singles carry it.
      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 24}))

      assert solution.assignments |> Enum.map(& &1.result.guid) |> Enum.sort() == ["e1", "e2", "e3"]
      assert solution.unfound == []
    end

    test "fit threshold is inclusive at the boundary" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]
      options = [option("s1-pack", {:season, 1}, quality: :hd_1080p)]

      # 3 of 4 aired → fit 0.75 == threshold: the pack consolidates.
      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 4}, 0.75))

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "s1-pack"
    end

    test "an episode span is gated by its own breadth, no span_sizes needed" do
      wanted = [{1, 1}, {1, 2}]

      tight = option("tight", {:episodes, 1, 1, 2}, quality: :hd_1080p)
      loose = option("loose", {:episodes, 1, 1, 10}, quality: :uhd_4k, seeders: 900)
      singles = [option("e1", {:episode, 1, 1}), option("e2", {:episode, 1, 2})]

      # tight span: 2 of 2 → fit 1.0 consolidates. loose span: 2 of 10 →
      # fit 0.2 is gated out even though it is broader and higher quality.
      solution = Planner.solve(wanted, [loose, tight | singles], fit_prefs(%{"1" => 24}))

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "tight"
    end

    test "gating off (no span_sizes) keeps legacy broad-first consolidation" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]
      options = [option("s1-pack", {:season, 1}, quality: :hd_1080p)]

      # pack_min_fit set but span_sizes empty → cannot judge fit → legacy.
      solution = Planner.solve(wanted, options, Map.put(@prefs, :pack_min_fit, 0.75))

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "s1-pack"
    end
  end

  describe "solve/3 — coverable allow-list (coverage guard)" do
    # An option's `coverable` set caps which wanted units it may claim,
    # below what its scope would otherwise cover. The plan runner computes
    # it (units a release can physically contain — aired on or before the
    # release was published); the planner just intersects. Default `:all`
    # is the unguarded behaviour every other test relies on.

    test "a season pack does not claim a unit excluded from its coverable set" do
      wanted = [{1, 1}, {1, 2}, {1, 3}]

      # The pack's scope is the whole season, but it physically contains
      # only E1–E2 (E3 aired after it was published).
      options = [option("s1-pack", {:season, 1}, coverable: MapSet.new([{1, 1}, {1, 2}]))]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert assignment.result.guid == "s1-pack"
      assert Enum.sort(assignment.units) == [{1, 1}, {1, 2}]
      assert solution.unfound == [{1, 3}]
    end

    test "a trimmed unit is unfound, not falsely satisfied, even with no other option" do
      wanted = [{1, 1}]

      # The only candidate cannot physically contain the wanted unit.
      options = [option("early-pack", {:season, 1}, coverable: MapSet.new([]))]

      solution = Planner.solve(wanted, options, @prefs)

      assert solution.assignments == []
      assert solution.unfound == [{1, 1}]
    end

    test "a trimmed-out pack is not offered to the unit it cannot contain" do
      wanted = [{1, 1}]

      # Fit gating would set this season pack aside as an offer, but it
      # physically cannot contain E1 — so it must not even be offered.
      options = [option("s1-pack", {:season, 1}, coverable: MapSet.new([]))]

      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 24}))

      assert solution.unfound == [{1, 1}]
      assert solution.offers == %{}
    end

    test "coverable narrows the fit numerator so a mostly-uncontainable pack is gated out" do
      wanted = [{1, 1}, {1, 2}, {1, 3}, {1, 4}]

      # Scope covers all 4 wanted of a 4-episode season (fit would be 1.0),
      # but the pack physically contains only E1 → effective fit 0.25 <
      # 0.75, so it is gated out and the single carries E1.
      options = [
        option("s1-pack", {:season, 1}, quality: :uhd_4k, seeders: 900, coverable: MapSet.new([{1, 1}])),
        option("e1", {:episode, 1, 1}, quality: :hd_1080p)
      ]

      solution = Planner.solve(wanted, options, fit_prefs(%{"1" => 4}))

      assert assigned_guid_for(solution, {1, 1}) == "e1"
      assert Enum.sort(solution.unfound) == [{1, 2}, {1, 3}, {1, 4}]
    end

    test "default :all coverable leaves an option's scope coverage unchanged" do
      wanted = [{1, 1}, {1, 2}]
      options = [option("s1-pack", {:season, 1})]

      solution = Planner.solve(wanted, options, @prefs)

      assert [assignment] = solution.assignments
      assert Enum.sort(assignment.units) == [{1, 1}, {1, 2}]
    end
  end
end
