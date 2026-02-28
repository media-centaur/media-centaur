defmodule MediaCentaur.Library.Types.MediaType do
  use Ash.Type.Enum, values: [:movie, :tv, :extra, :unknown]
end
