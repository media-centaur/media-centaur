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

  @doc "A TMDB id: a positive integer, given as one or as its digits in a path."
  @spec tmdb_id(term()) :: {:ok, pos_integer()} | refusal()
  def tmdb_id(id) when is_integer(id) and id > 0, do: {:ok, id}
  def tmdb_id(_other), do: refuse("tmdb_id must be a positive integer")

  @spec path_tmdb_id(String.t()) :: {:ok, pos_integer()} | refusal()
  def path_tmdb_id(id) do
    case Integer.parse(id) do
      {parsed, ""} -> tmdb_id(parsed)
      _other -> tmdb_id(nil)
    end
  end

  @doc "The API's media type, `movie` or `tv`, as the app's."
  @spec media_type(term()) :: {:ok, :movie | :tv_series} | refusal()
  def media_type("movie"), do: {:ok, :movie}
  def media_type("tv"), do: {:ok, :tv_series}
  def media_type(_other), do: refuse("media_type must be movie or tv")

  @spec refuse(String.t()) :: refusal()
  def refuse(message), do: {:error, {:invalid_request, message}}
end
