defmodule MediaCentaurWeb.ReviewLiveTest do
  @moduledoc """
  Review → Identity, the bulk list (campaign `review-bulk-match`). Rewritten
  2026-11-05 with the page: the master/detail groups by folder are gone, so
  the tests that drove `select_item`, `open_search` and `select_match` on a
  group are replaced by the same behaviours over ticked rows — the search,
  the type a match is saved under, arm-to-dismiss, arm-to-delete without
  ever removing a media root, live updates, the not-added reason, restore.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Review
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.TmdbStubs

  defp open(conn, path \\ "/review") do
    {:ok, view, _html} = live_async!(conn, path)
    render_async(view)
    view
  end

  defp waiting_episode(path, episode, overrides \\ %{}) do
    create_pending_file(
      Map.merge(
        %{
          file_path: path,
          media_directory: "/media/test",
          parsed_title: "Sample Show Signed",
          parsed_type: "tv",
          parsed_season: 1,
          parsed_episode: episode,
          tmdb_id: nil,
          tmdb_type: nil,
          confidence: nil,
          match_title: nil
        },
        overrides
      )
    )
  end

  defp tick(view, file), do: view |> element("#review-item-#{file.id}") |> render_click()

  defp waiting, do: Enum.filter(Review.list_queue(), &(&1.status == :pending))

  describe "GET /review" do
    test "first paint (disconnected render) lists the waiting files, not an empty flash", %{conn: conn} do
      create_pending_file(%{parsed_title: "First Paint Pending File", parsed_type: "movie"})

      html = conn |> get("/review") |> html_response(200)

      assert html =~ "First Paint Pending File",
             "waiting files must render on the disconnected first paint"
    end

    test "the empty queue says what lands in it", %{conn: conn} do
      assert render(open(conn)) =~ "Unmatched files show up here"
    end
  end

  # The case that opened the campaign: six episodes of one show, each in its
  # own release folder, none found on TMDB under the name they carry. One
  # tick on the divider, one search, one press.
  describe "matching episodes from separate release folders" do
    setup do
      enable_tmdb!()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())

      files =
        for episode <- 1..6 do
          waiting_episode(
            "/media/test/Sample.Show.Signed.S01E0#{episode}-GROUP/Sample.Show.Signed.S01E0#{episode}.mkv",
            episode
          )
        end

      TmdbStubs.stub_search_tv([
        TmdbStubs.tv_search_result(%{
          "id" => 4242,
          "name" => "Sample Show",
          "first_air_date" => "1995-04-21"
        })
      ])

      %{files: files}
    end

    test "the divider ticks all six; the bar searches the parsed title and one press matches them",
         %{conn: conn, files: [first | _] = files} do
      view = open(conn)

      view |> element("#review-divider-#{first.id}") |> render_click()
      render_until(view, "review-result-tv-4242")

      assert has_element?(view, "#review-match-bar", "6 files ticked")
      assert has_element?(view, "#review-search-form input[name='query'][value='Sample Show Signed']")

      view |> element("#review-result-tv-4242") |> render_click()

      for file <- files do
        path = file.file_path
        assert_receive {:file_matched, %{file_path: ^path, tmdb_id: 4242, tmdb_type: "tv"}}
      end

      assert render(view) =~ "Matched 6 files to Sample Show"
      refute has_element?(view, "#review-match-bar")
      assert waiting() == []
    end

    test "unticking a row leaves it out of the match", %{conn: conn, files: [first, second | _]} do
      view = open(conn)

      view |> element("#review-divider-#{first.id}") |> render_click()
      tick(view, second)
      render_until(view, "review-result-tv-4242")
      view |> element("#review-result-tv-4242") |> render_click()

      assert [%{id: left}] = waiting()
      assert left == second.id
    end
  end

  describe "the search" do
    setup do
      enable_tmdb!()
      :ok
    end

    # Regression (kept from the group page): a match was stamped with the
    # form's Type select, whatever found it. A result carries the type it
    # was searched as, so flipping the select afterwards cannot relabel it.
    test "a result is saved under the type it was searched as", %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Movie A",
          parsed_type: "movie",
          tmdb_id: nil,
          tmdb_type: nil
        })

      TmdbStubs.stub_search_movie([%{"id" => 777, "title" => "Movie A", "release_date" => "2001-01-01"}])

      view = open(conn)
      tick(view, file)
      render_until(view, "review-result-movie-777")

      view |> element("#review-result-movie-777") |> render_click()

      saved = MediaCentaur.Repo.get!(Review.PendingFile, file.id)
      assert {saved.tmdb_id, saved.tmdb_type, saved.status} == {777, "movie", :approved}
    end

    test "a typed query replaces the prefill and searches", %{conn: conn} do
      file = waiting_episode("/media/test/a.mkv", 1)
      TmdbStubs.stub_search_tv([TmdbStubs.tv_search_result(%{"id" => 99, "name" => "Other Show"})])

      view = open(conn)
      tick(view, file)

      view
      |> form("#review-search-form", %{"query" => "Other Show", "type" => "tv"})
      |> render_change()

      render_until(view, "review-result-tv-99")
      assert has_element?(view, "#review-search-form input[name='query'][value='Other Show']")
    end

    test "a crashed TMDB search clears searching and tells the user", %{conn: conn} do
      file = waiting_episode("/media/test/a.mkv", 1)
      Req.Test.stub(:tmdb, fn _conn -> raise "stub crashed" end)

      view = open(conn)
      tick(view, file)

      render_until(view, "TMDB search failed")
      refute has_element?(view, "#review-search-form button[disabled]")
    end
  end

  describe "accepting best guesses" do
    test "approves each ticked row under its own guess", %{conn: conn} do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())

      first =
        create_pending_file(%{file_path: "/media/test/Movie.A.mkv", parsed_title: "Movie A", tmdb_id: 1})

      second =
        create_pending_file(%{file_path: "/media/test/Movie.B.mkv", parsed_title: "Movie B", tmdb_id: 2})

      view = open(conn)
      tick(view, first)
      tick(view, second)
      view |> element("button", "Accept best guesses") |> render_click()

      assert_receive {:file_matched, %{file_path: "/media/test/Movie.A.mkv", tmdb_id: 1}}
      assert_receive {:file_matched, %{file_path: "/media/test/Movie.B.mkv", tmdb_id: 2}}
    end

    test "is not offered when a ticked row has no guess", %{conn: conn} do
      guessed = create_pending_file(%{parsed_title: "Movie A", tmdb_id: 1})
      unguessed = create_pending_file(%{parsed_title: "Movie B", tmdb_id: nil, tmdb_type: nil})

      view = open(conn)
      tick(view, guessed)
      tick(view, unguessed)

      refute has_element?(view, "button", "Accept best")
    end
  end

  describe "dismiss and restore" do
    test "Dismiss arms on the first press and fires on the second", %{conn: conn} do
      file = create_pending_file(%{parsed_title: "Dismissable Show", parsed_type: "tv"})

      view = open(conn)
      tick(view, file)

      assert view |> element("#review-match-bar button", "Dismiss") |> render_click() =~
               "Press again to dismiss"

      assert length(waiting()) == 1

      view |> element("#review-match-bar button", "Press again to dismiss") |> render_click()
      assert waiting() == []
    end

    test "a tick between the presses disarms", %{conn: conn} do
      first = create_pending_file(%{parsed_title: "AAA"})
      second = create_pending_file(%{parsed_title: "ZZZ"})

      view = open(conn)
      tick(view, first)
      view |> element("#review-match-bar button", "Dismiss") |> render_click()
      tick(view, second)

      refute render(view) =~ "Press again to dismiss"
    end

    test "the Dismissed view lists dismissed files, and Restore puts one back", %{conn: conn} do
      file = create_pending_file(%{parsed_title: "Restorable File"})
      {:ok, 1} = Review.dismiss([file.id])

      view = open(conn, "/review?status=dismissed")
      assert render(view) =~ "Restorable File"

      tick(view, file)
      view |> element("#review-match-bar button", "Restore") |> render_click()

      assert [%{id: restored}] = waiting()
      assert restored == file.id
    end
  end

  describe "delete" do
    setup do
      media_dir = Path.join(System.tmp_dir!(), "review_live_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(media_dir)
      on_exit(fn -> File.rm_rf!(media_dir) end)
      %{media_dir: media_dir}
    end

    test "the first press arms and names what goes; the second deletes the file", %{
      conn: conn,
      media_dir: media_dir
    } do
      release = Path.join(media_dir, "Broken.Release")
      File.mkdir_p!(release)
      path = Path.join(release, "broken.mkv")
      File.write!(path, "garbage")

      file =
        create_pending_file(%{
          file_path: path,
          media_directory: media_dir,
          parsed_title: "Broken Download"
        })

      view = open(conn)
      tick(view, file)
      render_async(view)

      assert view |> element("#review-match-bar button", "Delete") |> render_click() =~
               "Press again to delete 1 file and 1 folder"

      assert File.exists?(path), "the first press must only arm"

      view |> element("#review-match-bar button", "Press again to delete") |> render_click()
      render_async(view)

      refute File.exists?(release)
      refute render(view) =~ "Broken Download"
    end

    test "never deletes a configured media directory root — only the file", %{
      conn: conn,
      media_dir: media_dir
    } do
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        Map.put(config, :media_dirs, [media_dir])
      )

      path = Path.join(media_dir, "flat_movie.mkv")
      File.write!(path, "x")

      file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Flat Movie"})

      view = open(conn)
      tick(view, file)
      render_async(view)

      assert view |> element("#review-match-bar button", "Delete") |> render_click() =~
               "Press again to delete 1 file"

      view |> element("#review-match-bar button", "Press again to delete") |> render_click()
      render_async(view)

      refute File.exists?(path)
      assert File.dir?(media_dir), "the media directory root itself must never be removed"
    end
  end

  describe "the view" do
    test "the filter narrows the rows to the parsed title or file name", %{conn: conn} do
      create_pending_file(%{parsed_title: "Sample Show Signed"})
      create_pending_file(%{parsed_title: "Movie A"})

      view = open(conn, "/review?q=sample")

      assert render(view) =~ "Sample Show Signed"
      refute render(view) =~ "Movie A"
    end

    test "a filter that matches nothing says so and offers to clear it", %{conn: conn} do
      create_pending_file(%{parsed_title: "Movie A"})

      view = open(conn, "/review?q=nothing-like-it")

      assert render(view) =~ "Nothing here matches"
      assert has_element?(view, "button", "Clear the filter")
    end

    # Changed 2026-11-05: an approved file used to stay in its group marked
    # importing. It is listed in the Importing view until its file is
    # linked, which removes it.
    test "a matched file is listed under Importing until the library links it", %{conn: conn} do
      file = waiting_episode("/media/test/Approved Show/S01E01.mkv", 1, %{parsed_title: "Approved Show"})
      {:ok, 1} = Review.match([file.id], %{tmdb_id: 4242, tmdb_type: "tv", title: "Approved Show"})

      view = open(conn, "/review?status=importing")
      assert render(view) =~ "Approved Show"

      :ok = Review.file_linked(file.file_path)
      refute render_until(view, &(not String.contains?(&1, "Approved Show"))) =~ "Approved Show"
    end

    test "a file returned from the library shows why it was not added", %{conn: conn} do
      create_pending_file(%{
        parsed_title: "Returned File",
        parsed_type: "movie",
        error_message: "Adding it to the library failed. Approve it again to retry."
      })

      html = render(open(conn))

      assert html =~ "Not added"
      assert html =~ "Adding it to the library failed. Approve it again to retry."
    end

    test "a match contradicting a grab names the title the grab wanted, not a score", %{conn: conn} do
      create_pending_file(%{
        parsed_title: "Movie I",
        parsed_type: "movie",
        tmdb_id: 990_009,
        tmdb_type: "movie",
        match_title: "Movie I",
        confidence: 1.05,
        wanted_title: "Movie J"
      })

      html = render(open(conn))

      assert html =~ "Grab wanted Movie J"
      refute html =~ "105%"
    end

    test "file_added reloads the list after its debounce", %{conn: conn} do
      view = open(conn)
      create_pending_file(%{parsed_title: "Newly Arrived File", parsed_type: "movie"})

      send(view.pid, {:file_added, %FileAdded{pending_file_id: Ecto.UUID.generate()}})

      assert render_until(view, "Newly Arrived File") =~ "Newly Arrived File"
    end
  end

  describe "keyboard and gamepad reach" do
    test "the rows, the toolbar and, once a row is ticked, the bar are nav zones", %{conn: conn} do
      file = create_pending_file(%{parsed_title: "Sample Show"})

      view = open(conn)
      assert has_element?(view, "[data-nav-zone='review-toolbar'] [data-nav-item]")
      assert has_element?(view, "[data-nav-zone='review-rows'] #review-item-#{file.id}[data-nav-item]")
      refute has_element?(view, "[data-nav-zone='review-bar']")

      tick(view, file)
      assert has_element?(view, "[data-nav-zone='review-bar'] [data-nav-item]")
    end
  end
end
