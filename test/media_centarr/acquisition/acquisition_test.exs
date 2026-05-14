defmodule MediaCentarr.AcquisitionTest do
  use MediaCentarr.DataCase, async: false
  use Oban.Testing, repo: MediaCentarr.Repo

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{Prowlarr, SearchResult, Target, TargetEvents}
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Repo

  setup do
    # Oban runs jobs inline in tests (`testing: :inline` in config/test.exs).
    # Calling Acquisition.enqueue/4 triggers PursueTarget.perform immediately,
    # which calls Prowlarr.search — install an empty-response stub so the
    # worker snoozes cleanly instead of crashing.
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

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
      assert {:ok, target} = Acquisition.enqueue("100", "movie", "M")
      assert target.origin == "auto"
      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.origin == "auto"
    end

    test "accepts explicit origin opt" do
      assert {:ok, target} = Acquisition.enqueue("101", "movie", "M2", origin: "auto")
      assert target.origin == "auto"
    end
  end

  describe "PursueTarget snooze — next_attempt_at denormalisation" do
    # The suite-level setup stubs Prowlarr with empty results, so the
    # worker runs through `handle_no_results/3` and snoozes — perfect
    # for asserting that `next_attempt_at` lands on the target row in
    # the same transaction.
    test "writes next_attempt_at when snoozing after a no-results attempt" do
      before = DateTime.utc_now()
      assert {:ok, target} = Acquisition.enqueue("snooze-1", "movie", "Sample Movie")
      after_call = DateTime.utc_now()

      latest = Repo.get!(Target, target.id)

      assert latest.status == "seeking"
      assert %DateTime{} = latest.next_attempt_at
      # First-attempt snooze is 4h (2^0 * 4); allow a wide window.
      assert DateTime.diff(latest.next_attempt_at, before, :second) >= 3600
      assert DateTime.diff(latest.next_attempt_at, after_call, :second) >= 3600
    end
  end

  describe "pick_target/2 — manual unified path" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "submits to Prowlarr and inserts a manual-origin target in acquired state" do
      result = %SearchResult{
        title: "Sample.Movie.2010.2160p.UHD.BluRay.REMUX-FGT",
        guid: "manual-guid-1",
        indexer_id: 1,
        quality: :uhd_4k
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)

      assert {:ok, %Target{} = target} = Acquisition.pick_target(result, "Sample Movie 2010")

      assert target.origin == "manual"
      assert target.prowlarr_guid == "manual-guid-1"
      assert target.status == "acquired"
      assert target.quality == "4K"

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.recipe_type == "prowlarr_query"
      assert pursuit.manual_query == "Sample Movie 2010"

      assert_received %TargetEvents.Picked{target: %Target{origin: "manual"}}
    end

    test "does NOT insert a row when Prowlarr rejects the grab" do
      result = %SearchResult{title: "Bad", guid: "fail-1", indexer_id: 1, quality: :hd_1080p}

      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, _} = Acquisition.pick_target(result, "bad")
      assert Repo.aggregate(Target, :count) == 0
    end

    test "returns :not_configured when Prowlarr is not configured" do
      :persistent_term.erase({Prowlarr, :client})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.put(:persistent_term.get({MediaCentarr.Config, :config}), :prowlarr_url, nil)
      )

      result = %SearchResult{title: "T", guid: "g", indexer_id: 1, quality: :uhd_4k}
      assert {:error, :not_configured} = Acquisition.pick_target(result, "t")
    end
  end

  describe "statuses_for_releases/1" do
    test "returns a map keyed by (tmdb_id, tmdb_type, season, episode) → {pursuit, target}" do
      {:ok, movie_target} = Acquisition.enqueue("100", "movie", "M")

      {:ok, episode_target} =
        Acquisition.enqueue("200", "tv", "S",
          season_number: 3,
          episode_number: 4
        )

      {:ok, season_pack_target} =
        Acquisition.enqueue("200", "tv", "S", season_number: 5)

      keys = [
        {"100", "movie", nil, nil},
        {"200", "tv", 3, 4},
        {"200", "tv", 5, nil},
        # not-present key — should be absent from result map
        {"999", "movie", nil, nil}
      ]

      result = Acquisition.statuses_for_releases(keys)

      assert {_, %Target{id: id1}} = result[{"100", "movie", nil, nil}]
      assert id1 == movie_target.id

      assert {_, %Target{id: id2}} = result[{"200", "tv", 3, 4}]
      assert id2 == episode_target.id

      assert {_, %Target{id: id3}} = result[{"200", "tv", 5, nil}]
      assert id3 == season_pack_target.id

      refute Map.has_key?(result, {"999", "movie", nil, nil})
    end

    test "returns an empty map for an empty input list (no DB query)" do
      assert Acquisition.statuses_for_releases([]) == %{}
    end
  end

  describe "enqueue/4 — granularity" do
    test "movie key uses NULL season and episode" do
      assert {:ok, %Target{} = target} =
               Acquisition.enqueue("12345", "movie", "Sample Movie", year: 2010)

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.season_number == nil
      assert pursuit.episode_number == nil
      assert pursuit.year == 2010
      assert target.status == "seeking"
    end

    test "TV episode key carries season and episode on the pursuit" do
      assert {:ok, %Target{} = target} =
               Acquisition.enqueue("999", "tv", "Sample Show",
                 season_number: 3,
                 episode_number: 4
               )

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.tmdb_type == "tv"
      assert pursuit.season_number == 3
      assert pursuit.episode_number == 4
    end

    test "TV season pack uses non-NULL season with NULL episode on the pursuit" do
      assert {:ok, %Target{} = target} =
               Acquisition.enqueue("999", "tv", "Sample Show", season_number: 3)

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.season_number == 3
      assert pursuit.episode_number == nil
    end
  end

  describe "enqueue/4 — idempotency on the four-tuple" do
    test "second call for same (tmdb_id, type, season, episode) returns the existing target" do
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

    test "different episode of same series creates a separate target" do
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

    test "movie and TV with the same tmdb_id are independent (different tmdb_type)" do
      assert {:ok, movie} = Acquisition.enqueue("999", "movie", "Same Number")
      assert {:ok, tv} = Acquisition.enqueue("999", "tv", "Same Number")
      assert movie.id != tv.id
    end
  end

  describe "list_auto_targets/1" do
    test ":all returns every target" do
      _t1 = create_target(%{tmdb_id: "1", title: "First"})
      _t2 = create_target(%{tmdb_id: "2", title: "Second"})

      assert targets = Acquisition.list_auto_targets(:all)
      assert length(targets) == 2
    end
  end

  describe "rearm_target/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "flips a cancelled target back to seeking, broadcasts" do
      target = create_target(%{tmdb_id: "rearm-1", title: "Comeback"})

      target
      |> Ecto.Changeset.change(status: "cancelled", cancelled_reason: "user_disabled")
      |> Repo.update!()

      assert {:ok, rearmed} = Acquisition.rearm_target(target.id)

      assert rearmed.status == "seeking"
      assert rearmed.cancelled_at == nil
      assert rearmed.cancelled_reason == nil
      assert_received %TargetEvents.Armed{target: %Target{}}
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Acquisition.rearm_target(Ecto.UUID.generate())
    end
  end

  describe "cancel_target/2" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "marks status cancelled, sets reason and timestamp, broadcasts" do
      target = create_target()

      assert {:ok, cancelled} = Acquisition.cancel_target(target.id, "user_disabled")

      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_reason == "user_disabled"
      assert cancelled.cancelled_at != nil
      assert_received %TargetEvents.Cancelled{target: %Target{cancelled_reason: "user_disabled"}}
    end

    test "returns :not_found for unknown target id" do
      assert {:error, :not_found} = Acquisition.cancel_target(Ecto.UUID.generate(), "x")
    end
  end

  describe "pursuit linkage" do
    test "enqueue/4 creates a pursuit and links the new target to it" do
      assert {:ok, target} = Acquisition.enqueue("8001", "movie", "Sample Movie")

      refute is_nil(target.pursuit_id)

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.tmdb_id == "8001"
      assert pursuit.tmdb_type == "movie"
      assert pursuit.title == "Sample Movie"
      assert pursuit.state == "active"
      assert pursuit.origin == "auto"
      assert pursuit.recipe_type == "tmdb"
    end

    test "enqueue/4 idempotency: second call for same key returns existing target and same pursuit" do
      assert {:ok, first} = Acquisition.enqueue("8002", "movie", "Sample Movie")
      assert {:ok, second} = Acquisition.enqueue("8002", "movie", "Sample Movie")

      assert first.id == second.id
      assert first.pursuit_id == second.pursuit_id
    end

    test "pick_target/2 (manual) creates a pursuit linked to the target" do
      result = %SearchResult{
        title: "Sample.Movie.2010.2160p.UHD.BluRay-FGT",
        guid: "manual-guid-9001",
        indexer_id: 1,
        quality: :uhd_4k
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)

      assert {:ok, target} = Acquisition.pick_target(result, "Sample Movie 2010")

      refute is_nil(target.pursuit_id)

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.origin == "manual"
      assert pursuit.recipe_type == "prowlarr_query"
    end
  end

  describe "search_expanded/2 — brace-aware Prowlarr search" do
    test "expands a single brace list into N parallel searches and merges results" do
      # Record every query string Prowlarr receives so we can assert on
      # the fan-out shape. The stub yields a unique result per query so
      # the merged list lets us also assert dedup-by-guid works.
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:prowlarr_query, conn.query_params["query"] || body})

        result = %{
          "title" => "Result for #{conn.query_params["query"]}",
          "guid" => "guid-#{conn.query_params["query"]}",
          "indexerId" => 1,
          "size" => 1_000_000_000,
          "seeders" => 10,
          "leechers" => 0,
          "indexer" => "Test Indexer",
          "publishDate" => "2026-04-01T00:00:00Z"
        }

        Req.Test.json(conn, [result])
      end)

      assert {:ok, results} =
               Acquisition.search_expanded("Sample Show S01E{01,02,03}")

      # Three concrete queries fired (order is non-deterministic since
      # Task.async_stream parallelises).
      queries =
        for _ <- 1..3 do
          assert_received {:prowlarr_query, q}
          q
        end

      assert Enum.sort(queries) == [
               "Sample Show S01E01",
               "Sample Show S01E02",
               "Sample Show S01E03"
             ]

      # Three unique guids → three merged results, no duplicates.
      assert length(results) == 3
      assert Enum.sort(Enum.map(results, & &1.guid)) == Enum.map(Enum.sort(queries), &"guid-#{&1}")
    end

    test "no braces fans out to a single search (returns same shape as search/2)" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2049.1080p.WEB-DL",
            "guid" => "guid-one",
            "indexerId" => 1,
            "size" => 1_000_000_000,
            "seeders" => 10,
            "leechers" => 0,
            "indexer" => "Test Indexer",
            "publishDate" => "2026-04-01T00:00:00Z"
          }
        ])
      end)

      assert {:ok, [%SearchResult{guid: "guid-one"}]} =
               Acquisition.search_expanded("Sample Movie 2049")
    end

    test "returns {:error, :invalid_syntax} when braces are malformed" do
      assert {:error, :invalid_syntax} = Acquisition.search_expanded("bad {a,b{c}")
    end
  end

  describe "list_alternatives_for/1 — pursuit recipe contract" do
    test "expands brace syntax in manual_query for a prowlarr_query pursuit" do
      # The pursuit was created from a manual search like
      # "Sample Show S01E{01,02}". The decision card's refresh path goes
      # through `list_alternatives_for/1`, which must use the same
      # brace-aware fan-out as the original search — otherwise Prowlarr
      # receives the literal `S01E{01,02}` and returns nothing.
      # Factory's create_changeset always casts as recipe_type=tmdb first
      # (so tmdb_id/tmdb_type are required for the initial insert);
      # the prowlarr_query overlay is applied via Ecto.Changeset.change
      # after the insert. Dummy tmdb values get the row through.
      pursuit =
        create_pursuit(%{
          tmdb_id: "9999",
          tmdb_type: "tv",
          title: "Sample.Show.S01E01.1080p.WEB-DL",
          recipe_type: "prowlarr_query",
          manual_query: "Sample Show S01E{01,02}",
          origin: "manual"
        })

      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        q = conn.query_params["query"]
        send(test_pid, {:prowlarr_query, q})

        Req.Test.json(conn, [
          %{
            "title" => "Result for #{q}",
            "guid" => "guid-#{q}",
            "indexerId" => 1,
            "size" => 1_000_000_000,
            "seeders" => 10,
            "leechers" => 0,
            "indexer" => "Test Indexer",
            "publishDate" => "2026-04-01T00:00:00Z"
          }
        ])
      end)

      results = Acquisition.list_alternatives_for(pursuit)

      # Prowlarr saw the two expanded queries, not the literal braces.
      assert_received {:prowlarr_query, "Sample Show S01E01"}
      assert_received {:prowlarr_query, "Sample Show S01E02"}
      refute_received {:prowlarr_query, "Sample Show S01E{01,02}"}

      # Both expanded results came back, deduped.
      assert length(results) == 2

      assert Enum.sort(Enum.map(results, & &1.guid)) == [
               "guid-Sample Show S01E01",
               "guid-Sample Show S01E02"
             ]
    end

    test "excludes guids in tried_release_guids and caps the list at 8" do
      # Pre-tried guids 0..4; expect the next eight from a deeper Prowlarr
      # response back (0..4 are filtered out, 5..12 remain — top 8 = 5..12).
      tried = Enum.map(0..4, &"guid-#{&1}")

      pursuit =
        create_pursuit(%{
          tmdb_id: "tt-tried",
          tmdb_type: "tv",
          title: "Sample Show",
          tried_release_guids: tried
        })

      Req.Test.stub(:prowlarr, fn conn ->
        results =
          for n <- 0..15 do
            %{
              "title" => "Sample.Show.Release.#{n}",
              "guid" => "guid-#{n}",
              "indexerId" => 1,
              "size" => 1_000_000_000,
              "seeders" => 10,
              "leechers" => 0,
              "indexer" => "Test Indexer",
              "publishDate" => "2026-04-01T00:00:00Z"
            }
          end

        Req.Test.json(conn, results)
      end)

      results = Acquisition.list_alternatives_for(pursuit)

      guids = Enum.map(results, & &1.guid)
      assert length(guids) == 8
      assert Enum.all?(tried, &(&1 not in guids))
    end

    test "pick_alternative succeeds against a brace-expanded prowlarr_query pursuit" do
      # Regression: prior to consolidating onto `do_search_for_pursuit/1`,
      # `find_alternative/2` used literal `search/2` and would report
      # `:alternative_unavailable` for a guid that the decision card had
      # just surfaced via brace-expanded search. They now share one
      # private helper, so the round-trip validates the same way.
      pursuit =
        create_pursuit(%{
          tmdb_id: "9998",
          tmdb_type: "tv",
          title: "Sample.Show.S01E02.1080p",
          recipe_type: "prowlarr_query",
          manual_query: "Sample Show S01E{01,02}",
          origin: "manual"
        })

      target_guid = "guid-Sample Show S01E02"

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "GET" ->
            q = conn.query_params["query"]

            Req.Test.json(conn, [
              %{
                "title" => "Sample.Show.#{q}.1080p",
                "guid" => "guid-#{q}",
                "indexerId" => 1,
                "size" => 1_000_000_000,
                "seeders" => 10,
                "leechers" => 0,
                "indexer" => "Test Indexer",
                "publishDate" => "2026-04-01T00:00:00Z"
              }
            ])

          "POST" ->
            # Prowlarr.grab — acknowledge the grab succeeded.
            Req.Test.json(conn, %{})
        end
      end)

      assert {:ok, %Pursuit{}} =
               Acquisition.pick_alternative(pursuit.id, target_guid, "S01E02 1080p")
    end

    test "pick_alternative broadcasts %TargetEvents.Picked{} on the unified dialect" do
      # Regression: until 2026-05-14 this path broadcast the legacy
      # `{:target_picked, target}` tuple, which the LiveView's
      # struct-only `handle_info` (`TargetEvents.event?/1`) ignored —
      # the modal silently failed to refresh after the user picked an
      # alternative. Phase 5 unified the dialect to typed structs; this
      # test pins that contract.
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())

      pursuit =
        create_pursuit(%{
          tmdb_id: "broadcast-1",
          tmdb_type: "movie",
          title: "Sample.Movie.2010",
          year: 2010
        })

      cached_result = %SearchResult{
        title: "Sample.Movie.2010.1080p.WEB-DL.H264-NTG",
        guid: "broadcast-guid-1",
        indexer_id: 1,
        quality: :hd_1080p,
        size_bytes: 4_500_000_000,
        seeders: 25,
        indexer_name: "Test Indexer"
      }

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, %{}) end)

      assert {:ok, %Pursuit{}} =
               Acquisition.pick_alternative(pursuit.id, cached_result, "1080p WEB-DL")

      assert_received %TargetEvents.Picked{target: %Target{}}
      refute_received {:target_picked, _}
    end

    test "pick_alternative accepts a cached %SearchResult{} and skips the Prowlarr round-trip" do
      # When the LV already has the SearchResult cached from the most
      # recent decision-card render, it should pass the struct directly
      # — no extra GET to Prowlarr. We assert this by stubbing only the
      # POST (grab) and recording every request the stub sees.
      pursuit =
        create_pursuit(%{
          tmdb_id: "9997",
          tmdb_type: "movie",
          title: "Sample.Movie.2010.1080p",
          year: 2010
        })

      cached_result = %SearchResult{
        title: "Sample.Movie.2010.1080p.WEB-DL.H264-NTG",
        guid: "cached-guid-1",
        indexer_id: 1,
        quality: :hd_1080p,
        size_bytes: 4_500_000_000,
        seeders: 25,
        indexer_name: "Test Indexer"
      }

      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        send(test_pid, {:prowlarr_request, conn.method, conn.request_path})

        case conn.method do
          "POST" -> Req.Test.json(conn, %{})
          _ -> Req.Test.json(conn, [])
        end
      end)

      assert {:ok, %Pursuit{}} =
               Acquisition.pick_alternative(pursuit.id, cached_result, "1080p WEB-DL")

      # The grab POST happened — that's the only Prowlarr request we
      # should have seen on this path.
      assert_received {:prowlarr_request, "POST", _}
      refute_received {:prowlarr_request, "GET", _}
    end
  end
end
