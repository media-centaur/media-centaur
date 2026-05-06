defmodule MediaCentarrWeb.StorybookCompileTest do
  @moduledoc """
  Compile smoke for every storybook file. Closes the gap that `mix compile`
  doesn't cover: Phoenix Storybook compiles `.story.exs` and `_*.index.exs`
  files **lazily on dev page-load**, so a story with a typo or stale alias
  silently breaks until someone opens its catalog page.

  This test compiles each file in isolation and fails with the file path
  plus the underlying reason on the first compile error. One test per
  file, generated at module-compile time, so a single broken story
  doesn't mask the rest.

  Runs as part of `mix test` → `mix precommit`. ~5s for ~50 files.
  """

  use ExUnit.Case, async: false

  story_files =
    Path.wildcard("storybook/**/*.story.exs") ++
      Path.wildcard("storybook/**/_*.index.exs")

  if story_files == [] do
    raise "StorybookCompileTest: no story files found — wildcard is wrong"
  end

  for path <- story_files do
    @tag path: path
    test "compiles: #{path}" do
      relative = unquote(path)

      try do
        Code.compile_file(relative)
      rescue
        error ->
          flunk("""
          Failed to compile #{relative}:

          #{Exception.message(error)}
          """)
      end
    end
  end
end
