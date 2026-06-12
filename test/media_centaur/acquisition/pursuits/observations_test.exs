defmodule MediaCentaur.Acquisition.Pursuits.ObservationsTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query
  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, Observations, Units}
  alias MediaCentaur.Downloads.QueueItem

  defp insert_pursuit_with_unit(release_title) do
    {pursuit, _target} =
      create_pursuit_with_target(%{release_title: release_title})

    {pursuit, Units.single!(pursuit.id)}
  end

  defp set_unit(unit, attrs) do
    unit
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  defp set_pursuit(pursuit, attrs) do
    pursuit
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
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

  describe "refresh!/4 (per-unit signal timestamps)" do
    setup do
      now = ~U[2026-05-07 12:00:00Z]
      %{now: now}
    end

    test "no torrent found in queue → both timestamps cleared", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")

      unit =
        set_unit(unit,
          stall_first_seen_at: ~U[2026-05-07 11:00:00Z],
          zero_seeders_first_seen_at: ~U[2026-05-07 11:00:00Z]
        )

      refreshed = Observations.refresh!(pursuit, unit, [], now)

      assert refreshed.stall_first_seen_at == nil
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent found and healthy → both timestamps cleared", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      unit = set_unit(unit, stall_first_seen_at: ~U[2026-05-07 11:00:00Z])

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.stall_first_seen_at == nil
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent newly soft-stalled → stall_first_seen_at set to now", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :soft_stall)]

      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.stall_first_seen_at == now
      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "torrent already stalling → stall_first_seen_at preserved across refreshes", %{now: now} do
      original_seen = ~U[2026-05-06 12:00:00Z]

      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      unit = set_unit(unit, stall_first_seen_at: original_seen)

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :frozen)]

      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.stall_first_seen_at == original_seen
    end

    test "torrent in :stalled state → zero_seeders_first_seen_at set", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :stalled, health: :frozen)]

      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.zero_seeders_first_seen_at == now
      assert refreshed.stall_first_seen_at == now
    end

    test "torrent recovered from :stalled → zero_seeders timestamp cleared", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      unit = set_unit(unit, zero_seeders_first_seen_at: ~U[2026-05-07 06:00:00Z])

      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.zero_seeders_first_seen_at == nil
    end

    test "queue_state == :unknown → no changes (download client unreachable)", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      unit = set_unit(unit, stall_first_seen_at: ~U[2026-05-07 11:00:00Z])

      refreshed = Observations.refresh!(pursuit, unit, :unknown, now)

      assert refreshed.stall_first_seen_at == ~U[2026-05-07 11:00:00Z]
    end

    test "refresh! never emits timeline events — that's observe_pursuit!'s job", %{now: now} do
      {pursuit, unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      _ = Observations.refresh!(pursuit, unit, queue, now)

      assert [] = events_for(pursuit.id)
    end

    test "no target → no torrent to look up → timestamps cleared", %{now: now} do
      pursuit =
        create_pursuit(%{
          tmdb_id: "999",
          tmdb_type: "movie",
          title: "Lonely Pursuit",
          origin: "auto",
          stall_first_seen_at: ~U[2026-05-07 11:00:00Z]
        })

      unit = Units.single!(pursuit.id)

      queue = [queue_item("Some.Other.Title", state: :downloading)]
      refreshed = Observations.refresh!(pursuit, unit, queue, now)

      assert refreshed.stall_first_seen_at == nil
    end
  end

  describe "observe_pursuit!/4 (pursuit-level lifecycle events)" do
    setup do
      now = ~U[2026-05-07 12:00:00Z]
      %{now: now}
    end

    test "first observation → one DownloadStarted; observation persisted on the pursuit", %{
      now: now
    } do
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      observed = Observations.observe_pursuit!(pursuit, queue, now)

      assert observed.last_queue_state == "downloading"
      assert observed.last_queue_health == "healthy"

      assert [event] = events_for(pursuit.id)
      assert event.kind == "download_started"
      assert event.payload["client"] == "qbittorrent"
    end

    test "a multi-unit pursuit still emits exactly ONE event per transition", %{now: now} do
      # The Frieren regression: a 38-episode season pack produced 38
      # identical "Download started" rows because the observation lived
      # on each unit. The torrent is a pursuit-level fact; observing it
      # is too — unit count must not multiply timeline rows.
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Show.S01.1080p")
      for _extra <- 1..3, do: create_pursuit_unit(pursuit, %{})

      queue = [queue_item("Sample.Show.S01.1080p", state: :downloading, health: :healthy)]
      observed = Observations.observe_pursuit!(pursuit, queue, now)

      assert [%Event{kind: "download_started"}] = events_for(pursuit.id)

      queue_stalled = [queue_item("Sample.Show.S01.1080p", state: :stalled, health: :frozen)]
      _ = Observations.observe_pursuit!(observed, queue_stalled, ~U[2026-05-07 13:00:00Z])

      assert [_started] = events_for(pursuit.id, "download_started")
      assert [_changed] = events_for(pursuit.id, "health_changed")
    end

    test "unchanged (state, health) → no event", %{now: now} do
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")
      queue = [queue_item("Sample.Movie.2024.1080p", state: :downloading, health: :healthy)]

      observed = Observations.observe_pursuit!(pursuit, queue, now)
      _ = Observations.observe_pursuit!(observed, queue, ~U[2026-05-07 13:00:00Z])

      assert [%Event{kind: "download_started"}] = events_for(pursuit.id)
    end

    test "transition → one HealthChanged carrying both axes", %{now: now} do
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")

      pursuit =
        set_pursuit(pursuit, last_queue_state: "downloading", last_queue_health: "healthy")

      queue = [queue_item("Sample.Movie.2024.1080p", state: :stalled, health: :frozen)]
      observed = Observations.observe_pursuit!(pursuit, queue, now)

      assert observed.last_queue_state == "stalled"
      assert observed.last_queue_health == "frozen"

      assert [event] = events_for(pursuit.id, "health_changed")
      assert event.payload["from_state"] == "downloading"
      assert event.payload["to_state"] == "stalled"
      assert event.payload["from_health"] == "healthy"
      assert event.payload["to_health"] == "frozen"
    end

    test "nil health is a real nil, and the observation converges (no per-tick re-emission)", %{
      now: now
    } do
      # The "warming_up → nil" spam: nil was stringified to "nil" by
      # Atom.to_string/1, polluting payloads and UI copy. A present item
      # with nil health must store SQL NULL and emit at most once.
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")

      pursuit =
        set_pursuit(pursuit, last_queue_state: "downloading", last_queue_health: "warming_up")

      queue = [queue_item("Sample.Movie.2024.1080p", state: :other, health: nil)]

      observed = Observations.observe_pursuit!(pursuit, queue, now)
      assert observed.last_queue_state == "other"
      assert observed.last_queue_health == nil

      assert [event] = events_for(pursuit.id, "health_changed")
      assert event.payload["to_state"] == "other"
      assert event.payload["to_health"] == nil

      # Same observation next tick — converged, no new event.
      _ = Observations.observe_pursuit!(observed, queue, ~U[2026-05-07 13:00:00Z])
      assert [_only] = events_for(pursuit.id, "health_changed")
    end

    test "torrent absent from queue this tick → observation preserved, no event", %{now: now} do
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")

      pursuit =
        set_pursuit(pursuit, last_queue_state: "downloading", last_queue_health: "healthy")

      observed = Observations.observe_pursuit!(pursuit, [], now)

      assert observed.last_queue_state == "downloading"
      assert observed.last_queue_health == "healthy"
      assert [] = events_for(pursuit.id)
    end

    test "queue :unknown → pursuit untouched, no event", %{now: now} do
      {pursuit, _unit} = insert_pursuit_with_unit("Sample.Movie.2024.1080p")

      observed = Observations.observe_pursuit!(pursuit, :unknown, now)

      assert observed.last_queue_state == nil
      assert [] = events_for(pursuit.id)
    end

    test "no release title → nothing to observe, no event", %{now: now} do
      pursuit =
        create_pursuit(%{tmdb_id: "999", tmdb_type: "movie", title: "Lonely Pursuit", origin: "auto"})

      queue = [queue_item("Some.Other.Title", state: :downloading)]
      observed = Observations.observe_pursuit!(pursuit, queue, now)

      assert observed.last_queue_state == nil
      assert [] = events_for(pursuit.id)
    end
  end
end
