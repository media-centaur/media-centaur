defmodule MediaCentarr.Acquisition.Pursuits do
  @moduledoc """
  Read-side queries over the pursuit aggregate.

  Write-side operations live in `Acquisition.Pursuits.Commands.*`. This
  module is intentionally read-only — it never mutates state, never
  broadcasts, never enqueues jobs. Callers that want to change the world
  go through a command.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, State}
  alias MediaCentarr.Repo

  @spec get(Ecto.UUID.t()) :: {:ok, Pursuit.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Pursuit, id) do
      nil -> {:error, :not_found}
      %Pursuit{} = pursuit -> {:ok, pursuit}
    end
  end

  @doc "Lists every in-flight pursuit (`active` or `needs_decision`), newest-updated first."
  @spec list_active() :: [Pursuit.t()]
  def list_active do
    Pursuit
    |> where([p], p.state in ^State.in_flight())
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Returns events for a pursuit, newest first. Empty list for unknown pursuit_id —
  events with nilified `pursuit_id` are not surfaced here (use a dedicated query
  if you need orphan events).
  """
  @spec events_for(Ecto.UUID.t()) :: [Event.t()]
  def events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc "Returns the most recently inserted grab linked to a pursuit."
  @spec latest_grab(Ecto.UUID.t()) :: {:ok, Grab.t()} | {:error, :not_found}
  def latest_grab(pursuit_id) do
    grab =
      Grab
      |> where([g], g.pursuit_id == ^pursuit_id)
      |> order_by([g], desc: g.inserted_at)
      |> limit(1)
      |> Repo.one()

    case grab do
      nil -> {:error, :not_found}
      %Grab{} = grab -> {:ok, grab}
    end
  end
end
