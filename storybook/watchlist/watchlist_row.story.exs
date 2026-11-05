defmodule MediaCentaurWeb.Storybook.Watchlist.Row do
  @moduledoc """
  One row of the Watchlist page (campaign `discovery.md`, M15): the
  title's identity block with the host's markers and a friend's note,
  the social glyphs, the state block — one line and a date — and the
  rung as a glass select, always shown. The state matrix is the
  `State` kinds; the menu's items follow the rung and whether the
  library owns the title.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Watchlist.Row.Item
  alias MediaCentaurWeb.Components.Watchlist.Row.State

  def function, do: &MediaCentaurWeb.Components.Watchlist.Row.watchlist_row/1
  def render_source, do: :function
  def layout, do: :one_column

  @today ~D[2026-11-03]

  def template do
    """
    <div class="divide-y divide-base-content/8 pb-40">
      <.psb-variation/>
    </div>
    """
  end

  defp movie(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2026",
          release_date: ~D[2026-10-16],
          overview: "A sample movie overview that confirms this is the title you meant."
        },
        overrides
      )
    )
  end

  defp show(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 42,
          media_type: :tv_series,
          name: "Sample Show",
          year: "2023",
          release_date: ~D[2023-09-29],
          overview: "A sample show overview."
        },
        overrides
      )
    )
  end

  defp item(id, title, rung, overrides) do
    struct!(
      Item,
      Map.merge(
        %{id: id, ref: Title.ref(title), title: title, rung: rung, poster_url: nil},
        Map.new(overrides)
      )
    )
  end

  defp review do
    %{
      activity: %Activity{
        kind: :review,
        sentiment: :love,
        tmdb_id: 777,
        media_type: :movie,
        title: movie(),
        acted_at: ~U[2026-09-01 12:00:00Z]
      },
      author: %Person{
        pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
        name_override: "Nick",
        own?: false,
        short_npub: "npub1lyy9…8z4h",
        added_on: ~D[2026-08-30]
      }
    }
  end

  def variations do
    [
      %Variation{
        id: :episodes_out,
        description:
          "A followed series with aired episodes you do not have: the count and the latest date.",
        attributes: %{
          today: @today,
          item:
            item("row-episodes-out", show(), :follow,
              state: %State{kind: :episodes_out, count: 3, date: ~D[2026-10-27]}
            )
        }
      },
      %Variation{
        id: :episodes_out_caught_up_offered,
        description:
          "The same, with the Caught up button the page offers a followed series with episodes out: one press says you have seen them.",
        attributes: %{
          today: @today,
          caught_up?: true,
          item:
            item("row-episodes-out-caught-up", show(), :follow,
              state: %State{kind: :episodes_out, count: 3, date: ~D[2026-10-27], caught_up: {1, 25}}
            )
        }
      },
      %Variation{
        id: :next_episode,
        description: "Nothing outstanding; the next episode is dated.",
        attributes: %{
          today: @today,
          item: item("row-next", show(), :grab, state: %State{kind: :next_episode, date: ~D[2026-11-11]})
        }
      },
      %Variation{
        id: :caught_up_through,
        description:
          "Nothing out and a caught-up point: where you stand is the line, the next episode beneath it (M16).",
        attributes: %{
          today: @today,
          item:
            item("row-caught-up", show(), :grab,
              state: %State{kind: :next_episode, date: ~D[2026-11-11], caught_up: {1, 28}}
            )
        }
      },
      %Variation{
        id: :between_seasons,
        description: "Caught up on a returning series TMDB has not dated.",
        attributes: %{
          today: @today,
          item: item("row-between", show(), :follow, state: %State{kind: :between_seasons})
        }
      },
      %Variation{
        id: :not_listed,
        description:
          "A series you've watched with no record (the Series you've watched group): " <>
            "the select reads Not listed and offers the three list rungs — no Ignore " <>
            "(owned), no Remove (nothing to remove).",
        attributes: %{
          today: @today,
          item:
            item("row-not-listed", show(), nil,
              owned?: true,
              markers: ["In library"],
              state: %State{kind: :between_seasons}
            )
        }
      },
      %Variation{
        id: :not_listed_menu_open,
        description: "The same row with its menu open: On your list, Tracking, Auto-grab.",
        attributes: %{
          today: @today,
          item:
            item("row-not-listed-open", show(), nil,
              owned?: true,
              markers: ["In library"],
              state: %State{kind: :between_seasons},
              menu_open?: true
            )
        }
      },
      %Variation{
        id: :ended,
        description: "A followed series that ended.",
        attributes: %{
          today: @today,
          item: item("row-ended", show(), :follow, state: %State{kind: :ended})
        }
      },
      %Variation{
        id: :owned,
        description: "The library owns it — In library is the marker; the menu offers no Ignore.",
        attributes: %{
          today: @today,
          item:
            item("row-owned", show(), :follow,
              owned?: true,
              markers: ["In library"],
              state: %State{kind: :episodes_out, count: 1, date: ~D[2026-10-21]}
            )
        }
      },
      %Variation{
        id: :out_now,
        description:
          "A listed movie with a digital release behind it; Planning is the acquisition marker.",
        attributes: %{
          today: @today,
          item:
            item("row-out-now", movie(), :list,
              markers: ["Planning"],
              state: %State{kind: :out_now, date: ~D[2026-10-16]}
            )
        }
      },
      %Variation{
        id: :in_theaters,
        description: "A listed movie in cinemas.",
        attributes: %{
          today: @today,
          item:
            item("row-theaters", movie(), :list, state: %State{kind: :in_theaters, date: ~D[2026-10-30]})
        }
      },
      %Variation{
        id: :coming_up,
        description:
          "A movie at Auto-grab, dated next year; a friend's review is the note and the glyph.",
        attributes: %{
          today: @today,
          item:
            item("row-coming-up", movie(%{year: "2027", release_date: ~D[2027-03-25]}), :grab,
              notes: [%{name: "Nick", text: "The trailer alone sold me."}],
              social_activity: [review()],
              state: %State{kind: :coming_up, date: ~D[2027-03-25]}
            )
        }
      },
      %Variation{
        id: :undated,
        description: "TMDB has no usable date for it.",
        attributes: %{
          today: @today,
          item:
            item("row-undated", movie(%{year: nil, release_date: nil}), :list,
              state: %State{kind: :undated}
            )
        }
      },
      %Variation{
        id: :ignored,
        description:
          "An Ignored record: hidden from the Feed and Discovery, no poster (it references nothing in the store); the menu offers On your list and Stop ignoring.",
        attributes: %{
          today: @today,
          item: item("row-ignored", movie(), :ignored, state: %State{kind: :ignored})
        }
      },
      %Variation{
        id: :menu_open,
        description: "The rung menu open on a row: the current rung marked, Ignore and Remove as verbs.",
        attributes: %{
          today: @today,
          item:
            item("row-menu-open", show(), :follow,
              menu_open?: true,
              state: %State{kind: :between_seasons}
            )
        }
      }
    ]
  end
end
