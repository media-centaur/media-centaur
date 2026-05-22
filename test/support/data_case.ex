defmodule MediaCentarr.DataCase do
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
  by setting `use MediaCentarr.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias MediaCentarr.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MediaCentarr.DataCase
      import MediaCentarr.TestFactory
    end
  end

  setup tags do
    MediaCentarr.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.

  Also restores the `MediaCentarr.Config` `:persistent_term` cache to
  its post-helper pristine state. Without this, a previous test's
  `Config.update/2` call leaks into the next test's view of `Config.get/1`
  — the global cache survives sandbox rollback. See
  `campaigns/test-isolation-hardening.md` (Category E).
  """
  def setup_sandbox(tags) do
    restore_config_cache()
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MediaCentarr.Repo, shared: not tags[:async])

    # ExUnit on_exit callbacks run LIFO — the wait-for-tasks below
    # runs BEFORE stop_owner. Both run in `ExUnit.OnExitHandler`
    # (no sandbox ownership), so they must not touch the DB — only
    # Process.monitor (the wait) and sandbox API (the stop) are
    # safe here.
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    on_exit(&drain_supervised_tasks/0)
  end

  defp restore_config_cache do
    snapshot = :persistent_term.get({MediaCentarr.Config, :test_pristine_snapshot})
    :persistent_term.put({MediaCentarr.Config, :config}, snapshot)
  end

  # Waits for every `Task.Supervisor` child still running under
  # `MediaCentarr.TaskSupervisor` to terminate. LiveView `start_async`
  # calls + bare `Task.Supervisor.start_child` calls (e.g.
  # `SettingsLive.start_async_settings_load`) outlive the test process
  # by default; without this drain, those tasks hit the DB after the
  # sandbox owner has terminated and raise `DBConnection.OwnershipError`,
  # which Console.Handler then forwards into unrelated tests'
  # `refute_receive` checks. See `campaigns/test-isolation-hardening.md`
  # (Category B).
  # Grace window for an orphaned task to finish its (fast, sub-ms on
  # sqlite) DB work cleanly before the sandbox owner is released. Tasks
  # that overrun the grace are blocked on something slow and non-DB —
  # e.g. an HTTP retry backoff in a fire-and-forget Prowlarr search — and
  # are killed rather than waited on. Waiting the full second per orphan
  # is what turned the suite into an effective hang. The real cure is to
  # own such async work so it can't orphan (ADR-049); until every call
  # site is converted, this keeps teardown O(grace).
  @task_drain_grace_ms 100

  defp drain_supervised_tasks do
    MediaCentarr.TaskSupervisor
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
