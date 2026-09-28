defmodule MediaCentaurWeb.Components.Discovery.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, person: 2, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Discovery.IdentityTile

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&IdentityTile.identity_tile/1, attrs))

  defp tile(html), do: LazyHTML.query(html, "[data-component='identity-tile']")

  defp letter(html), do: html |> tile() |> LazyHTML.text() |> String.trim()

  defp mark(html), do: html |> tile() |> LazyHTML.attribute("data-mark")

  test "a friend is the monogram: the reader's name for them, first letter uppercased, hidden from assistive tech" do
    html = render(person: person("cleo"), size: 40)

    assert letter(html) == "C"
    assert mark(html) == ["letter"]
    assert html |> tile() |> LazyHTML.attribute("aria-hidden") == ["true"]
    assert html |> tile() |> LazyHTML.attribute("data-own") == []
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["40"]
  end

  test "an own tile says so and takes the letter of You" do
    html = render(person: own_person(), size: 48)

    assert html |> LazyHTML.query("[data-component='identity-tile'][data-own]") |> Enum.count() == 1
    assert letter(html) == "Y"
  end

  test "an avatar replaces the letter and paints eagerly" do
    html = render(person: person("Ada", avatar_url: "/images/storybook/sample-poster.jpg"), size: 48)
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")

    assert mark(html) == ["avatar"]
    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert letter(html) == ""
  end

  test "a friend with no name at all is the person glyph, never a letter" do
    html = render(person: person(nil), size: 40)
    assert mark(html) == ["glyph"]
    assert letter(html) == ""

    assert html |> LazyHTML.query("[data-component='identity-tile'] .hero-user-solid") |> Enum.count() ==
             1
  end

  test "the published name gives the letter when there is no override" do
    assert letter(render(person: person(nil, published_name: "ada"), size: 40)) == "A"
  end

  test "the tile carries the person's hue as --hue, the override first; none sets no style" do
    none = render(person: person("cleo"), size: 40)
    assert none |> tile() |> LazyHTML.attribute("style") == []
    assert none |> tile() |> LazyHTML.attribute("data-hue") == []
    assert none |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-friend"

    published = render(person: %{person("cleo") | published_hue: 195}, size: 40)
    assert published |> tile() |> LazyHTML.attribute("style") == ["--hue: 195"]
    assert published |> tile() |> LazyHTML.attribute("data-hue") == ["195"]

    overridden = render(person: %{person("cleo") | published_hue: 195, hue_override: 12}, size: 40)
    assert overridden |> tile() |> LazyHTML.attribute("style") == ["--hue: 12"]

    own = render(person: %{own_person() | published_hue: 290}, size: 48)
    assert own |> tile() |> LazyHTML.attribute("style") == ["--hue: 290"]
    assert own |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-own"

    avatar = render(person: person("Ada", avatar_url: "/x.webp"), size: 48)
    assert avatar |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-avatar"
  end

  test "the size is one of the two the surfaces render" do
    assert_raise ArgumentError, ~r/40 or 48/, fn -> render(person: person("Cleo"), size: 56) end
  end
end
