defmodule MediaCentaurWeb.Storybook.Title.SocialPanel do
  @moduledoc """
  The social panel the social capsule opens: every review on the title
  — the tile, the name, the review's glyph at its grade, how long ago,
  the words — then one sentence per act that carries no words.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.Social.social_panel/1
  def render_source, do: :function

  def template do
    """
    <div class="relative h-[520px] w-[460px]"><.psb-variation/></div>
    """
  end

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title

  @now ~U[2026-09-28 12:00:00Z]

  # One friend per name, each with their own key so the grade counts
  # them apart; nil is the reader.
  defp row(name, kind, attrs \\ %{}) do
    %{
      activity:
        struct(
          Activity,
          Map.merge(
            %{
              id: "#{name || "you"}-#{kind}",
              kind: kind,
              sentiment: nil,
              text: nil,
              author_pubkey: name || "you",
              tmdb_id: 777,
              media_type: :movie,
              title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}),
              acted_at: ~U[2026-09-26 12:00:00Z]
            },
            attrs
          )
        ),
      author: author(name)
    }
  end

  defp author(nil), do: %Person{pubkey: "you", own?: true}

  defp author(name),
    do: %Person{
      pubkey: name,
      name_override: name,
      own?: false,
      published_hue: hue(name),
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }

  defp hue("Nick"), do: 30
  defp hue("Sam"), do: 150
  defp hue(_name), do: 300

  # Two love it (a friend and you), one likes it, three watched it, one wants to.
  defp full do
    [
      row("Nick", :review, %{sentiment: :love, text: "Watch it before anyone spoils the ending."}),
      row(nil, :review, %{
        sentiment: :love,
        text: "Best thing they did together.",
        acted_at: ~U[2026-09-21 12:00:00Z]
      }),
      row("Sam", :review, %{sentiment: :like, acted_at: ~U[2026-09-07 12:00:00Z]}),
      row("Nick", :watched),
      row("Sam", :watched),
      row(nil, :watched),
      row("Cleo", :listing)
    ]
  end

  defp attrs(rows), do: %{id: "social-panel", rows: rows, now: @now}

  def variations do
    [
      %Variation{
        id: :reviews_and_acts,
        description: "Reviews, then who watched and who wants to watch.",
        attributes: attrs(full())
      },
      %Variation{
        id: :reviews_only,
        description: "Reviews only; a review with no words is the line alone.",
        attributes: attrs(Enum.filter(full(), &(&1.activity.kind == :review)))
      },
      %Variation{
        id: :acts_only,
        description: "No one reviewed it: the sentences alone.",
        attributes: attrs(Enum.reject(full(), &(&1.activity.kind == :review)))
      },
      %Variation{
        id: :long,
        description: "Long words wrap; past its height the panel scrolls.",
        attributes:
          attrs(
            for name <- ~w(Ada Ben Cleo Dee Eli Fay Gus) do
              row(name, :review, %{
                sentiment: :like,
                text:
                  "A long review that runs on over several lines to show how the panel wraps words and, past its height, scrolls."
              })
            end
          )
      }
    ]
  end
end
