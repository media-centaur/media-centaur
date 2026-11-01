defmodule MediaCentaurWeb.Components.PosterRowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.PosterRow.Item

  test "an item needs a name at construction time; its subject may be an entity or a ref" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{id: 1, entity_id: "e", year: "2024", poster_url: nil})
    end

    assert %Item{} =
             struct!(Item, %{id: 1, entity_id: "e", name: "Movie A", year: "2024", poster_url: nil})

    assert %Item{} =
             struct!(Item, %{id: 2, ref: {7, :movie}, name: "Movie B", year: "2024", poster_url: nil})
  end

  test "the tile key is the entity id, or the ref as the title detail's URL param" do
    entity = %Item{id: 1, entity_id: "entity-1", name: "Movie A", year: nil, poster_url: nil}
    ref = %Item{id: 2, ref: {7, :movie}, name: "Movie B", year: nil, poster_url: nil}

    assert Item.key(entity) == "entity-1"
    assert Item.key(ref) == "movie-7"
  end
end
