defmodule MediaCentarr.DateUtil do
  @moduledoc false
  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc """
  Extracts the four-character year prefix from a date string like `"2024-01-15"`.
  Returns `nil` for `nil` or empty input.
  """
  def extract_year(nil), do: nil
  def extract_year(""), do: nil
  def extract_year(<<year::binary-size(4), _rest::binary>>), do: year
end
