defmodule MediaCentaurWeb.Api.StatusControllerTest do
  use MediaCentaurWeb.ConnCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaurWeb.ApiKey

  @lan {192, 168, 1, 20}
  @not_found %{"error" => %{"code" => "not_found", "message" => "Not Found"}}

  defp authorized(conn, key), do: put_req_header(conn, "authorization", "Bearer #{key}")

  describe "while the feature is off" do
    test "the API answers as if it did not exist, even to a valid key", %{conn: conn} do
      key = ApiKey.generate()

      assert conn |> authorized(key) |> get("/api/v1/status") |> json_response(404) == @not_found
    end
  end

  describe "while the feature is on" do
    setup do
      Features.set(:local_api, true)
      %{key: ApiKey.generate()}
    end

    test "a valid key reads the version and what is ready", %{conn: conn, key: key} do
      body = conn |> authorized(key) |> get("/api/v1/status") |> json_response(200)

      assert is_binary(body["version"])

      assert %{
               "tmdb" => _,
               "prowlarr" => _,
               "download_client" => _,
               "acquisition" => _
             } = body["capabilities"]
    end

    test "Downloads off takes the API with it: it requires that feature", %{
      conn: conn,
      key: key
    } do
      Features.set(:acquisition, false)

      assert conn |> authorized(key) |> get("/api/v1/status") |> json_response(404) == @not_found
    end

    test "loopback has no exemption: no key is 401", %{conn: conn} do
      assert %{"error" => %{"code" => "unauthorized"}} =
               conn |> get("/api/v1/status") |> json_response(401)
    end

    test "a wrong key is 401", %{conn: conn} do
      assert conn |> authorized("wrong") |> get("/api/v1/status") |> json_response(401)
    end

    test "a LAN caller is admitted by its key alone, with no paired player", %{conn: conn, key: key} do
      conn = %{conn | remote_ip: @lan}

      assert conn |> authorized(key) |> get("/api/v1/status") |> json_response(200)
    end

    test "a LAN caller without a key is refused, not sent to the pairing page", %{conn: conn} do
      conn = %{conn | remote_ip: @lan}

      assert conn |> get("/api/v1/status") |> json_response(401)
    end

    test "an unknown path needs the key, then is a JSON 404", %{conn: conn, key: key} do
      assert conn |> post("/api/v1/nothing") |> json_response(401)
      assert conn |> authorized(key) |> post("/api/v1/nothing") |> json_response(404) == @not_found
    end

    test "a path that only begins with api goes through the gate", %{conn: conn} do
      conn = %{conn | remote_ip: @lan}

      assert conn |> get("/apifoo") |> redirected_to() == "/pair"
    end
  end
end
