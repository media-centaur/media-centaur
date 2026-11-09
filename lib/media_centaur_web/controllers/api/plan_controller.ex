defmodule MediaCentaurWeb.Api.PlanController do
  @moduledoc "`/api/v1/plans`: has Media Centaur choose releases for a title, and commit them."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaurWeb.Api.{Params, PlanJSON}

  action_fallback MediaCentaurWeb.Api.FallbackController

  def create(conn, params) do
    with {:ok, tmdb_id} <- tmdb_id(params["tmdb_id"]),
         {:ok, media_type} <- media_type(params["media_type"]),
         {:ok, policy} <- Params.approval_policy(params),
         {:ok, scope_opts} <- scope(params["scope"]),
         {:ok, plan} <-
           Plans.create_title_plan_by_id(tmdb_id, media_type, [approval_policy: policy] ++ scope_opts) do
      conn |> put_status(:accepted) |> json(PlanJSON.plan(plan))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, plan} <- Plans.fetch(id), do: json(conn, PlanJSON.plan(plan))
  end

  def approve(conn, %{"id" => id}) do
    with {:ok, plan} <- Plans.fetch(id),
         {:ok, committed} <- Plans.approve(plan) do
      json(conn, PlanJSON.plan(committed))
    end
  end

  def discard(conn, %{"id" => id}) do
    with {:ok, plan} <- Plans.fetch(id),
         {:ok, discarded} <- Plans.discard(plan) do
      json(conn, PlanJSON.plan(discarded))
    end
  end

  defp tmdb_id(id) when is_integer(id) and id > 0, do: {:ok, id}
  defp tmdb_id(_other), do: Params.refuse("tmdb_id must be a positive integer")

  defp media_type("movie"), do: {:ok, :movie}
  defp media_type("tv"), do: {:ok, :tv_series}
  defp media_type(_other), do: Params.refuse("media_type must be movie or tv")

  defp scope(nil), do: {:ok, []}

  defp scope(value) do
    case DownloadScope.parse(value) do
      {:ok, scope} -> {:ok, [scope: scope]}
      :error -> Params.refuse("scope must be first_missing_season, everything or latest_season")
    end
  end
end
