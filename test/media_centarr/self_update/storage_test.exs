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
        body: "Fix bug. Add feature."
      }

      assert :ok = Storage.put_latest_known(release, :update_available)

      assert {:ok, %{release: persisted, classification: :update_available}} =
               Storage.get_latest_known()

      assert persisted.version == "0.7.1"
      assert persisted.tag == "v0.7.1"
      assert persisted.published_at == ~U[2026-04-19 12:00:00Z]
      assert persisted.html_url =~ "v0.7.1"
      assert persisted.body == "Fix bug. Add feature."
    end

    test "stores the full body as-given (no truncation at the Storage layer)" do
      long_body = String.duplicate("x", 4_000)

      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body: long_body
      }

      :ok = Storage.put_latest_known(release, :update_available)
      assert {:ok, %{release: persisted}} = Storage.get_latest_known()
      assert persisted.body == long_body
    end

    test "falls back to legacy body_excerpt rows for installs upgraded mid-rename" do
      # Simulate a Settings.Entry row written by the pre-rename release.
      MediaCentarr.Settings.find_or_create_entry!(%{
        key: "update.latest_known",
        value: %{
          "version" => "0.8.0",
          "tag" => "v0.8.0",
          "published_at" => "2026-04-17T00:00:00Z",
          "html_url" => "https://github.com/x/x/releases/tag/v0.8.0",
          "body_excerpt" => "legacy notes",
          "classification" => "up_to_date"
        }
      })

      assert {:ok, %{release: %{body: "legacy notes"}}} = Storage.get_latest_known()
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

  describe "record_check_result/1" do
    test "dual-writes a successful release to Settings.Entry + :persistent_term" do
      release = %{
        version: "9.9.9",
        tag: "v9.9.9",
        published_at: ~U[2050-01-01 00:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v9.9.9",
        body: "Notes here."
      }

      assert {:ok, classification, ^release} = Storage.record_check_result({:ok, release})
      assert classification in [:update_available, :up_to_date, :ahead_of_release]

      # Durable store is updated.
      assert {:ok, %{release: persisted}} = Storage.get_latest_known()
      assert persisted.version == "9.9.9"
      assert {:ok, %DateTime{}} = Storage.get_last_check_at()

      # Hot-path cache is updated — this is what prevents the v0.8.0
      # regression where manual checks refreshed only the cache while
      # Settings.Entry kept the old value.
      assert {:fresh, {:ok, %{version: "9.9.9"}}} = UpdateChecker.cached_latest_release()
    end

    test "does not persist on failure but does cache the error result" do
      assert {:error, :not_found} = Storage.record_check_result({:error, :not_found})

      assert Storage.get_latest_known() == :none
      assert Storage.get_last_check_at() == :none
      assert {:fresh, {:error, :not_found}} = UpdateChecker.cached_latest_release()
    end
  end

  describe "hydrate_cache/0" do
    test "populates the :persistent_term cache from persisted Settings.Entry" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body: ""
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
