defmodule MediaCentaurWeb.Components.Acquisition.MediaOmniboxTest do
  @moduledoc """
  Unit tests for the omnibox's public pure helpers — the dropdown
  visibility rule and the spotlight preview resolution (ADR-030
  extracted logic; no rendering).
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.TitleResult
  alias MediaCentaurWeb.Components.Acquisition.MediaOmnibox

  defp title_result(tmdb_id, media_type, name) do
    struct!(TitleResult, %{tmdb_id: tmdb_id, media_type: media_type, name: name})
  end

  describe "previewed_result/2" do
    setup do
      results = [
        title_result(200, :tv_series, "Sample Show"),
        title_result(777, :movie, "Sample Movie")
      ]

      %{results: results}
    end

    test "defaults to the top hit when nothing is previewed", %{results: results} do
      assert %TitleResult{tmdb_id: 200} = MediaOmnibox.previewed_result(results, nil)
    end

    test "returns the previewed result when it is present", %{results: results} do
      assert %TitleResult{tmdb_id: 777} =
               MediaOmnibox.previewed_result(results, {:movie, 777})
    end

    test "falls back to the top hit when the previewed id is stale", %{results: results} do
      assert %TitleResult{tmdb_id: 200} =
               MediaOmnibox.previewed_result(results, {:movie, 999})
    end

    test "returns nil for an empty result set" do
      assert MediaOmnibox.previewed_result([], nil) == nil
      assert MediaOmnibox.previewed_result([], {:movie, 777}) == nil
    end
  end

  describe "dropdown?/1" do
    test "needs two or more non-whitespace-wrapped characters" do
      refute MediaOmnibox.dropdown?("")
      refute MediaOmnibox.dropdown?("a")
      refute MediaOmnibox.dropdown?("  a  ")
      assert MediaOmnibox.dropdown?("ab")
      assert MediaOmnibox.dropdown?(" ab ")
    end
  end
end
