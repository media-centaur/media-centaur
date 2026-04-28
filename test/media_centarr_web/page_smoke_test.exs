defmodule MediaCentarrWeb.PageSmokeTest do
  @moduledoc """
  Visits every top-level LiveView route and asserts it mounts and renders
  without crashing. This is the cheapest possible safety net for the kind
  of bug where adding a new assign or template variable trips a
  `KeyError` only on a specific page.

  Each route (and each zone of the library page) gets one test. If a page
  needs additional setup to mount (Prowlarr config, DB fixtures, etc.)
  the setup happens in this file so the smoke test stays isolated from
  the per-page test files.

  Where a zone has a non-trivial render branch (e.g. the upcoming zone's
  Active cards with theatrical / streaming / TV variants), the test
  seeds enough fixture data to exercise that branch — empty-state
  rendering catches a different (smaller) class of bug.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.{Config, Secret}

  for {path, label} <- [
        {"/", "home"},
        {"/library", "library browse"},
        {"/status", "status"},
        {"/settings", "settings"},
        {"/review", "review"},
        {"/console", "console"},
        {"/history", "watch history"},
        {"/upcoming", "upcoming"}
      ] do
    test "#{label} (#{path}) renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, unquote(path))
      assert is_binary(html)
    end
  end

  describe "/library?selected=<id> with movie that has ISO 8601 duration" do
    # Detail-panel metadata row formats `entity.duration` (ISO 8601) for
    # display. Calling the wrong formatter on this string crashes the
    # whole LiveView (ArithmeticError in :erlang.div/2). This smoke
    # ensures the metadata-row duration path renders for a movie shaped
    # like real production data.
    setup do
      movie =
        create_standalone_movie(%{
          name: "Smoke Movie With Duration",
          duration: "PT1H55M",
          date_published: "2008-07-18",
          content_rating: "PG-13"
        })

      {:ok, movie: movie}
    end

    test "library detail panel mounts for a movie with ISO 8601 duration",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = live(conn, ~p"/library?selected=#{movie.id}")
      assert is_binary(html)
    end
  end

  describe "/ with heavy rotation fixtures" do
    # Seeds a movie with 2 completions so the Heavy Rotation branch renders.
    # Covers the badge_label render path that empty-state can't reach.
    setup do
      movie = create_standalone_movie(%{name: "Heavy Rotation Movie"})

      Enum.each(1..2, fn _n ->
        create_watch_event(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: movie.name
        })
      end)

      :ok
    end

    test "home page with heavy rotation renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/")
      assert is_binary(html)
    end
  end

  describe "/?zone=upcoming with tracked-item fixtures" do
    # Fixture covers every shape the Active card path renders so a
    # render-time crash in any branch trips the smoke. Not data-correctness
    # — just "no clause / boolean / nil errors on the way to the screen".
    setup do
      tv_item =
        create_tracking_item(%{
          tmdb_id: 9_001,
          media_type: :tv_series,
          name: "Smoke TV Show"
        })

      # Two released-not-in-library episodes — exercises the active-row
      # status-icon path AND the "Queue all N" button branch (renders only
      # when pending_grab_count >= 2 with acquisition_ready).
      Enum.each(1..2, fn episode ->
        create_tracking_release(%{
          item_id: tv_item.id,
          air_date: Date.add(Date.utc_today(), -3 - episode),
          season_number: 1,
          episode_number: episode,
          title: "Episode #{episode}",
          released: true
        })
      end)

      # Upcoming — exercises the upcoming-row path inside the same card
      create_tracking_release(%{
        item_id: tv_item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 1,
        episode_number: 3,
        title: "Next Week",
        released: false
      })

      # Streaming movie — released, not in library
      streaming_movie =
        create_tracking_item(%{
          tmdb_id: 9_002,
          media_type: :movie,
          name: "Smoke Streaming Movie"
        })

      create_tracking_release(%{
        item_id: streaming_movie.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "Streaming",
        release_type: "digital",
        released: true
      })

      # Theatrical movie with NO home release dates — exercises the
      # "Home release: not yet announced" branch and is the exact shape
      # that previously crashed with `BadBooleanError` on the
      # `air_date and Date.compare(...)` expression.
      theatrical_movie =
        create_tracking_item(%{
          tmdb_id: 9_003,
          media_type: :movie,
          name: "Smoke Theatrical Movie"
        })

      create_tracking_release(%{
        item_id: theatrical_movie.id,
        air_date: Date.add(Date.utc_today(), -10),
        title: "Theatrical",
        release_type: "theatrical",
        released: true
      })

      # Theatrical movie WITH digital + physical release rows — exercises
      # the multi-line `home_release_lines/1` branch (Digital: …, Physical: …).
      home_release_movie =
        create_tracking_item(%{
          tmdb_id: 9_004,
          media_type: :movie,
          name: "Smoke Home Release Movie"
        })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), -20),
        title: "Theatrical",
        release_type: "theatrical",
        released: true
      })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), 30),
        title: "Digital",
        release_type: "digital",
        released: false
      })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), 60),
        title: "Physical",
        release_type: "physical",
        released: false
      })

      :ok
    end

    test "upcoming zone renders without crashing", %{conn: conn} do
      # /?zone=upcoming redirects to /upcoming (HomeLive handles zone params).
      assert {:error, {:live_redirect, %{to: "/upcoming"}}} = live(conn, "/?zone=upcoming")
      assert {:ok, _view, html} = live(conn, "/upcoming")
      assert is_binary(html)
    end
  end

  describe "/download" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)

      on_exit(fn ->
        MediaCentarr.Capabilities.clear_test_result(:prowlarr)
        :persistent_term.put({Config, :config}, original)
      end)

      :ok
    end

    test "renders without crashing (Prowlarr configured and tested)", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/download")
      assert is_binary(html)
    end
  end
end
