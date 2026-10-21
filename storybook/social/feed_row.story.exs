defmodule MediaCentaurWeb.Storybook.Social.FeedRow do
  @moduledoc """
  One row on the Feed and on the person page (UIDR-046, UIDR-054): one
  author's action on one title, or one person's acts on one title, as
  the app draws a list row — the identity tile at 40 when the row names
  its author, the poster at 80×120, then the verb with every glyph at
  its grade, the title and year, the episode's name on a series, the
  review's words in full, and the time at the row's right edge. No
  still: the poster is the row's one picture. The toolbar seat is empty
  at rest and shows on hover; the variations cover every state the two
  resolved slots can hold, both authors, the artwork states, and the
  hover seat pinned by the template. The rows sit in a column with a
  hairline between them, as the page draws them.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  def function, do: &MediaCentaurWeb.Components.Social.FeedRow.feed_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-[776px] divide-y divide-base-content/10">
      <.psb-variation/>
    </div>
    """
  end

  @hover_pinned """
  <div class="feed-hover-pin w-[776px] divide-y divide-base-content/10">
    <.psb-variation/>
  </div>
  """

  @review_text "Saw it twice. The last twenty minutes are the whole film, and the score does most of the work."

  @slots %ToolbarSlots{
    rung: nil,
    library_owner_id: nil,
    acquisition_state: nil,
    list: :list,
    download: :download
  }

  defp entry(id, overrides) do
    tmdb_id = Map.get(overrides, :tmdb_id, 777)

    struct!(
      %FeedEntry{
        id: "feed-row-#{id}",
        activity_id: id,
        ref: {tmdb_id, :movie},
        title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/images/storybook/sample-poster.jpg",
        author: friend(),
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

  defp friend,
    do: %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }

  defp you,
    do: %Person{pubkey: "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", own?: true}

  def variations do
    [
      %Variation{
        id: :listing,
        description: "A friend wants to watch it: two lines, the time at the row's edge.",
        attributes: %{entry: entry("listing", %{ago: "just now"})}
      },
      %Variation{
        id: :review_like_with_text,
        description: "Like is the thumbs up after the verb; the review is the third line.",
        attributes: %{
          entry:
            entry("like", %{kind: :review, glyphs: [{:like, :plain}], text: @review_text, ago: "2h ago"})
        }
      },
      %Variation{
        id: :review_long,
        description:
          "A review near the protocol's 500-character cap: shown in full, and only this row grows.",
        attributes: %{
          entry:
            entry("long", %{
              kind: :review,
              glyphs: [{:love, :plain}],
              text:
                "Watched it again after finishing the book. The film keeps the mood and drops almost every plot point, which works better than it should. The lighthouse sequence is still the strangest thing I have seen on a screen, and the score carries the last act. Slow in the middle, and two of the characters never get a scene of their own. I would still put it near the top of the year, and I will watch it a third time.",
              ago: "3h ago"
            })
        }
      },
      %Variation{
        id: :review_love,
        description: "Love: the heart in rose, the one warm hue outside the health palette.",
        attributes: %{
          entry: entry("love", %{kind: :review, glyphs: [{:love, :plain}], text: "Yes.", ago: "1d ago"})
        }
      },
      %Variation{
        id: :review_dislike,
        description: "Dislike: the thumbs down.",
        attributes: %{
          entry:
            entry("dislike", %{
              kind: :review,
              glyphs: [{:dislike, :plain}],
              text: "Not for me. The score does all the work the script should.",
              ago: "3d ago"
            })
        }
      },
      %Variation{
        id: :review_text_only,
        description: "A review with words and no sentiment (UIDR-040): the verb alone, then the words.",
        attributes: %{
          entry:
            entry("text-only", %{
              kind: :review,
              glyphs: [],
              text: "Slow start, give it three episodes."
            })
        }
      },
      %Variation{
        id: :review_bare,
        description: "A review with neither words nor sentiment: two lines, like a listing.",
        attributes: %{entry: entry("bare", %{kind: :review, glyphs: [], text: nil})}
      },
      %Variation{
        id: :unnamed_listing,
        description:
          "A friend with no name at all: the person glyph in the tile, Unnamed wants to watch it.",
        attributes: %{
          entry: entry("unnamed", %{author: %{friend() | name_override: nil}, ago: "5m ago"})
        }
      },
      %Variation{
        id: :own_listing,
        description: "The reader's own listing: the filled own tile, the second-person verb, no Ignore.",
        attributes: %{entry: entry("own", %{author: you(), subject: :you, ago: "1h ago"})}
      },
      %Variation{
        id: :own_review,
        description: "The reader's own review.",
        attributes: %{
          entry:
            entry("own-review", %{
              author: you(),
              subject: :you,
              kind: :review,
              glyphs: [{:love, :plain}],
              text: @review_text,
              ago: "1h ago"
            })
        }
      },
      %Variation{
        id: :listed_title,
        description: "The title is on the reader's list: Listed, filled, in the seat (hover to see it).",
        attributes: %{entry: entry("listed", %{slots: %{@slots | rung: :list, list: :listed}})}
      },
      %Variation{
        id: :following_title,
        description: "The title is tracked: Tracking as plain state in the List slot.",
        attributes: %{entry: entry("following", %{slots: %{@slots | rung: :follow, list: :following}})}
      },
      %Variation{
        id: :in_library,
        description: "In library as plain state in the Download slot.",
        attributes: %{
          entry:
            entry("owned", %{
              slots: %{@slots | library_owner_id: "owner", download: {:state, "In library"}}
            })
        }
      },
      %Variation{
        id: :downloading,
        description: "Downloading with the 3px hairline under the word.",
        attributes: %{
          entry:
            entry("downloading", %{
              slots: %{@slots | acquisition_state: :downloading, download: {:state, "Downloading"}}
            })
        }
      },
      %Variation{
        id: :no_artwork,
        description: "A title without a poster: the empty slot, the words unchanged.",
        attributes: %{entry: entry("no-art", %{poster_url: nil})}
      },
      %Variation{
        id: :hovered,
        description: "A friend's row hovered: List · Download · Ignore in the seat.",
        attributes: %{
          entry:
            entry("hovered", %{
              kind: :review,
              glyphs: [{:like, :plain}],
              text: @review_text,
              ago: "2h ago"
            })
        },
        template: @hover_pinned
      },
      %Variation{
        id: :own_hovered,
        description: "An own row hovered: Listed and In library, no Ignore, no Delete.",
        attributes: %{
          entry:
            entry("own-hovered", %{
              author: you(),
              subject: :you,
              kind: :review,
              glyphs: [{:love, :plain}],
              text: "Saw it twice.",
              slots: %{
                @slots
                | rung: :list,
                  list: :listed,
                  library_owner_id: "owner",
                  download: {:state, "In library"}
              }
            })
        },
        template: @hover_pinned
      },
      %Variation{
        id: :graded,
        description:
          "A love three friends share: the heart in gold, as on a card (the Feed's glyph takes its grade).",
        attributes: %{
          entry: entry("graded", %{kind: :review, glyphs: [{:love, :gold}], text: "Yes.", ago: "1d ago"})
        }
      },
      %Variation{
        id: :person_page_row,
        description:
          "The person page's row: no tile and no name (the page is one person), every act on the title after the verb — reviewed, love and watched — and the review's words.",
        attributes: %{
          entry:
            entry("page", %{
              id: "person-row-page",
              author: nil,
              kind: :review,
              glyphs: [{:love, :gold}, {:watched, :silver}],
              text: @review_text,
              ago: "1w ago"
            })
        }
      },
      %Variation{
        id: :person_page_series,
        description:
          "A series on the person page: watched at its latest episode, the episode's name in the words slot; reviewed earlier, so the opinion glyph follows the eye and the review's words sit under the name.",
        attributes: %{
          entry:
            entry("series", %{
              id: "person-row-series",
              ref: {1399, :tv_series},
              title:
                Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show", year: "1959"}),
              author: nil,
              kind: :watched,
              episode: %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"},
              glyphs: [{:watched, :plain}, {:review, :plain}],
              text: "Slow, but it earns the slowness.",
              ago: "2d ago"
            })
        }
      }
    ]
  end
end
