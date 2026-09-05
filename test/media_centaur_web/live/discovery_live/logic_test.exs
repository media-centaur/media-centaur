defmodule MediaCentaurWeb.DiscoveryLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.DiscoveryLive.Logic

  @today ~D[2026-09-05]

  defp movie(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", release_date: ~D[2010-03-05]},
        overrides
      )
    )
  end

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{
        library_owner_id: nil,
        on_watchlist?: false,
        acquisition_state: nil,
        release_mode_available: true,
        today: @today
      },
      overrides
    )
  end

  describe "title_detail/2 primary action" do
    test "in library wins over everything" do
      detail =
        Logic.title_detail(movie(), facts(%{library_owner_id: "owner", acquisition_state: :downloading}))

      assert detail.primary == {:in_library, "owner"}
    end

    test "downloading, needs review and planning are states, not actions" do
      assert Logic.title_detail(movie(), facts(%{acquisition_state: :downloading})).primary ==
               {:state, :downloading}

      assert Logic.title_detail(movie(), facts(%{acquisition_state: :needs_review})).primary ==
               {:state, :needs_review}

      assert Logic.title_detail(movie(), facts(%{acquisition_state: :planning})).primary ==
               {:state, :planning}
    end

    test "released with an indexer downloads; a series carries the scope menu" do
      assert Logic.title_detail(movie(), facts()).primary == :download

      show =
        Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show", release_date: ~D[2010-01-01]})

      detail = Logic.title_detail(show, facts())
      assert detail.primary == :download
      assert detail.scoped?
    end

    test "upcoming, or no indexer, tracks the release" do
      assert Logic.title_detail(movie(%{release_date: ~D[2999-01-01]}), facts()).primary == :track
      assert Logic.title_detail(movie(), facts(%{release_mode_available: false})).primary == :track
    end
  end

  describe "title_detail/2 secondary and provenance" do
    test "add to watchlist flips to on watchlist" do
      refute Logic.title_detail(movie(), facts()).on_watchlist?
      assert Logic.title_detail(movie(), facts(%{on_watchlist?: true})).on_watchlist?
    end

    test "carries the feed provenance when given" do
      detail =
        Logic.title_detail(
          movie(),
          facts(%{
            sender: "Sample Friend",
            note: "Watch it",
            recommended_at: ~U[2026-09-01 10:00:00Z],
            own?: false
          })
        )

      assert %TitleDetail{sender: "Sample Friend", note: "Watch it", own?: false} = detail
    end
  end

  describe "acquisition_marker/1" do
    test "words for each state, nil for none" do
      assert Logic.acquisition_marker(:planning) == "Planning"
      assert Logic.acquisition_marker(:downloading) == "Downloading"
      assert Logic.acquisition_marker(:needs_review) == "Needs review"
      assert Logic.acquisition_marker(nil) == nil
    end
  end

  describe "row_markers/1" do
    test "in library wins, then the acquisition state, then provenance" do
      assert Logic.row_markers(%{
               library_owner_id: "o",
               acquisition_state: :downloading,
               from_nickname: "Sample Friend",
               on_watchlist?: true
             }) == ["In library", "from Sample Friend"]

      assert Logic.row_markers(%{
               library_owner_id: nil,
               acquisition_state: :needs_review,
               from_nickname: nil,
               on_watchlist?: true
             }) == ["Needs review", "On watchlist"]

      assert Logic.row_markers(%{
               library_owner_id: nil,
               acquisition_state: nil,
               from_nickname: nil,
               on_watchlist?: false
             }) == []
    end
  end

  describe "parse_title_ref/1" do
    test "the URL param round-trips" do
      assert Logic.parse_title_ref("movie-777") == {:ok, {777, :movie}}
      assert Logic.parse_title_ref("tv_series-42") == {:ok, {42, :tv_series}}
      assert Logic.parse_title_ref("book-1") == :error
      assert Logic.parse_title_ref("movie-x") == :error
      assert Logic.title_ref_param({777, :movie}) == "movie-777"
    end
  end
end
