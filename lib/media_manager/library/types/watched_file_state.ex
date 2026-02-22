defmodule MediaManager.Library.Types.WatchedFileState do
  use Ash.Type.Enum,
    values: [
      :detected,
      :queued,
      :searching,
      :pending_review,
      :approved,
      :fetching_metadata,
      :fetching_images,
      :complete,
      :error,
      :removed,
      :dismissed
    ]
end
