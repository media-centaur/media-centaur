defmodule MediaCentaur.DataCase do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  Composes `MediaCentaur.Case` (the global-state checkout) and adds the
  SQL sandbox: changes done to the database are reverted at the end of
  every test. SQLite serialises writers, so `DataCase` tests are
  `async: false`.
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use MediaCentaur.Case, unquote(opts)

      alias MediaCentaur.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MediaCentaur.DataCase
      import MediaCentaur.TestFactory
      import MediaCentaur.Eventually
    end
  end

  setup tags do
    MediaCentaur.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Starts the SQL sandbox owner for the test, shared unless the test is
  `async: true`. The rest of the machine — `:persistent_term`, singletons,
  supervised tasks — is `MediaCentaur.Case`'s checkout, which every
  `DataCase` composes.

  The owner is stopped in `on_exit`, which runs after `MediaCentaur.Case`'s
  check-in (callbacks are LIFO and the template's setup registers first),
  so a supervised task check-in kills never outlives the connection it may
  be using.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MediaCentaur.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
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
