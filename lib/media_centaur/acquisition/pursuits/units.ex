defmodule MediaCentaur.Acquisition.Pursuits.Units do
  @moduledoc """
  Read-side queries over pursuit units.

  Units carry the attempt thread of a composite pursuit (ADR-055).
  Write-side transitions live in `Pursuits.Commands.*`; this module
  never mutates state.

  ## `single!/1` — the interim resolver

  Until the media-search campaign's batch-grab collapse lands, every
  pursuit has exactly one unit, and commands that historically took a
  `pursuit_id` resolve their unit through `single!/1`. It **raises**
  on a multi-unit pursuit — deliberately, so the first multi-unit
  composite trips loudly at every call site that still needs a
  unit-scoped argument instead of silently acting on the wrong unit.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.{TargetUnit, Unit}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Repo

  @spec fetch(Ecto.UUID.t()) :: {:ok, Unit.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Unit, id) do
      nil -> {:error, :not_found}
      %Unit{} = unit -> {:ok, unit}
    end
  end

  @doc "All units of a pursuit, in stable display order."
  @spec for_pursuit(Ecto.UUID.t()) :: [Unit.t()]
  def for_pursuit(pursuit_id) do
    Unit
    |> where([u], u.pursuit_id == ^pursuit_id)
    |> order_by([u], asc: u.position, asc: u.inserted_at)
    |> Repo.all()
  end

  @doc """
  Units of many pursuits in one query, grouped by `pursuit_id` and in
  stable display order. Batch variant of `for_pursuit/1` for row
  assembly.
  """
  @spec for_pursuits([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [Unit.t()]}
  def for_pursuits([]), do: %{}

  def for_pursuits(pursuit_ids) when is_list(pursuit_ids) do
    Unit
    |> where([u], u.pursuit_id in ^pursuit_ids)
    |> order_by([u], asc: u.position, asc: u.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.pursuit_id)
  end

  @doc """
  The pursuit's only unit. Raises on zero or many — see the moduledoc
  for why a raise (and not a quiet pick) is the right interim behavior.
  """
  @spec single!(Ecto.UUID.t()) :: Unit.t()
  def single!(pursuit_id) do
    case for_pursuit(pursuit_id) do
      [%Unit{} = unit] ->
        unit

      units ->
        raise ArgumentError,
              "expected pursuit #{pursuit_id} to have exactly one unit, got #{length(units)} — " <>
                "this call site needs a unit-scoped argument (ADR-055 rollout)"
    end
  end

  @doc """
  The unit a pursuit-scoped surface (detail modal, decision card,
  pursuit-level intervention) shows or acts on, until per-unit
  drill-down lands. Preference order: the active unit awaiting a
  decision, then the first active unit with a current target, then the
  first active unit, then the first unit at all. Nil for a unitless
  list.
  """
  @spec lead_of([Unit.t()]) :: Unit.t() | nil
  def lead_of(units) when is_list(units) do
    active = Enum.filter(units, &(&1.state == "active"))

    Enum.find(active, &(&1.awaiting_decision_at != nil)) ||
      Enum.find(active, &(&1.current_target_id != nil)) ||
      List.first(active) ||
      List.first(units)
  end

  @doc "Query-backed `lead_of/1` — loads the pursuit's units in display order first."
  @spec lead(Ecto.UUID.t()) :: Unit.t() | nil
  def lead(pursuit_id), do: pursuit_id |> for_pursuit() |> lead_of()

  @doc "The units covered by a target's release, via the coverage join."
  @spec covered_by(Ecto.UUID.t()) :: [Unit.t()]
  def covered_by(target_id) do
    Unit
    |> join(:inner, [u], tu in TargetUnit, on: tu.unit_id == u.id)
    |> where([u, tu], tu.target_id == ^target_id)
    |> order_by([u], asc: u.position)
    |> Repo.all()
  end

  @doc "Ids of every target covering the given unit."
  @spec covering_target_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def covering_target_ids(unit_id) do
    TargetUnit
    |> where([tu], tu.unit_id == ^unit_id)
    |> select([tu], tu.target_id)
    |> Repo.all()
  end

  @doc "The unit's current target (the row pointed at by `current_target_id`), if any."
  @spec current_target(Unit.t()) :: Target.t() | nil
  def current_target(%Unit{current_target_id: nil}), do: nil
  def current_target(%Unit{current_target_id: id}), do: Repo.get(Target, id)

  @doc "Unit state strings for a pursuit — the input to `State.fold_units/1`."
  @spec states_for(Ecto.UUID.t()) :: [String.t()]
  def states_for(pursuit_id) do
    Unit
    |> where([u], u.pursuit_id == ^pursuit_id)
    |> select([u], u.state)
    |> Repo.all()
  end

  @doc "Every `active` unit of a pursuit."
  @spec active_for(Ecto.UUID.t()) :: [Unit.t()]
  def active_for(pursuit_id) do
    Unit
    |> where([u], u.pursuit_id == ^pursuit_id and u.state == "active")
    |> order_by([u], asc: u.position)
    |> Repo.all()
  end
end
