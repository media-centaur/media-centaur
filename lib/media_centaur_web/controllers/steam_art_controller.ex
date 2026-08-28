defmodule MediaCentaurWeb.SteamArtController do
  @moduledoc """
  Serves Steam picker artwork from the local librarycache, falling back
  to a redirect at the flat-path Steam CDN URL.

  The picker's tiles can't hotlink the CDN alone: titles released under
  Steam's hash-addressed asset pipeline have no flat-path CDN asset
  (the hash is unknowable without the store API), so their only artwork
  is the local librarycache copy — which the browser can't reach as a
  filesystem path. This route bridges that: local file when
  `Steam.local_art_path/3` finds one (any layout), CDN redirect
  otherwise (still correct for older titles; a 404 there is no worse
  than hotlinking was).

  `root` mirrors the Apps page's `?steam_root=` override and defaults
  to `Steam.detect_root/0`.
  """
  use MediaCentaurWeb, :controller

  alias MediaCentaur.Apps.Steam

  @roles %{"banner" => :banner, "poster" => :poster}

  # sobelow_skip ["Traversal.SendFile"]
  # The served path is never request-assembled: `local_art_path/3` only
  # returns fixed role filenames under `<root>/appcache/librarycache/
  # <integer appid>/`, so the request can at most point `root` at a
  # different Steam-cache-shaped directory — on a par with the rest of
  # this unauthenticated single-user app's surface.
  def show(conn, %{"app_id" => app_id, "role" => role} = params) do
    with {:ok, role} <- Map.fetch(@roles, role),
         {app_id, ""} <- Integer.parse(app_id) do
      case local_art(params["root"], app_id, role) do
        nil ->
          redirect(conn, external: Steam.cdn_art_url(app_id, role))

        path ->
          conn
          |> put_resp_content_type(MIME.from_path(path))
          |> put_resp_header("cache-control", "public, max-age=3600")
          |> send_file(200, path)
      end
    else
      _invalid -> send_resp(conn, 404, "not found")
    end
  end

  defp local_art(root, app_id, role) do
    case root || Steam.detect_root() do
      nil -> nil
      root -> Steam.local_art_path(root, app_id, role)
    end
  end
end
