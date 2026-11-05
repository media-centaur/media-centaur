defmodule MediaCentaur.Acquisition.ViewModels.UnitBoardTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard
  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.{Attempt, Fold, Row}

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

  defp failed(detail \\ "Aborted, cannot be completed"),
    do: %Attempt{release_title: "Sample.Show.S04E01.1080p", outcome: :failed, detail: detail}

  describe "Row — the one word list and the outcome line" do
    test "every state has its word" do
      assert Row.word(row(state: :satisfied)) == "Landed"
      assert Row.word(row(state: :active)) == "Trying"
      assert Row.word(row(state: :active, awaiting_decision?: true)) == "Needs a pick"
      assert Row.word(row(state: :exhausted)) == "Gave up"
      assert Row.word(row(state: :cancelled)) == "Cancelled"
    end

    test "the outcome line carries the thread's cost" do
      assert Row.outcome_line(row(state: :satisfied, attempt_count: 1)) == "Landed"
      assert Row.outcome_line(row(state: :satisfied, attempt_count: 28)) == "Landed · 28th release"
      assert Row.outcome_line(row(state: :active, attempt_count: 3)) == "Trying · 3rd release"
      assert Row.outcome_line(row(state: :active, attempt_count: 22)) == "Trying · 22nd release"
      assert Row.outcome_line(row(state: :active, attempt_count: 11)) == "Trying · 11th release"

      cancelled = row(state: :cancelled, attempts: List.duplicate(failed(), 48), attempt_count: 48)
      assert Row.outcome_line(cancelled) == "Cancelled · 48 releases failed"

      gave_up = row(state: :exhausted, attempts: [failed()], attempt_count: 1)
      assert Row.outcome_line(gave_up) == "Gave up · 1 release failed"

      assert Row.outcome_line(row(state: :cancelled)) == "Cancelled"

      assert Row.outcome_line(row(state: :active, awaiting_decision?: true, attempt_count: 5)) ==
               "Needs a pick"
    end

    test "the cause is one sentence when every failed release failed the same way" do
      assert Row.cause(row(attempts: List.duplicate(failed(), 3))) ==
               "Every release failed at your download client — Aborted, cannot be completed."

      assert Row.cause(row(attempts: [failed()])) ==
               "Failed at your download client — Aborted, cannot be completed."

      assert Row.cause(row(attempts: [failed("Aborted"), failed("Repair failed")])) == nil
      assert Row.cause(row(attempts: [%Attempt{release_title: "x", outcome: :landed}])) == nil
    end
  end

  describe "group_rows/1 — cancelled units count and open the season" do
    test "a group with a cancelled unit names it and starts expanded" do
      rows =
        season_rows(4, 3, state: :satisfied) ++
          season_rows(4, 3, state: :cancelled) ++ season_rows(5, 6, state: :satisfied)

      [season_four, season_five] = UnitBoard.group_rows(rows)

      assert %UnitBoard.Group{satisfied: 3, cancelled: 3, expanded_default?: true} = season_four
      assert %UnitBoard.Group{satisfied: 6, cancelled: 0, expanded_default?: false} = season_five
    end
  end

  describe "fold/1" do
    test "counts the rows by word, and a pack covering three rows is one release tried" do
      pack = %Attempt{target_id: "t-pack", release_title: "Sample.Show.S04.1080p", outcome: :landed}

      tried = fn n ->
        for i <- 1..n, do: %Attempt{target_id: "t-#{i}", release_title: "r#{i}", outcome: :failed}
      end

      rows =
        season_rows(4, 3, state: :satisfied, attempts: [pack], attempt_count: 1) ++
          [
            row(
              label: "S04E04",
              season_number: 4,
              state: :cancelled,
              attempts: tried.(48),
              attempt_count: 48
            ),
            row(
              label: "S05E01",
              season_number: 5,
              state: :active,
              awaiting_decision?: true,
              attempts: [],
              attempt_count: 0
            )
          ]

      board = %UnitBoard{pursuit_id: "p", wanted: 5, satisfied: 3, units: rows}

      assert %Fold{
               wanted: 5,
               landed: 3,
               cancelled: 1,
               awaiting: 1,
               trying: 0,
               gave_up: 0,
               releases_tried: 49
             } =
               UnitBoard.fold(board)

      assert Fold.missing(UnitBoard.fold(board)) == 1
    end

    test "from the units alone, the releases tried are unknown" do
      assert %Fold{wanted: 2, landed: 1, trying: 1, releases_tried: nil} =
               Fold.from_states([{:satisfied, false}, {:active, false}])
    end
  end
end
