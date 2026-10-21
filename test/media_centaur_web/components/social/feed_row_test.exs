defmodule MediaCentaurWeb.Components.Social.FeedRowTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.FeedRow
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  @slots %ToolbarSlots{
    rung: nil,
    library_owner_id: nil,
    acquisition_state: nil,
    list: :list,
    download: :download
  }

  defp entry(overrides) do
    struct!(
      %FeedEntry{
        id: "feed-row-a",
        activity_id: "a",
        ref: {777, :movie},
        title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/media-images/x/poster.jpg",
        author: person("Sample Friend"),
        subject: :friend,
        kind: :listing,
        episode: nil,
        glyphs: [],
        text: nil,
        acted_at: ~U[2026-09-01 12:00:00Z],
        ago: "12m ago",
        slots: @slots
      },
      overrides
    )
  end

  defp render(overrides),
    do: LazyHTML.from_fragment(render_component(&FeedRow.feed_row/1, entry: entry(overrides)))

  defp root(html), do: LazyHTML.query(html, "[data-component='feed-row']")

  test "the poster is the row's one picture, width-declared and painted eagerly" do
    html = render(%{})

    assert html |> LazyHTML.query("img[data-role='poster']") |> LazyHTML.attribute("src") ==
             ["/media-images/x/poster.jpg?w=240"]

    assert html |> LazyHTML.query("img") |> LazyHTML.attribute("loading") |> Enum.uniq() == ["eager"]
    assert Enum.empty?(LazyHTML.query(html, "img[data-role='backdrop']"))
  end

  test "the row's contract holds: the id, the component name, the kind, the slots, the press" do
    root = root(render(%{kind: :review, glyphs: [{:love, :plain}], text: "Yes."}))

    assert LazyHTML.attribute(root, "id") == ["feed-row-a"]
    assert LazyHTML.attribute(root, "data-kind") == ["review"]
    assert LazyHTML.attribute(root, "phx-click") == ["open_title"]
    assert LazyHTML.attribute(root, "phx-value-activity") == ["a"]
    assert LazyHTML.attribute(root, "data-list-slot") == ["list"]
    assert LazyHTML.attribute(root, "data-download-slot") == ["download"]
  end

  test "the words: who did what with the sentiment after the verb, the title and year, the review, the time" do
    html = render(%{kind: :review, glyphs: [{:love, :plain}], text: "Saw it twice."})

    who = html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "Sample Friend reviewed"

    assert html
           |> LazyHTML.query("[data-role='who'] .social-glyph[data-flag='love'][data-grade='plain']")
           |> Enum.count() == 1

    title =
      html |> LazyHTML.query("[data-role='title']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")

    assert title =~ "Sample Movie"
    assert title =~ "2024"

    assert html |> LazyHTML.query("[data-role='text']") |> LazyHTML.text() |> String.trim() ==
             "Saw it twice."

    assert html |> LazyHTML.query("[data-role='time']") |> LazyHTML.text() |> String.trim() == "12m ago"
  end

  test "no artwork: the empty poster slot, no image" do
    html = render(%{poster_url: nil})

    assert Enum.empty?(LazyHTML.query(html, "img"))
    assert html |> LazyHTML.query("[data-role='poster-empty']") |> Enum.count() == 1
  end

  test "the author is the identity tile at 40: filled on an own row, with the second-person verb and no Ignore" do
    own = render(%{author: own_person(), subject: :you})

    assert own
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40'][data-own]")
           |> Enum.count() == 1

    assert own |> LazyHTML.query("[data-component='feed-row'][data-own]") |> Enum.count() == 1
    who = own |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "You want to watch"
    assert Enum.empty?(LazyHTML.query(own, "#feed-row-a-ignore"))

    friend = render(%{})

    assert friend
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40']:not([data-own])")
           |> Enum.count() == 1

    assert Enum.empty?(LazyHTML.query(friend, "[data-component='feed-row'][data-own]"))
    assert friend |> LazyHTML.query("#feed-row-a-ignore") |> Enum.count() == 1
  end

  test "a friend with no name at all is Unnamed under the person glyph" do
    html = render(%{author: person(nil)})

    who = html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "Unnamed wants to watch"

    assert html
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40']")
           |> LazyHTML.attribute("data-mark") == ["glyph"]
  end

  test "without an author the row draws no tile and no name: the person page's row" do
    html =
      render(%{author: nil, kind: :review, glyphs: [{:love, :gold}, {:watched, :silver}], text: "Yes."})

    assert Enum.empty?(LazyHTML.query(html, "[data-component='identity-tile']"))
    who = html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert String.trim(who) == "reviewed"
    refute who =~ "Sample Friend"

    glyphs = LazyHTML.query(html, "[data-role='who'] .social-glyph")
    assert LazyHTML.attribute(glyphs, "data-flag") == ["love", "watched"]
    assert LazyHTML.attribute(glyphs, "data-grade") == ["gold", "silver"]
    assert html |> LazyHTML.query("[data-role='text']") |> LazyHTML.text() |> String.trim() == "Yes."
  end

  test "a series row: the episode's verb and its name in the words slot, with the review's words under it" do
    episode = %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"}

    html =
      render(%{
        author: nil,
        kind: :watched,
        episode: episode,
        glyphs: [{:watched, :plain}, {:review, :plain}],
        text: "Slow."
      })

    assert html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.trim() =~
             "watched S01E07 of"

    assert html |> LazyHTML.query("[data-role='episode']") |> LazyHTML.text() |> String.trim() ==
             "Sample Episode"

    assert html |> LazyHTML.query("[data-role='text']") |> LazyHTML.text() |> String.trim() == "Slow."

    nameless = render(%{author: nil, kind: :watched, episode: %{episode | name: nil}})
    assert Enum.empty?(LazyHTML.query(nameless, "[data-role='episode']"))
  end

  test "Ignore follows the subject, not the author: none when the subject is You" do
    assert Enum.empty?(
             LazyHTML.query(render(%{author: nil, subject: :you}), "button[phx-click='ignore_title']")
           )

    assert render(%{author: nil, subject: :friend})
           |> LazyHTML.query("button[phx-click='ignore_title']")
           |> Enum.count() == 1
  end
end
