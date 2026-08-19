defmodule MediaCentaurWeb.Plugs.ImageServerTest do
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
  use MediaCentaurWeb.ConnCase, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaurWeb.Plugs.ImageServer

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

    test "placeholder response is uncached so a recovered drive serves real artwork on next fetch",
         %{conn: conn} do
      # Same URL maps to either the placeholder OR the real file depending on
      # whether the media dir is mounted right now. Caching the placeholder
      # response shadows the real file once the drive comes back — the browser
      # keeps serving the cached placeholder for the same URL until expiry.
      # `no-store` is the only correct cache directive for a response whose
      # body can flip on the next request without the URL changing.
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/poster.jpg")

      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "no-store"
    end
  end

  describe "existing file → aggressive cache headers" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "image_server_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      file_path = Path.join(tmp_dir, "poster.jpg")
      File.write!(file_path, "fake-jpeg-bytes")

      original = :persistent_term.get({Config, :config}, %{})
      :persistent_term.put({Config, :config}, Map.put(original, :data_dir, tmp_dir))

      on_exit(fn ->
        :persistent_term.put({Config, :config}, original)
        File.rm_rf!(tmp_dir)
      end)

      %{filename: "poster.jpg"}
    end

    test "versioned URL gets far-future immutable cache (URL is the cache key)",
         %{conn: conn, filename: filename} do
      conn = call_plug(conn, "/media-images/#{filename}", "v=7")

      assert conn.status == 200
      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "max-age=31536000"
      assert cache_control =~ "immutable"
      assert cache_control =~ "public"
    end

    test "plain URL gets short max-age plus ETag for cheap revalidation",
         %{conn: conn, filename: filename} do
      conn = call_plug(conn, "/media-images/#{filename}")

      assert conn.status == 200
      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "max-age=3600"
      assert cache_control =~ "public"
      refute cache_control =~ "immutable"

      assert [etag] = Plug.Conn.get_resp_header(conn, "etag")
      assert etag =~ ~r/^"\d+-\d+"$/
    end
  end

  describe "?w= width derivative" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "image_server_w_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      master_path = Path.join(tmp_dir, "backdrop.jpg")
      {:ok, image} = Image.new(1200, 675, color: :red)
      {:ok, _} = Image.write(image, master_path, suffix: ".jpg", quality: 90)

      # Generated derivatives land under tmp_dir (per-process override).
      Process.put(:image_derivative_root, tmp_dir)

      original = :persistent_term.get({Config, :config}, %{})
      :persistent_term.put({Config, :config}, Map.put(original, :data_dir, tmp_dir))

      on_exit(fn ->
        :persistent_term.put({Config, :config}, original)
        File.rm_rf!(tmp_dir)
      end)

      %{filename: "backdrop.jpg", master_path: master_path}
    end

    test "serves a smaller, revalidatable JPEG derivative (not immutable)",
         %{conn: conn, filename: filename, master_path: master_path} do
      conn = call_plug(conn, "/media-images/#{filename}", "w=320")

      assert conn.status == 200
      assert content_type(conn) =~ "image/jpeg"
      # The derivative is genuinely smaller than the full-resolution master.
      assert byte_size(conn.resp_body) < File.stat!(master_path).size

      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "max-age=3600"
      refute cache_control =~ "immutable"
      assert [_etag] = Plug.Conn.get_resp_header(conn, "etag")
    end

    test "a width at/above the master resolution serves the master untouched (no upscale)",
         %{conn: conn, filename: filename, master_path: master_path} do
      conn = call_plug(conn, "/media-images/#{filename}", "w=2000")

      assert conn.status == 200
      # Master is 1200px wide; a 2000px request must not upscale — same bytes.
      assert byte_size(conn.resp_body) == File.stat!(master_path).size
    end

    test "a missing master with ?w= still degrades to the placeholder", %{conn: conn} do
      conn = call_plug(conn, "/media-images/nope/backdrop.jpg", "w=320")

      assert conn.status == 200
      assert content_type(conn) =~ "image/svg+xml"
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

  describe "bare /media-images (no filename) degrades, never crashes" do
    # Regression for the production 500: an `<img src>` built from an empty
    # content_url (`/media-images/#{""}`) — or a crawler hitting the bare
    # mount point — arrives as path_info `["media-images"]` with nothing
    # after it. `Path.join([])` raises FunctionClauseError, so the plug must
    # short-circuit. We treat it like any other missing file: 200 + the
    # generic ("unknown" role) placeholder, consistent with the module's
    # graceful-degradation contract.
    test "bare path returns the generic placeholder instead of raising", %{conn: conn} do
      conn = call_plug(conn, "/media-images")

      assert conn.status == 200
      assert content_type(conn) =~ "image/svg+xml"
      # 200x200 generic square — the "unknown" role viewBox.
      assert conn.resp_body =~ ~s(viewBox="0 0 200 200")
    end
  end

  defp call_plug(conn, path, query_string \\ "") do
    segments = path |> String.trim_leading("/") |> String.split("/")

    ImageServer.call(
      %{conn | path_info: segments, request_path: path, query_string: query_string},
      ImageServer.init([])
    )
  end

  defp content_type(conn) do
    conn |> Plug.Conn.get_resp_header("content-type") |> List.first()
  end
end
