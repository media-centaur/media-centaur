defmodule MediaCentaur.Acquisition.Plans.MatchCriteria do
  @moduledoc """
  The single projection from a `TMDB.TitleIdentity` into the
  `Search.Criteria` every search and verification matches against.

  Both routes to `Criteria` come through here — a plan at solve time
  (`Jobs.RunPlan`, `Plans.Alternatives`) and a pursuit's recipe at
  execute time. They used to be independent hand-copies that had to
  agree by hand; a field carried onto plans and pursuits but projected
  in only one of them reached some searches and not others.

  It lives in Acquisition because it is the one context that depends on
  both TMDB (where identity is owned) and Search (whose `Criteria`
  deliberately knows nothing of its callers' domain — see that struct's
  moduledoc). Embedding `TitleIdentity` in `Criteria` would reverse that
  inversion, so this projection exists instead.

  A plan's identity is TMDB's: its id, its title (and its
  original-language title, when that differs), its year (movies) or
  origin countries (TV), plus the `imdb_id` / `tvdb_id` spellings
  indexers declare on their own results. Building the criteria in one
  place is what keeps a newly carried identifier from reaching some
  searches and not others.

  Scope — which season, which episode — is the caller's to add; this is
  identity only. Pure module: no I/O, no DB.
  """

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Search.Criteria
  alias MediaCentaur.TMDB.TitleIdentity

  @spec from(Plan.t() | TitleIdentity.t()) :: Criteria.t()
  def from(%Plan{} = plan), do: from(Plan.identity(plan))

  def from(%TitleIdentity{tmdb_type: :movie} = identity) do
    %Criteria{
      type: :tmdb,
      title: identity.title,
      tmdb_type: :movie,
      year: identity.year,
      tmdb_id: identity.tmdb_id,
      imdb_id: identity.imdb_id,
      tvdb_id: identity.tvdb_id,
      original_title: identity.original_title
    }
  end

  def from(%TitleIdentity{tmdb_type: :tv} = identity) do
    %Criteria{
      type: :tmdb,
      title: identity.title,
      tmdb_type: :tv,
      season_number: nil,
      episode_number: nil,
      tmdb_id: identity.tmdb_id,
      imdb_id: identity.imdb_id,
      tvdb_id: identity.tvdb_id,
      original_title: identity.original_title,
      origin_country: identity.origin_country
    }
  end
end
