defmodule MediaCentaurWeb.Storybook.Incoming.ShelfRow do
  @moduledoc """
  One Coming-up agenda row — date column, 2:3 poster thumb (or the
  quiet ghost-letterform placeholder), title/subtitle, and the shared
  status pill on the right (an under-pursuit pill carries the percent
  and anchors to the torrent row).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.Incoming.Shelf.Card

  def function, do: &MediaCentaurWeb.Components.Incoming.Shelf.shelf_row/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :in_pursuit,
        description:
          "Dropped today, already downloading — info pill with percent, anchoring to " <>
            "#pursuit-<pursuit_id>.",
        attributes: %{
          card: %Card{
            key: "sample-show-s02e05",
            item_id: 1,
            pursuit_id: "0af1c2d3-0000-0000-0000-000000000001",
            title: "Sample Show",
            subtitle: "S02E05 · \"The Vanishing Reel\"",
            date_label: "Tonight",
            status: :in_pursuit,
            percent: 62,
            kind: :episode
          }
        }
      },
      %Variation{
        id: :armed,
        description: "A future release that will auto-grab when it drops.",
        attributes: %{
          card: %Card{
            key: "haxan-s01e06",
            item_id: 2,
            title: "Häxan",
            subtitle: "S01E06 · Jul 17",
            date_label: "Fri Jul 17",
            status: :armed,
            kind: :episode
          }
        }
      },
      %Variation{
        id: :season_drop,
        description: "A whole season landing at once — the episode-count caption.",
        attributes: %{
          card: %Card{
            key: "the-golem-s3",
            item_id: 3,
            title: "The Golem",
            subtitle: "S3",
            date_label: "Fri Jul 24",
            kind: :season_drop,
            episode_count: 8
          }
        }
      },
      %Variation{
        id: :in_theaters,
        description: "Watch-only — neutral pill (identity, not health), no grab affordance.",
        attributes: %{
          card: %Card{
            key: "metropolis",
            item_id: 4,
            title: "Metropolis",
            subtitle: "Feature · home release TBA",
            date_label: "Now",
            status: :in_theaters,
            kind: :movie
          }
        }
      },
      %Variation{
        id: :plain_tracked,
        description:
          "No pill at all — a plain dated row, the honest acquisition-off degradation " <>
            "(the date column carries the date, nothing implies grabbing).",
        attributes: %{
          card: %Card{
            key: "phantom-carriage-s01e03",
            item_id: 5,
            title: "The Phantom Carriage",
            subtitle: "S01E03 · Jul 14",
            date_label: "Tue",
            kind: :episode
          }
        }
      },
      %Variation{
        id: :with_artwork,
        description:
          "With real art the placeholder gives way to an eager+sync thumb (fake URL — " <>
            "renders broken outside the app).",
        attributes: %{
          card: %Card{
            key: "nosferatu",
            item_id: 6,
            title: "Nosferatu",
            subtitle: "Feature · home release",
            date_label: "Aug 6",
            status: :tracked,
            art_url: "/images/sample-nosferatu-poster.jpg",
            kind: :movie
          }
        }
      }
    ]
  end
end
