defmodule MediaCentaurWeb.LegacyRedirectControllerTest do
  @moduledoc """
  Pins the backward-compat contract for routes that merged into
  `/incoming` (DDR-015): `/download` and `/upcoming` answer plain GET
  redirects (302), and the query string is preserved so deep-links keep
  their meaning — `/download?selected=<pursuit_id>` must still open the
  pursuit modal on the merged page.
  """

  use MediaCentaurWeb.ConnCase, async: false

  test "GET /download redirects to /incoming", %{conn: conn} do
    conn = get(conn, "/download")

    assert redirected_to(conn, 302) == "/incoming"
  end

  test "GET /download preserves the query string (pursuit-modal deep link)", %{conn: conn} do
    pursuit_id = Ecto.UUID.generate()
    conn = get(conn, "/download?selected=#{pursuit_id}&filter=all")

    assert redirected_to(conn, 302) == "/incoming?selected=#{pursuit_id}&filter=all"
  end

  test "GET /upcoming redirects to /incoming", %{conn: conn} do
    conn = get(conn, "/upcoming")

    assert redirected_to(conn, 302) == "/incoming"
  end

  test "GET /upcoming preserves the query string", %{conn: conn} do
    conn = get(conn, "/upcoming?plan=new&tmdb_id=550&tmdb_type=movie")

    assert redirected_to(conn, 302) == "/incoming?plan=new&tmdb_id=550&tmdb_type=movie"
  end

  test "GET /download/auto-grabs (pre-merge legacy route) redirects to /incoming", %{conn: conn} do
    conn = get(conn, "/download/auto-grabs")

    assert redirected_to(conn, 302) == "/incoming"
  end
end
