defmodule MediaCentaurWeb.ShellBadgesTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.ErrorReports.Fingerprint
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Topics
  alias MediaCentaurWeb.ShellBadges

  setup do
    on_exit(fn -> ShellBadges.reset_cache() end)
    :ok
  end

  describe "counts projection" do
    test "refresh_cache stores counts readable via counts/0" do
      create_pending_file()

      assert :ok = ShellBadges.refresh_cache()

      counts = ShellBadges.counts()
      assert counts.review_pending == 1
      assert counts.mapping_pending == 0
      assert is_integer(counts.diagnostics_unseen)
    end

    test "counts/0 falls back to a live computation when nothing is cached" do
      create_pending_file()
      create_pending_file()

      assert ShellBadges.counts().review_pending == 2
    end

    test "cached counts win over the live values until the next refresh" do
      assert :ok = ShellBadges.refresh_cache()
      assert ShellBadges.counts().review_pending == 0

      create_pending_file()
      # Still the cached snapshot — the worker refresh (event-driven in
      # prod) is what advances it.
      assert ShellBadges.counts().review_pending == 0

      assert :ok = ShellBadges.refresh_cache()
      assert ShellBadges.counts().review_pending == 1
    end

    test "refresh_cache broadcasts the derived update" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.shell_badges())

      assert :ok = ShellBadges.refresh_cache()

      assert_receive {:shell_badges_updated}
    end

    test "relevant?/1 accepts the source events feeding the counts" do
      assert ShellBadges.relevant?({:file_added, %FileAdded{pending_file_id: "id"}})
      assert ShellBadges.relevant?({:file_reviewed, %FileReviewed{pending_file_id: "id"}})
      assert ShellBadges.relevant?({:group_approved, %GroupApproved{group_key: "key", count: 2}})
      assert ShellBadges.relevant?({:reconciliation_updated})
      assert ShellBadges.relevant?({:buckets_changed, []})
      assert ShellBadges.relevant?({:setting_changed, "diagnostics_seen_at", %{}})
      refute ShellBadges.relevant?({:setting_changed, "unrelated_key", %{}})
      refute ShellBadges.relevant?(:unrelated_noise)
    end
  end

  describe "status_errors count" do
    # Letter-only token: the redactor collapses 3+ digit runs, so a numeric
    # id would merge distinct test fingerprints (same trick as BucketsTest).
    defp uniq do
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.to_charlist()
      |> Enum.map_join(fn digit -> <<digit - ?0 + ?a>> end)
    end

    # Ingests into the app's global bucket cache (the one `compute_counts`
    # reads); the returned fingerprint must be dismissed on exit so the
    # in-memory cache doesn't leak into later tests.
    defp ingest_global(level, message) do
      entry =
        Entry.new(%{
          id: System.unique_integer([:positive]),
          timestamp: DateTime.utc_now(),
          level: level,
          component: :pipeline,
          message: message,
          metadata: %{}
        })

      Buckets.ingest(entry)

      fingerprint = Fingerprint.fingerprint(:pipeline, message).key
      on_exit(fn -> ErrorReports.dismiss([fingerprint]) end)

      # ingest/2 is a cast; the follow-up call serializes on the GenServer
      # so the bucket is guaranteed cached before we assert.
      assert %ErrorReports.Bucket{} = Buckets.get_bucket(fingerprint)
      fingerprint
    end

    test "error buckets raise the count; warning-only buckets don't" do
      baseline = ShellBadges.counts().status_errors

      ingest_global(:error, "pipeline exploded #{uniq()}")
      assert ShellBadges.counts().status_errors == baseline + 1

      ingest_global(:warning, "pipeline grumbled #{uniq()}")
      assert ShellBadges.counts().status_errors == baseline + 1
    end
  end

  describe "Status nav error dot render" do
    test "shows the red dot on the Status entry while an error bucket is live" do
      ingest_global(:error, "watcher exploded #{uniq()}")

      {:ok, view, _html} = live(build_conn(), ~p"/history")

      assert has_element?(view, "#sidebar-status-error-dot")
    end

    test "no dot without error-severity buckets" do
      # Buckets is a global singleton; earlier tests that log real errors can
      # leave error buckets live. Dismiss them so the refute reflects only
      # this test's state.
      leaked =
        for %{severity: severity, fingerprint: fingerprint} <- Buckets.list_buckets(),
            severity in [:error, :critical],
            do: fingerprint

      ErrorReports.dismiss(leaked)

      ingest_global(:warning, "watcher grumbled #{uniq()}")

      {:ok, view, _html} = live(build_conn(), ~p"/history")

      refute has_element?(view, "#sidebar-status-error-dot")
    end
  end
end
