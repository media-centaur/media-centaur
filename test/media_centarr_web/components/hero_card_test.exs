defmodule MediaCentarrWeb.Components.HeroCardTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.HeroCard

  test "renders title and overview" do
    item = %{
      id: 1,
      name: "The Grand Budapest Hotel",
      year: "2014",
      runtime: "1h 39m",
      genre_label: "Comedy",
      overview: "A concierge teams up with a lobby boy.",
      backdrop_url: nil,
      play_url: "/play/1",
      detail_url: "/library?selected=1"
    }

    html = render_component(&HeroCard.hero_card/1, item: item)

    assert html =~ "The Grand Budapest Hotel"
    assert html =~ "concierge"
    assert html =~ "/play/1"
  end

  test "renders nothing when item is nil" do
    html = render_component(&HeroCard.hero_card/1, item: nil)
    refute html =~ "data-component=\"hero\""
  end
end
