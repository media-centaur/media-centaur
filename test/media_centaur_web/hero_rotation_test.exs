defmodule MediaCentaurWeb.HeroRotationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.HeroRotation

  test "returns nil for an empty candidate list" do
    assert HeroRotation.select([], ~U[2026-04-27 12:00:00Z]) == nil
  end

  test "returns a candidate from the list" do
    candidates = [%{id: 1}, %{id: 2}, %{id: 3}]
    assert HeroRotation.select(candidates, ~U[2026-04-27 12:00:00Z]) in candidates
  end

  test "is stable within the same 7-hour rotation window" do
    candidates = for i <- 1..10, do: %{id: i}
    reference = ~U[2026-04-27 12:00:00Z]
    block_start_unix = div(DateTime.to_unix(reference), 7 * 3600) * 7 * 3600
    block_start = DateTime.from_unix!(block_start_unix)
    a = HeroRotation.select(candidates, block_start)
    b = HeroRotation.select(candidates, DateTime.add(block_start, 7 * 3600 - 1, :second))
    assert a == b
  end

  test "rotates across the 7-hour window boundary" do
    candidates = for i <- 1..3, do: %{id: i}
    base = ~U[2026-04-27 00:00:00Z]
    picks = for i <- 0..2, do: HeroRotation.select(candidates, DateTime.add(base, i * 7 * 3600, :second))
    assert length(Enum.uniq(picks)) == 3
  end
end
