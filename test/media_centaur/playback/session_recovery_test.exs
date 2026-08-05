defmodule MediaCentaur.Playback.SessionRecoveryTest do
  @moduledoc """
  Boot-path tests for `MediaCentaur.Playback.SessionRecovery` (ADR-023).

  `recover_all/0` runs from `Playback.Supervisor.init/1` on every start, so
  a regression here is a startup crash or silently-dropped sessions. The
  cases below drive it through the public function against a real socket
  directory, with a stub mpv IPC server standing in for a live player —
  no `:sys.get_state`, no private-function calls.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Playback.SessionRecovery

  # The shipped default (`config.ex`), restored at the head of each setup.
  @default_socket_dir "/tmp"

  setup do
    socket_dir = Path.join(System.tmp_dir!(), "mc-recovery-#{System.unique_integer([:positive])}")
    File.mkdir_p!(socket_dir)

    # `Config.update/2` writes a Settings row, so it must run in the test
    # process where the sandbox connection is owned — never from `on_exit`,
    # which runs under `ExUnit.OnExitHandler` (Credo MC0020). The config is
    # therefore reset at the *start* of setup rather than after the test;
    # `on_exit` is left with filesystem cleanup only.
    MediaCentaur.Config.update(:mpv_socket_dir, @default_socket_dir)
    MediaCentaur.Config.update(:mpv_socket_dir, socket_dir)

    on_exit(fn -> File.rm_rf(socket_dir) end)

    {:ok, socket_dir: socket_dir}
  end

  defp socket_path(dir, entity_id), do: Path.join(dir, "media-centaur-#{entity_id}.sock")

  # A dead socket: the file exists but nothing is listening, which is what a
  # crashed mpv leaves behind.
  defp touch_dead_socket(dir, entity_id) do
    path = socket_path(dir, entity_id)
    File.write!(path, "")
    path
  end

  # Minimal mpv JSON-IPC stand-in. Answers `get_property` for the properties
  # `recover_all/0` asks for and nothing else.
  defp start_stub_mpv(path, properties) do
    parent = self()

    task =
      Task.async(fn ->
        {:ok, listen} =
          :gen_tcp.listen(0, [
            :binary,
            ifaddr: {:local, to_charlist(path)},
            packet: :line,
            active: false,
            reuseaddr: true
          ])

        send(parent, :stub_listening)
        {:ok, socket} = :gen_tcp.accept(listen, 2_000)
        serve(socket, properties)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
      end)

    assert_receive :stub_listening, 2_000
    task
  end

  defp serve(socket, properties) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, line} ->
        %{"command" => ["get_property", name]} = Jason.decode!(String.trim(line))

        reply =
          case Map.fetch(properties, name) do
            {:ok, value} -> %{"data" => value, "error" => "success"}
            :error -> %{"data" => nil, "error" => "property unavailable"}
          end

        :gen_tcp.send(socket, Jason.encode!(reply) <> "\n")
        serve(socket, properties)

      {:error, _closed} ->
        :ok
    end
  end

  describe "recover_all/0" do
    test "returns no sessions when the socket directory is empty" do
      assert SessionRecovery.recover_all() == []
    end

    test "reaps a socket file with no mpv behind it", %{socket_dir: dir} do
      path = touch_dead_socket(dir, Ecto.UUID.generate())
      assert File.exists?(path)

      assert SessionRecovery.recover_all() == []

      # Leaving the file would make every subsequent boot re-probe a socket
      # that can never answer.
      refute File.exists?(path)
    end

    test "recovers a live session and resolves it to the library entity", %{socket_dir: dir} do
      movie = create_standalone_movie(%{name: "Recovered Movie"})
      file = create_linked_file(%{movie_id: movie.id})

      path = socket_path(dir, movie.id)
      task = start_stub_mpv(path, %{"path" => file.file_path, "time-pos" => 42.5})

      assert [params] = SessionRecovery.recover_all()

      assert params.entity_id == movie.id
      assert params.entity_name == "Recovered Movie"
      assert params.content_url == file.file_path
      assert params.start_position == 42.5

      Task.shutdown(task, :brutal_kill)
    end

    test "recovers a live session playing a file the library doesn't know", %{socket_dir: dir} do
      entity_id = Ecto.UUID.generate()
      unknown_path = "/media/not-in-library/Sample.Movie.2020.1080p.mkv"

      path = socket_path(dir, entity_id)
      task = start_stub_mpv(path, %{"path" => unknown_path, "time-pos" => 7.0})

      # mpv is genuinely playing something; dropping the session because we
      # can't name it would strand a running player with no UI attached.
      assert [params] = SessionRecovery.recover_all()

      assert params.entity_id == entity_id
      assert params.content_url == unknown_path
      assert params.start_position == 7.0
      refute Map.has_key?(params, :entity_name)

      Task.shutdown(task, :brutal_kill)
    end

    test "skips a session whose mpv cannot report a path", %{socket_dir: dir} do
      entity_id = Ecto.UUID.generate()
      path = socket_path(dir, entity_id)
      task = start_stub_mpv(path, %{"time-pos" => 3.0})

      assert SessionRecovery.recover_all() == []

      Task.shutdown(task, :brutal_kill)
    end
  end
end
