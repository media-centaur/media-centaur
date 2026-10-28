defmodule MediaCentaurWeb.Components.Social.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, person: 2, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Social.IdentityTile

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&IdentityTile.identity_tile/1, attrs))
  defp tile(html), do: LazyHTML.query(html, "[data-component='identity-tile']")
  defp letter(html), do: html |> tile() |> LazyHTML.text() |> String.trim()
  defp mark(html), do: html |> tile() |> LazyHTML.attribute("data-mark")
  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()

  test "a name is its monogram, hidden from assistive tech, tinted for a friend" do
    html = render(name: "cleo", size: 40)
    assert letter(html) == "C"
    assert mark(html) == ["letter"]
    assert html |> tile() |> LazyHTML.attribute("aria-hidden") == ["true"]
    assert html |> tile() |> LazyHTML.attribute("data-own") == []
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["40"]
    assert count(html, "[data-component='identity-tile'].identity-tile-friend") == 1
  end

  test "own? fills the tile" do
    html = render(name: "You", own?: true, size: 48)
    assert count(html, "[data-component='identity-tile'][data-own]") == 1
    assert count(html, "[data-component='identity-tile'].identity-tile-own") == 1
    assert letter(html) == "Y"
  end

  test "a picture replaces the letter and paints eagerly" do
    html = render(name: "Ada", picture_url: "/images/storybook/sample-poster.jpg", size: 48)
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")
    assert mark(html) == ["avatar"]
    assert count(html, "[data-component='identity-tile'].identity-tile-avatar") == 1
    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert letter(html) == ""
  end

  test "no name at all is the person glyph, never a letter" do
    html = render(size: 40)
    assert mark(html) == ["glyph"]
    assert letter(html) == ""
    assert count(html, "[data-component='identity-tile'] .hero-user-solid") == 1
  end

  test "the hue rides as --hue; none sets no style" do
    none = render(name: "cleo", size: 40)
    assert none |> tile() |> LazyHTML.attribute("style") == []
    assert none |> tile() |> LazyHTML.attribute("data-hue") == []
    some = render(name: "cleo", hue: 195, size: 40)
    assert some |> tile() |> LazyHTML.attribute("style") == ["--hue: 195"]
    assert some |> tile() |> LazyHTML.attribute("data-hue") == ["195"]
  end

  test "an empty name is the person glyph too" do
    assert mark(render(name: "", size: 40)) == ["glyph"]
  end

  test "128 is accepted, its glyph sized to match" do
    html = render(size: 128)
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["128"]
    assert count(html, "[data-component='identity-tile'] .hero-user-solid.size-16") == 1
  end

  test "crop_previews/1 draws the two preview canvases, 48 then 40" do
    html = LazyHTML.from_fragment(render_component(&IdentityTile.crop_previews/1, %{}))
    widths = html |> LazyHTML.query("canvas[data-role='preview']") |> LazyHTML.attribute("width")
    assert widths == ["48", "40"]
  end

  test "a size no surface renders raises" do
    assert_raise ArgumentError, ~r/48 or 128/, fn -> render(name: "Cleo", size: 56) end
  end

  describe "person_attrs/1 — a Social.Person as the tile's facts" do
    test "a friend: the name the reader sees, the avatar, the resolved hue, tinted" do
      attrs =
        IdentityTile.person_attrs(
          person("cleo", avatar_url: "/a.webp", published_hue: 12, hue_override: 195)
        )

      assert attrs == [name: "cleo", picture_url: "/a.webp", hue: 195, own?: false]
    end

    test "a friend's published name and published hue stand in when the reader set none" do
      attrs = IdentityTile.person_attrs(person(nil, published_name: "ada", published_hue: 195))
      assert attrs[:name] == "ada"
      assert attrs[:hue] == 195
    end

    test "a friend with no name at all passes nil, so the glyph is drawn" do
      assert IdentityTile.person_attrs(person(nil))[:name] == nil
    end

    test "the reader's own takes You and is filled, in its published hue" do
      attrs = IdentityTile.person_attrs(%{own_person() | published_hue: 290})
      assert attrs[:name] == "You"
      assert attrs[:own?] == true
      assert attrs[:hue] == 290
    end
  end
end
