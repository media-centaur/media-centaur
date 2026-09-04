defmodule MediaCentaur.Retention do
  use Boundary, deps: [], exports: [Policy, PolicyProvider, PolicyStatus, SweepJob]

  @moduledoc """
  Public API for the Retention bounded context — the single place data
  retention is declared, executed, and observed.

  ## Shape

  Every context that retains prunable data declares its policies in a
  `MediaCentaur.Retention.PolicyProvider` module registered under the
  `:retention_policy_providers` config key. `sweep/0` (driven daily by
  `MediaCentaur.Retention.SweepJob`) runs each `:sweep`-mode policy and
  records what it removed; pruners that run on their own cadence
  (`:external` mode) report their counts via `record_run/2`. The Status
  page reads `status_by_subsystem/0` so both the policy ("what is kept,
  for how long") and the observed pruning behavior ("last swept, N
  removed") are visible per subsystem.

  Policies that intentionally keep data forever are declared with
  `:forever` mode — permanence is a decision worth surfacing, not an
  accident of missing code.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.Retention.{Policy, PolicyStatus, Run}

  @doc "All declared policies, in provider registration order."
  @spec policies() :: [Policy.t()]
  def policies do
    :media_centaur
    |> Application.fetch_env!(:retention_policy_providers)
    |> Enum.flat_map(& &1.policies())
  end

  @doc """
  Runs every `:sweep`-mode policy, recording each policy's removal count.

  A raising policy is isolated — later policies still run — and reported
  in the `{:error, failures}` return so the caller (the Oban sweep job)
  can retry. Retries are safe: prune runs are idempotent and re-running
  an already-swept policy removes nothing new.
  """
  @spec sweep() :: :ok | {:error, [{atom(), Exception.t()}]}
  def sweep do
    failures =
      for %Policy{mode: :sweep} = policy <- policies(), reduce: [] do
        failures ->
          case run_policy(policy) do
            :ok -> failures
            {:error, exception} -> [{policy.key, exception} | failures]
          end
      end

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  defp run_policy(%Policy{key: key, run: run}) do
    pruned = run.()
    record_run(key, pruned)

    if pruned > 0 do
      Log.info(:library, "swept #{key}: removed #{pruned}")
    end

    :ok
  rescue
    exception ->
      Log.error(:library, "sweep of #{key} failed: #{Exception.message(exception)}")
      {:error, exception}
  end

  @doc """
  Records one pruning run for `policy_key`: stamps `last_ran_at`,
  replaces `pruned_last_run`, and accumulates `pruned_total`. Called by
  the sweep for `:sweep` policies and by external pruners (corpus tick,
  absence sweeper) on their own cadence.

  Never raises: external pruners call this from boot paths (the absence
  sweeper's initial TTL check runs in `handle_continue`), and a stats
  write must not crash-loop a supervisor when the write fails — e.g. a
  dev boot before this table's migration has run. Failures are logged
  loudly instead; the run row is garnish, not correctness.
  """
  @spec record_run(atom(), non_neg_integer()) :: :ok
  def record_run(policy_key, pruned_count)
      when is_atom(policy_key) and is_integer(pruned_count) and pruned_count >= 0 do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      %Run{
        policy_key: to_string(policy_key),
        last_ran_at: now,
        pruned_last_run: pruned_count,
        pruned_total: pruned_count
      },
      on_conflict: [
        set: [last_ran_at: now, pruned_last_run: pruned_count],
        inc: [pruned_total: pruned_count]
      ],
      conflict_target: :policy_key
    )

    :ok
  rescue
    exception ->
      Log.error(
        :library,
        "failed to record run for #{policy_key}: #{Exception.message(exception)}"
      )

      :ok
  end

  @doc "The recorded run stats for one policy, or `nil` if it never ran."
  @spec get_run(atom()) :: Run.t() | nil
  def get_run(policy_key), do: Repo.get(Run, to_string(policy_key))

  @doc """
  Policies merged with their recorded run stats, grouped by Status-page
  subsystem key. Policy order within a subsystem follows provider
  registration order.
  """
  @spec status_by_subsystem() :: %{atom() => [PolicyStatus.t()]}
  def status_by_subsystem do
    runs = Map.new(Repo.all(Run), &{&1.policy_key, &1})

    policies()
    |> Enum.map(fn policy ->
      run = Map.get(runs, to_string(policy.key))

      %PolicyStatus{
        key: policy.key,
        subsystem: policy.subsystem,
        label: policy.label,
        description: policy.description,
        mode: policy.mode,
        last_ran_at: run && run.last_ran_at,
        pruned_last_run: (run && run.pruned_last_run) || 0,
        pruned_total: (run && run.pruned_total) || 0
      }
    end)
    |> Enum.group_by(& &1.subsystem)
  end
end
