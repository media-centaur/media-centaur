defmodule MediaManagerWeb.LibraryChannelTest do
  use MediaManagerWeb.ChannelCase

  defp join_library do
    {:ok, _, socket} =
      MediaManagerWeb.UserSocket
      |> socket()
      |> subscribe_and_join(MediaManagerWeb.LibraryChannel, "library")

    socket
  end

  describe "join" do
    test "empty library returns empty entities list" do
      {:ok, reply, _socket} =
        MediaManagerWeb.UserSocket
        |> socket()
        |> subscribe_and_join(MediaManagerWeb.LibraryChannel, "library")

      wire = json_roundtrip(reply)
      assert wire == %{"entities" => []}
    end

    test "library with a movie returns wrapped entity format" do
      entity = create_entity(%{type: :movie, name: "Blade Runner 2049"})

      {:ok, reply, _socket} =
        MediaManagerWeb.UserSocket
        |> socket()
        |> subscribe_and_join(MediaManagerWeb.LibraryChannel, "library")

      wire = json_roundtrip(reply)
      assert [entry] = wire["entities"]

      assert entry["@id"] == entity.id
      assert is_map(entry["entity"])
      assert entry["entity"]["@type"] == "Movie"
      assert entry["entity"]["name"] == "Blade Runner 2049"
      assert entry["progress"] == nil
    end

    test "entity with watch progress includes progress summary with string keys" do
      entity = create_entity(%{type: :movie, name: "Progress Movie"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 600.0,
        duration_seconds: 7200.0
      })

      {:ok, reply, _socket} =
        MediaManagerWeb.UserSocket
        |> socket()
        |> subscribe_and_join(MediaManagerWeb.LibraryChannel, "library")

      wire = json_roundtrip(reply)
      [entry] = wire["entities"]

      progress = entry["progress"]
      assert is_map(progress)
      assert Map.has_key?(progress, "episode_position_seconds")
      assert Map.has_key?(progress, "episode_duration_seconds")
      assert Map.has_key?(progress, "episodes_completed")
      assert Map.has_key?(progress, "episodes_total")
      assert progress["episode_position_seconds"] == 600.0
      assert progress["episode_duration_seconds"] == 7200.0
      assert progress["episodes_completed"] == 0
      assert progress["episodes_total"] == 1
      assert progress["current_episode"] == nil
    end
  end

  describe "entity pushes" do
    test "entity_added push for new entity" do
      socket = join_library()

      entity = create_entity(%{type: :movie, name: "Dune: Part Two"})

      # Send directly to the channel process to avoid PubSub side effects
      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entity_added", payload
      wire = json_roundtrip(payload)

      assert wire["@id"] == entity.id
      assert wire["entity"]["@type"] == "Movie"
      assert wire["entity"]["name"] == "Dune: Part Two"
      assert wire["progress"] == nil
    end

    test "entity_updated push for known entity" do
      entity = create_entity(%{type: :movie, name: "Original Name"})
      socket = join_library()

      # Entity is known from the join. Sending a change triggers entity_updated.
      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entity_updated", payload
      wire = json_roundtrip(payload)

      assert wire["@id"] == entity.id
      assert wire["entity"]["@type"] == "Movie"
    end

    test "entity_removed push for deleted entity" do
      entity = create_entity(%{type: :tv_series, name: "Cancelled Show"})
      socket = join_library()

      # Destroy the entity so the channel can't load it
      Ash.destroy!(entity)

      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entity_removed", payload
      wire = json_roundtrip(payload)

      assert wire == %{"@id" => entity.id}
    end
  end
end
