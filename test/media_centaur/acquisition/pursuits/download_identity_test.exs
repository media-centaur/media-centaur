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

  test "captures torrent_hash + content_path onto the matched target" do
    {_pursuit, target} =
      create_pursuit_with_target(%{
        recipe_type: "prowlarr_query",
        release_title: "Sample.Release.2024.1080p-GRP"
      })

    item =
      queue_item(%{
        id: "abc123hash",
        title: "Sample.Release.2024.1080p-GRP",
        content_path: "/downloads/Sample.Release.2024.1080p-GRP.mkv"
      })

    assert :ok = DownloadIdentity.capture!(target, [item], "Sample.Release.2024.1080p-GRP")

    reloaded = reload(target)
    assert reloaded.torrent_hash == "abc123hash"
    assert reloaded.content_path == "/downloads/Sample.Release.2024.1080p-GRP.mkv"
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
end
