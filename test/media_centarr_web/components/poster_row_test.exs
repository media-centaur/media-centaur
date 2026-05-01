defmodule MediaCentarrWeb.Components.PosterRowTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Components.PosterRow.Item

  test "Item struct enforces an :entity_id field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{id: 1, name: "Foo", year: "2024", poster_url: nil})
    end
  end
end
