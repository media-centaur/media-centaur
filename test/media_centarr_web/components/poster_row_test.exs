defmodule MediaCentarrWeb.Components.PosterRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.PosterRow
  alias MediaCentarrWeb.Components.PosterRow.Item

  test "renders one card per item with name visible" do
    items = [
      %Item{id: 1, entity_id: "uuid-1", name: "Sample Movie", year: "2023", poster_url: nil},
      %Item{id: 2, entity_id: "uuid-2", name: "Other Movie", year: "2023", poster_url: nil}
    ]

    html = render_component(&PosterRow.poster_row/1, items: items)

    assert html =~ "Sample Movie"
    assert html =~ "Other Movie"
  end

  test "renders nothing when items is empty" do
    html = render_component(&PosterRow.poster_row/1, items: [])
    refute html =~ "data-component=\"poster-row\""
  end

  test "Item struct enforces an :entity_id field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{id: 1, name: "Foo", year: "2024", poster_url: nil})
    end
  end
end
