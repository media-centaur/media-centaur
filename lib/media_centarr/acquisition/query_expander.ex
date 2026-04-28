defmodule MediaCentarr.Acquisition.QueryExpander do
  @moduledoc """
  Expands a search query that may contain a brace group into a flat list of
  concrete queries, one per expansion. Pure function module — no I/O, no state.

  Used by the Download page so a single user-typed query like
  `Sample Show S01E{01-10}` becomes ten parallel Prowlarr searches, one for each
  episode.

  ## Supported syntax

  Exactly one brace group per query, in one of two forms:

  * **Flat list** — `{a,b,c}` expands to N items, in order, with each item
    substituted into the surrounding text. Items are taken literally; no
    whitespace trimming. Example:

          iex> QueryExpander.expand("Sample Show S01E{01,02,03}")
          {:ok, ["Sample Show S01E01", "Sample Show S01E02", "Sample Show S01E03"]}

  * **Numeric range** — `{m-n}` where `m` and `n` are non-negative integers
    and `m <= n`. The output width is the width of the **left operand**, so
    leading zeros propagate. Example:

          iex> QueryExpander.expand("E{00-09}")
          {:ok, ["E00", "E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09"]}

          iex> QueryExpander.expand("E{1-3}")
          {:ok, ["E1", "E2", "E3"]}

  A query with no braces is returned as a single-element list:

      iex> QueryExpander.expand("Sample Movie 2049")
      {:ok, ["Sample Movie 2049"]}

  ## Rejected forms — return `{:error, :invalid_syntax}`

  * Empty braces — `{}`
  * Unmatched braces — `{a,b` or `a,b}`
  * Nested braces — `{a{b}c}`
  * More than one brace group — `{a,b}{c,d}`
  * Alphabetic ranges — `{a-c}` (use a flat list instead)
  * Malformed ranges — `{1-}`, `{-9}`, `{9-1}` (descending)
  * Mixed range and list — `{1-3,5}`
  * Negative numbers in ranges

  These restrictions are deliberate — they keep parsing trivial and
  predictable. The two supported forms cover all observed usage from the
  shell tool that this page replaces.
  """

  @type expansion :: {:ok, [String.t()]} | {:error, :invalid_syntax}

  @doc """
  Expands a query containing at most one brace group into a list of concrete
  queries. Returns `{:ok, [query]}` for queries without brace syntax.
  """
  @spec expand(String.t()) :: expansion()
  def expand(query) when is_binary(query) do
    case scan_braces(query) do
      :no_braces ->
        {:ok, [query]}

      {:single, prefix, content, suffix} ->
        with {:ok, parts} <- expand_content(content) do
          {:ok, Enum.map(parts, &(prefix <> &1 <> suffix))}
        end

      :invalid ->
        {:error, :invalid_syntax}
    end
  end

  # ---------------------------------------------------------------------------
  # Brace scanning
  # ---------------------------------------------------------------------------

  # Returns one of:
  #   :no_braces
  #   {:single, prefix, content, suffix}
  #   :invalid
  defp scan_braces(query) do
    chars = String.graphemes(query)
    do_scan(chars, [])
  end

  defp do_scan([], _prefix_rev), do: :no_braces

  defp do_scan(["{" | rest], prefix_rev) do
    do_scan_inside(rest, prefix_rev |> Enum.reverse() |> Enum.join(), [])
  end

  defp do_scan(["}" | _rest], _prefix_rev), do: :invalid

  defp do_scan([char | rest], prefix_rev) do
    do_scan(rest, [char | prefix_rev])
  end

  # Inside a brace group — accumulate until matching close.
  # Reject any nested `{`.
  defp do_scan_inside([], _prefix, _content_rev), do: :invalid
  defp do_scan_inside(["{" | _rest], _prefix, _content_rev), do: :invalid

  defp do_scan_inside(["}" | rest], prefix, content_rev) do
    suffix = Enum.join(rest)

    cond do
      "{" in rest -> :invalid
      "}" in rest -> :invalid
      true -> {:single, prefix, Enum.join(Enum.reverse(content_rev)), suffix}
    end
  end

  defp do_scan_inside([char | rest], prefix, content_rev) do
    do_scan_inside(rest, prefix, [char | content_rev])
  end

  # ---------------------------------------------------------------------------
  # Content expansion
  # ---------------------------------------------------------------------------

  defp expand_content(""), do: {:error, :invalid_syntax}

  defp expand_content(content) do
    cond do
      range?(content) -> expand_range(content)
      # Any `-` that isn't a valid numeric range is reserved syntax — reject.
      String.contains?(content, "-") -> {:error, :invalid_syntax}
      String.contains?(content, ",") -> expand_list(content)
      # Single literal item, no comma, no dash — treat as a one-element list.
      true -> {:ok, [content]}
    end
  end

  defp range?(content) do
    Regex.match?(~r/^\d+-\d+$/, content)
  end

  defp expand_range(content) do
    [left_str, right_str] = String.split(content, "-", parts: 2)
    left = String.to_integer(left_str)
    right = String.to_integer(right_str)
    width = String.length(left_str)

    if left > right do
      {:error, :invalid_syntax}
    else
      results =
        Enum.map(left..right, fn n ->
          n |> Integer.to_string() |> String.pad_leading(width, "0")
        end)

      {:ok, results}
    end
  end

  defp expand_list(content) do
    parts = String.split(content, ",")

    cond do
      Enum.any?(parts, &(&1 == "")) -> {:error, :invalid_syntax}
      Enum.any?(parts, &String.contains?(&1, "-")) -> {:error, :invalid_syntax}
      true -> {:ok, parts}
    end
  end
end
