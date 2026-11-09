defmodule MediaCentaurWeb.Api.TitleController do
  @moduledoc """
  `/api/v1/titles`: finds films and series on TMDB, to plan by id, and
  reads one title's state in the app.
  """

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition.TitleStates
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Library
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

  def show(conn, %{"media_type" => media_type, "tmdb_id" => tmdb_id}) do
    with {:ok, media_type} <- Params.media_type(media_type),
         {:ok, tmdb_id} <- Params.path_tmdb_id(tmdb_id) do
      ref = {tmdb_id, media_type}
      state = TitleStates.for_title(ref)

      json(conn, %{
        tmdb_id: tmdb_id,
        media_type: api_media_type(media_type),
        in_library: Library.ExternalIds.tmdb_owners([ref]) != %{},
        state: state.state,
        plan_ids: state.plan_ids,
        pursuit_ids: state.pursuit_ids
      })
    end
  end

  defp tmdb_ready do
    if Capabilities.tmdb_ready?(), do: :ok, else: {:error, :not_configured}
  end

  defp title(title) do
    %{
      tmdb_id: title.tmdb_id,
      media_type: api_media_type(title.media_type),
      name: title.name,
      year: title.year,
      release_date: title.release_date,
      overview: title.overview
    }
  end

  defp api_media_type(:tv_series), do: :tv
  defp api_media_type(:movie), do: :movie
end
