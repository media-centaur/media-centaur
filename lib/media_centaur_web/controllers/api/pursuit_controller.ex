defmodule MediaCentaurWeb.Api.PursuitController do
  @moduledoc "`/api/v1/pursuits`: follows downloads through to import, and stops or retries them."

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaurWeb.Api.{Params, PlanJSON, PursuitJSON}

  action_fallback MediaCentaurWeb.Api.FallbackController

  @filters %{
    "active" => :active,
    "failed" => :failed,
    "cancelled" => :cancelled,
    "succeeded" => :succeeded,
    "terminal" => :all_terminal
  }
  @default_limit 50
  @max_limit 200

  def index(conn, params) do
    with {:ok, filter} <- filter(Map.get(params, "state", "active")),
         {:ok, limit} <- limit(params["limit"]) do
      json(conn, %{pursuits: filter |> Pursuits.list_rows(limit: limit) |> Enum.map(&PursuitJSON.row/1)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, pursuit} <- Pursuits.fetch(id) do
      json(conn, pursuit |> Pursuits.status_from() |> PursuitJSON.detail())
    end
  end

  def search_again(conn, %{"id" => id} = params) do
    with {:ok, policy} <- Params.approval_policy(params),
         {:ok, pursuit} <- Pursuits.fetch(id),
         {:ok, plan} <- Plans.search_again(pursuit.id, approval_policy: policy) do
      conn |> put_status(:accepted) |> json(PlanJSON.plan(plan))
    end
  end

  def cancel(conn, %{"id" => id}) do
    with {:ok, pursuit} <- Acquisition.cancel_pursuit(id), do: json(conn, PursuitJSON.summary(pursuit))
  end

  defp filter(value) do
    case @filters do
      %{^value => filter} -> {:ok, filter}
      _unknown -> Params.refuse("state must be one of #{@filters |> Map.keys() |> Enum.join(", ")}")
    end
  end

  defp limit(nil), do: {:ok, @default_limit}

  defp limit(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..@max_limit -> {:ok, limit}
      _other -> Params.refuse("limit must be between 1 and #{@max_limit}")
    end
  end
end
