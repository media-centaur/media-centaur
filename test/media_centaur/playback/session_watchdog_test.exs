defmodule MediaCentaur.Playback.SessionWatchdogTest do
  @moduledoc """
  The watchdog acts on how a watched session ends: a crash is recovered on
  its player, a second crash on the same player within the window stops
  that player's mpv instead, and a session that ends normally is left
  alone. Recovery and stopping are injected, so each shows up here as a
  message.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.SessionWatchdog

  # Each injected call arrives through a supervised task the watchdog starts;
  # with the async suite saturating the schedulers that can take longer than
  # `assert_receive`'s default 100 ms. A positive assert returns as soon as
  # the message lands, so the deadline costs nothing when it passes.
  @deadline 1_000

  setup do
    test = self()
    tasks = start_supervised!({Task.Supervisor, name: nil}, id: :watchdog_tasks)

    start = fn crash_window_ms ->
      start_supervised!(
        {SessionWatchdog,
         name: nil,
         task_supervisor: tasks,
         crash_window_ms: crash_window_ms,
         recover: fn player -> send(test, {:recovered, player}) end,
         abandon: fn player -> send(test, {:abandoned, player}) end},
        id: {:watchdog, crash_window_ms}
      )
    end

    %{start: start}
  end

  defp session do
    spawn(fn ->
      receive do
        {:exit, reason} -> exit(reason)
      end
    end)
  end

  defp watched_session(watchdog, player) do
    pid = session()
    :ok = SessionWatchdog.watch(watchdog, pid, player)
    pid
  end

  test "a session that crashes is recovered on its player", %{start: start} do
    watchdog = start.(60_000)
    send(watched_session(watchdog, "player-a"), {:exit, :boom})

    assert_receive {:recovered, "player-a"}, @deadline
    refute_receive {:abandoned, _}, 50
  end

  test "a session that ends normally or is shut down is left alone", %{start: start} do
    watchdog = start.(60_000)

    for reason <- [:normal, :shutdown, {:shutdown, :removed}] do
      send(watched_session(watchdog, "player-a"), {:exit, reason})
    end

    refute_receive {:recovered, _}, 100
    refute_receive {:abandoned, _}, 0
  end

  test "a second crash on the same player within the window stops its mpv instead", %{start: start} do
    watchdog = start.(60_000)

    send(watched_session(watchdog, "player-a"), {:exit, :boom})
    assert_receive {:recovered, "player-a"}, @deadline

    send(watched_session(watchdog, "player-a"), {:exit, :boom})
    assert_receive {:abandoned, "player-a"}, @deadline
    refute_receive {:recovered, _}, 50
  end

  test "crashes on different players are each recovered", %{start: start} do
    watchdog = start.(60_000)

    send(watched_session(watchdog, "player-a"), {:exit, :boom})
    send(watched_session(watchdog, "player-b"), {:exit, :boom})

    assert_receive {:recovered, "player-a"}, @deadline
    assert_receive {:recovered, "player-b"}, @deadline
  end

  test "a crash after the window has passed is recovered again", %{start: start} do
    watchdog = start.(0)

    send(watched_session(watchdog, "player-a"), {:exit, :boom})
    assert_receive {:recovered, "player-a"}, @deadline

    send(watched_session(watchdog, "player-a"), {:exit, :boom})
    assert_receive {:recovered, "player-a"}, @deadline
  end
end
