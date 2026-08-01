defmodule MediaCentaurWeb.Components.Acquisition.MediaResultsTest do
  @moduledoc """
  Unit tests for the flat results section's public pure helper — the
  query-activity rule that decides whether the section owns the page
  (ADR-030 extracted logic; no rendering).
  """
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  describe "active_query?/1" do
    test "needs two or more non-whitespace-wrapped characters" do
      refute MediaResults.active_query?("")
      refute MediaResults.active_query?("a")
      refute MediaResults.active_query?("  a  ")
      assert MediaResults.active_query?("ab")
      assert MediaResults.active_query?(" ab ")
    end
  end
end
