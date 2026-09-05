defmodule MediaCentaurWeb.Storybook.Discovery.TitleDetailModal do
  @moduledoc """
  The Discovery title detail modal (spec 2026-09-05) — one surface for
  both tabs. The action row is the honest three-state rule with the
  acquisition state folded in; a series Download is the split control.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Discovery.TitleDetail

  def function, do: &MediaCentaurWeb.Components.Discovery.TitleDetailModal.title_detail_modal/1
  def render_source, do: :function
  def layout, do: :one_column

  # A real `position: fixed` overlay — iframe each variation (same
  # treatment as the release-tracking title modal story).
  def container, do: {:iframe, style: "min-height: 640px; width: 100%;"}

  defp movie do
    Title.new!(%{
      tmdb_id: 777,
      media_type: :movie,
      name: "Sample Movie",
      year: "2010",
      release_date: ~D[2010-03-05],
      overview: "A sample movie overview that confirms this is the title you meant."
    })
  end

  defp show do
    Title.new!(%{
      tmdb_id: 42,
      media_type: :tv_series,
      name: "Sample Show",
      year: "2012",
      release_date: ~D[2012-01-01],
      overview: "A sample series overview."
    })
  end

  defp detail(title, overrides) do
    struct!(
      %TitleDetail{
        ref: {title.tmdb_id, title.media_type},
        title: title,
        primary: :download,
        scoped?: title.media_type == :tv_series,
        on_watchlist?: false
      },
      overrides
    )
  end

  defp preview(title) do
    %TitlePreview{
      media_type: title.media_type,
      tmdb_id: to_string(title.tmdb_id),
      title: title.name,
      tagline: "Every confirmation counts.",
      overview: title.overview,
      metadata_items: ["2010", "2h 19m", "R", "US"],
      facets: [
        Facet.text("Director", "Jane Director"),
        Facet.rating("Rating", 8.2, 26_000),
        Facet.chips("Genres", ["Drama", "Mystery"])
      ],
      cast: [
        %Person{name: "Actor One", character: "The Drifter", order: 0},
        %Person{name: "Actor Two", character: "Lighthouse Keeper", order: 1}
      ],
      in_library?: false
    }
  end

  def variations do
    [
      %Variation{
        id: :dressed,
        description:
          "The live TMDB preview has landed: tagline in the lockup and the shared preview " <>
            "body — metadata row, facets, top cast — under the provenance. Backdrop and logo " <>
            "are hotlinked from TMDB in the app; nil here pins the frame's placeholder.",
        attributes: %{detail: detail(movie(), %{preview: preview(movie())})}
      },
      %Variation{
        id: :movie_download,
        description: "A released movie with an indexer: Download, Add to watchlist.",
        attributes: %{detail: detail(movie(), %{})}
      },
      %Variation{
        id: :series_split,
        description: "A series: the split control — Download season 1, chevron for Download all.",
        attributes: %{detail: detail(show(), %{})}
      },
      %Variation{
        id: :series_menu_open,
        description: "The scope menu open, showing the second verb.",
        attributes: %{detail: detail(show(), %{}), scope_menu_open: true}
      },
      %Variation{
        id: :from_friend,
        description:
          "Feed provenance: who recommended it and their note above the overview; " <>
            "On watchlist as the quiet secondary, with Remove from watchlist as the tertiary verb.",
        attributes: %{
          detail:
            detail(movie(), %{
              sender: "Sample Friend",
              note: "Watch it before anyone spoils the ending.",
              recommended_at: ~U[2026-09-01 10:00:00Z],
              own?: false,
              on_watchlist?: true
            })
        }
      },
      %Variation{
        id: :own_recommendation,
        description: "An own recommendation carries Delete recommendation as the tertiary verb.",
        attributes: %{
          detail: detail(movie(), %{own?: true, recommended_at: ~U[2026-09-01 10:00:00Z]})
        }
      },
      %Variation{
        id: :in_library,
        description: "The library owns it: In library links to the detail, nothing else competes.",
        attributes: %{
          detail: detail(movie(), %{primary: {:in_library, "0d2c5cd6-0000-4000-8000-000000000001"}})
        }
      },
      %Variation{
        id: :needs_review,
        description: "A parked plan: Needs review links to Downloads.",
        attributes: %{detail: detail(movie(), %{primary: {:state, :needs_review}})}
      },
      %Variation{
        id: :downloading,
        description: "A pursuit in flight: a stated fact, no verb.",
        attributes: %{detail: detail(movie(), %{primary: {:state, :downloading}})}
      },
      %Variation{
        id: :track,
        description: "Not out yet (or no indexer): Track release.",
        attributes: %{detail: detail(movie(), %{primary: :track})}
      },
      %Variation{
        id: :on_watchlist,
        description:
          "On the watchlist, from either tab: On watchlist replaces Add, and Remove from watchlist is the tertiary verb.",
        attributes: %{detail: detail(movie(), %{on_watchlist?: true})}
      }
    ]
  end
end
