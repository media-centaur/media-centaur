defmodule MediaCentarr.Acquisition.Pursuits.ObservationsTest do
  use MediaCentarr.DataCase, async: false

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, Observations, Pursuit}
  alias MediaCentarr.Downloads.QueueItem

  defp insert_pursuit_with_grab(release_title) do
    {:ok, pursuit} =
      Repo.insert(
        Pursuit.create_changeset(%{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        })
      )

    {:ok, _grab} =
      %Grab{}
      |> Ecto.Changeset.cast(
        %{
          tmdb_id: pursuit.tmdb_id,
          tmdb_type: pursuit.tmdb_type,
          title: pursuit.title,
          origin: pursuit.origin
        },
        [:tmdb_id, :tmdb_type, :title, :origin]
      )
      |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
      |> Ecto.Changeset.put_change(:release_title, release_title)
      |> Repo.insert()

    pursuit
  end

  defp events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], asc: e.occurred_at)
    |> Repo.all()
  end

  defp events_for(pursuit_id, kind) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id and e.kind == ^kind)
    |> order_by([e], asc: e.occurred_at)
    |> Repo.all()
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

  describe "refresh!/3" do
    setup do
      now = ~U[2026-05-07 12:00:00Z]
      %{now: now}
    end

    test "no torrent found in queue → both timestamps cleared", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(
          stall_first_seen_at: ~U[2026-05-07 11:00:00Z],
          zero_seeders_first_seen_at: ~U[2026-05-07 11:00:00Z]
        )
        |> Repo.update!()

      refreshed = Observations.refresh!(pursuit, [], now)

      assert refreshed.stall_first_seen_at == nil
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent found and healthy → both timestamps cleared", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(stall_first_seen_at: ~U[2026-05-07 11:00:00Z])
        |> Repo.update!()

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.stall_first_seen_at == nil
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent newly soft-stalled → stall_first_seen_at set to now", %{now: now} do
      pursuit = insert_pursuit_with_grab("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :soft_stall)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.stall_first_seen_at == now
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent already stalling → stall_first_seen_at preserved across refreshes", %{now: now} do
      original_seen = ~U[2026-05-06 12:00:00Z]

      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(stall_first_seen_at: original_seen)
        |> Repo.update!()

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :frozen)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.stall_first_seen_at == original_seen
    end

    test "torrent in :stalled state → zero_seeders_first_seen_at set", %{now: now} do
      pursuit = insert_pursuit_with_grab("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :stalled, health: :frozen)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.zero_seeders_first_seen_at == now
      assert refreshed.stall_first_seen_at == now
    end

    test "torrent recovered from :stalled → zero_seeders timestamp cleared", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(zero_seeders_first_seen_at: ~U[2026-05-07 06:00:00Z])
        |> Repo.update!()

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "queue_state == :unknown → no changes (download client unreachable)", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(stall_first_seen_at: ~U[2026-05-07 11:00:00Z])
        |> Repo.update!()

      refreshed = Observations.refresh!(pursuit, :unknown, now)

      assert refreshed.stall_first_seen_at == ~U[2026-05-07 11:00:00Z]
    end

    test "first observation of the torrent → DownloadStarted event recorded; last_queue_state set",
         %{now: now} do
      pursuit = insert_pursuit_with_grab("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.last_queue_state == "downloading"
      assert refreshed.last_queue_health == "healthy"

      events = events_for(pursuit.id)
      assert [event] = events
      assert event.kind == "download_started"
      assert event.payload["client"] == "qbittorrent"
    end

    test "queue (state, health) unchanged → no event recorded", %{now: now} do
      pursuit = insert_pursuit_with_grab("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      _ = Observations.refresh!(pursuit, queue, now)

      pursuit_after_first = Repo.get!(Pursuit, pursuit.id)
      _ = Observations.refresh!(pursuit_after_first, queue, ~U[2026-05-07 13:00:00Z])

      events =
        Event
        |> where([e], e.pursuit_id == ^pursuit.id)
        |> Repo.all()

      assert length(events) == 1
      assert hd(events).kind == "download_started"
    end

    test "state transition (:downloading → :stalled) → HealthChanged event recorded", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(last_queue_state: "downloading", last_queue_health: "healthy")
        |> Repo.update!()

      queue = [queue_item("Sample.Movie.2024.1080p", state: :stalled, health: :frozen)]

      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.last_queue_state == "stalled"
      assert refreshed.last_queue_health == "frozen"

      [event] = events_for(pursuit.id, "health_changed")
      assert event.payload["from_state"] == "downloading"
      assert event.payload["to_state"] == "stalled"
      assert event.payload["from_health"] == "healthy"
      assert event.payload["to_health"] == "frozen"
    end

    test "health-axis-only change → HealthChanged event still records both axes", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(last_queue_state: "downloading", last_queue_health: "healthy")
        |> Repo.update!()

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :slow)]

      _ = Observations.refresh!(pursuit, queue, now)

      [event] = events_for(pursuit.id, "health_changed")
      assert event.payload["from_state"] == "downloading"
      assert event.payload["to_state"] == "downloading"
      assert event.payload["from_health"] == "healthy"
      assert event.payload["to_health"] == "slow"
    end

    test "torrent absent from queue this tick → last_queue_state preserved, no event", %{now: now} do
      pursuit =
        insert_pursuit_with_grab("Sample.Movie.2024.1080p")
        |> Ecto.Changeset.change(last_queue_state: "downloading", last_queue_health: "healthy")
        |> Repo.update!()

      refreshed = Observations.refresh!(pursuit, [], now)

      assert refreshed.last_queue_state == "downloading"
      assert refreshed.last_queue_health == "healthy"

      assert [] = events_for(pursuit.id)
    end

    test "no grab → no torrent to look up → timestamps cleared", %{now: now} do
      {:ok, pursuit} =
        Repo.insert(
          Pursuit.create_changeset(%{
            tmdb_id: "999",
            tmdb_type: "movie",
            title: "Lonely Pursuit",
            origin: "auto"
          })
        )

      pursuit =
        pursuit
        |> Ecto.Changeset.change(stall_first_seen_at: ~U[2026-05-07 11:00:00Z])
        |> Repo.update!()

      queue = [queue_item("Some.Other.Title", state: :downloading)]
      refreshed = Observations.refresh!(pursuit, queue, now)

      assert refreshed.stall_first_seen_at == nil
    end
  end
end
