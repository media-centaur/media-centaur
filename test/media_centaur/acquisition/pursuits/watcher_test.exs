defmodule MediaCentaur.Acquisition.Pursuits.WatcherTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, Pursuit, TargetUnit, Units, Watcher}
  alias MediaCentaur.Downloads.QueueItem

  # Thread overrides (attempt_count, inserted_at, observation
  # timestamps) land on the unit — the thread carrier the Policy loop
  # reads (ADR-055).
  defp insert_pursuit(overrides) do
    pursuit_overrides =
      Map.merge(
        %{
          attempt_count: 0,
          inserted_at: DateTime.utc_now(:second)
        },
        overrides
      )

    {pursuit, _target} = create_pursuit_with_target(Map.delete(pursuit_overrides, :inserted_at))

    unit_overrides =
      Map.take(pursuit_overrides, [
        :attempt_count,
        :inserted_at,
        :stall_first_seen_at,
        :zero_seeders_first_seen_at
      ])

    pursuit.id
    |> Units.single!()
    |> force_attrs(unit_overrides)

    pursuit
  end

  defp set_current_target_release(pursuit, release_title) do
    unit = Units.single!(pursuit.id)

    %MediaCentaur.Acquisition.Target{}
    |> Ecto.Changeset.change(
      pursuit_id: pursuit.id,
      title: pursuit.title,
      origin: pursuit.origin,
      status: "acquired",
      release_title: release_title
    )
    |> Repo.insert!()
    |> tap(fn target ->
      %TargetUnit{}
      |> Ecto.Changeset.change(target_id: target.id, unit_id: unit.id)
      |> Repo.insert!()

      force_attrs(unit, current_target_id: target.id)
    end)
  end

  defp seed_queue(items) do
    :persistent_term.put(
      {MediaCentaur.Downloads.QueueMonitor, :state},
      %MediaCentaur.Downloads.QueueState{
        items: items,
        last_successful_poll_at: DateTime.utc_now()
      }
    )
  end

  defp queue_item(title, opts) do
    %QueueItem{
      id: "torrent-#{title}",
      title: title,
      state: Keyword.get(opts, :state, :downloading),
      health: Keyword.get(opts, :health),
      failure_message: Keyword.get(opts, :failure_message),
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

      force_state(pursuit, "satisfied")

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

    test "library reconciler runs each tick — pursuit whose file is already on disk gets satisfied" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "246810"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      create_episode(%{
        season_id: season.id,
        episode_number: 3,
        content_url: "/library/Sample.Show.S01E03.mkv"
      })

      pursuit =
        insert_pursuit(%{
          tmdb_id: "246810",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3
        })

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"

      satisfied_events =
        Event
        |> Ecto.Query.where(pursuit_id: ^pursuit.id, kind: "pursuit_satisfied")
        |> Repo.all()

      assert length(satisfied_events) == 1
    end

    test "queue shows persistent stall past window → pursuit awaiting_decision_at set" do
      release = "Sample.Movie.2024.1080p.WEB-DL"

      pursuit =
        insert_pursuit(%{
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -25 * 3600)
        })

      set_current_target_release(pursuit, release)
      seed_queue([queue_item(release, state: :downloading, health: :soft_stall)])

      assert :ok = Watcher.perform(%Oban.Job{args: %{}})

      refreshed = Repo.get!(Pursuit, pursuit.id)
      assert refreshed.state == "active"
      assert %DateTime{} = Units.single!(pursuit.id).awaiting_decision_at

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

    test "client-reported terminal failure → auto-pivot records the client's message on the event" do
      release = "Sample.Show.S01E01.1080p.WEB-DL"
      pursuit = insert_pursuit(%{})
      set_current_target_release(pursuit, release)

      seed_queue([
        queue_item(release,
          state: :error,
          failure_message: "Repair failed, not enough repair blocks"
        )
      ])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Watcher.perform(%Oban.Job{args: %{}})
      end)

      [event] =
        Event
        |> Ecto.Query.where(pursuit_id: ^pursuit.id, kind: "auto_cancelled")
        |> Repo.all()

      assert event.payload["reason"] == "download_failed"
      assert event.payload["detail"] == "Repair failed, not enough repair blocks"
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

      assert Units.single!(pursuit.id).stall_first_seen_at == nil
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end
end
