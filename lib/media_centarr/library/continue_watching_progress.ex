defmodule MediaCentarr.Library.ContinueWatchingProgress do
  @moduledoc """
  Pure helpers that turn a watch-progress summary into the 0-100 integer
  shown on the Continue Watching row's progress bar.

  The bar is the user's "where am I overall in this thing?" cue.
  Completed-episode count alone is too coarse for single-item entities
  (movies show 0 % until they finish, then drop out of Continue
  Watching anyway — the bar is never useful). Position alone is too
  coarse for long-running series (50 % through episode 6 of 24 should
  not read as 50 % overall). This module blends the two.

  Public for unit-testing — the contract is small and surprising
  enough to be worth crystallising.
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  @typedoc """
  Minimum shape required by `compute_pct/1` and the maximum shape this
  module reads from. Extra keys are ignored.
  """
  @type summary :: %{
          required(:episodes_completed) => non_neg_integer(),
          required(:episodes_total) => non_neg_integer(),
          optional(:episode_position_seconds) => number(),
          optional(:episode_duration_seconds) => number()
        }

  @doc """
  Returns a 0-100 integer for the Continue Watching progress bar.

  ## Formula

      (episodes_completed + current_episode_fraction) / episodes_total * 100

  where `current_episode_fraction` is `position / duration` of the
  active record, capped at 1.0. Result is `trunc/1`-ed (no rounding —
  the bar reads "you're past N %", not "you're at the closest N %").

  ## Edge cases

  - `nil` summary → `0`
  - `episodes_total == 0` → `0`
  - `episodes_completed >= episodes_total` → `100` (defends against
    the formula double-crediting completed entities that still carry
    a stale position record — `(1 + 1.0) / 1 * 100` would otherwise
    return `200`)
  - `episode_duration_seconds` missing or zero → contributes `0` to
    the fraction (no current-position info available)
  - `episode_position_seconds > episode_duration_seconds` (over-rolled
    progress, possible if duration was revised down) → caps at `1.0`
  """
  @spec compute_pct(summary() | nil) :: 0..100
  def compute_pct(nil), do: 0
  def compute_pct(%{episodes_total: 0}), do: 0

  def compute_pct(%{episodes_total: total, episodes_completed: completed}) when completed >= total,
    do: 100

  def compute_pct(%{episodes_total: total, episodes_completed: completed} = summary) do
    position = Map.get(summary, :episode_position_seconds, 0.0)
    duration = Map.get(summary, :episode_duration_seconds, 0.0)

    current_fraction =
      if duration > 0, do: min(1.0, position / duration), else: 0.0

    trunc((completed + current_fraction) / total * 100)
  end

  @doc """
  Picks the most recent in-progress record's position from a list and
  returns `%{episode_position_seconds, episode_duration_seconds}` ready
  to merge into a summary map.

  For movies / video-objects the list has at most one record; for TV /
  movie-series it's the episode the user is currently mid-way through.

  Records with `completed: true` are skipped — they are no longer the
  "current" item.

  Returns zeros when no in-progress record exists.
  """
  @spec current_position_summary([map()]) :: %{
          episode_position_seconds: float(),
          episode_duration_seconds: float()
        }
  def current_position_summary(progress_records) when is_list(progress_records) do
    record =
      progress_records
      |> Enum.reject(& &1.completed)
      |> Enum.max_by(& &1.last_watched_at, DateTime, fn -> nil end)

    case record do
      nil ->
        %{episode_position_seconds: 0.0, episode_duration_seconds: 0.0}

      record ->
        %{
          episode_position_seconds: record.position_seconds || 0.0,
          episode_duration_seconds: record.duration_seconds || 0.0
        }
    end
  end
end
