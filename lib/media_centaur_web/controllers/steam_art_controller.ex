defmodule MediaCentaurWeb.SteamArtController do
  @moduledoc """
  Serves Steam picker artwork, freshest source first.

  The picker's tiles can't hotlink a guessed CDN URL: titles on Steam's
  hash-addressed asset pipeline have no flat-path CDN asset, and both
  guessable sources (flat CDN path, local librarycache copy) go stale
  even when they exist. Banner requests therefore redirect to the
  current store URL when `SteamStore` can resolve it, then fall back to
  the local librarycache file (which the browser can't reach as a
  filesystem path), then to the legacy flat CDN path. Posters have no
  API source and start at the local copy.

  `root` mirrors the Apps page's `?steam_root=` override and defaults
  to `Steam.detect_root/0`.
  """
  use MediaCentaurWeb, :controller

  alias MediaCentaur.Apps.Steam
  alias MediaCentaur.Apps.SteamStore

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
      # Banner freshness ladder: current store URL (API) → local
      # librarycache copy → legacy flat CDN path. The guessable sources
      # both go stale for hash-addressed titles (see SteamStore);
      # posters have no API field, so they start at the local copy.
      current_url = if role == :banner, do: SteamStore.current_banner_url(app_id)

      cond do
        current_url ->
          conn
          |> put_resp_header("cache-control", "public, max-age=86400")
          |> redirect(external: current_url)

        path = local_art(params["root"], app_id, role) ->
          conn
          |> put_resp_content_type(MIME.from_path(path))
          |> put_resp_header("cache-control", "public, max-age=3600")
          |> send_file(200, path)

        true ->
          redirect(conn, external: Steam.cdn_art_url(app_id, role))
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
