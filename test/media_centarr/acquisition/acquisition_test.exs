defmodule MediaCentarr.AcquisitionTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{Grab, Prowlarr, SearchResult}
  alias MediaCentarr.Repo

  setup do
    # Oban runs jobs inline in tests (`testing: :inline` in config/test.exs).
    # Calling Acquisition.enqueue/4 therefore triggers SearchAndGrab.perform
    # immediately, which calls Prowlarr.search — install an empty-response
    # stub so the worker snoozes cleanly instead of crashing on no client.
    # We don't assert on the worker side-effects here (those tests live in
    # search_and_grab_test.exs); we only verify the grab row enqueue created.
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    # `Acquisition.grab/2` and `Acquisition.search/2` short-circuit with
    # `:not_configured` unless Config.available?/0 returns true (URL +
    # API key both present). Stub both via persistent_term so manual-grab
    # tests can exercise the unified path.
    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentarr.Secret.wrap("test-key"))
    )

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentarr.Config, :config}, config)
    end)

    :ok
  end

  describe "enqueue/4 — origin" do
    test "defaults to origin = auto" do
      assert {:ok, grab} = Acquisition.enqueue("100", "movie", "M")
      assert grab.origin == "auto"
    end

    test "accepts explicit origin opt" do
      assert {:ok, grab} = Acquisition.enqueue("101", "movie", "M2", origin: "auto")
      assert grab.origin == "auto"
    end
  end

  describe "grab/2 — manual unified path" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "submits to Prowlarr and inserts a manual-origin grab in terminal grabbed state" do
      result = %SearchResult{
        title: "Sample.Movie.2010.2160p.UHD.BluRay.REMUX-FGT",
        guid: "manual-guid-1",
        indexer_id: 1,
        quality: :uhd_4k
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)

      assert {:ok, %Grab{} = grab} = Acquisition.grab(result, "Inception 2010")

      assert grab.origin == "manual"
      assert grab.tmdb_type == "manual"
      assert grab.tmdb_id == "manual-guid-1"
      assert grab.prowlarr_guid == "manual-guid-1"
      assert grab.manual_query == "Inception 2010"
      assert grab.status == "grabbed"
      assert grab.quality == "4K"
      assert grab.grabbed_at != nil

      assert_received {:grab_submitted, %Grab{origin: "manual"}}
    end

    test "does NOT insert a row when Prowlarr rejects the grab" do
      result = %SearchResult{title: "Bad", guid: "fail-1", indexer_id: 1, quality: :hd_1080p}

      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, _} = Acquisition.grab(result, "bad")
      assert Repo.aggregate(Grab, :count) == 0
    end

    test "returns :not_configured when Prowlarr is not configured" do
      :persistent_term.erase({Prowlarr, :client})
      # Drop env so Config.available?/0 returns false.
      original_url = MediaCentarr.Config.get(:prowlarr_url)

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.put(:persistent_term.get({MediaCentarr.Config, :config}), :prowlarr_url, nil)
      )

      on_exit(fn ->
        :persistent_term.put(
          {MediaCentarr.Config, :config},
          Map.put(:persistent_term.get({MediaCentarr.Config, :config}), :prowlarr_url, original_url)
        )
      end)

      result = %SearchResult{title: "T", guid: "g", indexer_id: 1, quality: :uhd_4k}
      assert {:error, :not_configured} = Acquisition.grab(result, "t")
    end
  end

  describe "statuses_for_releases/1" do
    test "returns a map keyed by (tmdb_id, tmdb_type, season, episode) → grab" do
      {:ok, movie_grab} = Acquisition.enqueue("100", "movie", "M")

      {:ok, episode_grab} =
        Acquisition.enqueue("200", "tv", "S",
          season_number: 3,
          episode_number: 4
        )

      {:ok, season_pack_grab} =
        Acquisition.enqueue("200", "tv", "S", season_number: 5)

      keys = [
        {"100", "movie", nil, nil},
        {"200", "tv", 3, 4},
        {"200", "tv", 5, nil},
        # not-present key — should be absent from result map
        {"999", "movie", nil, nil}
      ]

      result = Acquisition.statuses_for_releases(keys)

      assert result[{"100", "movie", nil, nil}].id == movie_grab.id
      assert result[{"200", "tv", 3, 4}].id == episode_grab.id
      assert result[{"200", "tv", 5, nil}].id == season_pack_grab.id
      refute Map.has_key?(result, {"999", "movie", nil, nil})
    end

    test "returns an empty map for an empty input list (no DB query)" do
      assert Acquisition.statuses_for_releases([]) == %{}
    end

    test "ignores manual-origin grabs (their tmdb_type='manual' never matches release keys)" do
      result = %SearchResult{
        title: "Manual.Inception.1080p",
        guid: "guid-skip",
        indexer_id: 1,
        quality: :hd_1080p
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)
      {:ok, _} = Acquisition.grab(result, "Sample Movie")

      assert Acquisition.statuses_for_releases([{"guid-skip", "manual", nil, nil}]) ==
               %{
                 {"guid-skip", "manual", nil, nil} => Repo.get_by!(Grab, prowlarr_guid: "guid-skip")
               }

      # But a movie key for the same title doesn't pull the manual row.
      assert Acquisition.statuses_for_releases([{"some-tmdb-id", "movie", nil, nil}]) == %{}
    end
  end

  describe "list_auto_grabs/1 — origin column" do
    test ":all returns rows of both origins" do
      _ = Acquisition.enqueue("200", "movie", "Auto")

      result = %SearchResult{
        title: "Manual.Title.1080p",
        guid: "g-mix",
        indexer_id: 1,
        quality: :hd_1080p
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)
      {:ok, _} = Acquisition.grab(result, "manual")

      origins = Acquisition.list_auto_grabs(:all) |> Enum.map(& &1.origin) |> Enum.sort()
      assert origins == ["auto", "manual"]
    end
  end

  describe "enqueue/4 — granularity" do
    test "movie key uses NULL season and episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("12345", "movie", "Sample Movie", year: 2010)

      assert grab.season_number == nil
      assert grab.episode_number == nil
      assert grab.year == 2010
      assert grab.status == "searching"
    end

    test "TV episode key carries season and episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 4
               )

      assert grab.tmdb_type == "tv"
      assert grab.season_number == 3
      assert grab.episode_number == 4
    end

    test "TV season pack uses non-NULL season with NULL episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("999", "tv", "Sample Show", season_number: 3)

      assert grab.season_number == 3
      assert grab.episode_number == nil
    end
  end

  describe "enqueue/4 — idempotency on the four-tuple" do
    test "second call for same (tmdb_id, type, season, episode) returns the existing grab" do
      assert {:ok, first} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 4
               )

      assert {:ok, second} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 4
               )

      assert first.id == second.id
    end

    test "different episode of same series creates a separate grab" do
      assert {:ok, e4} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 4
               )

      assert {:ok, e5} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 5
               )

      assert e4.id != e5.id
    end

    test "movie and TV with the same tmdb_id are independent rows (different tmdb_type)" do
      assert {:ok, movie} = Acquisition.enqueue("999", "movie", "Same Number")
      assert {:ok, tv} = Acquisition.enqueue("999", "tv", "Same Number")
      assert movie.id != tv.id
    end
  end

  describe "list_auto_grabs/1" do
    test ":all returns every row, newest-updated first" do
      grab1 = create_grab(%{tmdb_id: "1", title: "First"})
      grab2 = create_grab(%{tmdb_id: "2", title: "Second"})
      _ = Repo.update!(Grab.cancelled_changeset(grab1, "x"))

      assert grabs = Acquisition.list_auto_grabs(:all)
      assert length(grabs) == 2
      assert Enum.find(grabs, &(&1.id == grab1.id))
      assert Enum.find(grabs, &(&1.id == grab2.id))
    end

    test ":active returns only searching/snoozed (excludes terminal states)" do
      _searching = create_grab(%{tmdb_id: "10", title: "Searching"})
      snoozed = create_grab(%{tmdb_id: "11", title: "Snoozed"})
      Repo.update!(Grab.attempt_changeset(snoozed, "no_results", snoozed: true))
      grabbed = create_grab(%{tmdb_id: "12", title: "Grabbed"})
      Repo.update!(Grab.grabbed_changeset(grabbed, "4K"))
      cancelled = create_grab(%{tmdb_id: "13", title: "Cancelled"})
      Repo.update!(Grab.cancelled_changeset(cancelled, "x"))

      titles = Acquisition.list_auto_grabs(:active) |> Enum.map(& &1.title) |> Enum.sort()
      assert titles == ["Searching", "Snoozed"]
    end

    test ":abandoned returns only abandoned" do
      grab = create_grab(%{tmdb_id: "20", title: "Lost cause"})
      Repo.update!(Grab.abandoned_changeset(grab))

      assert [%Grab{title: "Lost cause"}] = Acquisition.list_auto_grabs(:abandoned)
    end
  end

  describe "rearm_grab/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "flips a cancelled grab back to searching, resets attempts, broadcasts" do
      grab = create_grab(%{tmdb_id: "rearm-1", title: "Comeback", attempt_count: 5})
      Repo.update!(Grab.cancelled_changeset(grab, "user_disabled"))

      assert {:ok, rearmed} = Acquisition.rearm_grab(grab.id)

      assert rearmed.status == "searching"
      assert rearmed.attempt_count == 0
      assert rearmed.cancelled_at == nil
      assert rearmed.cancelled_reason == nil
      assert_received {:auto_grab_armed, %Grab{title: "Comeback"}}
    end

    test "flips an abandoned grab back to searching" do
      grab = create_grab(%{tmdb_id: "rearm-2", title: "Abandoned", attempt_count: 12})
      Repo.update!(Grab.abandoned_changeset(grab))

      assert {:ok, rearmed} = Acquisition.rearm_grab(grab.id)
      assert rearmed.status == "searching"
      assert rearmed.attempt_count == 0
    end

    test "is a no-op for active grabs (already searching/snoozed)" do
      grab = create_grab(%{tmdb_id: "rearm-3", title: "Already going"})

      assert {:ok, ^grab} = Acquisition.rearm_grab(grab.id)
      refute_received {:auto_grab_armed, _}
    end

    test "is a no-op for grabbed grabs" do
      grab = create_grab(%{tmdb_id: "rearm-4", title: "Already done"})
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "4K"))

      assert {:ok, ^grabbed} = Acquisition.rearm_grab(grabbed.id)
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Acquisition.rearm_grab(Ecto.UUID.generate())
    end
  end

  describe "cancel_grab/2" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "marks status cancelled, sets reason and timestamp, broadcasts" do
      grab = create_grab()

      assert {:ok, cancelled} = Acquisition.cancel_grab(grab.id, "user_disabled")

      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_reason == "user_disabled"
      assert cancelled.cancelled_at != nil
      assert_received {:auto_grab_cancelled, %Grab{cancelled_reason: "user_disabled"}}
    end

    test "returns :not_found for unknown grab id" do
      assert {:error, :not_found} = Acquisition.cancel_grab(Ecto.UUID.generate(), "x")
    end

    test "is a no-op (no broadcast) on a grab that is already grabbed" do
      grab = create_grab()
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "4K"))

      assert {:ok, ^grabbed} = Acquisition.cancel_grab(grabbed.id, "user_disabled")
      assert grabbed.status == "grabbed"
      refute_received {:auto_grab_cancelled, _}
    end
  end

  describe "enqueue_all_pending_for_item/1" do
    test "returns :not_found for an unknown item id" do
      assert {:error, :not_found} = Acquisition.enqueue_all_pending_for_item(Ecto.UUID.generate())
    end

    test "enqueues a grab per pending TV episode and reports the count" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_001,
          media_type: :tv_series,
          name: "Bulk Show"
        })

      Enum.each(1..3, fn episode ->
        create_tracking_release(%{
          item_id: item.id,
          season_number: 5,
          episode_number: episode,
          released: true
        })
      end)

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 3
      assert summary.rearmed == 0
      assert summary.in_progress == 0
      assert summary.already_grabbed == 0
      assert summary.failed == []

      grabs =
        Repo.all(
          from(g in Grab,
            where: g.tmdb_id == "7001" and g.tmdb_type == "tv",
            order_by: g.episode_number
          )
        )

      assert length(grabs) == 3
      assert Enum.map(grabs, & &1.episode_number) == [1, 2, 3]
    end

    test "skips releases with an active (searching/snoozed) grab as in_progress" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_002,
          media_type: :tv_series,
          name: "Half-flighted"
        })

      Enum.each(1..3, fn episode ->
        create_tracking_release(%{
          item_id: item.id,
          season_number: 1,
          episode_number: episode,
          released: true
        })
      end)

      # Pre-existing grab for episode 2 (still searching).
      {:ok, _} =
        Acquisition.enqueue("7002", "tv", "Half-flighted",
          season_number: 1,
          episode_number: 2
        )

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 2
      assert summary.in_progress == 1
      assert summary.rearmed == 0
      assert summary.already_grabbed == 0
    end

    test "re-arms cancelled and abandoned grabs back to searching" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_006,
          media_type: :tv_series,
          name: "Reanimate"
        })

      Enum.each(1..3, fn episode ->
        create_tracking_release(%{
          item_id: item.id,
          season_number: 1,
          episode_number: episode,
          released: true
        })
      end)

      {:ok, ep1} =
        Acquisition.enqueue("7006", "tv", "Reanimate", season_number: 1, episode_number: 1)

      {:ok, ep2} =
        Acquisition.enqueue("7006", "tv", "Reanimate", season_number: 1, episode_number: 2)

      {:ok, _} = Acquisition.cancel_grab(ep1.id, "user_cancelled")

      {:ok, _} =
        ep2
        |> Ecto.Changeset.change(status: "abandoned")
        |> MediaCentarr.Repo.update()

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 1
      assert summary.rearmed == 2
      assert summary.in_progress == 0
      assert summary.already_grabbed == 0

      # Re-armed grabs are active again. Oban runs the SearchAndGrab job
      # inline in tests, so they may have already transitioned from
      # `searching` → `snoozed` if the prowlarr stub returned no results.
      ep1_after = MediaCentarr.Repo.get(Grab, ep1.id)
      ep2_after = MediaCentarr.Repo.get(Grab, ep2.id)
      assert ep1_after.status in ["searching", "snoozed"]
      assert ep2_after.status in ["searching", "snoozed"]
    end

    test "skips successfully grabbed releases as already_grabbed" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_007,
          media_type: :tv_series,
          name: "Done Already"
        })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 1,
        released: true
      })

      {:ok, grab} =
        Acquisition.enqueue("7007", "tv", "Done Already", season_number: 1, episode_number: 1)

      {:ok, _} =
        grab
        |> Ecto.Changeset.change(status: "grabbed")
        |> MediaCentarr.Repo.update()

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 0
      assert summary.rearmed == 0
      assert summary.in_progress == 0
      assert summary.already_grabbed == 1
    end

    test "ignores not-released and already-in-library releases" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_003,
          media_type: :tv_series,
          name: "Mostly Not Pending"
        })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 1,
        released: true,
        in_library: true
      })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 2,
        released: false
      })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 3,
        released: true
      })

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 1
    end

    test "treats a movie's digital + physical releases as a single grab key" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_004,
          media_type: :movie,
          name: "Both Formats"
        })

      create_tracking_release(%{
        item_id: item.id,
        title: "Digital",
        released: true,
        release_type: "digital"
      })

      create_tracking_release(%{
        item_id: item.id,
        title: "Physical",
        released: true,
        release_type: "physical"
      })

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 1

      grabs = Repo.all(from(g in Grab, where: g.tmdb_id == "7004"))
      assert length(grabs) == 1
    end

    test "ignores theatrical-only movie items (no acquirable releases)" do
      item =
        create_tracking_item(%{
          tmdb_id: 7_005,
          media_type: :movie,
          name: "In Theaters"
        })

      create_tracking_release(%{
        item_id: item.id,
        title: "Theatrical",
        released: true,
        release_type: "theatrical"
      })

      assert {:ok, summary} = Acquisition.enqueue_all_pending_for_item(item.id)
      assert summary.queued == 0
      assert summary.rearmed == 0
      assert summary.in_progress == 0
      assert summary.already_grabbed == 0
    end
  end

  describe "handle_release_ready_event/2 — media_type → tmdb_type translation" do
    # Regression: an earlier version stringified item.media_type with
    # to_string/1, persisting the Ecto enum form ("tv_series") into Grab.tmdb_type.
    # QueryBuilder.build/1 only matches the TMDB-standard "tv" / "movie", so every
    # auto-armed TV grab crashed on the first SearchAndGrab wake — the row stayed
    # at attempts: 0, last_attempt_at: nil while Oban silently retried.
    setup do
      MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    test ~s{a :tv_series item produces a grab with tmdb_type="tv" (not "tv_series")} do
      item =
        create_tracking_item(%{
          tmdb_id: 4242,
          media_type: :tv_series,
          name: "TV Show"
        })

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: Date.add(Date.utc_today(), -1),
          title: "S01E01",
          season_number: 1,
          episode_number: 1,
          released: true,
          in_library: false,
          release_type: "digital"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Acquisition.handle_release_ready_event(item, release)
      end)

      [grab] = Repo.all(from g in Grab, where: g.tmdb_id == "4242")
      assert grab.tmdb_type == "tv"
    end

    test "a :movie item produces a grab with tmdb_type=\"movie\"" do
      item =
        create_tracking_item(%{
          tmdb_id: 4243,
          media_type: :movie,
          name: "A Movie"
        })

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: Date.add(Date.utc_today(), -1),
          title: "A Movie",
          released: true,
          in_library: false,
          release_type: "digital"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Acquisition.handle_release_ready_event(item, release)
      end)

      [grab] = Repo.all(from g in Grab, where: g.tmdb_id == "4243")
      assert grab.tmdb_type == "movie"
    end
  end

  describe "auto-grab service toggle" do
    # The auto-grab service is on by default but can be turned off per
    # environment (e.g. dev paused while prod runs) via the Settings page.
    # `pause_auto_grab/0` pauses the Oban :acquisition queue; while paused,
    # `:release_ready` events are dropped without arming a grab — manual
    # grabs and `:item_removed` cancellation keep working.
    setup do
      MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)

      on_exit(fn ->
        # Defensive — ensure we never leave the queue paused for a later test.
        Acquisition.resume_auto_grab()
      end)

      :ok
    end

    test "auto_grab_running?/0 reflects pause/resume" do
      assert Acquisition.auto_grab_running?()
      Acquisition.pause_auto_grab()
      refute Acquisition.auto_grab_running?()
      Acquisition.resume_auto_grab()
      assert Acquisition.auto_grab_running?()
    end

    test "handle_release_ready_event/2 is a no-op while paused — no grab row created" do
      Acquisition.pause_auto_grab()

      item =
        create_tracking_item(%{tmdb_id: 9001, media_type: :tv_series, name: "Paused Show"})

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: Date.add(Date.utc_today(), -1),
          title: "S01E01",
          season_number: 1,
          episode_number: 1,
          released: true,
          in_library: false,
          release_type: "digital"
        })

      assert :ok = Acquisition.handle_release_ready_event(item, release)

      assert Repo.all(from g in Grab, where: g.tmdb_id == "9001") == []
    end

    test "after resume, handle_release_ready_event/2 arms grabs again" do
      Acquisition.pause_auto_grab()
      Acquisition.resume_auto_grab()

      item =
        create_tracking_item(%{tmdb_id: 9002, media_type: :tv_series, name: "Resumed Show"})

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: Date.add(Date.utc_today(), -1),
          title: "S01E01",
          season_number: 1,
          episode_number: 1,
          released: true,
          in_library: false,
          release_type: "digital"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Acquisition.handle_release_ready_event(item, release)
      end)

      [grab] = Repo.all(from g in Grab, where: g.tmdb_id == "9002")
      assert grab.tmdb_type == "tv"
    end
  end
end
