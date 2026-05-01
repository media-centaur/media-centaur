defmodule MediaCentarrWeb.Components.HeroCardTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Components.HeroCard.Item

  test "Item struct enforces required identity fields at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{
        id: 1,
        name: "Foo",
        year: "2024",
        runtime: nil,
        genre_label: nil,
        overview: nil,
        backdrop_url: nil
      })
    end
  end
end
