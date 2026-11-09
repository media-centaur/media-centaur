defmodule MediaCentaurWeb.Api.FallbackController do
  @moduledoc "Turns a context's `{:error, reason}` into the Local API's one error response."

  use MediaCentaurWeb, :controller

  require MediaCentaur.Log, as: Log

  alias MediaCentaurWeb.ErrorJSON

  def call(conn, {:error, reason}) do
    {status, code, message} = describe(reason)

    if status == 500, do: Log.warning(:acquisition, "local api request failed — #{inspect(reason)}")

    conn |> put_status(status) |> json(ErrorJSON.body(code, message))
  end

  defp describe({:invalid_request, message}), do: {400, :invalid_request, message}
  defp describe(:invalid_syntax), do: {422, :invalid_query, "The query's braces are malformed."}
  defp describe(:not_found), do: {404, :not_found, "Not Found"}

  defp describe({:release_unavailable, guid}),
    do: {404, :release_unavailable, "No search has recorded the release #{guid}. Search again."}

  defp describe(:not_configured),
    do: {503, :not_configured, "The integration this needs is not set up. See GET /api/v1/status."}

  defp describe(:upstream_error), do: {502, :upstream_error, "TMDB did not answer."}
  defp describe(:not_ready), do: {409, :plan_not_ready, "The plan is not in a state that allows this."}

  defp describe(:nothing_to_plan),
    do: {422, :nothing_to_plan, "There is nothing left to download for this."}

  defp describe(:nothing_to_grab), do: {422, :nothing_to_grab, "The plan found no release to download."}

  defp describe({:overlap, _units}),
    do: {409, :already_downloading, "Part of this plan is already being downloaded."}

  defp describe(:not_eligible), do: {409, :not_cancellable, "The pursuit is already over."}
  defp describe(_other), do: {500, :internal_server_error, "The request failed. See the app's console."}
end
