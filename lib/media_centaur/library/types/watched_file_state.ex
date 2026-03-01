defmodule MediaCentaur.Library.Types.WatchedFileState do
  use Ash.Type.Enum,
    values: [
      :complete,
      :absent
    ]
end
