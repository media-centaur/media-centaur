defmodule MediaCentaurWeb.LibraryChannelTest do
  use MediaCentaurWeb.ChannelCase

  defp join_and_get_socket do
    {:ok, reply, socket} =
      MediaCentaurWeb.UserSocket
      |> socket()
      |> subscribe_and_join(MediaCentaurWeb.LibraryChannel, "library")

    assert reply == %{}

    socket
  end

  defp drain_initial_sync do
    drain_initial_sync([])
  end

  defp drain_initial_sync(entities) do
    receive do
      %Phoenix.Socket.Message{event: "library:entities", payload: %{entities: batch}} ->
        drain_initial_sync(entities ++ batch)

      %Phoenix.Socket.Message{event: "library:sync_complete"} ->
        entities
    after
      1_000 -> flunk("Timed out waiting for library:sync_complete")
    end
  end

  defp join_library do
    socket = join_and_get_socket()
    drain_initial_sync()
    socket
  end

  describe "join" do
    test "empty library returns empty reply and sync_complete with no entity batches" do
      _socket = join_and_get_socket()

      assert_push "library:sync_complete", %{}
      refute_push "library:entities", _
    end

    test "library with entity sends entity batch then sync_complete" do
      entity = create_entity(%{type: :movie, name: "Blade Runner 2049"})

      _socket = join_and_get_socket()
      entities = drain_initial_sync()

      wire = json_roundtrip(%{entities: entities})
      assert [entry] = wire["entities"]

      assert entry["@id"] == entity.id
      assert is_map(entry["entity"])
      assert entry["entity"]["@type"] == "Movie"
      assert entry["entity"]["name"] == "Blade Runner 2049"
      assert entry["progress"] == nil
    end

    test "entity with watch progress includes progress summary in batch" do
      entity = create_entity(%{type: :movie, name: "Progress Movie"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 600.0,
        duration_seconds: 7200.0
      })

      _socket = join_and_get_socket()
      entities = drain_initial_sync()

      wire = json_roundtrip(%{entities: entities})
      [entry] = wire["entities"]

      progress = entry["progress"]
      assert is_map(progress)
      assert progress["episode_position_seconds"] == 600.0
      assert progress["episode_duration_seconds"] == 7200.0
      assert progress["episodes_completed"] == 0
      assert progress["episodes_total"] == 1
      assert progress["current_episode"] == nil
    end
  end

  describe "incremental updates" do
    test "new entity pushes library:entities" do
      socket = join_library()

      entity = create_entity(%{type: :movie, name: "Dune: Part Two"})
      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entities", payload
      wire = json_roundtrip(payload)

      assert [entry] = wire["entities"]
      assert entry["@id"] == entity.id
      assert entry["entity"]["@type"] == "Movie"
      assert entry["entity"]["name"] == "Dune: Part Two"
      assert entry["progress"] == nil
    end

    test "known entity update pushes library:entities" do
      entity = create_entity(%{type: :movie, name: "Original Name"})
      socket = join_library()

      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entities", payload
      wire = json_roundtrip(payload)

      assert [entry] = wire["entities"]
      assert entry["@id"] == entity.id
      assert entry["entity"]["@type"] == "Movie"
    end

    test "deleted entity pushes library:entities_removed" do
      entity = create_entity(%{type: :tv_series, name: "Cancelled Show"})
      socket = join_library()

      Ash.destroy!(entity)
      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entities_removed", payload
      wire = json_roundtrip(payload)

      assert wire == %{"ids" => [entity.id]}
    end

    test "mixed updates and removals push both message types" do
      kept = create_entity(%{type: :movie, name: "Kept Movie"})
      removed = create_entity(%{type: :movie, name: "Removed Movie"})
      socket = join_library()

      Ash.destroy!(removed)
      send(socket.channel_pid, {:entities_changed, [kept.id, removed.id]})

      assert_push "library:entities", entities_payload
      assert_push "library:entities_removed", removed_payload

      entities_wire = json_roundtrip(entities_payload)
      assert [entry] = entities_wire["entities"]
      assert entry["@id"] == kept.id

      removed_wire = json_roundtrip(removed_payload)
      assert removed_wire == %{"ids" => [removed.id]}
    end

    test "large entity update is batched into multiple pushes" do
      entities = for i <- 1..55, do: create_entity(%{type: :movie, name: "Batch Movie #{i}"})
      socket = join_library()

      entity_ids = Enum.map(entities, & &1.id)
      send(socket.channel_pid, {:entities_changed, entity_ids})

      assert_push "library:entities", first_payload
      assert_push "library:entities", second_payload
      refute_push "library:entities", _

      first_wire = json_roundtrip(first_payload)
      second_wire = json_roundtrip(second_payload)

      assert length(first_wire["entities"]) == 50
      assert length(second_wire["entities"]) == 5
    end

    test "large removal list is batched into multiple pushes" do
      entities = for i <- 1..55, do: create_entity(%{type: :movie, name: "Remove Movie #{i}"})
      socket = join_library()

      entity_ids = Enum.map(entities, & &1.id)
      Enum.each(entities, &Ash.destroy!/1)
      send(socket.channel_pid, {:entities_changed, entity_ids})

      assert_push "library:entities_removed", first_payload
      assert_push "library:entities_removed", second_payload
      refute_push "library:entities_removed", _

      first_wire = json_roundtrip(first_payload)
      second_wire = json_roundtrip(second_payload)

      assert length(first_wire["ids"]) == 50
      assert length(second_wire["ids"]) == 5
    end
  end
end
