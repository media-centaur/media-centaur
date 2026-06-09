defmodule MediaCentaur.Acquisition.Pursuits.ThroughputTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Pursuits.Throughput
  alias MediaCentaur.Repo

  defp insert_pursuit(state) do
    {:ok, pursuit} =
      %{
        recipe_type: "tmdb",
        tmdb_id: Integer.to_string(System.unique_integer([:positive])),
        tmdb_type: "movie",
        title: "Movie A",
        origin: "auto"
      }
      |> Pursuit.create_changeset()
      |> Repo.insert()

    if state == "active" do
      pursuit
    else
      pursuit |> Ecto.Changeset.change(state: state) |> Repo.update!()
    end
  end

  describe "empty/0" do
    test "zeroed snapshot for the disconnected mount" do
      assert Throughput.empty() == %{acquired: 0, failed: 0, active: 0, success_rate: nil}
    end
  end

  describe "stats/0" do
    test "no pursuits mirrors empty/0" do
      assert Throughput.stats() == Throughput.empty()
    end

    test "buckets states and computes whole-percent success rate" do
      Enum.each(["satisfied", "satisfied", "satisfied"], &insert_pursuit/1)
      insert_pursuit("exhausted")
      insert_pursuit("cancelled")
      insert_pursuit("active")

      # 3 success, 2 failure => 3/5 = 60%; 1 active.
      assert Throughput.stats() == %{acquired: 3, failed: 2, active: 1, success_rate: 60}
    end

    test "success_rate is nil when there are no terminal pursuits" do
      insert_pursuit("active")
      assert %{acquired: 0, failed: 0, active: 1, success_rate: nil} = Throughput.stats()
    end
  end
end
