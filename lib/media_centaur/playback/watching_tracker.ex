defmodule MediaCentaur.Playback.WatchingTracker do
  @moduledoc """
  Pure function module that tracks whether the user is actively watching vs just
  seeking through a video. Used by MpvSession to gate DB persistence — only
  positions from continuous playback are saved, preventing seek-around from
  corrupting saved progress.

  ## Logic

  On each `time-pos` update from MPV:

  1. **Seek detection:** If `|new_position - previous_position| > 3.0 seconds`,
     a seek occurred. Reset the continuous timer and stop advancing the saveable
     position.

  2. **Continuous playback:** If not a seek, start or continue the continuous
     timer. Once uninterrupted playback reaches 20 seconds, set
     `actively_watching` to true and begin updating `saveable_position`.

  3. **First update** (`previous_position` is nil): Initialize — not a seek.
  """

  @seek_threshold_seconds 3.0
  @continuous_threshold_ms 20_000

  defstruct previous_position: nil,
            continuous_since: nil,
            actively_watching: false,
            saveable_position: nil

  @doc """
  Returns a new tracker with default state.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Process a new position update from MPV. Returns the updated tracker.

  `position` is the current `time-pos` in seconds (float).
  `now_ms` is the current monotonic time in milliseconds.
  """
  def update(%__MODULE__{previous_position: nil} = tracker, position, now_ms) do
    %{tracker | previous_position: position, continuous_since: now_ms}
  end

  def update(%__MODULE__{} = tracker, position, now_ms) do
    delta = abs(position - tracker.previous_position)

    if delta > @seek_threshold_seconds do
      handle_seek(tracker, position)
    else
      handle_continuous(tracker, position, now_ms)
    end
  end

  defp handle_seek(tracker, position) do
    %{tracker | previous_position: position, continuous_since: nil, actively_watching: false}
  end

  defp handle_continuous(tracker, position, now_ms) do
    continuous_since = tracker.continuous_since || now_ms

    elapsed = now_ms - continuous_since
    actively_watching = elapsed >= @continuous_threshold_ms

    saveable_position =
      if actively_watching do
        position
      else
        tracker.saveable_position
      end

    %{
      tracker
      | previous_position: position,
        continuous_since: continuous_since,
        actively_watching: actively_watching,
        saveable_position: saveable_position
    }
  end
end
