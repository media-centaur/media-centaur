defmodule MediaCentaurWeb.Api.PlanController do
  @moduledoc "`/api/v1/plans`: has Media Centaur choose releases for a title, and commit them."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaurWeb.Api.{Params, PlanJSON}

  action_fallback MediaCentaurWeb.Api.FallbackController

  def create(conn, params) do
    with {:ok, tmdb_id} <- Params.tmdb_id(params["tmdb_id"]),
         {:ok, media_type} <- Params.media_type(params["media_type"]),
         {:ok, policy} <- Params.approval_policy(params),
         {:ok, scope_opts} <- scope(media_type, params["scope"], params["episodes"]),
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

  def accept_lower_quality(conn, %{"id" => id}) do
    with {:ok, plan} <- Plans.fetch(id),
         {:ok, replanning} <- Plans.accept_lower_quality(plan) do
      conn |> put_status(:accepted) |> json(PlanJSON.plan(replanning))
    end
  end

  def discard(conn, %{"id" => id}) do
    with {:ok, plan} <- Plans.fetch(id),
         {:ok, discarded} <- Plans.discard(plan) do
      json(conn, PlanJSON.plan(discarded))
    end
  end

  defp scope(_media_type, nil, nil), do: {:ok, []}

  defp scope(:movie, _scope, episodes) when not is_nil(episodes),
    do: Params.refuse("episodes applies to a series")

  defp scope(_media_type, scope, episodes) when not is_nil(scope) and not is_nil(episodes),
    do: Params.refuse("send scope or episodes, not both")

  defp scope(_media_type, nil, episodes), do: episodes(episodes)

  defp scope(_media_type, value, nil) do
    case DownloadScope.parse(value) do
      {:ok, scope} -> {:ok, [scope: scope]}
      :error -> Params.refuse("scope must be first_missing_season, everything or latest_season")
    end
  end

  defp episodes([_first | _others] = episodes) do
    if Enum.all?(episodes, &episode?/1) do
      {:ok, [scope: {:episodes, Enum.map(episodes, &{&1["season"], &1["episode"]})}]}
    else
      Params.refuse("each of episodes needs a season, and may name an episode")
    end
  end

  defp episodes(_other), do: Params.refuse("episodes must list at least one season or episode")

  defp episode?(%{"season" => season} = episode) when is_integer(season) and season >= 0 do
    case episode["episode"] do
      nil -> true
      number -> is_integer(number) and number > 0
    end
  end

  defp episode?(_other), do: false
end
