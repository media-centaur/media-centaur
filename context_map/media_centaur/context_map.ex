defmodule MediaCentaur.ContextMap do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The context map: every Ecto schema by owning bounded context, and every
  crossing of a context boundary at the data level. Dev/test only — the
  `context_map/` directory is compiled by `elixirc_paths/1` for `:dev` and
  `:test`, like `credo_checks/`, and nothing under `lib/` references it.

  Design: `docs/superpowers/specs/2026-09-30-context-map-design.md`.
  Entry point: `mix context_map`.
  """

  @doc "Builds the whole document as a map ready for `Jason.encode!/2`."
  @spec build() :: map()
  def build do
    %{contexts: [], findings: [], kernel_reads: []}
  end
end
