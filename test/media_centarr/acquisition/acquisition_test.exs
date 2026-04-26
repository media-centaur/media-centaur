defmodule MediaCentarr.AcquisitionTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{Grab, Prowlarr}
  alias MediaCentarr.Repo

  setup do
    # Oban runs jobs inline in tests (`testing: :inline` in config/test.exs).
    # Calling Acquisition.enqueue/4 therefore triggers SearchAndGrab.perform
    # immediately, which calls Prowlarr.search — install an empty-response
    # stub so the worker snoozes cleanly instead of crashing on no client.
    # We don't assert on the worker side-effects here (those tests live in
    # search_and_grab_test.exs); we only verify the grab row enqueue created.
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)
    on_exit(fn -> :persistent_term.erase({Prowlarr, :client}) end)
    :ok
  end

  describe "enqueue/4 — granularity" do
    test "movie key uses NULL season and episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("12345", "movie", "Inception", year: 2010)

      assert grab.season_number == nil
      assert grab.episode_number == nil
      assert grab.year == 2010
      assert grab.status == "searching"
    end

    test "TV episode key carries season and episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("999", "tv", "Severance",
                 season_number: 3,
                 episode_number: 4
               )

      assert grab.tmdb_type == "tv"
      assert grab.season_number == 3
      assert grab.episode_number == 4
    end

    test "TV season pack uses non-NULL season with NULL episode" do
      assert {:ok, %Grab{} = grab} =
               Acquisition.enqueue("999", "tv", "Severance", season_number: 3)

      assert grab.season_number == 3
      assert grab.episode_number == nil
    end
  end

  describe "enqueue/4 — idempotency on the four-tuple" do
    test "second call for same (tmdb_id, type, season, episode) returns the existing grab" do
      assert {:ok, first} =
               Acquisition.enqueue("999", "tv", "Severance",
                 season_number: 3,
                 episode_number: 4
               )

      assert {:ok, second} =
               Acquisition.enqueue("999", "tv", "Severance",
                 season_number: 3,
                 episode_number: 4
               )

      assert first.id == second.id
    end

    test "different episode of same series creates a separate grab" do
      assert {:ok, e4} =
               Acquisition.enqueue("999", "tv", "Severance",
                 season_number: 3,
                 episode_number: 4
               )

      assert {:ok, e5} =
               Acquisition.enqueue("999", "tv", "Severance",
                 season_number: 3,
                 episode_number: 5
               )

      assert e4.id != e5.id
    end

    test "movie and TV with the same tmdb_id are independent rows (different tmdb_type)" do
      assert {:ok, movie} = Acquisition.enqueue("999", "movie", "Same Number")
      assert {:ok, tv} = Acquisition.enqueue("999", "tv", "Same Number")
      assert movie.id != tv.id
    end
  end

  describe "list_auto_grabs/1" do
    test ":all returns every row, newest-updated first" do
      grab1 = create_grab(%{tmdb_id: "1", title: "First"})
      grab2 = create_grab(%{tmdb_id: "2", title: "Second"})
      _ = Repo.update!(Grab.cancelled_changeset(grab1, "x"))

      assert grabs = Acquisition.list_auto_grabs(:all)
      assert length(grabs) == 2
      assert Enum.find(grabs, &(&1.id == grab1.id))
      assert Enum.find(grabs, &(&1.id == grab2.id))
    end

    test ":active returns only searching/snoozed (excludes terminal states)" do
      _searching = create_grab(%{tmdb_id: "10", title: "Searching"})
      snoozed = create_grab(%{tmdb_id: "11", title: "Snoozed"})
      Repo.update!(Grab.attempt_changeset(snoozed, "no_results", snoozed: true))
      grabbed = create_grab(%{tmdb_id: "12", title: "Grabbed"})
      Repo.update!(Grab.grabbed_changeset(grabbed, "4K"))
      cancelled = create_grab(%{tmdb_id: "13", title: "Cancelled"})
      Repo.update!(Grab.cancelled_changeset(cancelled, "x"))

      titles = Acquisition.list_auto_grabs(:active) |> Enum.map(& &1.title) |> Enum.sort()
      assert titles == ["Searching", "Snoozed"]
    end

    test ":abandoned returns only abandoned" do
      grab = create_grab(%{tmdb_id: "20", title: "Lost cause"})
      Repo.update!(Grab.abandoned_changeset(grab))

      assert [%Grab{title: "Lost cause"}] = Acquisition.list_auto_grabs(:abandoned)
    end
  end

  describe "rearm_grab/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "flips a cancelled grab back to searching, resets attempts, broadcasts" do
      grab = create_grab(%{tmdb_id: "rearm-1", title: "Comeback", attempt_count: 5})
      Repo.update!(Grab.cancelled_changeset(grab, "user_disabled"))

      assert {:ok, rearmed} = Acquisition.rearm_grab(grab.id)

      assert rearmed.status == "searching"
      assert rearmed.attempt_count == 0
      assert rearmed.cancelled_at == nil
      assert rearmed.cancelled_reason == nil
      assert_received {:auto_grab_armed, %Grab{title: "Comeback"}}
    end

    test "flips an abandoned grab back to searching" do
      grab = create_grab(%{tmdb_id: "rearm-2", title: "Abandoned", attempt_count: 12})
      Repo.update!(Grab.abandoned_changeset(grab))

      assert {:ok, rearmed} = Acquisition.rearm_grab(grab.id)
      assert rearmed.status == "searching"
      assert rearmed.attempt_count == 0
    end

    test "is a no-op for active grabs (already searching/snoozed)" do
      grab = create_grab(%{tmdb_id: "rearm-3", title: "Already going"})

      assert {:ok, ^grab} = Acquisition.rearm_grab(grab.id)
      refute_received {:auto_grab_armed, _}
    end

    test "is a no-op for grabbed grabs" do
      grab = create_grab(%{tmdb_id: "rearm-4", title: "Already done"})
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "4K"))

      assert {:ok, ^grabbed} = Acquisition.rearm_grab(grabbed.id)
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Acquisition.rearm_grab(Ecto.UUID.generate())
    end
  end

  describe "cancel_grab/2" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      :ok
    end

    test "marks status cancelled, sets reason and timestamp, broadcasts" do
      grab = create_grab()

      assert {:ok, cancelled} = Acquisition.cancel_grab(grab.id, "user_disabled")

      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_reason == "user_disabled"
      assert cancelled.cancelled_at != nil
      assert_received {:auto_grab_cancelled, %Grab{cancelled_reason: "user_disabled"}}
    end

    test "returns :not_found for unknown grab id" do
      assert {:error, :not_found} = Acquisition.cancel_grab(Ecto.UUID.generate(), "x")
    end

    test "is a no-op (no broadcast) on a grab that is already grabbed" do
      grab = create_grab()
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "4K"))

      assert {:ok, ^grabbed} = Acquisition.cancel_grab(grabbed.id, "user_disabled")
      assert grabbed.status == "grabbed"
      refute_received {:auto_grab_cancelled, _}
    end
  end
end
