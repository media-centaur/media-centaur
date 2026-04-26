defmodule MediaCentarrWeb.AcquisitionRedirectController do
  @moduledoc """
  Backward-compat redirects for routes that moved when manual + auto
  grabs were unified into a single Downloads page (v0.24.0).
  """
  use MediaCentarrWeb, :controller

  def auto_grabs(conn, _params), do: redirect(conn, to: "/download")
end
