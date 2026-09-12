defmodule MediaCentaurWeb.Storybook.Title.Pennant do
  @moduledoc """
  The pennant (UIDR-037): what friends did with a title, flying from the
  right edge of whatever the title is on. One shape at every width, one
  flag per kind of act. The template gives each variation a row-shaped
  surface with the mast pinned to its edge, as a Discovery row does —
  content-height over a one-row minimum, like the real row, so a full
  six-flag mast is shown rather than clipped.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.Title.Pennant.pennants/1
  def render_source, do: :function

  def template do
    """
    <div class="glass-surface flex min-h-16 w-80 items-center justify-end overflow-hidden rounded-xl py-3 pl-4">
      <.psb-variation/>
    </div>
    """
  end

  defp row(nickname, kind, sentiment \\ :like) do
    %{
      activity: %Activity{
        kind: kind,
        sentiment: sentiment,
        tmdb_id: 777,
        media_type: :movie,
        title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}),
        acted_at: ~U[2026-09-01 12:00:00Z]
      },
      nickname: nickname,
      own?: is_nil(nickname)
    }
  end

  def variations do
    [
      %Variation{
        id: :like,
        description: "A friend likes it: neutral tint, thumbs up.",
        attributes: %{activity: [row("Sample Friend", :review)]}
      },
      %Variation{
        id: :love,
        description:
          "A friend loves it: a heart on the rose fill, the one warm hue outside the health palette.",
        attributes: %{activity: [row("Sample Friend", :review, :love)]}
      },
      %Variation{
        id: :dislike,
        description: "A friend dislikes it: a thumbs down on the neutral tint.",
        attributes: %{activity: [row("Sample Friend", :review, :dislike)]}
      },
      %Variation{
        id: :reviewed,
        description: "A friend reviewed it without a verdict: a speech bubble on the neutral tint.",
        attributes: %{activity: [row("Sample Friend", :review, nil)]}
      },
      %Variation{
        id: :watched,
        description: "A friend watched it: an eye on the neutral tint.",
        attributes: %{activity: [row("Sample Friend", :watched)]}
      },
      %Variation{
        id: :listing,
        description: "A friend wants to watch it: a bookmark on the neutral tint.",
        attributes: %{activity: [row("Sample Friend", :listing)]}
      },
      %Variation{
        id: :own,
        description: "Your own review reads You. Your own watching and listing never fly.",
        attributes: %{activity: [row(nil, :review)]}
      },
      %Variation{
        id: :two_same,
        description: "Two friends, one flag: names joined, newest first.",
        attributes: %{
          activity: [
            row("Sample Friend", :review, :love),
            row("Other Friend", :review, :love)
          ]
        }
      },
      %Variation{
        id: :overflow,
        description: "Past two names the pennant counts.",
        attributes: %{
          activity: [
            row("Sample Friend", :review),
            row("Other Friend", :review),
            row("Third Friend", :review),
            row(nil, :review)
          ]
        }
      },
      %Variation{
        id: :stacked,
        description:
          "Every flag at once, in mast order: love, like, dislike, reviewed, watched, listing.",
        attributes: %{
          activity: [
            row("Other Friend", :listing),
            row("Third Friend", :watched),
            row("Fourth Friend", :review, nil),
            row("Third Friend", :review, :dislike),
            row("Other Friend", :review),
            row("Sample Friend", :review, :love)
          ]
        }
      },
      %Variation{
        id: :labelled,
        description:
          "A fixed label in place of the names — the Review modal's Dislike / Like / Love choice.",
        attributes: %{activity: [row(nil, :review, :love)], label: "Love"}
      },
      %Variation{
        id: :on_image,
        description: "Over imagery the neutral tint is dark glass; love keeps its fill.",
        attributes: %{
          activity: [
            row("Third Friend", :watched),
            row("Other Friend", :review),
            row("Sample Friend", :review, :love)
          ],
          on_image: true
        }
      }
    ]
  end
end
