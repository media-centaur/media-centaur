defmodule MediaCentaurWeb.Storybook.Title.SocialCapsule do
  @moduledoc """
  The social capsule: the title's social glyphs on a dark pill in the
  detail hero's upper right, each at its grade; pressing it opens the
  social panel beneath it. The template stands in for the hero: a dark
  backdrop band with the capsule at its upper right.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.Social.social_capsule/1
  def render_source, do: :function

  def template do
    """
    <div class="relative h-[560px] w-[760px] rounded-xl bg-[linear-gradient(135deg,oklch(40%_0.05_60),oklch(22%_0.03_264))]">
      <div class="absolute right-3 top-3"><.psb-variation/></div>
    </div>
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

  defp attrs(rows, open),
    do: %{
      id: "detail-social",
      rows: rows,
      open: open,
      zone: "detail_social",
      on_toggle: "social_panel_toggle",
      on_close: "social_panel_close",
      now: @now
    }

  def variations do
    [
      %Variation{
        id: :at_rest,
        description: "At rest: love silver (a friend and you), like plain, watched gold, listing plain.",
        attributes: attrs(full(), false)
      },
      %Variation{
        id: :open,
        description: "Open: the reviews, then who watched and who wants to watch.",
        attributes: attrs(full(), true)
      },
      %Variation{
        id: :one_friend,
        description: "One friend watched it: one plain eye.",
        attributes: attrs([row("Sam", :watched)], false)
      },
      %Variation{
        id: :reader_alone,
        description: "Only you acted on it: no capsule.",
        attributes: attrs([row(nil, :review, %{sentiment: :love}), row(nil, :listing)], false)
      }
    ]
  end
end
