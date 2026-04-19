defmodule MediaCentarr.SelfUpdate.UpdateCheckerTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.SelfUpdate.UpdateChecker

  setup do
    Req.Test.stub(:github_releases, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, JSON.encode!(%{"message" => "Not Found"}))
    end)

    client = Req.new(plug: {Req.Test, :github_releases}, retry: false)
    {:ok, client: client}
  end

  describe "latest_release/1" do
    test "returns the parsed release on a 200 response", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v0.5.0",
            "name" => "v0.5.0",
            "published_at" => "2026-05-01T10:00:00Z",
            "html_url" => "https://github.com/media-centarr/media-centarr/releases/tag/v0.5.0"
          })
        )
      end)

      assert {:ok, release} = UpdateChecker.latest_release(client)
      assert release.version == "0.5.0"
      assert release.tag == "v0.5.0"
      assert %DateTime{} = release.published_at
      assert release.html_url =~ "v0.5.0"
    end

    test "returns {:error, :not_found} on a 404", %{client: client} do
      # Default setup stub already returns 404.
      assert {:error, :not_found} = UpdateChecker.latest_release(client)
    end

    test "returns {:error, {:http_error, status}} on other non-200 statuses", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        Plug.Conn.send_resp(conn, 503, "busy")
      end)

      assert {:error, {:http_error, 503}} = UpdateChecker.latest_release(client)
    end

    test "detects rate-limit on a 403 with x-ratelimit-remaining: 0", %{client: client} do
      reset_epoch = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()

      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-remaining", "0")
        |> Plug.Conn.put_resp_header("x-ratelimit-reset", Integer.to_string(reset_epoch))
        |> Plug.Conn.send_resp(403, ~s({"message":"API rate limit exceeded"}))
      end)

      assert {:error, {:rate_limited, %DateTime{} = reset_at}} =
               UpdateChecker.latest_release(client)

      # Reset timestamp matches the header we sent (tolerate 2s clock skew).
      drift = abs(DateTime.diff(reset_at, DateTime.from_unix!(reset_epoch)))
      assert drift <= 2
    end

    test "falls back to {:http_error, 403} when 403 is returned without rate-limit headers",
         %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        # No x-ratelimit-remaining header — this is some other 403
        # (abuse detection, repository permission issue, etc.).
        Plug.Conn.send_resp(conn, 403, "forbidden")
      end)

      assert {:error, {:http_error, 403}} = UpdateChecker.latest_release(client)
    end

    test "returns {:error, :malformed} when tag_name is missing", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, JSON.encode!(%{"name" => "nope"}))
      end)

      assert {:error, :malformed} = UpdateChecker.latest_release(client)
    end

    test "returns {:error, reason} on transport failure", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               UpdateChecker.latest_release(client)
    end
  end

  describe "tag validation" do
    test "rejects a response with a shell-metachar tag", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v1.0.0; rm -rf $HOME",
            "published_at" => "2026-05-01T10:00:00Z",
            "html_url" => "https://github.com/media-centarr/media-centarr/releases/tag/v1.0.0"
          })
        )
      end)

      assert {:error, :invalid_tag} = UpdateChecker.latest_release(client)
    end

    test "rejects a response with a path-traversal tag", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "../../etc/passwd",
            "published_at" => "2026-05-01T10:00:00Z"
          })
        )
      end)

      assert {:error, :invalid_tag} = UpdateChecker.latest_release(client)
    end

    test "rejects an empty tag", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{"tag_name" => "", "published_at" => "2026-05-01T10:00:00Z"})
        )
      end)

      assert {:error, :invalid_tag} = UpdateChecker.latest_release(client)
    end

    test "rejects a tag without the v prefix", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{"tag_name" => "1.0.0", "published_at" => "2026-05-01T10:00:00Z"})
        )
      end)

      assert {:error, :invalid_tag} = UpdateChecker.latest_release(client)
    end

    test "accepts a valid pre-release tag", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v1.2.3-beta.4",
            "published_at" => "2026-05-01T10:00:00Z",
            "html_url" => "https://github.com/media-centarr/media-centarr/releases/tag/v1.2.3-beta.4"
          })
        )
      end)

      assert {:ok, %{tag: "v1.2.3-beta.4", version: "1.2.3-beta.4"}} =
               UpdateChecker.latest_release(client)
    end

    test "replaces an html_url pointing at an unexpected host", %{client: client} do
      Req.Test.stub(:github_releases, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "tag_name" => "v1.0.0",
            "published_at" => "2026-05-01T10:00:00Z",
            "html_url" => "https://evil.example.com/fake"
          })
        )
      end)

      assert {:ok, release} = UpdateChecker.latest_release(client)
      assert release.html_url == "https://github.com/media-centarr/media-centarr/releases/tag/v1.0.0"
    end

    test "validate_tag/1 accepts canonical shapes and rejects anything else" do
      assert :ok = UpdateChecker.validate_tag("v0.7.1")
      assert :ok = UpdateChecker.validate_tag("v10.20.30")
      assert :ok = UpdateChecker.validate_tag("v1.0.0-rc.1")

      assert {:error, :invalid_tag} = UpdateChecker.validate_tag("")
      assert {:error, :invalid_tag} = UpdateChecker.validate_tag("0.7.1")
      assert {:error, :invalid_tag} = UpdateChecker.validate_tag("v0.7")
      assert {:error, :invalid_tag} = UpdateChecker.validate_tag("v0.7.1 ")
      assert {:error, :invalid_tag} = UpdateChecker.validate_tag("v0.7.1;ls")
      assert {:error, :invalid_tag} = UpdateChecker.validate_tag(nil)
    end
  end

  describe "cache" do
    setup do
      UpdateChecker.clear_cache()
      on_exit(fn -> UpdateChecker.clear_cache() end)
      :ok
    end

    test "cached_latest_release/0 returns :stale when nothing cached" do
      assert UpdateChecker.cached_latest_release() == :stale
    end

    test "cache_result/1 stores a successful result and cached_latest_release returns :fresh" do
      release = %{version: "0.5.0", tag: "v0.5.0", published_at: now(), html_url: "x"}
      :ok = UpdateChecker.cache_result({:ok, release})
      assert {:fresh, {:ok, ^release}} = UpdateChecker.cached_latest_release()
    end

    test "cache_result/1 stores an error result and returns it as :fresh" do
      :ok = UpdateChecker.cache_result({:error, :not_found})
      assert {:fresh, {:error, :not_found}} = UpdateChecker.cached_latest_release()
    end

    test "clear_cache/0 drops the cached result" do
      :ok = UpdateChecker.cache_result({:error, :not_found})
      :ok = UpdateChecker.clear_cache()
      assert UpdateChecker.cached_latest_release() == :stale
    end
  end

  describe "compare/2" do
    test "classifies a newer remote version as :update_available" do
      release = %{version: "0.5.0", tag: "v0.5.0", published_at: now(), html_url: "x"}
      assert UpdateChecker.compare(release, "0.4.0") == :update_available
    end

    test "classifies matching versions as :up_to_date" do
      release = %{version: "0.4.0", tag: "v0.4.0", published_at: now(), html_url: "x"}
      assert UpdateChecker.compare(release, "0.4.0") == :up_to_date
    end

    test "classifies an older remote as :ahead_of_release (dev build)" do
      release = %{version: "0.3.0", tag: "v0.3.0", published_at: now(), html_url: "x"}
      assert UpdateChecker.compare(release, "0.4.0") == :ahead_of_release
    end
  end

  defp now, do: DateTime.utc_now()
end
