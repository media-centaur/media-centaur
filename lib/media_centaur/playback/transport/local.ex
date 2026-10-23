defmodule MediaCentaur.Playback.Transport.Local do
  @moduledoc """
  The host player's transport: an mpv process the host spawns, reached over
  its entity-scoped Unix domain socket in the configured socket dir, its
  file a host path.

  `open/2` tries the socket first and reattaches to a live mpv there
  (`{:attached, :reconnected}`, ADR-023) before spawning a fresh one from
  `LaunchFlags.argv/1` under `Platform.DisplayEnv`. The socket's bytes are
  stitched into IPC lines by `IpcFraming` and decoded here; the port's exit
  status and merged stderr feed `MpvExitClassifier` once both exit signals
  have had a moment to arrive, which becomes the `{:closed, _}` event.

  `close/2` with `final?` false leaves the socket file for recovery on the
  next boot: the mpv is still the viewer's. See `docs/playback.md` for the
  lifetime rules the systemd unit must honour (`KillMode=process`).
  """

  @behaviour MediaCentaur.Playback.Transport

  # This module defines the behaviour's `send/2`; the Erlang send is spelled out.
  import Kernel, except: [send: 2]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Platform.DisplayEnv
  alias MediaCentaur.Playback.{IpcFraming, LaunchFlags, MpvExitClassifier, MpvLogReader, MpvUserConfig}
  alias MediaCentaur.Settings.Config

  @socket_retry_interval_ms 200
  # Brief window after the first exit signal (tcp_closed OR exit_status) to let
  # the other signal and any final stderr chunks arrive before classifying.
  @exit_debounce_ms 200

  defstruct [
    :entity_id,
    :session_id,
    :socket_path,
    :log_file_path,
    :launch,
    :port,
    :socket,
    :socket_retries,
    :exit_status,
    output_tail: [],
    seen_property_event?: false,
    exiting?: false,
    ipc_buffer: ""
  ]

  @type t :: %__MODULE__{}

  @doc "A transport for the host player, for one entity's viewing chain."
  @spec new(String.t()) :: t()
  def new(entity_id) do
    session_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    socket_dir = Config.get(:mpv_socket_dir)

    %__MODULE__{
      entity_id: entity_id,
      session_id: session_id,
      socket_path: Path.join(socket_dir, "media-centaur-#{entity_id}.sock"),
      log_file_path: Path.join(socket_dir, "media-centaur-#{session_id}.log"),
      socket_retries: max_retries()
    }
  end

  @impl true
  def open(transport, launch) do
    Kernel.send(self(), {:transport, :try_reconnect})
    {[], %{transport | launch: launch}}
  end

  @impl true
  def send(%{socket: nil}, _command), do: :ok

  def send(%{socket: socket}, command) do
    :gen_tcp.send(socket, Jason.encode!(%{"command" => command}) <> "\n")
    :ok
  end

  @impl true
  def attached?(%{socket: socket, exiting?: exiting?}), do: socket != nil and not exiting?

  @impl true
  def locator(_transport, content_url), do: {:ok, content_url}

  @impl true
  def identify(_transport, reported_path), do: reported_path

  @impl true
  # The process carries the session options; only the entry's own start
  # rides on it (per entry, so an unwatched successor never inherits the
  # first episode's offset — ADR-062). mpv ≥ 0.38's five-argument form.
  def queue(_transport, locator, start) when start > 0,
    do: ["loadfile", locator, "append", -1, "start=#{start}"]

  def queue(_transport, locator, _start), do: ["loadfile", locator, "append"]

  @impl true
  def draws_subtitles?(_transport), do: true

  @impl true
  def holds_one_viewing?(_transport), do: false

  @impl true
  def describe(transport), do: "mpv on this computer (#{Path.basename(transport.socket_path)})"

  @impl true
  def close(transport, final?) do
    if transport.socket, do: :gen_tcp.close(transport.socket)

    # The socket file stays while mpv may still be running (a backend
    # shutdown mid-viewing), so recovery can reconnect on the next boot.
    if final? do
      File.rm(transport.socket_path)
      File.rm(transport.log_file_path)
    end

    :ok
  end

  # --- Messages delivered to the session process ---

  @impl true
  def handle_message(transport, {:transport, :try_reconnect}) do
    case connect(transport.socket_path, 500) do
      {:ok, socket} ->
        Log.info(
          :playback,
          "session #{transport.session_id} reconnected to existing mpv via #{Path.basename(transport.socket_path)}"
        )

        {[{:attached, :reconnected}], %{transport | socket: socket}}

      {:error, _reason} ->
        Log.info(:playback, "reconnect failed, cleaning stale socket, launching fresh")
        File.rm(transport.socket_path)
        Kernel.send(self(), {:transport, :launch})
        {[], transport}
    end
  end

  def handle_message(transport, {:transport, :launch}) do
    case DisplayEnv.resolve() do
      {:ok, env_pairs} ->
        {[], spawn_mpv(transport, env_pairs)}

      {:error, :no_display} ->
        Log.error(
          :playback,
          "no display server reachable — refusing to launch mpv (service likely started before the graphical session)"
        )

        message = "Media Centaur can't reach your desktop. Restart it after signing in."
        {[{:closed, {:error, :no_display, message}}], transport}
    end
  end

  def handle_message(transport, {:transport, :connect_socket}) do
    case connect(transport.socket_path, :infinity) do
      {:ok, socket} ->
        Log.info(:playback, "connected to IPC socket")

        if transport.launch.start_position > 0 do
          Log.info(:playback, "resuming at #{Format.format_seconds(transport.launch.start_position)}")
        end

        {[{:attached, :fresh}], %{transport | socket: socket}}

      {:error, _reason} when transport.socket_retries > 0 ->
        if transport.socket_retries == max_retries() do
          Log.info(:playback, "waiting for IPC socket (#{max_retries()} retries)")
        end

        Process.send_after(self(), {:transport, :connect_socket}, @socket_retry_interval_ms)
        {[], %{transport | socket_retries: transport.socket_retries - 1}}

      {:error, _reason} ->
        Log.error(:playback, "socket connect timed out")
        message = "mpv started but never opened its control socket."
        {[{:closed, {:error, :startup_failure, message}}], transport}
    end
  end

  # The socket is `packet: :raw`: a chunk may hold several IPC lines or only
  # part of one (`track-list` regularly exceeds the read buffer).
  def handle_message(transport, {:tcp, _socket, data}) do
    {lines, buffer} = IpcFraming.feed(transport.ipc_buffer, data)
    objects = lines |> Enum.map(&decode_line/1) |> Enum.reject(&is_nil/1)

    seen? =
      transport.seen_property_event? or Enum.any?(objects, &match?(%{"event" => "property-change"}, &1))

    {Enum.map(objects, &{:message, &1}), %{transport | ipc_buffer: buffer, seen_property_event?: seen?}}
  end

  def handle_message(transport, {:tcp_closed, _socket}) do
    Log.info(:playback, "socket closed")
    schedule_exit_classification(%{transport | socket: nil})
  end

  def handle_message(%{port: port} = transport, {port, {:exit_status, status}}) do
    Log.info(:playback, "mpv exited — status #{status}")
    schedule_exit_classification(%{transport | exit_status: status})
  end

  # mpv's stdout+stderr, merged. Kept as a bounded tail for classification
  # and logged live so a failure is diagnosable from the Console.
  def handle_message(%{port: port} = transport, {port, {:data, data}}) do
    log_mpv_lines(data)
    {[], %{transport | output_tail: MpvExitClassifier.append_output(transport.output_tail, data)}}
  end

  def handle_message(transport, {:transport, :classify}) do
    classification =
      MpvExitClassifier.classify(%{
        seen_property_event?: transport.seen_property_event?,
        exit_status: transport.exit_status,
        output_tail: MpvLogReader.fallback_tail(transport.output_tail, transport.log_file_path, 5)
      })

    case classification do
      {:ok, :ended} ->
        {[{:closed, {:ok, :ended}}], transport}

      {:error, :startup_failure, message} ->
        Log.error(:playback, "mpv startup failure — #{message}")
        {[{:closed, {:error, :startup_failure, message}}], transport}
    end
  end

  def handle_message(_transport, _message), do: :unhandled

  # --- mpv launch ---

  defp spawn_mpv(transport, env_pairs) do
    launch = transport.launch
    Log.info(:playback, "launching mpv — #{Path.basename(launch.content_url)}")

    warn_about_stale_script_copies()

    argv =
      LaunchFlags.argv(%{
        socket_path: transport.socket_path,
        log_file_path: transport.log_file_path,
        bundled_scripts_dir: LaunchFlags.bundled_scripts_dir(),
        session_options: launch.session_options,
        content_url: launch.content_url,
        start_position: launch.start_position
      })

    port =
      Port.open({:spawn_executable, to_charlist(Config.get(:mpv_path))}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:env, env_pairs},
        args: argv
      ])

    Process.send_after(self(), {:transport, :connect_socket}, @socket_retry_interval_ms)
    %{transport | port: port}
  end

  # Old single-file copies of the now-bundled scripts in the user config
  # double every overlay. Named here so Status → Playback shows them; the
  # app never deletes anything in the user's mpv config.
  defp warn_about_stale_script_copies do
    case MpvUserConfig.stale_bundled_copies() do
      [] ->
        :ok

      paths ->
        names = Enum.map_join(paths, ", ", &Path.basename/1)

        Log.warning(
          :playback,
          "old copies of the built-in mpv scripts in #{Path.dirname(hd(paths))}: #{names}. " <>
            "Delete them, or Skip Intro and Next Episode appear twice."
        )
    end
  end

  defp connect(socket_path, timeout) do
    :gen_tcp.connect(
      {:local, to_charlist(socket_path)},
      0,
      [:binary, packet: :raw, active: true],
      timeout
    )
  end

  defp max_retries, do: div(Config.get(:mpv_socket_timeout_ms), @socket_retry_interval_ms)

  defp schedule_exit_classification(%{exiting?: true} = transport), do: {[], transport}

  defp schedule_exit_classification(transport) do
    Process.send_after(self(), {:transport, :classify}, @exit_debounce_ms)
    {[], %{transport | exiting?: true}}
  end

  defp decode_line(line) do
    case String.trim(line) do
      "" ->
        nil

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, object} ->
            object

          {:error, error} ->
            Log.warning(:playback, "IPC JSON decode failed — #{inspect(error)}")
            nil
        end
    end
  end

  defp log_mpv_lines(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      trimmed = String.trim(line)
      if trimmed != "", do: Log.info(:playback, "mpv: #{trimmed}")
    end)
  end
end
