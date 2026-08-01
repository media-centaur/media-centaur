defmodule MediaCentaur.Acquisition.Pursuits.Events.AutoCancelled do
  @moduledoc "Recorded when Commands.AutoCancel cancels the active grab without user input."

  # `detail` is the download client's own failure message (SABnzbd's
  # `fail_message`) when the reason is a client-reported terminal
  # failure; nil for the other auto-cancel reasons.
  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "auto_cancelled",
    payload_keys: [:reason, :detail]
end
