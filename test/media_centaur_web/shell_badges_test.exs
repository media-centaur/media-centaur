defmodule MediaCentaurWeb.ShellBadgesTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

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

    test "relevant?/1 accepts the source events feeding the three counts" do
      assert ShellBadges.relevant?({:file_added, "id"})
      assert ShellBadges.relevant?({:file_reviewed, "id"})
      assert ShellBadges.relevant?({:group_approved, "key", 2})
      assert ShellBadges.relevant?({:reconciliation_updated})
      assert ShellBadges.relevant?({:buckets_changed, []})
      assert ShellBadges.relevant?({:setting_changed, "diagnostics_seen_at", %{}})
      refute ShellBadges.relevant?({:setting_changed, "unrelated_key", %{}})
      refute ShellBadges.relevant?(:unrelated_noise)
    end
  end
end
