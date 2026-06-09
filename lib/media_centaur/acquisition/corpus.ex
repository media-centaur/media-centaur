defmodule MediaCentaur.Acquisition.Corpus do
  @moduledoc """
  The durable search corpus (ADR-055 / media-search campaign): every
  acquisition search records what it found, keyed by search term +
  result-affecting options, and automated searches consult the corpus
  before touching an indexer.

  Two masters, per the campaign:

  1. **Indexer citizenship** — `search/2` is the consult-first seam:
     a key searched within the freshness window (#{30} minutes) serves
     from the corpus with zero HTTP. Empty result sets count as fresh
     too — negative knowledge is what stops an automated system from
     hammering indexers for releases that aren't there. User-initiated
     refreshes pass `force: true`.
  2. **Current-alternative fallback** — candidates are durable, so a
     pivot (auto-cancel, change-target) re-resolves among already-known
     releases for the unit's term instead of re-discovering.

  The corpus is **not** a wait-for-something-better mechanism: nothing
  watches it for upgrades, and rows beyond the #{14}-day retention are
  deleted (`prune_stale!/0`, ADR-033 — delete over hide), called from
  the pursuit watcher's tick.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Corpus.{Candidate, SearchRecord}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{Prowlarr, SearchResult}

  @freshness_window_minutes 30
  @retention_days 14

  # Opts that change what an indexer returns — part of the corpus key.
  # Everything else (e.g. :force) is corpus-internal.
  @keyed_opts [:type, :year]

  @doc """
  Consult-first search. A fresh corpus key returns its candidates with
  no indexer traffic; otherwise the term is live-searched through
  `Prowlarr.search/2` and the outcome recorded. `force: true` always
  live-searches (user-initiated refresh). Failures are returned as-is
  and never recorded — an indexer outage must not masquerade as fresh
  negative knowledge.
  """
  @spec search(String.t(), keyword()) :: {:ok, [SearchResult.t()]} | {:error, term()}
  def search(term, opts \\ []) when is_binary(term) do
    search_opts = Keyword.take(opts, @keyed_opts)

    if not Keyword.get(opts, :force, false) and fresh?(term, search_opts) do
      {:ok, candidates_for(term, search_opts)}
    else
      with {:ok, results} <- Prowlarr.search(term, search_opts) do
        record!(term, search_opts, results)
        {:ok, results}
      end
    end
  end

  @doc """
  Records a completed live search: upserts the search row (freshness)
  and one candidate per result. Mutable health facts (seeders,
  leechers, size) refresh on conflict; `first_seen_at` is preserved.
  """
  @spec record!(String.t(), keyword(), [SearchResult.t()]) :: :ok
  def record!(term, opts, results) when is_binary(term) and is_list(results) do
    now = DateTime.utc_now(:second)
    key = search_key(term, opts)

    Repo.insert!(
      SearchRecord.changeset(%{
        search_key: key,
        term: term,
        last_searched_at: now,
        result_count: length(results)
      }),
      on_conflict: {:replace, [:last_searched_at, :result_count, :updated_at]},
      conflict_target: :search_key
    )

    Enum.each(results, fn %SearchResult{} = result ->
      Repo.insert!(
        Candidate.changeset(%{
          search_key: key,
          guid: result.guid,
          title: result.title,
          indexer_id: result.indexer_id,
          indexer_name: result.indexer_name,
          quality: quality_to_string(result.quality),
          size_bytes: result.size_bytes,
          seeders: result.seeders,
          leechers: result.leechers,
          publish_date: result.publish_date,
          info_hash: result.info_hash,
          magnet_url: result.magnet_url,
          download_url: result.download_url,
          first_seen_at: now,
          last_seen_at: now
        }),
        on_conflict:
          {:replace,
           [
             :title,
             :indexer_id,
             :indexer_name,
             :quality,
             :size_bytes,
             :seeders,
             :leechers,
             :publish_date,
             :info_hash,
             :magnet_url,
             :download_url,
             :last_seen_at,
             :updated_at
           ]},
        conflict_target: [:search_key, :guid]
      )
    end)

    :ok
  end

  @doc "True when the key was searched within the freshness window."
  @spec fresh?(String.t(), keyword()) :: boolean()
  def fresh?(term, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@freshness_window_minutes * 60, :second)
    key = search_key(term, opts)

    SearchRecord
    |> where([s], s.search_key == ^key and s.last_searched_at >= ^cutoff)
    |> Repo.exists?()
  end

  @doc """
  The known candidates for a key, rehydrated as `SearchResult` structs
  (grab-ready), most-seeded first.
  """
  @spec candidates_for(String.t(), keyword()) :: [SearchResult.t()]
  def candidates_for(term, opts \\ []) do
    key = search_key(term, opts)

    Candidate
    |> where([c], c.search_key == ^key)
    |> order_by([c], desc: c.seeders, desc: c.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_search_result/1)
  end

  @doc """
  The corpus key for a term + its result-affecting options. Pure —
  exposed so tests and callers can address rows directly.
  """
  @spec search_key(String.t(), keyword()) :: String.t()
  def search_key(term, opts) do
    @keyed_opts
    |> Enum.flat_map(fn opt_key ->
      case Keyword.get(opts, opt_key) do
        nil -> []
        value -> ["#{opt_key}:#{value}"]
      end
    end)
    |> then(fn
      [] -> term
      parts -> Enum.join([term | parts], "|")
    end)
  end

  @doc """
  Deletes searches and candidates beyond the retention window
  (ADR-033 — delete over hide). Idempotent; called from the pursuit
  watcher's tick.
  """
  @spec prune_stale!() :: :ok
  def prune_stale! do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@retention_days * 86_400, :second)

    Repo.delete_all(from(c in Candidate, where: c.last_seen_at < ^cutoff))
    Repo.delete_all(from(s in SearchRecord, where: s.last_searched_at < ^cutoff))

    :ok
  end

  # Quality atoms are a closed two-value set (`Search.Quality.t()`) —
  # explicit clauses both ways so a bad row can never mint an atom.
  defp quality_to_string(:uhd_4k), do: "uhd_4k"
  defp quality_to_string(:hd_1080p), do: "hd_1080p"
  defp quality_to_string(_quality), do: nil

  defp quality_from_string("uhd_4k"), do: :uhd_4k
  defp quality_from_string("hd_1080p"), do: :hd_1080p
  defp quality_from_string(_quality), do: nil

  defp to_search_result(%Candidate{} = candidate) do
    %SearchResult{
      title: candidate.title,
      guid: candidate.guid,
      indexer_id: candidate.indexer_id,
      indexer_name: candidate.indexer_name,
      quality: quality_from_string(candidate.quality),
      size_bytes: candidate.size_bytes,
      seeders: candidate.seeders,
      leechers: candidate.leechers,
      publish_date: candidate.publish_date,
      info_hash: candidate.info_hash,
      magnet_url: candidate.magnet_url,
      download_url: candidate.download_url
    }
  end
end
