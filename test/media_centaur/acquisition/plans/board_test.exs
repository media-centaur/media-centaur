defmodule MediaCentaur.Acquisition.Plans.BoardTest do
  @moduledoc """
  The manifest (campaign plan-modal, M3): `Board.assemble/2` projects a
  plan's units into lines — every episode drawn once, inside the line
  that explains its outcome — and the board's summaries are functions of
  those lines. Pure: no database, `PlanUnit` structs in, a `PlanBoard`
  out.
  """

  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{Board, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  @pack_title "Sample.Show.S01.1080p.WEB-DL.x264-GRP"
  @single_title "Sample.Show.S02E01.1080p.WEB-DL.x264-GRP"

  defp plan(attrs \\ []) do
    struct!(
      %Plan{id: "plan-1", title: "Sample Show", status: "ready", tmdb_type: "tv", criteria: %{}},
      attrs
    )
  end

  # An episode of the plan; `nil`s make a movie's one unit.
  defp unit(season, episode, attrs \\ []) do
    base = %PlanUnit{
      id: if(season, do: "unit-s#{season}e#{episode}", else: "unit-movie"),
      plan_id: "plan-1",
      season_number: season,
      episode_number: episode,
      label: if(season, do: "S0#{season}E0#{episode} · Episode #{episode}", else: "Sample Movie"),
      position: if(season, do: season * 100 + episode, else: 0),
      status: "pending"
    }

    struct!(base, attrs)
  end

  defp found(season, episode, guid, title, extra \\ []) do
    unit(
      season,
      episode,
      [
        status: "found",
        assigned_guid: guid,
        assigned_title: title,
        assigned_quality: "1080p",
        assigned_seeders: 34,
        assigned_size_bytes: 3_100_000_000,
        assigned_scope: if(guid == "pack", do: "Season 1 pack", else: "S0#{season}E0#{episode}")
      ] ++ extra
    )
  end

  describe "assemble/2 — release lines" do
    test "release lines come first, ordered by their first episode, each with its rows and facts" do
      units = [
        found(2, 1, "single", @single_title),
        found(1, 1, "pack", @pack_title),
        found(1, 2, "pack", @pack_title),
        found(1, 3, "pack", @pack_title)
      ]

      board = Board.assemble(plan(), units)

      assert [
               %PlanBoard.Line{kind: :release, release: pack, rows: [pack_row]},
               %PlanBoard.Line{kind: :release, release: single, rows: [single_row]}
             ] = board.lines

      assert %PlanBoard.Release{guid: "pack", units_count: 3, scope_label: "Season 1 pack"} = pack
      assert %PlanBoard.SeasonRow{season_number: 1, cells: cells} = pack_row
      assert Enum.map(cells, & &1.episode_number) == [1, 2, 3]
      assert Enum.all?(cells, &(&1.state == :assigned and &1.release_guid == "pack"))

      assert %PlanBoard.Release{guid: "single", units_count: 1} = single
      assert %PlanBoard.SeasonRow{season_number: 2, cells: [%{episode_number: 1}]} = single_row

      assert board.wanted == 4
      assert board.covered == 4
      assert PlanBoard.releases(board) == [pack, single]
      # Per release, not per episode: the pack is one 3.1 GB grab.
      assert PlanBoard.total_size_bytes(board) == 2 * 3_100_000_000
      refute PlanBoard.empty?(board)
    end

    test "a release whose pack physically contains an episode assigned elsewhere carries the overlap" do
      units = [
        found(1, 1, "pack", @pack_title),
        found(1, 2, "single", "Sample.Show.S01E02.2160p.WEB-DL.x265-GRP"),
        found(1, 3, "pack", @pack_title)
      ]

      board = Board.assemble(plan(), units)

      assert [
               %PlanBoard.Line{release: %{guid: "pack", overlap: overlap}},
               %PlanBoard.Line{release: single}
             ] =
               board.lines

      assert %PlanBoard.Overlap{exclude_guid: "pack", exclude_unit_id: "unit-s1e1"} = overlap
      assert overlap.description =~ "download twice"
      assert is_nil(single.overlap)
    end
  end

  describe "assemble/2 — outcome lines" do
    test "outcome lines follow the releases in order: lower quality, not found, offers, dropped" do
      units = [
        found(1, 1, "single", "Sample.Show.S01E01.1080p.WEB-DL.x264-GRP"),
        unit(1, 2, status: "unfound", below_floor_count: 3),
        unit(1, 3, status: "unfound"),
        unit(1, 4,
          status: "unfound",
          offered_guid: "offered-pack",
          offered_title: @pack_title,
          offered_scope: "Season 1 pack",
          offered_size_bytes: 9_300_000_000
        ),
        unit(1, 5, status: "excluded"),
        unit(2, 1, status: "unfound")
      ]

      board = Board.assemble(plan(), units)

      assert Enum.map(board.lines, & &1.kind) == [
               :release,
               :below_preference,
               :not_found,
               :offer,
               :excluded
             ]

      [_release, below, not_found, offer, excluded] = board.lines

      assert %PlanBoard.BelowPreference{units: 1, releases: 3, unit_id: "unit-s1e2"} = below.below

      assert [
               %PlanBoard.SeasonRow{
                 season_number: 1,
                 cells: [%{episode_number: 2, state: :below_preference}]
               }
             ] =
               below.rows

      # Not found spans two seasons: one line, a row per season.
      assert [
               %PlanBoard.SeasonRow{season_number: 1, cells: [%{episode_number: 3}]},
               %PlanBoard.SeasonRow{season_number: 2, cells: [%{episode_number: 1}]}
             ] = not_found.rows

      assert %PlanBoard.Offer{guid: "offered-pack", scope_label: "Season 1 pack", unit_id: "unit-s1e4"} =
               offer.offer

      assert [%PlanBoard.SeasonRow{cells: [%{episode_number: 4, state: :unfound}]}] = offer.rows
      assert [%PlanBoard.SeasonRow{cells: [%{episode_number: 5, state: :excluded}]}] = excluded.rows

      # The summaries are functions of the lines.
      assert PlanBoard.gap_labels(board) == [
               "S01E03 · Episode 3",
               "S01E04 · Episode 4",
               "S02E01 · Episode 1"
             ]

      assert %PlanBoard.BelowPreference{units: 1, releases: 3} = PlanBoard.below_preference(board)
      assert board.wanted == 5
      assert board.covered == 1
    end

    test "a planning board's pending units are one searching line" do
      units = [
        found(1, 1, "pack", @pack_title),
        found(1, 2, "pack", @pack_title),
        unit(1, 3),
        unit(2, 1)
      ]

      board = Board.assemble(plan(status: "planning"), units)

      assert [%PlanBoard.Line{kind: :release}, %PlanBoard.Line{kind: :searching, rows: rows}] =
               board.lines

      assert [
               %PlanBoard.SeasonRow{season_number: 1, cells: [%{episode_number: 3, state: :searching}]},
               %PlanBoard.SeasonRow{season_number: 2, cells: [%{episode_number: 1, state: :searching}]}
             ] = rows

      assert board.status == :planning
      assert PlanBoard.gap_labels(board) == []
    end

    test "a ready board with nothing found is one not-found line and reads as empty" do
      board = Board.assemble(plan(), [unit(1, 1, status: "unfound"), unit(1, 2, status: "unfound")])

      assert [%PlanBoard.Line{kind: :not_found}] = board.lines
      assert PlanBoard.releases(board) == []
      assert PlanBoard.total_size_bytes(board) == nil
      assert PlanBoard.empty?(board)
      assert is_nil(PlanBoard.below_preference(board))
    end
  end

  describe "assemble/2 — a movie" do
    test "a found movie is one release line; its gap unit id is nil" do
      movie = unit(nil, nil)

      board =
        Board.assemble(
          plan(tmdb_type: "movie", title: "Sample Movie"),
          [
            struct!(movie,
              status: "found",
              assigned_guid: "movie-release",
              assigned_title: "Sample.Movie.2010.1080p.WEB-DL.x264-GRP",
              assigned_scope: "Movie"
            )
          ]
        )

      assert board.movie?

      assert [%PlanBoard.Line{kind: :release, rows: [%PlanBoard.SeasonRow{season_number: nil}]}] =
               board.lines

      assert is_nil(PlanBoard.movie_gap_unit_id(board))
    end

    test "an unfound movie is one not-found line whose unit the rejected list opens on" do
      movie = unit(nil, nil, status: "unfound")
      board = Board.assemble(plan(tmdb_type: "movie", title: "Sample Movie"), [movie])

      assert [%PlanBoard.Line{kind: :not_found}] = board.lines
      assert PlanBoard.movie_gap_unit_id(board) == "unit-movie"
      assert PlanBoard.gap_labels(board) == ["Sample Movie"]
      assert PlanBoard.empty?(board)
    end
  end
end
