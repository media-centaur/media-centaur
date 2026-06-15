defmodule MediaCentaur.Acquisition.Pursuits.Commands.Start do
  @moduledoc "Creates a pursuit (with its units) when its first grab is initiated."

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits.{Events, Pursuit, Unit}
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitStarted
  alias MediaCentaur.Repo

  @doc """
  Atomically inserts a Pursuit row, its units, and records the
  `pursuit_started` event. Returns `{:ok, pursuit}` on success or
  `{:error, changeset}` when a changeset fails. Event recording goes
  through `Events.record/1` so persistence and PubSub broadcast share
  one write path.

  `args` may carry `:units` — a list of `%{label, query, position}`
  maps (ADR-055). Defaults to a single unit whose `query` mirrors
  `manual_query` (nil for TMDB recipes, which derive queries from the
  parent recipe).
  """
  @spec execute(map()) :: {:ok, Pursuit.t()} | {:error, Ecto.Changeset.t()}
  def execute(args) when is_map(args) do
    unit_specs = Map.get(args, :units, [%{query: Map.get(args, :manual_query)}])

    # Creation commands run their own transaction rather than going through
    # Commands.Runner: Runner operates on an already-existing pursuit/unit
    # (load → mutate → emit), whereas Start brings the pursuit and its units
    # into being in the same transaction.
    result =
      Repo.transaction(fn ->
        with {:ok, pursuit} <- Repo.insert(Pursuit.create_changeset(Map.delete(args, :units))),
             {:ok, _units} <- insert_units(pursuit, unit_specs),
             {:ok, _event} <-
               Events.record(%PursuitStarted{
                 pursuit_id: pursuit.id,
                 pursuit_title: pursuit.title,
                 occurred_at: DateTime.utc_now(:second),
                 origin: pursuit.origin
               }) do
          pursuit
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, %Pursuit{title: title}} -> Log.info(:acquisition, "pursuit started — #{title}")
      _ -> :ok
    end

    result
  end

  defp insert_units(%Pursuit{} = pursuit, unit_specs) do
    unit_specs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {spec, index}, {:ok, inserted} ->
      attrs = %{
        pursuit_id: pursuit.id,
        label: Map.get(spec, :label),
        query: Map.get(spec, :query),
        season_number: Map.get(spec, :season_number),
        episode_number: Map.get(spec, :episode_number),
        position: Map.get(spec, :position, index)
      }

      case Repo.insert(Unit.create_changeset(attrs)) do
        {:ok, unit} -> {:cont, {:ok, [unit | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      error -> error
    end
  end
end
