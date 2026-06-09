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
      scope: scope
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

    test "user preference beats consolidation: complete singles at higher quality beat the pack" do
      wanted = [{1, 1}, {1, 2}]

      options = [
        option("pack", {:season, 1}, quality: :hd_1080p),
        option("e1-uhd", {:episode, 1, 1}, quality: :uhd_4k),
        option("e2-uhd", {:episode, 1, 2}, quality: :uhd_4k)
      ]

      solution = Planner.solve(wanted, options, @prefs)

      assert assigned_guid_for(solution, {1, 1}) == "e1-uhd"
      assert assigned_guid_for(solution, {1, 2}) == "e2-uhd"
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
end
