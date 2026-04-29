defmodule MediaCentarrWeb.Components.ComingUpRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ComingUpRow
  alias MediaCentarrWeb.Components.ComingUpRow.Item

  test "renders cards with badges" do
    items = [
      %Item{
        id: 1,
        name: "Sample Show",
        subtitle: "MON · S04E01",
        badge: %{label: "Grabbed", variant: :success},
        backdrop_url: nil,
        url: "/upcoming"
      },
      %Item{
        id: 2,
        name: "Other Show",
        subtitle: "THU · S02E08",
        badge: %{label: "Scheduled", variant: :default},
        backdrop_url: nil,
        url: "/upcoming"
      }
    ]

    html = render_component(&ComingUpRow.coming_up_row/1, items: items)

    assert html =~ "Sample Show"
    assert html =~ "Other Show"
    assert html =~ "Grabbed"
    assert html =~ "Scheduled"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ComingUpRow.coming_up_row/1, items: [])
    refute html =~ "data-component=\"coming-up\""
  end

  test "Item struct enforces a :url field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{
        id: 1,
        name: "Foo",
        subtitle: "S1",
        badge: %{label: "Scheduled", variant: :default},
        backdrop_url: nil
      })
    end
  end
end
