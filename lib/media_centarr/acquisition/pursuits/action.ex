defmodule MediaCentarr.Acquisition.Pursuits.Action do
  @moduledoc """
  Discriminated union returned by `Pursuits.Policy.evaluate/1`.

  The Watcher dispatches each variant to a single command:

      :no_action                       -> (skip)
      {:auto_cancel, reason}           -> Commands.AutoCancel
      {:request_decision, prompt}      -> Commands.RequestDecision
      {:satisfy, grab_id}              -> Commands.Satisfy
      {:exhaust, reason}               -> Commands.Exhaust
  """

  @type cancel_reason :: :zero_seeders | :stall_after_user_ack
  @type exhaust_reason :: :max_attempts | :no_alternatives

  @type t ::
          :no_action
          | {:auto_cancel, cancel_reason()}
          | {:request_decision, prompt :: String.t()}
          | {:satisfy, grab_id :: Ecto.UUID.t()}
          | {:exhaust, exhaust_reason()}
end
