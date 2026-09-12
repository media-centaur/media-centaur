defmodule MediaCentaurWeb.Storybook.Discovery.FeedEntryCard do
  @moduledoc """
  One Feed entry (UIDR-038): poster left, then who did what and when —
  the sentiment glyph after the verb when the review gives one — the
  title, and the review's text when it has some. The toolbar seat is
  empty at rest and shows on hover; the variations cover every state its
  two resolved slots can hold. A listing and a review are the same card.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.FeedEntry

  def function, do: &MediaCentaurWeb.Components.Discovery.FeedEntryCard.feed_entry_card/1
  def render_source, do: :function
  def layout, do: :one_column

  defp entry(id, overrides) do
    tmdb_id = Map.get(overrides, :tmdb_id, 777)

    struct!(
      %FeedEntry{
        id: "feed-entry-#{id}",
        activity_id: id,
        ref: {tmdb_id, :movie},
        title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/images/sample-nosferatu-poster.jpg",
        nickname: "Sample Friend",
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

  def variations do
    [
      %Variation{
        id: :listing,
        description: "A friend wants to watch it: two lines, centred against the poster.",
        attributes: %{entry: entry("listing", %{})}
      },
      %Variation{
        id: :review_like_with_text,
        description: "Like is the thumbs up after the verb; the text is the third line.",
        attributes: %{
          entry:
            entry("like", %{
              kind: :review,
              sentiment: :like,
              text: "Slow start, give it three episodes.",
              ago: "1d ago"
            })
        }
      },
      %Variation{
        id: :review_love,
        description: "Love is the rose heart after the verb — the only colour on the card.",
        attributes: %{
          entry:
            entry("love", %{
              kind: :review,
              sentiment: :love,
              text: "Saw it twice. The last twenty minutes are the whole film.",
              ago: "2h ago"
            })
        }
      },
      %Variation{
        id: :review_dislike,
        description: "Dislike is the thumbs down after the verb.",
        attributes: %{
          entry:
            entry("dislike", %{
              kind: :review,
              sentiment: :dislike,
              text: "Gave up halfway. Nothing happens, slowly.",
              ago: "3h ago"
            })
        }
      },
      %Variation{
        id: :review_text_only,
        description:
          "A review with words and no verdict: no glyph, the text still leads the third line.",
        attributes: %{
          entry:
            entry("text-only", %{
              kind: :review,
              sentiment: nil,
              text: "Not sure yet. Ask me after the finale.",
              ago: "5h ago"
            })
        }
      },
      %Variation{
        id: :review_bare,
        description: "A review with neither: the name, the verb and the title, nothing else.",
        attributes: %{
          entry: entry("bare-review", %{kind: :review, sentiment: nil, text: nil, ago: "6h ago"})
        }
      },
      %Variation{
        id: :listed_title,
        description: "The title is on your list: the bookmark fills and reads Listed.",
        attributes: %{entry: entry("listed", %{rung: :list, list_slot: :listed})}
      },
      %Variation{
        id: :following_title,
        description: "At Follow or above the List slot is plain state, not a toggle.",
        attributes: %{entry: entry("following", %{rung: :follow, list_slot: :following})}
      },
      %Variation{
        id: :in_library,
        description: "An owned title: the Download slot reads In library.",
        attributes: %{
          entry: entry("owned", %{library_owner_id: "owner", download_slot: {:state, "In library"}})
        }
      },
      %Variation{
        id: :downloading,
        description: "A plan in flight: Downloading with the hairline.",
        attributes: %{
          entry:
            entry("downloading", %{
              acquisition_state: :downloading,
              download_slot: {:state, "Downloading"}
            })
        }
      },
      %Variation{
        id: :no_poster,
        description: "No artwork yet: the poster slot is a quiet tile.",
        attributes: %{entry: entry("bare", %{poster_url: nil, ago: "3w ago"})}
      }
    ]
  end
end
