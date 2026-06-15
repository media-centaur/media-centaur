defmodule MediaCentaur.Guide.Library do
  @moduledoc """
  Loads and indexes guide chapters from `priv/guide/*.md` at COMPILE TIME.

  Each markdown file is registered as an `@external_resource`, so editing a
  chapter triggers a recompile (the dev workflow is `recompile` in IEx).
  Parsing at compile time means zero runtime file IO and an immutable index,
  matching the desktop-app rendering defaults.
  """
  alias MediaCentaur.Guide.Chapter

  # Resolve `priv/guide` relative to this source file so the path is stable at
  # compile time (`Application.app_dir/2` is unreliable mid-compile).
  @guide_dir Path.expand(Path.join([__DIR__, "..", "..", "..", "priv", "guide"]))

  paths = Path.wildcard(Path.join(@guide_dir, "*.md"))
  for path <- paths, do: @external_resource(path)

  @chapters paths
            |> Enum.map(fn path ->
              {:ok, chapter} = path |> File.read!() |> Chapter.parse()
              chapter
            end)
            |> Enum.sort_by(& &1.order)

  @by_slug Map.new(@chapters, &{&1.slug, &1})

  @spec chapters() :: [Chapter.t()]
  def chapters, do: @chapters

  @spec fetch(String.t()) :: {:ok, Chapter.t()} | :error
  def fetch(slug), do: Map.fetch(@by_slug, slug)
end
