defmodule MediaCentaur.Iso8601 do
  @moduledoc """
  Parse a *stored* ISO 8601 datetime string, falling back to `default` on any
  malformed or non-string input.

  Centralises the "trust-but-verify a persisted timestamp" pattern that the
  self-update and capabilities accessors each re-implemented with their own
  `case DateTime.from_iso8601/1`. Those call sites use different fallback
  polarities (`nil`, `now`, `:none`, `{:ok, now}`); this owns the parse, and
  each caller keeps its polarity by choosing `default` or wrapping the result
  (`case parse(iso) do nil -> :none; at -> {:ok, at} end`).
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc """
  Returns the parsed `DateTime` for a valid ISO 8601 string, or `default`
  (which defaults to `nil`) when `iso` is not a binary or doesn't parse.
  """
  @spec parse(term(), default) :: DateTime.t() | default when default: var
  def parse(iso, default \\ nil)

  def parse(iso, default) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> datetime
      _ -> default
    end
  end

  def parse(_iso, default), do: default
end
