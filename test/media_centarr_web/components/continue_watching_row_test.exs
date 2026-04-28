defmodule MediaCentarrWeb.Components.ContinueWatchingRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ContinueWatchingRow

  test "renders one card per item with title visible" do
    items = [
      %{id: 1, name: "Sample Show", subtitle: "S03 · E10", progress_pct: 47, backdrop_url: nil},
      %{id: 2, name: "Sample Movie", subtitle: "Movie", progress_pct: 22, backdrop_url: nil}
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Sample Show"
    assert html =~ "Sample Movie"
    assert html =~ "width: 47%"
    assert html =~ "See all"
    assert html =~ ~s(data-component="continue-watching-see-all")
  end

  test "renders all items provided — caller controls the limit (row scrolls horizontally)" do
    items =
      for i <- 1..10,
          do: %{id: i, name: "Item #{i}", subtitle: "S1", progress_pct: 50, backdrop_url: nil}

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Item 1"
    assert html =~ "Item 8"
    assert html =~ "Item 10"
    # Row scrolls horizontally — overflow handles the card-count display.
    assert html =~ ~s(data-scroll-row="continue-watching")
  end

  test "renders the See-all placeholder pointing to /library?in_progress=1" do
    items = [%{id: 1, name: "Foo", subtitle: "S1", progress_pct: 30, backdrop_url: nil}]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "See all"
    assert html =~ "/library?in_progress=1"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: [])
    refute html =~ ~s(data-component="continue-watching")
  end
end
