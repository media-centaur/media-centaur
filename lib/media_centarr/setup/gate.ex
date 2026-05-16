defmodule MediaCentarr.Setup.Gate do
  @moduledoc """
  Pure advance-gate for the Setup Tour wizard.

  The tour walks the user through configuring optional and required
  integrations. Pure-state probes (`Probes`) answer "is this saved?" —
  the gate combines that with `IntegrationHealth` ("does it work?") to
  answer "may the user advance past this step?".

  Critical-and-testable steps (`:tmdb`) require BOTH `probe.status =
  :ok` AND `health.test_state = :ok` before advancement. Non-critical
  steps (Prowlarr, download client) only need probe `:ok` to advance,
  but the gate still surfaces the test state to the UI so a misconfig
  is obvious.

  Pseudo-steps `:welcome` and `:summary` always pass.
  """

  alias MediaCentarr.IntegrationHealth.Status

  @testable_steps [:tmdb, :prowlarr, :download_client]

  # The set of steps whose `Probe.Result.critical?` value combined with
  # the testable flag means a successful network test is REQUIRED for
  # advancement. Today that's just :tmdb — if a future step is critical
  # AND has a network test, add it here (or derive from probe + ID set).
  @gating_test_steps [:tmdb]

  @type step_id :: atom()
  @type probe :: %{:status => atom(), optional(atom()) => term()} | nil
  @type reason ::
          :probe_not_ok
          | :test_pending
          | :test_failed
          | :test_not_run

  @doc """
  Decide whether the user may advance past `step`.

  Returns `:ok` to allow advance, or `{:blocked, reason}` with a stable
  atom suitable for tooltip / flash text via `reason_message/1`.

  `probe` is a `Probes.Probe.Result` or `nil` for steps without one.
  `health` is the integration's `%IntegrationHealth.Status{}` or `nil`
  when the step has no health concept.
  """
  @spec check(step_id(), probe(), Status.t() | nil) :: :ok | {:blocked, reason()}
  def check(:welcome, _probe, _health), do: :ok
  def check(:summary, _probe, _health), do: :ok

  def check(step, probe, health) when step in @gating_test_steps do
    with :ok <- probe_check(probe) do
      health_check(step, health)
    end
  end

  def check(step, probe, _health) when step in @testable_steps do
    probe_check(probe)
  end

  def check(_step, probe, _health), do: probe_check(probe)

  @doc "Convenience boolean wrapper around `check/3`."
  @spec blocked?(step_id(), probe(), Status.t() | nil) :: boolean()
  def blocked?(step, probe, health), do: check(step, probe, health) != :ok

  @doc "Stable human-readable tooltip text for a `{:blocked, reason}` result."
  @spec reason_message(reason()) :: String.t()
  def reason_message(:probe_not_ok), do: "Complete this step before continuing."
  def reason_message(:test_pending), do: "Verifying the connection — hold on…"
  def reason_message(:test_failed), do: "Connection test failed. Fix the credentials and try again."

  def reason_message(:test_not_run),
    do: "Save the credentials so the connection can be verified before continuing."

  def reason_message(_), do: "Complete this step before continuing."

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp probe_check(nil), do: {:blocked, :probe_not_ok}
  defp probe_check(%{status: :ok}), do: :ok
  defp probe_check(_), do: {:blocked, :probe_not_ok}

  defp health_check(step, nil), do: missing_test_reason(step)
  defp health_check(_, %Status{test_state: :ok}), do: :ok
  defp health_check(_, %Status{test_state: :pending}), do: {:blocked, :test_pending}
  defp health_check(_, %Status{test_state: :error}), do: {:blocked, :test_failed}
  defp health_check(step, %Status{test_state: :unknown}), do: missing_test_reason(step)

  defp missing_test_reason(_step), do: {:blocked, :test_not_run}
end
