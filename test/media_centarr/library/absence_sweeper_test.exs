defmodule MediaCentarr.Library.AbsenceSweeperTest do
  @moduledoc """
  Cross-context contract test for the TTL durability invariant: a
  watch drive that is currently unavailable must not lose its data,
  no matter how long it has been offline.

  Replaces the pre-Phase-6 `Watcher.DurabilityIntegrationTest`,
  which exercised `Watcher.AbsencePolicy` and `Watcher.KnownFile`
  rows. Phase 6 of the library-presence-unification campaign moved
  TTL purge to `Library.AbsenceSweeper` operating on
  `Library.FilePresence`; cascade-delete via the Phase-3 FK now
  removes `WatchedFile` / `ExtraFile` rows.

  Asserts on observable state — `FilePresence` / `WatchedFile` /
  `Movie` row counts — never on internals.

  Regression guard for the user-reported scenario: app starts,
  drive is unmounted, days pass, drive comes back. Entities must
  survive the silence.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  import Ecto.Query

  alias MediaCentarr.Library.{AbsenceSweeper, FilePresence, Movie, WatchedFile}
  alias MediaCentarr.Repo

  setup do
    original_ttl = MediaCentarr.Config.get(:file_absence_ttl_days)
    on_exit(fn -> if original_ttl, do: put_ttl_days(original_ttl) end)
    :ok
  end

  test "60 days unavailable → no FilePresence, WatchedFile, or Movie row destroyed" do
    movie = create_standalone_movie(%{name: "Vanishing Drive Movie"})
    watched_file = create_linked_file(%{movie_id: movie.id, watch_dir: "/mnt/cold-storage"})

    # 60 days pass with the drive still offline.
    backdate_last_seen(watched_file.file_path, days_ago: 60)
    put_ttl_days(30)

    # AbsenceSweeper.purge_expired called with [] — the drive is
    # not in the live watcher's available list while it's unavailable.
    assert {0, []} = AbsenceSweeper.purge_expired([])

    # Give the (non-existent) cascade a moment to NOT run.
    Process.sleep(150)

    # Every row is intact.
    assert Repo.get_by(FilePresence, file_path: watched_file.file_path)
    assert Repo.get_by(WatchedFile, id: watched_file.id)
    assert Repo.get(Movie, movie.id)
  end

  test "remount → files reset → genuine deletion (drive up + file still missing) does cascade" do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_file_events())

    movie = create_standalone_movie(%{name: "Eventually Missing Movie"})
    watched_file = create_linked_file(%{movie_id: movie.id, watch_dir: "/mnt/recoverable"})

    # Drive offline → 90 days of staleness accumulate.
    backdate_last_seen(watched_file.file_path, days_ago: 90)
    put_ttl_days(30)

    # Drive remounts. AbsenceSweeper resets last_seen_at for files
    # in that dir — production wiring is the
    # `:dir_state_changed → :available` handler; here we invoke the
    # primitive directly to keep the test synchronous.
    assert FilePresence.reset_last_seen_for_dir("/mnt/recoverable") == 1

    # First TTL check immediately after remount: clock just reset,
    # so the file is well within the window even though the drive
    # is now available. Nothing is purged.
    assert {0, []} = AbsenceSweeper.purge_expired(["/mnt/recoverable"])
    Process.sleep(50)
    assert Repo.get(Movie, movie.id)

    # 31 more days elapse with the drive up and the file still
    # missing on every scan. NOW it's a confirmed deletion.
    backdate_last_seen(watched_file.file_path, days_ago: 31)

    assert {1, [path]} = AbsenceSweeper.purge_expired(["/mnt/recoverable"])
    assert path == watched_file.file_path

    # Cascade-delete via the Phase-3 FK removes the WatchedFile;
    # the {:files_removed, ...} broadcast triggers FileEventHandler
    # (running in the test supervision tree), which cascades the
    # rest of the entity (Movie, extras, etc.).
    assert_receive {:files_removed, [^path]}, 500

    eventually(fn ->
      Repo.get(Movie, movie.id) == nil and
        Repo.get(WatchedFile, watched_file.id) == nil and
        Repo.get_by(FilePresence, file_path: path) == nil
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

  defp backdate_last_seen(file_path, days_ago: days) do
    at = DateTime.add(DateTime.utc_now(), -days, :day)

    {1, _} =
      Repo.update_all(
        from(p in FilePresence, where: p.file_path == ^file_path),
        set: [last_seen_at: at]
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
