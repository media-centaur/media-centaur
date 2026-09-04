defmodule MediaCentaurWeb.SteamArtControllerTest do
  use MediaCentaurWeb.ConnCase, async: true

  defp tmp_steam_root do
    root = Path.join(System.tmp_dir!(), "mc-steam-art-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_local_banner(root, app_id, bytes) do
    hash_dir = Path.join([root, "appcache", "librarycache", to_string(app_id), "3be0683f"])
    File.mkdir_p!(hash_dir)
    File.write!(Path.join(hash_dir, "library_header.jpg"), bytes)
  end

  defp stub_store(body) do
    Req.Test.stub(:steam, fn conn -> Req.Test.json(conn, body) end)
  end

  test "banner prefers the store API's current URL over local art", %{conn: conn} do
    root = tmp_steam_root()
    write_local_banner(root, 100, "stale-local-bytes")

    stub_store(%{
      "100" => %{
        "success" => true,
        "data" => %{"header_image" => "https://cdn.test/98dd/header.jpg?t=1"}
      }
    })

    conn = get(conn, ~p"/apps/steam-art/100/banner?#{[root: root]}")

    assert redirected_to(conn, 302) == "https://cdn.test/98dd/header.jpg?t=1"
  end

  test "serves locally-cached art for the role", %{conn: conn} do
    root = tmp_steam_root()
    hash_dir = Path.join([root, "appcache", "librarycache", "100", "3be0683f"])
    File.mkdir_p!(hash_dir)
    File.write!(Path.join(hash_dir, "library_header.jpg"), "banner-bytes")

    conn = get(conn, ~p"/apps/steam-art/100/banner?#{[root: root]}")

    assert response(conn, 200) == "banner-bytes"
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
  end

  test "redirects to the Steam CDN when no local art exists", %{conn: conn} do
    root = tmp_steam_root()

    conn = get(conn, ~p"/apps/steam-art/100/banner?#{[root: root]}")

    assert redirected_to(conn, 302) ==
             "https://shared.steamstatic.com/store_item_assets/steam/apps/100/header.jpg"
  end

  test "redirects to the CDN when the root does not exist", %{conn: conn} do
    conn = get(conn, ~p"/apps/steam-art/100/poster?#{[root: "/nonexistent"]}")

    assert redirected_to(conn, 302) ==
             "https://shared.steamstatic.com/store_item_assets/steam/apps/100/library_600x900.jpg"
  end

  test "rejects a non-integer app id", %{conn: conn} do
    root = tmp_steam_root()

    conn = get(conn, "/apps/steam-art/not-an-id/banner?root=#{URI.encode_www_form(root)}")

    assert response(conn, 404)
  end

  test "rejects an unknown role", %{conn: conn} do
    root = tmp_steam_root()

    conn = get(conn, "/apps/steam-art/100/hero?root=#{URI.encode_www_form(root)}")

    assert response(conn, 404)
  end
end
