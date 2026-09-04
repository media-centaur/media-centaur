defmodule MediaCentaur.Apps.SteamStoreTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.SteamStore

  defp stub_json(body) do
    test_pid = self()

    Req.Test.stub(:steam, fn conn ->
      send(test_pid, {:steam_request, conn.query_string})
      Req.Test.json(conn, body)
    end)
  end

  defp appdetails_body(app_id, url) do
    %{to_string(app_id) => %{"success" => true, "data" => %{"header_image" => url}}}
  end

  describe "current_banner_url/1" do
    test "returns the header URL from a decoded appdetails response" do
      stub_json(appdetails_body(100, "https://cdn.test/hash/header.jpg?t=1"))

      assert SteamStore.current_banner_url(100) == "https://cdn.test/hash/header.jpg?t=1"
      assert_receive {:steam_request, query}
      assert query =~ "appids=100"
    end

    test "decodes a raw JSON body served without a JSON content type" do
      body = JSON.encode!(appdetails_body(100, "https://cdn.test/hash/header.jpg"))

      Req.Test.stub(:steam, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert SteamStore.current_banner_url(100) == "https://cdn.test/hash/header.jpg"
    end

    test "nil when the API reports failure for the app" do
      stub_json(%{"100" => %{"success" => false}})

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on a non-200 response" do
      Req.Test.stub(:steam, fn conn -> Plug.Conn.send_resp(conn, 429, "") end)

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on a transport error" do
      Req.Test.stub(:steam, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on an empty body" do
      Req.Test.stub(:steam, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

      assert SteamStore.current_banner_url(100) == nil
    end
  end
end
