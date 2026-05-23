defmodule MediaCentaur.Acquisition.Pursuits.Events.AutoCancelled do
  @moduledoc "Recorded when Commands.AutoCancel cancels the active grab without user input."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "auto_cancelled",
    payload_keys: [:reason]
end
