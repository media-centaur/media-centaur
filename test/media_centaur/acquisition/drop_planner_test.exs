defmodule MediaCentaur.Acquisition.DropPlannerTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.{DropPlanner, PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Pursuits.Commands.Cancel
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Acquisition.Reactor.Handlers
  alias MediaCentaur.Capabilities
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Search.Prowlarr

  @last_month Date.add(Date.utc_today(), -30)

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    Capabilities.save_test_result(:prowlarr, :ok)

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentaur.Config, :config}, config)
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

      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)
      create_aired_release(item, 1, 2, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      pursuit = sole_pursuit()
      assert pursuit.origin == "auto"
      assert pursuit.tmdb_id == "246810"
      assert length(Units.for_pursuit(pursuit.id)) == 2

      # Plan provenance: origin + back-pointer to the tracking item.
      [plan] = Repo.all(Plans.Plan)
      assert plan.status == "committed"
      assert plan.origin == "tracking"
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

      item = create_tracking_item(%{tmdb_id: 1000, media_type: :movie, name: "Sample Saga"})

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

      {:ok, _} =
        unit
        |> Ecto.Changeset.change(state: "exhausted", tried_release_guids: ["dead-1"])
        |> Repo.update()

      {:ok, _} =
        Repo.get!(Pursuit, pursuit.id)
        |> Ecto.Changeset.change(state: "exhausted")
        |> Repo.update()

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
