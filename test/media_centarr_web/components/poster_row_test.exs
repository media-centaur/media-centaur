defmodule MediaCentarrWeb.Components.PosterRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.PosterRow

  test "renders one card per item with name visible" do
    items = [
      %{id: 1, name: "Oppenheimer", year: "2023", poster_url: nil},
      %{id: 2, name: "Prior Lives", year: "2023", poster_url: nil}
    ]

    html = render_component(&PosterRow.poster_row/1, items: items)

    assert html =~ "Oppenheimer"
    assert html =~ "Prior Lives"
  end

  test "renders nothing when items is empty" do
    html = render_component(&PosterRow.poster_row/1, items: [])
    refute html =~ "data-component=\"poster-row\""
  end
end
