defmodule MediaCentaur.Acquisition.Plans.SearchOrderTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{Plan, SearchOrder}

  # The spec's use-case table (2026-09-17-planning-descent-design.md):
  # a seven-season show, 22 aired episodes per season, the default
  # 75% pack fit.
  @span_sizes Map.new(1..7, &{Integer.to_string(&1), 22})

  defp plan, do: %Plan{title: "Sample Show", tmdb_type: "tv"}

  defp prefs(overrides \\ %{}), do: Map.merge(%{span_sizes: @span_sizes, pack_min_fit: 0.75}, overrides)

  defp season(number), do: for(episode <- 1..22, do: {number, episode})

  # The {scope, kind} sequence, each step's terms taken against the
  # whole want (the residual before anything is found).
  defp walk(wanted, prefs) do
    for step <- SearchOrder.steps(plan(), wanted, prefs),
        do: {step.scope, step.kind, step.terms.(wanted)}
  end

  describe "steps/3 — the scope that fits comes first" do
    test "U1 — one episode of a finished season: the single first; season and series only as fallback" do
      assert walk([{7, 13}], prefs()) == [
               {:episode, :primary, ["Sample Show S07E13"]},
               {:season, :fallback, ["Sample Show Season 7", "Sample Show S07"]},
               {:series, :fallback, ["Sample Show"]}
             ]
    end

    test "U2 — a few scattered episodes of one season: their singles, then the season pack as an offer" do
      assert walk([{7, 3}, {7, 9}, {7, 13}], prefs()) == [
               {:episode, :primary, ["Sample Show S07E03", "Sample Show S07E09", "Sample Show S07E13"]},
               {:season, :fallback, ["Sample Show Season 7", "Sample Show S07"]},
               {:series, :fallback, ["Sample Show"]}
             ]
    end

    test "U3 — most of a season: the season pack first, singles for what it leaves, the series only as fallback" do
      wanted = Enum.take(season(7), 18)

      assert [
               {:season, :primary, ["Sample Show Season 7", "Sample Show S07"]},
               {:episode, :primary, episode_terms},
               {:series, :fallback, ["Sample Show"]}
             ] = walk(wanted, prefs())

      assert length(episode_terms) == 18
    end

    test "U4 — a whole season reads like U3 with every single" do
      assert [
               {:season, :primary, ["Sample Show Season 7", "Sample Show S07"]},
               {:episode, :primary, episode_terms},
               {:series, :fallback, ["Sample Show"]}
             ] = walk(season(7), prefs())

      assert length(episode_terms) == 22
    end

    test "U5 — the whole series: widest first, no fallback" do
      wanted = Enum.flat_map(1..7, &season/1)

      assert [
               {:series, :primary, ["Sample Show"]},
               {:season, :primary, season_terms},
               {:episode, :primary, episode_terms}
             ] = walk(wanted, prefs())

      assert length(season_terms) == 14
      assert length(episode_terms) == 154
    end

    test "U9 — sparse across seasons: the singles, then each season as an offer, then the series" do
      assert walk([{1, 5}, {3, 10}], prefs()) == [
               {:episode, :primary, ["Sample Show S01E05", "Sample Show S03E10"]},
               {:season, :fallback,
                ["Sample Show Season 1", "Sample Show S01", "Sample Show Season 3", "Sample Show S03"]},
               {:series, :fallback, ["Sample Show"]}
             ]
    end

    test "a step's terms follow the residual, not the whole want" do
      wanted = season(1) ++ season(2)
      steps = SearchOrder.steps(plan(), wanted, prefs())
      season_step = Enum.find(steps, &(&1.scope == :season and &1.kind == :primary))
      episode_step = Enum.find(steps, &(&1.scope == :episode))

      residual = season(2)
      assert season_step.terms.(residual) == ["Sample Show Season 2", "Sample Show S02"]
      assert length(episode_step.terms.(residual)) == 22
    end
  end

  describe "steps/3 — when fit cannot be judged" do
    test "no span sizes: every scope fits, widest first, no fallback (today's order)" do
      assert walk([{7, 13}], prefs(%{span_sizes: %{}, pack_min_fit: nil})) == [
               {:series, :primary, ["Sample Show"]},
               {:season, :primary, ["Sample Show Season 7", "Sample Show S07"]},
               {:episode, :primary, ["Sample Show S07E13"]}
             ]
    end

    test "a nil threshold with span sizes reads the same" do
      assert walk([{7, 13}], prefs(%{pack_min_fit: nil})) == [
               {:series, :primary, ["Sample Show"]},
               {:season, :primary, ["Sample Show Season 7", "Sample Show S07"]},
               {:episode, :primary, ["Sample Show S07E13"]}
             ]
    end
  end
end
