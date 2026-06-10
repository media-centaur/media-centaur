defmodule MediaCentaur.Repo.DataMigrations.SupersedeLegacySeekersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.SupersedeLegacySeekers

  defp create_legacy_seeker(attrs \\ %{}) do
    {pursuit, target} =
      create_pursuit_with_target(
        Map.merge(
          %{
            recipe_type: "tmdb",
            tmdb_id: "1396",
            tmdb_type: "tv",
            title: "Sample Show",
            season_number: 2,
            episode_number: 7,
            origin: "auto",
            status: "seeking"
          },
          attrs
        )
      )

    {pursuit, target}
  end

  describe "supersede/1" do
    test "system-cancels a pure seeker: targets, units, and the parent" do
      {pursuit, target} = create_legacy_seeker()

      assert :ok = SupersedeLegacySeekers.supersede(Repo)

      assert Repo.get!(Pursuit, pursuit.id).state == "cancelled"
      assert Enum.all?(Units.for_pursuit(pursuit.id), &(&1.state == "cancelled"))

      reloaded_target = Repo.get!(Target, target.id)
      assert reloaded_target.status == "cancelled"
      assert reloaded_target.cancelled_reason == "superseded_by_plans"
    end

    test "leaves a pursuit with an acquired target (download in progress) alone" do
      {pursuit, _target} = create_legacy_seeker(%{tmdb_id: "1397", status: "acquired"})

      assert :ok = SupersedeLegacySeekers.supersede(Repo)

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "leaves manual (query-door) pursuits alone" do
      {pursuit, _target} =
        create_legacy_seeker(%{tmdb_id: "1398", origin: "manual", status: "seeking"})

      assert :ok = SupersedeLegacySeekers.supersede(Repo)

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "is idempotent" do
      {pursuit, _target} = create_legacy_seeker(%{tmdb_id: "1399"})

      assert :ok = SupersedeLegacySeekers.supersede(Repo)
      assert :ok = SupersedeLegacySeekers.supersede(Repo)

      assert Repo.get!(Pursuit, pursuit.id).state == "cancelled"
    end
  end
end
