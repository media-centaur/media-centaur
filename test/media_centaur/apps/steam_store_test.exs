defmodule MediaCentaur.Apps.SteamStoreTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.SteamStore

  defmodule FakeClient do
    @moduledoc false
    def get(url) do
      Process.put(:steam_store_requested_url, url)
      Process.get(:fake_store_response)
    end
  end

  defp stub(response) do
    Process.put(:steam_store_http_client, FakeClient)
    Process.put(:fake_store_response, response)
  end

  defp appdetails_body(app_id, url) do
    %{to_string(app_id) => %{"success" => true, "data" => %{"header_image" => url}}}
  end

  describe "current_banner_url/1" do
    test "returns the header URL from a decoded appdetails response" do
      stub({:ok, %{status: 200, body: appdetails_body(100, "https://cdn.test/hash/header.jpg?t=1")}})

      assert SteamStore.current_banner_url(100) == "https://cdn.test/hash/header.jpg?t=1"
      assert Process.get(:steam_store_requested_url) =~ "appids=100"
    end

    test "decodes a raw JSON body" do
      body = JSON.encode!(appdetails_body(100, "https://cdn.test/hash/header.jpg"))
      stub({:ok, %{status: 200, body: body}})

      assert SteamStore.current_banner_url(100) == "https://cdn.test/hash/header.jpg"
    end

    test "nil when the API reports failure for the app" do
      stub({:ok, %{status: 200, body: %{"100" => %{"success" => false}}}})

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on a non-200 response" do
      stub({:ok, %{status: 429, body: ""}})

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on a transport error" do
      stub({:error, :timeout})

      assert SteamStore.current_banner_url(100) == nil
    end

    test "nil on an undecodable body (the test-env noop client)" do
      stub({:ok, %{status: 200, body: ""}})

      assert SteamStore.current_banner_url(100) == nil
    end
  end
end
