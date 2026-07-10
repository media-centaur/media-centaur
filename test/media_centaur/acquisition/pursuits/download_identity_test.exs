defmodule MediaCentaur.Acquisition.Pursuits.DownloadIdentityTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.DownloadIdentity
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Repo

  defp queue_item(attrs) do
    struct!(
      %QueueItem{id: "HASH", title: "Sample.Release.2024.1080p-GRP"},
      attrs
    )
  end

  defp reload(target), do: Repo.get!(Target, target.id)

  @tag :tmp_dir
  test "captures torrent_hash + content_path onto the matched target", %{tmp_dir: tmp_dir} do
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    content_path = Path.join(tmp_dir, "Sample.Release.2024.1080p-GRP.mkv")
    File.touch!(content_path)

    item =
      queue_item(%{
        id: "abc123hash",
        title: "Sample.Release.2024.1080p-GRP",
        content_path: content_path
      })

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample.Release.2024.1080p-GRP")

    reloaded = reload(target)
    assert reloaded.torrent_hash == "abc123hash"
    assert reloaded.content_path == content_path
  end

  test "a content_path this host can't see is not pinned — the id still is" do
    # A dockerized client reports its own mount namespace (SABnzbd's
    # history storage: /downloads/completed/…). Pinning a path that
    # doesn't exist host-side poisons the write-once slot with a value
    # that can never match a library path; leaving it nil lets a later
    # sighting (or the name-match landing) fill it with something real.
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    item =
      queue_item(%{
        id: "abc123hash",
        title: "Sample.Release.2024.1080p-GRP",
        content_path: "/downloads/completed/Sample.Release.2024.1080p-GRP"
      })

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample.Release.2024.1080p-GRP")

    reloaded = reload(target)
    assert reloaded.torrent_hash == "abc123hash"
    assert reloaded.content_path == nil
  end

  test "matches by normalized title (separators differ between release and torrent name)" do
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample Release 2024 1080p GRP"
      })

    item =
      queue_item(%{
        id: "h2",
        title: "Sample.Release.2024.1080p-GRP",
        content_path: "/downloads/x.mkv"
      })

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample Release 2024 1080p GRP")
    assert reload(target).torrent_hash == "h2"
  end

  @tag :tmp_dir
  test "usenet two-phase capture — title match pins the nzo_id, completion fills the storage path",
       %{tmp_dir: tmp_dir} do
    # Provisional usenet identity (usenet-download-client campaign):
    # no infohash exists, so the first sighting matches by title and
    # pins the nzo_id into torrent_hash; content_path only exists once
    # the job completes into SABnzbd's history (`storage`), where the
    # now-pinned id matches and fills the remaining field (when the
    # reported path is real on this host).
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    live_item =
      queue_item(%{
        id: "SABnzbd_nzo_x1",
        title: "Sample.Release.2024.1080p-GRP",
        protocol: :usenet,
        content_path: nil
      })

    assert :ok = DownloadIdentity.capture!(target, [live_item], "Sample.Release.2024.1080p-GRP")

    pinned = reload(target)
    assert pinned.torrent_hash == "SABnzbd_nzo_x1"
    assert pinned.content_path == nil

    storage = Path.join(tmp_dir, "Sample.Release.2024.1080p-GRP")
    File.mkdir_p!(storage)

    completed_item =
      queue_item(%{
        id: "SABnzbd_nzo_x1",
        title: "Sample.Release.2024.1080p-GRP",
        protocol: :usenet,
        state: :completed,
        content_path: storage
      })

    assert :ok =
             DownloadIdentity.capture!(pinned, [completed_item], "Sample.Release.2024.1080p-GRP")

    landed = reload(target)
    assert landed.torrent_hash == "SABnzbd_nzo_x1"
    assert landed.content_path == storage
  end

  test "is write-once — an already-captured hash is not overwritten" do
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    {:ok, target} =
      target
      |> Target.record_download_changeset(%{torrent_hash: "original", content_path: "/orig.mkv"})
      |> Repo.update()

    item = queue_item(%{id: "different", content_path: "/different.mkv"})

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample.Release.2024.1080p-GRP")

    reloaded = reload(target)
    assert reloaded.torrent_hash == "original"
    assert reloaded.content_path == "/orig.mkv"
  end

  test "no-ops when the target's torrent isn't in the queue" do
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    other = queue_item(%{id: "other", title: "Unrelated.Thing.2020-XYZ"})

    assert :ok = DownloadIdentity.capture!(target, [other], "Sample.Release.2024.1080p-GRP")
    assert reload(target).torrent_hash == nil
  end

  test "no-ops on :unknown queue and on nil target" do
    {_pursuit, target} = create_pursuit_with_target(%{recipe_type: "prowlarr_query"})

    assert :ok = DownloadIdentity.capture!(target, :unknown, "anything")
    assert :ok = DownloadIdentity.capture!(nil, [], "anything")
    assert reload(target).torrent_hash == nil
  end

  @tag :tmp_dir
  test "captures content_path on a grab-time-hashed target while its torrent is still live",
       %{tmp_dir: tmp_dir} do
    # Grab-time infohash capture (v0.77.2) populates torrent_hash BEFORE the
    # download is ever seen in the queue. DownloadIdentity must still run to
    # capture content_path from the live download — paired by the hash —
    # otherwise the LibraryReconciler's authoritative content_path match is
    # starved and the pursuit orphans on release-name drift (the Mortal
    # Kombat II "mkv"-token miss). The hash being present is now an asset for
    # pairing, not a reason to skip.
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP",
        torrent_hash: "grabhash",
        content_path: nil
      })

    content_path = Path.join(tmp_dir, "Sample.Release.2024.1080p-GRP.mkv")
    File.touch!(content_path)

    item =
      queue_item(%{
        id: "grabhash",
        title: "Sample.Release.2024.1080p-GRP",
        content_path: content_path
      })

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample.Release.2024.1080p-GRP")

    reloaded = reload(target)
    assert reloaded.torrent_hash == "grabhash"
    assert reloaded.content_path == content_path
  end

  test "self-heals a no-hash target whose torrent name carries a tracker prefix" do
    release = "Sample.Show.S05E03.Every.Last.Bit.Of.It.2160p.AMZN.WEB-DL"

    {_pursuit, target} =
      create_pursuit_with_target(%{recipe_type: "prowlarr_query", release_title: release})

    # The screenshot bug: torrent name is prefixed by the tracker, which
    # exact normalized-title matching could never bridge. Containment in
    # the shared matcher pairs it so the hash gets captured.
    item =
      queue_item(%{
        id: "infohash903",
        title: "www.UIndex.org - Sample Show S05E03 Every Last Bit Of It 2160p AMZN WEB-DL",
        content_path: "/downloads/Sample.Show.S05E03/"
      })

    assert :ok = DownloadIdentity.capture!(target, [item], release)

    assert reload(target).torrent_hash == "infohash903"
  end
end
