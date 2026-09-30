defmodule MediaCentaur.Acquisition.Pursuits.Commands.Runner do
  @moduledoc """
  Shared transaction-and-event skeleton for pursuit commands.

  Every `Commands.*` module wraps the same shape: load a pursuit by id,
  run a Repo transaction containing one or more state transitions and
  one or more event records, log on success, return `{:error, :not_found}`
  when the pursuit doesn't exist. This module is the single place that
  shape lives.

  ## Usage

      Runner.run(pursuit_id, log_label, fn pursuit ->
        with {:ok, updated} <- Repo.update(Pursuit.satisfy_changeset(pursuit)),
             {:ok, _event} <- Events.record(%PursuitSatisfied{...}) do
          {:ok, updated}
        end
      end)

  The work function receives the loaded pursuit and runs inside a Repo
  transaction. Returning `{:ok, value}` commits and returns `{:ok, value}`
  — the work's own value, a pursuit or a tuple led by one; returning
  `{:error, term}` rolls back and surfaces the error to the caller. The runner logs the
  command outcome under the `:acquisition` component using `log_label`
  (which is interpolated as `"<label> — <pursuit.title>"`).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Repo

  @type work_result :: {:ok, term()} | {:error, term()}
  @type log_label :: String.t() | (Pursuit.t() -> String.t())

  @doc """
  Loads the pursuit, runs `work_fn` inside a transaction, and logs on success.

  - `:not_found` short-circuits without entering the transaction.
  - The transaction commits when `work_fn` returns `{:ok, _}` and rolls
    back when it returns `{:error, _}`.
  - The success log line is built from `log_label` — a string is used
    verbatim, a 1-arity function is called with the (post-transaction)
    pursuit so callers can include dynamic context (e.g., a chosen
    alternative label).
  """
  @spec run(Ecto.UUID.t(), log_label(), (Pursuit.t() -> work_result())) ::
          {:ok, term()} | {:error, :not_found | term()}
  def run(pursuit_id, log_label, work_fn) when is_binary(pursuit_id) and is_function(work_fn, 1) do
    case Repo.get(Pursuit, pursuit_id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        result =
          Repo.transaction(fn ->
            case work_fn.(pursuit) do
              {:ok, value} -> value
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        log_outcome(result, log_label)
        result
    end
  end

  defp log_outcome({:ok, value}, label) do
    case pursuit_of(value) do
      %Pursuit{} = pursuit when is_binary(label) -> Log.info(:acquisition, "#{label} — #{pursuit.title}")
      %Pursuit{} = pursuit -> Log.info(:acquisition, label.(pursuit))
      nil -> :ok
    end
  end

  defp log_outcome(_error, _label), do: :ok

  # A command returns its pursuit, or a tuple led by it (ChangeTarget,
  # AutoCancel carry the new target and abandoned hashes alongside).
  defp pursuit_of(%Pursuit{} = pursuit), do: pursuit
  defp pursuit_of(tuple) when is_tuple(tuple) and is_struct(elem(tuple, 0), Pursuit), do: elem(tuple, 0)
  defp pursuit_of(_value), do: nil
end
