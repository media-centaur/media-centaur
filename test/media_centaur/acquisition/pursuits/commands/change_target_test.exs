defmodule MediaCentaur.Acquisition.Pursuits.Commands.ChangeTargetTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.Commands.ChangeTarget
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Acquisition.Target

  defp run(args) do
    Oban.Testing.with_testing_mode(:manual, fn -> ChangeTarget.execute(args) end)
  end

  describe "execute/1 — stopping the replaced release's download" do
    # Swapping a release removes the abandoned attempt's download from
    # the client, like cancellation (user-settled 2026-06-11).

    test "the replaced release's download is deleted from the client" do
      MediaCentaur.DownloadClientStubs.setup_qbittorrent_client()
      MediaCentaur.DownloadClientStubs.forward_deletes_to(self())

      {pursuit, _target} =
        create_pursuit_with_target(%{status: "acquired", torrent_hash: "01dbeef00001dbeef00001dbeef00001dbeef000"})

      assert {:ok, %Pursuit{}} = run(%{pursuit_id: pursuit.id})

      assert_receive {:qbit_delete, %{"hashes" => "01dbeef00001dbeef00001dbeef00001dbeef000", "deleteFiles" => "true"}}
    end
  end

  describe "execute/1 — unit-scoped pivot (ADR-055 drill-down)" do
    test "pivots only the addressed unit; the sibling's thread is untouched" do
      {pursuit, first_target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          manual_query: "Sample Show S01E{01-02}",
          title: "Sample Show S01E{01-02}",
          query: "Sample Show S01E01",
          status: "acquired"
        })

      second_unit = create_pursuit_unit(pursuit, %{query: "Sample Show S01E02", position: 1})

      assert {:ok, %Pursuit{}} = run(%{pursuit_id: pursuit.id, unit_id: second_unit.id})

      # The addressed unit gained a fresh seeking target covering it.
      pivoted = Repo.reload(second_unit)
      refute is_nil(pivoted.current_target_id)
      new_target = Repo.get!(Target, pivoted.current_target_id)
      assert new_target.status == "seeking"
      assert [covered] = Units.covered_by(new_target.id)
      assert covered.id == second_unit.id

      # The sibling unit still points at its original acquired target.
      [first_unit, _] = Units.for_pursuit(pursuit.id)
      assert first_unit.current_target_id == first_target.id
      assert Repo.get!(Target, first_target.id).status == "acquired"
    end

    test "a terminal unit does not pivot" do
      {pursuit, _target} = create_pursuit_with_target(%{status: "acquired"})
      satisfied_unit = create_pursuit_unit(pursuit, %{position: 1, state: "satisfied"})

      assert {:error, :not_eligible} =
               run(%{pursuit_id: pursuit.id, unit_id: satisfied_unit.id})
    end

    test "without unit_id the lead unit pivots (legacy pursuit-scoped shape)" do
      # `seeking` is non-terminal, so the pivot fails it with the
      # user-pivot reason; an `acquired` target would be left as-is
      # (terminal-success in TargetStatus).
      {pursuit, original_target} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{}} = run(%{pursuit_id: pursuit.id})

      unit = Units.single!(pursuit.id)
      refute unit.current_target_id == original_target.id

      reloaded = Repo.get!(Target, original_target.id)
      assert reloaded.status == "failed"
      assert reloaded.cancelled_reason == "replaced_by_user_pivot"
    end
  end
end
