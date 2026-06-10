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
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  def function, do: &MediaCentaurWeb.Components.Acquisition.PlanModal.plan_modal/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :loading,
        description: "Targeting universe loading from TMDB.",
        attributes: %{open: true, stage: :loading}
      },
      %Variation{
        id: :targeting,
        description:
          "The picker — quick-action presets, tri-state season rows, the in-library row greyed (shown, never hidden), the unaired row inert.",
        attributes: %{
          open: true,
          stage: :targeting,
          selection: selection(),
          chosen: {:eval, ~s|MapSet.new([{1, 2}, {1, 3}, {2, 1}])|}
        }
      },
      %Variation{
        id: :movie_confirm,
        description: "The movie fast path — two clicks from omnibox to plan.",
        attributes: %{
          open: true,
          stage: :movie_confirm,
          movie: %{tmdb_id: "777", title: "Sample Movie", year: 2010, in_library?: false}
        }
      },
      %Variation{
        id: :board_planning,
        description: "Mid-flight — dashed searching cells, the activity ticker, no spinner-only state.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:planning),
          last_activity: "Sample Show S01E03 — 2 known (corpus)"
        }
      },
      %Variation{
        id: :board_ready,
        description:
          "Ready — the season pack fused into one capsule, a single covering the stray episode, an explicit gap row, the approval footer.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:ready),
          last_activity: "9 searches · 6 from corpus"
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
                seeders: 12
              },
              %PlanBoard.Alternative{
                guid: "alt-single",
                title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 41
              },
              %PlanBoard.Alternative{
                guid: "alt-evil",
                title: "Sample.Show.S01E01.1080p.HD.X264.1080p.exe",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 999,
                suspicious?: true
              }
            ]
          },
          last_activity: "9 searches · 6 from corpus"
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
      gaps: []
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
      gaps: ["S02E02 · Finale"]
    }
  end

  defp cell(season, episode, state, guid) do
    %PlanBoard.Cell{
      plan_unit_id: "story-unit-#{season}-#{episode}",
      season_number: season,
      episode_number: episode,
      label: "S0#{season}E0#{episode}",
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
      units_count: units_count,
      swap_unit_id: "story-unit-1-1"
    }
  end
end
