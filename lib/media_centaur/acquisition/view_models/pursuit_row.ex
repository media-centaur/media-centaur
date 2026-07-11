defmodule MediaCentaur.Acquisition.ViewModels.PursuitRow do
  @moduledoc """
  Display contract for one row in the Incoming page's in-flight zone — one card per
  active pursuit. Carries enough to render a meaningful title (show
  name + S/E) and a single severity-colored status sentence. Clicking
  the row opens the pursuit detail modal on `/incoming?selected=<id>`.
  """

  alias MediaCentaur.Acquisition.ViewModels.CurrentAction

  @enforce_keys [:id, :title, :state, :status]
  defstruct [
    :id,
    :title,
    :state,
    # When the pursuit last changed — for a terminal row this is when it
    # reached its outcome, which the Recently landed ledger renders as
    # relative time ("2 h ago").
    :updated_at,
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
    units_satisfied: 0,
    # Every in-flight target's pairing identity — one {torrent_hash,
    # release_title} per DISTINCT current target across the units, lead
    # first. A composite pursuit grabs several releases at once; the
    # queue matcher claims a torrent when ANY key matches (ADR-055).
    pairing_keys: [],
    # Which acquisition door created this pursuit (UIDR-014): :media
    # (TMDB-doored — earns the identity-banner treatment) or :query
    # (naked release search — stays a plain row).
    door: :query,
    # Ordered unit states ("satisfied"/"active"/…) for the segmented
    # progress row on composite media-door cards. Empty for singles.
    unit_states: []
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
          units_satisfied: non_neg_integer(),
          pairing_keys: [{String.t() | nil, String.t() | nil}],
          door: :media | :query,
          unit_states: [String.t()]
        }
end
