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
  alias MediaCentaur.Search.{IndexerHealth, Prowlarr, SearchResult}

  @freshness_window_minutes 30
  @retention_days 14

  # Opts that change what an indexer returns — part of the corpus key.
  # Everything else (e.g. :force) is corpus-internal.
  #
  # `:categories` is the only one left. Two predecessors were removed
  # after measurement: `:type` never reached Prowlarr at all, and `:year`
  # reached it but was ignored (the generic search type honours only
  # `q`). Both nonetheless split the key space, so one movie cached into
  # two rows depending on which subsystem asked and neither could see the
  # other's knowledge. Anything keyed here MUST be passed identically by
  # every caller reading the same term — `LadderTerms.search_opts/1` and
  # `QueryBuilder` are the two places that decide it.
  @keyed_opts [:categories]

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
        if results != [] or not blind?() do
          record!(term, search_opts, results)
        end

        {:ok, results}
      end
    end
  end

  # A zero-result 200 from Prowlarr is ambiguous: "no releases exist" or
  # "every indexer I'd ask is backed off / unreachable" look identical
  # (UIDR-016). Only the empty case pays for the disambiguating health
  # snapshot; a blind answer is an outage, and per this module's contract
  # an outage must never masquerade as fresh negative knowledge. The
  # check also lands the moment-of-truth observation in the
  # `IndexerHealth` cache, which the plan UI reads for the same honesty.
  defp blind?, do: IndexerHealth.blind?(IndexerHealth.check())

  @doc """
  Records a completed live search: upserts the search row (freshness)
  and one candidate per result. Mutable health facts (seeders,
  leechers, size) refresh on conflict; `first_seen_at` is preserved.
  """
  @spec record!(String.t(), keyword(), [SearchResult.t()]) :: :ok
  def record!(term, opts, results) when is_binary(term) and is_list(results) do
    now = DateTime.utc_now(:second)
    key = search_key(term, opts)

    Repo.transaction(fn -> record_rows!(key, term, now, results) end)
    :ok
  end

  # SQLite binds at most 32_766 variables per statement; 23 columns per row.
  @insert_chunk 500

  defp candidate_row(%SearchResult{} = result, key, now) do
    %{
      # `insert_all` skips the schema's `autogenerate: true`; without this
      # the rows land with a null id.
      id: Ecto.UUID.generate(),
      search_key: key,
      guid: result.guid,
      title: result.title,
      indexer_id: result.indexer_id,
      indexer_name: result.indexer_name,
      quality: quality_to_string(result.quality),
      size_bytes: result.size_bytes,
      seeders: result.seeders,
      leechers: result.leechers,
      grabs: result.grabs,
      publish_date: result.publish_date,
      protocol: protocol_to_string(result.protocol),
      imdb_id: result.imdb_id,
      tmdb_id: result.tmdb_id,
      tvdb_id: result.tvdb_id,
      info_hash: result.info_hash,
      magnet_url: result.magnet_url,
      download_url: result.download_url,
      first_seen_at: now,
      last_seen_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp record_rows!(key, term, now, results) do
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

    # One statement per chunk instead of one autocommit per result — a
    # broad search returns hundreds of rows and each autocommit took the
    # SQLite write lock in turn (audit P5). `insert_all` bypasses the
    # changeset, so rows are shaped by `candidate_row/3` from the typed
    # `SearchResult`; the unique `(search_key, guid)` index drives the
    # upsert exactly as before.
    results
    |> Enum.map(&candidate_row(&1, key, now))
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(fn rows ->
      Repo.insert_all(Candidate, rows,
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
             :grabs,
             :publish_date,
             :protocol,
             :imdb_id,
             :tmdb_id,
             :tvdb_id,
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

  @doc "The consult-first freshness window — also the gap verdict's live/stale boundary (UIDR-022)."
  @spec freshness_window_minutes() :: pos_integer()
  def freshness_window_minutes, do: @freshness_window_minutes

  @doc """
  The search record for a key — when it last ran and how many results
  it returned — or nil when the term was never searched (or its record
  aged past retention). The gap verdict's evidence source (UIDR-022).
  """
  @spec record_for(String.t(), keyword()) ::
          %{searched_at: DateTime.t(), result_count: non_neg_integer()} | nil
  def record_for(term, opts \\ []) do
    key = search_key(term, opts)

    SearchRecord
    |> where([s], s.search_key == ^key)
    |> select([s], %{searched_at: s.last_searched_at, result_count: s.result_count})
    |> Repo.one()
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

    {candidate_count, _} = Repo.delete_all(from(c in Candidate, where: c.last_seen_at < ^cutoff))

    {search_count, _} =
      Repo.delete_all(from(s in SearchRecord, where: s.last_searched_at < ^cutoff))

    MediaCentaur.Retention.record_run(:search_corpus, candidate_count + search_count)

    :ok
  end

  @doc "The corpus retention window in days — surfaced on the Status page."
  @spec retention_days() :: pos_integer()
  def retention_days, do: @retention_days

  # Quality atoms are a closed two-value set (`Search.Quality.t()`) —
  # explicit clauses both ways so a bad row can never mint an atom.
  defp quality_to_string(:uhd_4k), do: "uhd_4k"
  defp quality_to_string(:hd_1080p), do: "hd_1080p"
  defp quality_to_string(_quality), do: nil

  defp quality_from_string("uhd_4k"), do: :uhd_4k
  defp quality_from_string("hd_1080p"), do: :hd_1080p
  defp quality_from_string(_quality), do: nil

  defp protocol_to_string(:torrent), do: "torrent"
  defp protocol_to_string(:usenet), do: "usenet"
  defp protocol_to_string(_protocol), do: nil

  defp protocol_from_string("torrent"), do: :torrent
  defp protocol_from_string("usenet"), do: :usenet
  defp protocol_from_string(_protocol), do: nil

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
      grabs: candidate.grabs,
      publish_date: candidate.publish_date,
      protocol: protocol_from_string(candidate.protocol),
      imdb_id: candidate.imdb_id,
      tmdb_id: candidate.tmdb_id,
      tvdb_id: candidate.tvdb_id,
      info_hash: candidate.info_hash,
      magnet_url: candidate.magnet_url,
      download_url: candidate.download_url
    }
  end
end
