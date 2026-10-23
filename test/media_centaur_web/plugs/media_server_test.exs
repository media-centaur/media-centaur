defmodule MediaCentaurWeb.Plugs.MediaServerTest do
  @moduledoc """
  The media endpoint through the whole endpoint, from a LAN address with no
  session: admitted by the capability token alone — while the token's
  player is still paired — confined to the media directories, honouring
  one `Range`.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Library.MediaFileAvailability
  alias MediaCentaurWeb.MediaToken

  @lan {192, 168, 1, 20}
  @bytes "0123456789abcdefghij"

  setup %{tmp_dir: tmp_dir} do
    media_dir = register_media_dir(tmp_dir)
    path = Path.join(media_dir, "Sample.Movie.2010.1080p.mkv")
    File.write!(path, @bytes)
    presence = FilePresence.stamp(path, media_dir)
    player = create_player(name: "Living room TV")
    %{presence: presence, path: path, media_dir: media_dir, player: player}
  end

  defp from_lan(conn), do: %{conn | remote_ip: @lan}

  defp media_url(presence, token), do: "/media/#{presence.id}?t=#{token}"

  @tag :tmp_dir
  test "the whole file, with the headers a player reads", %{player: player, conn: conn, presence: presence} do
    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))

    assert response(conn, 200) == @bytes
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-type") == ["video/x-matroska"]
    assert get_resp_header(conn, "content-length") == [Integer.to_string(byte_size(@bytes))]
    assert [_last_modified] = get_resp_header(conn, "last-modified")
    assert [_etag] = get_resp_header(conn, "etag")
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  @tag :tmp_dir
  test "one range is a 206 with its slice", %{player: player, conn: conn, presence: presence} do
    conn =
      conn
      |> from_lan()
      |> put_req_header("range", "bytes=5-9")
      |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))

    assert response(conn, 206) == "56789"
    assert get_resp_header(conn, "content-range") == ["bytes 5-9/20"]
    assert get_resp_header(conn, "content-length") == ["5"]

    conn =
      conn
      |> recycle()
      |> from_lan()
      |> put_req_header("range", "bytes=15-")
      |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))

    assert response(conn, 206) == "fghij"
  end

  @tag :tmp_dir
  test "an unsatisfiable range is a 416 naming the size", %{player: player, conn: conn, presence: presence} do
    conn =
      conn
      |> from_lan()
      |> put_req_header("range", "bytes=20-")
      |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))

    assert response(conn, 416)
    assert get_resp_header(conn, "content-range") == ["bytes */20"]
  end

  @tag :tmp_dir
  test "HEAD answers the headers and no body", %{player: player, conn: conn, presence: presence} do
    conn = conn |> from_lan() |> head(media_url(presence, MediaToken.sign(player.id, presence.id)))
    assert response(conn, 200) == ""
    assert get_resp_header(conn, "content-length") == ["20"]
  end

  @tag :tmp_dir
  test "no token, a bad token, or a token for another file is refused", %{player: player, conn: conn, presence: presence} do
    assert conn |> from_lan() |> get("/media/#{presence.id}") |> response(403)
    assert conn |> from_lan() |> get(media_url(presence, "garbage")) |> response(403)

    other = MediaToken.sign(player.id, Ecto.UUID.generate())
    assert conn |> from_lan() |> get(media_url(presence, other)) |> response(403)
  end

  @tag :tmp_dir
  test "a file's sidecar subtitle is served under the file's own token, by its name beside the file", %{player: player, 
    conn: conn,
    presence: presence,
    path: path,
    media_dir: media_dir
  } do
    watched_file =
      create_linked_file(%{
        file_path: path,
        media_dir: media_dir,
        movie_id: create_standalone_movie().id
      })

    assert watched_file.file_presence_id == presence.id

    sidecar = Path.join(media_dir, "Sample.Movie.2010.1080p.en.srt")
    File.write!(sidecar, "1\n00:00:01,000 --> 00:00:02,000\nHello\n")

    {:ok, _track} =
      MediaCentaur.Subtitles.create_track(%{
        watched_file_id: watched_file.id,
        kind: :sidecar,
        language: "en",
        source: sidecar
      })

    token = MediaToken.sign(player.id, presence.id)

    conn =
      conn
      |> from_lan()
      |> get("/media/#{presence.id}/subtitles/Sample.Movie.2010.1080p.en.srt?t=#{token}")

    assert response(conn, 200) == File.read!(sidecar)
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]

    # A basename with spaces arrives percent-encoded, as the locator encodes it:
    # the segment is matched decoded. The router decodes path segments before
    # it matches; this plug runs ahead of the router and must do the same.
    spaced = Path.join(media_dir, "Sample Movie (2010) 1080p.en.srt")
    File.write!(spaced, "1\n00:00:01,000 --> 00:00:02,000\nSpaced\n")

    {:ok, _track} =
      MediaCentaur.Subtitles.create_track(%{
        watched_file_id: watched_file.id,
        kind: :sidecar,
        language: "en",
        source: spaced
      })

    encoded = URI.encode("Sample Movie (2010) 1080p.en.srt", &URI.char_unreserved?/1)

    conn =
      conn
      |> recycle()
      |> from_lan()
      |> get("/media/#{presence.id}/subtitles/#{encoded}?t=#{token}")

    assert response(conn, 200) == File.read!(spaced)

    # Only a detected sidecar of that file: a neighbour that is not one of its tracks is not served.
    File.write!(Path.join(media_dir, "Sample.Movie.2010.1080p.de.srt"), "")

    conn =
      conn
      |> recycle()
      |> from_lan()
      |> get("/media/#{presence.id}/subtitles/Sample.Movie.2010.1080p.de.srt?t=#{token}")

    assert response(conn, 404)

    # The file's token, not another's.
    other = MediaToken.sign(player.id, Ecto.UUID.generate())

    conn =
      conn
      |> recycle()
      |> from_lan()
      |> get("/media/#{presence.id}/subtitles/Sample.Movie.2010.1080p.en.srt?t=#{other}")

    assert response(conn, 403)
  end

  @tag :tmp_dir
  test "a token for a player that has since been removed is refused", %{conn: conn, presence: presence} do
    removed = create_player(name: "Old TV")
    token = MediaToken.sign(removed.id, presence.id)
    :ok = MediaCentaur.Players.remove(removed)

    assert conn |> from_lan() |> get(media_url(presence, token)) |> response(403)
  end

  @tag :tmp_dir
  test "an unknown id is not found", %{player: player, conn: conn} do
    id = Ecto.UUID.generate()
    conn = conn |> from_lan() |> get("/media/#{id}?t=#{MediaToken.sign(player.id, id)}")
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file outside every media directory is not served, even with a presence row", %{player: player, conn: conn} do
    outside = Path.join(System.tmp_dir!(), "mc-outside-#{System.unique_integer([:positive])}.mkv")
    File.write!(outside, @bytes)
    on_exit(fn -> File.rm(outside) end)
    presence = FilePresence.stamp(outside, Path.dirname(outside))

    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file gone from disk is not found", %{player: player, conn: conn, presence: presence, path: path} do
    File.rm!(path)
    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))
    assert response(conn, 404)
  end

  @tag :tmp_dir
  test "a file on an unavailable media directory is a retryable 503",
       %{player: player, conn: conn, presence: presence, media_dir: media_dir} do
    :persistent_term.put({MediaFileAvailability, :state}, %{media_dir => :unavailable})

    conn = conn |> from_lan() |> get(media_url(presence, MediaToken.sign(player.id, presence.id)))
    assert response(conn, 503)
  end

  @tag :tmp_dir
  test "anything but GET or HEAD on a media path is not allowed", %{player: player, conn: conn, presence: presence} do
    conn = conn |> from_lan() |> post(media_url(presence, MediaToken.sign(player.id, presence.id)), %{})
    assert response(conn, 405)
  end
end
