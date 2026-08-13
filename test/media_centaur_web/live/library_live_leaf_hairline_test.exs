defmodule MediaCentaurWeb.LibraryLiveLeafHairlineTest do
  @moduledoc """
  UIDR-024: leaves (standalone movies, collection members) carry watched
  progress in the hero orientation hairline — the same idiom TV series
  already use — and the remaining time rides the metadata line as its
  final item ("29m left"), displacing the status while present. No
  progress gauge or remaining copy renders in the card area below.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  describe "standalone movie" do
    setup do
      movie =
        create_movie(%{
          name: "Hairline Fixture Movie",
          description: "A sample synopsis about a fictional heist.",
          status: :released,
          duration_seconds: 7200,
          date_published: ~D[2018-01-01],
          content_url: "/movies/hairline-fixture.mkv"
        })

      {:ok, movie: movie}
    end

    test "mid-watch: hairline carries the movie's fraction, metadata carries the remaining time",
         %{conn: conn, movie: movie} do
      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 5400.0,
        duration_seconds: 7200.0
      })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="75"]|
             )

      modal_html = view |> element("#detail-modal") |> render()
      assert modal_html =~ "30m left"
      refute modal_html =~ "30m remaining"

      # Status is displaced while a remaining figure exists — a title you
      # are 75% through is self-evidently released.
      refute modal_html =~ "Released"
    end

    test "unstarted: bare track at zero, metadata line unchanged",
         %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="0"]|
             )

      modal_html = view |> element("#detail-modal") |> render()
      assert modal_html =~ "Released"
      refute modal_html =~ ~r/\d+m left/
    end

    test "fully watched: hairline fills, remaining copy absent, status returns",
         %{conn: conn, movie: movie} do
      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 0.0,
        duration_seconds: 0.0,
        completed: true
      })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="100"]|
             )

      modal_html = view |> element("#detail-modal") |> render()
      assert modal_html =~ "Released"
      refute modal_html =~ ~r/\d+m left/
      refute modal_html =~ ~r/\d+m remaining/
    end
  end

  describe "collection member" do
    setup do
      collection = create_movie_series(%{name: "Hairline Collection"})

      [part_1, part_2] =
        for {name, position} <- [{"Hairline Part 1", 0}, {"Hairline Part 2", 1}] do
          part =
            create_movie(%{
              movie_series_id: collection.id,
              name: name,
              position: position,
              description: "#{name} synopsis: the hills again.",
              duration_seconds: 3600
            })

          create_linked_file(%{movie_id: part.id})
          part
        end

      {:ok, collection: collection, part_1: part_1, part_2: part_2}
    end

    test "hairline shows the selected member's own fraction and agrees with its rail tile",
         %{conn: conn, collection: collection, part_1: part_1, part_2: part_2} do
      create_watch_progress(%{
        movie_id: part_1.id,
        position_seconds: 0.0,
        duration_seconds: 0.0,
        completed: true
      })

      create_watch_progress(%{
        movie_id: part_2.id,
        position_seconds: 900.0,
        duration_seconds: 3600.0
      })

      # Resume target is the in-progress part 2 → its fraction, not the
      # collection's.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="25"]|
             )

      modal_html = view |> element("#detail-modal") |> render()
      assert modal_html =~ "45m left"

      # The rail tile carries the same member state the hero shows.
      assert has_element?(view, "#rail-tile-#{part_2.id} [data-rail-state='current']")

      # Re-anchoring onto the watched member re-anchors the hairline too.
      view
      |> element("#rail-tile-#{part_1.id}")
      |> render_click()

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="100"]|
             )

      refute view |> element("#detail-modal") |> render() =~ ~r/\d+m left/
    end

    test "unstarted member shows the bare track",
         %{conn: conn, collection: collection} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Movie progress"][aria-valuenow="0"]|
             )
    end
  end

  describe "TV series" do
    test "keeps the series-fraction hairline, labeled for the series", %{conn: conn} do
      tv_series = create_tv_series(%{name: "Hairline Fixture Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      for episode_number <- 1..2 do
        create_episode(%{
          season_id: season.id,
          episode_number: episode_number,
          name: "Episode S1E#{episode_number}",
          duration_seconds: 1260,
          content_url: "/tv/hairline-show/s01e0#{episode_number}.mkv"
        })
      end

      [first_episode | _rest] = MediaCentaur.Library.Episodes.list_for_season(season.id)

      create_watch_progress(%{
        episode_id: first_episode.id,
        position_seconds: 0.0,
        duration_seconds: 0.0,
        completed: true
      })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(
               view,
               ~s|[role="progressbar"][aria-label="Series progress"][aria-valuenow="50"]|
             )
    end
  end
end
