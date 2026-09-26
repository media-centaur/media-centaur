defmodule MediaCentaurWeb.Components.Discovery.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Discovery.IdentityTile

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&IdentityTile.identity_tile/1, attrs))

  defp tile(html), do: LazyHTML.query(html, "[data-component='identity-tile']")

  defp letter(html), do: html |> tile() |> LazyHTML.text() |> String.trim()

  test "a monogram carries the name's first letter uppercased, hidden from assistive tech" do
    html = render(name: "cleo", size: 40)

    assert letter(html) == "C"
    assert html |> tile() |> LazyHTML.attribute("aria-hidden") == ["true"]
    assert html |> tile() |> LazyHTML.attribute("data-own") == []
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["40"]
  end

  test "an own tile says so; the letter stays" do
    html = render(name: "You", own?: true, size: 48)

    assert html |> LazyHTML.query("[data-component='identity-tile'][data-own]") |> Enum.count() == 1
    assert letter(html) == "Y"
  end

  test "a photo replaces the letter and paints eagerly" do
    html = render(name: "Ada", size: 48, photo_url: "/images/storybook/sample-poster.jpg")
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")

    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert letter(html) == ""
  end

  test "the size is one of the two the surfaces render" do
    assert_raise ArgumentError, ~r/40 or 48/, fn -> render(name: "Cleo", size: 56) end
  end
end
