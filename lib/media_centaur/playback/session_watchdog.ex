defmodule MediaCentaur.Playback.SessionWatchdog do
  @moduledoc """
  Keeps every playing mpv under a session. An mpv outlives its session by
  design (ADR-023: the host's across restarts, a device's on its own), and
  `Sessions.recover/1` reattaches a session to such an mpv when the host
  boots and when a device's channel connects. A session that crashes leaves
  the same thing behind — an mpv playing with no session to save progress
  or, on a device, to draw its controls — so the watchdog recovers it then
  too.

  Every session registers itself in its own `init/1` (`watch/3`), before
  anything in that init can fail. When one exits:

    * normally or by shutdown — a stop, an end of file, a removed player —
      nothing happens;
    * by a crash — the player's orphaned mpvs are recovered
      (`Sessions.recover/1`);
    * by a crash on a player that crashed within the last
      `#{div(60_000, 1000)}` s — a session that keeps crashing — the
      player's orphaned mpvs are stopped (`Sessions.abandon/1`) instead,
      so a crash loop ends with nothing playing rather than recovering
      forever.

  Recovery reads the player over IPC and stopping talks to it, so both run
  in a supervised task, off this process. Started only where background
  work runs (`Playback.Supervisor`), as boot recovery is.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.Sessions

  @crash_window_ms 60_000

  @doc """
  Options (each defaults to the production one): `name`, `task_supervisor`,
  `crash_window_ms`, and the `recover` and `abandon` functions of a player.
  """
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Watches `session`, a session on `player`; a no-op where the watchdog does not run (an instance without background services)."
  @spec watch(GenServer.server(), pid(), Playback.player()) :: :ok
  def watch(server \\ __MODULE__, session, player) do
    GenServer.call(server, {:watch, session, player})
  catch
    :exit, {:noproc, _call} -> :ok
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       task_supervisor: Keyword.get(opts, :task_supervisor, MediaCentaur.TaskSupervisor),
       crash_window_ms: Keyword.get(opts, :crash_window_ms, @crash_window_ms),
       recover: Keyword.get(opts, :recover, &Sessions.recover/1),
       abandon: Keyword.get(opts, :abandon, &Sessions.abandon/1),
       watched: %{},
       crashed_at: %{}
     }}
  end

  @impl true
  def handle_call({:watch, session, player}, _from, state) do
    ref = Process.monitor(session)
    {:reply, :ok, put_in(state.watched[ref], player)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {player, watched} = Map.pop(state.watched, ref)
    state = %{state | watched: watched}

    if player && crash?(reason),
      do: {:noreply, after_crash(state, player, reason)},
      else: {:noreply, state}
  end

  defp after_crash(state, player, reason) do
    now = System.monotonic_time(:millisecond)

    repeated? =
      now - Map.get(state.crashed_at, player, now - state.crash_window_ms) < state.crash_window_ms

    if repeated? do
      Log.warning(
        :playback,
        "session on #{describe(player)} crashed again — stopping its mpv (#{inspect(reason)})"
      )

      run(state, fn -> state.abandon.(player) end)
    else
      Log.warning(
        :playback,
        "session on #{describe(player)} crashed — recovering its mpv (#{inspect(reason)})"
      )

      run(state, fn -> state.recover.(player) end)
    end

    put_in(state.crashed_at[player], now)
  end

  defp run(state, fun), do: {:ok, _pid} = Task.Supervisor.start_child(state.task_supervisor, fun)

  # A session that was told to end, or ended on its own, is not a crash;
  # `:noproc` is a session that was gone before it could be watched, whose
  # reason is unknown.
  defp crash?(reason) when reason in [:normal, :shutdown, :noproc], do: false
  defp crash?({:shutdown, _}), do: false
  defp crash?(_reason), do: true

  defp describe(:host), do: "the host"
  defp describe(player), do: "player #{Format.short_id(player)}"
end
