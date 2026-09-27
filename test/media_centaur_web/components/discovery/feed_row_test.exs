defmodule MediaCentaurWeb.Components.Discovery.FeedRowTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Discovery.FeedRow

  defp entry(overrides) do
    struct!(
      %FeedEntry{
        id: "feed-row-a",
        activity_id: "a",
        ref: {777, :movie},
        title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/media-images/x/poster.jpg",
        author: person("Sample Friend"),
        kind: :listing,
        sentiment: nil,
        text: nil,
        acted_at: ~U[2026-09-01 12:00:00Z],
        ago: "12m ago",
        rung: nil,
        library_owner_id: nil,
        acquisition_state: nil,
        list_slot: :list,
        download_slot: :download
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
    root = root(render(%{kind: :review, sentiment: :love, text: "Yes."}))

    assert LazyHTML.attribute(root, "id") == ["feed-row-a"]
    assert LazyHTML.attribute(root, "data-kind") == ["review"]
    assert LazyHTML.attribute(root, "phx-click") == ["open_title"]
    assert LazyHTML.attribute(root, "phx-value-activity") == ["a"]
    assert LazyHTML.attribute(root, "data-list-slot") == ["list"]
    assert LazyHTML.attribute(root, "data-download-slot") == ["download"]
  end

  test "the words: who did what with the sentiment after the verb, the title and year, the review, the time" do
    html = render(%{kind: :review, sentiment: :love, text: "Saw it twice."})

    who = html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "Sample Friend reviewed"
    assert html |> LazyHTML.query("[data-role='who'] [data-sentiment='love']") |> Enum.count() == 1

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
    own = render(%{author: own_person()})

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

    assert friend |> LazyHTML.query("#feed-row-a-ignore") |> Enum.count() == 1
  end
end
