defmodule MediaCentaurWeb.Components.Discovery.PersonCardTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, person: 2, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
  alias MediaCentaurWeb.Components.Discovery.PersonCard

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&PersonCard.person_card/1, attrs))

  defp act(tmdb_id, flags, opts) do
    %Act{
      ref: {tmdb_id, :movie},
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"}),
      poster_url: Keyword.get(opts, :poster_url, "/media-images/#{tmdb_id}/poster.jpg"),
      activity_id: Keyword.fetch!(opts, :id),
      acted_at: ~U[2026-09-01 12:00:00Z],
      ago: "2h ago",
      episode: nil,
      flags: flags,
      grades: Keyword.get(opts, :grades, Map.new(flags, &{&1, :plain})),
      entries: Enum.map(flags, &entry(&1, Keyword.fetch!(opts, :id)))
    }
  end

  defp entry(flag, id),
    do: %Entry{
      activity_id: id,
      kind: :review,
      flag: flag,
      episode: nil,
      acted_at: ~U[2026-09-01 12:00:00Z]
    }

  defp friend, do: person("Sample Friend")

  defp acts_of(count \\ 3) do
    [
      act(7, [:love, :watched], id: "r7", grades: %{love: :gold, watched: :silver}),
      act(9, [:watched], id: "w9a"),
      act(11, [:listing], id: "l11")
    ] ++
      for index <- 4..count//1, do: act(100 + index, [:watched], id: "w#{index}")
  end

  defp you_acts, do: [act(7, [:love], id: "r7")]

  defp acts(html), do: LazyHTML.query(html, "[data-role='acts'] > button")

  test "the strip is one button per act, newest first, carrying its flags and opening the newest activity" do
    posters = acts(render(person: friend(), acts: acts_of(), width: :rail))

    assert LazyHTML.attribute(posters, "data-flags") == ["love watched", "watched", "listing"]
    assert LazyHTML.attribute(posters, "phx-value-activity") == ["r7", "w9a", "l11"]
    assert LazyHTML.attribute(posters, "phx-click") == ["open_title", "open_title", "open_title"]
    assert posters |> LazyHTML.query("[data-flag='love']") |> Enum.count() == 1
  end

  test "the glyphs sit centred above the poster in mast order, each at its grade" do
    html = render(person: friend(), acts: acts_of(), width: :rail)
    glyphs = LazyHTML.query(html, "[data-role='acts'] > button > .act-slots > .act-glyph")

    assert LazyHTML.attribute(glyphs, "data-flag") == ["love", "watched", "watched", "listing"]
    assert LazyHTML.attribute(glyphs, "data-grade") == ["gold", "silver", "plain", "plain"]
    assert LazyHTML.attribute(glyphs, "data-slot") == []
    assert Enum.empty?(LazyHTML.query(html, ".act-disc, .act-discs"))
  end

  test "the poster is width-declared for its surface; a title without one is named in the slot" do
    rail = render(person: friend(), acts: acts_of(), width: :rail)
    page = render(person: friend(), acts: acts_of(), width: :page)

    assert rail |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=240"

    assert page |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=320"

    html = render(person: friend(), acts: [act(7, [:watched], id: "w7", poster_url: nil)], width: :rail)
    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts'] img"))
    assert html |> LazyHTML.query(".act-empty") |> LazyHTML.text() |> String.trim() == "Sample Movie 7"
  end

  test "the rail shows three acts and navigates; the page shows five and opens in place" do
    rail = render(person: friend(), acts: acts_of(7), width: :rail)
    page = render(person: friend(), acts: acts_of(7), width: :page)

    assert rail |> acts() |> Enum.count() == 3
    assert page |> acts() |> Enum.count() == 5

    assert rail |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("phx-click") ==
             ["open_person"]

    assert page |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("phx-click") ==
             ["toggle_person"]

    assert rail |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("data-width") ==
             ["rail"]
  end

  test "an opened page card shows every act, one row per poster, and the foot; the You card has no foot" do
    opened = render(person: friend(), acts: acts_of(7), width: :page, opened?: true)

    assert opened |> acts() |> Enum.count() == 7
    assert opened |> LazyHTML.query("[data-role='act-row']") |> Enum.count() == 7

    assert opened
           |> LazyHTML.query("[data-role='act-row']")
           |> LazyHTML.attribute("phx-value-activity")
           |> hd() == "r7"

    assert opened |> LazyHTML.query("footer button[phx-click='remove_friend']") |> Enum.count() == 1

    assert opened
           |> LazyHTML.query("[data-component='person-card']")
           |> LazyHTML.attribute("data-opened") == [""]

    you = render(person: own_person(), acts: you_acts(), width: :page, opened?: true)
    assert Enum.empty?(LazyHTML.query(you, "footer"))

    row_text =
      you |> LazyHTML.query("[data-role='act-row']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")

    assert row_text =~ "reviewed Sample Movie 7"
  end

  test "the opened foot carries your name for the friend, ready to change" do
    html = render(person: person("Nick"), acts: [], width: :page, opened?: true)
    input = LazyHTML.query(html, "footer [data-role='name-form'] input[name='name']")

    assert LazyHTML.attribute(input, "value") == ["Nick"]

    assert html |> LazyHTML.query("footer [data-role='name-form']") |> LazyHTML.attribute("phx-submit") ==
             ["set_friend_name"]

    # The form swallows its clicks so typing in it does not press the card.
    assert html |> LazyHTML.query("footer [data-role='name-form']") |> LazyHTML.attribute("phx-click") ==
             ["[]"]

    assert html
           |> LazyHTML.query("footer [data-role='name-form'] input[name='pubkey']")
           |> LazyHTML.attribute("value") == [person("Nick").pubkey]
  end

  test "the opened foot carries the avatar switch, checked when the reader shows it" do
    shown =
      render(
        person: person("Nick", avatar_url: "/media-images/images/social/x.webp?v=1"),
        acts: [],
        width: :page,
        opened?: true
      )

    switch = LazyHTML.query(shown, "footer [data-role='avatar-switch']")
    assert LazyHTML.attribute(switch, "role") == ["switch"]
    assert LazyHTML.attribute(switch, "aria-checked") == ["true"]
    assert LazyHTML.attribute(switch, "phx-click") == ["set_show_avatar"]
    assert LazyHTML.attribute(switch, "phx-value-pubkey") == [person("Nick").pubkey]
    assert LazyHTML.attribute(switch, "phx-value-show") == ["false"]
    assert switch |> LazyHTML.query("input[type='checkbox']") |> LazyHTML.attribute("checked") == [""]

    hidden = render(person: person("Nick", show_avatar: false), acts: [], width: :page, opened?: true)
    switch = LazyHTML.query(hidden, "footer [data-role='avatar-switch']")
    assert LazyHTML.attribute(switch, "aria-checked") == ["false"]
    assert LazyHTML.attribute(switch, "phx-value-show") == ["true"]
    assert switch |> LazyHTML.query("input[type='checkbox']") |> LazyHTML.attribute("checked") == []
  end

  test "the foot's Colour row: Theirs in the published hue, the palette, the slider in a form saving on the act; the rename field is 16rem" do
    html =
      render(
        person: person("Nick", published_hue: 12, hue_override: 195),
        acts: [],
        width: :page,
        opened?: true
      )

    form = LazyHTML.query(html, "footer form[data-role='hue-form']")

    assert LazyHTML.attribute(form, "phx-change") == ["set_hue_override"]
    # The form swallows its clicks so the slider does not press the card.
    assert LazyHTML.attribute(form, "phx-click") == ["[]"]

    assert form |> LazyHTML.query("input[type='hidden'][name='pubkey']") |> LazyHTML.attribute("value") ==
             [person("Nick").pubkey]

    theirs = LazyHTML.query(form, "button[data-role='theirs']")
    assert LazyHTML.attribute(theirs, "style") == ["--hue: 12"]
    assert LazyHTML.attribute(theirs, "aria-pressed") == ["false"]
    assert LazyHTML.attribute(theirs, "phx-click") == ["set_hue_override"]
    assert LazyHTML.attribute(theirs, "phx-value-pubkey") == [person("Nick").pubkey]

    assert form |> LazyHTML.query("button[data-hue='195']") |> LazyHTML.attribute("aria-pressed") ==
             ["true"]

    assert form |> LazyHTML.query("input[type='range'][name='hue']") |> LazyHTML.attribute("value") ==
             ["195"]

    assert html
           |> LazyHTML.query("footer [data-role='name-form'] input[name='name']")
           |> LazyHTML.attribute("class")
           |> hd() =~ "basis-64"
  end

  test "the foot's placeholder is the published name the override masks, else Unnamed; never a letter of it" do
    published =
      render(person: person("Nick", published_name: "Ada"), acts: [], width: :page, opened?: true)

    input = LazyHTML.query(published, "footer [data-role='name-form'] input[name='name']")

    assert LazyHTML.attribute(input, "value") == ["Nick"]
    assert LazyHTML.attribute(input, "placeholder") == ["Ada"]

    nameless = render(person: person(nil), acts: [], width: :page, opened?: true)
    input = LazyHTML.query(nameless, "footer [data-role='name-form'] input[name='name']")

    assert LazyHTML.attribute(input, "value") == []
    assert LazyHTML.attribute(input, "placeholder") == ["Unnamed"]

    assert nameless |> LazyHTML.query("[data-role='name']") |> LazyHTML.text() |> String.trim() ==
             "Unnamed"

    assert nameless
           |> LazyHTML.query("[data-component='identity-tile']")
           |> LazyHTML.attribute("data-mark") == ["glyph"]
  end

  test "dom_id/1 is person-you for the reader and the key's first eight hex digits for a friend" do
    assert PersonCard.dom_id(own_person()) == "person-you"
    assert PersonCard.dom_id(friend()) == "person-f9308a01"

    assert render(person: friend(), acts: [], width: :rail)
           |> LazyHTML.query("#person-f9308a01")
           |> Enum.count() == 1
  end

  test "the card the address names takes focus on mount; the others do not" do
    landed = render(person: friend(), acts: [], width: :page, landed?: true)

    assert landed
           |> LazyHTML.query("[data-component='person-card']")
           |> LazyHTML.attribute("phx-mounted") != []

    plain = render(person: friend(), acts: [], width: :page)

    assert plain |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("phx-mounted") ==
             []
  end

  test "a person with no acts is a tile and a name: no strip, no ago, no note of any kind" do
    html = render(person: friend(), acts: [], width: :rail)

    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts']"))
    assert Enum.empty?(LazyHTML.query(html, "[data-role='ago']"))
    refute LazyHTML.text(html) =~ "shared"

    assert html |> LazyHTML.query("[data-role='name']") |> LazyHTML.text() |> String.trim() ==
             "Sample Friend"
  end

  test "the tile is the identity tile at the width's size; the card carries no clock" do
    assert render(person: friend(), acts: [], width: :rail)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40']")
           |> Enum.count() == 1

    assert render(person: friend(), acts: [], width: :page)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='48']")
           |> Enum.count() == 1

    assert Enum.empty?(
             LazyHTML.query(render(person: friend(), acts: acts_of(), width: :rail), "[data-role='ago']")
           )
  end
end
