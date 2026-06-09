defmodule MediaCentaur.Acquisition.Pursuits.Commands.Arm do
  @moduledoc """
  Idempotent "arm a pursuit for a TMDB target" command.

  Used by the auto-acquisition entry points (Reactor handler,
  Acquisition.enqueue facade, ArmAll bulk classifier) to:

    1. Find or create a pursuit for the given TMDB tuple.
    2. Ensure the pursuit's unit has an in-flight target — reusing the
       existing one when it's seeking/acquired, creating a fresh
       seeking target when the existing one is terminal-non-success
       or when no current target exists.

  Idempotency: a second call with the same TMDB tuple finds the same
  pursuit and either returns the existing in-flight target or arms a
  fresh one. The `PursueTarget` Oban job uses `unique` keys so the
  enqueue is also idempotent.

  Auto-grab pursuits are single-unit composites (ADR-055): the TMDB
  tuple identifies one wanted thing, so the unit resolves via
  `Units.single!/1`.

  Returns `{:ok, target}` carrying the target the worker will pursue
  (either freshly inserted or the pre-existing in-flight one).
  """

  alias MediaCentaur.Acquisition.Jobs.PursueTarget
  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Commands.Start
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit, Units}
  alias MediaCentaur.Acquisition.{Target, TargetStatus}
  alias MediaCentaur.Repo

  @doc """
  Required args:
    - `:tmdb_id` (string), `:tmdb_type` (`"movie" | "tv"`), `:title` (string)

  Optional:
    - `:season_number`, `:episode_number`, `:year` (TMDB recipe extras)
    - `:origin` (`"auto" | "manual"`, defaults to `"auto"`)
    - `:criteria` (map; quality bounds + patience window)
  """
  @spec execute(map()) :: {:ok, Target.t()} | {:error, term()}
  def execute(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type, title: title} = args)
      when is_binary(tmdb_id) and is_binary(tmdb_type) and is_binary(title) do
    with {:ok, pursuit} <- find_or_create_pursuit(args) do
      ensure_in_flight_target(pursuit)
    end
  end

  defp find_or_create_pursuit(args) do
    target = %{
      tmdb_id: args.tmdb_id,
      tmdb_type: args.tmdb_type,
      season_number: Map.get(args, :season_number),
      episode_number: Map.get(args, :episode_number)
    }

    case Pursuits.find_by_tmdb_recipe(target) do
      nil ->
        args
        |> Map.put(:recipe_type, "tmdb")
        |> Map.put_new(:origin, "auto")
        |> Map.put_new(:criteria, %{})
        |> Start.execute()

      %Pursuit{} = pursuit ->
        {:ok, pursuit}
    end
  end

  defp ensure_in_flight_target(%Pursuit{} = pursuit) do
    unit = Units.single!(pursuit.id)

    case Units.current_target(unit) do
      %Target{status: status} = target ->
        if TargetStatus.terminal?(status) and status != "succeeded" do
          # Existing terminal-non-success — start a fresh seeking target.
          new_seeking_target(pursuit, unit)
        else
          {:ok, target}
        end

      nil ->
        new_seeking_target(pursuit, unit)
    end
  end

  defp new_seeking_target(%Pursuit{} = pursuit, %Unit{} = unit) do
    with {:ok, target} <-
           %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
           |> Target.create_changeset()
           |> Repo.insert(),
         {:ok, _coverage} <-
           Repo.insert(TargetUnit.create_changeset(%{target_id: target.id, unit_id: unit.id})),
         {:ok, _unit} <-
           Repo.update(Unit.set_current_target_changeset(unit, target.id)) do
      Oban.insert(PursueTarget.new(%{"target_id" => target.id}))
      {:ok, target}
    end
  end
end
