defmodule MediaCentaur.Acquisition.Pursuits.Events.IdentityVerified do
  @moduledoc "Recorded when post-download verification confirms the file matches the goal."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "identity_verified",
    payload_keys: [:file_path]
end
