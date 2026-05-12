defmodule MediaCentarr.Acquisition.PursuitsTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Acquisition.Target

  defp insert_pursuit(overrides \\ %{}), do: create_pursuit(overrides)

  defp set_state(pursuit, new_state) do
    pursuit
    |> Ecto.Changeset.change(state: new_state)
    |> Repo.update!()
  end

  defp insert_event(pursuit, kind, occurred_at) do
    {:ok, event} =
      Repo.insert(
        Event.create_changeset(%{
          pursuit_id: pursuit.id,
          denormalized_pursuit_title: pursuit.title,
          kind: kind,
          payload: %{},
          occurred_at: occurred_at
        })
      )

    event
  end

  defp insert_target_for(pursuit, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    {:ok, target} =
      %Target{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            pursuit_id: pursuit.id,
            title: pursuit.title,
            origin: pursuit.origin,
            status: "seeking",
            inserted_at: now,
            updated_at: now
          },
          attrs
        )
      )
      |> Repo.insert()

    target
  end

  describe "get/1" do
    test "returns the pursuit by id" do
      pursuit = insert_pursuit()
      assert {:ok, fetched} = Pursuits.get(pursuit.id)
      assert fetched.id == pursuit.id
    end

    test "returns :not_found when missing" do
      assert {:error, :not_found} = Pursuits.get(Ecto.UUID.generate())
    end
  end

  describe "list_active/0" do
    test "returns only in-flight pursuits, excludes terminal states" do
      terminal = set_state(insert_pursuit(), "satisfied")
      active_old = insert_pursuit(%{tmdb_id: "111", title: "Old"})
      active_new = insert_pursuit(%{tmdb_id: "222", title: "New"})

      ids = Enum.map(Pursuits.list_active(), & &1.id)

      assert active_new.id in ids
      assert active_old.id in ids
      refute terminal.id in ids
    end

    test "needs_decision pursuits also count as active" do
      pursuit = set_state(insert_pursuit(), "needs_decision")
      ids = Enum.map(Pursuits.list_active(), & &1.id)
      assert pursuit.id in ids
    end

    test "excludes satisfied, exhausted, and cancelled" do
      satisfied = set_state(insert_pursuit(%{tmdb_id: "1"}), "satisfied")
      exhausted = set_state(insert_pursuit(%{tmdb_id: "2"}), "exhausted")
      cancelled = set_state(insert_pursuit(%{tmdb_id: "3"}), "cancelled")

      ids = Enum.map(Pursuits.list_active(), & &1.id)

      refute satisfied.id in ids
      refute exhausted.id in ids
      refute cancelled.id in ids
    end
  end

  describe "events_for/1" do
    test "returns events for a pursuit, newest first" do
      pursuit = insert_pursuit()
      old = insert_event(pursuit, "pursuit_started", DateTime.add(DateTime.utc_now(:second), -60))
      new = insert_event(pursuit, "release_picked", DateTime.utc_now(:second))

      [first, second] = Pursuits.events_for(pursuit.id)
      assert first.id == new.id
      assert second.id == old.id
    end

    test "returns empty list for unknown pursuit_id" do
      assert Pursuits.events_for(Ecto.UUID.generate()) == []
    end
  end

  describe "latest_target/1" do
    test "returns the most recently inserted target linked to the pursuit" do
      pursuit = insert_pursuit()
      old = insert_target_for(pursuit)

      old
      |> Ecto.Changeset.change(inserted_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      newer = insert_target_for(pursuit, %{title: "Newer attempt"})

      assert {:ok, found} = Pursuits.latest_target(pursuit.id)
      assert found.id == newer.id
    end

    test "returns :not_found when no targets exist" do
      pursuit = insert_pursuit()
      assert {:error, :not_found} = Pursuits.latest_target(pursuit.id)
    end
  end

  describe "find_active_for_target/1" do
    test "returns active movie pursuits matching tmdb_id + tmdb_type" do
      match = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie"})
      _other = insert_pursuit(%{tmdb_id: "999", tmdb_type: "movie"})

      [result] = Pursuits.find_active_for_target(%{tmdb_id: "555", tmdb_type: "movie"})
      assert result.id == match.id
    end

    test "excludes terminal-state pursuits" do
      pursuit = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie"})
      set_state(pursuit, "satisfied")

      assert [] = Pursuits.find_active_for_target(%{tmdb_id: "555", tmdb_type: "movie"})
    end

    test "excludes needs_decision pursuits (paused, awaiting user)" do
      pursuit = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie"})
      set_state(pursuit, "needs_decision")

      assert [] = Pursuits.find_active_for_target(%{tmdb_id: "555", tmdb_type: "movie"})
    end

    test "matches TV pursuits by tmdb_id, season_number, and episode_number" do
      match =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 5
        })

      _wrong_episode =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 6
        })

      [result] =
        Pursuits.find_active_for_target(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          season_number: 2,
          episode_number: 5
        })

      assert result.id == match.id
    end

    test "TV pursuit without season pin matches any episode (e.g., season-pack pursuit)" do
      match =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show"
        })

      [result] =
        Pursuits.find_active_for_target(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          season_number: 2,
          episode_number: 5
        })

      assert result.id == match.id
    end

    test "does not cross movie pursuits to tv events" do
      _movie = insert_pursuit(%{tmdb_id: "777", tmdb_type: "movie"})

      assert [] =
               Pursuits.find_active_for_target(%{
                 tmdb_id: "777",
                 tmdb_type: "tv",
                 season_number: 1,
                 episode_number: 1
               })
    end

    test "returns [] for malformed targets" do
      assert [] = Pursuits.find_active_for_target(%{})
      assert [] = Pursuits.find_active_for_target(%{tmdb_id: nil, tmdb_type: "movie"})
    end
  end

  describe "list_active_rows/0" do
    alias MediaCentarr.Acquisition.ViewModels.{CurrentAction, PursuitRow}

    test "returns PursuitRow VMs for in-flight pursuits" do
      pursuit = insert_pursuit()

      [row] = Pursuits.list_active_rows()

      assert %PursuitRow{} = row
      assert row.id == pursuit.id
      assert row.title == "Sample Movie"
      assert row.state == :active
    end

    test "excludes terminal pursuits" do
      _terminal = set_state(insert_pursuit(), "satisfied")
      assert Pursuits.list_active_rows() == []
    end

    test "row carries season_number and episode_number from a TV pursuit" do
      _pursuit =
        insert_pursuit(%{
          tmdb_type: "tv",
          tmdb_id: "1001",
          title: "Sample Show",
          season_number: 2,
          episode_number: 1
        })

      [row] = Pursuits.list_active_rows()

      assert row.season_number == 2
      assert row.episode_number == 1
    end

    test "row season_number/episode_number are nil for a movie pursuit" do
      _pursuit = insert_pursuit()

      [row] = Pursuits.list_active_rows()

      assert row.season_number == nil
      assert row.episode_number == nil
    end

    test "row.status is a CurrentAction derived from pursuit + current target" do
      {_pursuit, _target} =
        create_pursuit_with_target(%{
          release_title: "Sample.Movie.2010.1080p.WEB-DL",
          status: "seeking"
        })

      [row] = Pursuits.list_active_rows()

      assert %CurrentAction{verb: "Searching", severity: :info} = row.status
    end

    test "row.status reflects needs_decision pursuit state" do
      pursuit = insert_pursuit()

      _ =
        pursuit
        |> Ecto.Changeset.change(state: "needs_decision")
        |> MediaCentarr.Repo.update!()

      [row] = Pursuits.list_active_rows()

      assert %CurrentAction{verb: "Decision needed", severity: :warning} = row.status
    end

    test "row carries the current target's release_title and status for queue matching" do
      {pursuit, target} =
        create_pursuit_with_target(%{
          release_title: "Sample.Movie.2010.1080p.WEB-DL",
          status: "acquired"
        })

      _ = pursuit
      _ = target

      [row] = Pursuits.list_active_rows()

      assert row.release_title == "Sample.Movie.2010.1080p.WEB-DL"
      assert row.target_status == :acquired
    end

    test "row release_title and target_status are nil when no target is linked" do
      _pursuit = insert_pursuit()

      [row] = Pursuits.list_active_rows()

      assert row.release_title == nil
      assert row.target_status == nil
    end
  end

  describe "list_rows/1" do
    alias MediaCentarr.Acquisition.ViewModels.PursuitRow

    test ":active matches list_active_rows/0 — pursuits in :active or :needs_decision" do
      active = insert_pursuit(%{title: "Active Show", tmdb_id: "2001"})
      needs = set_state(insert_pursuit(%{title: "Decision Show", tmdb_id: "2002"}), "needs_decision")
      _terminal = set_state(insert_pursuit(%{title: "Done Show", tmdb_id: "2003"}), "satisfied")

      rows = Pursuits.list_rows(:active)

      assert Enum.all?(rows, &match?(%PursuitRow{}, &1))
      ids = Enum.sort(Enum.map(rows, & &1.id))
      assert ids == Enum.sort([active.id, needs.id])
    end

    test ":failed returns only pursuits in :exhausted state" do
      exhausted = set_state(insert_pursuit(%{title: "Exhausted", tmdb_id: "2010"}), "exhausted")
      _cancelled = set_state(insert_pursuit(%{title: "Cancelled", tmdb_id: "2011"}), "cancelled")
      _satisfied = set_state(insert_pursuit(%{title: "Satisfied", tmdb_id: "2012"}), "satisfied")
      _active = insert_pursuit(%{title: "Active", tmdb_id: "2013"})

      [row] = Pursuits.list_rows(:failed)
      assert row.id == exhausted.id
      assert row.state == :exhausted
    end

    test ":cancelled returns only pursuits in :cancelled state" do
      cancelled = set_state(insert_pursuit(%{title: "Cancelled", tmdb_id: "2020"}), "cancelled")
      _exhausted = set_state(insert_pursuit(%{title: "Exhausted", tmdb_id: "2021"}), "exhausted")

      [row] = Pursuits.list_rows(:cancelled)
      assert row.id == cancelled.id
      assert row.state == :cancelled
    end

    test ":succeeded returns only pursuits in :satisfied state" do
      satisfied = set_state(insert_pursuit(%{title: "Satisfied", tmdb_id: "2030"}), "satisfied")
      _exhausted = set_state(insert_pursuit(%{title: "Exhausted", tmdb_id: "2031"}), "exhausted")

      [row] = Pursuits.list_rows(:succeeded)
      assert row.id == satisfied.id
      assert row.state == :satisfied
    end

    test ":all_terminal returns every terminal-state pursuit, excludes in-flight" do
      _active = insert_pursuit(%{title: "Active", tmdb_id: "2040"})
      ex = set_state(insert_pursuit(%{title: "Exhausted", tmdb_id: "2041"}), "exhausted")
      ca = set_state(insert_pursuit(%{title: "Cancelled", tmdb_id: "2042"}), "cancelled")
      sa = set_state(insert_pursuit(%{title: "Satisfied", tmdb_id: "2043"}), "satisfied")

      rows = Pursuits.list_rows(:all_terminal)
      ids = Enum.sort(Enum.map(rows, & &1.id))
      assert ids == Enum.sort([ex.id, ca.id, sa.id])
    end

    test "rows carry season_number, episode_number, and release_title from the current target" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_type: "tv",
          tmdb_id: "2050",
          title: "Sample Show",
          season_number: 1,
          episode_number: 4,
          release_title: "Sample.Show.S01E04.1080p.WEB-DL",
          status: "failed"
        })

      _ = set_state(pursuit, "exhausted")

      [row] = Pursuits.list_rows(:failed)
      assert row.season_number == 1
      assert row.episode_number == 4
      assert row.release_title == "Sample.Show.S01E04.1080p.WEB-DL"
    end
  end

  describe "header_for/1" do
    alias MediaCentarr.Acquisition.ViewModels.PursuitHeader

    test "returns a PursuitHeader VM for an existing pursuit" do
      pursuit =
        insert_pursuit(%{
          criteria: %{"min_quality" => "1080p", "max_quality" => "2160p"}
        })

      assert {:ok, %PursuitHeader{} = header} = Pursuits.header_for(pursuit.id)

      assert header.id == pursuit.id
      assert header.title == "Sample Movie"
      assert header.state == :active
      assert header.criteria_summary =~ "1080p"
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} = Pursuits.header_for(Ecto.UUID.generate())
    end
  end

  describe "timeline_for/1" do
    alias MediaCentarr.Acquisition.ViewModels.{Timeline, TimelineEntry}

    test "returns a Timeline VM with all events newest-first" do
      pursuit = insert_pursuit()
      insert_event(pursuit, "pursuit_started", DateTime.add(DateTime.utc_now(:second), -300))
      insert_event(pursuit, "stall_confirmed", DateTime.add(DateTime.utc_now(:second), -60))
      insert_event(pursuit, "user_decision_requested", DateTime.utc_now(:second))

      timeline = Pursuits.timeline_for(pursuit.id)

      assert %Timeline{pursuit_id: pid} = timeline
      assert pid == pursuit.id

      kinds = Enum.map(timeline.entries, & &1.kind)
      assert kinds == ["user_decision_requested", "stall_confirmed", "pursuit_started"]

      stall = Enum.find(timeline.entries, &(&1.kind == "stall_confirmed"))
      assert %TimelineEntry{severity: :warning} = stall
    end

    test "returns an empty Timeline when there are no events" do
      pursuit = insert_pursuit()
      timeline = Pursuits.timeline_for(pursuit.id)
      assert timeline.pursuit_id == pursuit.id
      assert timeline.entries == []
    end
  end
end
