defmodule MediaCentaurWeb.LegacyRedirectController do
  @moduledoc """
  Backward-compat redirects for routes that moved. `/download` and
  `/upcoming` merged into `/incoming` (DDR-015); the auto-grabs route
  predates that (manual + auto grabs unified into one page, v0.24.0).

  Query strings are preserved so deep-links keep their meaning —
  `/download?selected=<pursuit_id>` still opens the pursuit modal on
  the merged page.
  """
  use MediaCentaurWeb, :controller

  def download(conn, _params), do: redirect(conn, to: preserve_query(conn, "/incoming"))

  def upcoming(conn, _params), do: redirect(conn, to: preserve_query(conn, "/incoming"))

  def auto_grabs(conn, _params), do: redirect(conn, to: "/incoming")

  defp preserve_query(%{query_string: ""}, path), do: path
  defp preserve_query(%{query_string: query}, path), do: path <> "?" <> query
end
