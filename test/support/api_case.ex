defmodule MediaCentaurWeb.ApiCase do
  @moduledoc """
  For Local API controller tests: the feature on, a key on the connection,
  and `assert_schema/2`, which holds a response to the published OpenAPI
  document so the document cannot drift from what the API answers.
  """

  use ExUnit.CaseTemplate

  alias MediaCentaur.Features
  alias MediaCentaurWeb.ApiKey

  using opts do
    quote do
      use MediaCentaurWeb.ConnCase, unquote(opts)

      import MediaCentaurWeb.ApiCase

      setup {MediaCentaurWeb.ApiCase, :authorize}
    end
  end

  @doc "Turns the feature on and puts a valid key on the connection."
  def authorize(%{conn: conn}) do
    Features.set(:local_api, true)
    {:ok, conn: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{ApiKey.generate()}")}
  end

  @doc "The published document, decoded."
  def spec, do: "priv/api/openapi.json" |> File.read!() |> JSON.decode!()

  @doc "Fails unless `body` matches the named schema exactly: no missing and no undocumented fields."
  def assert_schema(body, name) do
    spec = spec()

    case violations(body, %{"$ref" => "#/components/schemas/#{name}"}, spec, "$") do
      [] -> body
      found -> ExUnit.Assertions.flunk("response does not match #{name}:\n" <> Enum.join(found, "\n"))
    end
  end

  defp violations(value, %{"$ref" => "#/components/schemas/" <> name}, spec, path),
    do: violations(value, spec["components"]["schemas"][name], spec, path)

  defp violations(value, %{"enum" => allowed} = schema, spec, path) do
    if value in allowed do
      violations(value, Map.delete(schema, "enum"), spec, path)
    else
      ["#{path}: #{inspect(value)} is not one of #{inspect(allowed)}"]
    end
  end

  defp violations(value, %{"oneOf" => branches}, spec, path) do
    if Enum.any?(branches, &(violations(value, &1, spec, path) == [])) do
      []
    else
      branches |> Enum.flat_map(&violations(value, &1, spec, path)) |> Enum.uniq()
    end
  end

  defp violations(value, %{"type" => types} = schema, spec, path) when is_list(types) do
    case Enum.find(types, &type?(value, &1)) do
      nil -> ["#{path}: #{inspect(value)} is none of #{inspect(types)}"]
      "null" -> []
      type -> violations(value, %{schema | "type" => type}, spec, path)
    end
  end

  defp violations(value, %{"type" => "object"} = schema, spec, path) when is_map(value) do
    properties = Map.get(schema, "properties", %{})

    missing =
      for key <- Map.get(schema, "required", []),
          not is_map_key(value, key),
          do: "#{path}.#{key}: missing"

    undocumented =
      for key <- Map.keys(value),
          not is_map_key(properties, key),
          do: "#{path}.#{key}: not in the document"

    nested =
      for {key, item} <- value, is_map_key(properties, key) do
        violations(item, properties[key], spec, "#{path}.#{key}")
      end

    missing ++ undocumented ++ List.flatten(nested)
  end

  defp violations(value, %{"type" => "array", "items" => items}, spec, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> violations(item, items, spec, "#{path}[#{index}]") end)
  end

  defp violations(value, %{"type" => type}, _spec, path) do
    if type?(value, type), do: [], else: ["#{path}: #{inspect(value)} is not #{type}"]
  end

  defp violations(_value, _schema, _spec, _path), do: []

  defp type?(value, "null"), do: is_nil(value)
  defp type?(value, "string"), do: is_binary(value)
  defp type?(value, "integer"), do: is_integer(value)
  defp type?(value, "number"), do: is_number(value)
  defp type?(value, "boolean"), do: is_boolean(value)
  defp type?(value, "object"), do: is_map(value)
  defp type?(value, "array"), do: is_list(value)
end
