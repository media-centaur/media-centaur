defmodule MediaCentaur.Acquisition.Pursuits.ObservationsTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query
  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, Observations}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem

  @release "Sample.Release.2024.1080p-GRP"
  @now ~U[2026-09-21 12:00:00Z]

  defp pursuit_with_target(attrs \\ %{}) do
    create_pursuit_with_target(
      Map.merge(
        %{recipe_type: "prowlarr_query", release_title: @release, status: "acquired"},
        attrs
      )
    )
  end

  defp queue_item(attrs \\ %{}) do
    struct!(%QueueItem{id: "HASH", title: @release, state: :downloading}, attrs)
  end

  defp reload(%Target{} = target), do: Repo.get!(Target, target.id)

  defp events_for(pursuit_id, kind) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id and e.kind == ^kind)
    |> order_by([e], asc: e.occurred_at)
    |> Repo.all()
  end

  defp all_events(pursuit_id) do
    Event |> where([e], e.pursuit_id == ^pursuit_id) |> Repo.all()
  end

  describe "observe!/4 — the first-sighting stamp" do
    test "a target seen at the client is stamped, and the stamp is write-once" do
      {pursuit, target} = pursuit_with_target()

      refute reload(target).first_seen_in_queue_at

      observed = Observations.observe!(pursuit, target, [queue_item()], @now)
      assert observed.first_seen_in_queue_at == @now

      later = DateTime.add(@now, 3600, :second)
      again = Observations.observe!(pursuit, observed, [queue_item(%{health: :frozen})], later)

      assert again.first_seen_in_queue_at == @now
    end

    test "a target the client has not shown is never stamped" do
      {pursuit, target} = pursuit_with_target()

      stranger = queue_item(%{id: "other", title: "Unrelated.Thing.2020-XYZ"})
      assert Observations.observe!(pursuit, target, [stranger], @now) == target

      refute reload(target).first_seen_in_queue_at
    end

    test "an unreachable client says nothing at all" do
      {pursuit, target} = pursuit_with_target()

      assert Observations.observe!(pursuit, target, :unknown, @now) == target
      refute reload(target).first_seen_in_queue_at
      assert all_events(pursuit.id) == []
    end

    test "a nil target is a no-op" do
      {pursuit, _target} = pursuit_with_target()

      assert Observations.observe!(pursuit, nil, [queue_item()], @now) == nil
    end
  end

  describe "observe!/4 — the durable file link" do
    @tag :tmp_dir
    test "captures torrent_hash and content_path from the live download", %{tmp_dir: tmp_dir} do
      {pursuit, target} = pursuit_with_target()
      content_path = Path.join(tmp_dir, "#{@release}.mkv")
      File.touch!(content_path)

      observed =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{id: "abc123hash", content_path: content_path})],
          @now
        )

      assert observed.torrent_hash == "abc123hash"
      assert observed.content_path == content_path
    end

    test "a content_path this host can't see is not pinned — the id still is" do
      # A dockerized client reports its own mount namespace (SABnzbd's history
      # storage: /downloads/completed/…). Pinning a path that doesn't exist
      # host-side poisons the write-once slot with a value that can never match
      # a library path; leaving it nil lets a later sighting fill it.
      {pursuit, target} = pursuit_with_target()

      observed =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{id: "abc123hash", content_path: "/downloads/completed/#{@release}"})],
          @now
        )

      assert observed.torrent_hash == "abc123hash"
      assert observed.content_path == nil
    end

    test "is write-once — an already-captured hash and path are not overwritten" do
      {pursuit, target} = pursuit_with_target()
      target = force_attrs(target, torrent_hash: "original", content_path: "/orig.mkv")

      observed =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{id: "original", content_path: "/different.mkv"})],
          @now
        )

      assert observed.torrent_hash == "original"
      assert observed.content_path == "/orig.mkv"
    end

    @tag :tmp_dir
    test "usenet two-phase capture — the title pins the nzo_id, completion fills the path",
         %{tmp_dir: tmp_dir} do
      # No infohash exists for a usenet grab, so the first sighting matches by
      # title and pins the nzo_id into torrent_hash; content_path only exists
      # once the job completes into SABnzbd's history, where the now-pinned id
      # matches and fills the remaining field.
      {pursuit, target} = pursuit_with_target()

      pinned =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{id: "SABnzbd_nzo_x1", protocol: :usenet, content_path: nil})],
          @now
        )

      assert pinned.torrent_hash == "SABnzbd_nzo_x1"
      assert pinned.content_path == nil

      storage = Path.join(tmp_dir, @release)
      File.mkdir_p!(storage)

      landed =
        Observations.observe!(
          pursuit,
          pinned,
          [
            queue_item(%{
              id: "SABnzbd_nzo_x1",
              protocol: :usenet,
              state: :completed,
              content_path: storage
            })
          ],
          DateTime.add(@now, 60, :second)
        )

      assert landed.torrent_hash == "SABnzbd_nzo_x1"
      assert landed.content_path == storage
    end

    test "captures content_path on a grab-time-hashed target while its torrent is live" do
      # Grab-time infohash capture populates torrent_hash BEFORE the download
      # is ever seen. The pass must still run to capture content_path from the
      # live download — paired by that hash — or the LibraryReconciler's
      # authoritative path match is starved and the pursuit orphans on
      # release-name drift.
      {pursuit, target} = pursuit_with_target(%{torrent_hash: "grabhash", content_path: nil})

      observed =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{id: "grabhash", title: "totally different name"})],
          @now
        )

      assert observed.torrent_hash == "grabhash"
      assert observed.first_seen_in_queue_at == @now
    end

    test "self-heals a no-hash target whose torrent name carries a tracker prefix" do
      release = "Sample.Show.S05E03.Every.Last.Bit.Of.It.2160p.AMZN.WEB-DL"
      {pursuit, target} = pursuit_with_target(%{release_title: release})

      observed =
        Observations.observe!(
          pursuit,
          target,
          [
            queue_item(%{
              id: "infohash903",
              title: "www.UIndex.org - Sample Show S05E03 Every Last Bit Of It 2160p AMZN WEB-DL"
            })
          ],
          @now
        )

      assert observed.torrent_hash == "infohash903"
    end

    test "matches by normalized title when separators differ" do
      {pursuit, target} = pursuit_with_target(%{release_title: "Sample Release 2024 1080p GRP"})

      observed = Observations.observe!(pursuit, target, [queue_item(%{id: "h2"})], @now)

      assert observed.torrent_hash == "h2"
    end
  end

  describe "observe!/4 — the observation windows Policy decides on" do
    test "a newly soft-stalled download opens the stall window" do
      {pursuit, target} = pursuit_with_target()

      observed = Observations.observe!(pursuit, target, [queue_item(%{health: :soft_stall})], @now)

      assert observed.stall_first_seen_at == @now
      refute observed.zero_seeders_first_seen_at
    end

    test "a window that is still open is preserved, not restamped" do
      {pursuit, target} = pursuit_with_target()

      first = Observations.observe!(pursuit, target, [queue_item(%{health: :frozen})], @now)

      second =
        Observations.observe!(
          pursuit,
          first,
          [queue_item(%{health: :frozen})],
          DateTime.add(@now, 600, :second)
        )

      assert second.stall_first_seen_at == @now
    end

    test "recovery closes both windows" do
      {pursuit, target} = pursuit_with_target()
      target = force_attrs(target, stall_first_seen_at: @now, zero_seeders_first_seen_at: @now)

      observed =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{state: :downloading, health: :healthy})],
          DateTime.add(@now, 600, :second)
        )

      refute observed.stall_first_seen_at
      refute observed.zero_seeders_first_seen_at
    end

    test "a stalled torrent opens the zero-seeders window too" do
      # qBittorrent's `stalledDL` means "no peers / no progress" — the
      # strongest dead-release signal available without a seeder count.
      {pursuit, target} = pursuit_with_target()

      observed = Observations.observe!(pursuit, target, [queue_item(%{state: :stalled})], @now)

      assert observed.stall_first_seen_at == @now
      assert observed.zero_seeders_first_seen_at == @now
    end

    test "a target absent from this tick keeps its open windows" do
      # A transient absence must not read as recovery.
      {pursuit, target} = pursuit_with_target()
      target = force_attrs(target, stall_first_seen_at: @now)

      observed = Observations.observe!(pursuit, target, [], DateTime.add(@now, 600, :second))

      assert observed.stall_first_seen_at == @now
    end
  end

  describe "observe!/4 — the timeline" do
    test "the first sighting is one DownloadStarted naming the torrent" do
      {pursuit, target} = pursuit_with_target()

      Observations.observe!(pursuit, target, [queue_item(%{id: "abc", health: :healthy})], @now)

      assert [event] = events_for(pursuit.id, "download_started")
      assert event.payload["client"] == "qbittorrent"
      assert event.payload["infohash"] == "abc"
    end

    test "a later transition is one HealthChanged carrying both axes" do
      {pursuit, target} = pursuit_with_target()

      first =
        Observations.observe!(
          pursuit,
          target,
          [queue_item(%{state: :downloading, health: :healthy})],
          @now
        )

      Observations.observe!(
        pursuit,
        first,
        [queue_item(%{state: :stalled, health: :frozen})],
        DateTime.add(@now, 600, :second)
      )

      assert [event] = events_for(pursuit.id, "health_changed")
      assert event.payload["from_state"] == "downloading"
      assert event.payload["to_state"] == "stalled"
      assert event.payload["from_health"] == "healthy"
      assert event.payload["to_health"] == "frozen"
    end

    test "an unchanged tick writes nothing and emits nothing" do
      {pursuit, target} = pursuit_with_target()
      item = queue_item(%{state: :downloading, health: :healthy})

      first = Observations.observe!(pursuit, target, [item], @now)
      before_count = length(all_events(pursuit.id))

      second = Observations.observe!(pursuit, first, [item], DateTime.add(@now, 30, :second))

      assert length(all_events(pursuit.id)) == before_count
      assert second.updated_at == first.updated_at
    end

    test "a nil health stores a real nil and converges" do
      # `Atom.to_string(nil)` is the string "nil", which once leaked into
      # payloads and UI copy as the literal word.
      {pursuit, target} = pursuit_with_target()
      item = queue_item(%{state: :other, health: nil})

      first = Observations.observe!(pursuit, target, [item], @now)
      assert first.last_queue_health == nil

      Observations.observe!(pursuit, first, [item], DateTime.add(@now, 30, :second))

      assert Enum.empty?(events_for(pursuit.id, "health_changed"))
    end

    test "a target absent from this tick preserves its observation and emits nothing" do
      {pursuit, target} = pursuit_with_target()
      first = Observations.observe!(pursuit, target, [queue_item()], @now)
      before_count = length(all_events(pursuit.id))

      second = Observations.observe!(pursuit, first, [], DateTime.add(@now, 30, :second))

      assert second.last_queue_state == "downloading"
      assert length(all_events(pursuit.id)) == before_count
    end

    test "a target with no release title and no hash pairs with nothing" do
      {pursuit, target} = pursuit_with_target(%{release_title: nil, torrent_hash: nil})

      assert Observations.observe!(pursuit, target, [queue_item()], @now) == target
      assert all_events(pursuit.id) == []
    end
  end
end
