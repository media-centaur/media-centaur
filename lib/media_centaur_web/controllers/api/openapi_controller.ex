defmodule MediaCentaurWeb.Api.OpenApiController do
  @moduledoc "`GET /api/v1/openapi.json`: the OpenAPI document describing this API."

  use MediaCentaurWeb, :controller

  @document_path Path.expand("../../../../priv/api/openapi.json", __DIR__)
  @external_resource @document_path
  @document File.read!(@document_path)

  def show(conn, _params) do
    conn |> put_resp_content_type("application/json") |> send_resp(200, @document)
  end
end
