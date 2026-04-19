defmodule MediaCentarr.SelfUpdate.DownloaderTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.SelfUpdate.Downloader

  @tmp_root System.tmp_dir!()

  defp tmp_dir do
    path = Path.join(@tmp_root, "downloader-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp stub_tarball_and_sums(tarball_bytes, filename) do
    sha256 = Base.encode16(:crypto.hash(:sha256, tarball_bytes), case: :lower)
    sha256_body = "#{sha256}  #{filename}\n"

    Req.Test.stub(:downloader, fn conn ->
      case conn.request_path do
        "/tarball" ->
          conn
          |> Plug.Conn.put_resp_header("content-length", Integer.to_string(byte_size(tarball_bytes)))
          |> Plug.Conn.send_resp(200, tarball_bytes)

        "/SHA256SUMS" ->
          Plug.Conn.send_resp(conn, 200, sha256_body)
      end
    end)

    sha256
  end

  defp client, do: Req.new(plug: {Req.Test, :downloader}, retry: false)

  describe "run/2 happy path" do
    test "writes the tarball, returns sha, and reports progress" do
      dir = tmp_dir()
      bytes = :crypto.strong_rand_bytes(1024)
      expected_sha = stub_tarball_and_sums(bytes, "release.tar.gz")

      progress_msgs =
        :ets.new(:progress, [:public, :duplicate_bag])

      progress_fn = fn downloaded, total ->
        :ets.insert(progress_msgs, {downloaded, total})
        :ok
      end

      assert {:ok, %{tarball_path: path, sha256: sha}} =
               Downloader.run(
                 "http://host/tarball",
                 "http://host/SHA256SUMS",
                 target_dir: dir,
                 filename: "release.tar.gz",
                 client: client(),
                 progress_fn: progress_fn
               )

      assert sha == expected_sha
      assert File.read!(path) == bytes

      events = :ets.tab2list(progress_msgs)
      assert Enum.any?(events, fn {_down, total} -> total == byte_size(bytes) end)

      :ets.delete(progress_msgs)
    end
  end

  describe "run/2 error paths" do
    test "returns {:error, :checksum_mismatch} when the SHA doesn't match" do
      dir = tmp_dir()
      bytes = :crypto.strong_rand_bytes(512)
      fake_sha = Base.encode16(:crypto.hash(:sha256, <<"not the same">>), case: :lower)

      Req.Test.stub(:downloader, fn conn ->
        case conn.request_path do
          "/tarball" ->
            conn
            |> Plug.Conn.put_resp_header("content-length", Integer.to_string(byte_size(bytes)))
            |> Plug.Conn.send_resp(200, bytes)

          "/SHA256SUMS" ->
            Plug.Conn.send_resp(conn, 200, "#{fake_sha}  release.tar.gz\n")
        end
      end)

      assert {:error, :checksum_mismatch} =
               Downloader.run(
                 "http://host/tarball",
                 "http://host/SHA256SUMS",
                 target_dir: dir,
                 filename: "release.tar.gz",
                 client: client()
               )

      refute File.exists?(Path.join(dir, "release.tar.gz"))
    end

    test "returns {:error, :not_found} on a 404 tarball" do
      dir = tmp_dir()

      Req.Test.stub(:downloader, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :not_found} =
               Downloader.run(
                 "http://host/tarball",
                 "http://host/SHA256SUMS",
                 target_dir: dir,
                 filename: "release.tar.gz",
                 client: client()
               )
    end

    test "returns {:error, :too_large} when the downloaded body exceeds max_bytes" do
      dir = tmp_dir()
      fake_sha = String.duplicate("a", 64)
      big_body = :crypto.strong_rand_bytes(4096)

      Req.Test.stub(:downloader, fn conn ->
        case conn.request_path do
          "/SHA256SUMS" ->
            Plug.Conn.send_resp(conn, 200, "#{fake_sha}  release.tar.gz\n")

          "/tarball" ->
            Plug.Conn.send_resp(conn, 200, big_body)
        end
      end)

      assert {:error, :too_large} =
               Downloader.run(
                 "http://host/tarball",
                 "http://host/SHA256SUMS",
                 target_dir: dir,
                 filename: "release.tar.gz",
                 client: client(),
                 max_bytes: 1024
               )

      refute File.exists?(Path.join(dir, "release.tar.gz"))
    end

    test "returns {:error, :checksum_missing} when the filename isn't in SHA256SUMS" do
      dir = tmp_dir()
      bytes = :crypto.strong_rand_bytes(64)

      Req.Test.stub(:downloader, fn conn ->
        case conn.request_path do
          "/SHA256SUMS" ->
            # Entry for a different file.
            Plug.Conn.send_resp(conn, 200, "deadbeef  other.tar.gz\n")

          "/tarball" ->
            conn
            |> Plug.Conn.put_resp_header("content-length", Integer.to_string(byte_size(bytes)))
            |> Plug.Conn.send_resp(200, bytes)
        end
      end)

      assert {:error, :checksum_missing} =
               Downloader.run(
                 "http://host/tarball",
                 "http://host/SHA256SUMS",
                 target_dir: dir,
                 filename: "release.tar.gz",
                 client: client()
               )
    end
  end
end
