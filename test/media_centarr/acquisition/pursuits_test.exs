defmodule MediaCentarr.Acquisition.PursuitsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}

  defp insert_pursuit(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        },
        overrides
      )

    {:ok, pursuit} = Repo.insert(Pursuit.create_changeset(attrs))
    pursuit
  end

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

  defp insert_grab_for(pursuit, attrs \\ %{}) do
    base = %{
      tmdb_id: pursuit.tmdb_id,
      tmdb_type: pursuit.tmdb_type,
      title: pursuit.title,
      origin: pursuit.origin
    }

    %Grab{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:tmdb_id, :tmdb_type, :title, :origin])
    |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
    |> Repo.insert!()
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

  describe "latest_grab/1" do
    test "returns the most recently inserted grab linked to the pursuit" do
      pursuit = insert_pursuit()
      old = insert_grab_for(pursuit)
      # Backdate the older grab explicitly so we don't depend on per-second
      # `inserted_at` resolution differing between two same-test inserts.
      old
      |> Ecto.Changeset.change(inserted_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      newer = insert_grab_for(pursuit, %{title: "Newer attempt"})

      assert {:ok, found} = Pursuits.latest_grab(pursuit.id)
      assert found.id == newer.id
    end

    test "returns :not_found when no grabs exist" do
      pursuit = insert_pursuit()
      assert {:error, :not_found} = Pursuits.latest_grab(pursuit.id)
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
    alias MediaCentarr.Acquisition.ViewModels.{PursuitRow, TimelineEntry}

    test "returns PursuitRow VMs for in-flight pursuits with recent events" do
      pursuit = insert_pursuit()
      insert_event(pursuit, "pursuit_started", DateTime.add(DateTime.utc_now(:second), -120))
      insert_event(pursuit, "release_picked", DateTime.utc_now(:second))

      [row] = Pursuits.list_active_rows()

      assert %PursuitRow{} = row
      assert row.id == pursuit.id
      assert row.title == "Sample Movie"
      assert row.state == :active
      assert row.origin == :auto
      assert row.detail_path == "/download/#{pursuit.id}"

      # newest first, capped at recent count
      assert [%TimelineEntry{kind: "release_picked"}, %TimelineEntry{kind: "pursuit_started"}] =
               row.recent_events
    end

    test "excludes terminal pursuits" do
      _terminal = set_state(insert_pursuit(), "satisfied")
      assert Pursuits.list_active_rows() == []
    end

    test "row has empty recent_events when no events exist" do
      pursuit = insert_pursuit()
      [row] = Pursuits.list_active_rows()
      assert row.id == pursuit.id
      assert row.recent_events == []
    end
  end

  describe "header_for/1" do
    alias MediaCentarr.Acquisition.ViewModels.PursuitHeader

    test "returns a PursuitHeader VM for an existing pursuit" do
      pursuit =
        insert_pursuit(%{
          criteria: %{"min_quality" => "1080p", "max_quality" => "2160p"}
        })

      pursuit
      |> Ecto.Changeset.change(tried_release_guids: ["guid-a", "guid-b"], attempt_count: 2)
      |> Repo.update!()

      assert {:ok, %PursuitHeader{} = header} = Pursuits.header_for(pursuit.id)

      assert header.id == pursuit.id
      assert header.title == "Sample Movie"
      assert header.state == :active
      assert header.attempt_count == 2
      assert header.tried_count == 2
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

      # severity is mapped per kind
      stall = Enum.find(timeline.entries, &(&1.kind == "stall_confirmed"))
      assert %TimelineEntry{severity: :warning} = stall

      verified = %TimelineEntry{
        kind: "pursuit_started",
        occurred_at: DateTime.utc_now(:second),
        summary: "Pursuit started",
        severity: :info
      }

      assert is_struct(verified)
    end

    test "returns an empty Timeline when there are no events" do
      pursuit = insert_pursuit()
      timeline = Pursuits.timeline_for(pursuit.id)
      assert timeline.pursuit_id == pursuit.id
      assert timeline.entries == []
    end
  end
end
