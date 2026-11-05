defmodule MediaCentaurWeb.SettingsLiveRememberedMatchesTest do
  @moduledoc """
  Settings → Media Import's remembered matches (campaign
  `review-bulk-match`): answers given in Review, listed by the name the
  files were read as, each with Forget.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Review
  alias MediaCentaurWeb.SettingsLive.ImportSection

  defp answer(parsed_title) do
    file =
      create_pending_file(%{parsed_title: parsed_title, parsed_type: "tv", tmdb_id: nil, tmdb_type: nil})

    {:ok, 1} =
      Review.match([file.id], %{tmdb_id: 4242, tmdb_type: "tv", title: "Sample Show", year: "1995"})
  end

  test "lists each remembered match, and Forget removes it", %{conn: conn} do
    answer("Sample Show Signed")
    [remembered] = Review.list_remembered_matches()

    {:ok, view, _html} = live_async!(conn, "/settings?section=import")
    render_async(view)

    assert render(view) =~ "Sample Show Signed · TV → Sample Show (1995)"

    view
    |> element("#remembered-matches button[phx-value-item='#{remembered.id}']", "Forget")
    |> render_click()

    assert Review.list_remembered_matches() == []
    refute render(view) =~ "Sample Show Signed · TV"
  end

  test "with none, the card says how they are made", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/settings?section=import")

    assert render_async(view) =~ "Matching files by hand in Review adds them here."
  end

  describe "remembered_match_label/1" do
    test "names the read name with its year and type, and the title it means" do
      assert ImportSection.remembered_match_label(%{
               parsed_title: "Sample Show",
               parsed_year: 2005,
               media_type: "tv",
               match_title: "Sample Show",
               match_year: "2005",
               tmdb_id: 1
             }) == "Sample Show (2005) · TV → Sample Show (2005)"

      assert ImportSection.remembered_match_label(%{
               parsed_title: "Movie A Directors Cut",
               parsed_year: nil,
               media_type: "movie",
               match_title: nil,
               match_year: nil,
               tmdb_id: 77
             }) == "Movie A Directors Cut · Movie → TMDB 77"
    end
  end
end
