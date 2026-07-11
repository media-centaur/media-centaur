defmodule MediaCentaurWeb.AcquisitionLive.HistoryLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow}
  alias MediaCentaurWeb.AcquisitionLive.HistoryLogic, as: Logic

  defp row(overrides) do
    base = %PursuitRow{
      id: Ecto.UUID.generate(),
      title: "Sample Movie",
      state: :exhausted,
      status: %CurrentAction{verb: "Stopped", description: "Nothing acceptable found", severity: :error}
    }

    Map.merge(base, overrides)
  end

  describe "filter_pursuit_rows_by_search/2" do
    test "empty search returns all rows unchanged" do
      rows = [row(%{title: "Sample Movie"}), row(%{title: "Other Title"})]
      assert Logic.filter_pursuit_rows_by_search(rows, "") == rows
    end

    test "case-insensitive substring match on title" do
      rows = [
        row(%{title: "Sample Movie"}),
        row(%{title: "Other Title"}),
        row(%{title: "sampler"})
      ]

      result = Logic.filter_pursuit_rows_by_search(rows, "SAMP")
      assert Enum.map(result, & &1.title) == ["Sample Movie", "sampler"]
    end

    test "match on release_title when title doesn't hit" do
      rows = [
        row(%{title: "Sample Show", release_title: "Sample.Show.S01E01.1080p.WEB-DL"}),
        row(%{title: "Sample Show", release_title: "Sample.Show.S01E02.720p.WEB-DL"})
      ]

      result = Logic.filter_pursuit_rows_by_search(rows, "1080p")
      assert length(result) == 1
      assert hd(result).release_title == "Sample.Show.S01E01.1080p.WEB-DL"
    end

    test "tolerates nil title and nil release_title" do
      rows = [row(%{title: nil, release_title: nil})]
      assert Logic.filter_pursuit_rows_by_search(rows, "anything") == []
    end
  end

  describe "parse_filter/1" do
    test "recognised values map to atoms" do
      assert Logic.parse_filter("failed") == :failed
      assert Logic.parse_filter("cancelled") == :cancelled
      assert Logic.parse_filter("succeeded") == :succeeded
      assert Logic.parse_filter("all") == :all
    end

    test "unknown / nil defaults to :failed" do
      assert Logic.parse_filter(nil) == :failed
      assert Logic.parse_filter("nope") == :failed
      assert Logic.parse_filter("") == :failed
    end
  end

  describe "filter_atoms/0" do
    test "renders chips in the canonical order" do
      assert Logic.filter_atoms() == [:failed, :cancelled, :succeeded, :all]
    end
  end

  describe "list_rows_filter/1" do
    test "renames :all to :all_terminal for the Pursuits read-layer" do
      assert Logic.list_rows_filter(:failed) == :failed
      assert Logic.list_rows_filter(:cancelled) == :cancelled
      assert Logic.list_rows_filter(:succeeded) == :succeeded
      assert Logic.list_rows_filter(:all) == :all_terminal
    end
  end

  describe "filter_label/1" do
    test "human-readable labels for chips" do
      assert Logic.filter_label(:failed) == "Failed"
      assert Logic.filter_label(:cancelled) == "Cancelled"
      assert Logic.filter_label(:succeeded) == "Succeeded"
      assert Logic.filter_label(:all) == "All"
    end
  end

  describe "empty_state/1" do
    test "filter-specific empty-state copy" do
      assert Logic.empty_state(:failed) == "Nothing has failed."
      assert Logic.empty_state(:cancelled) == "Nothing has been cancelled."
      assert Logic.empty_state(:succeeded) == "Nothing has finished yet."
      assert Logic.empty_state(:all) == "No past pursuits on record."
    end
  end

  describe "ledger_rows/2 — the Recently landed ledger" do
    defp terminal_row(n) do
      row(%{id: "pursuit-#{n}", state: :satisfied, status: "Landed"})
    end

    test "collapsed shows the newest few and reports what stays hidden" do
      rows = Enum.map(1..9, &terminal_row/1)

      {visible, hidden} = Logic.ledger_rows(rows, false)

      assert Enum.map(visible, & &1.id) == ["pursuit-1", "pursuit-2", "pursuit-3", "pursuit-4"]
      assert hidden == 5
    end

    test "expanded reveals more without becoming the full history view" do
      rows = Enum.map(1..20, &terminal_row/1)

      {visible, hidden} = Logic.ledger_rows(rows, true)

      assert length(visible) == 12
      assert hidden == 8
    end

    test "fewer rows than the cap means nothing hidden" do
      rows = Enum.map(1..2, &terminal_row/1)

      assert {^rows, 0} = Logic.ledger_rows(rows, false)
      assert {^rows, 0} = Logic.ledger_rows(rows, true)
    end

    test "input order is preserved (the read layer owns newest-first)" do
      rows = [terminal_row(3), terminal_row(1), terminal_row(2)]

      {visible, 0} = Logic.ledger_rows(rows, false)

      assert Enum.map(visible, & &1.id) == ["pursuit-3", "pursuit-1", "pursuit-2"]
    end
  end
end
