defmodule MediaCentaur.Acquisition.CourSegmentationTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.CourSegmentation

  # Synthetic air dates only (house rule — no real titles/data). Shapes
  # mirror the multi-cour case the design targets: a long broadcast gap
  # between two contiguous episode ranges of the same TMDB season.

  defp ep(season, episode, air_date) do
    %{season: season, episode: episode, air_date: air_date}
  end

  # A weekly run starting at `start` for `count` episodes from `first_ep`.
  defp weekly(season, first_ep, count, start) do
    for offset <- 0..(count - 1) do
      ep(season, first_ep + offset, Date.add(start, offset * 7))
    end
  end

  describe "runs/2 — multi-cour split" do
    test "splits a single TMDB season at a long air-date gap into two runs" do
      cour1 = weekly(1, 1, 28, ~D[2023-09-29])
      # ~9 months after cour 1 ends — a genuine production gap.
      cour2 = weekly(1, 29, 10, ~D[2026-01-16])

      assert [run1, run2] = CourSegmentation.runs(cour1 ++ cour2)

      assert run1.index == 0
      assert run1.first_ep == {1, 1}
      assert run1.last_ep == {1, 28}

      assert run2.index == 1
      assert run2.first_ep == {1, 29}
      assert run2.last_ep == {1, 38}
    end

    test "keeps a short between-cour break (≤ gap) in one run" do
      # E1–E16 weekly, then a two-week new-year break before E17 — under
      # the 56-day threshold, so it stays one run.
      part1 = weekly(1, 1, 16, ~D[2023-09-29])
      part2 = weekly(1, 17, 12, Date.add(List.last(part1).air_date, 14))

      assert [run] = CourSegmentation.runs(part1 ++ part2)
      assert run.first_ep == {1, 1}
      assert run.last_ep == {1, 28}
    end

    test "exposes the date span of each run" do
      cour1 = weekly(1, 1, 4, ~D[2023-09-29])
      cour2 = weekly(1, 5, 4, ~D[2026-01-16])

      assert [run1, run2] = CourSegmentation.runs(cour1 ++ cour2)
      assert run1.date_span == {~D[2023-09-29], List.last(cour1).air_date}
      assert run2.date_span == {~D[2026-01-16], List.last(cour2).air_date}
    end
  end

  describe "runs/2 — single run" do
    test "a continuous weekly season is one run" do
      assert [run] = CourSegmentation.runs(weekly(1, 1, 12, ~D[2024-01-05]))
      assert run.index == 0
      assert run.first_ep == {1, 1}
      assert run.last_ep == {1, 12}
    end

    test "all-nil air dates collapse to one run (no split on missing data)" do
      episodes = for episode <- 1..10, do: ep(1, episode, nil)

      assert [run] = CourSegmentation.runs(episodes)
      assert run.first_ep == {1, 1}
      assert run.last_ep == {1, 10}
      assert run.date_span == nil
    end

    test "a nil air date mid-stream attaches to the current run without splitting" do
      episodes =
        weekly(1, 1, 3, ~D[2024-01-05]) ++
          [ep(1, 4, nil)] ++
          weekly(1, 5, 2, ~D[2024-01-26])

      assert [run] = CourSegmentation.runs(episodes)
      assert run.last_ep == {1, 6}
    end

    test "an empty episode list yields no runs" do
      assert CourSegmentation.runs([]) == []
    end
  end

  describe "runs/2 — gap_days parameter" do
    test "a custom threshold honored — splits where the default would not" do
      # A 30-day gap: under the 56-day default (one run), over a 21-day
      # custom threshold (two runs).
      episodes = [
        ep(1, 1, ~D[2024-01-01]),
        ep(1, 2, ~D[2024-01-08]),
        ep(1, 3, Date.add(~D[2024-01-08], 30)),
        ep(1, 4, Date.add(~D[2024-01-08], 37))
      ]

      assert [_single] = CourSegmentation.runs(episodes)
      assert [run1, run2] = CourSegmentation.runs(episodes, 21)
      assert run1.last_ep == {1, 2}
      assert run2.first_ep == {1, 3}
    end

    test "input order does not matter — episodes are sorted before segmentation" do
      cour1 = weekly(1, 1, 4, ~D[2023-09-29])
      cour2 = weekly(1, 5, 4, ~D[2026-01-16])

      shuffled = Enum.reverse(cour1, Enum.reverse(cour2))
      assert [run1, run2] = CourSegmentation.runs(shuffled)
      assert run1.first_ep == {1, 1}
      assert run2.first_ep == {1, 5}
    end
  end

  describe "run_index_for/3" do
    test "answers which run a unit belongs to" do
      episodes = weekly(1, 1, 4, ~D[2023-09-29]) ++ weekly(1, 5, 4, ~D[2026-01-16])

      assert CourSegmentation.run_index_for(episodes, {1, 2}) == 0
      assert CourSegmentation.run_index_for(episodes, {1, 6}) == 1
    end

    test "returns nil for a unit not present in the episode set" do
      episodes = weekly(1, 1, 4, ~D[2024-01-05])
      assert CourSegmentation.run_index_for(episodes, {2, 1}) == nil
    end
  end
end
