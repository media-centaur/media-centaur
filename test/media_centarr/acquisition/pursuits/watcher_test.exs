defmodule MediaCentarr.Acquisition.Pursuits.WatcherTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, Watcher}
  alias MediaCentarr.Downloads.QueueItem

  defp insert_pursuit(overrides) do
    pursuit_overrides =
      Map.merge(
        %{
          attempt_count: 0,
          inserted_at: DateTime.utc_now(:second)
        },
        overrides
      )

    {pursuit, _target} = create_pursuit_with_target(pursuit_overrides)

    pursuit
    |> Ecto.Changeset.change(pursuit_overrides)
    |> Repo.update!()
  end

  defp set_current_target_release(pursuit, release_title) do
    %MediaCentarr.Acquisition.Target{}
    |> Ecto.Changeset.change(
      pursuit_id: pursuit.id,
      title: pursuit.title,
      origin: pursuit.origin,
      status: "acquired",
      release_title: release_title
    )
    |> Repo.insert!()
    |> tap(fn target ->
      pursuit
      |> Ecto.Changeset.change(current_target_id: target.id)
      |> Repo.update!()
    end)
  end

  defp seed_queue(items) do
    :persistent_term.put(
      {MediaCentarr.Downloads.QueueMonitor, :state},
      %MediaCentarr.Downloads.QueueState{
        items: items,
        last_successful_poll_at: DateTime.utc_now()
      }
    )

    on_exit(fn ->
      :persistent_term.erase({MediaCentarr.Downloads.QueueMonitor, :state})
    end)
  end

  defp queue_item(title, opts) do
    %QueueItem{
      id: "torrent-#{title}",
      title: title,
      state: Keyword.get(opts, :state, :downloading),
      health: Keyword.get(opts, :health),
      status: nil
    }
  end

  describe "perform/1" do
    test "exhausts pursuits that meet the exhaustion criteria" do
      # 4 attempts, > 6 days old → Policy returns {:exhaust, :max_attempts}
      old_pursuit =
        insert_pursuit(%{
          attempt_count: 4,
          inserted_at: DateTime.add(DateTime.utc_now(:second), -7, :day)
        })

      # 0 attempts, fresh → Policy returns :no_action
      fresh_pursuit = insert_pursuit(%{attempt_count: 0})

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      assert Repo.get!(Pursuit, old_pursuit.id).state == "exhausted"
      assert Repo.get!(Pursuit, fresh_pursuit.id).state == "active"

      old_events =
        Event
        |> Ecto.Query.where(pursuit_id: ^old_pursuit.id)
        |> Repo.all()

      assert Enum.any?(old_events, &(&1.kind == "pursuit_exhausted"))
    end

    test "skips terminal-state pursuits entirely" do
      pursuit = insert_pursuit(%{attempt_count: 4})

      pursuit
      |> Ecto.Changeset.change(state: "satisfied")
      |> Repo.update!()

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"

      events =
        Event
        |> Ecto.Query.where(pursuit_id: ^pursuit.id)
        |> Repo.all()

      assert events == []
    end

    test "is idempotent across runs" do
      old_pursuit =
        insert_pursuit(%{
          attempt_count: 4,
          inserted_at: DateTime.add(DateTime.utc_now(:second), -7, :day)
        })

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})
      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      events =
        Event
        |> Ecto.Query.where(pursuit_id: ^old_pursuit.id, kind: "pursuit_exhausted")
        |> Repo.all()

      assert length(events) == 1
    end

    test "returns :ok when there are no active pursuits" do
      assert :ok = Watcher.perform(%Oban.Job{args: %{}})
    end

    test "queue shows persistent stall past window → pursuit transitions to needs_decision" do
      release = "Sample.Movie.2024.1080p.WEB-DL"

      pursuit =
        insert_pursuit(%{
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -25 * 3600)
        })

      set_current_target_release(pursuit, release)
      seed_queue([queue_item(release, state: :downloading, health: :soft_stall)])

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      assert Repo.get!(Pursuit, pursuit.id).state == "needs_decision"

      events =
        Event
        |> Ecto.Query.where(pursuit_id: ^pursuit.id, kind: "user_decision_requested")
        |> Repo.all()

      assert length(events) == 1
    end

    test "queue shows persistent zero-seeders past window → pursuit auto-pivoted" do
      # Watcher dispatch wiring only — AutoCancelTest covers the full
      # auto-pivot contract. Oban runs in manual mode so the
      # freshly-enqueued PursueTarget doesn't immediately hit Prowlarr.
      release = "Sample.Movie.2024.2160p.UHD"

      pursuit =
        insert_pursuit(%{
          zero_seeders_first_seen_at: DateTime.add(DateTime.utc_now(:second), -7 * 3600),
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -7 * 3600)
        })

      set_current_target_release(pursuit, release)
      seed_queue([queue_item(release, state: :stalled, health: :frozen)])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Watcher.perform(%Oban.Job{args: %{}})
      end)

      events =
        Event
        |> Ecto.Query.where(pursuit_id: ^pursuit.id, kind: "auto_cancelled")
        |> Repo.all()

      assert length(events) == 1
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "torrent recovered (healthy in queue) → observation timestamps cleared, no action" do
      release = "Sample.Movie.2024.1080p.WEB-DL"

      pursuit =
        insert_pursuit(%{
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -25 * 3600)
        })

      set_current_target_release(pursuit, release)
      seed_queue([queue_item(release, state: :downloading, health: :healthy)])

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      reloaded = Repo.get!(Pursuit, pursuit.id)
      assert reloaded.stall_first_seen_at == nil
      assert reloaded.state == "active"
    end
  end
end
