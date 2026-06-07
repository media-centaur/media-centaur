defmodule MediaCentaur.SelfUpdate.IncidentContext do
  @moduledoc """
  Self-update's contribution to diagnostics — the `assess/0` health probe the
  `ErrorReports.Evaluator` polls to drive the **Updates** tile on the Status
  board.

  Three fault conditions, in descending priority (the evaluator wants the single
  current condition):

    * `:apply_failed` (**error**) — the most recent update apply attempt failed.
      The dangerous case: an update tried to install and couldn't.
    * `:check_failing` (**warning**) — update checks have failed three or more
      times in a row (GitHub unreachable / API errors). A single transient
      failure does not fault.
    * `:checks_stalled` (**warning**) — background checks are enabled but no
      successful check has landed in at least three times the configured
      interval, i.e. the scheduler looks wedged.

  An *available update is never a fault* — that is normal, expected state.

  The decision is the pure `decide/4`; `assess/0` is the thin shell that gathers
  the durable `Health` snapshot, the last-check timestamp, and the relevant
  config, then defers to it. Registered via `config :media_centaur,
  :diagnostics_contributors`, so `ErrorReports` reaches it through the runtime
  registry — which binds assessors by `function_exported?(module, :assess, 0)`,
  purely by name.

  This module fulfils the `ErrorReports.IncidentContext` `assess/0` contract
  **structurally rather than via `@behaviour`**: declaring the behaviour would
  add a compile-time `SelfUpdate → ErrorReports` edge, closing a Boundary cycle
  (`SelfUpdate → ErrorReports → Console → SelfUpdate`, since `Console` already
  depends on `SelfUpdate` for unit detection). The registry's name-based binding
  is exactly the seam that lets a subsystem report health without that edge.
  """

  alias MediaCentaur.Config
  alias MediaCentaur.SelfUpdate
  alias MediaCentaur.SelfUpdate.Health

  @check_failing_threshold 3
  @stalled_interval_multiplier 3

  @doc "Health probe polled by the diagnostics evaluator. Side-effect-free."
  @spec assess() :: :ok | {:fault, atom(), :warning | :error, map()}
  def assess do
    decide(
      Health.snapshot(),
      SelfUpdate.last_check_at(),
      DateTime.utc_now(),
      %{
        enabled: Config.get(:update_check_enabled) == true,
        interval_minutes: Config.update_check_interval_minutes()
      }
    )
  end

  @doc """
  Cross-subsystem vitals — a cheap, side-effect-free snapshot of update state,
  folded into every frozen incident report so a failure elsewhere can be
  correlated with "was an update applying / failing at the time?".
  """
  @spec vitals() :: map()
  def vitals do
    {classification, release} = SelfUpdate.last_known_status()
    %{check_failure_streak: streak, last_apply_failure: apply_failure} = Health.snapshot()

    %{
      "version" => MediaCentaur.Version.current_version(),
      "classification" => classification_label(classification),
      "latest_tag" => release && release.tag,
      "last_check_at" => last_check_iso(SelfUpdate.last_check_at()),
      "check_failure_streak" => streak,
      "apply_failed" => apply_failure != nil,
      "check_enabled" => Config.get(:update_check_enabled) == true,
      "auto_update_enabled" => Config.get(:auto_update_enabled) == true
    }
  end

  defp classification_label({:error, _reason}), do: "error"
  defp classification_label(classification), do: to_string(classification)

  defp last_check_iso(:none), do: nil
  defp last_check_iso({:ok, %DateTime{} = at}), do: DateTime.to_iso8601(at)

  @doc """
  Pure fault decision. Returns the single dominant fault or `:ok`.

    * `snapshot` — `Health.snapshot/0` (streak + last apply failure).
    * `last_check_at` — `{:ok, DateTime.t()}` or `:none`.
    * `now` — current time.
    * `config` — `%{enabled: boolean(), interval_minutes: pos_integer()}`.
  """
  @spec decide(
          Health.snapshot(),
          {:ok, DateTime.t()} | :none,
          DateTime.t(),
          %{enabled: boolean(), interval_minutes: pos_integer()}
        ) :: :ok | {:fault, atom(), :warning | :error, map()}
  def decide(snapshot, last_check_at, now, config) do
    cond do
      apply_failed?(snapshot) -> {:fault, :apply_failed, :error, %{}}
      check_failing?(snapshot) -> {:fault, :check_failing, :warning, %{}}
      checks_stalled?(last_check_at, now, config) -> {:fault, :checks_stalled, :warning, %{}}
      true -> :ok
    end
  end

  defp apply_failed?(%{last_apply_failure: nil}), do: false
  defp apply_failed?(%{last_apply_failure: _failure}), do: true

  defp check_failing?(%{check_failure_streak: streak}), do: streak >= @check_failing_threshold

  defp checks_stalled?(:none, _now, _config), do: false
  defp checks_stalled?(_last, _now, %{enabled: false}), do: false

  defp checks_stalled?({:ok, %DateTime{} = last}, now, %{interval_minutes: interval}) do
    DateTime.diff(now, last, :minute) >= @stalled_interval_multiplier * interval
  end
end
