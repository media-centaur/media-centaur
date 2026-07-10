defmodule MediaCentaur.DownloadClientStubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared download-client stub helpers (mirrors `TmdbStubs`).

  Configures qBittorrent as the active driver and installs a
  `Req.Test`-backed client in `:persistent_term` so driver calls hit
  the `:qbittorrent` stub. Config and client are restored on exit.
  """

  alias MediaCentaur.Downloads.DownloadClient.QBittorrent
  alias MediaCentaur.Downloads.DownloadClient.SABnzbd

  @doc """
  Points the configured download client at a `Req.Test` `:qbittorrent`
  stub (default stub answers `%{}` to everything — override per test
  with `Req.Test.stub(:qbittorrent, …)`). Call in test setup or test
  body; cleans up on exit automatically.
  """
  def setup_qbittorrent_client(context \\ %{}) do
    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      Map.merge(config, %{
        download_client_type: "qbittorrent",
        download_client_url: "http://qbit.test"
      })
    )

    qbit_client = Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")
    :persistent_term.put({QBittorrent, :client}, qbit_client)
    Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, %{}) end)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.put({MediaCentaur.Config, :config}, config)
      QBittorrent.invalidate_client()
    end)

    context
  end

  @doc """
  Points the configured usenet client (SABnzbd) at a `Req.Test`
  `:sabnzbd` stub — the usenet-slot mirror of
  `setup_qbittorrent_client/1`. Default stub answers an empty queue +
  history; override per test with `Req.Test.stub(:sabnzbd, …)`.
  """
  def setup_sabnzbd_client(context \\ %{}) do
    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      Map.merge(config, %{
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://sab.test"
      })
    )

    sab_client = Req.new(plug: {Req.Test, :sabnzbd}, retry: false, base_url: "http://sab.test")
    :persistent_term.put({SABnzbd, :client}, sab_client)

    Req.Test.stub(:sabnzbd, fn conn ->
      case conn.params["mode"] do
        "history" -> Req.Test.json(conn, %{"history" => %{"slots" => []}})
        _other -> Req.Test.json(conn, %{"queue" => %{"slots" => []}})
      end
    end)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.put({MediaCentaur.Config, :config}, config)
      SABnzbd.invalidate_client()
    end)

    context
  end

  @doc """
  Stubs `:qbittorrent` to forward every torrent-delete request's form
  params to `test_pid` as `{:qbit_delete, params}` (other requests
  answer `%{}` silently).
  """
  def forward_deletes_to(test_pid) do
    Req.Test.stub(:qbittorrent, fn conn ->
      if conn.request_path == "/api/v2/torrents/delete" do
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:qbit_delete, URI.decode_query(body)})
      end

      Req.Test.json(conn, %{})
    end)
  end
end
