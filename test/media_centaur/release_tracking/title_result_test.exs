defmodule MediaCentaur.ReleaseTracking.TitleResultTest do
  @moduledoc """
  Locks the contract of the unified TMDB title-search result — the one
  struct both the omnibox dropdown and the track flow consume. Enforced
  construction is the gate that makes "forgot to populate `:name`"-style
  bugs crash at the data layer instead of silently rendering broken rows.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.TitleResult

  describe "TitleResult struct" do
    test "constructs with all enforced keys and applies defaults" do
      result =
        struct!(TitleResult, %{
          tmdb_id: 1234,
          media_type: :movie,
          name: "Sample Movie"
        })

      assert %TitleResult{} = result
      assert result.year == nil
      assert result.poster_path == nil
      assert result.overview == nil
      assert result.tracked? == false
    end

    test "carries year, poster_path, overview, and tracked? when given" do
      result =
        struct!(TitleResult, %{
          tmdb_id: 1234,
          media_type: :tv_series,
          name: "Sample Show",
          year: "2010",
          poster_path: "/abc.jpg",
          overview: "A sample overview.",
          tracked?: true
        })

      assert result.year == "2010"
      assert result.poster_path == "/abc.jpg"
      assert result.overview == "A sample overview."
      assert result.tracked? == true
    end

    test "raises ArgumentError when tmdb_id missing" do
      assert_raise ArgumentError, fn ->
        struct!(TitleResult, %{media_type: :movie, name: "Sample Movie"})
      end
    end

    test "raises ArgumentError when media_type missing" do
      assert_raise ArgumentError, fn ->
        struct!(TitleResult, %{tmdb_id: 1234, name: "Sample Movie"})
      end
    end

    test "raises ArgumentError when name missing" do
      assert_raise ArgumentError, fn ->
        struct!(TitleResult, %{tmdb_id: 1234, media_type: :movie})
      end
    end
  end
end
