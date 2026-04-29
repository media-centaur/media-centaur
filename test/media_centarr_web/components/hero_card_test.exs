defmodule MediaCentarrWeb.Components.HeroCardTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.HeroCard
  alias MediaCentarrWeb.Components.HeroCard.Item

  test "renders title and overview" do
    item = %Item{
      id: 1,
      entity_id: "uuid-1",
      name: "Sample Movie",
      year: "2014",
      runtime: "1h 39m",
      genre_label: "Comedy",
      overview: "A concierge teams up with a lobby boy.",
      backdrop_url: nil,
      logo_url: nil
    }

    html = render_component(&HeroCard.hero_card/1, item: item)

    assert html =~ "Sample Movie"
    assert html =~ "concierge"
    # Play / Details buttons fire phx-click="select_entity" with the entity id
    assert html =~ ~s(phx-value-id="uuid-1")
  end

  test "renders nothing when item is nil" do
    html = render_component(&HeroCard.hero_card/1, item: nil)
    refute html =~ "data-component=\"hero\""
  end

  test "Item struct enforces required identity fields at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{
        id: 1,
        name: "Foo",
        year: "2024",
        runtime: nil,
        genre_label: nil,
        overview: nil,
        backdrop_url: nil
      })
    end
  end
end
