defmodule MediaCentaurWeb.Live.SettingsLive.SystemSection do
  @moduledoc """
  Pure view helpers for the Settings > System section — formatters for
  build metadata and the "check for updates" status indicator.

  Extracted from `MediaCentaurWeb.SettingsLive` per ADR-030 (LiveView
  logic extraction). Tested with `async: true` against plain data.
  """

  alias MediaCentaur.SelfUpdate.UpdateChecker

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
  @spec built_label({:ok, MediaCentaur.Version.build_info()} | :dev_build) :: String.t()
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

  defp format_reason({:rate_limited, %DateTime{} = reset_at}),
    do: "GitHub rate limit reached. Try again after #{format_local_time(reset_at)}."

  defp format_reason({:rate_limited, _}), do: "GitHub rate limit reached. Try again in a few minutes."

  defp format_reason({:http_error, status}), do: "HTTP #{status}"
  defp format_reason(%Req.TransportError{reason: reason}), do: "network: #{reason}"
  defp format_reason(other), do: inspect(other)

  defp format_local_time(datetime) do
    # Use UTC for a stable display — browsers render server-rendered
    # labels verbatim and we don't have the user's tz here. Short form.
    Calendar.strftime(datetime, "%H:%M UTC")
  end

  @doc """
  Parses the update-check interval the user typed, clamping it up to the
  rate-limit `floor` and falling back to `default` when the input can't be
  read as an integer.
  """
  @spec normalize_interval_minutes(String.t() | nil, pos_integer(), pos_integer()) ::
          pos_integer()
  def normalize_interval_minutes(raw, floor, default) do
    case Integer.parse(to_string(raw)) do
      {minutes, _rest} -> max(floor, minutes)
      :error -> default
    end
  end

  @doc """
  Relative "last checked …" label for the update card, e.g. `"just now"`,
  `"3 minutes ago"`, `"3 hours ago"`, `"2 days ago"`, or `"Never checked"`.
  """
  @spec last_checked_label({:ok, DateTime.t()} | :none, DateTime.t()) :: String.t()
  def last_checked_label(:none, _now), do: "Never checked"

  def last_checked_label({:ok, %DateTime{} = at}, %DateTime{} = now) do
    seconds = max(0, DateTime.diff(now, at, :second))

    cond do
      seconds < 60 -> "Last checked just now"
      seconds < 3600 -> "Last checked #{pluralize(div(seconds, 60), "minute")} ago"
      seconds < 86_400 -> "Last checked #{pluralize(div(seconds, 3600), "hour")} ago"
      true -> "Last checked #{pluralize(div(seconds, 86_400), "day")} ago"
    end
  end

  defp pluralize(1, unit), do: "1 #{unit}"
  defp pluralize(n, unit), do: "#{n} #{unit}s"

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
          | :verifying
          | :extracting
          | :handing_off
          | :done
          | :done_stuck
          | :failed

  # Phase rows shown in the apply-progress modal, in the order they run.
  # `:preparing` and `:done`/`:failed` aren't rows — preparing flashes
  # past before the UI has time to render, and terminal states are
  # surfaced separately.
  @visible_phases [:downloading, :verifying, :extracting, :handing_off]

  @doc "Ordered list of phases shown as rows in the apply-progress modal."
  @spec visible_phases() :: [atom()]
  def visible_phases, do: @visible_phases

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
  def apply_phase_label(:verifying), do: "Verifying checksum"
  def apply_phase_label(:extracting), do: "Extracting files"
  def apply_phase_label(:handing_off), do: "Installing and restarting"
  def apply_phase_label(:done), do: "Update staged. Restarting the service…"
  def apply_phase_label(:done_stuck), do: "Taking longer than expected"
  def apply_phase_label(:failed), do: "Update failed"
  def apply_phase_label(nil), do: ""

  @doc """
  Given one phase row and the current overall phase (plus which phase
  was active when `:failed` was reached), classifies the row into one
  of `:pending | :active | :done | :failed` so the modal can render the
  correct icon and styling.
  """
  @spec phase_state(apply_phase(), apply_phase(), apply_phase()) ::
          :pending | :active | :done | :failed
  def phase_state(_target, nil, _failed_at), do: :pending

  def phase_state(target, :failed, failed_at) do
    cond do
      target == failed_at -> :failed
      phase_index(target) < phase_index(failed_at) -> :done
      true -> :pending
    end
  end

  def phase_state(_target, current, _failed_at) when current in [:done, :done_stuck], do: :done

  def phase_state(target, current, _failed_at) do
    target_idx = phase_index(target)
    current_idx = phase_index(current)

    cond do
      target_idx < current_idx -> :done
      target_idx == current_idx -> :active
      true -> :pending
    end
  end

  defp phase_index(:preparing), do: 0
  defp phase_index(:downloading), do: 1
  defp phase_index(:verifying), do: 2
  defp phase_index(:extracting), do: 3
  defp phase_index(:handing_off), do: 4
  defp phase_index(:done), do: 5
  defp phase_index(:done_stuck), do: 5
  defp phase_index(_), do: 0

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

  @doc """
  True when the "What's new" release notes should be rendered — only
  when an update is available, so the notes preview what the user is
  about to install.

  Every other state hides them: :up_to_date has nothing new to show,
  :idle and :checking have no release yet, {:error, _} is noise, and
  :ahead_of_release is a dev/unreleased build whose "latest" might be
  stale or regressive.
  """
  @spec show_release_notes?(update_status()) :: boolean()
  def show_release_notes?(:update_available), do: true
  def show_release_notes?(_), do: false

  @doc """
  True when the "Prefer the terminal?" recovery commands should be
  rendered. These are an alternative to the "Update now" button (the
  first command mirrors it exactly), so they only make sense when an
  update is actually available — when on the latest release there is
  nothing for them to do.
  """
  @spec show_terminal_recovery?(update_status()) :: boolean()
  def show_terminal_recovery?(:update_available), do: true
  def show_terminal_recovery?(_), do: false

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

  # --- Terminal recovery commands ----------------------------------------

  @install_root "~/.local/lib/media-centaur"
  @bootstrap_url "https://raw.githubusercontent.com/media-centaur/media-centaur/main/installer/install.sh"

  @doc """
  Returns the CLI command that runs the bundled shell installer's
  `--update` flow. This is the primary fallback when the in-app updater
  fails — the shell installer does not depend on the running BEAM and
  does the full download/verify/migrate/restart dance itself.
  """
  @spec terminal_recovery_command() :: String.t()
  def terminal_recovery_command, do: "#{@install_root}/current/bin/media-centaur-install --update"

  @doc """
  Returns the CLI command that re-runs the bundled installer even when
  it is already on the latest tag. Useful when a previous apply failed
  partway and left the install in a half-applied state — `--force`
  re-extracts and re-migrates without needing a new version tag.
  """
  @spec force_recovery_command() :: String.t()
  def force_recovery_command, do: "#{@install_root}/current/bin/media-centaur-install --update --force"

  @doc """
  Returns the `curl | sh` one-liner that bootstraps a fresh install
  over the top. Used as a last-resort recovery when even the bundled
  installer is missing or corrupt.
  """
  @spec bootstrap_install_command() :: String.t()
  def bootstrap_install_command, do: "curl -fsSL #{@bootstrap_url} | sh"

  @doc "Formats an apply error reason into a human-readable sentence."
  @spec apply_error_label(any()) :: String.t()
  def apply_error_label({:download, reason}), do: "Download failed: #{format_reason(reason)}"
  def apply_error_label({:stage, reason}), do: "Tarball rejected: #{format_reason(reason)}"
  def apply_error_label({:handoff, _}), do: "Could not hand off to the installer."
  def apply_error_label({:task_crashed, _}), do: "Update process crashed unexpectedly."
  def apply_error_label(other), do: "Update failed: #{format_reason(other)}"
end
