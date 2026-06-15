defmodule MediaCentaur.Guide.Chapter do
  @moduledoc """
  A single guide chapter: parsed frontmatter plus the raw markdown body.

  Frontmatter is a small fixed key set (`title`, `part`, `slug`, `order`)
  delimited by `---` lines at the top of the file:

      ---
      title: How identification works
      part: Your library
      slug: how-identification-works
      order: 4
      ---
      <markdown body>

  Parsed by hand to avoid a YAML dependency for four well-controlled keys,
  matching the lean-parser instinct of `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes`.
  """

  @enforce_keys [:title, :part, :slug, :order, :body]
  defstruct [:title, :part, :slug, :order, :body]

  @type t :: %__MODULE__{
          title: String.t(),
          part: String.t(),
          slug: String.t(),
          order: non_neg_integer(),
          body: String.t()
        }

  @required ~w(title part slug order)

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    with {:ok, fm_block, body} <- split(raw),
         {:ok, fields} <- parse_fields(fm_block) do
      {:ok,
       %__MODULE__{
         title: fields["title"],
         part: fields["part"],
         slug: fields["slug"],
         order: String.to_integer(fields["order"]),
         body: String.trim(body)
       }}
    end
  end

  # Leading `---\n`, then frontmatter, then `\n---\n`, then the body.
  defp split("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [fm, body] -> {:ok, fm, body}
      _ -> {:error, :missing_frontmatter}
    end
  end

  defp split(_), do: {:error, :missing_frontmatter}

  defp parse_fields(block) do
    fields =
      block
      |> String.split("\n", trim: true)
      |> Map.new(fn line ->
        [k, v] = String.split(line, ":", parts: 2)
        {String.trim(k), String.trim(v)}
      end)

    case @required -- Map.keys(fields) do
      [] -> {:ok, fields}
      missing -> {:error, {:missing_keys, missing}}
    end
  end
end
