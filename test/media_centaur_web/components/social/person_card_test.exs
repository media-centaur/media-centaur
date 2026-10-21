defmodule MediaCentaurWeb.Components.Social.PersonCardTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.PersonCard
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  @slots %ToolbarSlots{
    rung: nil,
    library_owner_id: nil,
    acquisition_state: nil,
    list: :list,
    download: :download
  }

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&PersonCard.person_card/1, attrs))

  defp act(tmdb_id, flags, opts) do
    grades = Keyword.get(opts, :grades, Map.new(flags, &{&1, :plain}))

    %FeedEntry{
      id: "person-row-#{tmdb_id}",
      activity_id: Keyword.fetch!(opts, :id),
      ref: {tmdb_id, :movie},
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"}),
      poster_url: Keyword.get(opts, :poster_url, "/media-images/#{tmdb_id}/poster.jpg"),
      author: nil,
      subject: :friend,
      kind: :review,
      episode: nil,
      glyphs: Enum.map(flags, &{&1, grades[&1]}),
      text: nil,
      acted_at: ~U[2026-09-01 12:00:00Z],
      ago: "2h ago",
      slots: @slots
    }
  end

  defp friend, do: person("Sample Friend")

  defp acts_of(count \\ 3) do
    [
      act(7, [:love, :watched], id: "r7", grades: %{love: :gold, watched: :silver}),
      act(9, [:watched], id: "w9a"),
      act(11, [:listing], id: "l11")
    ] ++
      for index <- 4..count//1, do: act(100 + index, [:watched], id: "w#{index}")
  end

  defp acts(html), do: LazyHTML.query(html, "[data-role='acts'] > button")

  test "the strip is one button per act, newest first, carrying its flags and opening the newest activity" do
    posters = acts(render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :rail))

    assert LazyHTML.attribute(posters, "data-flags") == ["love watched", "watched", "listing"]
    assert LazyHTML.attribute(posters, "phx-value-activity") == ["r7", "w9a", "l11"]
    assert LazyHTML.attribute(posters, "phx-click") == ["open_title", "open_title", "open_title"]
    assert posters |> LazyHTML.query("[data-flag='love']") |> Enum.count() == 1
  end

  test "an act's sentence is the house tooltip and its accessible name, never a native title" do
    posters = acts(render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :rail))
    [tip | _] = LazyHTML.attribute(posters, "data-tip")

    assert tip =~ ~r/^Sample Friend .*Sample Movie 7$/
    assert LazyHTML.attribute(posters, "aria-label") == LazyHTML.attribute(posters, "data-tip")
    assert LazyHTML.attribute(posters, "title") == []
  end

  test "the glyphs sit centred above the poster in order, each at its grade" do
    html = render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :rail)
    glyphs = LazyHTML.query(html, "[data-role='acts'] > button > .act-slots > .social-glyph")

    assert LazyHTML.attribute(glyphs, "data-flag") == ["love", "watched", "watched", "listing"]
    assert LazyHTML.attribute(glyphs, "data-grade") == ["gold", "silver", "plain", "plain"]
    assert LazyHTML.attribute(glyphs, "data-slot") == []
    assert Enum.empty?(LazyHTML.query(html, ".act-disc, .act-discs"))
  end

  test "the poster is width-declared for its surface; a title without one is named in the slot" do
    rail = render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :rail)
    page = render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :page)

    assert rail |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=240"

    assert page |> LazyHTML.query("[data-role='acts'] img") |> LazyHTML.attribute("src") |> hd() =~
             "w=320"

    html =
      render(
        patch: "/social/friends/you",
        person: friend(),
        acts: [act(7, [:watched], id: "w7", poster_url: nil)],
        width: :rail
      )

    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts'] img"))
    assert html |> LazyHTML.query(".act-empty") |> LazyHTML.text() |> String.trim() == "Sample Movie 7"
  end

  test "the rail shows three acts and the page five; the head is a link to the person's page, the root presses nothing" do
    rail =
      render(
        patch: "/social/friends/you",
        person: friend(),
        acts: acts_of(7),
        width: :rail,
        patch: "/social/friends/npub1x"
      )

    page =
      render(
        patch: "/social/friends/you",
        person: friend(),
        acts: acts_of(7),
        width: :page,
        patch: "/social/friends/npub1x"
      )

    assert rail |> acts() |> Enum.count() == 3
    assert page |> acts() |> Enum.count() == 5

    for html <- [rail, page] do
      head = LazyHTML.query(html, "a[data-role='head']")
      assert LazyHTML.attribute(head, "href") == ["/social/friends/npub1x"]
      assert LazyHTML.attribute(head, "data-phx-link") == ["patch"]
      assert LazyHTML.attribute(head, "data-nav-item") == [""]

      assert html |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("phx-click") ==
               []

      assert html |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("role") == []
      assert Enum.empty?(LazyHTML.query(html, "footer, [data-role='act-row']"))
    end

    assert rail |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("data-width") ==
             ["rail"]
  end

  test "dom_id/1 is person-you for the reader and the key's first eight hex digits for a friend" do
    assert PersonCard.dom_id(own_person()) == "person-you"
    assert PersonCard.dom_id(friend()) == "person-f9308a01"

    assert render(patch: "/social/friends/you", person: friend(), acts: [], width: :rail)
           |> LazyHTML.query("#person-f9308a01")
           |> Enum.count() == 1
  end

  test "a person with no acts is a tile and a name: no strip, no ago, no note of any kind" do
    html = render(patch: "/social/friends/you", person: friend(), acts: [], width: :rail)

    assert Enum.empty?(LazyHTML.query(html, "[data-role='acts']"))
    assert Enum.empty?(LazyHTML.query(html, "[data-role='ago']"))
    refute LazyHTML.text(html) =~ "shared"

    assert html |> LazyHTML.query("[data-role='name']") |> LazyHTML.text() |> String.trim() ==
             "Sample Friend"
  end

  test "the tile is the identity tile at the width's size; the card carries no clock" do
    assert render(patch: "/social/friends/you", person: friend(), acts: [], width: :rail)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40']")
           |> Enum.count() == 1

    assert render(patch: "/social/friends/you", person: friend(), acts: [], width: :page)
           |> LazyHTML.query("[data-component='identity-tile'][data-size='48']")
           |> Enum.count() == 1

    assert Enum.empty?(
             LazyHTML.query(
               render(patch: "/social/friends/you", person: friend(), acts: acts_of(), width: :rail),
               "[data-role='ago']"
             )
           )
  end
end
