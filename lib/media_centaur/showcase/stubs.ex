defmodule MediaCentaur.Showcase.Stubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The showcase's stand-ins for its upstreams, so a showcase-mode instance
  (`showcase_mode = true` in its override TOML) answers Prowlarr,
  qBittorrent and the TMDB API without a live backend or an API key.

  `MediaCentaur.HttpClient.new/2` passes every client it builds through
  `attach/2`, which does nothing outside showcase mode. In showcase mode it
  routes by upstream: Prowlarr and qBittorrent to the fixture plugs below,
  the TMDB API to the recorded responses of
  `MediaCentaur.Showcase.Stubs.TmdbFixtures`. Every other upstream — the
  TMDB image CDN included — stays live. Stubbed requests still go through
  the real client, so they emit telemetry and land in the request time
  series like any other traffic (see `MediaCentaur.Showcase.SyntheticTraffic`).

  All fixtures use public-domain media (Big Buck Bunny, Metropolis,
  Nosferatu, Plan 9, Night of the Living Dead) so the marketing
  screenshots never depict piracy of copyrighted content.
  """

  alias MediaCentaur.Showcase.Stubs.TmdbFixtures

  @doc """
  Routes `request` to the stand-in for `upstream` when this instance is in
  showcase mode; returns it unchanged otherwise.

  TMDB answers from `priv/showcase/tmdb/`, recording what it lacks when
  the application env sets `:showcase_tmdb_record` (`mix seed.showcase
  --record-tmdb`).
  """
  @spec attach(Req.Request.t(), atom()) :: Req.Request.t()
  def attach(%Req.Request{} = request, upstream) do
    if MediaCentaur.Settings.Config.get(:showcase_mode),
      do: route(request, upstream),
      else: request
  end

  defp route(request, :prowlarr), do: Req.merge(request, plug: &prowlarr_plug/1, retry: false)
  defp route(request, :qbittorrent), do: Req.merge(request, plug: &qbittorrent_plug/1, retry: false)

  defp route(request, :tmdb) do
    root = Application.app_dir(:media_centaur, "priv/showcase/tmdb")

    TmdbFixtures.attach(request,
      authored: Path.join(root, "authored"),
      recorded: Path.join(root, "recorded"),
      record: Application.get_env(:media_centaur, :showcase_tmdb_record, false)
    )
  end

  defp route(request, _live_upstream), do: request

  # --- Prowlarr plug ---

  @doc """
  Plug entry point for stubbed Prowlarr responses. Pass to `Req.new/1`
  as `plug: &Stubs.prowlarr_plug/1`.
  """
  def prowlarr_plug(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/api/v1/search"} ->
        Req.Test.json(conn, prowlarr_search_fixtures())

      {"POST", "/api/v1/search"} ->
        # Grab endpoint — just return 200 ok with empty body.
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{}")

      {"GET", "/api/v1/indexer"} ->
        # IndexerHealth snapshot (UIDR-016): one enabled, healthy indexer so
        # the showcase never grows a "Needs attention" search card.
        Req.Test.json(conn, [%{"id" => 1, "name" => "Cinema 10.net", "enable" => true}])

      {"GET", "/api/v1/indexerstatus"} ->
        Req.Test.json(conn, [])

      _ ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, ~s({"error":"not stubbed"}))
    end
  end

  defp prowlarr_search_fixtures do
    [
      %{
        "guid" => "showcase-notld-uhd-geckos",
        "title" => "Night.of.the.Living.Dead.1968.2160p.UHD.BluRay.x265.10bit.HDR.DTS-HD.MA.5.1-GECKOS",
        "indexerId" => 1,
        "size" => 42_000_000_000,
        "seeders" => 187,
        "leechers" => 12,
        "indexer" => "Cinema 10.net",
        "publishDate" => "2025-06-15T00:00:00Z"
      },
      %{
        "guid" => "showcase-notld-criterion-remux",
        "title" => "Night.of.the.Living.Dead.1968.Criterion.Collection.1080p.BluRay.x264-REMUX",
        "indexerId" => 2,
        "size" => 14_200_000_000,
        "seeders" => 312,
        "leechers" => 8,
        "indexer" => "HD-Torrents",
        "publishDate" => "2024-11-03T00:00:00Z"
      },
      %{
        "guid" => "showcase-notld-1080p-rarbg",
        "title" => "Night.of.the.Living.Dead.1968.1080p.BluRay.H264.AAC-RARBG",
        "indexerId" => 3,
        "size" => 2_100_000_000,
        "seeders" => 1204,
        "leechers" => 43,
        "indexer" => "1337x",
        "publishDate" => "2023-02-18T00:00:00Z"
      },
      %{
        "guid" => "showcase-notld-720p-handjob",
        "title" => "Night.of.the.Living.Dead.1968.REMASTERED.720p.BluRay.x264-HANDJOB",
        "indexerId" => 4,
        "size" => 1_300_000_000,
        "seeders" => 456,
        "leechers" => 11,
        "indexer" => "TorrentGalaxy",
        "publishDate" => "2022-10-31T00:00:00Z"
      },
      %{
        "guid" => "showcase-notld-720p-cinefile",
        "title" => "Night.Of.The.Living.Dead.1968.720p.BluRay.x264-CiNEFiLE",
        "indexerId" => 5,
        "size" => 945_000_000,
        "seeders" => 89,
        "leechers" => 3,
        "indexer" => "OpenTrackr",
        "publishDate" => "2021-01-15T00:00:00Z"
      }
    ]
  end

  # --- qBittorrent plug ---

  @doc """
  Plug entry point for stubbed qBittorrent responses. Pass to `Req.new/1`
  as `plug: &Stubs.qbittorrent_plug/1`.
  """
  def qbittorrent_plug(conn) do
    case {conn.method, conn.request_path} do
      {"POST", "/api/v2/auth/login"} ->
        # Accept any credentials, set a fake session cookie, return "Ok."
        conn
        |> Plug.Conn.put_resp_header("set-cookie", "SID=showcase; Path=/")
        |> Plug.Conn.send_resp(200, "Ok.")

      {"GET", "/api/v2/torrents/info"} ->
        filter = conn.query_string |> URI.decode_query() |> Map.get("filter", "all")
        Req.Test.json(conn, qbittorrent_torrents_fixtures(filter))

      {"GET", "/api/v2/sync/maindata"} ->
        # What `QueueMonitor` actually polls. Always a full update: the
        # fixtures are static, so there is no delta to express, and
        # `Sync.apply_maindata/2` treats `full_update` as "replace".
        torrents =
          "all"
          |> qbittorrent_torrents_fixtures()
          |> Map.new(&{&1["hash"], Map.delete(&1, "hash")})

        Req.Test.json(conn, %{"rid" => 1, "full_update" => true, "torrents" => torrents})

      {"GET", "/api/v2/app/version"} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "v4.6.0")

      _ ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, ~s({"error":"not stubbed"}))
    end
  end

  defp qbittorrent_torrents_fixtures("completed"), do: []

  defp qbittorrent_torrents_fixtures(_) do
    now = System.system_time(:second)

    [
      %{
        "hash" => "showcase0000000000000000000000000000bbbb",
        "name" => "Big.Buck.Bunny.2008.2160p.UHD.BluRay.x265-GROUP",
        "progress" => 0.67,
        "dlspeed" => 89_000_000,
        "eta" => 128,
        "state" => "downloading",
        "size" => 42_000_000_000,
        "amount_left" => 13_860_000_000,
        "added_on" => now - 3 * 3600,
        "category" => "movies"
      },
      %{
        "hash" => "showcase0000000000000000000000000000metr",
        "name" => "Metropolis.1927.Criterion.Collection.2160p.UHD.BluRay.x265-REMUX",
        "progress" => 0.89,
        "dlspeed" => 120_000_000,
        "eta" => 35,
        "state" => "downloading",
        "size" => 38_000_000_000,
        "amount_left" => 4_180_000_000,
        "added_on" => now - 2 * 3600,
        "category" => "movies"
      },
      %{
        "hash" => "showcase0000000000000000000000000000nosf",
        "name" => "Nosferatu.1922.REMASTERED.1080p.BluRay.x264-HANDJOB",
        "progress" => 0.0,
        "dlspeed" => 0,
        "eta" => 8_640_000,
        "state" => "queuedDL",
        "size" => 2_400_000_000,
        "amount_left" => 2_400_000_000,
        "added_on" => now - 15 * 60,
        "category" => "movies"
      },
      %{
        "hash" => "showcase0000000000000000000000000000pln9",
        "name" => "Plan.9.from.Outer.Space.1959.1080p.BluRay.x264-CiNEFiLE",
        "progress" => 0.23,
        "dlspeed" => 45_000_000,
        "eta" => 890,
        "state" => "downloading",
        "size" => 1_800_000_000,
        "amount_left" => 1_386_000_000,
        "added_on" => now - 45 * 60,
        "category" => "movies"
      }
    ]
  end
end
