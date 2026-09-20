defmodule MediaCentaur.TMDB.References do
  @moduledoc """
  Who references a TMDB identity — the one answer behind two decisions:
  what the store and the artwork cache keep alive, and which stored
  titles are scheduled for checks (ADR-071 §4).

  A reference is a `{tmdb_id, media_type}` ref held by a context: a
  tracked item, a title intent, an open pursuit, a friend's activity.
  Each context registers a `Provider` under
  `config :media_centaur, :tmdb_reference_providers` — runtime dispatch,
  so the referencing contexts stay upstream of TMDB in the Boundary
  graph. `all/1` is retention; `scheduled/1` is only the providers whose
  references mean the user is waiting on how the title unfolds. A title
  known only through friends' activity is kept, never checked.

  Generalised from `TmdbArtwork.HoldProvider` (2026-09-20), which asked
  the retention half of this question for artwork alone. Scheduling
  widens phase by phase as readers move onto the store: tracked titles
  in Phase 2 of `tmdb-fetch-policy`, listed and planned titles in
  Phase 3, owned titles in Phase 4.
  """

  alias MediaCentaur.TMDB.Store

  defmodule Provider do
    @moduledoc """
    A context that holds TMDB titles: what it references, and whether
    those references schedule checks. `references/0` runs inside the
    checker's tick and the daily retention sweep; a provider that raises
    fails that run, so keep it a plain query.
    """
    @callback references() :: MapSet.t(Store.ref())
    @callback schedules_checks?() :: boolean()
  end

  @doc "The registered providers, in configuration order."
  @spec providers() :: [module()]
  def providers, do: Application.get_env(:media_centaur, :tmdb_reference_providers, [])

  @doc "Every referenced identity — what stays alive."
  @spec all([module()]) :: MapSet.t(Store.ref())
  def all(providers \\ providers()) do
    Enum.reduce(providers, MapSet.new(), &MapSet.union(&2, &1.references()))
  end

  @doc "The identities whose references schedule checks."
  @spec scheduled([module()]) :: MapSet.t(Store.ref())
  def scheduled(providers \\ providers()) do
    providers
    |> Enum.filter(& &1.schedules_checks?())
    |> all()
  end
end
