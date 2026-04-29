defmodule MediaCentarrWeb.Components.HeroCardTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.HeroCard
  alias MediaCentarrWeb.Components.HeroCard.Item

  test "renders title and overview" do
    item = %Item{
      id: 1,
      name: "Sample Movie",
      year: "2014",
      runtime: "1h 39m",
      genre_label: "Comedy",
      overview: "A concierge teams up with a lobby boy.",
      backdrop_url: nil,
      logo_url: nil,
      play_url: "/play/1",
      detail_url: "/library?selected=1"
    }

    html = render_component(&HeroCard.hero_card/1, item: item)

    assert html =~ "Sample Movie"
    assert html =~ "concierge"
    assert html =~ "/play/1"
  end

  test "renders nothing when item is nil" do
    html = render_component(&HeroCard.hero_card/1, item: nil)
    refute html =~ "data-component=\"hero\""
  end

  test "Item struct enforces required URL fields at construction time" do
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
