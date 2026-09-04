defmodule MediaCentaur.SelfUpdateTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.SelfUpdate
  alias MediaCentaur.SelfUpdate.{Storage, UpdateChecker}

  setup do
    # boot!/0 can enqueue a CheckerJob that runs inline in the test
    # Oban config. Install a stub client so any such job uses the stub
    # instead of the real GitHub API.
    Req.Test.stub(:github, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)

    Req.Test.set_req_test_from_context(%{async: false})
    Req.Test.allow(:github, self(), self())

    UpdateChecker.clear_cache()

    on_exit(fn ->
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  describe "subscribe/0" do
    test "subscribes the caller to the self_update status topic" do
      :ok = SelfUpdate.subscribe()

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.self_update_status(),
        {:check_complete, {:up_to_date, %{version: "0.7.0"}}, :scheduled}
      )

      assert_receive {:check_complete, {:up_to_date, %{version: "0.7.0"}}, :scheduled}
    end
  end

  describe "boot!/0" do
    test "hydrates the :persistent_term cache from persisted state" do
      release = %{
        version: "0.7.1",
        tag: "v0.7.1",
        published_at: ~U[2026-04-19 12:00:00Z],
        html_url: "https://github.com/media-centaur/media-centaur/releases/tag/v0.7.1",
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
        MediaCentaur.Repo.all(
          from j in Oban.Job, where: j.worker == "MediaCentaur.SelfUpdate.CheckerJob"
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
        html_url: "https://github.com/media-centaur/media-centaur/releases/tag/v0.7.1"
      }

      UpdateChecker.cache_result({:ok, release})

      assert {:ok, ^release} = SelfUpdate.cached_release()
    end
  end

  describe "view_status/0" do
    test "returns the cached classification without contacting GitHub when fresh" do
      release = %{
        version: "99.0.0",
        tag: "v99.0.0",
        published_at: ~U[2099-01-01 00:00:00Z],
        html_url: "https://github.com/media-centaur/media-centaur/releases/tag/v99.0.0",
        body: ""
      }

      UpdateChecker.cache_result({:ok, release})

      assert {:update_available, ^release} = SelfUpdate.view_status()
      # A fresh cache is a pure read — no check is kicked.
      assert Storage.get_last_check_at() == :none
    end

    test "is a pure read — never contacts GitHub, even when the cache is stale" do
      # view_status/0 never triggers a check; the scheduled CheckerJob is the
      # single poller. A stale cache reads as idle, not as a fresh fetch.
      UpdateChecker.clear_cache()

      assert {:idle, nil} = SelfUpdate.view_status()
      assert Storage.get_last_check_at() == :none
    end
  end

  describe "run_check/1" do
    test "fetches, records, broadcasts, and returns the success outcome" do
      Req.Test.stub(:github, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{"tag_name" => "v99.0.0", "published_at" => "2099-01-01T00:00:00Z"})
        )
      end)

      :ok = SelfUpdate.subscribe()

      assert {:update_available, %{version: "99.0.0"}} = SelfUpdate.run_check()
      assert_receive {:check_started}
      assert_receive {:check_complete, {:update_available, %{version: "99.0.0"}}, :scheduled}
      assert {:ok, %DateTime{}} = Storage.get_last_check_at()
    end

    test "defaults the broadcast source to :scheduled" do
      :ok = SelfUpdate.subscribe()

      # Default stub returns 404 → :not_found, which is enough to observe source.
      assert {:error, :not_found} = SelfUpdate.run_check()
      assert_receive {:check_complete, {:error, :not_found}, :scheduled}
    end

    test "tags the broadcast with :manual when the manual path runs it" do
      :ok = SelfUpdate.subscribe()

      assert {:error, :not_found} = SelfUpdate.run_check(:manual)
      assert_receive {:check_complete, {:error, :not_found}, :manual}
    end

    test "returns and broadcasts an error outcome on failure" do
      # The default stub returns 404, which maps to :not_found.
      :ok = SelfUpdate.subscribe()

      assert {:error, :not_found} = SelfUpdate.run_check()
      assert_receive {:check_complete, {:error, :not_found}, :scheduled}
    end
  end
end
