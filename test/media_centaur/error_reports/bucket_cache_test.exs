defmodule MediaCentaur.ErrorReports.BucketCacheTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.BucketCache
  alias MediaCentaur.ErrorReports.Fingerprint
  alias MediaCentaur.ErrorReports.Incident

  defp entry(overrides) do
    Entry.new(
      Map.merge(
        %{
          id: System.unique_integer([:positive]),
          timestamp: DateTime.utc_now(),
          level: :error,
          component: :tmdb,
          message: "rate limited",
          metadata: %{}
        },
        Map.new(overrides)
      )
    )
  end

  describe "put_entry/2" do
    test "opens a new bucket for an unseen fingerprint" do
      [bucket] =
        BucketCache.new()
        |> BucketCache.put_entry(entry(component: :tmdb, message: "rate limited"))
        |> BucketCache.to_list()

      assert %Bucket{} = bucket
      assert bucket.component == :tmdb
      assert bucket.count == 1
      assert bucket.severity == :error
      assert bucket.display_title =~ "[TMDB]"
      assert [%{message: _}] = bucket.sample_entries
    end

    test "a live bucket carries its headline from the first entry, like one rebuilt from the store" do
      cache =
        BucketCache.put_entry(
          %{},
          entry(component: :nostr, message: "lost ws://127.0.0.1:2173/: closed by relay")
        )

      [bucket] = Map.values(cache)

      assert bucket.headline == "lost ws:/<path> closed by relay"
      assert bucket.headline == MediaCentaur.ErrorReports.Headline.derive(bucket.normalized_message)
    end

    test "maps level to severity" do
      assert [%Bucket{severity: :warning}] =
               BucketCache.new()
               |> BucketCache.put_entry(entry(level: :warning, message: "slow"))
               |> BucketCache.to_list()
    end

    test "increments the count and spans first/last seen for a repeated fingerprint" do
      early = DateTime.utc_now()
      late = DateTime.add(early, 60, :second)

      [bucket] =
        BucketCache.new()
        |> BucketCache.put_entry(entry(message: "boom", timestamp: late))
        |> BucketCache.put_entry(entry(message: "boom", timestamp: early))
        |> BucketCache.to_list()

      assert bucket.count == 2
      assert DateTime.compare(bucket.first_seen, early) == :eq
      assert DateTime.compare(bucket.last_seen, late) == :eq
    end

    test "keeps at most five samples" do
      cache =
        Enum.reduce(1..10, BucketCache.new(), fn n, cache ->
          BucketCache.put_entry(
            cache,
            entry(message: "repeat", timestamp: DateTime.add(DateTime.utc_now(), n, :second))
          )
        end)

      assert [%Bucket{sample_entries: samples}] = BucketCache.to_list(cache)
      assert length(samples) == 5
    end

    test "caps the working set at max_active_buckets, dropping the least-recent" do
      cap = BucketCache.max_active_buckets()
      base = DateTime.utc_now()

      cache =
        Enum.reduce(0..cap, BucketCache.new(), fn n, cache ->
          # Letter-only token so the redactor's digit-collapsing doesn't merge
          # fingerprints; each message is distinct.
          message = "cap " <> String.duplicate("x", n + 1)

          BucketCache.put_entry(
            cache,
            entry(message: message, timestamp: DateTime.add(base, n, :second))
          )
        end)

      assert map_size(cache) == cap

      oldest_fingerprint = Fingerprint.fingerprint(:tmdb, "cap x").key
      assert BucketCache.get(cache, oldest_fingerprint) == nil
    end
  end

  describe "to_list/1" do
    test "orders buckets newest-active first" do
      base = DateTime.utc_now()

      cache =
        BucketCache.new()
        |> BucketCache.put_entry(entry(message: "old", timestamp: DateTime.add(base, -100, :second)))
        |> BucketCache.put_entry(entry(message: "new", timestamp: base))

      assert ["new", "old"] == Enum.map(BucketCache.to_list(cache), & &1.normalized_message)
    end
  end

  describe "delete/2" do
    test "removes a bucket by fingerprint" do
      cache =
        BucketCache.new()
        |> BucketCache.put_entry(entry(message: "keep"))
        |> BucketCache.put_entry(entry(message: "drop"))

      drop_fp = Fingerprint.fingerprint(:tmdb, "drop").key
      cache = BucketCache.delete(cache, drop_fp)

      assert BucketCache.get(cache, drop_fp) == nil
      assert ["keep"] == Enum.map(BucketCache.to_list(cache), & &1.normalized_message)
    end

    test "is a no-op for an unknown fingerprint" do
      cache = BucketCache.put_entry(BucketCache.new(), entry(message: "boom"))
      assert BucketCache.delete(cache, "nope") == cache
    end
  end

  describe "from_incidents/1" do
    test "projects incidents with their samples into buckets" do
      now = DateTime.utc_now()

      incident = %Incident{
        fingerprint: "fp_proj",
        component: "pipeline",
        message: "ingest failed",
        display_title: "[Pipeline] ingest failed",
        severity: :error,
        count: 7,
        first_seen: DateTime.add(now, -300, :second),
        last_seen: now
      }

      samples = [%{timestamp: now, message: "ingest failed"}]

      cache = BucketCache.from_incidents([{incident, samples}])

      assert %Bucket{count: 7, component: :pipeline, severity: :error, sample_entries: ^samples} =
               BucketCache.get(cache, "fp_proj")
    end

    test "skips incidents without a fingerprint" do
      incident = %Incident{
        fingerprint: nil,
        component: "system",
        severity: :critical,
        count: 1,
        first_seen: DateTime.utc_now(),
        last_seen: DateTime.utc_now()
      }

      assert BucketCache.from_incidents([{incident, []}]) == %{}
    end
  end
end
