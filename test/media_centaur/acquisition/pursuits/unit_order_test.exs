defmodule MediaCentaur.Acquisition.Pursuits.UnitOrderTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.UnitOrder

  # Extracts {season, episode} from a plain map for the tests.
  defp se(item), do: {item[:s], item[:e]}

  describe "with_positions/2" do
    test "already-ordered items keep their order and get sequential positions" do
      items = [%{s: 1, e: 1}, %{s: 1, e: 2}, %{s: 1, e: 3}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: 1, e: 1}, 0},
               {%{s: 1, e: 2}, 1},
               {%{s: 1, e: 3}, 2}
             ]
    end

    test "reversed items sort ascending by episode" do
      items = [%{s: 1, e: 3}, %{s: 1, e: 1}, %{s: 1, e: 2}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: 1, e: 1}, 0},
               {%{s: 1, e: 2}, 1},
               {%{s: 1, e: 3}, 2}
             ]
    end

    test "sorts across seasons (S01E10 before S02E01)" do
      items = [%{s: 2, e: 1}, %{s: 1, e: 10}, %{s: 1, e: 2}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: 1, e: 2}, 0},
               {%{s: 1, e: 10}, 1},
               {%{s: 2, e: 1}, 2}
             ]
    end

    test "all-nil season/episode preserves input order (no reordering)" do
      items = [%{s: nil, e: nil, q: "c"}, %{s: nil, e: nil, q: "a"}, %{s: nil, e: nil, q: "b"}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: nil, e: nil, q: "c"}, 0},
               {%{s: nil, e: nil, q: "a"}, 1},
               {%{s: nil, e: nil, q: "b"}, 2}
             ]
    end

    test "nil season/episode sorts last but keeps relative input order" do
      items = [%{s: nil, e: nil, q: "x"}, %{s: 1, e: 2}, %{s: nil, e: nil, q: "y"}, %{s: 1, e: 1}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: 1, e: 1}, 0},
               {%{s: 1, e: 2}, 1},
               {%{s: nil, e: nil, q: "x"}, 2},
               {%{s: nil, e: nil, q: "y"}, 3}
             ]
    end

    test "a season with no episode number sorts after its numbered episodes" do
      # episode_number nil is a missing key, so it sorts last within the season.
      items = [%{s: 1, e: 5}, %{s: 1, e: nil}, %{s: 1, e: 1}]

      assert UnitOrder.with_positions(items, &se/1) == [
               {%{s: 1, e: 1}, 0},
               {%{s: 1, e: 5}, 1},
               {%{s: 1, e: nil}, 2}
             ]
    end

    test "empty list returns empty" do
      assert UnitOrder.with_positions([], &se/1) == []
    end
  end
end
