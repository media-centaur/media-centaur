defmodule MediaCentarr.Credo do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Boundary anchor for the custom Credo checks under
  `MediaCentarr.Credo.Checks.*`. These run at static-analysis time only and
  do not participate in production code paths — Boundary checks are disabled
  for this namespace.
  """
end
