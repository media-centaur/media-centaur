defmodule MediaManager.Library.WatchedFile.Changes.SearchTmdbTest do
  use MediaManager.DataCase

  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
    :ok
  end

  defp detect_and_search(file_path, overrides \\ %{}) do
    file = create_watched_file(Map.merge(%{file_path: file_path}, overrides))

    file
    |> Ash.Changeset.for_update(:search, %{})
    |> Ash.update()
  end

  # ---------------------------------------------------------------------------
  # Search strategy by type
  # ---------------------------------------------------------------------------

  describe "search strategy by type" do
    test "movie type searches movies only" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{"id" => 550, "title" => "Sample Title Fi"})
           ]
         }}
      ])

      assert {:ok, file} =
               detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")

      assert file.tmdb_id == "550"
      assert file.match_title == "Sample Title Fi"
      assert file.state in [:approved, :pending_review]
    end

    test "tv type searches TV only" do
      stub_routes([
        {"/search/tv",
         %{
           "results" => [
             tv_search_result(%{"id" => 1396, "name" => "Sample Title Eh"})
           ]
         }}
      ])

      assert {:ok, file} =
               detect_and_search("/media/TV/Sample.Title.Eh/Season.01/Sample.Title.Eh.S01E01.mkv")

      assert file.tmdb_id == "1396"
      assert file.match_title == "Sample Title Eh"
    end

    test "unknown type searches both movie and tv, picks highest score" do
      stub_search_both(
        [movie_search_result(%{"id" => 550, "title" => "Sample Title Fi"})],
        [tv_search_result(%{"id" => 9999, "name" => "Totally Different Show"})]
      )

      # "Sample Title Fi" should score higher for a filename "Sample.Title.Fi"
      assert {:ok, file} = detect_and_search("/media/Sample.Title.Fi.mkv")

      assert file.tmdb_id == "550"
      assert file.match_title == "Sample Title Fi"
    end
  end

  # ---------------------------------------------------------------------------
  # Confidence thresholds
  # ---------------------------------------------------------------------------

  describe "confidence thresholds" do
    test "high confidence — state becomes :approved" do
      # Exact title match + year match + top result = high confidence
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Sample Title Fi",
               "release_date" => "1999-10-15"
             })
           ]
         }}
      ])

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.state == :approved
      assert file.confidence_score >= 0.85
    end

    test "low confidence — state becomes :pending_review" do
      # Very different title = low confidence
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 999,
               "title" => "Completely Unrelated Movie Title",
               "release_date" => "2020-01-01"
             })
           ]
         }}
      ])

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.state == :pending_review
      assert file.confidence_score < 0.85
    end

    test "no results — state becomes :pending_review" do
      stub_routes([
        {"/search/movie", %{"results" => []}},
        {"/search/tv", %{"results" => []}}
      ])

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.state == :pending_review
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "no parsed_title — state = :error immediately, no API call" do
      # Create a file and clear parsed_title via update_state
      file = create_watched_file(%{file_path: "/media/test.mkv"})

      file =
        file
        |> Ash.Changeset.for_update(:update_state, %{parsed_title: nil})
        |> Ash.update!()

      result =
        file
        |> Ash.Changeset.for_update(:search, %{})
        |> Ash.update()

      assert {:ok, searched} = result
      assert searched.state == :error
      assert searched.error_message =~ "no parsed title"
    end

    test "search_title overrides parsed_title" do
      # Stub both search endpoints since :unknown type searches both
      Req.Test.stub(:tmdb, fn conn ->
        cond do
          String.contains?(conn.request_path, "/search/movie") ->
            json_resp(conn, 200, %{
              "results" => [
                movie_search_result(%{"id" => 550, "title" => "Sample Title Fi"})
              ]
            })

          String.contains?(conn.request_path, "/search/tv") ->
            json_resp(conn, 200, %{"results" => []})

          true ->
            json_resp(conn, 404, %{"status_message" => "Not Found"})
        end
      end)

      file = create_watched_file(%{file_path: "/media/Movies/wrong_title.mkv"})

      file =
        file
        |> Ash.Changeset.for_update(:update_state, %{search_title: "Sample Title Fi"})
        |> Ash.update!()

      {:ok, searched} =
        file
        |> Ash.Changeset.for_update(:search, %{})
        |> Ash.update()

      assert searched.tmdb_id == "550"
      assert searched.match_title == "Sample Title Fi"
    end

    test "TMDB API error — state = :error with message" do
      stub_tmdb_error("/search/movie", 500)

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.state == :error
      assert file.error_message != nil
    end

    test "year extraction from release_date" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Sample Title Fi",
               "release_date" => "1999-10-15"
             })
           ]
         }}
      ])

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.match_year == "1999"
    end

    test "match_poster_path is stored from search results" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Sample Title Fi",
               "poster_path" => "/customPoster.jpg"
             })
           ]
         }}
      ])

      assert {:ok, file} = detect_and_search("/media/Movies/Sample.Title.Fi.1999.BluRay.mkv")
      assert file.match_poster_path == "/customPoster.jpg"
    end
  end

  defp json_resp(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(data))
  end
end
