defmodule MediaCentaurWeb.Components.Acquisition.MediaResultsTest do
  @moduledoc """
  Unit tests for the flat results section's public pure helper — the
  query-activity rule that decides whether the section owns the page
  (ADR-030 extracted logic; no rendering).
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.TitleResult
  alias MediaCentaurWeb.Components.Acquisition.MediaResults

  @today ~D[2026-08-02]

  defp title_result(tmdb_id, release_date) do
    struct!(TitleResult, %{
      tmdb_id: tmdb_id,
      media_type: :movie,
      name: "Sample Movie #{tmdb_id}",
      release_date: release_date
    })
  end

  describe "active_query?/1" do
    test "needs two or more non-whitespace-wrapped characters" do
      refute MediaResults.active_query?("")
      refute MediaResults.active_query?("a")
      refute MediaResults.active_query?("  a  ")
      assert MediaResults.active_query?("ab")
      assert MediaResults.active_query?(" ab ")
    end
  end

  describe "release_status/2" do
    test "a passed date (including today) is released" do
      assert MediaResults.release_status(title_result(1, ~D[2020-01-01]), @today) == :released
      assert MediaResults.release_status(title_result(1, @today), @today) == :released
    end

    test "a future date is upcoming" do
      assert MediaResults.release_status(title_result(1, ~D[2027-01-01]), @today) == :upcoming
    end

    test "no date at all is upcoming — TMDB leaves unreleased titles undated" do
      assert MediaResults.release_status(title_result(1, nil), @today) == :upcoming
    end
  end

  describe "scope/3" do
    setup do
      results = [
        title_result(1, ~D[2020-01-01]),
        title_result(2, ~D[2027-01-01]),
        title_result(3, nil)
      ]

      %{results: results}
    end

    test ":all passes everything through untouched", %{results: results} do
      assert MediaResults.scope(results, :all, @today) == results
    end

    test ":released keeps only passed dates, in order", %{results: results} do
      assert [%TitleResult{tmdb_id: 1}] = MediaResults.scope(results, :released, @today)
    end

    test ":upcoming keeps future and undated titles, in order", %{results: results} do
      assert [%TitleResult{tmdb_id: 2}, %TitleResult{tmdb_id: 3}] =
               MediaResults.scope(results, :upcoming, @today)
    end
  end
end
