defmodule MediaCentaur.Acquisition.ViewModels.PlanBoard do
  @moduledoc """
  Display contract for the planning coverage board (UIDR-014) — the
  live view of a draft plan: unit cells in season rows, the chosen
  releases beneath, the gaps, and the approval summary. Built by
  `MediaCentaur.Acquisition.Plans.board_for/1`; re-built on every
  `PlanEvents.Changed` (the durable plan rows are the state of record).
  """

  defmodule Cell do
    @moduledoc "One unit cell of the grid — an episode and where its coverage stands."

    @enforce_keys [:plan_unit_id, :season_number, :episode_number, :label, :state]
    defstruct [
      :plan_unit_id,
      :season_number,
      :episode_number,
      :label,
      :state,
      :release_guid,
      :release_title
    ]

    @type state :: :searching | :assigned | :unfound | :excluded

    @type t :: %__MODULE__{
            plan_unit_id: Ecto.UUID.t(),
            season_number: pos_integer() | nil,
            episode_number: pos_integer() | nil,
            label: String.t(),
            state: state(),
            release_guid: String.t() | nil,
            release_title: String.t() | nil
          }
  end

  defmodule SeasonRow do
    @moduledoc "One grid row: a season and its cells in episode order."

    @enforce_keys [:season_number, :cells]
    defstruct [:season_number, :cells]

    @type t :: %__MODULE__{season_number: pos_integer() | nil, cells: [Cell.t()]}
  end

  defmodule Release do
    @moduledoc "One chosen release: the evidence row beneath the grid."

    @enforce_keys [:guid, :title, :units_count, :swap_unit_id]
    defstruct [:guid, :title, :scope_label, :quality, :seeders, :units_count, :swap_unit_id]

    @type t :: %__MODULE__{
            guid: String.t(),
            title: String.t(),
            scope_label: String.t() | nil,
            quality: String.t() | nil,
            seeders: integer() | nil,
            units_count: pos_integer(),
            # Any covered plan-unit id — exclusions are plan-wide, so one
            # representative carries the swap/exclude verb.
            swap_unit_id: Ecto.UUID.t()
          }
  end

  defmodule Alternative do
    @moduledoc """
    One choosable candidate in the swap picker — corpus-known, identity-
    verified, covering the unit. `suspicious?` marks bait-pattern titles
    (`Search.ReleaseRedFlags`): never auto-picked, but visible and
    deliberately choosable — the heuristic demotes, it doesn't hide.
    """

    @enforce_keys [:guid, :title]
    defstruct [:guid, :title, :scope_label, :quality, :seeders, suspicious?: false]

    @type t :: %__MODULE__{
            guid: String.t(),
            title: String.t(),
            scope_label: String.t() | nil,
            quality: String.t() | nil,
            seeders: integer() | nil,
            suspicious?: boolean()
          }
  end

  @enforce_keys [:plan_id, :title, :status, :wanted, :covered, :seasons, :releases, :gaps]
  defstruct [
    :plan_id,
    :title,
    :status,
    :error,
    :wanted,
    :covered,
    :seasons,
    :releases,
    :gaps,
    movie?: false
  ]

  @type status :: :planning | :ready | :committed | :discarded

  @type t :: %__MODULE__{
          plan_id: Ecto.UUID.t(),
          title: String.t(),
          status: status(),
          error: String.t() | nil,
          wanted: non_neg_integer(),
          covered: non_neg_integer(),
          seasons: [SeasonRow.t()],
          releases: [Release.t()],
          gaps: [String.t()],
          movie?: boolean()
        }
end
