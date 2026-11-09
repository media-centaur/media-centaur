defmodule MediaCentaurWeb.Api.NotFoundController do
  @moduledoc "An `/api` path no route matches: the API's one JSON 404, behind its key."

  use MediaCentaurWeb, :controller

  alias MediaCentaurWeb.ErrorJSON

  def show(conn, _params) do
    conn |> put_status(404) |> json(ErrorJSON.body(404))
  end
end
