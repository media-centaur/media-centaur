defmodule MediaCentarr.Acquisition.Pursuits.Commands.ReSearchTest do
  use MediaCentarr.DataCase, async: false
  use Oban.Testing, repo: MediaCentarr.Repo

  alias MediaCentarr.Acquisition.Pursuits.Commands.ReSearch
  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Repo

  defp setup_with_grab(pursuit_state, grab_status) do
    pursuit = create_pursuit(%{state: pursuit_state})

    grab =
      create_grab(%{
        pursuit_id: pursuit.id,
        status: grab_status,
        attempt_count: 3
      })

    {pursuit, grab}
  end

  describe "execute/1 — happy paths" do
    test "snoozed grab: forces search and records pursuit_re_searched event" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {pursuit, grab} = setup_with_grab("active", "snoozed")

        assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})

        assert_enqueued(
          worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab,
          args: %{"grab_id" => grab.id}
        )

        assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
      end)
    end

    test "abandoned grab: re-arms and records event" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {pursuit, _grab} = setup_with_grab("active", "abandoned")

        assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})
        assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
      end)
    end

    test "cancelled grab: re-arms" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {pursuit, _grab} = setup_with_grab("active", "cancelled")
        assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})
      end)
    end

    test "grabbed grab (stuck — file never landed): restarts and records event" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {pursuit, grab} = setup_with_grab("active", "grabbed")

        assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})

        assert_enqueued(
          worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab,
          args: %{"grab_id" => grab.id}
        )

        assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
      end)
    end
  end

  describe "execute/1 — refusal paths" do
    test "refuses when pursuit is terminal" do
      {pursuit, _grab} = setup_with_grab("satisfied", "grabbed")
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "refuses when no grab is linked" do
      pursuit = create_pursuit(%{state: "active"})
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "refuses manual-origin grabs (SearchAndGrab has no QueryBuilder clause for them)" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        pursuit = create_pursuit(%{state: "active", origin: "manual"})

        grab =
          create_grab(%{
            pursuit_id: pursuit.id,
            status: "grabbed",
            origin: "manual",
            tmdb_type: "manual"
          })

        assert {:error, :manual_pursuit} = ReSearch.execute(%{pursuit_id: pursuit.id})

        # No SearchAndGrab job should be enqueued — that's the whole point of
        # rejecting up-front, since the job would crash-loop on FunctionClauseError.
        refute_enqueued(
          worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab,
          args: %{"grab_id" => grab.id}
        )
      end)
    end

    test "refuses when grab is already searching" do
      {pursuit, _grab} = setup_with_grab("active", "searching")
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "returns :not_found for unknown pursuit_id" do
      assert {:error, :not_found} = ReSearch.execute(%{pursuit_id: Ecto.UUID.generate()})
    end
  end
end
