defmodule MediaCentarr.IntegrationHealth.Status do
  @moduledoc """
  Per-integration health snapshot owned by `MediaCentarr.IntegrationHealth`.

  Each external integration (TMDB, Prowlarr, download client) has two
  orthogonal axes:

    * `configured?` — does the user's `Config` carry the required keys?
      Pure read of `Config`; no network involved.
    * `test_state` — does the integration actually respond when probed?
      Updated by `IntegrationHealth.verify/1`, which runs the
      integration's `Verifier` callback on a `Task.Supervisor`. Network
      lives here, never in `configured?`.

  Setup-gate logic (`MediaCentarr.Setup.Gate`) combines the two: a
  critical step like TMDB requires both `configured? = true` AND
  `test_state = :ok` before the wizard advances. A saved-but-rejected
  key is the failure mode this struct exists to surface.

  `test_state` transitions: `:unknown → :pending → (:ok | :error)`, and
  back to `:pending` whenever the underlying config key changes.
  """

  @type id :: :tmdb | :prowlarr | :download_client
  @type test_state :: :unknown | :pending | :ok | :error

  @enforce_keys [:id, :configured?, :test_state]
  defstruct [:id, :configured?, :test_state, :test_error, :last_tested_at]

  @type t :: %__MODULE__{
          id: id(),
          configured?: boolean(),
          test_state: test_state(),
          test_error: term() | nil,
          last_tested_at: DateTime.t() | nil
        }
end
