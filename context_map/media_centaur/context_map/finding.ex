defmodule MediaCentaur.ContextMap.Finding do
  @moduledoc """
  One crossing the extractor reports. `key/1` is what the verdicts file
  references: rule, schema, field, value, consumer — never the line, so a
  verdict survives an unrelated edit to the consumer file. `concept_key/1`
  is the same key with the consumer segment replaced by `*`: the concept
  `{rule, schema, field, value}` every consumer of it shares.

  `excerpt` is the trimmed source line at `file:line`. R1
  `:owner_never_reads` and R4 findings point at the field's declaration in
  the schema file and carry that declaration.

  `detail` carries rule-specific facts: for R4 the target schema and
  whether the target context is in the owner's deps; for R1 the kind
  (`:owner_never_reads` or `:foreign_write`).
  """

  @enforce_keys [:rule, :owner, :schema, :field, :consumer, :consumer_context, :file, :line, :excerpt]
  defstruct [
    :rule,
    :owner,
    :schema,
    :field,
    :value,
    :consumer,
    :consumer_context,
    :file,
    :line,
    :excerpt,
    :detail,
    surfaces: [],
    anchored?: true
  ]

  @type t :: %__MODULE__{
          rule: String.t(),
          owner: module() | nil,
          schema: module(),
          field: atom(),
          value: atom() | nil,
          consumer: module() | nil,
          consumer_context: module() | :web | nil,
          surfaces: [module()],
          anchored?: boolean(),
          file: String.t(),
          line: pos_integer(),
          excerpt: String.t(),
          detail: map() | nil
        }

  @doc "The stable verdict key: rule, schema, field, value and consumer, joined by `|`."
  @spec key(t()) :: String.t()
  def key(%__MODULE__{} = finding) do
    Enum.map_join(
      [finding.rule, inspect(finding.schema), finding.field, finding.value || "", consumer_key(finding)],
      "|",
      &to_string/1
    )
  end

  @doc "The concept key: `key/1` with the consumer segment replaced by `*`."
  @spec concept_key(t()) :: String.t()
  def concept_key(%__MODULE__{} = finding) do
    finding |> key() |> String.split("|") |> List.replace_at(-1, "*") |> Enum.join("|")
  end

  defp consumer_key(%{rule: "R4", detail: %{target: target}}), do: inspect(target)
  defp consumer_key(%{rule: "R4", detail: %{unresolved: true}}), do: "unresolved"

  defp consumer_key(%{rule: "R1", detail: %{kind: kind}, consumer_context: context}),
    do: "#{kind}:#{inspect(context)}"

  defp consumer_key(%{consumer: consumer}), do: inspect(consumer)
end
