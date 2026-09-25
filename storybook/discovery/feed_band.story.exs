defmodule MediaCentaurWeb.Storybook.Discovery.FeedBand do
  @moduledoc """
  One Feed band (UIDR-046): one author's action on one title as a
  1236×224 unit on ink — the identity tile, the poster, then who did
  what (the sentiment glyph after the verb when the review gives one),
  the title and year, the review's words at two lines, the time at the
  text zone's edge, and the title's still in a right-hand image box
  under the scrim's 360px dissolve. The toolbar seat is empty at rest
  and shows on hover; the variations cover every state the two resolved
  slots can hold, both authors, the artwork states, the adjacent pair's
  offset crop, and the hover seat pinned by the template. Every size is
  the couch floor's: nothing read is under 18px.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.FeedEntry

  def function, do: &MediaCentaurWeb.Components.Discovery.FeedBand.feed_band/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="feed-column w-[1236px]">
      <.psb-variation/>
    </div>
    """
  end

  @hover_pinned """
  <div class="feed-column feed-hover-pin w-[1236px]">
    <.psb-variation/>
  </div>
  """

  @review_text "Saw it twice. The last twenty minutes are the whole film, and the score does most of the work."

  defp entry(id, overrides) do
    tmdb_id = Map.get(overrides, :tmdb_id, 777)

    struct!(
      %FeedEntry{
        id: "feed-row-#{id}",
        activity_id: id,
        ref: {tmdb_id, :movie},
        title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/images/storybook/sample-poster.jpg",
        backdrop_url: "/images/storybook/sample-backdrop.jpg",
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
        download_slot: :download,
        offset_crop?: false
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :listing,
        description:
          "A friend wants to watch it: two lines, the time at the text zone's edge, the still in its box.",
        attributes: %{entry: entry("listing", %{ago: "just now"})}
      },
      %Variation{
        id: :review_like_with_text,
        description:
          "Like is the thumbs up after the verb; the review is the third line, two lines at most.",
        attributes: %{
          entry: entry("like", %{kind: :review, sentiment: :like, text: @review_text, ago: "1d ago"})
        }
      },
      %Variation{
        id: :review_love,
        description: "Love is the rose heart after the verb — the only colour on a friend's band.",
        attributes: %{
          entry: entry("love", %{kind: :review, sentiment: :love, text: @review_text, ago: "2h ago"})
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
        id: :own_listing,
        description:
          "Your own listing: the filled own tile, \"You want to watch\", Listed filled, no Ignore.",
        attributes: %{
          entry:
            entry("own-listing", %{
              author: "You",
              own?: true,
              rung: :list,
              list_slot: :listed,
              ago: "3d ago"
            })
        }
      },
      %Variation{
        id: :own_review,
        description: "Your own review: the same band; the seat holds List and Download only.",
        attributes: %{
          entry:
            entry("own-review", %{
              author: "You",
              own?: true,
              kind: :review,
              sentiment: :love,
              text: @review_text,
              ago: "1h ago"
            })
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
        id: :no_artwork,
        description:
          "No artwork on any tier: the band on the inset tone with a short scrim, the poster slot empty.",
        attributes: %{entry: entry("bare", %{poster_url: nil, backdrop_url: nil, ago: "3w ago"})}
      },
      %Variation{
        id: :no_backdrop,
        description: "A poster and no still: the words on the bare ground, the poster in place.",
        attributes: %{entry: entry("no-still", %{backdrop_url: nil, ago: "2w ago"})}
      },
      %VariationGroup{
        id: :adjacent_pair,
        description:
          "Two adjacent bands of one title: the same still at 30%, then at 38% — one frame never repeats exactly.",
        template: """
        <div class="feed-column w-[1236px]">
          <.psb-variation-group/>
        </div>
        """,
        variations: [
          %Variation{
            id: :first,
            attributes: %{entry: entry("pair-a", %{author: "Cleo", ago: "4m ago"})}
          },
          %Variation{
            id: :second,
            attributes: %{
              entry:
                entry("pair-b", %{
                  author: "Nick",
                  kind: :review,
                  sentiment: :like,
                  ago: "9m ago",
                  offset_crop?: true
                })
            }
          }
        ]
      },
      %Variation{
        id: :hovered,
        description:
          "Under the cursor: the seat shown — List · Download · Ignore — the scrim × .8, the ground lifted; the height unchanged.",
        attributes: %{entry: entry("hovered", %{kind: :review, sentiment: :like, text: @review_text})},
        template: @hover_pinned
      },
      %Variation{
        id: :own_hovered,
        description: "An own band under the cursor: List · Download, no Ignore.",
        attributes: %{
          entry: entry("own-hovered", %{author: "You", own?: true, rung: :list, list_slot: :listed})
        },
        template: @hover_pinned
      }
    ]
  end
end
