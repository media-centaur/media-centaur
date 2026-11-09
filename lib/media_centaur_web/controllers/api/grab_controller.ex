defmodule MediaCentaurWeb.Api.GrabController do
  @moduledoc "`POST /api/v1/grabs`: sends releases a search found to the download client."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition
  alias MediaCentaurWeb.Api.Params

  action_fallback MediaCentaurWeb.Api.FallbackController

  def create(conn, params) do
    with {:ok, query} <- Params.text(params, "query"),
         {:ok, picks} <- picks(params["releases"]),
         {:ok, [first | _others] = targets} <- Acquisition.grab_releases(picks, query) do
      conn
      |> put_status(:accepted)
      |> json(%{pursuit_id: first.pursuit_id, grabs: Enum.map(targets, &grab/1)})
    end
  end

  defp picks([_first | _others] = releases) do
    if Enum.all?(releases, &pick?/1) do
      {:ok, Enum.map(releases, &%{guid: &1["guid"], term: &1["term"]})}
    else
      Params.refuse("each release needs a guid and a term")
    end
  end

  defp picks(_empty_or_missing), do: Params.refuse("releases must list at least one release")

  defp pick?(%{"guid" => guid, "term" => term}) when is_binary(guid) and is_binary(term), do: true
  defp pick?(_other), do: false

  defp grab(target),
    do: %{guid: target.prowlarr_guid, title: target.release_title, status: target.status}
end
