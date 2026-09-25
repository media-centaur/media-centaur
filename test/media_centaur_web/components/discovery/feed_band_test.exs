defmodule MediaCentaurWeb.Components.Discovery.FeedBandTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.FeedBand
  alias MediaCentaurWeb.Components.Discovery.FeedEntry

  defp entry(overrides) do
    struct!(
      %FeedEntry{
        id: "feed-row-a",
        activity_id: "a",
        ref: {777, :movie},
        title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/media-images/x/poster.jpg",
        backdrop_url: "/media-images/x/backdrop.jpg",
        author: "Sample Friend",
        own?: false,
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
    do: LazyHTML.from_fragment(render_component(&FeedBand.feed_band/1, entry: entry(overrides)))

  defp root(html), do: LazyHTML.query(html, "[data-component='feed-row']")

  test "the still and the poster are width-declared for the band's boxes and paint eagerly" do
    html = render(%{})

    assert html |> LazyHTML.query("img[data-role='backdrop']") |> LazyHTML.attribute("src") ==
             ["/media-images/x/backdrop.jpg?w=1280"]

    assert html |> LazyHTML.query("img[data-role='poster']") |> LazyHTML.attribute("src") ==
             ["/media-images/x/poster.jpg?w=240"]

    assert html |> LazyHTML.query("img") |> LazyHTML.attribute("loading") |> Enum.uniq() == ["eager"]
  end

  test "the row's contract holds: the id, the component name, the kind, the slots, the press" do
    root = root(render(%{kind: :review, sentiment: :love, text: "Yes."}))

    assert LazyHTML.attribute(root, "id") == ["feed-row-a"]
    assert LazyHTML.attribute(root, "data-kind") == ["review"]
    assert LazyHTML.attribute(root, "phx-click") == ["open_title"]
    assert LazyHTML.attribute(root, "phx-value-activity") == ["a"]
    assert LazyHTML.attribute(root, "data-list-slot") == ["list"]
    assert LazyHTML.attribute(root, "data-download-slot") == ["download"]
    assert LazyHTML.attribute(root, "data-offset-crop") == []
  end

  test "the second of an adjacent pair says so" do
    assert render(%{offset_crop?: true})
           |> LazyHTML.query("[data-component='feed-row'][data-offset-crop]")
           |> Enum.count() == 1
  end

  test "no artwork: the empty poster slot, no still, the bare ground" do
    html = render(%{poster_url: nil, backdrop_url: nil})

    assert Enum.empty?(LazyHTML.query(html, "img"))
    assert html |> LazyHTML.query("[data-role='poster-empty']") |> Enum.count() == 1
    assert html |> LazyHTML.query("[data-component='feed-row'].feed-band-bare") |> Enum.count() == 1
  end

  test "the author is the identity tile at 56 — filled on an own band, with the second-person verb and no Ignore" do
    own = render(%{author: "You", own?: true})

    assert own
           |> LazyHTML.query("[data-component='identity-tile'][data-size='56'][data-own]")
           |> Enum.count() == 1

    who = own |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "You want to watch"
    assert Enum.empty?(LazyHTML.query(own, "#feed-row-a-ignore"))

    friend = render(%{})

    assert friend
           |> LazyHTML.query("[data-component='identity-tile'][data-size='56']:not([data-own])")
           |> Enum.count() == 1

    assert friend |> LazyHTML.query("#feed-row-a-ignore") |> Enum.count() == 1
  end
end
