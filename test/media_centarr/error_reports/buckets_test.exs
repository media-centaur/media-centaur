defmodule MediaCentarr.ErrorReports.BucketsTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.{Bucket, Buckets}
  alias MediaCentarr.Topics

  setup do
    # Use an isolated name so tests don't collide with the app supervisor.
    start_supervised!({Buckets, name: :buckets_test, window_minutes: 60})
    :ok
  end

  defp error_entry(id, component, message, ts \\ DateTime.utc_now()) do
    Entry.new(%{
      id: id,
      timestamp: ts,
      level: :error,
      component: component,
      message: message,
      metadata: %{}
    })
  end

  describe "listing and insertion" do
    test "starts empty" do
      assert Buckets.list_buckets(:buckets_test) == []
    end

    test "records an :error entry into a fingerprinted bucket" do
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429"))

      [%Bucket{} = bucket] = Buckets.list_buckets(:buckets_test)
      assert bucket.component == :tmdb
      assert bucket.count == 1
      assert bucket.display_title =~ "[TMDB]"
    end

    test "ignores non-error entries" do
      info_entry = %{
        error_entry(1, :tmdb, "TMDB returned 429")
        | level: :info
      }

      Buckets.ingest(:buckets_test, info_entry)
      assert Buckets.list_buckets(:buckets_test) == []
    end

    test "increments the count when the same fingerprint repeats" do
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429 at 200ms"))
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "TMDB returned 429 at 500ms"))

      [bucket] = Buckets.list_buckets(:buckets_test)
      assert bucket.count == 2
    end

    test "keeps up to 5 sample_entries" do
      for i <- 1..10 do
        Buckets.ingest(:buckets_test, error_entry(i, :tmdb, "TMDB returned 429 at #{i * 100}ms"))
      end

      [bucket] = Buckets.list_buckets(:buckets_test)
      assert length(bucket.sample_entries) == 5
    end
  end

  describe "window-based eviction" do
    test "list_buckets/1 filters buckets whose last_seen is outside the window" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3_600, :second)
      new_now = DateTime.utc_now()
      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "old error", old))
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "new error", new_now))

      buckets = Buckets.list_buckets(:buckets_test)
      messages = Enum.map(buckets, & &1.normalized_message)
      assert "new error" in messages
      refute "old error" in messages
    end
  end

  describe "broadcasts" do
    test "broadcasts a throttled :buckets_changed message" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.error_reports())

      Buckets.ingest(:buckets_test, error_entry(1, :tmdb, "TMDB returned 429"))
      assert_receive {:buckets_changed, _snapshot}, 1_500

      # Rapid second insertion within throttle window: no second message
      Buckets.ingest(:buckets_test, error_entry(2, :tmdb, "TMDB returned 429"))
      refute_receive {:buckets_changed, _}, 500
    end
  end
end
