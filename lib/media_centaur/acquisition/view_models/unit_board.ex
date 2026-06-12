defmodule MediaCentaur.Acquisition.ViewModels.UnitBoard do
  @moduledoc """
  Display contract for the per-unit drill-down of a composite pursuit
  (ADR-055) — the embryo of the media-search campaign's coverage board.

  One row per unit: what the unit wants (its label/term), where its
  thread stands (state + awaiting flag), and which release currently
  covers it. Built by `MediaCentaur.Acquisition.Pursuits.unit_board_for/1`;
  the modal renders it only for multi-unit pursuits (`wanted > 1`) —
  a single-unit pursuit's thread is already the whole modal.

  ## Season roll-up

  Big shows are a wall of rows (a 38-episode season pack = 38 rows), so
  `group_rows/1` rolls rows up into collapsible `Group`s when the board
  warrants it: two or more distinct seasons, or a single season at or
  past the grouping threshold. Headers carry the aggregate (counts +
  the shared covering release) so the *collapsed* state is the
  informative one; groups containing exceptions (awaiting decision,
  exhausted) default open. Rows without season identity (query-door
  units) collect into a trailing "Other" group. `groups` is `nil` for
  small flat boards — the component renders the plain list.
  """

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.{Group, Row}

  # A single-season board at or past this many rows still groups — one
  # collapsible "Season 1 · 38/38" line is the whole point.
  @single_season_grouping_threshold 10

  @enforce_keys [:pursuit_id, :wanted, :satisfied, :units]
  defstruct [:pursuit_id, :wanted, :satisfied, :units, :groups]

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          wanted: pos_integer(),
          satisfied: non_neg_integer(),
          units: [Row.t()],
          groups: [Group.t()] | nil
        }

  defmodule Row do
    @moduledoc """
    One unit of the board: identity (`label` — the expanded term for
    query-door units, falling back to the pursuit title), thread state,
    season identity for the roll-up, and the release its current target
    carries. `actionable?` gates the per-unit "Change target" affordance
    — only in-flight units that are not already awaiting a user decision
    can pivot.
    """

    @enforce_keys [:id, :label, :state]
    defstruct [
      :id,
      :label,
      :state,
      :season_number,
      :release_title,
      awaiting_decision?: false,
      actionable?: false
    ]

    @type state :: :active | :satisfied | :exhausted | :cancelled

    @type t :: %__MODULE__{
            id: Ecto.UUID.t(),
            label: String.t(),
            state: state(),
            season_number: integer() | nil,
            release_title: String.t() | nil,
            awaiting_decision?: boolean(),
            actionable?: boolean()
          }
  end

  defmodule Group do
    @moduledoc """
    A collapsible season bucket of the board. `key` is the stable
    toggle identity carried on the click event (`"1"`, `"2"`, …,
    `"other"`). `shared_release_title` is hoisted to the header when a
    single release covers every targeted row, so expanded rows only
    show deviations. `expanded_default?` is exception-driven: a group
    holding an awaiting-decision or exhausted unit opens by default.
    """

    @enforce_keys [:key, :label, :rows, :wanted, :satisfied]
    defstruct [
      :key,
      :label,
      :season_number,
      :rows,
      :wanted,
      :satisfied,
      :shared_release_title,
      awaiting: 0,
      exhausted: 0,
      expanded_default?: false
    ]

    @type t :: %__MODULE__{
            key: String.t(),
            label: String.t(),
            season_number: integer() | nil,
            rows: [MediaCentaur.Acquisition.ViewModels.UnitBoard.Row.t()],
            wanted: pos_integer(),
            satisfied: non_neg_integer(),
            awaiting: non_neg_integer(),
            exhausted: non_neg_integer(),
            shared_release_title: String.t() | nil,
            expanded_default?: boolean()
          }
  end

  @doc """
  Rolls rows up into season `Group`s, or returns `nil` when the board
  should stay flat (fewer than two seasons and under the grouping
  threshold). Groups sort by season ascending; seasonless rows trail
  as "Other". Pure.
  """
  @spec group_rows([Row.t()]) :: [Group.t()] | nil
  def group_rows(rows) when is_list(rows) do
    distinct_seasons =
      rows |> Enum.map(& &1.season_number) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    cond do
      distinct_seasons == [] -> nil
      length(distinct_seasons) == 1 and length(rows) < @single_season_grouping_threshold -> nil
      true -> build_groups(rows)
    end
  end

  @doc """
  The set of group keys that default open — seed value for the
  LiveView's expanded-seasons assign before the user has toggled
  anything. `nil` groups (a flat board) yield the empty set.
  """
  @spec default_expanded([Group.t()] | nil) :: MapSet.t(String.t())
  def default_expanded(nil), do: MapSet.new()

  def default_expanded(groups) when is_list(groups) do
    groups
    |> Enum.filter(& &1.expanded_default?)
    |> MapSet.new(& &1.key)
  end

  defp build_groups(rows) do
    rows
    |> Enum.group_by(& &1.season_number)
    |> Enum.sort_by(fn {season, _rows} -> {is_nil(season), season} end)
    |> Enum.map(fn {season, season_rows} ->
      %Group{
        key: if(season, do: Integer.to_string(season), else: "other"),
        label: if(season, do: "Season #{season}", else: "Other"),
        season_number: season,
        rows: season_rows,
        wanted: length(season_rows),
        satisfied: Enum.count(season_rows, &(&1.state == :satisfied)),
        awaiting: Enum.count(season_rows, & &1.awaiting_decision?),
        exhausted: Enum.count(season_rows, &(&1.state == :exhausted)),
        shared_release_title: shared_release_title(season_rows),
        expanded_default?: Enum.any?(season_rows, &(&1.awaiting_decision? or &1.state == :exhausted))
      }
    end)
  end

  # The one release covering every targeted row of the group — rows
  # without a target yet don't block the hoist; two different releases
  # do.
  defp shared_release_title(rows) do
    rows
    |> Enum.map(& &1.release_title)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [title] -> title
      _none_or_many -> nil
    end
  end
end
