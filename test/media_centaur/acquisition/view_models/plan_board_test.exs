defmodule MediaCentaur.Acquisition.ViewModels.PlanBoardTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  defp board(overrides) do
    struct!(
      %PlanBoard{
        plan_id: "plan-1",
        title: "Sample Movie",
        status: :ready,
        wanted: 1,
        covered: 0,
        seasons: [],
        releases: [],
        gaps: ["Sample Movie"]
      },
      overrides
    )
  end

  defp release do
    %PlanBoard.Release{guid: "g", title: "Sample.Movie.2005.1080p", units_count: 1, swap_unit_id: "u"}
  end

  describe "empty?/1" do
    test "a ready board with nothing to approve is empty" do
      assert PlanBoard.empty?(board(%{}))
    end

    test "a ready board with a release is not" do
      refute PlanBoard.empty?(board(%{releases: [release()], covered: 1, gaps: []}))
    end

    test "a board still planning is not empty yet, whatever it holds" do
      refute PlanBoard.empty?(board(%{status: :planning}))
    end

    test "a committed or discarded board is not empty either — it is over" do
      refute PlanBoard.empty?(board(%{status: :committed}))
      refute PlanBoard.empty?(board(%{status: :discarded}))
    end
  end
end
