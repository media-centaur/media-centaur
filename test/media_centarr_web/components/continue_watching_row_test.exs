defmodule MediaCentarrWeb.Components.ContinueWatchingRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ContinueWatchingRow

  test "renders one card per item with title visible" do
    items = [
      %{id: 1, name: "The Bear", subtitle: "S03 · E10", progress_pct: 47, backdrop_url: nil},
      %{id: 2, name: "Sample Movie Thirteen", subtitle: "Movie", progress_pct: 22, backdrop_url: nil}
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "The Bear"
    assert html =~ "Sample Movie Thirteen"
    assert html =~ "width: 47%"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: [])
    refute html =~ "data-component=\"continue-watching\""
  end
end
