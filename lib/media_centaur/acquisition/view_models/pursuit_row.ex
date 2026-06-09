defmodule MediaCentaur.Acquisition.ViewModels.PursuitRow do
  @moduledoc """
  Display contract for one row in the Downloads index — one card per
  active pursuit. Carries enough to render a meaningful title (show
  name + S/E) and a single severity-colored status sentence. Clicking
  the row opens the pursuit detail modal on `/download?selected=<id>`.
  """

  alias MediaCentaur.Acquisition.ViewModels.CurrentAction

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
    # pairing — see `MediaCentaur.Acquisition.QueueMatcher.match/2`.
    # Nil for rows without a release title.
    :normalized_release_title,
    # qBittorrent infohash captured on the pursuit's target, when known.
    # When present, `QueueMatcher.match/2` pairs by this exact key instead
    # of the title — immune to tracker-prefixed torrent names. Nil falls
    # back to (prefix-tolerant) title matching.
    :torrent_hash,
    awaiting_decision?: false,
    # Composite progress (ADR-055): progress is always units satisfied /
    # units wanted, never a count of targets. Single-unit pursuits carry
    # 1/0-or-1 and render no progress chip.
    units_wanted: 1,
    units_satisfied: 0
  ]

  @type state ::
          :active
          | :satisfied
          | :partial
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
          normalized_release_title: String.t() | nil,
          torrent_hash: String.t() | nil,
          awaiting_decision?: boolean(),
          units_wanted: pos_integer(),
          units_satisfied: non_neg_integer()
        }
end
