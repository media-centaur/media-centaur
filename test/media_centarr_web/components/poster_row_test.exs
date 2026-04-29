defmodule MediaCentarrWeb.Components.PosterRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.PosterRow
  alias MediaCentarrWeb.Components.PosterRow.Item

  test "renders one card per item with name visible" do
    items = [
      %Item{id: 1, name: "Sample Movie", year: "2023", poster_url: nil, url: "/library?selected=1"},
      %Item{id: 2, name: "Other Movie", year: "2023", poster_url: nil, url: "/library?selected=2"}
    ]

    html = render_component(&PosterRow.poster_row/1, items: items)

    assert html =~ "Sample Movie"
    assert html =~ "Other Movie"
  end

  test "renders nothing when items is empty" do
    html = render_component(&PosterRow.poster_row/1, items: [])
    refute html =~ "data-component=\"poster-row\""
  end

  test "Item struct enforces a :url field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{id: 1, name: "Foo", year: "2024", poster_url: nil})
    end
  end
end
