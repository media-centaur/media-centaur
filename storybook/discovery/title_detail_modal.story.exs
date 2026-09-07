defmodule MediaCentaurWeb.Storybook.Discovery.TitleDetailModal do
  @moduledoc """
  The title detail modal (UIDR-035) — the one surface for a title
  without files, on Discovery and Incoming alike. The action row is the
  honest rule with the acquisition state folded in; a series Download
  is the split control; below it the shared release timeline and
  tracking-mode control for any title the library does not own.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Library.Person
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.Facet
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail

  @today ~D[2026-08-03]

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

  defp recommendation(title, nickname, sentiment) do
    %{
      activity: %Activity{
        kind: :recommendation,
        sentiment: sentiment,
        tmdb_id: title.tmdb_id,
        media_type: title.media_type,
        title: title,
        acted_at: ~U[2026-09-01 10:00:00Z]
      },
      nickname: nickname,
      own?: is_nil(nickname)
    }
  end

  defp detail(title, overrides) do
    struct!(
      %TitleDetail{
        ref: {title.tmdb_id, title.media_type},
        title: title,
        primary: :download,
        scoped?: title.media_type == :tv_series,
        rung: nil,
        acquisition?: true,
        default_grab_mode: "ask"
      },
      overrides
    )
  end

  defp episode(id, season, episode, air_date, status) do
    %Event{
      id: id,
      item_id: "sample-show",
      item_name: "Sample Show",
      media_type: :tv_series,
      kind: :episode,
      season_number: season,
      episode_number: episode,
      air_date: air_date,
      status: status
    }
  end

  defp tracking(overrides) do
    struct!(
      %TrackingDetail{
        item_id: "sample-show",
        tracking_since: ~U[2026-03-14 12:00:00Z],
        timeline: [
          episode("s02e05", 2, 5, @today, :upcoming),
          episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming),
          episode("s02e04", 2, 4, ~D[2026-07-27], :in_library)
        ],
        activity: [
          %{text: "Grabbed S02E04", at: "6 days ago"},
          %{text: "Started tracking", at: "4 months ago"}
        ]
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
        attributes: %{today: @today, detail: detail(movie(), %{preview: preview(movie())})}
      },
      %Variation{
        id: :movie_download,
        description: "A released movie with an indexer: Download, Add to watchlist.",
        attributes: %{today: @today, detail: detail(movie(), %{})}
      },
      %Variation{
        id: :series_split,
        description: "A series: the split control — Download season 1, chevron for Download all.",
        attributes: %{today: @today, detail: detail(show(), %{})}
      },
      %Variation{
        id: :series_menu_open,
        description: "The scope menu open, showing the second verb.",
        attributes: %{today: @today, detail: detail(show(), %{}), scope_menu_open: true}
      },
      %Variation{
        id: :from_friend,
        description:
          "Feed provenance: who recommended it and their note above the overview; " <>
            "On watchlist as the quiet secondary, with Remove from watchlist as the tertiary verb.",
        attributes: %{
          today: @today,
          detail:
            detail(movie(), %{
              kind: :recommendation,
              sender: "Sample Friend",
              note: "Watch it before anyone spoils the ending.",
              acted_at: ~U[2026-09-01 10:00:00Z],
              own?: false,
              rung: :follow,
              recommendations: [recommendation(movie(), "Sample Friend", :love)]
            })
        }
      },
      %Variation{
        id: :recommended_by_two,
        description:
          "Two friends with different sentiments: the pennants stack on the hero's right " <>
            "edge under the actions, love above like, the like body dark glass over the art.",
        attributes: %{
          today: @today,
          detail:
            detail(movie(), %{
              rung: :follow,
              recommendations: [
                recommendation(movie(), "Other Friend", :like),
                recommendation(movie(), "Sample Friend", :love)
              ]
            })
        }
      },
      %Variation{
        id: :own_recommendation,
        description: "An own recommendation carries Delete recommendation as the tertiary verb.",
        attributes: %{
          today: @today,
          detail:
            detail(movie(), %{kind: :recommendation, own?: true, acted_at: ~U[2026-09-01 10:00:00Z]})
        }
      },
      %Variation{
        id: :friend_watched,
        description: "A friend finished an episode: the statement names it; no note.",
        attributes: %{
          today: @today,
          detail:
            detail(show(), %{
              kind: :watched,
              episode: %Episode{season_number: 2, episode_number: 5, name: "The Fifth"},
              sender: "Sample Friend",
              acted_at: ~U[2026-09-01 10:00:00Z],
              own?: false,
              primary: nil
            })
        }
      },
      %Variation{
        id: :own_tracking,
        description: "An own tracking activity carries Delete tracking activity as the tertiary verb.",
        attributes: %{
          today: @today,
          detail:
            detail(show(), %{
              kind: :tracking,
              own?: true,
              acted_at: ~U[2026-09-01 10:00:00Z],
              primary: nil
            })
        }
      },
      %Variation{
        id: :in_library,
        description:
          "The library owns it: In library links to the detail, nothing else competes — " <>
            "no tracking sections either, that detail is the library's.",
        attributes: %{
          today: @today,
          detail: detail(movie(), %{primary: {:in_library, "0d2c5cd6-0000-4000-8000-000000000001"}})
        }
      },
      %Variation{
        id: :needs_review,
        description: "A parked plan: Needs review links to Downloads.",
        attributes: %{today: @today, detail: detail(movie(), %{primary: {:state, :needs_review}})}
      },
      %Variation{
        id: :downloading,
        description: "A pursuit in flight: a stated fact, no verb.",
        attributes: %{today: @today, detail: detail(movie(), %{primary: {:state, :downloading}})}
      },
      %Variation{
        id: :not_out_yet,
        description:
          "Not out yet (or no indexer): no primary verb — the tracking-mode control " <>
            "below is the act, and its copy says arming adds the title to the watchlist.",
        attributes: %{today: @today, detail: detail(movie(), %{primary: nil})}
      },
      %Variation{
        id: :tracked_watch,
        description:
          "A watchlisted series armed at Watch: Tracking since in the orientation, the " <>
            "release timeline first (tonight's episode featured), the control at Watch, " <>
            "recent activity, then the overview.",
        attributes: %{
          today: @today,
          detail: detail(show(), %{primary: nil, rung: :follow, tracking: tracking(%{})})
        }
      },
      %Variation{
        id: :tracked_grab,
        description:
          "Armed at Grab with the per-title quality acceptance set: the timeline's next " <>
            "episode reads Will grab and the acceptance row follows the control.",
        attributes: %{
          today: @today,
          detail:
            detail(show(), %{
              primary: nil,
              rung: :grab,
              lower_quality_accepted?: true,
              tracking:
                tracking(%{
                  timeline: [
                    episode("s02e05", 2, 5, @today, :armed),
                    episode("s02e06", 2, 6, ~D[2026-08-11], :armed)
                  ]
                })
            })
        }
      },
      %Variation{
        id: :off,
        description:
          "A title that is not on the ladder: the control shows Off and there is no " <>
            "tracking half at all, because nothing is stored for it.",
        attributes: %{
          today: @today,
          detail: detail(show(), %{primary: nil, rung: nil, tracking: nil})
        }
      },
      %Variation{
        id: :forecast_only,
        description:
          "Acquisition not configured: the grab modes stay selectable and the note " <>
            "says nothing downloads until it is; the timeline carries no grab implication.",
        attributes: %{
          today: @today,
          detail:
            detail(show(), %{
              primary: nil,
              acquisition?: false,
              rung: :default,
              tracking: tracking(%{})
            })
        }
      },
      %Variation{
        id: :listed,
        description:
          "On the list at List: the ladder control carries that state, and the strip " <>
            "has no Add/Remove verbs of its own any more.",
        attributes: %{today: @today, detail: detail(movie(), %{rung: :list})}
      }
    ]
  end
end
