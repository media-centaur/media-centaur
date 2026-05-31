defmodule MediaCentaur.ErrorReports.BucketsTest do
  # DataCase (non-async → shared sandbox) because Buckets now persists through
  # the durable Store. Assertions key on a per-test unique fingerprint so the
  # app's global Buckets (also subscribed to the log stream) can't contaminate
  # them.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.{Bucket, Buckets, Capture, Fingerprint, Store}
  alias MediaCentaur.Topics

  setup do
    # Large persist window so the durable-write throttle is deterministic in
    # tests: a repeat coalesces and no periodic flush fires mid-test. terminate/2
    # still flushes pending writes on stop_supervised!.
    start_supervised!({Buckets, name: :buckets_test, persist_window_ms: 60_000})
    :ok
  end

  # Letter-only token: the redactor collapses 3+ digit runs, so a numeric id
  # would merge distinct test fingerprints. Map each digit to a letter instead.
  defp uniq do
    System.unique_integer([:positive])
    |> Integer.to_string()
    |> String.to_charlist()
    |> Enum.map_join(fn digit -> <<digit - ?0 + ?a>> end)
  end

  defp entry(overrides) do
    Entry.new(
      Map.merge(
        %{
          id: System.unique_integer([:positive]),
          timestamp: DateTime.utc_now(),
          level: :error,
          component: :tmdb,
          message: "boom",
          metadata: %{}
        },
        Map.new(overrides)
      )
    )
  end

  defp fingerprint_of(component, message), do: Fingerprint.fingerprint(component, message).key

  describe "capture + cache" do
    test "an error is cached and durably persisted" do
      message = "tmdb failed #{uniq()}"
      fingerprint = fingerprint_of(:tmdb, message)

      Buckets.ingest(:buckets_test, entry(message: message))

      assert %Bucket{count: 1, severity: :error} = Buckets.get_bucket(:buckets_test, fingerprint)
      assert %{count: 1, origin: :log} = Store.get_incident_by_fingerprint(fingerprint)
    end

    test "warnings are captured too" do
      message = "slow query #{uniq()}"
      fingerprint = fingerprint_of(:library, message)

      Buckets.ingest(:buckets_test, entry(component: :library, level: :warning, message: message))

      assert %Bucket{severity: :warning} = Buckets.get_bucket(:buckets_test, fingerprint)
    end

    test "info and debug are ignored — neither cached nor persisted" do
      message = "fyi #{uniq()}"
      fingerprint = fingerprint_of(:tmdb, message)

      Buckets.ingest(:buckets_test, entry(level: :info, message: message))

      assert Buckets.get_bucket(:buckets_test, fingerprint) == nil
      assert Store.get_incident_by_fingerprint(fingerprint) == nil
    end

    test "a repeated fingerprint counts in cache immediately but coalesces the durable write" do
      message = "duplicate #{uniq()}"
      fingerprint = fingerprint_of(:tmdb, message)

      Buckets.ingest(:buckets_test, entry(message: message))
      Buckets.ingest(:buckets_test, entry(message: message))

      # The cache reflects both occurrences right away...
      assert %Bucket{count: 2} = Buckets.get_bucket(:buckets_test, fingerprint)
      # ...but the durable incident shows only the first; the second is deferred
      # by the per-fingerprint throttle until the next flush.
      assert %{count: 1} = Store.get_incident_by_fingerprint(fingerprint)
    end

    test "the sandbox-disconnect noise pattern is dropped, not captured" do
      message =
        "Exqlite.Connection disconnected: ** (DBConnection.ConnectionError) owner exited " <>
          "Client is still using a connection from owner (Ecto.Adapters.SQL.Sandbox)"

      fingerprint = fingerprint_of(:ecto, message)
      Buckets.ingest(:buckets_test, entry(component: :ecto, message: message))

      assert Buckets.get_bucket(:buckets_test, fingerprint) == nil
      assert Store.get_incident_by_fingerprint(fingerprint) == nil
    end
  end

  describe "durability" do
    test "rebuilds the cache from the store on boot" do
      message = "persisted before boot #{uniq()}"
      fingerprint = fingerprint_of(:pipeline, message)

      # Seed durably from the test process (sandbox owner), then start a fresh
      # Buckets and confirm its boot rebuild surfaces the incident.
      {:ok, _incident} =
        Capture.persist_entry(entry(component: :pipeline, level: :warning, message: message))

      start_supervised!(Supervisor.child_spec({Buckets, name: :buckets_boot}, id: :buckets_boot))

      assert %Bucket{count: 1, severity: :warning} =
               Buckets.get_bucket(:buckets_boot, fingerprint)
    end
  end

  describe "durable write throttle" do
    test "flushes coalesced occurrences durably on graceful shutdown" do
      message = "coalesced #{uniq()}"
      fingerprint = fingerprint_of(:tmdb, message)

      for _ <- 1..3, do: Buckets.ingest(:buckets_test, entry(message: message))

      # Cache has all three; durable store has only the first (two deferred).
      assert %Bucket{count: 3} = Buckets.get_bucket(:buckets_test, fingerprint)
      assert %{count: 1} = Store.get_incident_by_fingerprint(fingerprint)

      # Graceful stop runs terminate/2, which flushes the pending two.
      stop_supervised!(Buckets)

      assert %{count: 3} = Store.get_incident_by_fingerprint(fingerprint)
    end
  end

  describe "broadcast" do
    test "emits a throttled :buckets_changed after an ingest" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())

      Buckets.ingest(:buckets_test, entry(message: "broadcast me #{uniq()}"))

      assert_receive {:buckets_changed, buckets}, 1_500
      assert is_list(buckets)
    end
  end
end
