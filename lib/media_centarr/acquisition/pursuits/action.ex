defmodule MediaCentarr.Acquisition.Pursuits.Action do
  @moduledoc """
  Discriminated union returned by `Pursuits.Policy.evaluate/1`.

  The Watcher dispatches each variant to a single command:

      :no_action                       -> (skip)
      {:auto_cancel, reason}           -> Commands.AutoCancel
      {:request_decision, prompt}      -> Commands.RequestDecision
      {:exhaust, reason}               -> Commands.Exhaust

  ## Variant ↔ Policy ↔ Watcher contract

  Adding a new action variant is a three-step change:

    1. Extend the type below.
    2. Have `Pursuits.Policy.evaluate/1` produce it.
    3. Add a matching `Pursuits.Watcher.dispatch/2` clause.

  Skipping step 3 means the Watcher would crash on the new variant; the
  type definition is the only place that names every clause the
  dispatcher must handle.
  """

  @type cancel_reason :: :zero_seeders
  @type exhaust_reason :: :max_attempts

  @type t ::
          :no_action
          | {:auto_cancel, cancel_reason()}
          | {:request_decision, prompt :: String.t()}
          | {:exhaust, exhaust_reason()}
end
