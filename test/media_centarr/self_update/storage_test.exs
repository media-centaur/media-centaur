defmodule MediaCentarr.SelfUpdate.StorageTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.SelfUpdate.{Storage, UpdateChecker}

  setup do
    UpdateChecker.clear_cache()
    on_exit(fn -> UpdateChecker.clear_cache() end)
    :ok
  end

  describe "put_latest_known/2 + get_latest_known/0" do
    test "round-trips a release + classification" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body_excerpt: "Fix bug. Add feature."
      }

      assert :ok = Storage.put_latest_known(release, :update_available)

      assert {:ok, %{release: persisted, classification: :update_available}} =
               Storage.get_latest_known()

      assert persisted.version == "0.7.1"
      assert persisted.tag == "v0.7.1"
      assert persisted.published_at == ~U[2026-04-19 12:00:00Z]
      assert persisted.html_url =~ "v0.7.1"
      assert persisted.body_excerpt == "Fix bug. Add feature."
    end

    test "truncates body_excerpt at 500 characters at save time" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body_excerpt: String.duplicate("x", 900)
      }

      :ok = Storage.put_latest_known(release, :update_available)
      assert {:ok, %{release: persisted}} = Storage.get_latest_known()
      assert String.length(persisted.body_excerpt) == 500
    end

    test "returns :none when nothing is persisted" do
      assert :none = Storage.get_latest_known()
    end
  end

  describe "put_last_check_at/1 + get_last_check_at/0" do
    test "round-trips an ISO8601 datetime" do
      now = DateTime.utc_now(:second)
      assert :ok = Storage.put_last_check_at(now)
      assert {:ok, ^now} = Storage.get_last_check_at()
    end

    test "returns :none when never set" do
      assert :none = Storage.get_last_check_at()
    end
  end

  describe "hydrate_cache/0" do
    test "populates the :persistent_term cache from persisted Settings.Entry" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body_excerpt: ""
      }

      :ok = Storage.put_latest_known(release, :update_available)
      UpdateChecker.clear_cache()

      :ok = Storage.hydrate_cache()

      assert {:fresh, {:ok, hydrated}} = UpdateChecker.cached_latest_release()
      assert hydrated.version == "0.7.1"
      assert hydrated.tag == "v0.7.1"
    end

    test "is a no-op when nothing is persisted" do
      :ok = Storage.hydrate_cache()
      assert UpdateChecker.cached_latest_release() == :stale
    end
  end

  describe "stale?/2" do
    test "returns true when nothing is persisted" do
      assert Storage.stale?()
    end

    test "returns true when the last check was older than the ttl" do
      old = DateTime.add(DateTime.utc_now(), -7 * 3600, :second)
      :ok = Storage.put_last_check_at(old)
      assert Storage.stale?(:timer.hours(6))
    end

    test "returns false when the last check was recent enough" do
      recent = DateTime.add(DateTime.utc_now(), -10, :second)
      :ok = Storage.put_last_check_at(recent)
      refute Storage.stale?(:timer.hours(6))
    end
  end
end
