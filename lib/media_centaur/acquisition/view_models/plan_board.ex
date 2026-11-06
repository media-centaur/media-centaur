defmodule MediaCentaur.Acquisition.ViewModels.PlanBoard do
  @moduledoc """
  Display contract for the plan board (UIDR-014; UIDR-029 as amended
  2026-11-06) — the live view of a draft plan as a **manifest**: one
  list of `Line`s, each a release with the episode cells it covers, or a
  group of cells sharing one outcome (searching, lower quality only, not
  found, a pack offer, dropped by you). Every episode is drawn once,
  inside the line that explains its outcome; the board's summaries —
  the releases, the gap labels, the below-preference total, a movie's
  gap unit — are functions of the lines, never fields beside them.

  Built by `MediaCentaur.Acquisition.Plans.Board.assemble/2` (pure, from
  the plan's units) through `Board.build/1`; re-built on every
  `PlanEvents.Changed` (the durable plan rows are the state of record).
  """

  alias MediaCentaur.Search.ReleaseCoverage

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  defmodule Cell do
    @moduledoc "One unit cell — an episode and where its coverage stands."

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

    @type state :: :searching | :assigned | :below_preference | :unfound | :excluded

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
    @moduledoc "A line's cells for one season, in episode order."

    @enforce_keys [:season_number, :cells]
    defstruct [:season_number, :cells]

    @type t :: %__MODULE__{season_number: pos_integer() | nil, cells: [Cell.t()]}
  end

  defmodule Release do
    @moduledoc """
    One chosen release — a release line's facts. `overlap` is set when
    the release physically contains an episode assigned to another
    release (a swap-picker choice; the planner never does this): the
    duplicate-data warning is drawn on the line it concerns.
    """

    @enforce_keys [:guid, :title, :units_count, :swap_unit_id]
    defstruct [
      :guid,
      :title,
      :scope_label,
      :quality,
      :seeders,
      :size_bytes,
      :units_count,
      :swap_unit_id,
      :overlap
    ]

    @type t :: %__MODULE__{
            guid: String.t(),
            title: String.t(),
            scope_label: String.t() | nil,
            quality: String.t() | nil,
            seeders: integer() | nil,
            size_bytes: integer() | nil,
            units_count: pos_integer(),
            # Any covered plan-unit id — exclusions are plan-wide, so one
            # representative carries the swap/exclude verb.
            swap_unit_id: Ecto.UUID.t(),
            overlap: MediaCentaur.Acquisition.ViewModels.PlanBoard.Overlap.t() | nil
          }
  end

  defmodule Line do
    @moduledoc """
    One line of the manifest. A `:release` line carries the release's
    facts and the cells it covers; an outcome line carries the cells
    sharing that outcome and the facts its decision needs — the
    `BelowPreference` total on `:below_preference`, the pack on
    `:offer`. `rows` are the line's cells by season, in episode order.
    `id` is stable per line and safe in a DOM id.
    """

    @enforce_keys [:id, :kind, :rows]
    defstruct [:id, :kind, :rows, :release, :below, :offer]

    @type kind :: :release | :searching | :below_preference | :not_found | :offer | :excluded

    @type t :: %__MODULE__{
            id: String.t(),
            kind: kind(),
            rows: [MediaCentaur.Acquisition.ViewModels.PlanBoard.SeasonRow.t()],
            release: MediaCentaur.Acquisition.ViewModels.PlanBoard.Release.t() | nil,
            below: MediaCentaur.Acquisition.ViewModels.PlanBoard.BelowPreference.t() | nil,
            offer: MediaCentaur.Acquisition.ViewModels.PlanBoard.Offer.t() | nil
          }

    @doc "The line's cells across its rows, in season and episode order."
    @spec cells(t()) :: [MediaCentaur.Acquisition.ViewModels.PlanBoard.Cell.t()]
    def cells(%__MODULE__{rows: rows}), do: Enum.flat_map(rows, & &1.cells)
  end

  defmodule Alternative do
    @moduledoc """
    One choosable candidate in the swap picker — corpus-known, identity-
    verified, covering the unit. `suspicious?` marks bait-pattern titles
    (`Search.ReleaseRedFlags`): never auto-picked, but visible and
    deliberately choosable — the heuristic demotes, it doesn't hide.

    `reason` is set only on the gap banner's rejected list (UIDR-022):
    the muted line saying which gate the run's search failed this
    candidate on. Nil in the swap picker.
    """

    @enforce_keys [:guid, :title]
    defstruct [:guid, :title, :scope_label, :quality, :seeders, :size_bytes, :reason, suspicious?: false]

    @type t :: %__MODULE__{
            guid: String.t(),
            title: String.t(),
            scope_label: String.t() | nil,
            quality: String.t() | nil,
            seeders: integer() | nil,
            size_bytes: integer() | nil,
            reason: String.t() | nil,
            suspicious?: boolean()
          }
  end

  defmodule Offer do
    @moduledoc """
    A fit-gated over-grab the user can opt into: an unfound unit whose
    only coverage is an over-broad pack (the planner set it aside rather
    than auto-grabbing the whole season/series for one episode). The CTA
    grabs the pack via the same path as a swap-picker choice.
    """

    @enforce_keys [:unit_id, :unit_label, :guid, :scope_label]
    defstruct [:unit_id, :unit_label, :guid, :scope_label, :title, :size_bytes]

    @type t :: %__MODULE__{
            unit_id: Ecto.UUID.t(),
            unit_label: String.t(),
            guid: String.t(),
            scope_label: String.t(),
            title: String.t() | nil,
            size_bytes: integer() | nil
          }
  end

  defmodule BelowPreference do
    @moduledoc """
    The grouped "available only in lower quality" outcome (UIDR-029):
    every unfound unit for which identity-verified releases exist, all
    below the quality preference, totalled into one summary — one row,
    however many episodes it covers. Counts are the planner's
    solve-time verdict (durable on the units); candidates are listed
    live via `Plans.Alternatives.for_unit/1`. `unit_id`/`unit_label` are set
    only when a single unit is below preference (the movie case, or one
    stray episode) so the row can open that unit's picker directly.
    Never presented as a bare "not available" gap.
    """

    @enforce_keys [:units, :releases]
    defstruct [:units, :releases, :unit_id, :unit_label]

    @type t :: %__MODULE__{
            units: pos_integer(),
            releases: pos_integer(),
            unit_id: Ecto.UUID.t() | nil,
            unit_label: String.t() | nil
          }
  end

  defmodule Overlap do
    @moduledoc """
    A duplicate-data warning: one assigned release physically contains
    episodes that are assigned to *other* releases — approving would
    download those episodes twice. Created by deliberate swap-picker
    choices (the planner itself never assigns overlapping releases);
    the CTA excludes the containing release plan-wide and re-solves.
    """

    @enforce_keys [:description, :action_label, :exclude_guid, :exclude_unit_id]
    defstruct [:description, :action_label, :exclude_guid, :exclude_unit_id]

    @type t :: %__MODULE__{
            description: String.t(),
            action_label: String.t(),
            exclude_guid: String.t(),
            exclude_unit_id: Ecto.UUID.t()
          }
  end

  @enforce_keys [:plan_id, :title, :status, :wanted, :covered, :lines]
  defstruct [
    :plan_id,
    :title,
    :status,
    :error,
    :wanted,
    :covered,
    :lines,
    movie?: false,
    lower_quality_accepted?: false
  ]

  @type status :: :planning | :ready | :committed | :discarded

  @type t :: %__MODULE__{
          plan_id: Ecto.UUID.t(),
          title: String.t(),
          status: status(),
          error: String.t() | nil,
          wanted: non_neg_integer(),
          covered: non_neg_integer(),
          lines: [Line.t()],
          movie?: boolean(),
          lower_quality_accepted?: boolean()
        }

  @doc "The chosen releases, in line order."
  @spec releases(t()) :: [Release.t()]
  def releases(%__MODULE__{lines: lines}) do
    for %Line{kind: :release, release: release} <- lines, do: release
  end

  @doc "The sum of the chosen releases' sizes, or nil when none says."
  @spec total_size_bytes(t()) :: integer() | nil
  def total_size_bytes(%__MODULE__{} = board) do
    sizes = board |> releases() |> Enum.map(& &1.size_bytes) |> Enum.filter(&is_integer/1)
    if sizes != [], do: Enum.sum(sizes)
  end

  @doc """
  The labels of the units nothing acceptable covers — the not-found and
  the offered cells, in season and episode order — the gap verdict's
  `gaps`. Below-preference units are not gaps: releases exist.
  """
  @spec gap_labels(t()) :: [String.t()]
  def gap_labels(%__MODULE__{lines: lines}) do
    lines
    |> Enum.filter(&(&1.kind in [:not_found, :offer]))
    |> Enum.flat_map(&Line.cells/1)
    |> Enum.sort_by(&{&1.season_number || 0, &1.episode_number || 0})
    |> Enum.map(& &1.label)
  end

  @doc "The below-preference total, or nil when no unit is below preference."
  @spec below_preference(t()) :: BelowPreference.t() | nil
  def below_preference(%__MODULE__{lines: lines}) do
    Enum.find_value(lines, fn
      %Line{kind: :below_preference, below: below} -> below
      _line -> nil
    end)
  end

  @doc """
  The unfound unit of a movie board — what the gap verdict's rejected
  list (UIDR-022) opens on. Nil for a series or a found movie.
  """
  @spec movie_gap_unit_id(t()) :: Ecto.UUID.t() | nil
  def movie_gap_unit_id(%__MODULE__{movie?: true, lines: lines}) do
    Enum.find_value(lines, fn
      %Line{kind: :not_found} = line -> line |> Line.cells() |> List.first() |> Map.get(:plan_unit_id)
      _line -> nil
    end)
  end

  def movie_gap_unit_id(%__MODULE__{}), do: nil

  @doc """
  A ready board with nothing to approve — every wanted unit unfound. Its
  foot carries the watchlist in place of Approve (spec 2026-09-14).
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{status: :ready} = board), do: releases(board) == []
  def empty?(%__MODULE__{}), do: false

  @doc """
  Duplicate-data warnings across the assigned releases. `claims` maps
  each release guid to the `{season, episode}` units assigned to it;
  a release whose *physical* scope (re-classified from its title)
  covers units claimed by other releases gets one `Overlap` pointing
  at itself — excluding the container is the resolution that keeps
  the user's narrower choice. Pure; the planner never creates this
  state, only swap-picker choices do.
  """
  @spec overlaps([Release.t()], %{String.t() => [{pos_integer() | nil, pos_integer() | nil}]}) ::
          [Overlap.t()]
  def overlaps(releases, claims) when is_list(releases) and is_map(claims) do
    Enum.flat_map(releases, fn release ->
      scope = ReleaseCoverage.classify(release.title)

      shadowed =
        for {guid, units} <- claims,
            guid != release.guid,
            {season, episode} <- units,
            is_integer(season) and is_integer(episode),
            ReleaseCoverage.covers?(scope, season, episode),
            do: {season, episode}

      case shadowed do
        [] ->
          []

        units ->
          [
            %Overlap{
              description:
                "#{release_name(release)} also contains #{count(length(units), "episode")} " <>
                  "assigned to other releases — they'd download twice",
              action_label: "Remove it & re-solve",
              exclude_guid: release.guid,
              exclude_unit_id: release.swap_unit_id
            }
          ]
      end
    end)
  end

  defp release_name(%Release{scope_label: label}) when is_binary(label), do: "The #{label}"
  defp release_name(%Release{title: title}), do: title
end
