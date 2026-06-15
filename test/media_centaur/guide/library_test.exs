defmodule MediaCentaur.Guide.LibraryTest do
  use ExUnit.Case, async: true

  test "loads chapters ordered by :order" do
    chapters = MediaCentaur.Guide.chapters()
    assert Enum.any?(chapters, &(&1.slug == "how-identification-works"))
    orders = Enum.map(chapters, & &1.order)
    assert orders == Enum.sort(orders)
  end

  test "parts/0 groups chapters under their part name" do
    parts = MediaCentaur.Guide.parts()
    assert Enum.any?(parts, fn {name, chs} -> name == "Your library" and chs != [] end)
  end

  test "fetch_chapter/1 returns {:ok, chapter} for a known slug" do
    assert {:ok, ch} = MediaCentaur.Guide.fetch_chapter("how-identification-works")
    assert ch.title == "How identification works"
  end

  test "fetch_chapter/1 returns :error for an unknown slug" do
    assert :error = MediaCentaur.Guide.fetch_chapter("nope")
  end
end
