defmodule MediaCentaurWeb.Components.Discovery.PersonCardTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Act
  alias MediaCentaurWeb.Components.Discovery.Person.Entry
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
      gold: Keyword.get(opts, :gold, []),
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

  defp friend_with_acts(count \\ 3) do
    acts =
      [
        act(7, [:love, :watched], id: "r7", gold: [:love]),
        act(9, [:watched], id: "w9a"),
        act(11, [:listing], id: "l11")
      ] ++
        for index <- 4..count//1, do: act(100 + index, [:watched], id: "w#{index}")

    %Person{
      id: "person-f9308a01",
      name: "Sample Friend",
      own?: false,
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30],
      acts: acts
    }
  end

  defp you_with_acts,
    do: %Person{id: "person-you", name: "You", own?: true, acts: [act(7, [:love], id: "r7")]}

  defp quiet_friend, do: %{friend_with_acts() | acts: []}

  defp acts(html), do: LazyHTML.query(html, "[data-role='acts'] > button")

  test "the strip is one button per act, newest first, carrying its flags and opening the newest activity" do
    posters = acts(render(person: friend_with_acts(), width: :rail))

    assert LazyHTML.attribute(posters, "data-flags") == ["love watched", "watched", "listing"]
    assert LazyHTML.attribute(posters, "phx-value-activity") == ["r7", "w9a", "l11"]
    assert LazyHTML.attribute(posters, "phx-click") == ["open_title", "open_title", "open_title"]
    assert posters |> LazyHTML.query("[data-flag='love']") |> Enum.count() == 1
  end

  test "each glyph sits in its fixed slot above the poster; a flag at the grade is gold, the rest matte" do
    html = render(person: friend_with_acts(), width: :rail)
    glyphs = LazyHTML.query(html, "[data-role='acts'] > button > .act-slots > .act-glyph")

    assert LazyHTML.attribute(glyphs, "data-slot") == ["1", "2", "2", "3"]
    assert html |> LazyHTML.query(".act-glyph-gold") |> LazyHTML.attribute("data-flag") == ["love"]
    assert Enum.empty?(LazyHTML.query(html, ".act-disc, .act-discs"))
  end

  test "the poster is width-declared for its surface; a title without one is named in the slot" do
    rail = render(person: friend_with_acts(), width: :rail)
    page = render(person: friend_with_acts(), width: :page)

    assert rail |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=240"

    assert page |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=320"

    bare = %{friend_with_acts() | acts: [act(7, [:watched], id: "w7", poster_url: nil)]}
    html = render(person: bare, width: :rail)
    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts'] img"))
    assert html |> LazyHTML.query(".act-empty") |> LazyHTML.text() |> String.trim() == "Sample Movie 7"
  end

  test "the rail shows three acts and navigates; the page shows five and opens in place" do
    rail = render(person: friend_with_acts(7), width: :rail)
    page = render(person: friend_with_acts(7), width: :page)

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
    opened = render(person: friend_with_acts(7), width: :page, opened?: true)

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

    you = render(person: you_with_acts(), width: :page, opened?: true)
    assert Enum.empty?(LazyHTML.query(you, "footer"))

    row_text =
      you |> LazyHTML.query("[data-role='act-row']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")

    assert row_text =~ "reviewed Sample Movie 7"
  end

  test "a person with no acts is a tile and a name: no strip, no ago, no note of any kind" do
    html = render(person: quiet_friend(), width: :rail)

    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts']"))
    assert Enum.empty?(LazyHTML.query(html, "[data-role='ago']"))
    refute LazyHTML.text(html) =~ "shared"

    assert html |> LazyHTML.query("[data-role='name']") |> LazyHTML.text() |> String.trim() ==
             "Sample Friend"
  end

  test "the tile is the identity tile at the width's size; the ago is the newest act's" do
    assert render(person: quiet_friend(), width: :rail)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='48']")
           |> Enum.count() == 1

    assert render(person: quiet_friend(), width: :page)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='64']")
           |> Enum.count() == 1

    assert render(person: friend_with_acts(), width: :rail)
           |> LazyHTML.query("[data-role='ago']")
           |> LazyHTML.text()
           |> String.trim() == "2h ago"
  end
end
