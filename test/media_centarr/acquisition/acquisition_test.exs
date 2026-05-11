defmodule MediaCentarr.AcquisitionTest do
  use MediaCentarr.DataCase, async: false
  use Oban.Testing, repo: MediaCentarr.Repo

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{Prowlarr, SearchResult, Target}
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

      assert_received {:target_picked, %Target{origin: "manual"}}
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
      assert_received {:target_armed, %Target{}}
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
      assert_received {:target_cancelled, %Target{cancelled_reason: "user_disabled"}}
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
end
