defmodule MediaCentaur.HttpClient.Cache.Freshness do
  @moduledoc """
  Reads how long a response may be served without asking the origin
  again, from its `Cache-Control` header.

  The subset of RFC 9111 this app needs, for a private cache:

    * `no-store` — never stored; `max_age/1` returns `nil`.
    * `max-age=N` — fresh for `N` seconds.
    * `no-cache` — stored, but stale at once (fresh for `0` seconds),
      so every use revalidates with the ETag.
    * Anything else, or no header — not stored; `nil`.

  `private` is honoured as cacheable because this cache serves one
  user. `s-maxage` is for shared caches and is ignored.
  """

  @doc "Freshness lifetime in seconds, or `nil` when the response must not be stored."
  @spec max_age(Req.Response.t()) :: non_neg_integer() | nil
  def max_age(%Req.Response{} = response) do
    directives =
      response
      |> Req.Response.get_header("cache-control")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

    cond do
      "no-store" in directives -> nil
      "no-cache" in directives -> 0
      true -> max_age_directive(directives)
    end
  end

  defp max_age_directive(directives) do
    Enum.find_value(directives, fn
      "max-age=" <> seconds ->
        case Integer.parse(seconds) do
          {value, ""} when value >= 0 -> value
          _ -> nil
        end

      _ ->
        nil
    end)
  end
end
