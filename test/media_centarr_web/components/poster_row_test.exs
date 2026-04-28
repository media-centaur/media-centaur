defmodule MediaCentarrWeb.Components.PosterRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.PosterRow

  test "renders one card per item with name visible" do
    items = [
      %{id: 1, name: "Sample Movie", year: "2023", poster_url: nil},
      %{id: 2, name: "Other Movie", year: "2023", poster_url: nil}
    ]

    html = render_component(&PosterRow.poster_row/1, items: items)

    assert html =~ "Sample Movie"
    assert html =~ "Other Movie"
  end

  test "renders nothing when items is empty" do
    html = render_component(&PosterRow.poster_row/1, items: [])
    refute html =~ "data-component=\"poster-row\""
  end

  test "renders a badge when item has badge_label" do
    items = [%{id: 1, name: "Test", year: "2024", poster_url: nil, badge_label: "3×"}]

    html = render_component(&PosterRow.poster_row/1, items: items)

    assert html =~ "3×"
  end

  test "renders no badge when item has no badge_label" do
    items = [%{id: 1, name: "Test", year: "2024", poster_url: nil}]

    html = render_component(&PosterRow.poster_row/1, items: items)

    refute html =~ "bg-primary/85"
  end
end
