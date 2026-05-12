defmodule MediaCentarr.Acquisition.ViewModels.PursuitRow do
  @moduledoc """
  Display contract for one row in the Downloads index — one card per
  active pursuit. Carries enough to render a meaningful title (show
  name + S/E), a single severity-colored status sentence, and a stable
  navigate target.
  """

  alias MediaCentarr.Acquisition.ViewModels.CurrentAction

  @enforce_keys [:id, :title, :state, :detail_path, :status]
  defstruct [
    :id,
    :title,
    :state,
    :season_number,
    :episode_number,
    :detail_path,
    :release_title,
    :target_status,
    :status
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
          detail_path: String.t(),
          release_title: String.t() | nil,
          target_status: target_status() | nil,
          status: CurrentAction.t()
        }
end
