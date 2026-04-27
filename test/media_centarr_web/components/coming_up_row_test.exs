defmodule MediaCentarrWeb.Components.ComingUpRowTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ComingUpRow

  test "renders cards with badges" do
    items = [
      %{
        id: 1,
        name: "The Bear",
        subtitle: "MON · S04E01",
        badge: %{label: "Grabbed", variant: :success},
        backdrop_url: nil
      },
      %{
        id: 2,
        name: "Severance",
        subtitle: "THU · S02E08",
        badge: %{label: "Scheduled", variant: :default},
        backdrop_url: nil
      }
    ]

    html = render_component(&ComingUpRow.coming_up_row/1, items: items)

    assert html =~ "The Bear"
    assert html =~ "Severance"
    assert html =~ "Grabbed"
    assert html =~ "Scheduled"
  end

  test "renders nothing when items is empty" do
    html = render_component(&ComingUpRow.coming_up_row/1, items: [])
    refute html =~ "data-component=\"coming-up\""
  end
end
