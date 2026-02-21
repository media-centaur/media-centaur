defmodule MediaManager.Library.Types.MediaType do
  use Ash.Type.Enum, values: [:movie, :tv, :unknown]
end
