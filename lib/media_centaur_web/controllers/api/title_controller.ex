defmodule MediaCentaurWeb.Api.TitleController do
  @moduledoc """
  `/api/v1/titles`: finds films and series on TMDB, to plan by id, and
  reads and sets one title's state in the app.
  """

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition.TitleStates
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.Watchlist
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

  def show(conn, params) do
    with {:ok, ref} <- ref(params), do: json(conn, title_state(ref))
  end

  @doc """
  Turns Auto-grab on: the title's releases from now on are planned as they
  come out, as the Watchlist's Grab does. No person acts, so nothing is
  shared with friends, and a series starts caught up on its latest aired
  episode.
  """
  def start_auto_grab(conn, params), do: set_rung(conn, params, :grab)

  @doc "Turns Auto-grab off, leaving the title on the Watchlist at Follow."
  def stop_auto_grab(conn, params), do: set_rung(conn, params, :follow)

  defp set_rung(conn, params, rung) do
    with {:ok, ref} <- ref(params),
         {:ok, title} <- Store.ensure_snapshot(ref),
         {:ok, _intent} <- ReleaseTracking.set_rung(title, rung, nil) do
      json(conn, title_state(ref))
    end
  end

  defp ref(%{"media_type" => media_type, "tmdb_id" => tmdb_id}) do
    with {:ok, media_type} <- Params.media_type(media_type),
         {:ok, tmdb_id} <- Params.path_tmdb_id(tmdb_id) do
      {:ok, {tmdb_id, media_type}}
    end
  end

  defp title_state({tmdb_id, media_type} = ref) do
    state = TitleStates.for_title(ref)

    %{
      tmdb_id: tmdb_id,
      media_type: api_media_type(media_type),
      in_library: Library.ExternalIds.tmdb_owners([ref]) != %{},
      auto_grab: Watchlist.grabs?(tmdb_id, media_type),
      state: state.state,
      plan_ids: state.plan_ids,
      pursuit_ids: state.pursuit_ids
    }
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
