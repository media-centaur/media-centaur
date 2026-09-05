defmodule MediaCentaurWeb.Storybook.Discovery.RecommendationPennant do
  @moduledoc """
  The recommendation pennant: who recommended a title and how much,
  flying from the right edge of whatever the title is on. One shape at
  every width. The template gives each variation a row-shaped surface
  with the mast pinned to its edge, as a Discovery row does.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  def function, do: &MediaCentaurWeb.Components.Discovery.RecommendationPennant.recommendation_pennants/1
  def render_source, do: :function

  def template do
    """
    <div class="glass-surface flex h-16 w-80 items-center justify-end overflow-hidden rounded-xl pl-4">
      <.psb-variation/>
    </div>
    """
  end

  defp row(nickname, sentiment) do
    %{
      activity: %Activity{
        kind: :recommendation,
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
        attributes: %{recommendations: [row("Sample Friend", :like)]}
      },
      %Variation{
        id: :love,
        description:
          "A friend loves it: a heart on the rose fill, the one warm hue outside the health palette.",
        attributes: %{recommendations: [row("Sample Friend", :love)]}
      },
      %Variation{
        id: :icon_only,
        description: "The Feed drops the name — its lead line already says who.",
        attributes: %{recommendations: [row("Sample Friend", :love)], named?: false}
      },
      %Variation{
        id: :own,
        description: "Your own recommendation reads You.",
        attributes: %{recommendations: [row(nil, :like)]}
      },
      %Variation{
        id: :two_same,
        description: "Two friends, one sentiment: names joined, newest first.",
        attributes: %{recommendations: [row("Sample Friend", :love), row("Other Friend", :love)]}
      },
      %Variation{
        id: :overflow,
        description: "Past two names the pennant counts.",
        attributes: %{
          recommendations: [
            row("Sample Friend", :like),
            row("Other Friend", :like),
            row("Third Friend", :like),
            row(nil, :like)
          ]
        }
      },
      %Variation{
        id: :stacked,
        description: "Mixed sentiments stack on the mast, love above like.",
        attributes: %{recommendations: [row("Other Friend", :like), row("Sample Friend", :love)]}
      },
      %Variation{
        id: :labelled,
        description: "A fixed label in place of the names — the Recommend modal's Like / Love choice.",
        attributes: %{recommendations: [row(nil, :love)], label: "Love"}
      },
      %Variation{
        id: :on_image,
        description: "Over imagery the like body is dark glass; love keeps its fill.",
        attributes: %{
          recommendations: [row("Other Friend", :like), row("Sample Friend", :love)],
          on_image: true
        }
      }
    ]
  end
end
