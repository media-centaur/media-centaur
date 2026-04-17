defmodule MediaCentarrWeb.Live.SettingsLive.SystemSection do
  @moduledoc """
  Pure view helpers for the Settings > System section — formatters for
  build metadata and the "check for updates" status indicator.

  Extracted from `MediaCentarrWeb.SettingsLive` per ADR-030 (LiveView
  logic extraction). Tested with `async: true` against plain data.
  """

  alias MediaCentarr.UpdateChecker

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
end
