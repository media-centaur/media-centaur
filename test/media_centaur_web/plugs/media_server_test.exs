defmodule MediaCentaurWeb.Plugs.MediaServerTest do
  @moduledoc """
  The media endpoint through the whole endpoint, from a LAN address with no
  session: admitted by the capability token alone, confined to the media
  directories, honouring one `Range`.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Library.MediaFileAvailability
  alias MediaCentaurWeb.MediaToken

  @lan {192, 168, 1, 20}
  @player "a0a0a0a0-0000-4000-8000-000000000001"
  @bytes "0123456789abcdefghij"

  setup %{tmp_dir: tmp_dir} do
    media_dir = register_media_dir(tmp_dir)
    path = Path.join(media_dir, "Sample.Movie.2010.1080p.mkv")
    File.write!(path, @bytes)
    presence = FilePresence.stamp(path, media_dir)
    %{presence: presence, path: path, media_dir: media_dir}
  end

  defp from_lan(conn), do: %{conn | remote_ip: @lan}

  defp media_url(presence, token), do: "/media/#{presence.id}?t=#{token}"

  @tag :tmp_dir
  test "the whole file, with the headers a player reads", %{conn: conn, presence: presence} do
    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(@player, presence.id)))

    assert response(conn, 200) == @bytes
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-type") == ["video/x-matroska"]
    assert get_resp_header(conn, "content-length") == [Integer.to_string(byte_size(@bytes))]
    assert [_last_modified] = get_resp_header(conn, "last-modified")
    assert [_etag] = get_resp_header(conn, "etag")
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  @tag :tmp_dir
  test "one range is a 206 with its slice", %{conn: conn, presence: presence} do
    conn =
      conn
      |> from_lan()
      |> put_req_header("range", "bytes=5-9")
      |> get(media_url(presence, MediaToken.sign(@player, presence.id)))

    assert response(conn, 206) == "56789"
    assert get_resp_header(conn, "content-range") == ["bytes 5-9/20"]
    assert get_resp_header(conn, "content-length") == ["5"]

    conn =
      conn
      |> recycle()
      |> from_lan()
      |> put_req_header("range", "bytes=15-")
      |> get(media_url(presence, MediaToken.sign(@player, presence.id)))

    assert response(conn, 206) == "fghij"
  end

  @tag :tmp_dir
  test "an unsatisfiable range is a 416 naming the size", %{conn: conn, presence: presence} do
    conn =
      conn
      |> from_lan()
      |> put_req_header("range", "bytes=20-")
      |> get(media_url(presence, MediaToken.sign(@player, presence.id)))

    assert response(conn, 416)
    assert get_resp_header(conn, "content-range") == ["bytes */20"]
  end

  @tag :tmp_dir
  test "HEAD answers the headers and no body", %{conn: conn, presence: presence} do
    conn = conn |> from_lan() |> head(media_url(presence, MediaToken.sign(@player, presence.id)))
    assert response(conn, 200) == ""
    assert get_resp_header(conn, "content-length") == ["20"]
  end

  @tag :tmp_dir
  test "no token, a bad token, or a token for another file is refused", %{conn: conn, presence: presence} do
    assert conn |> from_lan() |> get("/media/#{presence.id}") |> response(403)
    assert conn |> from_lan() |> get(media_url(presence, "garbage")) |> response(403)

    other = MediaToken.sign(@player, Ecto.UUID.generate())
    assert conn |> from_lan() |> get(media_url(presence, other)) |> response(403)
  end

  @tag :tmp_dir
  test "an unknown id is not found", %{conn: conn} do
    id = Ecto.UUID.generate()
    conn = conn |> from_lan() |> get("/media/#{id}?t=#{MediaToken.sign(@player, id)}")
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file outside every media directory is not served, even with a presence row", %{conn: conn} do
    outside = Path.join(System.tmp_dir!(), "mc-outside-#{System.unique_integer([:positive])}.mkv")
    File.write!(outside, @bytes)
    on_exit(fn -> File.rm(outside) end)
    presence = FilePresence.stamp(outside, Path.dirname(outside))

    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(@player, presence.id)))
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file gone from disk is not found", %{conn: conn, presence: presence, path: path} do
    File.rm!(path)
    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(@player, presence.id)))
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file on an unavailable media directory is a retryable 503",
       %{conn: conn, presence: presence, media_dir: media_dir} do
    :persistent_term.put({MediaFileAvailability, :state}, %{media_dir => :unavailable})

    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(@player, presence.id)))
    assert response(conn, 503)
  end

  @tag :tmp_dir
  test "anything but GET or HEAD on a media path is not allowed", %{conn: conn, presence: presence} do
    conn = conn |> from_lan() |> post(media_url(presence, MediaToken.sign(@player, presence.id)), %{})
    assert response(conn, 405)
  end
end
