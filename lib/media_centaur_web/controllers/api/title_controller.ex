defmodule MediaCentaurWeb.Api.TitleController do
  @moduledoc "`GET /api/v1/titles`: finds films and series on TMDB, to plan by id."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Capabilities
  alias MediaCentaur.TMDB.TitleSearch
  alias MediaCentaurWeb.Api.Params

  action_fallback MediaCentaurWeb.Api.FallbackController

  def index(conn, params) do
    with {:ok, query} <- Params.text(params, "q"),
         :ok <- tmdb_ready(),
         {:ok, titles} <- TitleSearch.lookup(query) do
      json(conn, %{titles: Enum.map(titles, &title/1)})
    end
  end

  defp tmdb_ready do
    if Capabilities.tmdb_ready?(), do: :ok, else: {:error, :not_configured}
  end

  defp title(title) do
    %{
      tmdb_id: title.tmdb_id,
      media_type: if(title.media_type == :tv_series, do: :tv, else: :movie),
      name: title.name,
      year: title.year,
      release_date: title.release_date,
      overview: title.overview
    }
  end
end
