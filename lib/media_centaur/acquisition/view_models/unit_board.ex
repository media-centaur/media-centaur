defmodule MediaCentaur.Acquisition.ViewModels.UnitBoard do
  @moduledoc """
  Display contract for the coverage board: the window's units as attempt
  threads (ADR-055).

  One row per unit: what the unit wants (its label), where its thread
  stands (a state word), the release that covers it now, and every
  release tried for it (`Row.attempts`, from the targets covering the
  unit — the same targets History resolves its events through). Built by
  `MediaCentaur.Acquisition.Pursuits.detail_for/1`; the modal renders it
  for every pursuit, a single film included, and draws the Coverage count
  and bar for multi-unit goals only.

  ## The words

  A unit's state has one word list, on `Row` — **Landed · Trying · Needs a
  pick · Gave up · Cancelled** — read by the row, the season header's
  counts and the Activity card's fold (`fold/1`, `Fold`). The cell and
  segment treatments for the same states live in
  `MediaCentaurWeb.Components.Acquisition.CellVocabulary`.

  ## Season roll-up

  Big shows are a wall of rows (a 38-episode season pack = 38 rows), so
  `group_rows/1` rolls rows up into collapsible `Group`s when the board
  warrants it: two or more distinct seasons, or a single season at or
  past the grouping threshold. Headers carry the aggregate (counts +
  the shared covering release) so the *collapsed* state is the
  informative one; a group holding any unlanded exception — a unit
  awaiting a pick, one that gave up, one that was cancelled — defaults
  open. Rows without season identity (query-door units) collect into a
  trailing "Other" group. `groups` is `nil` for small flat boards — the
  component renders the plain list.
  """

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.{Fold, Group, Row}

  # A single-season board at or past this many rows still groups — one
  # collapsible "Season 1 · 38 of 38 landed" line is the whole point.
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

  defmodule Attempt do
    @moduledoc """
    One release tried for a unit, read off its target: the release's facts,
    when it was tried, how it ended and — for a release the download client
    gave up on — the client's words.
    """

    @enforce_keys [:release_title, :outcome]
    defstruct [
      :target_id,
      :release_title,
      :quality,
      :size_bytes,
      :indexer,
      :started_at,
      :ended_at,
      :detail,
      :outcome
    ]

    @typedoc """
    `:landed` the file arrived; `:trying` in flight; `:failed` the client
    could not finish it (or the grab was refused); `:abandoned` closed with
    the download when the download itself was cancelled; `:stopped` a
    person swapped it out.
    """
    @type outcome :: :landed | :trying | :failed | :abandoned | :stopped

    @type t :: %__MODULE__{
            # The target's id — one pack covering three episodes is one
            # release tried, however many rows it appears under.
            target_id: Ecto.UUID.t() | nil,
            release_title: String.t(),
            quality: String.t() | nil,
            size_bytes: integer() | nil,
            indexer: String.t() | nil,
            started_at: DateTime.t() | nil,
            ended_at: DateTime.t() | nil,
            detail: String.t() | nil,
            outcome: outcome()
          }

    @spec word(outcome()) :: String.t()
    def word(:landed), do: "Landed"
    def word(:trying), do: "Trying"
    def word(:failed), do: "Failed"
    def word(:abandoned), do: "Abandoned with the download"
    def word(:stopped), do: "Stopped"
  end

  defmodule Row do
    @moduledoc """
    One unit of the board: identity (`label` — the expanded term for
    query-door units, falling back to the pursuit title), thread state,
    season identity for the roll-up, the release its current target
    carries, and its attempts. `actionable?` gates the per-unit "Pick a
    different release" affordance — only in-flight units that are not
    already awaiting a pick can swap.
    """

    alias MediaCentaur.Acquisition.ViewModels.UnitBoard.Attempt

    @enforce_keys [:id, :label, :state]
    defstruct [
      :id,
      :label,
      :state,
      :season_number,
      :release_title,
      awaiting_decision?: false,
      actionable?: false,
      attempts: [],
      attempt_count: 0
    ]

    @type state :: :active | :satisfied | :exhausted | :cancelled
    @type severity :: :info | :success | :warning | :error | :muted

    @type t :: %__MODULE__{
            id: Ecto.UUID.t(),
            label: String.t(),
            state: state(),
            season_number: integer() | nil,
            release_title: String.t() | nil,
            awaiting_decision?: boolean(),
            actionable?: boolean(),
            # Newest first.
            attempts: [Attempt.t()],
            attempt_count: non_neg_integer()
          }

    @doc "The one word for the unit's state."
    @spec word(t()) :: String.t()
    def word(%__MODULE__{awaiting_decision?: true}), do: "Needs a pick"
    def word(%__MODULE__{state: :active}), do: "Trying"
    def word(%__MODULE__{state: :satisfied}), do: "Landed"
    def word(%__MODULE__{state: :exhausted}), do: "Gave up"
    def word(%__MODULE__{state: :cancelled}), do: "Cancelled"

    @spec severity(t()) :: severity()
    def severity(%__MODULE__{awaiting_decision?: true}), do: :warning
    def severity(%__MODULE__{state: :active}), do: :info
    def severity(%__MODULE__{state: :satisfied}), do: :success
    def severity(%__MODULE__{state: :exhausted}), do: :error
    def severity(%__MODULE__{state: :cancelled}), do: :muted

    @doc """
    The word with the thread's cost: "Landed · 28th release", "Trying ·
    3rd release", "Gave up · 4 releases failed", "Cancelled · 48 releases
    failed"; the bare word when there is nothing to add.
    """
    @spec outcome_line(t()) :: String.t()
    def outcome_line(%__MODULE__{awaiting_decision?: true} = row), do: word(row)

    def outcome_line(%__MODULE__{state: :satisfied, attempt_count: count} = row) when count > 1,
      do: "#{word(row)} · #{ordinal(count)} release"

    def outcome_line(%__MODULE__{state: :active, attempt_count: count} = row) when count > 1,
      do: "#{word(row)} · #{ordinal(count)} release"

    def outcome_line(%__MODULE__{state: :exhausted} = row), do: with_failures(row)
    def outcome_line(%__MODULE__{state: :cancelled} = row), do: with_failures(row)
    def outcome_line(%__MODULE__{} = row), do: word(row)

    defp with_failures(row) do
      case failed_count(row) do
        0 -> word(row)
        n -> "#{word(row)} · #{n} #{releases(n)} failed"
      end
    end

    @doc """
    One sentence for why the thread failed, when every failed release
    failed the same way (the client's words); nil otherwise.
    """
    @spec cause(t()) :: String.t() | nil
    def cause(%__MODULE__{attempts: attempts}) do
      details =
        attempts
        |> Enum.filter(&(&1.outcome == :failed and is_binary(&1.detail) and &1.detail != ""))
        |> Enum.map(& &1.detail)

      case {Enum.uniq(details), length(details)} do
        {[detail], 1} -> "Failed at your download client — #{detail}."
        {[detail], _several} -> "Every release failed at your download client — #{detail}."
        _mixed_or_none -> nil
      end
    end

    @spec failed_count(t()) :: non_neg_integer()
    def failed_count(%__MODULE__{attempts: attempts}), do: Enum.count(attempts, &(&1.outcome == :failed))

    defp releases(1), do: "release"
    defp releases(_n), do: "releases"

    defp ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"
    defp ordinal(n) when rem(n, 10) == 1, do: "#{n}st"
    defp ordinal(n) when rem(n, 10) == 2, do: "#{n}nd"
    defp ordinal(n) when rem(n, 10) == 3, do: "#{n}rd"
    defp ordinal(n), do: "#{n}th"
  end

  defmodule Group do
    @moduledoc """
    A collapsible season bucket of the board. `key` is the stable
    toggle identity carried on the click event (`"1"`, `"2"`, …,
    `"other"`). `shared_release_title` is hoisted to the header when a
    single release covers every targeted row, so expanded rows only
    show deviations. `expanded_default?` is exception-driven: a group
    holding a unit awaiting a pick, one that gave up or one that was
    cancelled opens by default.
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
      trying: 0,
      awaiting: 0,
      exhausted: 0,
      cancelled: 0,
      expanded_default?: false
    ]

    @type t :: %__MODULE__{
            key: String.t(),
            label: String.t(),
            season_number: integer() | nil,
            rows: [MediaCentaur.Acquisition.ViewModels.UnitBoard.Row.t()],
            wanted: pos_integer(),
            satisfied: non_neg_integer(),
            trying: non_neg_integer(),
            awaiting: non_neg_integer(),
            exhausted: non_neg_integer(),
            cancelled: non_neg_integer(),
            shared_release_title: String.t() | nil,
            expanded_default?: boolean()
          }
  end

  defmodule Fold do
    @moduledoc """
    The board folded into the counts the Activity card speaks: how many
    units were wanted and how many landed, are trying, need a pick, gave
    up or were cancelled; `releases_tried` is the number of targets across
    the units, nil when the caller has only the units (the Downloads list
    rows, which read no targets).
    """

    alias MediaCentaur.Acquisition.ViewModels.UnitBoard.Row

    defstruct wanted: 0, landed: 0, trying: 0, awaiting: 0, gave_up: 0, cancelled: 0, releases_tried: nil

    @type t :: %__MODULE__{
            wanted: non_neg_integer(),
            landed: non_neg_integer(),
            trying: non_neg_integer(),
            awaiting: non_neg_integer(),
            gave_up: non_neg_integer(),
            cancelled: non_neg_integer(),
            releases_tried: non_neg_integer() | nil
          }

    @spec from_rows([Row.t()]) :: t()
    def from_rows(rows) when is_list(rows) do
      releases_tried =
        rows
        |> Enum.flat_map(& &1.attempts)
        |> Enum.uniq_by(&(&1.target_id || make_ref()))
        |> length()

      %{from_states(Enum.map(rows, &{&1.state, &1.awaiting_decision?})) | releases_tried: releases_tried}
    end

    @doc "From `{state, awaiting?}` pairs — the units alone, no targets."
    @spec from_states([{Row.state(), boolean()}]) :: t()
    def from_states(pairs) when is_list(pairs) do
      %__MODULE__{
        wanted: length(pairs),
        landed: Enum.count(pairs, &match?({:satisfied, _}, &1)),
        awaiting: Enum.count(pairs, &match?({:active, true}, &1)),
        trying: Enum.count(pairs, &match?({:active, false}, &1)),
        gave_up: Enum.count(pairs, &match?({:exhausted, _}, &1)),
        cancelled: Enum.count(pairs, &match?({:cancelled, _}, &1))
      }
    end

    @doc "The units that did not land and are not being tried."
    @spec missing(t()) :: non_neg_integer()
    def missing(%__MODULE__{gave_up: gave_up, cancelled: cancelled}), do: gave_up + cancelled
  end

  @doc "The board folded into the Activity card's counts."
  @spec fold(t()) :: Fold.t()
  def fold(%__MODULE__{units: rows}), do: Fold.from_rows(rows)

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

  defp build_groups(rows) do
    rows
    |> Enum.group_by(& &1.season_number)
    |> Enum.sort_by(fn {season, _rows} -> {is_nil(season), season} end)
    |> Enum.map(fn {season, season_rows} ->
      awaiting = Enum.count(season_rows, & &1.awaiting_decision?)
      exhausted = Enum.count(season_rows, &(&1.state == :exhausted))
      cancelled = Enum.count(season_rows, &(&1.state == :cancelled))

      %Group{
        key: if(season, do: Integer.to_string(season), else: "other"),
        label: if(season, do: "Season #{season}", else: "Other"),
        season_number: season,
        rows: season_rows,
        wanted: length(season_rows),
        satisfied: Enum.count(season_rows, &(&1.state == :satisfied)),
        trying: Enum.count(season_rows, &(&1.state == :active and not &1.awaiting_decision?)),
        awaiting: awaiting,
        exhausted: exhausted,
        cancelled: cancelled,
        shared_release_title: shared_release_title(season_rows),
        expanded_default?: awaiting + exhausted + cancelled > 0
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
