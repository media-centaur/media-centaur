defmodule MediaCentaurWeb.Api.Admission do
  @moduledoc """
  Admission to the Local API (`/api`), the first plug of the router's
  `:api` pipeline. While the feature is off the API answers 404, as if it
  did not exist (ADR-081). While it is on, every request must carry
  `Authorization: Bearer <key>` (`ApiKey`), loopback included: a web page
  in the host's browser can reach a loopback address, but it has no key to
  send. `Plugs.RemoteAccess` leaves `/api` to this plug, since a caller is
  admitted by its key and has no paired player.
  """

  @behaviour Plug

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias MediaCentaur.Features
  alias MediaCentaurWeb.ApiKey
  alias MediaCentaurWeb.ErrorJSON

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      not Features.enabled?(:local_api) -> refuse(conn, 404)
      authorized?(conn) -> conn
      true -> conn |> put_resp_header("www-authenticate", "Bearer") |> refuse(401)
    end
  end

  defp authorized?(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> ApiKey.valid?(key)
      _absent_or_malformed -> false
    end
  end

  defp refuse(conn, status) do
    conn |> put_status(status) |> json(ErrorJSON.body(status)) |> halt()
  end
end
