defmodule MediaCentaurWeb.IncomingLive.PlanLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.{GapEvidence, PlanBoard}
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.IncomingLive.PlanLogic

  # S1: E1 in library, E2/E3 pickable. S2: E1 pickable, E2 unaired.
  defp selection do
    %Targeting.Selection{
      tmdb_id: "246810",
      title: "Sample Show",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes: [
            episode(1, 1, aired?: true, in_library?: true),
            episode(1, 2, aired?: true),
            episode(1, 3, aired?: true)
          ]
        },
        %Targeting.Season{
          season_number: 2,
          episodes: [
            episode(2, 1, aired?: true),
            episode(2, 2, aired?: false)
          ]
        }
      ]
    }
  end

  defp episode(season, number, opts) do
    %Targeting.Episode{
      season_number: season,
      episode_number: number,
      label: "Episode #{number}",
      aired?: Keyword.get(opts, :aired?, true),
      in_library?: Keyword.get(opts, :in_library?, false)
    }
  end

  test "pickable_units excludes in-library and unaired" do
    assert PlanLogic.pickable_units(selection()) == [{1, 2}, {1, 3}, {2, 1}]
  end

  test "toggle_unit flips pickable units and ignores unpickable ones" do
    chosen = MapSet.new()

    chosen = PlanLogic.toggle_unit(chosen, selection(), {1, 2})
    assert MapSet.member?(chosen, {1, 2})

    chosen = PlanLogic.toggle_unit(chosen, selection(), {1, 2})
    refute MapSet.member?(chosen, {1, 2})

    # In-library and unaired are no-ops.
    assert PlanLogic.toggle_unit(chosen, selection(), {1, 1}) == chosen
    assert PlanLogic.toggle_unit(chosen, selection(), {2, 2}) == chosen
  end

  test "toggle_season fills, then clears" do
    chosen = PlanLogic.toggle_season(MapSet.new(), selection(), 1)
    assert MapSet.equal?(chosen, MapSet.new([{1, 2}, {1, 3}]))

    assert PlanLogic.toggle_season(chosen, selection(), 1) == MapSet.new()
  end

  test "season_state — the in-library subtraction keeps a full season indeterminate" do
    [season_one, season_two] = selection().seasons

    assert PlanLogic.season_state(MapSet.new(), selection(), season_one) == :unchecked

    partial = MapSet.new([{1, 2}])
    assert PlanLogic.season_state(partial, selection(), season_one) == :indeterminate

    # Every pickable unit chosen, but E1 is in-library → still indeterminate.
    full = MapSet.new([{1, 2}, {1, 3}])
    assert PlanLogic.season_state(full, selection(), season_one) == :indeterminate

    # S2 has one pickable + one unaired → same rule.
    assert PlanLogic.season_state(MapSet.new([{2, 1}]), selection(), season_two) == :indeterminate

    # A season with nothing pickable is disabled.
    empty_season = %Targeting.Season{season_number: 3, episodes: [episode(3, 1, aired?: false)]}
    assert PlanLogic.season_state(MapSet.new(), selection(), empty_season) == :disabled
  end

  test "season_state — checked when everything in the season is pickable and chosen" do
    clean_selection = %Targeting.Selection{
      tmdb_id: "1",
      title: "T",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes: [episode(1, 1, []), episode(1, 2, [])]
        }
      ]
    }

    chosen = MapSet.new([{1, 1}, {1, 2}])
    [season] = clean_selection.seasons
    assert PlanLogic.season_state(chosen, clean_selection, season) == :checked
  end

  test "presets" do
    assert PlanLogic.apply_preset(selection(), :everything_aired) ==
             MapSet.new([{1, 2}, {1, 3}, {2, 1}])

    # Library's last present episode is S01E01 → everything after it.
    assert PlanLogic.apply_preset(selection(), :continue) ==
             MapSet.new([{1, 2}, {1, 3}, {2, 1}])

    assert PlanLogic.apply_preset(selection(), :latest_season) == MapSet.new([{2, 1}])

    assert PlanLogic.apply_preset(selection(), :none) == MapSet.new()
  end

  test "chosen_in_order returns airing order regardless of set order" do
    chosen = MapSet.new([{2, 1}, {1, 2}])
    assert PlanLogic.chosen_in_order(chosen, selection()) == [{1, 2}, {2, 1}]
  end

  test "toggle_expanded adds a collapsed season and removes an expanded one" do
    expanded = PlanLogic.toggle_expanded(MapSet.new(), 2)
    assert expanded == MapSet.new([2])

    assert PlanLogic.toggle_expanded(expanded, 2) == MapSet.new()
    assert PlanLogic.toggle_expanded(expanded, 1) == MapSet.new([1, 2])
  end

  describe "shell_backdrop_url/2 — the plan modal's cinematic shell" do
    alias MediaCentaur.TMDB.Title

    defp sources(overrides) do
      Map.merge(%{identity: nil, selection: nil, movie: nil, artwork: nil}, overrides)
    end

    defp identity(backdrop_path) do
      Title.new!(%{
        tmdb_id: 246_810,
        media_type: :tv_series,
        name: "Sample Show",
        backdrop_path: backdrop_path
      })
    end

    test "loading dresses from the picked search result immediately" do
      assert PlanLogic.shell_backdrop_url(:loading, sources(%{identity: identity("/pick.jpg")})) ==
               "https://image.tmdb.org/t/p/w1280/pick.jpg"
    end

    test "loading with no identity in hand renders the scrim alone" do
      assert PlanLogic.shell_backdrop_url(:loading, sources(%{})) == nil
    end

    test "targeting wears the selection's backdrop" do
      selection = %Targeting.Selection{
        tmdb_id: "246810",
        title: "Sample Show",
        tracked?: false,
        seasons: [],
        backdrop_path: "/series.jpg"
      }

      assert PlanLogic.shell_backdrop_url(:targeting, sources(%{selection: selection})) ==
               "https://image.tmdb.org/t/p/w1280/series.jpg"
    end

    test "targeting falls back to the picked identity when TMDB has no series backdrop" do
      selection = %Targeting.Selection{
        tmdb_id: "246810",
        title: "Sample Show",
        tracked?: false,
        seasons: []
      }

      assert PlanLogic.shell_backdrop_url(
               :targeting,
               sources(%{selection: selection, identity: identity("/pick.jpg")})
             ) == "https://image.tmdb.org/t/p/w1280/pick.jpg"
    end

    test "movie confirm wears the preview's backdrop, poster as fallback" do
      movie = %TitlePreview{
        media_type: :movie,
        tmdb_id: "550",
        in_library?: false,
        backdrop_url: "https://x/b.jpg"
      }

      assert PlanLogic.shell_backdrop_url(:movie_confirm, sources(%{movie: movie})) == "https://x/b.jpg"

      poster_only = %TitlePreview{
        media_type: :movie,
        tmdb_id: "550",
        in_library?: false,
        poster_url: "https://x/p.jpg"
      }

      assert PlanLogic.shell_backdrop_url(:movie_confirm, sources(%{movie: poster_only})) ==
               "https://x/p.jpg"
    end

    test "board prefers locally cached artwork, then falls back through the flow's earlier stages" do
      movie = %TitlePreview{
        media_type: :movie,
        tmdb_id: "550",
        in_library?: false,
        backdrop_url: "https://x/movie.jpg"
      }

      artwork = %{backdrop_url: "/media-images/tracking/backdrop-550.jpg", logo_url: nil}

      assert PlanLogic.shell_backdrop_url(:board, sources(%{movie: movie, artwork: artwork})) ==
               "/media-images/tracking/backdrop-550.jpg"

      # No cache yet — the confirm stage's backdrop carries over (refresh loses
      # it, and the async ensure fills the cache for the next open).
      assert PlanLogic.shell_backdrop_url(:board, sources(%{movie: movie})) == "https://x/movie.jpg"
    end

    test "the error stage is honest — no artwork" do
      assert PlanLogic.shell_backdrop_url(:error, sources(%{identity: identity("/pick.jpg")})) == nil
    end
  end

  describe "lockup/2 — the pinned identity block per stage" do
    alias MediaCentaur.TMDB.Title

    defp lockup_sources(overrides) do
      Map.merge(%{identity: nil, selection: nil, movie: nil, board: nil}, overrides)
    end

    test "loading introduces the picked result by name — no logo yet" do
      identity = Title.new!(%{tmdb_id: 1, media_type: :tv_series, name: "Sample Show"})

      assert PlanLogic.lockup(:loading, lockup_sources(%{identity: identity})) ==
               %{title: "Sample Show", logo_url: nil, tagline: nil}
    end

    test "loading without an identity has nothing to introduce" do
      assert PlanLogic.lockup(:loading, lockup_sources(%{})) == nil
    end

    test "targeting wears the series logo when TMDB has one, hotlinked" do
      selection = %Targeting.Selection{
        tmdb_id: "246810",
        title: "Sample Show",
        tracked?: false,
        seasons: [],
        logo_path: "/logo.png"
      }

      assert PlanLogic.lockup(:targeting, lockup_sources(%{selection: selection})) ==
               %{
                 title: "Sample Show",
                 logo_url: "https://image.tmdb.org/t/p/w500/logo.png",
                 tagline: nil
               }
    end

    test "movie confirm carries the preview's logo and tagline" do
      movie = %TitlePreview{
        media_type: :movie,
        tmdb_id: "550",
        in_library?: false,
        title: "Sample Movie",
        logo_url: "https://image.tmdb.org/t/p/original/m-logo.png",
        tagline: "Look closer."
      }

      assert PlanLogic.lockup(:movie_confirm, lockup_sources(%{movie: movie})) ==
               %{
                 title: "Sample Movie",
                 logo_url: "https://image.tmdb.org/t/p/original/m-logo.png",
                 tagline: "Look closer."
               }
    end

    test "board keeps the identity painted, borrowing the logo from earlier stages" do
      board = %MediaCentaur.Acquisition.ViewModels.PlanBoard{
        title: "Sample Show",
        plan_id: "plan-1",
        status: :ready,
        wanted: 3,
        covered: 3,
        seasons: [],
        releases: [],
        gaps: []
      }

      selection = %Targeting.Selection{
        tmdb_id: "246810",
        title: "Sample Show",
        tracked?: false,
        seasons: [],
        logo_path: "/logo.png"
      }

      assert PlanLogic.lockup(:board, lockup_sources(%{board: board, selection: selection})) ==
               %{
                 title: "Sample Show",
                 logo_url: "https://image.tmdb.org/t/p/w500/logo.png",
                 tagline: nil
               }
    end

    test "the error stage introduces nothing" do
      assert PlanLogic.lockup(:error, lockup_sources(%{})) == nil
    end
  end

  describe "rejected_items/1 (UIDR-022)" do
    defp rejected(guid, reason, seeders) do
      %GapEvidence.Rejected{
        guid: guid,
        title: "Another.Picture.1990.1080p.WEB-DL.x264",
        reason: reason,
        quality: "1080p",
        seeders: seeders,
        size_bytes: 2_000_000_000
      }
    end

    test "maps rejection gates to reason copy, suspicious rows last, seeders first" do
      evidence = %GapEvidence{
        searches: [],
        rejected: [
          rejected("bait", :red_flag, 40),
          rejected("low", :identity, 2),
          rejected("high", :excluded, 9)
        ],
        raw_total: 3,
        checked_at: nil
      }

      items = PlanLogic.rejected_items(evidence)

      assert Enum.map(items, &{&1.guid, &1.reason, &1.suspicious?}) == [
               {"high", "you excluded this earlier", false},
               {"low", "didn't match this title", false},
               {"bait", "flagged suspicious", true}
             ]
    end
  end

  describe "movie_gap_unit_id/1" do
    test "finds the movie board's unfound cell and refuses TV boards" do
      cell = %PlanBoard.Cell{
        plan_unit_id: "unit-1",
        season_number: nil,
        episode_number: nil,
        label: "Sample Movie",
        state: :unfound
      }

      board = %PlanBoard{
        plan_id: "plan-1",
        title: "Sample Movie",
        status: :ready,
        wanted: 1,
        covered: 0,
        seasons: [%PlanBoard.SeasonRow{season_number: nil, cells: [cell]}],
        releases: [],
        gaps: ["Sample Movie"],
        movie?: true
      }

      assert PlanLogic.movie_gap_unit_id(board) == "unit-1"
      assert PlanLogic.movie_gap_unit_id(%{board | movie?: false}) == nil
    end
  end

  describe "search_activity_line/2" do
    defp activity(outcome, result_count) do
      %PlanEvents.SearchActivity{
        plan_id: "plan-1",
        term: "Sample Movie 2005",
        outcome: outcome,
        result_count: result_count
      }
    end

    test "live outcomes report the count" do
      assert PlanLogic.search_activity_line(activity(:live, 62), nil) ==
               "Searched: Sample Movie 2005 — 62 found"
    end

    test "a zero-count live outcome while blind reports the outage, not knowledge" do
      health = %IndexerHealth{state: :blind, checked_at: ~U[2026-08-01 00:00:00Z]}

      assert PlanLogic.search_activity_line(activity(:live, 0), health) ==
               "Searched: Sample Movie 2005 — couldn't reach any indexer"
    end

    test "a zero-count live outcome with healthy indexers is genuine knowledge" do
      health = %IndexerHealth{state: :ok, checked_at: ~U[2026-08-01 00:00:00Z]}

      assert PlanLogic.search_activity_line(activity(:live, 0), health) ==
               "Searched: Sample Movie 2005 — 0 found"
    end

    test "corpus and error outcomes are unchanged" do
      assert PlanLogic.search_activity_line(activity(:corpus, 5), nil) ==
               "Sample Movie 2005 — 5 known (corpus)"

      assert PlanLogic.search_activity_line(activity(:error, 0), nil) ==
               "Search failed: Sample Movie 2005"
    end
  end
end
