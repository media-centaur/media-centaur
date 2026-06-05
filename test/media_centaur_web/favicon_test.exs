defmodule MediaCentaurWeb.FaviconTest do
  @moduledoc """
  Guards the favicon/app-icon wiring: the static artifacts are actually served
  (i.e. listed in `static_paths/0` and present on disk) and the adaptive SVG
  favicon is referenced from the root layout. This is a behaviour test — it
  exercises the endpoint, not the contents of a static config file.
  """
  use MediaCentaurWeb.ConnCase, async: true

  test "favicon.ico is served", %{conn: conn} do
    conn = get(conn, "/favicon.ico")
    assert conn.status == 200
  end

  test "the adaptive SVG favicon is served with the svg content type", %{conn: conn} do
    conn = get(conn, "/images/favicon.svg")
    assert conn.status == 200
    assert List.first(get_resp_header(conn, "content-type")) =~ "image/svg+xml"
  end

  test "the web manifest is served", %{conn: conn} do
    conn = get(conn, "/site.webmanifest")
    assert conn.status == 200
  end

  test "the root layout references the adaptive SVG favicon", %{conn: conn} do
    # /setup renders the root layout unconditionally (it is exempt from the
    # first-run SetupRedirect), so it is a stable place to assert head wiring.
    html = conn |> get(~p"/setup") |> html_response(200)
    assert html =~ ~s(type="image/svg+xml")
    assert html =~ "/images/favicon.svg"
  end
end
