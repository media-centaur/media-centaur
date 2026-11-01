defmodule MediaCentaurWeb.Components.HeroCardTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.HeroCard.Item

  test "an item needs its name and the fields the card draws; its subject may be an entity or a ref" do
    fields = %{
      year: "2024",
      runtime: nil,
      genre_label: nil,
      overview: nil,
      backdrop_url: nil,
      logo_url: nil
    }

    assert_raise ArgumentError, fn ->
      struct!(Item, Map.merge(fields, %{id: 1, entity_id: "e"}))
    end

    assert %Item{} = struct!(Item, Map.merge(fields, %{id: 1, entity_id: "e", name: "Movie A"}))
    assert %Item{} = struct!(Item, Map.merge(fields, %{id: 2, ref: {7, :movie}, name: "Movie B"}))
  end
end
