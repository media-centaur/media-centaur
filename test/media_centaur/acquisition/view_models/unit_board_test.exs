defmodule MediaCentaur.Acquisition.ViewModels.UnitBoardTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard

  defp row(attrs) do
    defaults = %{id: Ecto.UUID.generate(), label: "Sample Show", state: :active}
    struct(UnitBoard.Row, Map.merge(defaults, Map.new(attrs)))
  end

  defp season_rows(season, count, attrs \\ []) do
    for episode <- 1..count do
      row(
        Keyword.merge(
          [label: "Sample Show S#{season}E#{episode}", season_number: season],
          attrs
        )
      )
    end
  end

  describe "group_rows/1 — when grouping applies" do
    test "fewer than two seasons and a small board → nil (flat list)" do
      assert UnitBoard.group_rows(season_rows(1, 4)) == nil
    end

    test "two seasons → grouped, sorted by season ascending" do
      rows = season_rows(2, 2) ++ season_rows(1, 2)

      assert [%UnitBoard.Group{season_number: 1}, %UnitBoard.Group{season_number: 2}] =
               UnitBoard.group_rows(rows)
    end

    test "a single big season still groups — one collapsible wall-killer" do
      # The motivating case: a 38-episode single-season pack is a wall
      # of rows; one "Season 1 · 38/38" line is the entire point.
      assert [%UnitBoard.Group{season_number: 1, label: "Season 1"}] =
               UnitBoard.group_rows(season_rows(1, 10))
    end

    test "rows without season identity collect into a trailing Other group" do
      rows = season_rows(1, 2) ++ season_rows(2, 2) ++ [row(label: "Query unit")]

      assert [
               %UnitBoard.Group{season_number: 1},
               %UnitBoard.Group{season_number: 2},
               %UnitBoard.Group{season_number: nil, label: "Other", key: "other"}
             ] = UnitBoard.group_rows(rows)
    end
  end

  describe "group_rows/1 — group aggregates" do
    test "counts satisfied / awaiting / exhausted per group" do
      rows =
        season_rows(1, 2, state: :satisfied) ++
          [
            row(label: "S01E03", season_number: 1, state: :active, awaiting_decision?: true),
            row(label: "S01E04", season_number: 1, state: :exhausted)
          ] ++ season_rows(2, 2)

      [season_one, _season_two] = UnitBoard.group_rows(rows)

      assert season_one.wanted == 4
      assert season_one.satisfied == 2
      assert season_one.awaiting == 1
      assert season_one.exhausted == 1
    end

    test "hoists the release title when one release covers the whole group" do
      rows =
        season_rows(1, 3, release_title: "Sample.Show.S01.1080p") ++
          season_rows(2, 2, release_title: "Sample.Show.S02E01.1080p") ++
          [row(label: "S02E03", season_number: 2, release_title: "Sample.Show.S02E03.720p")]

      [season_one, season_two] = UnitBoard.group_rows(rows)

      assert season_one.shared_release_title == "Sample.Show.S01.1080p"
      assert season_two.shared_release_title == nil
    end

    test "rows without a target don't block hoisting the one real release" do
      rows =
        season_rows(1, 2, release_title: "Sample.Show.S01.1080p") ++
          [row(label: "S01E03", season_number: 1, release_title: nil)] ++ season_rows(2, 2)

      [season_one, _] = UnitBoard.group_rows(rows)
      assert season_one.shared_release_title == "Sample.Show.S01.1080p"
    end
  end

  describe "group_rows/1 — default expansion is exception-driven" do
    test "a homogeneous group starts collapsed" do
      rows = season_rows(1, 3, state: :satisfied) ++ season_rows(2, 3)

      [season_one, season_two] = UnitBoard.group_rows(rows)
      refute season_one.expanded_default?
      refute season_two.expanded_default?
    end

    test "a group containing an awaiting-decision or exhausted unit starts expanded" do
      rows =
        season_rows(1, 2, state: :satisfied) ++
          [row(label: "S01E03", season_number: 1, awaiting_decision?: true)] ++
          season_rows(2, 2) ++
          [row(label: "S02E03", season_number: 2, state: :exhausted)]

      [season_one, season_two] = UnitBoard.group_rows(rows)
      assert season_one.expanded_default?
      assert season_two.expanded_default?
    end
  end

  describe "default_expanded/1" do
    test "collects the keys of groups that default open" do
      rows =
        season_rows(1, 2, state: :satisfied) ++
          season_rows(2, 2) ++
          [row(label: "S02E03", season_number: 2, state: :exhausted)]

      expanded = rows |> UnitBoard.group_rows() |> UnitBoard.default_expanded()

      assert expanded == MapSet.new(["2"])
    end

    test "nil groups (flat board) → empty set" do
      assert UnitBoard.default_expanded(nil) == MapSet.new()
    end
  end
end
