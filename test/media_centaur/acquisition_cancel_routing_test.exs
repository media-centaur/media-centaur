defmodule MediaCentaur.AcquisitionCancelRoutingTest do
  # With two configured clients, a cancel must reach the client that
  # owns the download. The live queue item's protocol tag is
  # authoritative; when the item has already left the snapshot (cleanup
  # cancels arrive late), the id shape decides — SABnzbd ids are always
  # "SABnzbd_nzo_…", torrent ids are bare infohashes.
  use ExUnit.Case, async: false

  alias MediaCentaur.Acquisition
  alias MediaCentaur.DownloadClientStubs

  setup do
    DownloadClientStubs.setup_qbittorrent_client()
    DownloadClientStubs.setup_sabnzbd_client()

    test_pid = self()

    Req.Test.stub(:qbittorrent, fn conn ->
      if conn.request_path == "/api/v2/torrents/delete" do
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:qbit_delete, URI.decode_query(body)})
      end

      Req.Test.json(conn, %{})
    end)

    Req.Test.stub(:sabnzbd, fn conn ->
      if conn.params["name"] == "delete" do
        send(test_pid, {:sab_delete, conn.params})
      end

      Req.Test.json(conn, %{"status" => true})
    end)

    :ok
  end

  test "a SABnzbd id routes to the usenet client" do
    assert :ok = Acquisition.cancel_download("SABnzbd_nzo_abc123")

    assert_received {:sab_delete, %{"value" => "SABnzbd_nzo_abc123", "del_files" => "1"}}
    refute_received {:qbit_delete, _}
  end

  test "an infohash routes to the torrent client" do
    hash = "ad0352787544b70df51dc696b9e0f99add01acd4"
    assert :ok = Acquisition.cancel_download(hash)

    assert_received {:qbit_delete, %{"hashes" => ^hash}}
    refute_received {:sab_delete, _}
  end
end
