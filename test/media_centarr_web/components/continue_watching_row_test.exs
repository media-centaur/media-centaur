defmodule MediaCentarrWeb.Components.ContinueWatchingRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ContinueWatchingRow
  alias MediaCentarrWeb.Components.ContinueWatchingRow.Item

  defp build_item(attrs) do
    defaults = %{
      id: 1,
      entity_id: "uuid-1",
      name: "Sample Show",
      progress_pct: 50,
      backdrop_url: nil,
      logo_url: nil,
      autoplay: true
    }

    struct!(Item, Map.merge(defaults, Map.new(attrs)))
  end

  test "renders one card per item with title visible when no logo is present" do
    items = [
      build_item(id: 1, name: "Sample Show", progress_pct: 47),
      build_item(id: 2, name: "Sample Movie", progress_pct: 22)
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Sample Show"
    assert html =~ "Sample Movie"
    assert html =~ "width: 47%"
    assert html =~ "See all"
    assert html =~ ~s(data-component="continue-watching-see-all")
  end

  test "renders the logo image instead of the title text when logo_url is present" do
    items = [
      build_item(
        id: 1,
        name: "Sample Show",
        logo_url: "/media-images/abc/logo.png"
      )
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ ~s(src="/media-images/abc/logo.png")
    assert html =~ ~s(alt="Sample Show")
    # Title text should not appear as a heading when logo is shown
    refute html =~ ~s(<div class="text-2xl font-semibold)
  end

  test "falls back to title text when logo_url is nil" do
    items = [
      build_item(id: 1, name: "Sample Show", logo_url: nil)
    ]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Sample Show"
    refute html =~ "<img src=\"/media-images"
  end

  test "renders all items provided — caller controls the limit (row scrolls horizontally)" do
    items =
      for i <- 1..10,
          do: build_item(id: i, name: "Item #{i}", progress_pct: 50)

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "Item 1"
    assert html =~ "Item 8"
    assert html =~ "Item 10"
    # Row scrolls horizontally — overflow handles the card-count display.
    assert html =~ ~s(data-scroll-row="continue-watching")
  end

  test "renders the See-all placeholder pointing to /library?in_progress=1" do
    items = [build_item(id: 1, name: "Foo", progress_pct: 30)]

    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: items)

    assert html =~ "See all"
    assert html =~ "/library?in_progress=1"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ContinueWatchingRow.continue_watching_row/1, items: [])
    refute html =~ ~s(data-component="continue-watching")
  end

  test "Item struct enforces an :entity_id field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{
        id: 1,
        name: "Foo",
        progress_pct: 30,
        backdrop_url: nil
      })
    end
  end
end
