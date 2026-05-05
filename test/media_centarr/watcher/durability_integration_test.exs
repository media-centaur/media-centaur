defmodule MediaCentarr.Watcher.DurabilityIntegrationTest do
  @moduledoc """
  Cross-context contract test for the TTL durability invariant: a
  watch drive that is currently unavailable must not lose its data,
  no matter how long it has been offline.

  Spans `Watcher.AbsencePolicy` (TTL purge), `Watcher.FilePresence`
  (data primitives), `Library.FileEventHandler` (cleanup cascade
  triggered by `{:files_removed, paths}`), and `Library.EntityCascade`
  (entity destruction). Asserts on observable state — KnownFile /
  WatchedFile / Movie row counts — never on internals.

  This is the regression guard for the user-reported scenario: app
  starts, drive is unmounted, days pass, drive comes back. Entities
  must survive the silence.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.Library.{Movie, WatchedFile}
  alias MediaCentarr.Watcher.{AbsencePolicy, FilePresence, KnownFile}

  setup do
    original_ttl = MediaCentarr.Config.get(:file_absence_ttl_days)
    on_exit(fn -> if original_ttl, do: put_ttl_days(original_ttl) end)
    :ok
  end

  test "60 days unavailable → no KnownFile, WatchedFile, or Movie row destroyed" do
    movie = create_standalone_movie(%{name: "Vanishing Drive Movie"})
    watched_file = create_linked_file(%{movie_id: movie.id, watch_dir: "/mnt/cold-storage"})
    FilePresence.record_file(watched_file.file_path, "/mnt/cold-storage")

    # Drive goes offline. Files marked absent immediately, absent_since = now.
    FilePresence.mark_absent_for_watch_dir("/mnt/cold-storage")

    # 60 days pass with the drive still offline.
    backdate_absent_since(watched_file.file_path, days_ago: 60)
    put_ttl_days(30)

    # AbsencePolicy.purge_expired called with [] — the drive is not
    # in the live watcher's available list while it's unavailable.
    assert {0, []} = AbsencePolicy.purge_expired([])

    # Give the (non-existent) cascade a moment to NOT run.
    Process.sleep(150)

    # Every row is intact.
    assert Repo.get_by(KnownFile, file_path: watched_file.file_path)
    assert Repo.get_by(WatchedFile, id: watched_file.id)
    assert Repo.get(Movie, movie.id)
  end

  test "remount → files reset → genuine deletion (drive up + file still missing) does cascade" do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_file_events())

    movie = create_standalone_movie(%{name: "Eventually Missing Movie"})
    watched_file = create_linked_file(%{movie_id: movie.id, watch_dir: "/mnt/recoverable"})
    FilePresence.record_file(watched_file.file_path, "/mnt/recoverable")

    # Drive offline → mark absent → 90 days pass.
    FilePresence.mark_absent_for_watch_dir("/mnt/recoverable")
    backdate_absent_since(watched_file.file_path, days_ago: 90)
    put_ttl_days(30)

    # Drive remounts. AbsencePolicy resets the clock for absent files
    # — production wiring is the `:dir_state_changed → :available`
    # handler; here we invoke the primitive directly to keep the test
    # synchronous.
    assert FilePresence.reset_absence_clock_for_dir("/mnt/recoverable") == 1

    # First TTL check immediately after remount: clock has just been
    # reset, so the file is well within the window even though the
    # drive is now available. Nothing is purged.
    assert {0, []} = AbsencePolicy.purge_expired(["/mnt/recoverable"])
    Process.sleep(50)
    assert Repo.get(Movie, movie.id)

    # 31 more days elapse with the drive up and the file still
    # missing on every scan. NOW it's a confirmed deletion.
    backdate_absent_since(watched_file.file_path, days_ago: 31)

    assert {1, [path]} = AbsencePolicy.purge_expired(["/mnt/recoverable"])
    assert path == watched_file.file_path

    # The {:files_removed, ...} broadcast triggers FileEventHandler
    # (running in the test supervision tree), which cascades through
    # WatchedFile → entity-orphan check → EntityCascade.destroy!.
    assert_receive {:files_removed, [^path]}, 500

    eventually(fn ->
      Repo.get(Movie, movie.id) == nil and
        Repo.get(WatchedFile, watched_file.id) == nil and
        Repo.get_by(KnownFile, file_path: path) == nil
    end)
  end

  # --- helpers ---

  defp put_ttl_days(days) do
    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      Map.put(config, :file_absence_ttl_days, days)
    )
  end

  defp backdate_absent_since(file_path, days_ago: days) do
    at = DateTime.add(DateTime.utc_now(), -days, :day)

    {1, _} =
      Repo.update_all(
        from(k in KnownFile, where: k.file_path == ^file_path),
        set: [absent_since: at]
      )
  end

  defp eventually(fun, attempts \\ 50, delay_ms \\ 20) do
    cond do
      fun.() ->
        :ok

      attempts > 0 ->
        Process.sleep(delay_ms)
        eventually(fun, attempts - 1, delay_ms)

      true ->
        flunk("eventually/3 condition never became true")
    end
  end
end
