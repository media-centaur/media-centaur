defmodule MediaManager.Library.WatchProgress.Changes.ComputeCompleted do
  @moduledoc """
  Sets `completed` to `true` when playback position reaches 90% of duration.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    position = Ash.Changeset.get_attribute(changeset, :position_seconds)
    duration = Ash.Changeset.get_attribute(changeset, :duration_seconds)

    completed =
      if is_number(position) and is_number(duration) and duration > 0 do
        position / duration >= 0.90
      else
        false
      end

    Ash.Changeset.change_attribute(changeset, :completed, completed)
  end
end
