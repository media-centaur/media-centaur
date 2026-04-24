defmodule MediaCentarrWeb.Plugs.ImageServerTest do
  @moduledoc """
  Guards the graceful-degradation contract for `/media-images/*`.

  When an image file is missing from disk, the plug responds 200 with an
  inline SVG placeholder whose aspect matches the requested role. This
  keeps the UI out of the browser's native broken-image state anywhere
  an `<img src="/media-images/…">` is rendered — posters, backdrops,
  episode thumbnails, and logos alike. The specific artwork can change;
  the contract being tested here is the response shape that callers
  (the browser) depend on.
  """
  use MediaCentarrWeb.ConnCase, async: true

  alias MediaCentarrWeb.Plugs.ImageServer

  describe "missing file → role-appropriate SVG placeholder" do
    test "poster miss returns 2:3 SVG placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/poster.jpg")

      assert conn.status == 200
      assert content_type(conn) == "image/svg+xml; charset=utf-8"
      assert conn.resp_body =~ "<svg"
      assert conn.resp_body =~ ~r/viewBox="0 0 200 300"/
    end

    test "backdrop miss returns 16:9 SVG placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/backdrop.jpg")

      assert conn.status == 200
      assert content_type(conn) == "image/svg+xml; charset=utf-8"
      assert conn.resp_body =~ ~r/viewBox="0 0 320 180"/
    end

    test "thumb miss returns 16:9 SVG placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/thumb.jpg")

      assert conn.status == 200
      assert content_type(conn) == "image/svg+xml; charset=utf-8"
      assert conn.resp_body =~ ~r/viewBox="0 0 320 180"/
    end

    test "logo miss returns 4:1 SVG placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/logo.png")

      assert conn.status == 200
      assert content_type(conn) == "image/svg+xml; charset=utf-8"
      assert conn.resp_body =~ ~r/viewBox="0 0 400 100"/
    end

    test "unknown role miss returns generic square SVG placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/mystery.jpg")

      assert conn.status == 200
      assert content_type(conn) == "image/svg+xml; charset=utf-8"
      assert conn.resp_body =~ ~r/viewBox="0 0 200 200"/
    end

    test "placeholder response has Cache-Control so browsers don't spam retries", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/poster.jpg")

      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "public"
    end
  end

  describe "path traversal guard (preserved)" do
    test "path containing .. halts with 400", %{conn: conn} do
      conn = call_plug(conn, "/media-images/../../etc/passwd")

      assert conn.status == 400
    end
  end

  describe "non-matching path is a passthrough" do
    test "does not halt when path is outside /media-images", %{conn: conn} do
      conn = call_plug(conn, "/something-else/file.jpg")

      refute conn.halted
    end
  end

  defp call_plug(conn, path) do
    segments = path |> String.trim_leading("/") |> String.split("/")

    ImageServer.call(%{conn | path_info: segments, request_path: path}, ImageServer.init([]))
  end

  defp content_type(conn) do
    conn |> Plug.Conn.get_resp_header("content-type") |> List.first()
  end
end
