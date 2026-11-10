defmodule MediaCentaur.Library.SupervisorTest do
  # async: false — crashes a child of the application's own Library
  # supervisor until that supervisor gives up.
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.Eventually

  alias MediaCentaur.Library

  @moduletag :capture_log

  test "a subsystem that exhausts its restarts is restarted alone; the application and the web layer stay up" do
    endpoint = Process.whereis(MediaCentaurWeb.Endpoint)
    application = Process.whereis(MediaCentaur.Supervisor)
    library = Process.whereis(Library.Supervisor)

    # More crashes than Library.Supervisor's budget allows in its window.
    # The exit signal is asynchronous, so each round waits for a pid that is
    # not the one it killed.
    Enum.reduce(1..7, Process.whereis(Library.AbsenceSweeper), fn _round, pid ->
      Process.exit(pid, :kill)

      eventually(
        fn ->
          case Process.whereis(Library.AbsenceSweeper) do
            replacement when is_pid(replacement) and replacement != pid -> replacement
            _still -> nil
          end
        end,
        timeout: 5_000
      )
    end)

    assert eventually(fn -> Process.whereis(Library.Supervisor) not in [nil, library] end,
             timeout: 5_000
           )

    assert Process.alive?(application)
    assert Process.whereis(MediaCentaur.Supervisor) == application
    assert Process.whereis(MediaCentaurWeb.Endpoint) == endpoint
    assert eventually(fn -> Process.whereis(Library.AbsenceSweeper) != nil end, timeout: 5_000)
  end
end
