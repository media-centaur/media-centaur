defmodule MediaCentaurWeb.Api.StatusController do
  @moduledoc "`GET /api/v1/status`: the running version and which integrations are ready."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Version

  def show(conn, _params) do
    json(conn, %{
      version: Version.current_version(),
      capabilities: %{
        tmdb: Capabilities.tmdb_ready?(),
        prowlarr: Capabilities.prowlarr_ready?(),
        download_client: Capabilities.download_client_ready?(),
        acquisition: Capabilities.acquisition_ready?()
      }
    })
  end
end
