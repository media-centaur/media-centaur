defmodule MediaCentaurWeb.Api.Params do
  @moduledoc "Reads and refuses the Local API's request parameters."

  @approval_policies ["automatic", "review"]

  @type refusal :: {:error, {:invalid_request, String.t()}}

  @spec text(map(), String.t()) :: {:ok, String.t()} | refusal()
  def text(params, key) do
    case params[key] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: refuse("#{key} must not be blank"), else: {:ok, value}

      _missing ->
        refuse("#{key} is required")
    end
  end

  @doc "The caller's approval policy; `review` unless asked otherwise."
  @spec approval_policy(map()) :: {:ok, String.t()} | refusal()
  def approval_policy(params) do
    case Map.get(params, "approval_policy", "review") do
      policy when policy in @approval_policies -> {:ok, policy}
      _other -> refuse("approval_policy must be automatic or review")
    end
  end

  @spec refuse(String.t()) :: refusal()
  def refuse(message), do: {:error, {:invalid_request, message}}
end
