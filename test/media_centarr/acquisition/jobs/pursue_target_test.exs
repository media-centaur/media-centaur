defmodule MediaCentarr.Acquisition.Jobs.PursueTargetTest do
  @moduledoc """
  Defensive checks on the worker that should NEVER reach Prowlarr.

  The architectural primary defense is that `Satisfy` / `Exhaust` /
  `Cancel` cancel in-flight targets at terminal-pursuit transition, so
  the worker's next wake sees a cancelled target and early-exits via the
  pre-existing target-status guard. This test asserts the second layer:
  even if a `seeking` target row somehow survives on a terminal pursuit
  (race, manual DB edit, code path that bypasses the cleanup), the worker
  must not call Prowlarr — pursuit state is the authority.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Jobs.PursueTarget
  alias MediaCentarr.Search.Prowlarr

  setup do
    # Install a stub that crashes if invoked — any Prowlarr call is a
    # bug since the worker should early-exit before reaching the network.
    Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called") end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    on_exit(fn -> :persistent_term.erase({Prowlarr, :client}) end)
    :ok
  end

  describe "perform/1 — pursuit-state guard" do
    for terminal_state <- ["satisfied", "exhausted", "cancelled"] do
      test "early-exits for #{terminal_state} pursuit even when target is seeking" do
        {_pursuit, target} =
          create_pursuit_with_target(%{state: unquote(terminal_state), status: "seeking"})

        assert {:ok, :pursuit_terminal} =
                 PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      end
    end
  end
end
