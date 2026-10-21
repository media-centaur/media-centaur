defmodule MediaCentaurWeb.Components.Social.ReaderViewTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, person: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Social.ReaderView

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&ReaderView.reader_view/1, attrs))

  defp text(html, selector),
    do:
      html
      |> LazyHTML.query(selector)
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

  test "the card is headed with the reader's name for them and says only the reader sees it" do
    html = render(person: person("Nick"))

    assert text(html, "[data-component='reader-view'] h3") == "Your view of Nick"
    assert text(html, "[data-component='reader-view']") =~ "Only you see these"
  end

  test "Name: the override in the field, the masked name as the placeholder, Rename submits set_friend_name with the key" do
    html = render(person: person("Nick", published_name: "Ada"))
    form = LazyHTML.query(html, "[data-role='name-form']")

    assert LazyHTML.attribute(form, "phx-submit") == ["set_friend_name"]

    assert form |> LazyHTML.query("input[name='pubkey']") |> LazyHTML.attribute("value") ==
             [person("Nick").pubkey]

    assert form |> LazyHTML.query("input[name='name']") |> LazyHTML.attribute("value") == ["Nick"]
    assert form |> LazyHTML.query("input[name='name']") |> LazyHTML.attribute("placeholder") == ["Ada"]
    assert text(form, "button[type='submit']") == "Rename"

    nameless = render(person: person(nil))

    assert nameless
           |> LazyHTML.query("[data-role='name-form'] input[name='name']")
           |> LazyHTML.attribute("value") == []

    assert nameless
           |> LazyHTML.query("[data-role='name-form'] input[name='name']")
           |> LazyHTML.attribute("placeholder") == ["Unnamed"]
  end

  test "Show their picture is a switch carrying the key and the value to set" do
    shown =
      LazyHTML.query(render(person: person("Nick")), "[role='switch'][phx-click='set_show_avatar']")

    assert LazyHTML.attribute(shown, "aria-checked") == ["true"]
    assert LazyHTML.attribute(shown, "phx-value-pubkey") == [person("Nick").pubkey]
    assert LazyHTML.attribute(shown, "phx-value-show") == ["false"]

    hidden =
      LazyHTML.query(
        render(person: person("Nick", show_avatar: false)),
        "[role='switch'][phx-click='set_show_avatar']"
      )

    assert LazyHTML.attribute(hidden, "aria-checked") == ["false"]
    assert LazyHTML.attribute(hidden, "phx-value-show") == ["true"]
  end

  test "Colour: Theirs in the published hue, the chosen swatch pressed, the slider in a form saving on the act" do
    html = render(person: person("Nick", published_hue: 12, hue_override: 195))
    form = LazyHTML.query(html, "form[data-role='hue-form']")

    assert LazyHTML.attribute(form, "phx-change") == ["set_hue_override"]

    assert form |> LazyHTML.query("input[type='hidden'][name='pubkey']") |> LazyHTML.attribute("value") ==
             [person("Nick").pubkey]

    assert form |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("style") ==
             ["--hue: 12"]

    assert form |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("aria-pressed") ==
             ["false"]

    assert form |> LazyHTML.query("button[data-hue='195']") |> LazyHTML.attribute("aria-pressed") ==
             ["true"]

    assert form |> LazyHTML.query("input[type='range'][name='hue']") |> LazyHTML.attribute("value") ==
             ["195"]
  end

  test "Hide is a switch: off for a shown person, on for a hidden one, carrying the value to set" do
    shown = LazyHTML.query(render(person: person("Nick")), "[role='switch'][phx-click='set_hidden']")
    assert LazyHTML.attribute(shown, "aria-checked") == ["false"]
    assert LazyHTML.attribute(shown, "phx-value-hide") == ["true"]

    hidden =
      LazyHTML.query(
        render(person: %{person("Nick") | hidden: true}),
        "[role='switch'][phx-click='set_hidden']"
      )

    assert LazyHTML.attribute(hidden, "aria-checked") == ["true"]
    assert LazyHTML.attribute(hidden, "phx-value-hide") == ["false"]
  end

  test "the foot: the key and how the reader follows them; Remove friend for a friend, never for a member" do
    friend = render(person: person("Nick"))
    assert text(friend, "[data-role='foot']") =~ "npub1lyy9…8z4h"
    assert text(friend, "[data-role='foot']") =~ "added Aug 30"

    assert friend
           |> LazyHTML.query("button[phx-click='remove_friend']")
           |> LazyHTML.attribute("phx-value-pubkey") == [person("Nick").pubkey]

    member =
      render(
        person: %{
          person("Sample Member")
          | friend?: false,
            added_on: nil,
            member_of: ["wss://group.example/"]
        }
      )

    assert text(member, "[data-role='foot']") =~ "on group.example"
    refute text(member, "[data-role='foot']") =~ "added"
    assert Enum.empty?(LazyHTML.query(member, "button[phx-click='remove_friend']"))
  end
end
