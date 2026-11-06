defmodule MediaCentaurWeb.Components.MarqueeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Marquee
  alias MediaCentaurWeb.Components.Marquee.Item

  defp item(name) do
    %Item{
      entity_id: "entity-" <> name,
      ref: {1, :tv_series},
      name: name,
      eyebrow: "Tonight",
      badge: nil,
      backdrop_url: nil,
      logo_url: nil,
      line: nil
    }
  end

  defp names(columns) do
    Enum.map(columns, fn column ->
      Enum.map(column, fn
        :see_all -> :see_all
        %Item{name: name} -> name
      end)
    end)
  end

  describe "columns/2 — the See all tile takes the slot after the last tile" do
    test "no tiles: See all alone in the first column" do
      assert names(Marquee.columns([], true)) == [[:see_all]]
    end

    test "one tile shares its column with See all" do
      assert names(Marquee.columns([item("B")], true)) == [["B", :see_all]]
    end

    test "three tiles fill a column, See all starts the next" do
      tiles = Enum.map(~w(B C D), &item/1)
      assert names(Marquee.columns(tiles, true)) == [["B", "C", "D"], [:see_all]]
    end

    test "nine tiles fill three columns, See all alone in a fourth" do
      tiles = Enum.map(~w(B C D E F G H I J), &item/1)

      assert names(Marquee.columns(tiles, true)) ==
               [["B", "C", "D"], ["E", "F", "G"], ["H", "I", "J"], [:see_all]]
    end

    test "without a page to see, the columns hold the tiles alone" do
      tiles = Enum.map(~w(B C D E), &item/1)
      assert names(Marquee.columns(tiles, false)) == [["B", "C", "D"], ["E"]]
      assert Marquee.columns([], false) == []
    end
  end

  describe "Item.key/1 — how a tile is opened and identified" do
    test "a tile with a library entity is keyed by it" do
      assert Item.key(item("B")) == "entity-B"
    end

    test "a tile without one is keyed by its TMDB ref" do
      assert Item.key(%{item("B") | entity_id: nil, ref: {246_810, :tv_series}}) ==
               "tv_series-246810"
    end
  end
end
