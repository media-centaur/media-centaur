defmodule MediaCentaurWeb.Api.OpenApiControllerTest do
  use MediaCentaurWeb.ApiCase, async: false

  alias Phoenix.Router

  defp api_routes do
    for %{path: "/api/v1" <> path, verb: verb} <- Router.routes(MediaCentaurWeb.Router),
        verb != :*,
        into: MapSet.new() do
      {String.replace(path, ~r/:(\w+)/, "{\\1}"), Atom.to_string(verb)}
    end
  end

  defp documented_operations do
    for {path, operations} <- spec()["paths"], {verb, operation} <- operations do
      {path, verb, operation}
    end
  end

  test "a caller with the key downloads the document", %{conn: conn} do
    body = conn |> get("/api/v1/openapi.json") |> json_response(200)

    assert body == spec()
    assert String.starts_with?(body["openapi"], "3.1")
  end

  test "a caller without the key does not" do
    assert local_conn() |> get("/api/v1/openapi.json") |> json_response(401)
  end

  test "the document lists exactly the router's endpoints" do
    documented = MapSet.new(documented_operations(), fn {path, verb, _operation} -> {path, verb} end)

    assert documented == api_routes()
  end

  test "every operation documents its refusal and a success" do
    for {path, verb, operation} <- documented_operations() do
      codes = Map.keys(operation["responses"])

      assert "401" in codes, "#{verb} #{path} does not document 401"
      assert Enum.any?(codes, &String.starts_with?(&1, "2")), "#{verb} #{path} documents no success"
      assert operation["operationId"], "#{verb} #{path} has no operationId"
      assert operation["description"] || operation["summary"], "#{verb} #{path} is undescribed"
    end
  end
end
