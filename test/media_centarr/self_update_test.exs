defmodule MediaCentarr.SelfUpdateTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.SelfUpdate
  alias MediaCentarr.SelfUpdate.{Storage, UpdateChecker}

  setup do
    # boot!/0 can enqueue a CheckerJob that runs inline in the test
    # Oban config. Install a stub client so any such job uses the stub
    # instead of the real GitHub API.
    Req.Test.stub(:github_releases_facade, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)

    Req.Test.set_req_test_from_context(%{async: false})

    client = Req.new(plug: {Req.Test, :github_releases_facade}, retry: false)
    :persistent_term.put({UpdateChecker, :client}, client)
    Req.Test.allow(:github_releases_facade, self(), self())

    UpdateChecker.clear_cache()

    on_exit(fn ->
      :persistent_term.erase({UpdateChecker, :client})
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  describe "subscribe/0" do
    test "subscribes the caller to the self_update status topic" do
      :ok = SelfUpdate.subscribe()

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.self_update_status(),
        {:check_complete, {:up_to_date, %{version: "0.7.0"}}}
      )

      assert_receive {:check_complete, {:up_to_date, %{version: "0.7.0"}}}
    end
  end

  describe "boot!/0" do
    test "hydrates the :persistent_term cache from persisted state" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1",
        body: ""
      }

      :ok = Storage.put_latest_known(release, :update_available)
      # Mark last_check_at as recent so boot!/0 doesn't enqueue a fresh
      # check that would overwrite the hydrated cache.
      :ok = Storage.put_last_check_at(DateTime.utc_now())
      UpdateChecker.clear_cache()

      :ok = SelfUpdate.boot!()

      assert {:fresh, {:ok, %{version: "0.7.1"}}} = UpdateChecker.cached_latest_release()
    end

    test "is safe to call when nothing is persisted" do
      # Mark a recent check so the stale guard doesn't enqueue. Without
      # this the inline test-mode Oban would run the CheckerJob
      # immediately and hit the stubbed GitHub endpoint, which isn't
      # what this test is asserting.
      :ok = Storage.put_last_check_at(DateTime.utc_now())

      :ok = SelfUpdate.boot!()
      assert UpdateChecker.cached_latest_release() == :stale
    end
  end

  describe "cached_release/0" do
    test "returns the last known release or :none" do
      assert SelfUpdate.cached_release() == :none

      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v0.7.1"
      }

      UpdateChecker.cache_result({:ok, release})

      assert {:ok, ^release} = SelfUpdate.cached_release()
    end
  end
end
