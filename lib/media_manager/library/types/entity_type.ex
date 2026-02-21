defmodule MediaManager.Library.Types.EntityType do
  use Ash.Type.Enum, values: [:movie, :movie_series, :tv_series, :video_object]
end
