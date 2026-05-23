defmodule MediaCentaur.Acquisition.Pursuits.Events.IdentityMismatch do
  @moduledoc "Recorded when post-download verification rejects a file as the wrong content."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "identity_mismatch",
    payload_keys: [:expected, :observed, :file_path]
end
