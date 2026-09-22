defmodule MediaCentaurWeb.Plugs.ImageServerTest do
  @moduledoc """
  Guards the response contract for `/media-images/*`: a file on disk is
  served with the cache headers UIDR-012 fixes, a file that is not on disk
  is an uncached 404. The plug never stands in for a missing file; the
  read models decide what artwork a page may show
  (`docs/plans/2026-09-22-artwork-availability.md`).
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Settings.Config
  alias MediaCentaurWeb.Plugs.ImageServer

  describe "missing file → 404" do
    # The plug never stands in for a missing file. Whether an entry's
    # artwork can be shown is decided in the read models from the
    # availability of its media directory, so a page never emits a URL
    # this plug cannot serve while a drive is unmounted. A 404 here is a
    # data defect (file missing while its volume is up), owned by
    # `Library.ImageHealth`.
    test "a poster that is not on disk is a 404", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/poster.jpg")

      assert conn.status == 404
      assert conn.halted
    end

    test "the 404 is uncached, so the same URL serves the file the moment it lands", %{conn: conn} do
      conn = call_plug(conn, "/media-images/ffffffff-0000-0000-0000-000000000000/backdrop.jpg")

      [cache_control] = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control =~ "no-store"
    end
  end

  describe "a miss for library artwork is reported to the library" do
    # Reporting is not deciding: the read models decide what artwork a
    # page shows, and this is the fact they need to re-decide — a row
    # whose file vanished after it landed. The owner's container is
    # broadcast as changed, every projection re-checks the file, and the
    # page swaps the broken image for its placeholder.
    test "a missing poster broadcasts its movie as changed", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      image =
        create_image(%{
          movie_id: movie.id,
          role: "poster",
          content_url: "#{movie.id}/poster.jpg",
          extension: "jpg"
        })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      conn = call_plug(conn, "/media-images/#{image.content_url}")

      assert conn.status == 404
      assert_receive {:entities_changed, %{entity_ids: [changed_id]}}, 1_000
      assert changed_id == movie.id
    end

    test "a missing episode thumb broadcasts its series", %{conn: conn} do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "Pilot"})

      image =
        create_image(%{
          episode_id: episode.id,
          role: "thumb",
          content_url: "#{episode.id}/thumb.jpg",
          extension: "jpg"
        })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      call_plug(conn, "/media-images/#{image.content_url}")

      assert_receive {:entities_changed, %{entity_ids: [changed_id]}}, 1_000
      assert changed_id == series.id
    end

    test "a path outside the library layout is not reported", %{conn: conn} do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      conn = call_plug(conn, "/media-images/images/apps/ffffffff-0000-0000-0000-000000000000/banner.jpg")

      assert conn.status == 404
      refute_receive {:entities_changed, _}, 200
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

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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

    test "a missing master with ?w= is a 404 too", %{conn: conn} do
      conn = call_plug(conn, "/media-images/nope/backdrop.jpg", "w=320")

      assert conn.status == 404
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

  describe "bare /media-images (no filename) answers, never crashes" do
    # Regression for the production 500: an `<img src>` built from an empty
    # content_url (`/media-images/#{""}`) — or a crawler hitting the bare
    # mount point — arrives as path_info `["media-images"]` with nothing
    # after it. `Path.join([])` raises, so the plug must short-circuit to
    # the same 404 any other missing file gets.
    test "bare path is a 404 instead of raising", %{conn: conn} do
      conn = call_plug(conn, "/media-images")

      assert conn.status == 404
      assert conn.halted
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
