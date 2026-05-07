defmodule MediaCentarr.Acquisition.Pursuits.ObservationsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Observations, Pursuit}
  alias MediaCentarr.Acquisition.QueueItem

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
