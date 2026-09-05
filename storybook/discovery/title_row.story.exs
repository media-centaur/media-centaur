defmodule MediaCentaurWeb.Storybook.Discovery.TitleRow do
  @moduledoc """
  One Discovery row — poster thumb, identity line, the host's lead line
  and quiet markers, a note or the overview — as a whole-card click
  target. Every verb lives in the title detail modal, so the row never
  grows or loses a control depending on where the title stands; only
  its markers change. `poster_url: nil` shows the icon fallback.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.Discovery.TitleRow.title_row/1
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

  defp recommendation(nickname, sentiment) do
    %{
      activity: %Activity{
        kind: :recommendation,
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
        id: :from_friend_with_note,
        description:
          "A feed row: the lead line says who and when, On watchlist is a marker, the " <>
            "friend's note displaces the overview, and the pennant is icon-only because " <>
            "the lead already names the friend.",
        attributes: %{
          id: "row-from-friend",
          title: title(),
          lead: "Sample Friend recommended · 2 days ago",
          markers: ["On watchlist"],
          secondary: "Watch it before anyone spoils the ending.",
          recommendations: [recommendation("Sample Friend", :love)],
          named?: false
        }
      },
      %Variation{
        id: :own_recommendation,
        description: "An own recommendation on the Yours scope: the lead reads You.",
        attributes: %{
          id: "row-own",
          title: title(),
          lead: "You recommended · today",
          recommendations: [recommendation(nil, :like)],
          named?: false
        }
      },
      %Variation{
        id: :watchlist_recommended,
        description: "A watchlist row has no lead, so the pennants carry the names — love above like.",
        attributes: %{
          id: "row-watchlist-recommended",
          title: title(),
          markers: ["In library"],
          recommendations: [
            recommendation("Other Friend", :like),
            recommendation("Sample Friend", :love)
          ]
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
