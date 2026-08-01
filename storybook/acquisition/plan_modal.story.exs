defmodule MediaCentaurWeb.Storybook.Acquisition.PlanModal do
  @moduledoc """
  The plan-flow modal (UIDR-014): targeting picker → live coverage
  board → approval footer, one continuous URL-driven surface. The
  board's cell vocabulary — searching (dashed/pulsing), assigned
  (filled; consecutive same-release cells fuse into a capsule), unfound
  (amber hollow) — is the same language the pursuit card's segmented
  progress and the UnitBoard drill-down speak.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.DescentNarrative
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaur.Library.Person
  alias MediaCentaur.ReleaseTracking.TitleResult
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaurWeb.IncomingLive.MoviePreview
  alias MediaCentaurWeb.Components.Detail.Facet

  def function, do: &MediaCentaurWeb.Components.Acquisition.PlanModal.plan_modal/1
  def render_source, do: :function

  # A self-contained gradient standing in for a TMDB backdrop — the
  # shell's cinematic layer demonstrated without hotlinking artwork.
  @sample_backdrop "data:image/svg+xml;utf8," <>
                     "<svg xmlns='http://www.w3.org/2000/svg' width='1280' height='720'>" <>
                     "<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>" <>
                     "<stop offset='0' stop-color='%232b3a5c'/>" <>
                     "<stop offset='1' stop-color='%230d1017'/></linearGradient></defs>" <>
                     "<rect width='1280' height='720' fill='url(%23g)'/></svg>"

  def variations do
    [
      %Variation{
        id: :loading,
        description:
          "Loading, already dressed — the picked search result's identity (title, poster, " <>
            "backdrop) paints immediately; TMDB detail fills in behind it. No gray box.",
        attributes: %{
          open: true,
          stage: :loading,
          backdrop_url: @sample_backdrop,
          identity: %TitleResult{
            tmdb_id: 246_810,
            media_type: :tv_series,
            name: "Sample Show",
            year: "2008",
            poster_path: nil
          }
        }
      },
      %Variation{
        id: :loading_bare,
        description:
          "Loading with nothing in hand (a shared / refreshed plan link) — the scrim-only " <>
            "shell and the spinner line.",
        attributes: %{open: true, stage: :loading}
      },
      %Variation{
        id: :targeting,
        description:
          "The picker wearing the series backdrop (UIDR-014 — the TV path gets the same " <>
            "cinematic shell as the movie confirm). Quick-action presets, tri-state season " <>
            "rows collapsed by default; season 1 expanded showing the episode drill-in: the " <>
            "in-library row greyed (shown, never hidden), the unaired row inert. The footer " <>
            "carries Track only (follow future releases, download nothing) for an untracked " <>
            "series — the retired Track modal's verb, re-homed.",
        attributes: %{
          open: true,
          stage: :targeting,
          backdrop_url: @sample_backdrop,
          selection: selection(),
          chosen: {:eval, ~s|MapSet.new([{1, 2}, {1, 3}, {2, 1}])|},
          expanded_seasons: {:eval, ~s|MapSet.new([1])|}
        }
      },
      %Variation{
        id: :targeting_no_artwork,
        description:
          "The picker when TMDB has no backdrop — the scrim-only shell; poster thumb and " <>
            "title carry the identity.",
        attributes: %{
          open: true,
          stage: :targeting,
          selection: selection(),
          chosen: {:eval, ~s|MapSet.new([{1, 2}])|},
          expanded_seasons: {:eval, ~s|MapSet.new()|}
        }
      },
      %Variation{
        id: :movie_confirm,
        description:
          "The movie fast path, now a detail-page-shaped preview so the pick reads as \"of\" " <>
            "that movie: hero (backdrop + logo, both rendered live from TMDB in the app — nil " <>
            "here pins the title fallback + film-icon frame), metadata row, overview, the same " <>
            "facet strip the owned detail panel shows (director, rating, language, studio, " <>
            "genres), and a top-cast strip. The footer: Cancel · Track release (follow the " <>
            "movie's release without grabbing — the retired Track modal's verb) · Plan it.",
        attributes: %{
          open: true,
          stage: :movie_confirm,
          movie: %MoviePreview{
            tmdb_id: "777",
            title: "Sample Movie",
            tagline: "Every confirmation counts.",
            overview:
              "A drifter arrives in a coastal town the day the lighthouse goes dark and " <>
                "finds every clock stopped at the same minute — confirming you picked the " <>
                "right Sample Movie is exactly what this preview is for.",
            backdrop_url: nil,
            logo_url: nil,
            poster_url: nil,
            metadata_items: ["2010", "2h 19m", "R", "US"],
            facets: [
              Facet.text("Director", "Jane Director"),
              Facet.rating("Rating", 8.2, 26_000),
              Facet.text("Original language", "en"),
              Facet.text("Studio", "Sample Studio"),
              Facet.chips("Genres", ["Drama", "Mystery"])
            ],
            cast: [
              %Person{name: "Actor One", character: "The Drifter", order: 0},
              %Person{name: "Actor Two", character: "Lighthouse Keeper", order: 1},
              %Person{name: "Actor Three", character: "Sheriff", order: 2},
              %Person{name: "Actor Four", character: "Diner Owner", order: 3}
            ],
            in_library?: false
          }
        }
      },
      %Variation{
        id: :movie_confirm_sparse,
        description:
          "The same stage when TMDB has nothing beyond the title — no artwork, no facts, no " <>
            "cast; just the title over the film-icon frame, and the already-in-library state " <>
            "disabling the CTA.",
        attributes: %{
          open: true,
          stage: :movie_confirm,
          movie: %MoviePreview{
            tmdb_id: "778",
            title: "Sample Movie",
            in_library?: true
          }
        }
      },
      %Variation{
        id: :board_planning,
        description:
          "Mid-flight — the expectation panel narrates the descent (done/active/pending rungs), dashed searching cells, the activity ticker, no spinner-only state.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:planning),
          descent: %DescentNarrative.View{
            headline: "Now searching season packs — 2 episodes still need coverage…",
            rows: [
              %DescentNarrative.Row{
                id: :series,
                state: :done,
                label: "Complete series",
                detail: "nothing usable found"
              },
              %DescentNarrative.Row{
                id: :seasons,
                state: :active,
                label: "Season packs",
                detail: "searching — 4 terms…"
              },
              %DescentNarrative.Row{
                id: :episodes,
                state: :pending,
                label: "Individual episodes",
                detail: "single episodes, only for what's still missing"
              }
            ]
          },
          last_activity: "Sample Show S01E03 — 2 known (corpus)"
        }
      },
      %Variation{
        id: :board_ready,
        description:
          "Ready — the shell keeps the title's backdrop through the board (no themed → plain " <>
            "regression mid-flow); the season pack fused into one capsule, a single covering " <>
            "the stray episode, an explicit gap row, the approval footer.",
        attributes: %{
          open: true,
          stage: :board,
          backdrop_url: @sample_backdrop,
          board: board(:ready),
          last_activity: "9 searches · 6 from corpus"
        }
      },
      %Variation{
        id: :board_gaps_search_blind,
        description:
          "The gap search ran while search was blind (every enabled indexer backed off, " <>
            "UIDR-016) — the banner says availability couldn't be checked instead of " <>
            "presenting \"not available\" as knowledge. Search again stays; Track these " <>
            "later stops reading as an informed conclusion.",
        attributes: %{
          open: true,
          stage: :board,
          backdrop_url: @sample_backdrop,
          board: board(:blind_gap),
          search_health: %IndexerHealth{
            state: :blind,
            checked_at: ~U[2026-08-01 00:00:00Z],
            retry_at: ~U[2026-08-01 00:25:00Z],
            enabled_count: 1,
            backed_off: [%{name: "Indexer A", retry_at: ~U[2026-08-01 00:25:00Z]}]
          },
          last_activity: "Searched: Sample Movie — couldn't reach any indexer"
        }
      },
      %Variation{
        id: :board_long_season,
        description:
          "A 26-episode season fused into one capsule — the capsule wraps inside the modal instead of overflowing it.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:long_season),
          last_activity: "3 searches · all from corpus"
        }
      },
      %Variation{
        id: :board_alternatives_open,
        description:
          "The swap picker — corpus alternatives under the release row: clean candidates first, bait-pattern titles flagged ('looks fake') but choosable; exclude-and-re-solve and re-search as the escape hatches.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:ready),
          alternatives: %{
            unit_id: "story-unit-1-1",
            items: [
              %PlanBoard.Alternative{
                guid: "alt-uhd",
                title: "Sample.Show.S01.2160p.WEB-DL.x265-GROUP",
                scope_label: "Season 1 pack",
                quality: "4K",
                seeders: 12,
                size_bytes: 28_000_000_000
              },
              %PlanBoard.Alternative{
                guid: "alt-single",
                title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 41,
                size_bytes: 2_100_000_000
              },
              %PlanBoard.Alternative{
                guid: "alt-evil",
                title: "Sample.Show.S01E01.1080p.HD.X264.1080p.exe",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 999,
                size_bytes: 4_000_000,
                suspicious?: true
              }
            ]
          },
          last_activity: "9 searches · 6 from corpus"
        }
      },
      %Variation{
        id: :board_alternatives_searching,
        description:
          "Find-more in flight — the button shows progress and ignores clicks; already-known candidates stay put.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:ready),
          alternatives: %{
            unit_id: "story-unit-1-1",
            searching?: true,
            items: [
              %PlanBoard.Alternative{
                guid: "alt-single",
                title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 41,
                size_bytes: 2_100_000_000
              }
            ]
          },
          last_activity: "Searched: Sample Show S01E01 — 1 found"
        }
      },
      %Variation{
        id: :board_overlap,
        description:
          "Duplicate-data warning — a swap-picker choice left a broad pack physically containing episodes now assigned elsewhere; the CTA excludes the container and re-solves. Each release row also carries the ✕ remove affordance.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:overlap),
          last_activity: "9 searches · 6 from corpus"
        }
      },
      %Variation{
        id: :board_offer,
        description:
          "Fit-gated offer — no right-sized release for the wanted episode; the only thing covering it is an over-broad season pack, surfaced as an explicit one-click over-grab rather than auto-grabbed.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:offer),
          last_activity: "11 searches · 8 from corpus"
        }
      },
      %Variation{
        id: :board_below_floor,
        description:
          "Below-floor offer (movie) — genuine releases exist but all sit below the quality " <>
            "preference, so instead of a bare \"not available\" gap the board says what exists " <>
            "and offers the picker. Grabbing one is an explicit per-title override.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:below_floor),
          last_activity: "2 searches · 62 results, none matching your quality preference"
        }
      },
      %Variation{
        id: :board_below_floor_open,
        description:
          "The below-floor picker open — known-lower candidates badge their real resolution " <>
            "(720p, DVD), an unlabeled release badges \"Quality unknown\"; no exclude-current " <>
            "verb because nothing is assigned yet.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:below_floor),
          alternatives: %{
            unit_id: "story-unit-movie",
            items: [
              %PlanBoard.Alternative{
                guid: "bf-720p",
                title: "Sample.Movie.2005.720p.WEBRip.x264-GROUP",
                scope_label: nil,
                quality: "720p",
                seeders: 9,
                size_bytes: 1_400_000_000
              },
              %PlanBoard.Alternative{
                guid: "bf-dvd",
                title: "Sample.Movie.2005.DVDRip.x264-GROUP",
                scope_label: nil,
                quality: "DVD",
                seeders: 4,
                size_bytes: 700_000_000
              },
              %PlanBoard.Alternative{
                guid: "bf-unlabeled",
                title: "Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264",
                scope_label: nil,
                quality: nil,
                seeders: 2,
                size_bytes: 1_000_000_000
              }
            ]
          },
          last_activity: "2 searches · 62 results, none matching your quality preference"
        }
      },
      %Variation{
        id: :error,
        description: "Targeting failed — honest dead end, one way out.",
        attributes: %{
          open: true,
          stage: :error,
          error: "Couldn't load this title from TMDB."
        }
      }
    ]
  end

  # --- fixtures -------------------------------------------------------------

  defp selection do
    %Targeting.Selection{
      tmdb_id: "246810",
      title: "Sample Show",
      tracked?: true,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes: [
            episode(1, 1, "Pilot", in_library?: true),
            episode(1, 2, "Earthfall", []),
            episode(1, 3, "The Signal", [])
          ]
        },
        %Targeting.Season{
          season_number: 2,
          episodes: [
            episode(2, 1, "Return", []),
            episode(2, 2, "Finale", aired?: false)
          ]
        }
      ]
    }
  end

  defp episode(season, number, label, opts) do
    %Targeting.Episode{
      season_number: season,
      episode_number: number,
      label: label,
      air_date: ~D[2020-01-01],
      aired?: Keyword.get(opts, :aired?, true),
      in_library?: Keyword.get(opts, :in_library?, false)
    }
  end

  defp board(:planning) do
    %PlanBoard{
      plan_id: "story-plan",
      title: "Sample Show",
      status: :planning,
      wanted: 4,
      covered: 2,
      seasons: [
        %PlanBoard.SeasonRow{
          season_number: 1,
          cells: [
            cell(1, 1, :assigned, "pack"),
            cell(1, 2, :assigned, "pack"),
            cell(1, 3, :searching, nil)
          ]
        },
        %PlanBoard.SeasonRow{season_number: 2, cells: [cell(2, 1, :searching, nil)]}
      ],
      releases: [release("pack", "Season 1 pack", 2)],
      gaps: [],
      total_size_bytes: 6_200_000_000
    }
  end

  defp board(:ready) do
    %PlanBoard{
      plan_id: "story-plan",
      title: "Sample Show",
      status: :ready,
      wanted: 4,
      covered: 3,
      seasons: [
        %PlanBoard.SeasonRow{
          season_number: 1,
          cells: [
            cell(1, 1, :assigned, "pack"),
            cell(1, 2, :assigned, "pack"),
            cell(1, 3, :assigned, "pack")
          ]
        },
        %PlanBoard.SeasonRow{
          season_number: 2,
          cells: [cell(2, 1, :assigned, "single"), cell(2, 2, :unfound, nil)]
        }
      ],
      releases: [
        release("pack", "Season 1 pack", 3),
        release("single", "S02E01", 1)
      ],
      gaps: ["S02E02 · Finale"],
      total_size_bytes: 12_400_000_000
    }
  end

  defp board(:blind_gap) do
    %PlanBoard{
      plan_id: "story-plan",
      title: "Sample Movie",
      status: :ready,
      wanted: 1,
      covered: 0,
      movie?: true,
      seasons: [
        %PlanBoard.SeasonRow{
          season_number: nil,
          cells: [
            %PlanBoard.Cell{
              plan_unit_id: "story-unit-movie-gap",
              season_number: nil,
              episode_number: nil,
              label: "Sample Movie",
              state: :unfound
            }
          ]
        }
      ],
      releases: [],
      gaps: ["Sample Movie"],
      total_size_bytes: nil
    }
  end

  defp board(:offer) do
    %PlanBoard{
      plan_id: "story-plan",
      title: "Sample Show",
      status: :ready,
      wanted: 1,
      covered: 0,
      seasons: [
        %PlanBoard.SeasonRow{season_number: 1, cells: [cell(1, 3, :unfound, nil)]}
      ],
      releases: [],
      gaps: ["S01E03 · The Signal"],
      total_size_bytes: nil,
      offers: [
        %PlanBoard.Offer{
          unit_id: "story-unit-s01e03",
          unit_label: "S01E03 · The Signal",
          guid: "s1-pack",
          scope_label: "Season 1 pack",
          title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
          size_bytes: 9_400_000_000
        }
      ]
    }
  end

  defp board(:below_floor) do
    %PlanBoard{
      plan_id: "story-plan-movie",
      title: "Sample Movie",
      status: :ready,
      wanted: 1,
      covered: 0,
      movie?: true,
      seasons: [
        %PlanBoard.SeasonRow{
          season_number: nil,
          cells: [
            %PlanBoard.Cell{
              plan_unit_id: "story-unit-movie",
              season_number: nil,
              episode_number: nil,
              label: "Sample Movie",
              state: :unfound,
              release_guid: nil,
              release_title: nil
            }
          ]
        }
      ],
      releases: [],
      gaps: [],
      total_size_bytes: nil,
      below_floor: [
        %PlanBoard.BelowFloor{
          unit_id: "story-unit-movie",
          unit_label: "Sample Movie",
          count: 3
        }
      ]
    }
  end

  defp board(:long_season) do
    long_cells = for episode <- 1..26, do: cell(2, episode, :assigned, "pack")

    %PlanBoard{
      plan_id: "story-plan",
      title: "Sample Show",
      status: :ready,
      wanted: 35,
      covered: 35,
      seasons: [
        %PlanBoard.SeasonRow{
          season_number: 1,
          cells: for(episode <- 1..9, do: cell(1, episode, :assigned, "pack-s1"))
        },
        %PlanBoard.SeasonRow{season_number: 2, cells: long_cells}
      ],
      releases: [
        release("pack-s1", "Season 1 pack", 9),
        release("pack", "Season 2 pack", 26)
      ],
      gaps: [],
      total_size_bytes: 32_400_000_000
    }
  end

  defp board(:overlap) do
    %{
      board(:ready)
      | overlaps: [
          %PlanBoard.Overlap{
            description:
              "The Season 1 pack also contains 1 episode assigned to other releases — they'd download twice",
            action_label: "Remove it & re-solve",
            exclude_guid: "pack",
            exclude_unit_id: "story-unit-1-1"
          }
        ]
    }
  end

  defp cell(season, episode, state, guid) do
    %PlanBoard.Cell{
      plan_unit_id: "story-unit-#{season}-#{episode}",
      season_number: season,
      episode_number: episode,
      label: "S0#{season}E#{String.pad_leading(to_string(episode), 2, "0")}",
      state: state,
      release_guid: guid,
      release_title: guid && "Sample.Show.S0#{season}.1080p.WEB-DL"
    }
  end

  defp release(guid, scope, units_count) do
    %PlanBoard.Release{
      guid: guid,
      title: "Sample.Show.#{guid}.1080p.WEB-DL.x264",
      scope_label: scope,
      quality: "1080p",
      seeders: 34,
      size_bytes: 3_100_000_000 * units_count,
      units_count: units_count,
      swap_unit_id: "story-unit-1-1"
    }
  end
end
