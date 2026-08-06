defmodule MediaCentaur.SelfUpdate.Health do
  @moduledoc """
  Durable health projection for the self-update subsystem — the data
  `SelfUpdate.IncidentContext.assess/0` reads to decide the **Updates** tile's
  state on the Status board.

  Two facts, persisted via `Settings.Entry` under the `update.*` namespace so
  they survive restarts (a failed apply must still show on the board after the
  BEAM bounces):

    * `update.check_failure_streak` — consecutive failed checks, reset to 0 on
      any successful check. Drives the `:check_failing` warning.
    * `update.last_apply` — the outcome of the most recent apply attempt
      (`"ok"` or `"failed"` + reason). A failure is cleared when a new apply
      *starts* (a retry supersedes the stale failure); the success path simply
      leaves it cleared, which sidesteps the write-vs-restart race at hand-off.
      Drives the `:apply_failed` error.

  Writers are the two seams that already exist: `CheckerJob` records each check
  outcome, `Updater` clears on apply start and records on apply failure.
  `assess/0` is a read-only consumer — this module performs no derivation, only
  storage.
  """

  alias MediaCentaur.Settings

  @streak_key "update.check_failure_streak"
  @apply_key "update.last_apply"

  @type snapshot :: %{
          check_failure_streak: non_neg_integer(),
          last_apply_failure: %{reason: String.t(), at: DateTime.t()} | nil
        }

  @doc "Resets the consecutive-check-failure streak (a check succeeded)."
  @spec record_check_success() :: :ok
  def record_check_success, do: put_streak(0)

  @doc "Increments the consecutive-check-failure streak (a check failed)."
  @spec record_check_failure() :: :ok
  def record_check_failure, do: put_streak(streak() + 1)

  @doc "Records that the most recent apply attempt failed, with its reason."
  @spec record_apply_failed(term()) :: :ok
  def record_apply_failed(reason) do
    put_apply(%{
      "result" => "failed",
      "reason" => inspect(reason),
      "at" => DateTime.to_iso8601(DateTime.utc_now())
    })
  end

  @doc """
  Clears any recorded apply failure. Called when a new apply starts — a retry
  supersedes the previous failure, and a clean start that goes on to succeed
  leaves the slot clear.
  """
  @spec clear_apply_failure() :: :ok
  def clear_apply_failure, do: put_apply(%{"result" => "ok"})

  @doc "Read-only snapshot consumed by `IncidentContext.assess/0` and the widget."
  @spec snapshot() :: snapshot()
  def snapshot do
    %{check_failure_streak: streak(), last_apply_failure: last_apply_failure()}
  end

  defp streak do
    case Settings.get_by_key(@streak_key) do
      %{value: %{"count" => count}} when is_integer(count) and count >= 0 -> count
      _ -> 0
    end
  end

  defp put_streak(count) do
    Settings.find_or_create_entry!(%{key: @streak_key, value: %{"count" => count}})
    :ok
  end

  defp put_apply(value) do
    Settings.find_or_create_entry!(%{key: @apply_key, value: value})
    :ok
  end

  defp last_apply_failure do
    case Settings.get_by_key(@apply_key) do
      %{value: %{"result" => "failed", "reason" => reason, "at" => at}} ->
        %{reason: reason, at: decode_at(at)}

      _ ->
        nil
    end
  end

  defp decode_at(iso), do: MediaCentaur.Iso8601.parse(iso, DateTime.utc_now())
end
