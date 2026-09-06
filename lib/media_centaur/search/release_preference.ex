defmodule MediaCentaur.Search.ReleasePreference do
  @moduledoc """
  The single order in which an **automatic** grab prefers one
  identity-verified, quality-acceptable release over another.

      resolution tier -> source ladder -> popularity

  Both automated pickers — the plan runner's movie solve
  (`Acquisition.Jobs.RunPlan`) and the pursuit retry loop
  (`Acquisition.Jobs.PursueTarget`) — sort by this and nothing else, so
  the two cannot drift on what "best" means. They previously did: the
  plan runner ranked on all three components while the retry loop ranked
  on resolution alone, which meant an unattended grab ignored the user's
  `auto_grab.size_preference` and picked arbitrarily among same-tier
  releases.

  ## Popularity — seeders OR grabs

  `seeders` is a torrent concept. A usenet indexer returns no swarm, so
  on a usenet-only setup a seeders-only tiebreak is permanently `nil`
  and every tie past the source ladder falls to pool order. Prowlarr
  reports `grabs` (how many times the indexer has served the release),
  which is the usenet analogue, so this reads whichever the protocol
  actually populates. It is only ever a **tiebreak** — never a gate, and
  never able to outrank resolution or source.

  ## Not the picker's order

  The swap picker (`Acquisition.Plans.Alternatives`) deliberately sorts
  differently: it floats suspicious releases last and ranks the
  below-floor resolutions (720p, DVD) that this module's two-tier
  `Quality.rank/1` collapses to zero. Those are presentation concerns a
  human chooser needs and an automatic pick must never have, so the two
  orders are genuinely different rather than duplicates.

  Pure module — no I/O, no DB.
  """

  alias MediaCentaur.Search.{Quality, SearchResult}

  @type key :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  The comparison key for one release, highest wins. Feed it straight to
  `Enum.max_by/3` or `Enum.sort_by/3`.
  """
  @spec key(SearchResult.t(), Quality.size_preference()) :: key()
  def key(%SearchResult{} = result, size_preference) do
    {Quality.rank(result.quality), Quality.source_rank(Quality.source(result.title), size_preference),
     popularity(result)}
  end

  @doc """
  The best release in `results`, or `nil` for an empty list. Ties keep
  the **earliest** candidate, which is how the movie ladder's
  precise-before-broad term order survives into the pick: an equal
  candidate found under `Title year` is preferred to one found under the
  bare `Title`, because the year-matched term is the likelier identity.
  """
  @spec best([SearchResult.t()], Quality.size_preference()) :: SearchResult.t() | nil
  def best(results, size_preference) when is_list(results) do
    Enum.reduce(results, nil, fn result, best -> better_of(best, result, size_preference) end)
  end

  @doc """
  Keeps whichever of the two ranks higher, preferring `incumbent` on an
  exact tie. `nil` stands for "nothing yet", so this folds cleanly over
  candidates arriving rung by rung.
  """
  @spec better_of(SearchResult.t() | nil, SearchResult.t() | nil, Quality.size_preference()) ::
          SearchResult.t() | nil
  def better_of(incumbent, nil, _size_preference), do: incumbent
  def better_of(nil, challenger, _size_preference), do: challenger

  def better_of(%SearchResult{} = incumbent, %SearchResult{} = challenger, size_preference) do
    if key(challenger, size_preference) > key(incumbent, size_preference),
      do: challenger,
      else: incumbent
  end

  defp popularity(%SearchResult{seeders: seeders}) when is_integer(seeders), do: seeders
  defp popularity(%SearchResult{grabs: grabs}) when is_integer(grabs), do: grabs
  defp popularity(%SearchResult{}), do: 0
end
