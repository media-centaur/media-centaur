defmodule MediaCentaur.Settings.LadderTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Settings.Ladder

  @hours [1, 2, 3, 4, 6, 8, 12, 24]

  test "neighbours on a fixed list" do
    assert Ladder.down(@hours, 6) == 4
    assert Ladder.up(@hours, 6) == 8
  end

  test "the ends clamp to themselves" do
    assert Ladder.down(@hours, 1) == 1
    assert Ladder.up(@hours, 24) == 24
  end

  test "a value off the ladder steps from the nearest rung" do
    assert Ladder.down(@hours, 5) == 4
    assert Ladder.up(@hours, 5) == 6
  end

  test "range/3 builds a ladder" do
    assert Ladder.range(5, 100, 5) == Enum.to_list(5..100//5)
  end
end
