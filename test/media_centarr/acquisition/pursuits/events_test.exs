defmodule MediaCentarr.Acquisition.Pursuits.EventsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.{PursuitStarted, ReleasePicked, StallConfirmed}
  alias MediaCentarr.Topics

  defp insert_pursuit do
    {:ok, pursuit} =
      Repo.insert(
        Pursuit.create_changeset(%{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        })
      )

    pursuit
  end

  describe "kind/0 + payload round-trip" do
    test "PursuitStarted round-trips through to_payload/from_payload" do
      original = %PursuitStarted{
        pursuit_id: Ecto.UUID.generate(),
        pursuit_title: "Sample Movie",
        occurred_at: DateTime.utc_now(:second),
        origin: "auto"
      }

      payload = PursuitStarted.to_payload(original)
      restored = PursuitStarted.from_payload(payload)

      # envelope fields are not part of the payload — they're persisted on the row directly
      assert payload == %{"origin" => "auto"}
      assert restored.origin == original.origin
    end

    test "ReleasePicked round-trips multi-key payload" do
      original = %ReleasePicked{
        pursuit_id: Ecto.UUID.generate(),
        pursuit_title: "Sample Movie",
        occurred_at: DateTime.utc_now(:second),
        release_title: "Sample.Movie.2010.1080p",
        guid: "indexer-guid-1",
        indexer: "ExampleIndexer",
        quality: "1080p",
        size_bytes: 4_500_000_000
      }

      payload = ReleasePicked.to_payload(original)
      restored = ReleasePicked.from_payload(payload)

      assert restored.release_title == original.release_title
      assert restored.guid == original.guid
      assert restored.indexer == original.indexer
      assert restored.quality == original.quality
      assert restored.size_bytes == original.size_bytes
    end
  end

  describe "Events.record/1" do
    test "persists an Event row and broadcasts the struct on acquisition_updates" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
      pursuit = insert_pursuit()

      event = %PursuitStarted{
        pursuit_id: pursuit.id,
        pursuit_title: "Sample Movie",
        occurred_at: DateTime.utc_now(:second),
        origin: "auto"
      }

      assert {:ok, ^event} = Events.record(event)

      # row persisted
      [row] = Repo.all(Event)
      assert row.kind == "pursuit_started"
      assert row.pursuit_id == event.pursuit_id
      assert row.denormalized_pursuit_title == "Sample Movie"
      assert row.payload == %{"origin" => "auto"}

      # struct broadcast
      assert_receive ^event
    end

    test "returns {:error, changeset} on validation failure" do
      pursuit = insert_pursuit()

      event = %PursuitStarted{
        pursuit_id: pursuit.id,
        # invalid: missing pursuit_title
        pursuit_title: nil,
        occurred_at: DateTime.utc_now(:second),
        origin: "auto"
      }

      assert {:error, %Ecto.Changeset{}} = Events.record(event)
    end
  end

  describe "Events.deserialize/2" do
    test "rebuilds a struct from a persisted Event row" do
      pursuit = insert_pursuit()
      occurred_at = DateTime.utc_now(:second)

      original = %StallConfirmed{
        pursuit_id: pursuit.id,
        pursuit_title: "Sample Movie",
        occurred_at: occurred_at,
        window_hours: 24,
        throughput_avg_bps: 0
      }

      {:ok, _} = Events.record(original)
      [row] = Repo.all(Event)

      restored = Events.deserialize(row)

      assert %StallConfirmed{} = restored
      assert restored.pursuit_id == pursuit.id
      assert restored.pursuit_title == "Sample Movie"
      assert DateTime.compare(restored.occurred_at, occurred_at) == :eq
      assert restored.window_hours == 24
      assert restored.throughput_avg_bps == 0
    end
  end

  describe "kind ↔ struct module mapping completeness" do
    test "every Event.kinds() entry has a corresponding struct module that returns that kind" do
      for kind <- Event.kinds() do
        module = Events.module_for_kind!(kind)

        assert module.kind() == kind,
               "module #{inspect(module)} reported kind #{module.kind()} but registered as #{kind}"
      end
    end

    test "no struct module is registered without being in Event.kinds()" do
      registered_kinds = Events.all_kinds()
      assert Enum.sort(registered_kinds) == Enum.sort(Event.kinds())
    end
  end
end
