defmodule MediaCentaurWeb.IncomingLive.HistoryLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow}
  alias MediaCentaurWeb.IncomingLive.HistoryLogic, as: Logic

  defp row(overrides) do
    base = %PursuitRow{
      id: Ecto.UUID.generate(),
      title: "Sample Movie",
      state: :exhausted,
      status: %CurrentAction{verb: "Stopped", description: "Nothing acceptable found", severity: :error}
    }

    Map.merge(base, overrides)
  end

  @today ~D[2026-08-03]

  defp single(updated_at, overrides \\ %{}) do
    {:single, row(Map.put(overrides, :updated_at, updated_at))}
  end

  defp group(member_times) do
    vms = Enum.map(member_times, &row(%{updated_at: &1}))

    {:group,
     %{
       title: "Sample Show",
       state: :cancelled,
       awaiting?: false,
       count: length(vms),
       verb: "Cancelled",
       severity: :info,
       vms: vms,
       expanded?: false
     }}
  end

  describe "section_entries/2" do
    test "labels entries Today / Yesterday / This week / month-year" do
      entries = [
        single(~U[2026-08-03 09:00:00Z]),
        single(~U[2026-08-02 20:00:00Z]),
        single(~U[2026-07-30 10:00:00Z]),
        single(~U[2026-07-10 10:00:00Z]),
        single(~U[2026-06-20 10:00:00Z])
      ]

      assert [
               {"Today", [_]},
               {"Yesterday", [_]},
               {"This week", [_]},
               {"July 2026", [_]},
               {"June 2026", [_]}
             ] = Logic.section_entries(entries, @today)
    end

    test "consecutive entries with the same label share one section" do
      entries = [
        single(~U[2026-08-03 09:00:00Z]),
        single(~U[2026-08-03 07:00:00Z]),
        single(~U[2026-07-10 10:00:00Z]),
        single(~U[2026-07-05 10:00:00Z])
      ]

      assert [{"Today", today_entries}, {"July 2026", july_entries}] =
               Logic.section_entries(entries, @today)

      assert length(today_entries) == 2
      assert length(july_entries) == 2
    end

    test "a group is placed by its newest member" do
      entries = [group([~U[2026-07-15 10:00:00Z], ~U[2026-08-03 08:00:00Z]])]

      assert [{"Today", [_]}] = Logic.section_entries(entries, @today)
    end

    test "entries without a timestamp fall into Earlier" do
      entries = [single(nil)]

      assert [{"Earlier", [_]}] = Logic.section_entries(entries, @today)
    end

    test "empty input yields no sections" do
      assert Logic.section_entries([], @today) == []
    end
  end

  describe "latest_time/1" do
    test "returns the newest updated_at, tolerating nils" do
      vms = [
        row(%{updated_at: ~U[2026-07-01 10:00:00Z]}),
        row(%{updated_at: nil}),
        row(%{updated_at: ~U[2026-08-01 10:00:00Z]})
      ]

      assert Logic.latest_time(vms) == ~U[2026-08-01 10:00:00Z]
    end

    test "returns nil for an empty or all-nil list" do
      assert Logic.latest_time([]) == nil
      assert Logic.latest_time([row(%{updated_at: nil})]) == nil
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
      assert Logic.parse_filter(nil) == :all
      assert Logic.parse_filter("nope") == :all
      assert Logic.parse_filter("") == :all
    end
  end

  describe "filter_atoms/0" do
    test "renders chips in the canonical order" do
      assert Logic.filter_atoms() == [:all, :failed, :cancelled, :succeeded]
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
end
