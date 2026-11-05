defmodule MediaCentaur.Acquisition.Pursuits.Action do
  @moduledoc """
  Discriminated union returned by `Pursuits.Policy.evaluate/1`.

  The Watcher dispatches each variant to a single command:

      :no_action                       -> (skip)
      {:auto_cancel, reason, next}     -> Commands.AutoCancel
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

  @type cancel_reason :: :zero_seeders | :download_failed
  @type exhaust_reason :: :max_attempts

  @typedoc """
  What follows the dead release's cancellation: `:pivot` searches for the
  next release; `:give_up` exhausts the unit, because this failure spent
  its last attempt.
  """
  @type next :: :pivot | :give_up

  @type t ::
          :no_action
          | {:auto_cancel, cancel_reason(), next()}
          | {:request_decision, prompt :: String.t()}
          | {:exhaust, exhaust_reason()}
end
