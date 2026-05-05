defmodule MediaCentarr.Watcher.AbsencePolicyTest do
  @moduledoc """
  Unit tests for the lifecycle policy that owns TTL purge of absent
  watcher files. The cross-context "drive cycle does not destroy
  entities" contract is asserted by
  `MediaCentarr.Watcher.DurabilityIntegrationTest`; this file covers
  the policy's primitives in isolation.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Repo
  alias MediaCentarr.Watcher.{AbsencePolicy, FilePresence, KnownFile}

  setup do
    # Tests reach into config to control the TTL window. We touch
    # `:persistent_term` directly (the same backing store
    # `MediaCentarr.Config.get/1` reads) to avoid writing test state
    # to the Settings DB. Restore the default after every case so
    # cross-test interactions can't carry a near-zero window into a
    # later test.
    original = MediaCentarr.Config.get(:file_absence_ttl_days)
    on_exit(fn -> if original, do: put_ttl_days(original) end)
    :ok
  end

  defp put_ttl_days(days) do
    config = :persistent_term.get({MediaCentarr.Config, :config})
    :persistent_term.put({MediaCentarr.Config, :config}, Map.put(config, :file_absence_ttl_days, days))
  end

  describe "purge_expired/1 — the durability invariant" do
    test "skips files whose watch_dir is not in the available list" do
      # Setup: an absent file long past TTL, but its drive is not in
      # the supplied available_dirs. The purge must not touch it.
      FilePresence.record_file("/media/offline/movie.mkv", "/media/offline")
      FilePresence.mark_files_absent(["/media/offline/movie.mkv"])

      backdate_absent_since("/media/offline/movie.mkv", days_ago: 60)
      put_ttl_days(30)

      assert {0, []} = AbsencePolicy.purge_expired([])
      assert {0, []} = AbsencePolicy.purge_expired(["/media/some-other-dir"])

      # File still in the table — durability preserved.
      assert Repo.get_by(KnownFile, file_path: "/media/offline/movie.mkv")
    end

    test "purges files whose watch_dir IS in the available list" do
      FilePresence.record_file("/media/online/movie.mkv", "/media/online")
      FilePresence.mark_files_absent(["/media/online/movie.mkv"])

      backdate_absent_since("/media/online/movie.mkv", days_ago: 60)
      put_ttl_days(30)

      assert {1, ["/media/online/movie.mkv"]} =
               AbsencePolicy.purge_expired(["/media/online"])

      refute Repo.get_by(KnownFile, file_path: "/media/online/movie.mkv")
    end

    test "leaves :present files alone even when their dir is available" do
      FilePresence.record_file("/media/online/present.mkv", "/media/online")

      put_ttl_days(0)
      assert {0, []} = AbsencePolicy.purge_expired(["/media/online"])

      assert Repo.get_by!(KnownFile, file_path: "/media/online/present.mkv").state == :present
    end

    test "leaves absent files within the TTL window alone" do
      FilePresence.record_file("/media/online/recent.mkv", "/media/online")
      FilePresence.mark_files_absent(["/media/online/recent.mkv"])

      # absent_since is now (~just now); cutoff is 30 days ago — file
      # is well within the window.
      put_ttl_days(30)
      assert {0, []} = AbsencePolicy.purge_expired(["/media/online"])
    end

    test "broadcasts {:files_removed, paths} when rows are deleted" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_file_events())

      FilePresence.record_file("/media/online/movie.mkv", "/media/online")
      FilePresence.mark_files_absent(["/media/online/movie.mkv"])
      backdate_absent_since("/media/online/movie.mkv", days_ago: 60)
      put_ttl_days(30)

      AbsencePolicy.purge_expired(["/media/online"])

      assert_receive {:files_removed, ["/media/online/movie.mkv"]}, 500
    end

    test "does NOT broadcast when no rows are deleted" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_file_events())

      FilePresence.record_file("/media/online/movie.mkv", "/media/online")
      FilePresence.mark_files_absent(["/media/online/movie.mkv"])
      backdate_absent_since("/media/online/movie.mkv", days_ago: 60)
      put_ttl_days(30)

      # Drive is unavailable — no purge, no broadcast.
      AbsencePolicy.purge_expired([])

      refute_receive {:files_removed, _}, 200
    end

    test "emits telemetry event with the documented metadata" do
      handler_id = "ttl-purge-test-#{:erlang.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:media_centarr, :watcher, :absence_policy, :purge],
        fn _name, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      FilePresence.record_file("/media/online/movie.mkv", "/media/online")
      FilePresence.mark_files_absent(["/media/online/movie.mkv"])
      backdate_absent_since("/media/online/movie.mkv", days_ago: 60)
      put_ttl_days(30)

      AbsencePolicy.purge_expired(["/media/online"])

      assert_receive {:telemetry, %{count: 1}, metadata}, 500
      assert metadata.paths == ["/media/online/movie.mkv"]
      assert metadata.available_dirs == ["/media/online"]
    end
  end

  describe "at_risk_summary/0" do
    test "returns one entry per dir with absent files, with count and earliest absent_since" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -45, :day)
      newer = DateTime.add(now, -10, :day)

      FilePresence.record_file("/media/drive1/a.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/b.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive2/c.mkv", "/media/drive2")
      FilePresence.record_file("/media/drive2/present.mkv", "/media/drive2")

      FilePresence.mark_files_absent([
        "/media/drive1/a.mkv",
        "/media/drive1/b.mkv",
        "/media/drive2/c.mkv"
      ])

      set_absent_since("/media/drive1/a.mkv", old)
      set_absent_since("/media/drive1/b.mkv", newer)
      set_absent_since("/media/drive2/c.mkv", newer)

      summary = AbsencePolicy.at_risk_summary()

      assert summary["/media/drive1"].file_count == 2

      assert DateTime.truncate(summary["/media/drive1"].earliest_absent_since, :second) ==
               DateTime.truncate(old, :second)

      assert summary["/media/drive2"].file_count == 1

      assert DateTime.truncate(summary["/media/drive2"].earliest_absent_since, :second) ==
               DateTime.truncate(newer, :second)
    end

    test "returns an empty map when nothing is absent" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      assert AbsencePolicy.at_risk_summary() == %{}
    end
  end

  describe ":dir_state_changed → :available handler resets the absence clock" do
    # The GenServer is running as part of the application's
    # supervision tree in test mode. We exercise the policy via the
    # PubSub channel it subscribes to — the same path production
    # broadcasts arrive on — and assert on the observable side
    # effect (KnownFile.absent_since moved forward).
    test "broadcasting :available for a dir bumps absent_since forward" do
      FilePresence.record_file("/media/recovery/movie.mkv", "/media/recovery")
      FilePresence.mark_files_absent(["/media/recovery/movie.mkv"])
      backdate_absent_since("/media/recovery/movie.mkv", days_ago: 90)

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.dir_state(),
        {:dir_state_changed, "/media/recovery", :watch_dir, :available}
      )

      # The handler spawns a Task; give it a moment to run and write.
      eventually(fn ->
        row = Repo.get_by!(KnownFile, file_path: "/media/recovery/movie.mkv")
        DateTime.diff(DateTime.utc_now(), row.absent_since, :day) < 1
      end)

      assert Repo.get_by!(KnownFile, file_path: "/media/recovery/movie.mkv").state == :absent
    end
  end

  # --- helpers ---

  defp backdate_absent_since(file_path, days_ago: days) do
    set_absent_since(file_path, DateTime.add(DateTime.utc_now(), -days, :day))
  end

  defp set_absent_since(file_path, %DateTime{} = at) do
    {1, _} =
      Repo.update_all(
        from(k in KnownFile, where: k.file_path == ^file_path),
        set: [absent_since: at]
      )
  end

  defp eventually(fun, attempts \\ 30, delay_ms \\ 20) do
    if fun.() do
      :ok
    else
      if attempts > 0 do
        Process.sleep(delay_ms)
        eventually(fun, attempts - 1, delay_ms)
      else
        flunk("eventually/3 condition never became true")
      end
    end
  end
end
