defmodule MediaCentarr.Acquisition.AutoGrabService do
  @moduledoc """
  Persistent on/off lever for auto-grab.

  The lever is stored in `Settings` under the
  `services:<env>:start_acquisition` key — the same per-env persistence
  the watcher and pipeline toggles use — so the choice survives restarts.
  Pausing also pauses the Oban `:acquisition` queue so pre-existing
  snoozed/searching grabs stop firing.

  Manual grabs and `:item_removed` cancellation always work regardless
  of this flag; it gates only `:release_ready`-triggered arming and the
  Oban-driven search/snooze loop.
  """

  alias MediaCentarr.Settings

  @doc "True when auto-grab is enabled (defaults to true on fresh installs)."
  @spec running?() :: boolean()
  def running? do
    case Settings.get_by_key(service_flag_key()) do
      {:ok, %{value: %{"enabled" => false}}} -> false
      _ -> true
    end
  end

  @doc """
  Pauses auto-grab. Persists `enabled: false` in Settings and pauses
  the Oban `:acquisition` queue. Idempotent.
  """
  @spec pause() :: :ok
  def pause do
    persist_flag(false)
    pause_queue()
    :ok
  end

  @doc """
  Resumes auto-grab. Persists `enabled: true` in Settings and resumes
  the Oban `:acquisition` queue. Idempotent.
  """
  @spec resume() :: :ok
  def resume do
    persist_flag(true)
    resume_queue()
    :ok
  end

  defp service_flag_key do
    env = Application.get_env(:media_centarr, :environment, :dev)
    "services:#{env}:start_acquisition"
  end

  defp persist_flag(enabled?) do
    Settings.find_or_create_entry!(%{
      key: service_flag_key(),
      value: %{"enabled" => enabled?}
    })
  end

  # Inline Oban testing mode doesn't run real queue processes, so
  # `Oban.pause_queue/1` raises. Skip it there — `running?/0` is the
  # source of truth for tests; production has both.
  defp pause_queue do
    if oban_queue_running?(), do: Oban.pause_queue(queue: :acquisition)
    :ok
  end

  defp resume_queue do
    if oban_queue_running?(), do: Oban.resume_queue(queue: :acquisition)
    :ok
  end

  defp oban_queue_running? do
    Application.get_env(:media_centarr, Oban)[:testing] != :inline
  end
end
