defmodule MediaCentaur.Acquisition.CoursTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Cours
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  # Synthetic season: E1–E3 aired 2023, E4–E5 a later cour in 2026.
  defp season_data do
    %{
      "episodes" => [
        %{"episode_number" => 1, "air_date" => "2023-10-01", "name" => "A"},
        %{"episode_number" => 2, "air_date" => "2023-10-08", "name" => "B"},
        %{"episode_number" => 3, "air_date" => "2023-10-15", "name" => "C"},
        %{"episode_number" => 4, "air_date" => "2026-01-16", "name" => "D"},
        %{"episode_number" => 5, "air_date" => "2026-01-23", "name" => "E"}
      ]
    }
  end

  describe "runs_for_season/2" do
    test "fetches the season and segments it into broadcast runs" do
      TmdbStubs.stub_get_season("246810", 1, season_data())

      assert [run1, run2] = Cours.runs_for_season("246810", 1)
      assert run1.last_ep == {1, 3}
      assert run2.first_ep == {1, 4}
      assert run2.index == 1
    end

    test "degrades to no runs on a TMDB error rather than failing" do
      TmdbStubs.stub_tmdb_error("/tv/246810/season/1")

      assert Cours.runs_for_season("246810", 1) == []
    end
  end

  describe "later_run/2" do
    test "returns the later run a unit belongs to" do
      runs = [
        %{index: 0, first_ep: {1, 1}, last_ep: {1, 3}, date_span: nil},
        %{index: 1, first_ep: {1, 4}, last_ep: {1, 5}, date_span: nil}
      ]

      assert Cours.later_run(runs, {1, 5}).index == 1
    end

    test "returns nil for a first-run unit" do
      runs = [
        %{index: 0, first_ep: {1, 1}, last_ep: {1, 3}, date_span: nil},
        %{index: 1, first_ep: {1, 4}, last_ep: {1, 5}, date_span: nil}
      ]

      assert Cours.later_run(runs, {1, 2}) == nil
    end

    test "returns nil when the season is a single run" do
      runs = [%{index: 0, first_ep: {1, 1}, last_ep: {1, 12}, date_span: nil}]
      assert Cours.later_run(runs, {1, 8}) == nil
    end
  end
end
