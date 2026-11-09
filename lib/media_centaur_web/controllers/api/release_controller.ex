defmodule MediaCentaurWeb.Api.ReleaseController do
  @moduledoc "`GET /api/v1/releases`: searches the indexers, reporting each expanded term."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition
  alias MediaCentaurWeb.Api.{Params, ReleaseJSON}

  action_fallback MediaCentaurWeb.Api.FallbackController

  def index(conn, params) do
    with {:ok, query} <- Params.text(params, "q"),
         {:ok, outcomes} <- Acquisition.search_terms(query, force: params["refresh"] == "true") do
      json(conn, %{query: query, terms: Enum.map(outcomes, &ReleaseJSON.term/1)})
    end
  end
end
