defmodule MediaCentaurWeb.ErrorJSON do
  @moduledoc """
  The one error body of a JSON response:
  `{"error": {"code": "not_found", "message": "Not Found"}}`. The endpoint
  renders it for errors it raises; the Local API sends it directly.
  """

  def render(template, _assigns) do
    template |> Path.rootname() |> String.to_integer() |> body()
  end

  @doc "The body for an HTTP status."
  @spec body(Plug.Conn.status()) :: %{error: %{code: atom(), message: String.t()}}
  def body(status) when is_integer(status) do
    %{
      error: %{
        code: Plug.Conn.Status.reason_atom(status),
        message: Plug.Conn.Status.reason_phrase(status)
      }
    }
  end
end
