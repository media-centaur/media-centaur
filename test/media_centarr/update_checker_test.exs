defmodule MediaCentarr.UpdateCheckerTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.UpdateChecker

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
