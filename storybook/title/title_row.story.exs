defmodule MediaCentaurWeb.Storybook.Title.Row do
  @moduledoc """
  One title row — poster thumb, identity line, the host's quiet
  markers, the notes or the overview — as a whole-card click target.
  Every verb lives in the title detail modal, so the row never grows or
  loses a control depending on where the title stands; only its markers
  change. `poster_url: nil` shows the icon fallback.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.Title.Row.title_row/1
  def render_source, do: :function
  def layout, do: :one_column

  defp title(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          release_date: ~D[2010-03-05],
          overview: "A sample movie overview that confirms this is the title you meant."
        },
        overrides
      )
    )
  end

  defp review(nickname, sentiment) do
    %{
      activity: %Activity{
        kind: :review,
        sentiment: sentiment,
        tmdb_id: 777,
        media_type: :movie,
        title: title(),
        acted_at: ~U[2026-09-01 12:00:00Z]
      },
      nickname: nickname,
      own?: is_nil(nickname)
    }
  end

  def variations do
    [
      %Variation{
        id: :bare,
        description: "A watchlist entry with nothing in flight: identity and overview only.",
        attributes: %{id: "row-bare", title: title()}
      },
      %Variation{
        id: :in_library,
        description: "The library owns it — In library is the marker; no other state competes.",
        attributes: %{id: "row-in-library", title: title(), markers: ["In library"]}
      },
      %Variation{
        id: :planning,
        description: "A one-click download is searching: Planning.",
        attributes: %{id: "row-planning", title: title(), markers: ["Planning"]}
      },
      %Variation{
        id: :downloading,
        description: "A pursuit is in flight: Downloading.",
        attributes: %{id: "row-downloading", title: title(), markers: ["Downloading"]}
      },
      %Variation{
        id: :needs_review,
        description: "The plan parked for a decision on Downloads: Needs review.",
        attributes: %{id: "row-needs-review", title: title(), markers: ["Needs review"]}
      },
      %Variation{
        id: :reviewed_by_one,
        description:
          "A title one friend reviewed: On watchlist is a marker, the note " <>
            "displaces the overview unattributed, and the named pennant carries the sentiment.",
        attributes: %{
          id: "row-reviewed-by-one",
          title: title(),
          markers: ["On watchlist"],
          notes: [%{name: nil, text: "Watch it before anyone spoils the ending."}],
          friend_activity: [review("Sample Friend", :love)]
        }
      },
      %Variation{
        id: :reviewed_by_two,
        description:
          "Two friends on one title (UIDR-031): each note carries its name, " <>
            "and the mast stacks love above like.",
        attributes: %{
          id: "row-reviewed-by-two",
          title: title(),
          notes: [
            %{name: "Sample Friend", text: "Watch it before anyone spoils the ending."},
            %{name: "Other Friend", text: "Fine."}
          ],
          friend_activity: [
            review("Other Friend", :like),
            review("Sample Friend", :love)
          ]
        }
      },
      %Variation{
        id: :watchlist_with_note,
        description: "A watchlist row: the item's own note, and the pennants name who reviewed it.",
        attributes: %{
          id: "row-watchlist-with-note",
          title: title(),
          markers: ["In library"],
          notes: [%{name: nil, text: "For the weekend."}],
          friend_activity: [review("Sample Friend", :love)]
        }
      },
      %Variation{
        id: :with_poster,
        description: "With art the placeholder gives way to the eager+sync poster thumb.",
        attributes: %{
          id: "row-with-poster",
          title: title(),
          poster_url: "/images/sample-nosferatu-poster.jpg"
        }
      }
    ]
  end
end
