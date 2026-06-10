defmodule MediaCentaur.Acquisition.Plans.Claims do
  @moduledoc """
  The single definition of "this unit is claimed by an active pursuer"
  (ADR-055's overlap invariant, generalized for ADR-056).

  Two claim sources:

  * **Pursuits** — active TMDB pursuits' active units. This is the half
    `CommitPlan` enforces at approval (commit-time overlap rejection).
  * **Live drafts** — non-excluded units of `planning`/`ready` plans.
    The drop planner adds this half so a want under review in any draft
    (media-search or tracking) is not re-planned by the tick.

  Unit identity lives on units (season/episode, ADR-055); movies claim
  at the title level (a movie pursuit/plan is the whole film).
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Repo

  @doc "Active-pursuit-claimed `{season, episode}` set for a TV title."
  @spec pursuit_claimed_units(String.t()) :: MapSet.t()
  def pursuit_claimed_units(tmdb_id) do
    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "tv")
    |> Repo.all()
    |> Enum.flat_map(&claimed_units/1)
    |> MapSet.new()
  end

  @doc "Whether an active pursuit claims this movie."
  @spec movie_pursuit_claimed?(String.t()) :: boolean()
  def movie_pursuit_claimed?(tmdb_id) do
    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "movie")
    |> Repo.exists?()
  end

  @doc "Live-draft-claimed `{season, episode}` set for a TV title."
  @spec draft_claimed_units(String.t()) :: MapSet.t()
  def draft_claimed_units(tmdb_id) do
    PlanUnit
    |> join(:inner, [u], p in Plan, on: p.id == u.plan_id)
    |> where([u, p], p.status in ["planning", "ready"])
    |> where([u, p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "tv")
    |> where([u, _p], u.status != "excluded")
    |> select([u, _p], {u.season_number, u.episode_number})
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Whether a live draft claims this movie."
  @spec movie_draft_claimed?(String.t()) :: boolean()
  def movie_draft_claimed?(tmdb_id) do
    Plan
    |> where([p], p.status in ["planning", "ready"])
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "movie")
    |> Repo.exists?()
  end

  @doc "Pursuit + draft claims combined — the drop planner's read."
  @spec claimed_units(String.t(), String.t()) :: MapSet.t() | boolean()
  def claimed_units(tmdb_id, "tv") do
    MapSet.union(pursuit_claimed_units(tmdb_id), draft_claimed_units(tmdb_id))
  end

  def claimed_units(tmdb_id, "movie") do
    movie_pursuit_claimed?(tmdb_id) or movie_draft_claimed?(tmdb_id)
  end

  # A pursuit's claimed units. Identity lives on units (ADR-055):
  # every pursuit creation path stamps season/episode on the unit and
  # the `BackfillUnitIdentity` data migration covered pre-existing
  # rows, so there is no parent-level fallback here.
  defp claimed_units(%Pursuit{} = pursuit) do
    pursuit.id
    |> Units.for_pursuit()
    |> Enum.filter(&(&1.state == "active"))
    |> Enum.map(&{&1.season_number, &1.episode_number})
    |> Enum.reject(&(&1 == {nil, nil}))
  end
end
