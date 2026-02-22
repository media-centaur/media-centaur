defmodule MediaManagerWeb.LibraryChannelTest do
  use MediaManagerWeb.ChannelCase

  alias MediaManager.Library.{Entity, WatchProgress}

  defp json_roundtrip(payload), do: payload |> Jason.encode!() |> Jason.decode!()

  defp join_library do
    {:ok, _, socket} =
      MediaManagerWeb.UserSocket
      |> socket()
      |> subscribe_and_join(MediaManagerWeb.LibraryChannel, "library")

    socket
  end

  defp create_movie(name) do
    {:ok, entity} =
      Entity
      |> Ash.Changeset.for_create(:create_from_tmdb, %{type: :movie, name: name})
      |> Ash.create()

    entity
  end

  defp create_tv_series(name) do
    {:ok, entity} =
      Entity
      |> Ash.Changeset.for_create(:create_from_tmdb, %{type: :tv_series, name: name})
      |> Ash.create()

    entity
  end

  defp create_progress(entity_id, attrs) do
    {:ok, progress} =
      WatchProgress
      |> Ash.Changeset.for_create(
        :upsert_progress,
        Map.merge(%{entity_id: entity_id}, attrs)
      )
      |> Ash.create()

    progress
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
      entity = create_movie("Blade Runner 2049")

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
      entity = create_movie("Progress Movie")

      create_progress(entity.id, %{
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

      entity = create_movie("Dune: Part Two")

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
      entity = create_movie("Original Name")
      socket = join_library()

      # Entity is known from the join. Sending a change triggers entity_updated.
      send(socket.channel_pid, {:entities_changed, [entity.id]})

      assert_push "library:entity_updated", payload
      wire = json_roundtrip(payload)

      assert wire["@id"] == entity.id
      assert wire["entity"]["@type"] == "Movie"
    end

    test "entity_removed push for deleted entity" do
      entity = create_tv_series("Cancelled Show")
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
