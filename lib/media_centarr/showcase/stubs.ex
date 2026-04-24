defmodule MediaCentarr.Showcase.Stubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Runtime HTTP stubs used by the showcase instance so the /download
  page renders rich fixture data without a live Prowlarr or
  qBittorrent backend. Activated when `MediaCentarr.Config.get(:showcase_mode)`
  returns true — `Acquisition.Prowlarr.build_client/0` and
  `Acquisition.DownloadClient.QBittorrent.default_client/0` swap their
  real HTTP clients for `Req.new(plug: ...)` wrappers that call the
  functions in this module.

  All fixtures use public-domain media (Big Buck Bunny, Metropolis,
  Nosferatu, Plan 9, Night of the Living Dead) so the marketing
  screenshots never depict piracy of copyrighted content.
  """

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
