defmodule MediaCentarrWeb.Live.SettingsLive.SystemSection do
  @moduledoc """
  Pure view helpers for the Settings > System section — formatters for
  build metadata and the "check for updates" status indicator.

  Extracted from `MediaCentarrWeb.SettingsLive` per ADR-030 (LiveView
  logic extraction). Tested with `async: true` against plain data.
  """

  alias MediaCentarr.SelfUpdate.UpdateChecker

  @type update_status ::
          :idle
          | :checking
          | :up_to_date
          | :update_available
          | :ahead_of_release
          | {:error, any()}

  @type tone :: :neutral | :success | :info | :warning | :error

  @doc """
  Formats the "Built" row value.

  For a real build returns something like `"2026-04-17 (abc1234)"`.
  For a dev environment returns `"dev build"`.
  """
  @spec built_label({:ok, MediaCentarr.Version.build_info()} | :dev_build) :: String.t()
  def built_label(:dev_build), do: "dev build"

  def built_label({:ok, %{built_at: datetime, git_sha: git_sha}}) do
    "#{Calendar.strftime(datetime, "%Y-%m-%d")} (#{short_sha(git_sha)})"
  end

  defp short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)

  @doc "Human-readable label for an `update_status/0` value."
  @spec update_status_label(update_status(), UpdateChecker.release() | nil) :: String.t()
  def update_status_label(:idle, _release), do: "Check for updates to see what's new."

  def update_status_label(:checking, _release), do: "Checking GitHub releases…"

  def update_status_label(:up_to_date, _release), do: "You're on the latest release."

  def update_status_label(:update_available, %{tag: tag, published_at: published_at}) do
    "Update available: #{tag} (released #{Calendar.strftime(published_at, "%Y-%m-%d")})"
  end

  def update_status_label(:ahead_of_release, %{tag: tag}) do
    "You're ahead of the latest release (#{tag}) — dev build?"
  end

  def update_status_label({:error, reason}, _release) do
    "Update check error: #{format_reason(reason)}"
  end

  defp format_reason(:not_found), do: "no releases published"
  defp format_reason(:malformed), do: "unexpected response from GitHub"
  defp format_reason({:http_error, status}), do: "HTTP #{status}"
  defp format_reason(%Req.TransportError{reason: reason}), do: "network: #{reason}"
  defp format_reason(other), do: inspect(other)

  @doc "Maps an `update_status/0` to a semantic tone for styling."
  @spec update_status_tone(update_status()) :: tone()
  def update_status_tone(:idle), do: :neutral
  def update_status_tone(:checking), do: :neutral
  def update_status_tone(:up_to_date), do: :success
  def update_status_tone(:update_available), do: :info
  def update_status_tone(:ahead_of_release), do: :warning
  def update_status_tone({:error, _}), do: :error

  # --- Apply (Update now) state helpers -----------------------------------

  @type apply_phase ::
          nil
          | :preparing
          | :downloading
          | :extracting
          | :handing_off
          | :done
          | :failed

  @doc """
  Returns `true` when the progress modal should be visible — an apply
  is in flight or has just completed/failed.
  """
  @spec apply_visible?(apply_phase()) :: boolean()
  def apply_visible?(nil), do: false
  def apply_visible?(_), do: true

  @doc "Human-readable label for the current apply phase."
  @spec apply_phase_label(apply_phase()) :: String.t()
  def apply_phase_label(:preparing), do: "Preparing…"
  def apply_phase_label(:downloading), do: "Downloading release"
  def apply_phase_label(:extracting), do: "Extracting"
  def apply_phase_label(:handing_off), do: "Installing and restarting…"
  def apply_phase_label(:done), do: "Update staged. Restarting the service…"
  def apply_phase_label(:failed), do: "Update failed"
  def apply_phase_label(nil), do: ""

  @doc """
  Returns `true` when the apply phase is one the user is still allowed to
  cancel. After handoff the detached shell has been spawned, so cancel
  is gone.
  """
  @spec apply_cancelable?(apply_phase()) :: boolean()
  def apply_cancelable?(phase) when phase in [:preparing, :downloading, :extracting], do: true
  def apply_cancelable?(_), do: false

  @doc """
  Formats a progress percentage for display, or returns an empty string
  when the progress is unknown.
  """
  @spec apply_progress_text(integer() | nil) :: String.t()
  def apply_progress_text(nil), do: ""
  def apply_progress_text(pct) when is_integer(pct), do: "#{pct}%"

  # --- First-run prompts --------------------------------------------------

  @doc """
  True when the TMDB API key is missing or empty. The Settings > Overview
  callout uses this to show a one-click prompt that navigates the user to
  External Services, where they can paste in a key.
  """
  @spec tmdb_key_missing?(any()) :: boolean()
  def tmdb_key_missing?(nil), do: true
  def tmdb_key_missing?(""), do: true
  def tmdb_key_missing?(%{value: value}) when is_binary(value), do: tmdb_key_missing?(value)
  def tmdb_key_missing?(value) when is_binary(value), do: String.trim(value) == ""
  def tmdb_key_missing?(_), do: true

  @doc "Formats an apply error reason into a human-readable sentence."
  @spec apply_error_label(any()) :: String.t()
  def apply_error_label({:download, reason}), do: "Download failed: #{format_reason(reason)}"
  def apply_error_label({:stage, reason}), do: "Tarball rejected: #{format_reason(reason)}"
  def apply_error_label({:handoff, _}), do: "Could not hand off to the installer."
  def apply_error_label({:task_crashed, _}), do: "Update process crashed unexpectedly."
  def apply_error_label(other), do: "Update failed: #{format_reason(other)}"
end
