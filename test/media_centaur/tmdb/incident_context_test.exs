defmodule MediaCentaur.TMDB.IncidentContextTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.ErrorReports.Contributors
  alias MediaCentaur.TMDB.IncidentContext

  test "vitals/0 surfaces the rate-limiter window" do
    assert %{"rate_limiter" => %{available: _, total: _, used: _}} = IncidentContext.vitals()
  end

  test "is reachable through the runtime registry as a vitals source" do
    # Uses the real configured registry — TMDB is registered in config.exs.
    vitals = Contributors.all_vitals()

    assert %{"rate_limiter" => %{total: _}} = vitals[:tmdb]
  end
end
