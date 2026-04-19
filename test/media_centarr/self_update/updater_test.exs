defmodule MediaCentarr.SelfUpdate.UpdaterTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.SelfUpdate.{Updater, UpdateChecker}
  alias MediaCentarr.Topics

  # Test doubles — records calls, returns canned results.
  defmodule FakeDownloader do
    def run(tarball_url, sha256_url, opts) do
      send(test_pid(), {:downloader_called, tarball_url, sha256_url, opts})
      progress_fn = Keyword.get(opts, :progress_fn, fn _, _ -> :ok end)
      _ = progress_fn.(0, 1000)
      _ = progress_fn.(1000, 1000)
      target = Keyword.fetch!(opts, :target_dir)
      filename = Keyword.fetch!(opts, :filename)
      {:ok, %{tarball_path: Path.join(target, filename), sha256: String.duplicate("a", 64)}}
    end

    defp test_pid, do: :persistent_term.get({__MODULE__, :test_pid})
  end

  defmodule FailingDownloader do
    def run(_tarball_url, _sha256_url, _opts), do: {:error, :checksum_mismatch}
  end

  defmodule FakeStager do
    def extract(tarball, target_dir, _opts \\ []) do
      send(test_pid(), {:stager_called, tarball, target_dir})
      {:ok, target_dir}
    end

    defp test_pid, do: :persistent_term.get({FakeDownloader, :test_pid})
  end

  defmodule FakeHandoff do
    def spawn_detached(staged_root, _opts \\ []) do
      send(test_pid(), {:handoff_called, staged_root})
      :ok
    end

    defp test_pid, do: :persistent_term.get({FakeDownloader, :test_pid})
  end

  setup do
    :persistent_term.put({FakeDownloader, :test_pid}, self())
    UpdateChecker.clear_cache()

    on_exit(fn ->
      :persistent_term.erase({FakeDownloader, :test_pid})
      UpdateChecker.clear_cache()
    end)

    :ok
  end

  defp valid_release do
    %{
      version: "99.0.0",
      tag: "v99.0.0",
      published_at: ~U[2099-01-01 00:00:00Z],
      html_url: "https://github.com/media-centarr/media-centarr/releases/tag/v99.0.0",
      body_excerpt: ""
    }
  end

  defp start_updater(name, opts \\ []) do
    default_opts = [
      name: name,
      downloader: FakeDownloader,
      stager: FakeStager,
      handoff: FakeHandoff,
      staging_root: Path.join(System.tmp_dir!(), "updater-test-#{System.unique_integer([:positive])}")
    ]

    {:ok, pid} = Updater.start_link(Keyword.merge(default_opts, opts))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  describe "apply_pending/1" do
    test "returns {:error, :no_update_pending} when the cache has no release" do
      name = :updater_no_pending
      start_updater(name)
      assert {:error, :no_update_pending} = Updater.apply_pending(name)
    end

    test "returns {:error, :no_update_pending} when the cached release is :ahead_of_release" do
      # Current version is higher than the cached release → :ahead_of_release
      ahead_release = %{valid_release() | version: "0.0.1", tag: "v0.0.1"}
      UpdateChecker.cache_result({:ok, ahead_release})

      name = :updater_ahead
      start_updater(name)
      assert {:error, :no_update_pending} = Updater.apply_pending(name)
    end

    test "runs the full pipeline when a valid update is pending" do
      UpdateChecker.cache_result({:ok, valid_release()})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_progress())

      name = :updater_happy
      start_updater(name)

      assert :ok = Updater.apply_pending(name)

      # Downloader invoked with template URLs (not from API response fields).
      assert_receive {:downloader_called, tarball_url, sha256_url, _opts}, 1_000

      assert tarball_url ==
               "https://github.com/media-centarr/media-centarr/releases/download/v99.0.0/media-centarr-99.0.0-linux-x86_64.tar.gz"

      assert sha256_url ==
               "https://github.com/media-centarr/media-centarr/releases/download/v99.0.0/SHA256SUMS"

      assert_receive {:stager_called, _tarball, _target}, 1_000
      assert_receive {:handoff_called, _staged_root}, 1_000

      # Progress events flow through the self_update:progress topic.
      assert_receive {:progress, :preparing, _}, 1_000
      assert_receive {:progress, :downloading, _}, 1_000
      assert_receive {:progress, :extracting, _}, 1_000
      assert_receive {:progress, :handing_off, _}, 1_000
      assert_receive {:progress, :done, _}, 1_000
    end

    test "returns {:error, :already_running} on concurrent applies" do
      UpdateChecker.cache_result({:ok, valid_release()})

      # Downloader that blocks until told to proceed.
      test_pid = self()

      defmodule BlockingDownloader do
        def run(_tarball_url, _sha256_url, opts) do
          test_pid = :persistent_term.get({__MODULE__, :test_pid})
          send(test_pid, {:blocking_started, self()})

          receive do
            :proceed -> :ok
          after
            5_000 -> :timeout
          end

          target = Keyword.fetch!(opts, :target_dir)
          filename = Keyword.fetch!(opts, :filename)
          {:ok, %{tarball_path: Path.join(target, filename), sha256: String.duplicate("a", 64)}}
        end
      end

      :persistent_term.put({BlockingDownloader, :test_pid}, test_pid)

      name = :updater_concurrent
      start_updater(name, downloader: BlockingDownloader)

      assert :ok = Updater.apply_pending(name)
      assert_receive {:blocking_started, blocker_pid}, 1_000

      assert {:error, :already_running} = Updater.apply_pending(name)

      send(blocker_pid, :proceed)
    end

    test "transitions to :failed and broadcasts when the downloader errors" do
      UpdateChecker.cache_result({:ok, valid_release()})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_progress())

      name = :updater_download_fail
      start_updater(name, downloader: FailingDownloader)

      assert :ok = Updater.apply_pending(name)
      assert_receive {:apply_failed, {:download, :checksum_mismatch}}, 1_000

      # After failure, the state machine returns to idle-ready-to-retry.
      %{phase: phase} = Updater.status(name)
      assert phase in [:failed, :idle]
    end

    # Regression: a previous implementation treated `:failed` as
    # "apply in progress" and returned `{:error, :already_running}`,
    # wedging the GenServer until the BEAM restarted. A new apply_pending
    # call after a failure must reset and start a fresh attempt.
    test "allows a retry after a previous failure" do
      UpdateChecker.cache_result({:ok, valid_release()})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_progress())

      name = :updater_retry_after_fail
      # Use a process-dictionary switch so the first apply fails and the
      # second (retry) succeeds, exercising the exact :failed → :preparing
      # transition the UI depends on.
      :persistent_term.put({__MODULE__, :toggle_download_fails}, true)

      defmodule ToggleDownloader do
        def run(_tarball_url, _sha256_url, opts) do
          key = {MediaCentarr.SelfUpdate.UpdaterTest, :toggle_download_fails}

          if :persistent_term.get(key, false) do
            :persistent_term.put(key, false)
            {:error, :simulated_failure}
          else
            target = Keyword.fetch!(opts, :target_dir)
            filename = Keyword.fetch!(opts, :filename)
            {:ok, %{tarball_path: Path.join(target, filename), sha256: String.duplicate("a", 64)}}
          end
        end
      end

      start_updater(name, downloader: ToggleDownloader)

      assert :ok = Updater.apply_pending(name)
      assert_receive {:apply_failed, {:download, :simulated_failure}}, 1_000

      # Second attempt must not be rejected as already-running.
      assert :ok = Updater.apply_pending(name)
      assert_receive {:progress, :done, _}, 1_000
    end

    test "allows a retry after a previous :done (handoff survived-BEAM case)" do
      UpdateChecker.cache_result({:ok, valid_release()})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.self_update_progress())

      name = :updater_retry_after_done
      start_updater(name)

      assert :ok = Updater.apply_pending(name)
      assert_receive {:progress, :done, _}, 1_000

      # Don't depend on a race for the state read — assert via the
      # public retry path instead. If :done were blocking, this second
      # call would return {:error, :already_running}.
      assert :ok = Updater.apply_pending(name)
    end

    test "rejects a release whose cached tag somehow fails regex validation" do
      bad_release = %{valid_release() | tag: "not-a-tag"}
      UpdateChecker.cache_result({:ok, bad_release})

      name = :updater_bad_tag
      start_updater(name)

      assert {:error, :invalid_tag} = Updater.apply_pending(name)
    end
  end

  describe "status/1" do
    test "returns :idle when no apply has been attempted" do
      name = :updater_status
      start_updater(name)
      assert %{phase: :idle} = Updater.status(name)
    end
  end
end
