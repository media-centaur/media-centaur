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
      UpdateChecker.clear_cache()

      # Suspend Oban's inline test mode so the always-enqueued boot
      # CheckerJob doesn't run synchronously and overwrite the hydrated
      # cache. This test isolates `boot!/0`'s hydrate behaviour from
      # the concurrent fresh-check it schedules.
      Oban.Testing.with_testing_mode(:manual, fn ->
        :ok = SelfUpdate.boot!()
      end)

      assert {:fresh, {:ok, %{version: "0.7.1"}}} = UpdateChecker.cached_latest_release()
    end

    test "is safe to call when nothing is persisted" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        :ok = SelfUpdate.boot!()
      end)

      assert UpdateChecker.cached_latest_release() == :stale
    end

    test "always enqueues a fresh check so stale Storage can't survive a restart" do
      # Simulate: Storage has a recent last_check_at (the CheckerJob
      # ran within the last 6h), but with a stale release value. The
      # old boot! gated on `Storage.stale?` and would NOT have enqueued
      # a fresh check — letting the stale row survive. The new boot!
      # always enqueues.
      :ok = Storage.put_last_check_at(DateTime.utc_now())

      Oban.Testing.with_testing_mode(:manual, fn ->
        :ok = SelfUpdate.boot!()
      end)

      import Ecto.Query

      jobs =
        MediaCentarr.Repo.all(
          from j in Oban.Job, where: j.worker == "MediaCentarr.SelfUpdate.CheckerJob"
        )

      assert jobs != []
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
