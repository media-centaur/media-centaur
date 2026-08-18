defmodule MediaCentaurWeb.Storybook.Discovery.WatchlistRow do
  @moduledoc """
  One watchlist entry — poster thumb, identity line, note or overview,
  and the single state-dependent primary action (In library / Download /
  Track release) with Remove as the quiet secondary. `poster_url: nil`
  throughout shows the icon fallback; a fixed `today` pins the
  released/upcoming split.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Discovery.WatchlistItem

  def function, do: &MediaCentaurWeb.Components.Discovery.WatchlistRow.watchlist_row/1
  def render_source, do: :function
  def layout, do: :one_column

  defp item(overrides) do
    struct!(
      %WatchlistItem{
        tmdb_id: 777,
        media_type: :movie,
        name: "Sample Movie",
        year: "2010",
        release_date: ~D[2010-03-05],
        overview: "A sample movie overview that confirms this is the title you meant.",
        source: :manual
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :in_library,
        description:
          "The library already knows the title — the primary action links straight " <>
            "to its detail; no download verb competes with what is already owned.",
        attributes: %{
          item: item(%{}),
          library_owner_id: "0d2c5cd6-0000-4000-8000-000000000001",
          release_mode_available: true,
          today: ~D[2026-08-18]
        }
      },
      %Variation{
        id: :download,
        description:
          "Released (`:released`), indexer configured, not in the library — " <>
            "Download opens the plan flow.",
        attributes: %{
          item: item(%{}),
          release_mode_available: true,
          today: ~D[2026-08-18]
        }
      },
      %Variation{
        id: :track_release,
        description: "Not out yet (`:upcoming`) — the only honest verb is Track release.",
        attributes: %{
          item:
            item(%{
              tmdb_id: 778,
              media_type: :tv_series,
              name: "Sample Upcoming Show",
              year: "2999",
              release_date: ~D[2999-03-01],
              overview: "Announced but unaired — tracking is the only move."
            }),
          release_mode_available: true,
          today: ~D[2026-08-18]
        }
      },
      %Variation{
        id: :track_only,
        description:
          "Released but no indexer configured — the row offers Track release; " <>
            "nothing promises a grab the app can't make.",
        attributes: %{
          item: item(%{}),
          release_mode_available: false,
          today: ~D[2026-08-18]
        }
      },
      %Variation{
        id: :with_note,
        description: "A provenance note displaces the TMDB overview — the note is why it's here.",
        attributes: %{
          item: item(%{note: "Recommended after movie night — the sequel to the one we liked."}),
          release_mode_available: true,
          today: ~D[2026-08-18]
        }
      }
    ]
  end
end
