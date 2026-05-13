defmodule MediaCentarr.Acquisition.ViewModels.PursuitRow do
  @moduledoc """
  Display contract for one row in the Downloads index — one card per
  active pursuit. Carries enough to render a meaningful title (show
  name + S/E) and a single severity-colored status sentence. Clicking
  the row opens the pursuit detail modal on `/download?selected=<id>`.
  """

  alias MediaCentarr.Acquisition.ViewModels.CurrentAction

  @enforce_keys [:id, :title, :state, :status]
  defstruct [
    :id,
    :title,
    :state,
    :season_number,
    :episode_number,
    :release_title,
    :target_status,
    :status,
    # Memoised normalisation of `release_title` for render-hot queue
    # pairing — see `MediaCentarr.Acquisition.QueueMatcher.match/2`.
    # Nil for rows without a release title.
    :normalized_release_title
  ]

  @type state ::
          :active
          | :needs_decision
          | :satisfied
          | :exhausted
          | :cancelled

  @type target_status ::
          :seeking | :acquired | :succeeded | :failed | :cancelled

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: state(),
          season_number: integer() | nil,
          episode_number: integer() | nil,
          release_title: String.t() | nil,
          target_status: target_status() | nil,
          status: CurrentAction.t(),
          normalized_release_title: String.t() | nil
        }
end
