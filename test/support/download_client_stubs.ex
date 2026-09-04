defmodule MediaCentaur.DownloadClientStubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared download-client stub helpers (mirrors `TmdbStubs`).

  Configures a download-client slot in Settings; the test config routes
  each driver's requests through its `Req.Test` stub
  (`MediaCentaur.HttpClient`), so driver calls hit `:qbittorrent` /
  `:sabnzbd`. Config is restored on exit.
  """

  @doc """
  Points the configured download client at a `Req.Test` `:qbittorrent`
  stub (default stub answers `%{}` to everything — override per test
  with `Req.Test.stub(:qbittorrent, …)`). Call in test setup or test
  body; cleans up on exit automatically.
  """
  def setup_qbittorrent_client(context \\ %{}) do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, %{
        download_client_type: "qbittorrent",
        download_client_url: "http://qbit.test"
      })
    )

    Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, %{}) end)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, config)
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
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, %{
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://sab.test"
      })
    )

    Req.Test.stub(:sabnzbd, fn conn ->
      case conn.params["mode"] do
        "history" -> Req.Test.json(conn, %{"history" => %{"slots" => []}})
        _other -> Req.Test.json(conn, %{"queue" => %{"slots" => []}})
      end
    end)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, config)
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
