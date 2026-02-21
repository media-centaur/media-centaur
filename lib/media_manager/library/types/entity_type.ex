defmodule MediaManager.Library.Types.EntityType do
  use Ash.Type.Enum, values: [:movie, :tv_series, :video_object]
end
