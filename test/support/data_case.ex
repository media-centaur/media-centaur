defmodule MediaCentaur.DataCase do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MediaCentaur.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias MediaCentaur.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MediaCentaur.DataCase
      import MediaCentaur.TestFactory
    end
  end

  setup tags do
    MediaCentaur.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.

  Also resets the global state the SQL sandbox cannot roll back — every
  `:persistent_term` cache this app owns, plus the shared singletons a
  test can perturb. See `MediaCentaur.GlobalStateSandbox`; without it a
  previous test's `Config.update/2` or `QueueMonitor` poll is still there
  when the next test reads it.
  """
  def setup_sandbox(tags) do
    MediaCentaur.GlobalStateSandbox.restore!()
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MediaCentaur.Repo, shared: not tags[:async])

    # ExUnit on_exit callbacks run LIFO — the wait-for-tasks below
    # runs BEFORE stop_owner. Both run in `ExUnit.OnExitHandler`
    # (no sandbox ownership), so they must not touch the DB — only
    # Process.monitor (the wait) and sandbox API (the stop) are
    # safe here.
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    on_exit(&drain_supervised_tasks/0)
  end

  # Terminates any `Task.Supervisor` child still running under
  # `MediaCentaur.TaskSupervisor` at teardown, so it can't hit the DB
  # after the sandbox owner is released (`DBConnection.OwnershipError`,
  # which Console.Handler then forwards into unrelated tests'
  # `refute_receive` checks — the test-isolation-hardening campaign's
  # Category B; that campaign is retired, see git history).
  #
  # Each orphan gets a short grace window to finish its (fast, sub-ms on
  # sqlite) DB work cleanly; one that overruns is blocked on something
  # slow and non-DB — e.g. an HTTP retry backoff in a fire-and-forget
  # search — and is killed rather than waited on. (Waiting the full
  # second per orphan is what once turned the suite into an effective
  # hang — the test-suite-performance campaign, likewise retired.)
  #
  # This is the permanent teardown safety net, not a temporary bridge.
  # The web layer no longer spawns fire-and-forget tasks (ADR-049 /
  # MC0019), but context-layer background work — searches, library
  # maintenance, rescans (`Acquisition.run_search_one_async/2`,
  # `Maintenance.*_async/1`, `Watcher.Supervisor.scan_async/0`, …) —
  # legitimately runs under the global supervisor and can outlive a
  # test. The drain bounds that to O(grace) per orphaned child.
  @task_drain_grace_ms 100

  defp drain_supervised_tasks do
    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      after
        @task_drain_grace_ms ->
          Process.demonitor(ref, [:flush])
          Process.exit(pid, :kill)
      end
    end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
