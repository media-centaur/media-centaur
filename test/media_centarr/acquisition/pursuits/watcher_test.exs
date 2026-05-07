defmodule MediaCentarr.Acquisition.Pursuits.WatcherTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, Watcher}

  defp insert_pursuit(overrides) do
    {:ok, pursuit} =
      Repo.insert(
        Pursuit.create_changeset(%{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        })
      )

    overrides =
      Map.merge(
        %{
          attempt_count: 0,
          inserted_at: DateTime.utc_now(:second)
        },
        overrides
      )

    pursuit
    |> Ecto.Changeset.change(overrides)
    |> Repo.update!()
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

      # The exhausted pursuit recorded a pursuit_exhausted event
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

      # Second run skips already-exhausted pursuit; only one exhaustion event
      events =
        Event
        |> Ecto.Query.where(pursuit_id: ^old_pursuit.id, kind: "pursuit_exhausted")
        |> Repo.all()

      assert length(events) == 1
    end

    test "returns :ok when there are no active pursuits" do
      assert :ok = Watcher.perform(%Oban.Job{args: %{}})
    end
  end
end
