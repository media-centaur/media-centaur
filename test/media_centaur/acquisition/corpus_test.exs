defmodule MediaCentaur.Acquisition.CorpusTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Search.{IndexerHealth, SearchResult}

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    IndexerHealth.clear_cache()

    on_exit(fn ->
      IndexerHealth.clear_cache()
    end)

    :ok
  end

  defp result(guid, attrs \\ %{}) do
    struct(
      %SearchResult{
        title: "Sample.Show.S01E01.1080p.WEB-DL",
        guid: guid,
        indexer_id: 1,
        indexer_name: "indexer-a",
        quality: :hd_1080p,
        size_bytes: 1_000_000,
        seeders: 12,
        leechers: 1,
        publish_date: "2026-06-01T00:00:00Z",
        info_hash: "abc123"
      },
      attrs
    )
  end

  describe "record!/3 + candidates_for/2" do
    test "round-trips search results through the durable corpus" do
      results = [result("guid-1"), result("guid-2", %{quality: :uhd_4k, seeders: 99})]

      Corpus.record!("Sample Show S01E01", [], results)

      candidates = Corpus.candidates_for("Sample Show S01E01")

      assert [%SearchResult{} = first, %SearchResult{} = second] = candidates
      # Ordered most-seeded first.
      assert first.guid == "guid-2"
      assert first.quality == :uhd_4k
      assert second.guid == "guid-1"
      assert second.info_hash == "abc123"
      assert second.indexer_name == "indexer-a"
    end

    test "search opts are part of the key — same term, different type, different corpus" do
      Corpus.record!("Sample Title", [year: 2010], [result("guid-2010")])
      Corpus.record!("Sample Title", [year: 2011], [result("guid-2011")])

      assert [%{guid: "guid-2010"}] = Corpus.candidates_for("Sample Title", year: 2010)
      assert [%{guid: "guid-2011"}] = Corpus.candidates_for("Sample Title", year: 2011)
      assert [] = Corpus.candidates_for("Sample Title", [])
    end

    test "re-recording upserts: mutable fields refresh, no duplicate rows" do
      Corpus.record!("Sample Show S01E01", [], [result("guid-1", %{seeders: 5})])
      Corpus.record!("Sample Show S01E01", [], [result("guid-1", %{seeders: 50})])

      assert [%{guid: "guid-1", seeders: 50}] = Corpus.candidates_for("Sample Show S01E01", [])
    end

    test "an empty result set is recorded — negative knowledge is still freshness" do
      Corpus.record!("Obscure Query", [], [])

      assert Corpus.fresh?("Obscure Query", [])
      assert [] = Corpus.candidates_for("Obscure Query", [])
    end
  end

  describe "fresh?/2" do
    test "false for a never-searched term" do
      refute Corpus.fresh?("Never Searched", [])
    end

    test "true within the freshness window, false beyond it" do
      Corpus.record!("Sample Show S01E01", [], [result("guid-1")])
      assert Corpus.fresh?("Sample Show S01E01", [])

      age_search!("Sample Show S01E01", [], minutes_ago: 45)
      refute Corpus.fresh?("Sample Show S01E01", [])
    end
  end

  describe "search/2 — consult-first (indexer citizenship)" do
    test "a fresh corpus serves without touching Prowlarr" do
      Corpus.record!("Sample Show S01E01", [], [result("guid-cached")])

      # Poison the stub: any HTTP call would fail loudly.
      Req.Test.stub(:prowlarr, fn _conn -> raise "Prowlarr was consulted despite a fresh corpus" end)

      assert {:ok, [%SearchResult{guid: "guid-cached"}]} = Corpus.search("Sample Show S01E01", [])
    end

    test "a stale corpus live-searches and records the results" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Show.S01E01.1080p",
            "guid" => "guid-live",
            "indexerId" => 1,
            "seeders" => 3
          }
        ])
      end)

      assert {:ok, [%SearchResult{guid: "guid-live"}]} = Corpus.search("Sample Show S01E01", [])

      # The live search landed in the corpus and is now fresh.
      assert Corpus.fresh?("Sample Show S01E01", [])
      assert [%{guid: "guid-live"}] = Corpus.candidates_for("Sample Show S01E01", [])
    end

    test "force: true bypasses a fresh corpus (user-initiated refresh)" do
      Corpus.record!("Sample Show S01E01", [], [result("guid-old")])

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Show.S01E01.1080p",
            "guid" => "guid-new",
            "indexerId" => 1,
            "seeders" => 3
          }
        ])
      end)

      assert {:ok, [%SearchResult{guid: "guid-new"}]} =
               Corpus.search("Sample Show S01E01", force: true)
    end

    test "a zero-result search while search is blind is not recorded as fresh knowledge" do
      # Prowlarr answers the search with an empty 200 — but every enabled
      # indexer is backed off, so nothing was actually asked (UIDR-016).
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [])

          "/api/v1/indexer" ->
            Req.Test.json(conn, [%{"id" => 1, "name" => "Indexer A", "enable" => true}])

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [%{"indexerId" => 1, "disabledTill" => "2099-01-01T00:00:00Z"}])
        end
      end)

      assert {:ok, []} = Corpus.search("Sample Show S01E01", [])

      refute Corpus.fresh?("Sample Show S01E01", [])
      # The moment-of-truth observation landed in the health cache.
      assert %IndexerHealth{state: :blind} = IndexerHealth.cached()
    end

    test "a zero-result search with live indexers records as usual" do
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [])

          "/api/v1/indexer" ->
            Req.Test.json(conn, [%{"id" => 1, "name" => "Indexer A", "enable" => true}])

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [])
        end
      end)

      assert {:ok, []} = Corpus.search("Sample Show S01E01", [])

      # A genuine zero-result answer is knowledge and stays fresh.
      assert Corpus.fresh?("Sample Show S01E01", [])
    end

    test "a live-search failure neither records nor poisons freshness" do
      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, _reason} = Corpus.search("Sample Show S01E01", [])
      refute Corpus.fresh?("Sample Show S01E01", [])
    end
  end

  describe "prune_stale!/0 (ADR-033 — delete over hide)" do
    test "removes searches and candidates beyond the retention window; keeps recent ones" do
      Corpus.record!("Old Query", [], [result("guid-old")])
      Corpus.record!("Recent Query", [], [result("guid-recent")])

      age_search!("Old Query", [], days_ago: 15)

      Corpus.prune_stale!()

      assert [] = Corpus.candidates_for("Old Query", [])
      refute Corpus.fresh?("Old Query", [])
      assert [%{guid: "guid-recent"}] = Corpus.candidates_for("Recent Query", [])
    end

    test "records its run for the Status page's retention panel" do
      Corpus.record!("Old Query", [], [result("guid-old")])
      age_search!("Old Query", [], days_ago: 15)

      Corpus.prune_stale!()

      assert %{pruned_last_run: pruned, last_ran_at: %DateTime{}} =
               MediaCentaur.Retention.get_run(:search_corpus)

      # one stale candidate + one stale search record
      assert pruned == 2
    end
  end

  # Backdates a corpus search row (and its candidates' last_seen_at) so
  # freshness/retention tests don't sleep.
  defp age_search!(term, opts, age) do
    seconds =
      case age do
        [minutes_ago: minutes] -> minutes * 60
        [days_ago: days] -> days * 86_400
      end

    past = DateTime.add(DateTime.utc_now(:second), -seconds, :second)
    key = Corpus.search_key(term, opts)

    force_where(
      from(s in Corpus.SearchRecord, where: s.search_key == ^key),
      last_searched_at: past
    )

    force_where(
      from(c in Corpus.Candidate, where: c.search_key == ^key),
      last_seen_at: past
    )
  end
end
