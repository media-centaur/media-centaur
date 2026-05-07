defmodule MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled do
  @moduledoc "Recorded when Commands.AutoCancel cancels the active grab without user input."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "auto_cancelled",
    payload_keys: [:reason]
end
