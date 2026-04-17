defmodule MediaCentarr.Credo do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Boundary anchor for the custom Credo checks under
  `MediaCentarr.Credo.Checks.*`. The check modules themselves live in the
  top-level `credo_checks/` directory and are only compiled in `:dev` and
  `:test` (see `elixirc_paths/1` in `mix.exs`) — `:credo` is a dev/test-only
  dependency, so loading them under `MIX_ENV=prod` would fail. Boundary
  checks are disabled for this namespace since these modules don't
  participate in production code paths.
  """
end
