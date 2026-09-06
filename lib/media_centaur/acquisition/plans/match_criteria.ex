defmodule MediaCentaur.Acquisition.Plans.MatchCriteria do
  @moduledoc """
  The `Search.Criteria` that identify a plan's title — the single
  projection every plan-side search and verification shares
  (`Jobs.RunPlan`, `Plans.Alternatives`).

  A plan's identity is TMDB's: its id, its title, its year (movies) or
  origin countries (TV), plus the `imdb_id` / `tvdb_id` spellings
  indexers declare on their own results. Building the criteria in one
  place is what keeps a newly carried identifier from reaching some
  searches and not others.

  Scope — which season, which episode — is the caller's to add; this is
  identity only. Pure module: no I/O, no DB.
  """

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Search.Criteria

  @spec from(Plan.t()) :: Criteria.t()
  def from(%Plan{tmdb_type: "movie"} = plan) do
    %Criteria{
      type: :tmdb,
      title: plan.title,
      tmdb_type: :movie,
      year: plan.year,
      tmdb_id: plan.tmdb_id,
      imdb_id: plan.imdb_id,
      tvdb_id: plan.tvdb_id
    }
  end

  def from(%Plan{tmdb_type: "tv"} = plan) do
    %Criteria{
      type: :tmdb,
      title: plan.title,
      tmdb_type: :tv,
      season_number: nil,
      episode_number: nil,
      tmdb_id: plan.tmdb_id,
      imdb_id: plan.imdb_id,
      tvdb_id: plan.tvdb_id,
      origin_country: plan.origin_country || []
    }
  end
end
