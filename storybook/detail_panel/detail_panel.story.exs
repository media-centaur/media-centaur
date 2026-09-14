defmodule MediaCentaurWeb.Storybook.DetailPanel.DetailPanel do
  @moduledoc """
  The title detail modal (UIDR-043) — `DetailPanel` is the tenant of
  `CinematicShell` that renders one `Title.Detail`, owned or not, so
  each variation renders the **whole modal**: the always-in-DOM shell,
  the panel-fixed backdrop, the scrollport, the pinned orientation block
  (identity lockup, hairline, metadata row, action row, prose), and the
  body the facts call for — TV seasons + episodes, the collection poster
  rail (UIDR-023), extras for leaves, Cast and Manage for an owned title,
  and the tracking card (UIDR-042) for any title with something to say.
  Delete confirmations are *inline* — there is no secondary modal.

  ## Variations covered

  The owned half — the library modal's presentation, the bar every
  section is judged against:

    * `:closed` — the shell alone (`detail: nil`).
    * `:movie_basic`, `:movie_reviewed`, `:movie_with_progress` — a bare
      movie: never watched; two friends' pennants on the mast; mid-watch
      with Resume, the hairline and the time left.
    * `:tv_series_all_collapsed`, `:tv_series_with_seasons`,
      `:tv_series_gap_in_flight`, `:tv_series_acquisition_off`,
      `:tv_series_episode_details_open`, `:tv_series_all_episode_details_open`,
      `:tv_series_spoiler_free`, `:tv_series_with_upcoming_inline`,
      `:tv_series_aired_not_in_library`, `:tv_series_only_future`,
      `:tv_series_untracked`, `:tv_series_off` — the season accordion and
      its row states, the tracking card at Grab, and its absence.
    * `:movie_series`, `:movie_series_with_upcoming` — the movie-first
      collection modal over the poster rail.
    * `:info_view_with_files`, `:info_view_files_loading`,
      `:info_view_files_failed`, `:info_view_collapsed_ledger`,
      `:rematch_confirm`, `:delete_pending_all_inline`,
      `:delete_pending_file_inline`, `:delete_in_flight_all` — Manage
      and its gestures.
    * `:tv_series_cast_view`, `:offline`.

  The unowned half — a title without files, the former title modal's
  states, on the same block structure:

    * `:dressed` — the live TMDB preview has landed: tagline, the
      preview's metadata row and overview.
    * `:movie_download`, `:series_split`, `:series_mode_menu_open`,
      `:series_auto_default`, `:series_scope_menu_open`,
      `:series_all_seasons`, `:series_planning` — the Download split
      control and the series scope select, their menus and the pending
      state.
    * `:from_friend`, `:every_flag`, `:own_note`, `:own_review`,
      `:own_listing` — the pennants, a friend's note, your own note, and
      Delete <noun> on an own activity.
    * `:needs_review`, `:downloading`, `:not_out_yet` — the acquisition
      state as a fact, and no verb at all.
    * `:tracked_watch`, `:tracked_grab`, `:unowned_off`, `:forecast_only`,
      `:listed`, `:with_review` — the tracking card's states.

  ## Fudged data

  Image URLs are intentionally absent — `image_url/2` always builds a
  `/media-images/<content_url>` path that our placeholder image server
  can't satisfy in storybook, so the hero falls back to its built-in
  placeholder and episode thumbnails render as `bg-base-300/30`
  rectangles. Showcase-style titles only — "Sample Movie", "Quiet Sample
  Series", and the like.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Library.{Person, WatchedFile}
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library
  alias MediaCentaurWeb.Components.Title.Logic, as: TitleLogic
  alias MediaCentaurWeb.Components.Title.ModalState
  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.SeasonView
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  @today ~D[2026-08-03]

  def function, do: &MediaCentaurWeb.Components.DetailPanel.detail_panel/1
  def render_source, do: :function

  # The detail panel is naturally tall and wide — one column shows the
  # production layout end-to-end.
  def layout, do: :one_column

  # Each variation renders a real `position: fixed` overlay, so they would
  # otherwise stack in a shared DOM and only the last would be visible.
  # Iframing isolates them.
  def container, do: {:iframe, style: "min-height: 720px; width: 100%;"}

  def variations do
    [closed_variation() | Enum.map(open_variations(), &closable/1)]
  end

  # Closing a variation drops its detail, which renders the closed shell.
  defp closable(%Variation{id: id, attributes: attributes} = variation) do
    %{variation | attributes: Map.merge(%{today: @today, on_close: close_event(id)}, attributes)}
  end

  defp close_event(variation_id) do
    {:eval,
     ~s|Phoenix.LiveView.JS.push("psb-assign", value: %{variation_id: #{inspect(variation_id)}, detail: nil})|}
  end

  defp closed_variation do
    %Variation{
      id: :closed,
      description:
        "Closed state — the modal shell is in the DOM but visually hidden via " <>
          "`data-state=\"closed\"`, keeping the blur compositing layer warm.",
      attributes: %{today: @today, detail: nil}
    }
  end

  defp open_variations, do: owned_variations() ++ unowned_variations()

  # ===================================================================
  # Owned titles — the library half
  # ===================================================================

  defp owned_variations do
    [
      %Variation{
        id: :movie_basic,
        description:
          "A bare movie the library owns, never watched, storage available. " <>
            "Simplest path through the action row (just Play), the hairline at " <>
            "zero, no body (content-fit panel).",
        attributes: %{detail: movie_detail()}
      },
      %Variation{
        id: :movie_reviewed,
        description:
          "The same movie two friends reviewed: the pennants fly from the hero's " <>
            "right edge under the actions, love above like, the like body dark glass.",
        attributes: %{
          detail:
            movie_detail(%{
              tracking: tracking(%{}),
              friend_activity: [
                act(603, :movie, "Other Friend", :review, :like),
                act(603, :movie, "Sample Friend", :review, :love)
              ]
            })
        }
      },
      %Variation{
        id: :movie_with_progress,
        description:
          "Same movie, mid-watch — the hairline at half, the CTA flips to **Resume**, " <>
            "and the time left displaces the status on the metadata line (UIDR-024).",
        attributes: %{detail: movie_detail(%{}, movie_progress())}
      },
      %Variation{
        id: :tv_series_all_collapsed,
        description:
          "Every season collapsed to its header row — the **completed-series** " <>
            "state, where there is no next episode and the rows serve as a compact " <>
            "rewatch index. Play controls left, synopsis right, hairline on the " <>
            "hero's bottom edge.",
        attributes: %{detail: series_detail(), state: ModalState.new(:main)}
      },
      %Variation{
        id: :tv_series_with_seasons,
        description:
          "A series with two seasons, season 1 expanded into dense one-line episode " <>
            "rows + a missing-episode placeholder for the gap at episode 4. Season 2 " <>
            "stays collapsed. The CTA reads **Resume Episode 2**. The tracking card " <>
            "under the list at Grab, with the calendar's dates.",
        attributes: %{detail: series_detail(), state: series_state()}
      },
      %Variation{
        id: :tv_series_gap_in_flight,
        description:
          "Same shape with the gap claimed: an InFlight row reading \"Downloading\", " <>
            "not clickable, not focusable — an active pursuit already has the episode.",
        attributes: %{detail: series_detail(seasons: gap_in_flight_seasons()), state: series_state()}
      },
      %Variation{
        id: :tv_series_acquisition_off,
        description:
          "Same shape with `acquisition?: false`: the missing-episode row is inert " <>
            "and \"Download more of this show\" is absent — the gate for an install " <>
            "with no indexer or download client configured.",
        attributes: %{detail: series_detail(detail: %{acquisition?: false}), state: series_state()}
      },
      %Variation{
        id: :tv_series_episode_details_open,
        description:
          "Same shape with episode 3's disclosure open — the dense row grows an " <>
            "inline synopsis + thumbnail block beneath it.",
        attributes: %{
          detail: series_detail(),
          state: %{
            series_state()
            | expanded_item_details: MapSet.new(["33333333-3333-3333-3333-3333000s01e03"])
          }
        }
      },
      %Variation{
        id: :tv_series_all_episode_details_open,
        description:
          "Same shape with the list-level episode-details toggle on — every episode " <>
            "row in the expanded season grows its block, and the toggle reads **Hide details**.",
        attributes: %{detail: series_detail(), state: %{series_state() | all_episode_details_open: true}}
      },
      %Variation{
        id: :tv_series_spoiler_free,
        description:
          "Same shape with `spoiler_free`: unwatched episodes blur their titles; " <>
            "the leading number stays legible; watched and current rows render clear.",
        attributes: %{detail: series_detail(), state: series_state(), spoiler_free: true}
      },
      %Variation{
        id: :tv_series_with_upcoming_inline,
        description:
          "Three Upcoming rows mixed in: one fills the S1 gap, one extends S1, and " <>
            "a future S3 appears as its own collapsible. Date pills read \"in Xd\".",
        attributes: %{
          detail: series_detail(seasons: upcoming_seasons()),
          state: ModalState.new(:main, MapSet.new([1, 3]))
        }
      },
      %Variation{
        id: :tv_series_aired_not_in_library,
        description:
          "One Missing row carrying a past air date and a title — the calendar " <>
            "knows the episode aired and no file was imported: an \"aired Xd ago\" " <>
            "pill, and the row is actionable.",
        attributes: %{
          detail: series_detail(seasons: aired_not_in_library_seasons()),
          state: series_state()
        }
      },
      %Variation{
        id: :tv_series_only_future,
        description:
          "Library has one minimal season; releases project a synthetic future " <>
            "Season 2 whose header omits the watched-count copy.",
        attributes: %{detail: only_future_detail(), state: series_state()}
      },
      %Variation{
        id: :tv_series_untracked,
        description:
          "Same library shape but `tracking: nil` at Grab: the switches without a " <>
            "calendar readout beside them.",
        attributes: %{detail: series_detail(detail: %{tracking: nil}), state: series_state()}
      },
      %Variation{
        id: :tv_series_off,
        description:
          "An owned series nobody follows: no tracking card at all under the " <>
            "seasons — listing comes first (UIDR-039).",
        attributes: %{detail: series_detail(detail: %{tracking: nil, rung: nil}), state: series_state()}
      },
      %Variation{
        id: :movie_series,
        description:
          "The movie-first collection modal (UIDR-023): the selected member (movie 2, " <>
            "in progress) renders the standalone-movie panel — member synopsis, " <>
            "**Resume** with the member's own hairline fraction and Watched toggle — " <>
            "over the poster rail: watched check on movie 1, progress underline on " <>
            "the lit movie 2, dimmed movie 3.",
        attributes: %{detail: collection_detail()}
      },
      %Variation{
        id: :movie_series_with_upcoming,
        description:
          "A tracked collection's announced fourth part renders as a muted, " <>
            "unpickable rail tile with the air-date pill.",
        attributes: %{detail: collection_detail(upcoming: true)}
      },
      %Variation{
        id: :info_view_with_files,
        description:
          "Manage (`view: :info`) swaps the content list for the Manage sheet: " <>
            "toolbar card (Delete all / Rematch / Refresh artwork, external IDs + " <>
            "UUID) over the folder ledger. Three files ≤ the auto-expand threshold, " <>
            "so every group opens.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_detail_files()}),
          state: ModalState.new(:info)
        }
      },
      %Variation{
        id: :info_view_files_loading,
        description:
          "The Manage sheet while the deferred file-info load is still running " <>
            "— a status line where the ledger will be, no Delete all.",
        attributes: %{detail: movie_detail(%{}, nil, :loading), state: ModalState.new(:info)}
      },
      %Variation{
        id: :info_view_files_failed,
        description:
          "The Manage sheet after the file-info load crashed — the panel says " <>
            "so rather than rendering an empty inventory as fact.",
        attributes: %{detail: movie_detail(%{}, nil, :failed), state: ModalState.new(:info)}
      },
      %Variation{
        id: :info_view_collapsed_ledger,
        description:
          "A large inventory (8 files, two folders — above the auto-expand " <>
            "threshold) rests as collapsed folder summary rows. Zero file rows at rest.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_season_detail_files()}),
          state: ModalState.new(:info)
        }
      },
      %Variation{
        id: :rematch_confirm,
        description:
          "`rematch_confirm` — the **Rematch** action in the toolbar card flips to " <>
            "its confirm prompt.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_detail_files()}),
          state: %{ModalState.new(:info) | rematch_confirm: true}
        }
      },
      %Variation{
        id: :delete_pending_all_inline,
        description:
          "`delete_confirm: :all` — the prominent danger button reads **Click again " <>
            "to confirm — Delete all files (size)** with an inline Cancel beside it.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_detail_files()}),
          state: %{ModalState.new(:info) | delete_confirm: :all}
        }
      },
      %Variation{
        id: :delete_pending_file_inline,
        description:
          "`delete_confirm: {:file, path}` targeting one row: the danger tint, a " <>
            "thin error ring, and the trash button widens to **Click to confirm**.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_detail_files()}),
          state: %{
            ModalState.new(:info)
            | delete_confirm: {:file, "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv"}
          }
        }
      },
      %Variation{
        id: :delete_in_flight_all,
        description:
          "`deleting: :all` — the async delete is running: the danger button reads " <>
            "**Deleting…** and every delete button on the panel is disabled.",
        attributes: %{
          detail: movie_detail(%{}, nil, {:ok, sample_detail_files()}),
          state: %{ModalState.new(:info) | deleting: :all}
        }
      },
      %Variation{
        id: :tv_series_cast_view,
        description: "Cast (`view: :cast`) on a series — the aggregate-cast grid alone.",
        attributes: %{detail: series_detail(), state: ModalState.new(:cast)}
      },
      %Variation{
        id: :offline,
        description:
          "Storage offline and TMDB not configured: the play CTA collapses to the " <>
            "disabled **Offline** pill, thumbnails become quiet placeholders, and " <>
            "Manage's Rematch is replaced by the \"needs TMDB\" hint.",
        attributes: %{
          detail: series_detail(available: false, files: {:ok, []}),
          state: ModalState.new(:info),
          tmdb_ready: false
        }
      }
    ]
  end

  # ===================================================================
  # Unowned titles — the former title modal's states
  # ===================================================================

  defp unowned_variations do
    [
      %Variation{
        id: :dressed,
        description:
          "The live TMDB preview has landed: tagline in the lockup, the preview's " <>
            "metadata row and overview above the action row. Backdrop and logo are " <>
            "hotlinked from TMDB in the app; nil here pins the frame's placeholder.",
        attributes: %{detail: unowned(movie(), %{preview: preview(movie())})}
      },
      %Variation{
        id: :movie_download,
        description:
          "A released movie with an indexer: Download, the bookmark, and nothing under the hero.",
        attributes: %{detail: unowned(movie(), %{})}
      },
      %Variation{
        id: :series_split,
        description:
          "A series: the split Download (main segment = the default planning mode, " <>
            "chevron for the other) and the scope select beside it, on Season 1.",
        attributes: %{detail: unowned(show(), %{})}
      },
      %Variation{
        id: :series_mode_menu_open,
        description: "The mode menu open: manual selection is the default, so it offers auto-select.",
        attributes: %{detail: unowned(show(), %{}), state: %{ModalState.new() | open_menu: :mode}}
      },
      %Variation{
        id: :series_auto_default,
        description: "Auto-select as the default: the menu offers manual selection instead.",
        attributes: %{
          detail: unowned(show(), %{planning_mode: :auto_select_best_release}),
          state: %{ModalState.new() | open_menu: :mode}
        }
      },
      %Variation{
        id: :series_scope_menu_open,
        description: "The scope menu open, Season 1 active, All seasons on offer.",
        attributes: %{detail: unowned(show(), %{}), state: %{ModalState.new() | open_menu: :scope}}
      },
      %Variation{
        id: :series_all_seasons,
        description: "All seasons chosen: the select shows it; nothing else moves.",
        attributes: %{
          detail: unowned(show(), %{}),
          state: %{ModalState.new() | download_scope: :everything}
        }
      },
      %Variation{
        id: :series_planning,
        description: "A manual plan is being created: the split is disabled and reads Planning…",
        attributes: %{
          detail: unowned(show(), %{}),
          state: %{ModalState.new() | pending: {:download, "Sample Show"}}
        }
      },
      %Variation{
        id: :from_friend,
        description:
          "Opened from a friend's review: the love pennant on the mast says who, " <>
            "and their note — the one thing a pennant cannot hold — leads the prose, attributed.",
        attributes: %{
          detail:
            unowned(movie(), %{
              activity:
                act(
                  777,
                  :movie,
                  "Sample Friend",
                  :review,
                  :love,
                  "Watch it before anyone spoils the ending."
                ),
              rung: :follow,
              friend_activity: [act(777, :movie, "Sample Friend", :review, :love)]
            })
        }
      },
      %Variation{
        id: :every_flag,
        description:
          "Friends did everything: the pennants stack on the hero's right edge under the " <>
            "actions — love, like, watched, listing — the neutral bodies dark glass over the art.",
        attributes: %{
          detail:
            unowned(show(), %{
              rung: :follow,
              release_mode_available: false,
              friend_activity: [
                act(42, :tv_series, "Third Friend", :listing),
                act(42, :tv_series, "Other Friend", :watched),
                act(42, :tv_series, "Other Friend", :review),
                act(42, :tv_series, "Sample Friend", :review, :love)
              ]
            })
        }
      },
      %Variation{
        id: :own_note,
        description: "Your own watchlist note, unattributed, above the overview.",
        attributes: %{
          detail: unowned(movie(), %{rung: :list, intent_note: "Pick this for the long weekend."})
        }
      },
      %Variation{
        id: :own_review,
        description:
          "Opened from the You card: your own review flies You and carries " <>
            "Delete review at the row's far end.",
        attributes: %{
          detail:
            unowned(movie(), %{
              activity: act(777, :movie, nil, :review),
              friend_activity: [act(777, :movie, nil, :review)]
            })
        }
      },
      %Variation{
        id: :own_listing,
        description:
          "Opened from the You card: an own listing broadcast carries Delete listing. " <>
            "It flies no pennant — a pennant tells you what friends did.",
        attributes: %{
          detail:
            unowned(show(), %{
              activity: act(42, :tv_series, nil, :listing),
              release_mode_available: false
            })
        }
      },
      %Variation{
        id: :needs_review,
        description: "A parked plan: Needs review links to Incoming.",
        attributes: %{detail: unowned(movie(), %{acquisition_state: :needs_review})}
      },
      %Variation{
        id: :downloading,
        description: "A pursuit in flight: a stated fact, no verb.",
        attributes: %{detail: unowned(movie(), %{acquisition_state: :downloading})}
      },
      %Variation{
        id: :not_out_yet,
        description:
          "Not out yet (or no indexer): no primary verb — the tracking switches " <>
            "below are the act once the title is listed.",
        attributes: %{detail: unowned(movie(), %{release_mode_available: false})}
      },
      %Variation{
        id: :tracked_watch,
        description:
          "A watchlisted series armed at Follow: the tracking card under the hero " <>
            "with the switches and the calendar's dates.",
        attributes: %{
          detail:
            unowned(show(), %{release_mode_available: false, rung: :follow, tracking: tracking(%{})})
        }
      },
      %Variation{
        id: :tracked_grab,
        description:
          "Armed at Grab with the per-title quality acceptance set: the acceptance " <>
            "row follows the switches.",
        attributes: %{
          detail:
            unowned(show(), %{
              release_mode_available: false,
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
        id: :unowned_off,
        description:
          "A title with no record: the row's bookmark is empty and there is no " <>
            "tracking card at all — listing comes first (UIDR-039).",
        attributes: %{
          detail: unowned(show(), %{release_mode_available: false, rung: nil, tracking: nil})
        }
      },
      %Variation{
        id: :forecast_only,
        description:
          "Acquisition not configured: the rows stay, and the note says nothing " <>
            "downloads until it is; the dates carry no grab implication.",
        attributes: %{
          detail:
            unowned(show(), %{
              release_mode_available: false,
              acquisition?: false,
              rung: :grab,
              tracking: tracking(%{})
            })
        }
      },
      %Variation{
        id: :listed,
        description:
          "On the list: the bookmark is filled and the tracking switches appear " <>
            "under the hero.",
        attributes: %{detail: unowned(movie(), %{rung: :list})}
      },
      %Variation{
        id: :with_review,
        description: "Friend network on — the row offers the pencil Review.",
        attributes: %{detail: unowned(movie(), %{}), review?: true}
      }
    ]
  end

  # ===================================================================
  # Builders
  # ===================================================================

  # An owned title: the library half from a typed entry, the snapshot
  # from the subject's own metadata — the way the hosts build it.
  defp owned(entry, opts) do
    library =
      entry
      |> Library.new(Keyword.get(opts, :member_id), available: Keyword.get(opts, :available, true))
      |> Map.put(:files, Keyword.get(opts, :files, {:ok, []}))

    title = TitleLogic.snapshot_from_entity(library.subject)

    struct!(
      %TitleDetail{
        ref: title && Title.ref(title),
        title: title,
        library: library,
        rung: nil,
        acquisition?: true,
        complete?: match?(%Title{media_type: :movie}, title),
        planning_mode: :auto_select_best_release
      },
      Keyword.get(opts, :detail, %{})
    )
  end

  defp unowned(title, overrides) do
    struct!(
      %TitleDetail{
        ref: Title.ref(title),
        title: title,
        rung: nil,
        acquisition?: true,
        release_mode_available: true
      },
      overrides
    )
  end

  defp leaf(entity, progress, records) do
    %LeafDetail{entity: entity, progress: progress, progress_records: records, resume_target: nil}
  end

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

  defp act(tmdb_id, media_type, nickname, kind, sentiment \\ :like, text \\ nil) do
    %{
      activity: %Activity{
        id:
          "0d2c5cd6-0000-4000-8000-00000000000" <> Integer.to_string(:erlang.phash2({nickname, kind}, 9)),
        kind: kind,
        sentiment: sentiment,
        text: text,
        tmdb_id: tmdb_id,
        media_type: media_type,
        acted_at: ~U[2026-09-01 10:00:00Z]
      },
      nickname: nickname,
      own?: is_nil(nickname)
    }
  end

  defp preview(title) do
    %TitlePreview{
      media_type: title.media_type,
      tmdb_id: to_string(title.tmdb_id),
      title: title.name,
      tagline: "Every confirmation counts.",
      overview: title.overview,
      metadata_items: ["2010", "2h 19m", "R", "US"],
      facets: [],
      cast: [
        %Person{name: "Actor One", character: "The Drifter", order: 0},
        %Person{name: "Actor Two", character: "Lighthouse Keeper", order: 1}
      ],
      in_library?: false
    }
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

  # The tracked-title half the tracking card renders: armed at the app
  # default with the next episode announced.
  defp tracking(overrides) do
    struct!(
      %TrackingDetail{
        item_id: "sample-item",
        ref: "tv_series-42",
        tracking_since: ~U[2026-03-14 12:00:00Z],
        today: @today,
        acquisition?: true,
        timeline: [
          episode("s02e05", 2, 5, @today, :upcoming),
          episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming),
          episode("s02e04", 2, 4, ~D[2026-07-27], :in_library)
        ]
      },
      overrides
    )
  end

  # --- Movie fixture ----------------------------------------------------

  @movie_id "11111111-1111-1111-1111-111111111111"

  defp movie_detail(overrides \\ %{}, progress \\ nil, files \\ {:ok, []}) do
    records = if progress, do: [movie_progress_record(@movie_id)], else: []
    owned(leaf(sample_movie_entity(), progress, records), files: files, detail: overrides)
  end

  defp movie_progress do
    %{
      current_episode: nil,
      episode_position_seconds: 1800.0,
      episode_duration_seconds: 5400.0,
      episodes_completed: 0,
      episodes_total: 1
    }
  end

  defp sample_movie_entity do
    struct!(EntityView,
      id: @movie_id,
      type: :movie,
      name: "A Sample Silent Picture",
      description:
        "An ordinary morning unspools into a series of small, surprising tableaux. " <>
          "A demonstration entity — descriptions render under the metadata row.",
      tagline: "Look closer.",
      date_published: ~D[1922-09-04],
      duration_seconds: 5400,
      director: "Sample Director",
      content_rating: "PG",
      number_of_seasons: nil,
      aggregate_rating_value: 7.4,
      vote_count: 1284,
      original_language: "en",
      studio: "Public Domain Pictures",
      country_code: "US",
      network: nil,
      status: :released,
      genres: ["Drama", "Comedy"],
      images: [],
      external_ids: [
        %{source: "imdb", external_id: "tt0000000"},
        %{source: "tmdb", external_id: "1001"}
      ],
      imdb_id: "tt0000000",
      tmdb_id: "1001",
      extras: [],
      seasons: [],
      movies: [],
      watched_files: [],
      url: "https://example.invalid/movies/sample",
      content_url: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv",
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    )
  end

  # Plain-map progress records mirror `MediaCentaur.Library.WatchProgress`
  # — all three foreign keys included with explicit `nil` for the unused
  # ones, since the consuming code does `record.episode_id`.
  defp movie_progress_record(movie_id) do
    %{
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      movie_id: movie_id,
      episode_id: nil,
      video_object_id: nil,
      position_seconds: 1800.0,
      duration_seconds: 5400.0,
      completed: false,
      last_watched_at: ~U[2026-04-30 22:15:00Z]
    }
  end

  # --- TV series fixture -----------------------------------------------

  @tv_id "22222222-2222-2222-2222-222222222222"
  @s1_id "22222222-2222-2222-2222-22220000s001"
  @s2_id "22222222-2222-2222-2222-22220000s002"

  defp series_state, do: ModalState.new(:main, MapSet.new([1]))

  defp series_detail(opts \\ []) do
    entity = Keyword.get(opts, :entity, sample_tv_entity())
    records = sample_tv_progress_records(entity)

    seasons =
      Keyword.get_lazy(opts, :seasons, fn -> build_library_only_seasons_view(entity, records, {1, 2}) end)

    entry = %SeriesDetail{
      entity: entity,
      progress: %{
        current_episode: %{season: 1, episode: 2},
        episode_position_seconds: 600.0,
        episode_duration_seconds: 1500.0,
        episodes_completed: 1,
        episodes_total: 8
      },
      progress_records: records,
      seasons: seasons,
      extras: [],
      resume_target: nil,
      releases: [],
      claimed_units: MapSet.new()
    }

    detail = Map.merge(%{tracking: tracking(%{}), rung: :grab}, Keyword.get(opts, :detail, %{}))
    owned(entry, Keyword.merge([detail: detail], Keyword.take(opts, [:available, :files])))
  end

  # S1 has releases for the missing slot (episode 4, replaces the
  # Missing) and one episode beyond number_of_episodes (episode 6). A
  # future season (S3) appears as its own collapsible.
  defp upcoming_seasons do
    entity = sample_tv_entity()

    [s1_view, s2_view] =
      build_library_only_seasons_view(entity, sample_tv_progress_records(entity), {1, 2})

    new_items =
      Enum.map(s1_view.items, fn
        %EpisodeRow.Missing{episode_number: 4} ->
          %EpisodeRow.Upcoming{
            season_number: 1,
            episode_number: 4,
            title: "The Far Hike",
            air_date: Date.add(Date.utc_today(), 7)
          }

        other ->
          other
      end) ++
        [
          %EpisodeRow.Upcoming{
            season_number: 1,
            episode_number: 6,
            title: "After the Snow",
            air_date: Date.add(Date.utc_today(), 21)
          }
        ]

    s3_future = %SeasonView{
      season_number: 3,
      name: nil,
      kind: :future,
      items: [
        %EpisodeRow.Upcoming{
          season_number: 3,
          episode_number: 1,
          title: "Spring Returns",
          air_date: Date.add(Date.utc_today(), 60)
        },
        %EpisodeRow.Upcoming{
          season_number: 3,
          episode_number: 2,
          title: "An Old Letter",
          air_date: Date.add(Date.utc_today(), 67)
        }
      ],
      extras: [],
      watched_count: nil,
      total_count: 2
    }

    [%{s1_view | items: new_items}, s2_view, s3_future]
  end

  defp gap_in_flight_seasons do
    entity = sample_tv_entity()

    [s1_view, s2_view] =
      build_library_only_seasons_view(entity, sample_tv_progress_records(entity), {1, 2})

    items =
      Enum.map(s1_view.items, fn
        %EpisodeRow.Missing{episode_number: 4} = row ->
          %EpisodeRow.InFlight{
            season_number: row.season_number,
            episode_number: row.episode_number,
            title: row.title,
            air_date: row.air_date
          }

        other ->
          other
      end)

    [%{s1_view | items: items}, s2_view]
  end

  defp aired_not_in_library_seasons do
    entity = sample_tv_entity()

    [s1_view, s2_view] =
      build_library_only_seasons_view(entity, sample_tv_progress_records(entity), {1, 2})

    items =
      Enum.map(s1_view.items, fn
        %EpisodeRow.Missing{episode_number: 4} ->
          %EpisodeRow.Missing{
            season_number: 1,
            episode_number: 4,
            title: "The Quiet Hour",
            air_date: Date.add(Date.utc_today(), -3)
          }

        other ->
          other
      end)

    [%{s1_view | items: items}, s2_view]
  end

  defp only_future_detail do
    entity =
      sample_tv_entity()
      |> Map.put(:seasons, [])
      |> Map.put(:number_of_seasons, 1)

    s1_future = %SeasonView{
      season_number: 1,
      name: nil,
      kind: :future,
      items: [
        %EpisodeRow.Upcoming{
          season_number: 1,
          episode_number: 1,
          title: "Pilot",
          air_date: Date.add(Date.utc_today(), 14)
        },
        %EpisodeRow.Upcoming{
          season_number: 1,
          episode_number: 2,
          title: "The Letter",
          air_date: Date.add(Date.utc_today(), 21)
        }
      ],
      extras: [],
      watched_count: nil,
      total_count: 2
    }

    entry = %SeriesDetail{
      entity: entity,
      progress: nil,
      progress_records: [],
      seasons: [s1_future],
      extras: [],
      resume_target: nil,
      releases: [],
      claimed_units: MapSet.new()
    }

    owned(entry, detail: %{tracking: tracking(%{}), rung: :follow})
  end

  defp sample_tv_progress_records(entity) do
    season_one_episodes = entity.seasons |> Enum.at(0) |> Map.get(:episodes)
    [ep1, ep2 | _] = season_one_episodes

    [
      %{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01",
        movie_id: nil,
        episode_id: ep1.id,
        video_object_id: nil,
        position_seconds: 0.0,
        duration_seconds: 1500.0,
        completed: true,
        last_watched_at: ~U[2026-04-28 21:00:00Z]
      },
      %{
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02",
        movie_id: nil,
        episode_id: ep2.id,
        video_object_id: nil,
        position_seconds: 600.0,
        duration_seconds: 1500.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 21:30:00Z]
      }
    ]
  end

  defp build_library_only_seasons_view(entity, progress_records, resume_episode_key) do
    progress_by_episode_id =
      progress_records
      |> Enum.filter(& &1.episode_id)
      |> Map.new(&{&1.episode_id, &1})

    Enum.map(entity.seasons, fn season ->
      build_library_season_view(season, progress_by_episode_id, resume_episode_key)
    end)
  end

  defp build_library_season_view(season, progress_by_episode_id, resume_episode_key) do
    items = build_library_items(season, progress_by_episode_id, resume_episode_key)
    watched = Enum.count(season.episodes, &watched?(&1, progress_by_episode_id))

    %SeasonView{
      season_number: season.season_number,
      name: season.name,
      kind: :library,
      items: items,
      extras: season.extras,
      watched_count: watched,
      total_count: max(length(season.episodes), season.number_of_episodes)
    }
  end

  defp build_library_items(season, progress_by_episode_id, resume_episode_key) do
    episode_map = Map.new(season.episodes, &{&1.episode_number, &1})
    upper = max(season.number_of_episodes, length(season.episodes))

    if upper == 0 do
      []
    else
      for n <- 1..upper do
        case Map.get(episode_map, n) do
          nil ->
            %EpisodeRow.Missing{
              season_number: season.season_number,
              episode_number: n
            }

          episode ->
            progress = Map.get(progress_by_episode_id, episode.id)

            %EpisodeRow.Library{
              episode: episode,
              season_number: season.season_number,
              progress: progress,
              state: episode_state(progress),
              is_resume_target: resume_episode_key == {season.season_number, episode.episode_number}
            }
        end
      end
    end
  end

  defp watched?(episode, progress_by_episode_id) do
    case Map.get(progress_by_episode_id, episode.id) do
      %{completed: true} -> true
      _ -> false
    end
  end

  defp episode_state(nil), do: :unwatched
  defp episode_state(%{completed: true}), do: :watched
  defp episode_state(%{position_seconds: pos}) when is_number(pos) and pos > 0.0, do: :current
  defp episode_state(_), do: :unwatched

  defp sample_tv_entity do
    struct!(EntityView,
      id: @tv_id,
      type: :tv_series,
      tmdb_id: "246810",
      name: "Quiet Sample Series",
      description:
        "An anthology of small stories from a sleepy town. Each episode " <>
          "follows a different resident through a single afternoon.",
      tagline: nil,
      date_published: ~D[1925-01-12],
      duration_seconds: nil,
      director: nil,
      content_rating: "TV-PG",
      number_of_seasons: 2,
      aggregate_rating_value: 8.1,
      vote_count: 312,
      original_language: "en",
      studio: nil,
      country_code: "US",
      network: "Public Domain Network",
      status: :ended,
      genres: ["Drama", "Anthology"],
      images: [],
      external_ids: [%{source: "tmdb", external_id: "246810"}],
      imdb_id: "tt0000200",
      cast:
        Enum.map(0..7, fn i ->
          %Person{
            name: "Sample Actor #{i + 1}",
            character: "Sample Role #{i + 1}",
            tmdb_person_id: 1000 + i,
            profile_path: nil,
            order: i
          }
        end),
      crew: [
        %Person{
          tmdb_person_id: 11,
          name: "Sample Creator A",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        },
        %Person{
          tmdb_person_id: 12,
          name: "Sample Creator B",
          job: "Creator",
          department: "Creator",
          profile_path: nil
        }
      ],
      extras: [],
      seasons: [
        sample_season(@s1_id, 1, "Season 1", 5, [
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e01",
            1,
            "The First Visit",
            "Mira returns to town after years away."
          ),
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e02",
            2,
            "Letters",
            "A bundle of unsent letters surfaces."
          ),
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e03",
            3,
            "The Mechanic",
            "An old engine is coaxed back to life."
          ),
          # Episode 4 intentionally omitted — number_of_episodes: 5 means
          # the missing-episode row fills in for it.
          sample_episode(
            "33333333-3333-3333-3333-3333000s01e05",
            5,
            "First Snow",
            "Winter arrives early."
          )
        ]),
        sample_season(@s2_id, 2, "Season 2", 3, [
          sample_episode(
            "33333333-3333-3333-3333-3333000s02e01",
            1,
            "Return",
            "A familiar face appears at the diner."
          )
        ])
      ],
      movies: [],
      watched_files: [],
      url: "https://example.invalid/tv/quiet-sample",
      content_url: nil,
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    )
  end

  # --- Movie series fixture --------------------------------------------

  @ms_id "44444444-4444-4444-4444-444444444444"

  defp collection_detail(opts \\ []) do
    entity = sample_movie_series_entity()
    [m1, m2, _m3] = entity.movies

    progress_records = [
      %{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc01",
        movie_id: m1.id,
        episode_id: nil,
        video_object_id: nil,
        position_seconds: 0.0,
        duration_seconds: 5400.0,
        completed: true,
        last_watched_at: ~U[2026-04-20 21:00:00Z]
      },
      %{
        id: "cccccccc-cccc-cccc-cccc-cccccccccc02",
        movie_id: m2.id,
        episode_id: nil,
        video_object_id: nil,
        position_seconds: 1500.0,
        duration_seconds: 5700.0,
        completed: false,
        last_watched_at: ~U[2026-04-30 22:00:00Z]
      }
    ]

    upcoming =
      if Keyword.get(opts, :upcoming, false) do
        [
          %MovieRow.Upcoming{
            part_tmdb_id: 900_004,
            title: "Sample Picture IV",
            air_date: Date.add(Date.utc_today(), 45),
            sub_status: :unaired
          }
        ]
      else
        []
      end

    entry = %CollectionDetail{
      entity: entity,
      progress: %{
        current_episode: %{season: 0, episode: 2},
        episode_position_seconds: 1500.0,
        episode_duration_seconds: 5700.0,
        episodes_completed: 1,
        episodes_total: 3
      },
      progress_records: progress_records,
      movies: movie_series_items(entity, progress_records) ++ upcoming,
      extras: [],
      resume_target: nil,
      releases: []
    }

    # The movie-first subject (UIDR-023): movie 2 selected — composed
    # through the same `Library.new/3` the live path uses.
    owned(entry, member_id: m2.id)
  end

  # Typed `MovieRow.Library` fixtures mirroring what
  # `CollectionDetail.build/3` composes: movie 1 watched, movie 2
  # current + resume target, movie 3 unwatched.
  defp movie_series_items(entity, progress_records) do
    [m1, m2, m3] = entity.movies
    [p1, p2] = progress_records

    [
      %MovieRow.Library{movie: m1, progress: p1, state: :watched, is_resume_target: false},
      %MovieRow.Library{movie: m2, progress: p2, state: :current, is_resume_target: true},
      %MovieRow.Library{movie: m3, progress: nil, state: :unwatched, is_resume_target: false}
    ]
  end

  defp sample_movie_series_entity do
    movies = [
      sample_child_movie(
        "55555555-5555-5555-5555-555555555501",
        "Sample Picture I",
        ~D[1920-05-01],
        5400,
        "/media/sample-picture-1.mkv",
        1,
        900_001,
        "The first chapter — a rumour leads three siblings into the hills."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555502",
        "Sample Picture II",
        ~D[1922-07-10],
        5700,
        "/media/sample-picture-2.mkv",
        2,
        900_002,
        "A return to the same valley, years later."
      ),
      sample_child_movie(
        "55555555-5555-5555-5555-555555555503",
        "Sample Picture III",
        ~D[1925-11-04],
        6000,
        "/media/sample-picture-3.mkv",
        3,
        900_003,
        "The valley closes its books."
      )
    ]

    struct!(EntityView,
      id: @ms_id,
      type: :movie_series,
      name: "Sample Picture Trilogy",
      description: "Three pictures, one valley.",
      tagline: nil,
      date_published: ~D[1920-05-01],
      duration_seconds: nil,
      director: nil,
      content_rating: nil,
      number_of_seasons: nil,
      aggregate_rating_value: 7.8,
      vote_count: 540,
      original_language: "en",
      studio: nil,
      country_code: "US",
      network: nil,
      status: nil,
      genres: ["Adventure", "Drama"],
      images: [],
      external_ids: [],
      extras: [],
      seasons: [],
      movies: movies,
      watched_files: [],
      url: "https://example.invalid/series/sample-trilogy",
      content_url: nil,
      watch_progress: [],
      extra_progress: [],
      inserted_at: ~U[2026-04-01 00:00:00Z],
      updated_at: ~U[2026-04-01 00:00:00Z]
    )
  end

  # --- Detail files fixture --------------------------------------------

  defp sample_detail_files do
    [
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff01",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.mkv",
          media_dir: "/media/movies"
        },
        size: 4_294_967_296
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff02",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.subtitles.srt",
          media_dir: "/media/movies"
        },
        size: 32_768
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff03",
          file_path: "/media/archive/Sample.Movie.1922.480p.legacy.mkv",
          media_dir: "/media/archive"
        },
        # `nil` size renders the "absent" badge — the file went missing
        # off disk after being indexed.
        size: nil
      }
    ]
  end

  # Eight files across two season folders — above the ledger's ≤6
  # auto-expand threshold, so the Manage sheet rests collapsed.
  defp sample_season_detail_files do
    for season <- 1..2, episode <- 1..4 do
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-fffffffff#{season}0#{episode}",
          file_path:
            "/media/tv/Sample Show/Season #{season}/Sample.Show.S0#{season}E0#{episode}.1080p.WEB-DL.mkv",
          media_dir: "/media/tv"
        },
        size: 183_500_800
      }
    end
  end

  # --- Plain-map child builders ----------------------------------------
  #
  # Episode/Season/Movie are kept as plain maps rather than schema
  # structs because the detail panel digs into nested associations
  # (`episode.images`, `movie.images`) via `image_url/2`. Schema structs
  # default those to `%Ecto.Association.NotLoaded{}`, which is truthy but
  # not enumerable. Plain maps with `images: []` sidestep that.

  defp sample_season(id, season_number, name, number_of_episodes, episodes) do
    %{
      id: id,
      season_number: season_number,
      name: name,
      number_of_episodes: number_of_episodes,
      episodes: episodes,
      extras: []
    }
  end

  defp sample_episode(id, episode_number, name, description) do
    %{
      id: id,
      episode_number: episode_number,
      name: name,
      description: description,
      duration_seconds: 1500,
      content_url: "/media/quiet-sample/episode-#{episode_number}.mkv",
      images: []
    }
  end

  defp sample_child_movie(
         id,
         name,
         date_published,
         duration_seconds,
         content_url,
         position,
         tmdb_id,
         description
       ) do
    %{
      id: id,
      name: name,
      description: description,
      date_published: date_published,
      duration_seconds: duration_seconds,
      director: "Sample Director",
      content_url: content_url,
      position: position,
      tmdb_id: tmdb_id,
      genres: ["Adventure"],
      status: :released,
      images: []
    }
  end
end
