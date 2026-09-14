defmodule MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitchesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitches
  alias MediaCentaur.Settings

  # The schema no longer admits the retired rungs, so the legacy state is
  # written the way the old app left it: straight into the column.
  defp legacy_rung!(tmdb_id, rung) do
    Repo.query!("UPDATE title_intents SET rung = ? WHERE tmdb_id = ?", [rung, tmdb_id])
    :ok
  end

  defp rungs do
    %{rows: rows} = Repo.query!("SELECT tmdb_id, rung FROM title_intents ORDER BY tmdb_id", [])
    Map.new(rows, fn [id, rung] -> {id, rung} end)
  end

  defp global_mode!(mode) do
    Settings.find_or_create_entry!(%{key: "auto_grab.default_mode", value: %{"value" => mode}})
  end

  setup do
    for {id, rung} <- [{1, :list}, {2, :follow}, {3, :grab}, {4, :grab}, {5, :ignored}] do
      create_title_intent(%{tmdb_id: id, media_type: :movie, name: "Movie #{id}", rung: rung})
    end

    legacy_rung!(3, "ask")
    legacy_rung!(4, "default")
    :ok
  end

  describe "sweep/1" do
    test "ask becomes grab; default becomes grab when the old setting grabbed; the setting goes" do
      global_mode!("all_releases")

      assert :ok = TrackingIsTwoSwitches.sweep(Repo)

      assert rungs() == %{1 => "list", 2 => "follow", 3 => "grab", 4 => "grab", 5 => "ignored"}
      assert Settings.get_by_key("auto_grab.default_mode") == nil
    end

    test "default becomes follow when the old setting was Notify only" do
      global_mode!("off")

      assert :ok = TrackingIsTwoSwitches.sweep(Repo)

      assert rungs()[4] == "follow"
      assert rungs()[3] == "grab"
    end

    test "default becomes grab when the old setting was Ask first, or absent" do
      global_mode!("ask")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs()[4] == "grab"

      legacy_rung!(4, "default")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs()[4] == "grab"
    end

    test "is idempotent" do
      global_mode!("off")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      before = rungs()
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs() == before
    end
  end
end
