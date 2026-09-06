defmodule MediaCentaur.Acquisition.DropPlannerTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.{DropPlanner, PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Pursuits.Commands.{AutoCancel, Cancel}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Acquisition.Reactor.Handlers
  alias MediaCentaur.Capabilities
  alias MediaCentaur.ReleaseTracking

  @last_month Date.add(Date.utc_today(), -30)

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    # A re-search of a TV pursuit consults cour segmentation (a TMDB season
    # fetch); an empty season degrades it to the regular queries.
    MediaCentaur.TmdbStubs.setup_tmdb_client()
    Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"episodes" => []}) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    Capabilities.save_test_result(:prowlarr, :ok)

    on_exit(fn ->
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, config)
    end)

    :ok
  end

  defp create_tracked_show(attrs \\ %{}) do
    create_tracking_item(
      Map.merge(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"}, attrs)
    )
  end

  defp create_aired_release(item, season, episode, air_date) do
    ReleaseTracking.create_release!(%{
      item_id: item.id,
      air_date: air_date,
      title: "Episode #{episode}",
      season_number: season,
      episode_number: episode,
      released: true
    })
  end

  defp release(title, guid, attrs) do
    Map.merge(
      %{
        "title" => title,
        "guid" => guid,
        "indexerId" => 1,
        "indexer" => "indexer-a",
        "seeders" => Map.get(attrs, :seeders, 10)
      },
      Map.new(Map.delete(attrs, :seeders), fn {k, v} -> {to_string(k), v} end)
    )
  end

  defp stub_results(results_by_query) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
        # :unconfigured — not blind — so corpus recording behaves as before.
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)
          Req.Test.json(conn, Map.get(results_by_query, query, []))

        {"POST", "/api/v1/search"} ->
          Req.Test.json(conn, %{"approved" => true})

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  # Drives the production flow a DataCase test can't get from PubSub:
  # the tick creates plans (RunPlan solves inline under Oban's test
  # mode), then the mode gate fires for each ready tracking plan the
  # way the Reactor would on PlanEvents.Changed.
  defp tick_and_gate do
    DropPlanner.run_tick()

    Enum.each(Plans.list_drafts(), fn plan ->
      Handlers.plan_changed(%PlanEvents.Changed{plan_id: plan.id, status: plan.status})
    end)
  end

  defp sole_pursuit do
    [pursuit] = Repo.all(Pursuit)
    pursuit
  end

  describe "run_tick/0 — auto mode end-to-end" do
    test "due wants become one tracking plan per title, auto-committed as one pursuit" do
      stub_results(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ]
      })

      item =
        create_tracked_show(%{
          imdb_id: "tt0903747",
          tvdb_id: "81189",
          original_title: "Beispielserie"
        })

      create_aired_release(item, 1, 1, @last_month)
      create_aired_release(item, 1, 2, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      pursuit = sole_pursuit()
      assert pursuit.origin == "auto"
      assert pursuit.tmdb_id == "246810"

      # The automated path carries the title's identity too, so an
      # unattended grab can be verified against the ids indexers declare.
      assert pursuit.imdb_id == "tt0903747"
      assert pursuit.tvdb_id == "81189"
      assert pursuit.original_title == "Beispielserie"
      assert length(Units.for_pursuit(pursuit.id)) == 2

      # Plan provenance: origin + back-pointer to the tracking item.
      [plan] = Repo.all(Plans.Plan)
      assert plan.status == "committed"
      assert plan.origin == "tracking"
      assert plan.approval_policy == "automatic"
      assert plan.tracking_item_id == item.id
      assert plan.pursuit_id == pursuit.id

      # Included wants were stamped searched (back-off anchor).
      open_wants = ReleaseTracking.open_wants_for_item(item.id)
      assert Enum.all?(open_wants, & &1.last_searched_at)
    end

    test "a movie want becomes a single-unit tracking movie plan keyed by the part id" do
      year = @last_month.year

      stub_results(%{
        "Sample Saga Part II #{year}" => [
          release("Sample.Saga.Part.II.#{year}.1080p.WEB-DL", "saga-2", %{seeders: 25})
        ]
      })

      item =
        create_tracking_item(%{
          tmdb_id: 1000,
          media_type: :movie,
          name: "Sample Saga",
          imdb_id: "tt0137523"
        })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @last_month,
        title: "Sample Saga Part II",
        part_tmdb_id: 2002,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      pursuit = sole_pursuit()
      assert pursuit.tmdb_type == "movie"
      assert pursuit.tmdb_id == "2002"
      assert pursuit.title == "Sample Saga Part II"

      # A collection part is a different film from the item, so the
      # item's own IMDb id would be the wrong identity to claim.
      assert pursuit.imdb_id == nil
    end
  end

  describe "run_tick/0 — patience quality floors" do
    test "a want inside its patience window demands the ceiling; aged wants take the floor" do
      stub_results(%{
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.1080p.WEB-DL", "e1-hd", %{seeders: 20})
        ],
        "Sample Show S09E01" => [
          release("Sample.Show.S09E01.1080p.WEB-DL", "e901-hd", %{seeders: 20})
        ]
      })

      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{quality_4k_patience_hours: 24})

      # Aged want (patience long expired) and a day-of want (inside it).
      create_aired_release(item, 1, 1, @last_month)
      create_aired_release(item, 9, 1, Date.utc_today())
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      # Only the aged unit commits — 1080p can't satisfy the young
      # unit's elevated floor, so it stays an open, searched want.
      pursuit = sole_pursuit()
      [unit] = Units.for_pursuit(pursuit.id)
      assert {unit.season_number, unit.episode_number} == {1, 1}

      young_want =
        item.id
        |> ReleaseTracking.open_wants_for_item()
        |> Enum.find(&(&1.season_number == 9))

      assert young_want
      assert young_want.last_searched_at
    end
  end

  describe "run_tick/0 — modes" do
    test "ask mode leaves the solved plan ready and a second tick does not duplicate it" do
      stub_results(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ]
      })

      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "ask"})
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      assert [] = Repo.all(Pursuit)
      [plan] = Plans.list_drafts()
      assert plan.status == "ready"
      assert plan.origin == "tracking"
      assert plan.approval_policy == "review"

      tick_and_gate()

      assert [_still_just_one] = Plans.list_drafts()
    end

    test "off mode plans nothing" do
      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "off"})
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      assert Repo.all(Plans.Plan) == []
    end

    test "a plan that solves to zero found units is deleted; the wants stay open, stamped" do
      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      # An automated tick that found nothing leaves no plan rows behind
      # — the want IS the durable intent, stamped for back-off.
      assert Repo.all(Plans.Plan) == []
      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.last_searched_at
    end
  end

  describe "sweep tick — mode-off reconciliation (Q11)" do
    # Use-case 11: flipping an item to `off` mid-flight. Entry point is
    # the real one — `Handlers.tracking_sweep_completed/0`, which runs
    # the reconciliation pass before the drop planner tick.

    defp episode_stub do
      stub_results(%{
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.1080p.WEB-DL", "e1-hd", %{seeders: 20})
        ]
      })
    end

    test "a parked ask draft is discarded on the tick after the flip; wants stay open" do
      episode_stub()

      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "ask"})
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      [parked] = Plans.list_drafts()
      assert parked.status == "ready"

      {:ok, _item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "off"})
      Handlers.tracking_sweep_completed()

      assert Plans.list_drafts() == []
      {:ok, discarded} = Plans.fetch(parked.id)
      assert discarded.status == "discarded"

      # Mode off ≠ stop wanting — media search remains the expected
      # path (Q3), so the ledger keeps the intent.
      assert [_want] = ReleaseTracking.open_wants_for_item(item.id)
    end

    test "a still-seeking tracking pursuit is system-cancelled; wants stay open" do
      episode_stub()

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      pursuit = sole_pursuit()

      # Degrade the grab the way production does: the safe-case pivot
      # cancels the dead release and re-arms a seeking target (the
      # worker snoozes against the now-empty stub).
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
      {:ok, _pivoted} = AutoCancel.execute(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      {:ok, _item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "off"})
      Handlers.tracking_sweep_completed()

      assert Repo.get!(Pursuit, pursuit.id).state == "cancelled"
      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.season_number == 1
    end

    test "a tracking pursuit with a live download is left alone" do
      episode_stub()

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      pursuit = sole_pursuit()

      {:ok, _item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "off"})
      Handlers.tracking_sweep_completed()

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "a user-initiated plan-now draft survives the flip" do
      episode_stub()

      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "off"})
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      {:ok, :planned} = DropPlanner.plan_item_now(item.id)
      [draft] = Plans.list_drafts()
      assert draft.origin == "manual"
      assert draft.approval_policy == "review"

      Handlers.tracking_sweep_completed()

      assert [_still_there] = Plans.list_drafts()
    end

    test "an item inheriting a global default of off is reconciled too" do
      episode_stub()

      item = create_tracked_show()
      {:ok, item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "ask"})
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      assert [_parked] = Plans.list_drafts()

      {:ok, _item} = ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "global"})

      MediaCentaur.Settings.find_or_create_entry!(%{
        key: "auto_grab.default_mode",
        value: %{"value" => "off"}
      })

      Handlers.tracking_sweep_completed()

      assert Plans.list_drafts() == []
    end
  end

  describe "run_tick/0 — claims and gating" do
    test "wants claimed by an active pursuit are skipped" do
      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      {_pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "246810",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 1
        })

      tick_and_gate()

      assert Repo.all(Plans.Plan) == []
    end

    test "wants searched recently are not due" do
      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      [want] = ReleaseTracking.open_wants_for_item(item.id)
      first_stamp = want.last_searched_at
      assert first_stamp

      # The want was just searched; an immediate second tick is not due,
      # so the stamp must not move.
      tick_and_gate()

      [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.last_searched_at == first_stamp
    end

    test "without prowlarr the tick is inert" do
      Capabilities.save_test_result(:prowlarr, :error)

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      assert Repo.all(Plans.Plan) == []
    end
  end

  describe "tried-and-failed exclusion (Q5 loop-breaker)" do
    test "a release that already failed for the unit is never re-assigned" do
      # A prior pursuit for S01E01 exhausted itself on "dead-1".
      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "tmdb",
          tmdb_id: "246810",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 1,
          origin: "auto",
          status: "failed"
        })

      [unit] = Units.for_pursuit(pursuit.id)

      _ = force_attrs(unit, state: "exhausted", tried_release_guids: ["dead-1"])

      _ = force_state(Repo.get!(Pursuit, pursuit.id), "exhausted")

      # The indexer still only offers the dead release.
      stub_results(%{
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.1080p.WEB-DL", "dead-1", %{seeders: 20})
        ]
      })

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      # The dead release is excluded at plan time: nothing assignable,
      # no pursuit, the want stays open for a genuinely new release.
      assert Enum.filter(Repo.all(Pursuit), &(&1.state == "active")) == []
      assert [%{status: :open}] = ReleaseTracking.open_wants_for_item(item.id)
    end
  end

  describe "cancellation semantics (Q5)" do
    setup do
      stub_results(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ]
      })

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      create_aired_release(item, 1, 2, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      {:ok, item: item, pursuit: sole_pursuit()}
    end

    test "user cancel of a tracking pursuit dismisses its wants", %{item: item, pursuit: pursuit} do
      {:ok, _} =
        Cancel.execute(%{pursuit_id: pursuit.id, cancelled_by: :user, reason: "user_request"})

      assert ReleaseTracking.open_wants_for_item(item.id) == []

      dismissed =
        Repo.all(
          from(w in ReleaseTracking.Want,
            where: w.item_id == ^item.id and w.status == :dismissed
          )
        )

      assert length(dismissed) == 2
    end

    test "system cancel leaves the wants open for the next cadence", %{
      item: item,
      pursuit: pursuit
    } do
      {:ok, _} =
        Cancel.execute(%{pursuit_id: pursuit.id, cancelled_by: :system, reason: "stall"})

      assert length(ReleaseTracking.open_wants_for_item(item.id)) == 2
    end
  end
end
