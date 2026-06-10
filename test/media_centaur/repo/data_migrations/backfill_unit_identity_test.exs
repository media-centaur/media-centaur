defmodule MediaCentaur.Repo.DataMigrations.BackfillUnitIdentityTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.BackfillUnitIdentity

  # Pre-backfill shape: an auto pursuit carrying season/episode on the
  # parent whose single unit was created without identity (the Phase-3
  # migration added the unit columns additively, no backfill).
  defp create_legacy_auto_pursuit do
    {pursuit, _target} =
      create_pursuit_with_target(%{
        tmdb_id: "1396",
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 2,
        episode_number: 7
      })

    unit = Units.single!(pursuit.id)

    {:ok, legacy_unit} =
      unit
      |> Ecto.Changeset.change(season_number: nil, episode_number: nil)
      |> Repo.update()

    {pursuit, legacy_unit}
  end

  describe "backfill/1" do
    test "copies parent-level season/episode onto an identity-less unit" do
      {pursuit, _legacy_unit} = create_legacy_auto_pursuit()

      assert :ok = BackfillUnitIdentity.backfill(Repo)

      backfilled = Units.single!(pursuit.id)
      assert backfilled.season_number == 2
      assert backfilled.episode_number == 7
    end

    test "leaves units that already carry identity untouched" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "1396",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 7
        })

      unit = Units.single!(pursuit.id)

      {:ok, _divergent} =
        unit
        |> Ecto.Changeset.change(season_number: 4, episode_number: 1)
        |> Repo.update()

      assert :ok = BackfillUnitIdentity.backfill(Repo)

      untouched = Units.single!(pursuit.id)
      assert untouched.season_number == 4
      assert untouched.episode_number == 1
    end

    test "leaves query-door units (no parent identity) untouched and is idempotent" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          title: "Sample.Show.S01E01.1080p.WEB-DL",
          manual_query: "Sample Show S01E01"
        })

      assert :ok = BackfillUnitIdentity.backfill(Repo)
      assert :ok = BackfillUnitIdentity.backfill(Repo)

      unit = Units.single!(pursuit.id)
      assert is_nil(unit.season_number)
      assert is_nil(unit.episode_number)
    end
  end
end
